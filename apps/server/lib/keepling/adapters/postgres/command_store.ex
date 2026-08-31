defmodule Keepling.Adapters.Postgres.CommandStore do
  @moduledoc """
  PostgreSQL interpreter for semantic commands and stable command results.

  The account-scoped receipt uniqueness constraint arbitrates first delivery.
  Accepted task, activity, and terminal acknowledgement commit together.
  """

  @behaviour Keepling.Application.Commands.Port

  alias Ecto.Adapters.SQL
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
           SELECT id, title, inbox_state, revision, captured_at
           FROM tasks
           WHERE account_id = $1 AND inbox_state = 'inbox'
           ORDER BY captured_at DESC, id ASC
           """,
           [account_id]
         ) do
      {:ok, %{rows: rows}} -> {:ok, Enum.map(rows, &task_from_row/1)}
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
      case decide.(accepted_command) do
        {:ok, task, activity} -> persist_capture(repo, command, context, task, activity)
        {:error, reason} -> semantic_rejection(reason)
      end

    finalize_receipt(repo, context.account_id, command.mutation_id, result)
    {:ok, result}
  end

  defp persist_capture(repo, command, context, task, activity) do
    inserted_task =
      SQL.query!(
        repo,
        """
        INSERT INTO tasks (
          account_id, id, title, inbox_state, revision, captured_at, inserted_at, updated_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $6, $6)
        ON CONFLICT (account_id, id) DO NOTHING
        RETURNING id, title, inbox_state, revision, captured_at
        """,
        [
          context.account_id,
          dump_uuid(task.id),
          task.title,
          Atom.to_string(task.inbox_state),
          task.revision,
          task.captured_at
        ]
      )

    case inserted_task.rows do
      [row] ->
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
            dump_uuid(task.id),
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

        task_body = task_from_row(row)

        %{
          status: 201,
          body: %{
            "mutation_id" => command.mutation_id,
            "outcome" => "accepted",
            "revision" => task.revision,
            "snapshot" => task_body,
            "task_id" => task.id,
            "warnings" => []
          }
        }

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

  defp semantic_rejection(:title_required) do
    problem(
      422,
      "title_required",
      "Task title required",
      "Enter a task title before adding it.",
      false,
      "edit_title"
    )
  end

  defp semantic_rejection(:title_too_long) do
    problem(
      422,
      "title_too_long",
      "Task title too long",
      "Shorten the task title to 512 characters or fewer.",
      false,
      "edit_title"
    )
  end

  defp problem(status, code, title, detail, retryable, recovery_action) do
    %{
      status: status,
      body: %{
        "code" => code,
        "detail" => detail,
        "recovery_action" => recovery_action,
        "retryable" => retryable,
        "status" => status,
        "title" => title,
        "type" => "/problems/#{code}"
      }
    }
  end

  defp task_from_row([id, title, inbox_state, revision, captured_at]) do
    %{
      "captured_at" => utc_iso8601(captured_at),
      "id" => load_uuid(id),
      "inbox_state" => inbox_state,
      "revision" => revision,
      "title" => title
    }
  end

  defp fingerprint(%{type: :capture_task} = command) do
    {:capture_task, command.version, command.task_id, String.trim(command.title)}
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
  end

  defp dump_uuid(uuid), do: Ecto.UUID.dump!(uuid)
  defp load_uuid(uuid), do: Ecto.UUID.load!(uuid)

  defp utc_iso8601(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp utc_iso8601(%NaiveDateTime{} = value) do
    value |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()
  end
end
