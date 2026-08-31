defmodule Keepling.Adapters.Postgres.CommandStore do
  @moduledoc """
  PostgreSQL interpreter for semantic commands and stable command results.

  The account-scoped receipt uniqueness constraint arbitrates first delivery.
  Accepted task, activity, and terminal acknowledgement commit together.
  """

  @behaviour Keepling.Application.Commands.Port

  alias Ecto.Adapters.SQL
  alias Keepling.Domain.Task
  alias Keepling.Repo

  @impl true
  def execute(command, context, decide) do
    fingerprint = fingerprint(command)

    case Repo.transact(fn repo ->
           {:ok, first_delivery_or_replay(repo, command, context, fingerprint, decide)}
         end) do
      {:ok, result} -> result
      {:error, _reason} -> {:error, :infrastructure_failure}
    end
  rescue
    _error in [DBConnection.ConnectionError, Postgrex.Error] ->
      {:error, :infrastructure_failure}
  end

  @impl true
  def list_inbox(%{account_id: account_id}) do
    case SQL.query(
           Repo,
           """
           SELECT id, title, notes, inbox_state, revision, captured_at
           FROM tasks
           WHERE account_id = $1 AND inbox_state = 'inbox'
           ORDER BY captured_at DESC, id ASC
           """,
           [account_id]
         ) do
      {:ok, %{rows: rows}} -> {:ok, Enum.map(rows, &task_body_from_row/1)}
      {:error, _reason} -> {:error, :infrastructure_failure}
    end
  end

  @impl true
  def lookup_result(%{account_id: account_id}, mutation_id) do
    case SQL.query(
           Repo,
           """
           SELECT response_status, response
           FROM command_receipts
           WHERE account_id = $1 AND mutation_id = $2 AND terminal = TRUE
           """,
           [account_id, dump_uuid(mutation_id)]
         ) do
      {:ok, %{rows: [[status, response]]}} -> {:ok, %{status: status, body: response}}
      {:ok, %{rows: []}} -> {:error, :not_found}
      {:error, _reason} -> {:error, :infrastructure_failure}
    end
  end

  defp first_delivery_or_replay(repo, command, context, fingerprint, decide) do
    inserted =
      SQL.query!(
        repo,
        """
        INSERT INTO command_receipts (
          account_id, mutation_id, fingerprint, terminal, inserted_at, updated_at
        )
        VALUES ($1, $2, $3, FALSE, $4, $4)
        ON CONFLICT (account_id, mutation_id) DO NOTHING
        RETURNING mutation_id
        """,
        [context.account_id, dump_uuid(command.mutation_id), fingerprint, context.accepted_at]
      )

    case inserted.rows do
      [[_mutation_id]] -> execute_first_delivery(repo, command, context, decide)
      [] -> replay(repo, command, context, fingerprint)
    end
  end

  defp execute_first_delivery(repo, command, context, decide) do
    accepted_command = Map.put(command, :accepted_at, context.accepted_at)

    result =
      case command.type do
        :capture_task ->
          case decide.(accepted_command) do
            {:ok, task, activity} -> persist_capture(repo, command, context, task, activity)
            {:error, reason} -> semantic_rejection(reason)
          end

        _existing_task_command ->
          case lock_task(repo, context.account_id, command.task_id) do
            nil -> task_not_found()
            current -> decide_existing(repo, command, context, current, accepted_command, decide)
          end
      end

    finalize_receipt(repo, context.account_id, command.mutation_id, result)
    {:ok, result}
  end

  defp decide_existing(repo, command, context, current, accepted_command, decide) do
    case decide.(current, accepted_command) do
      {:ok, task, nil, :already_satisfied} ->
        acknowledgement(command, task, :already_satisfied)

      {:ok, task, activity, :accepted} ->
        persist_existing(repo, command, context, task, activity)

      {:error, reason} ->
        semantic_rejection(reason, current)
    end
  end

  defp lock_task(repo, account_id, task_id) do
    case SQL.query!(
           repo,
           """
           SELECT id, title, notes, inbox_state, revision, captured_at
           FROM tasks
           WHERE account_id = $1 AND id = $2
           FOR UPDATE
           """,
           [account_id, dump_uuid(task_id)]
         ).rows do
      [row] -> task_from_row(row)
      [] -> nil
    end
  end

  defp persist_capture(repo, command, context, task, activity) do
    inserted_task =
      SQL.query!(
        repo,
        """
        INSERT INTO tasks (
          account_id, id, title, notes, inbox_state, revision, captured_at, inserted_at, updated_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $7, $7)
        ON CONFLICT (account_id, id) DO NOTHING
        RETURNING id, title, notes, inbox_state, revision, captured_at
        """,
        [
          context.account_id,
          dump_uuid(task.id),
          task.title,
          task.notes,
          Atom.to_string(task.inbox_state),
          task.revision,
          task.captured_at
        ]
      )

    case inserted_task.rows do
      [row] ->
        persist_activity(repo, command, context, activity)
        acknowledgement(command, task_from_row(row), :accepted, 201)

      [] ->
        problem(
          409,
          "task_identity_reused",
          "Task identity already used",
          "Use a new task identity for a different capture.",
          false,
          "create_new_task_identity"
        )
    end
  end

  defp persist_existing(repo, command, context, task, activity) do
    %{num_rows: 1} =
      SQL.query!(
        repo,
        """
        UPDATE tasks
        SET title = $3, notes = $4, inbox_state = $5, revision = $6, updated_at = $7
        WHERE account_id = $1 AND id = $2
        """,
        [
          context.account_id,
          dump_uuid(task.id),
          task.title,
          task.notes,
          Atom.to_string(task.inbox_state),
          task.revision,
          context.accepted_at
        ]
      )

    persist_activity(repo, command, context, activity)
    acknowledgement(command, task, :accepted)
  end

  defp persist_activity(repo, command, context, activity) do
    SQL.query!(
      repo,
      """
      INSERT INTO task_activities (
        account_id, task_id, mutation_id, activity_type, activity_version,
        actor_type, client_kind, from_revision, to_revision, changed_fields,
        accepted_at, inserted_at
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10::jsonb, $11, $11)
      """,
      [
        context.account_id,
        dump_uuid(command.task_id),
        dump_uuid(command.mutation_id),
        Atom.to_string(activity.type),
        activity.version,
        context.actor_type,
        context.client_kind,
        activity.from_revision,
        activity.to_revision,
        activity.changed_fields,
        activity.accepted_at
      ]
    )
  end

  defp acknowledgement(command, task, outcome, status \\ 200) do
    %{
      status: status,
      body: %{
        "mutation_id" => command.mutation_id,
        "outcome" => Atom.to_string(outcome),
        "revision" => task.revision,
        "snapshot" => task_body(task),
        "task_id" => task.id,
        "warnings" => []
      }
    }
  end

  defp finalize_receipt(repo, account_id, mutation_id, result) do
    SQL.query!(
      repo,
      """
      UPDATE command_receipts
      SET response_status = $3, response = $4::jsonb, terminal = TRUE, updated_at = NOW()
      WHERE account_id = $1 AND mutation_id = $2
      """,
      [account_id, dump_uuid(mutation_id), result.status, result.body]
    )
  end

  defp replay(repo, command, context, fingerprint) do
    %{rows: [[stored_fingerprint, status, response]]} =
      SQL.query!(
        repo,
        """
        SELECT fingerprint, response_status, response
        FROM command_receipts
        WHERE account_id = $1 AND mutation_id = $2 AND terminal = TRUE
        """,
        [context.account_id, dump_uuid(command.mutation_id)]
      )

    if Plug.Crypto.secure_compare(stored_fingerprint, fingerprint) do
      {:ok, %{status: status, body: response}}
    else
      {:ok,
       problem(
         409,
         "mutation_identity_reused",
         "Mutation identity already used",
         "Retry only the original command with this mutation identity.",
         false,
         "use_original_command"
       )}
    end
  end

  defp semantic_rejection(:title_required),
    do:
      problem(
        422,
        "title_required",
        "Task title required",
        "Enter a task title.",
        false,
        "edit_title"
      )

  defp semantic_rejection(:title_too_long),
    do:
      problem(
        422,
        "title_too_long",
        "Task title too long",
        "Shorten the task title to 512 characters or fewer.",
        false,
        "edit_title"
      )

  defp semantic_rejection(reason), do: semantic_rejection(reason, nil)

  defp semantic_rejection(:notes_too_long, _current),
    do:
      problem(
        422,
        "notes_too_long",
        "Task notes too long",
        "Shorten the notes to 50000 characters or fewer.",
        false,
        "edit_notes"
      )

  defp semantic_rejection(:no_fields_touched, _current),
    do:
      problem(
        422,
        "no_fields_touched",
        "No task details changed",
        "Send at least one changed title or notes field.",
        false,
        "edit_task"
      )

  defp semantic_rejection({:edit_conflict, affected_fields}, current) do
    problem(
      409,
      "task_edit_conflict",
      "Task changed elsewhere",
      "Review the affected fields before saving again.",
      false,
      "review_task_conflict",
      %{
        "affected_fields" => affected_fields,
        "current_revision" => current.revision
      }
    )
  end

  defp semantic_rejection(_reason, _current),
    do:
      problem(
        422,
        "invalid_task_details",
        "Invalid task details",
        "Send matching touched fields and base values.",
        false,
        "edit_task"
      )

  defp task_not_found do
    problem(
      404,
      "task_not_found",
      "Task not found",
      "Refresh the view before trying again.",
      false,
      "refresh_view"
    )
  end

  defp problem(status, code, title, detail, retryable, recovery_action, extensions \\ %{}) do
    body = %{
      "code" => code,
      "detail" => detail,
      "recovery_action" => recovery_action,
      "retryable" => retryable,
      "status" => status,
      "title" => title,
      "type" => "/problems/#{code}"
    }

    %{status: status, body: Map.merge(body, extensions)}
  end

  defp task_from_row([id, title, notes, inbox_state, revision, captured_at]) do
    %Task{
      id: load_uuid(id),
      title: title,
      notes: notes,
      inbox_state: String.to_existing_atom(inbox_state),
      revision: revision,
      captured_at: to_datetime(captured_at)
    }
  end

  defp task_body_from_row(row), do: row |> task_from_row() |> task_body()

  defp task_body(task) do
    %{
      "captured_at" => utc_iso8601(task.captured_at),
      "id" => task.id,
      "inbox_state" => Atom.to_string(task.inbox_state),
      "notes" => task.notes,
      "revision" => task.revision,
      "title" => task.title
    }
  end

  defp fingerprint(command) do
    command
    |> canonical_command()
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
  end

  defp canonical_command(%{type: :capture_task} = command),
    do: %{command | title: String.trim(command.title)}

  defp canonical_command(%{fields: fields, base_values: base_values} = command) do
    command
    |> Map.put(:fields, canonical_detail_map(fields))
    |> Map.put(:base_values, canonical_detail_map(base_values))
  end

  defp canonical_command(command), do: command

  defp canonical_detail_map(details) do
    case Map.fetch(details, :title) do
      {:ok, title} -> Map.put(details, :title, String.trim(title))
      :error -> details
    end
  end

  defp dump_uuid(uuid), do: Ecto.UUID.dump!(uuid)
  defp load_uuid(uuid), do: Ecto.UUID.load!(uuid)
  defp to_datetime(%DateTime{} = value), do: value
  defp to_datetime(%NaiveDateTime{} = value), do: DateTime.from_naive!(value, "Etc/UTC")
  defp utc_iso8601(value), do: value |> to_datetime() |> DateTime.to_iso8601()
end
