defmodule Keepling.Adapters.Postgres.CommandStore do
  @moduledoc """
  PostgreSQL interpreter for semantic commands and stable command results.

  The account-scoped receipt uniqueness constraint arbitrates first delivery.
  Accepted task, activity, and terminal acknowledgement commit together.
  """

  @behaviour Keepling.Application.Commands.Port

  alias Ecto.Adapters.SQL
  alias Keepling.Adapters.Postgres.SyncFeed
  alias Keepling.Application.{Activity, Undo}
  alias Keepling.Domain.{Organization, Task, TaskDates}
  alias Keepling.Repo

  @behaviour Activity.Port
  @behaviour Undo.Port

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

  @impl Undo.Port
  def execute_undo(command, context, apply_inverse) do
    fingerprint = fingerprint(command)

    case Repo.transact(fn repo ->
           {:ok,
            first_undo_delivery_or_replay(
              repo,
              command,
              context,
              fingerprint,
              apply_inverse
            )}
         end) do
      {:ok, result} -> result
      {:error, _reason} -> {:error, :infrastructure_failure}
    end
  rescue
    _error in [DBConnection.ConnectionError, Postgrex.Error] ->
      {:error, :infrastructure_failure}
  end

  @impl true
  def get_task(%{account_id: account_id}, task_id) do
    case SQL.query(
           Repo,
           """
           SELECT id, title, notes, inbox_state, revision, captured_at,
                  planned_on, deadline_on, completed_at, trashed_at
           FROM tasks
           WHERE account_id = $1 AND id = $2 AND trashed_at IS NULL
           """,
           [account_id, Ecto.UUID.dump!(task_id)]
         ) do
      {:ok, %{rows: [row]}} ->
        {:ok, task_body_from_row(row, account_id, Repo)}

      {:ok, %{rows: []}} ->
        {:error, :not_found}

      {:error, _reason} ->
        {:error, :infrastructure_failure}
    end
  end

  @impl true
  def list_inbox(%{account_id: account_id}) do
    case SQL.query(
           Repo,
           """
           SELECT id, title, notes, inbox_state, revision, captured_at,
                  planned_on, deadline_on, completed_at, trashed_at
           FROM tasks
           WHERE account_id = $1 AND inbox_state = 'inbox'
             AND completed_at IS NULL AND trashed_at IS NULL
           ORDER BY captured_at DESC, id ASC
           """,
           [account_id]
         ) do
      {:ok, %{rows: rows}} ->
        {:ok, Enum.map(rows, &task_body_from_row(&1, account_id, Repo))}

      {:error, _reason} ->
        {:error, :infrastructure_failure}
    end
  end

  @impl true
  def list_trash(%{account_id: account_id}) do
    case SQL.query(
           Repo,
           """
           SELECT id, title, notes, inbox_state, revision, captured_at,
                  planned_on, deadline_on, completed_at, trashed_at
           FROM tasks
           WHERE account_id = $1 AND trashed_at IS NOT NULL
           ORDER BY trashed_at DESC, id DESC
           """,
           [account_id]
         ) do
      {:ok, %{rows: rows}} ->
        {:ok, Enum.map(rows, &task_body_from_row(&1, account_id, Repo))}

      {:error, _reason} ->
        {:error, :infrastructure_failure}
    end
  end

  @impl true
  def list_organizations(%{account_id: account_id}) do
    case SQL.query(
           Repo,
           """
           SELECT id, kind, display_name, name_key, name_key_version, archived_at, revision
           FROM organizations
           WHERE account_id = $1
           ORDER BY kind ASC, archived_at NULLS FIRST, display_name ASC, id ASC
           """,
           [account_id]
         ) do
      {:ok, %{rows: rows}} ->
        {:ok, Enum.map(rows, &organization_body_from_row/1)}

      {:error, _reason} ->
        {:error, :infrastructure_failure}
    end
  end

  @impl Activity.Port
  def list_task_activity(%{account_id: account_id}, task_id, options) do
    case Repo.transact(fn repo ->
           with {:ok, account_timezone, view_revision} <-
                  activity_scope(repo, account_id, task_id),
                :ok <- cursor_revision(options.cursor, view_revision),
                {:ok, facts, next_keyset} <-
                  activity_page(
                    repo,
                    account_id,
                    task_id,
                    options.cursor,
                    options.limit
                  ) do
             {:ok,
              %{
                account_timezone: account_timezone,
                facts: facts,
                next_keyset: next_keyset,
                view_revision: view_revision
              }}
           else
             {:error, reason} -> Repo.rollback(reason)
           end
         end) do
      {:ok, page} ->
        {:ok, page}

      {:error, reason} when reason in [:infrastructure_failure, :not_found, :stale_cursor] ->
        {:error, reason}

      {:error, _reason} ->
        {:error, :infrastructure_failure}
    end
  rescue
    _error in [DBConnection.ConnectionError, Postgrex.Error] ->
      {:error, :infrastructure_failure}
  end

  @impl true
  def lookup_result(%{account_id: account_id} = context, mutation_id) do
    case SQL.query(
           Repo,
           """
           SELECT response_status, response
           FROM command_receipts
           WHERE account_id = $1 AND mutation_id = $2 AND terminal = TRUE
           """,
           [account_id, dump_uuid(mutation_id)]
         ) do
      {:ok, %{rows: [[status, response]]}} ->
        {:ok,
         attach_replay_undo(
           Repo,
           account_id,
           mutation_id,
           %{status: status, body: response},
           Map.get(context, :accepted_at, DateTime.utc_now())
         )}

      {:ok, %{rows: []}} ->
        {:error, :not_found}

      {:error, _reason} ->
        {:error, :infrastructure_failure}
    end
  end

  defp activity_scope(repo, account_id, task_id) do
    case SQL.query(
           repo,
           """
           SELECT accounts.timezone, accounts.activity_view_revision
           FROM tasks
           JOIN accounts ON accounts.id = tasks.account_id
           WHERE tasks.account_id = $1 AND tasks.id = $2
           FOR SHARE OF accounts
           """,
           [account_id, dump_uuid(task_id)]
         ) do
      {:ok, %{rows: [[timezone, view_revision]]}} ->
        {:ok, timezone, view_revision}

      {:ok, %{rows: []}} ->
        {:error, :not_found}

      {:error, _reason} ->
        {:error, :infrastructure_failure}
    end
  end

  defp cursor_revision(nil, _view_revision), do: :ok

  defp cursor_revision(%{view_revision: view_revision}, view_revision), do: :ok

  defp cursor_revision(_cursor, _view_revision), do: {:error, :stale_cursor}

  defp activity_page(repo, account_id, task_id, cursor, limit) do
    {keyset_sql, keyset_params} =
      case cursor do
        nil ->
          {"", []}

        %{accepted_at: accepted_at, activity_id: activity_id} ->
          {"AND (accepted_at, id) < ($3, $4)", [accepted_at, activity_id]}
      end

    query =
      """
      SELECT id, mutation_id, activity_type, activity_version,
             actor_type, actor_principal, actor_label, client_kind,
             from_revision, to_revision, changed_fields, recovery_state,
             undone_activity_id, accepted_at
      FROM task_activities
      WHERE account_id = $1 AND task_id = $2
      #{keyset_sql}
      ORDER BY accepted_at DESC, id DESC
      LIMIT $#{3 + length(keyset_params)}
      """

    params =
      [account_id, dump_uuid(task_id)] ++ keyset_params ++ [limit + 1]

    case SQL.query(repo, query, params) do
      {:ok, %{rows: rows}} ->
        {page_rows, extra_rows} = Enum.split(rows, limit)
        organization_references = activity_organization_references(repo, account_id, page_rows)
        facts = Enum.map(page_rows, &activity_fact(&1, organization_references))

        next_keyset =
          case {page_rows, extra_rows} do
            {[], _extra} -> nil
            {_page, []} -> nil
            {_page, [_extra | _rest]} -> page_rows |> List.last() |> activity_keyset()
          end

        {:ok, facts, next_keyset}

      {:error, _reason} ->
        {:error, :infrastructure_failure}
    end
  end

  defp activity_fact(
         [
           id,
           mutation_id,
           activity_type,
           activity_version,
           actor_type,
           actor_principal,
           actor_label,
           client_kind,
           from_revision,
           to_revision,
           changed_fields,
           recovery_state,
           undone_activity_id,
           accepted_at
         ],
         organization_references
       ) do
    %{
      accepted_at: to_datetime(accepted_at),
      activity_id: id,
      actor_label: actor_label,
      actor_principal: actor_principal,
      actor_type: actor_type,
      changed_fields: changed_fields,
      client_kind: client_kind,
      from_revision: from_revision,
      mutation_id: load_uuid(mutation_id),
      organization_references: organization_references,
      recovery_state: recovery_state,
      to_revision: to_revision,
      type: activity_type,
      undone_activity_id: undone_activity_id,
      version: activity_version
    }
  end

  defp activity_keyset([id | row_tail]) do
    %{accepted_at: row_tail |> List.last() |> to_datetime(), activity_id: id}
  end

  defp activity_organization_references(repo, account_id, rows) do
    ids =
      rows
      |> Enum.flat_map(fn row -> row |> Enum.at(10) |> activity_organization_ids() end)
      |> Enum.uniq()

    if ids == [] do
      %{}
    else
      SQL.query!(
        repo,
        """
        SELECT id, display_name, archived_at
        FROM organizations
        WHERE account_id = $1 AND id = ANY($2::uuid[])
        """,
        [account_id, Enum.map(ids, &dump_uuid/1)]
      ).rows
      |> Map.new(fn row ->
        reference = organization_reference(row)
        {reference["id"], reference}
      end)
    end
  end

  defp activity_organization_ids(changed_fields) do
    project_ids =
      changed_fields
      |> Map.get("project_id", %{})
      |> Map.take(["from", "to"])
      |> Map.values()
      |> Enum.reject(&is_nil/1)

    tag_ids =
      changed_fields
      |> Map.get("tag_ids", %{})
      |> Map.take(["from", "to"])
      |> Map.values()
      |> Enum.flat_map(fn
        ids when is_list(ids) -> ids
        _other -> []
      end)

    project_ids ++ tag_ids
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
      [[_mutation_id]] ->
        {:ok, sequence} = SyncFeed.reserve_sequence(repo, context.account_id, context.accepted_at)
        execute_first_delivery(repo, command, context, decide, sequence)

      [] ->
        replay(repo, command, context, fingerprint)
    end
  end

  defp first_undo_delivery_or_replay(repo, command, context, fingerprint, apply_inverse) do
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
      [[_mutation_id]] ->
        {:ok, sequence} = SyncFeed.reserve_sequence(repo, context.account_id, context.accepted_at)
        result = apply_undo_delivery(repo, command, context, apply_inverse)

        :ok =
          SyncFeed.append_terminal(
            repo,
            context.account_id,
            sequence,
            command,
            result,
            context.accepted_at
          )

        finalize_receipt(repo, context.account_id, command.mutation_id, result)
        {:ok, public_result(result)}

      [] ->
        replay(repo, command, context, fingerprint)
    end
  end

  defp execute_first_delivery(repo, command, context, decide, sequence) do
    accepted_command =
      command
      |> Map.put(:accepted_at, context.accepted_at)
      |> maybe_put_account_timezone(repo, context)

    result =
      case command.type do
        :capture_task ->
          case decide.(accepted_command) do
            {:ok, task, activity} -> persist_capture(repo, command, context, task, activity)
            {:error, reason} -> semantic_rejection(reason)
          end

        :create_organization ->
          execute_create_organization(repo, command, context, accepted_command, decide)

        type
        when type in [:rename_organization, :archive_organization, :unarchive_organization] ->
          execute_existing_organization(repo, command, context, accepted_command, decide)

        :assign_task_organizations ->
          execute_task_assignment(repo, command, context, accepted_command, decide)

        :resolve_task_conflict ->
          execute_conflict_resolution(repo, command, context, accepted_command, decide)

        _existing_task_command ->
          case lock_task(repo, context.account_id, command.task_id) do
            nil ->
              task_not_found()

            current ->
              decide_existing(repo, accepted_command, context, current, accepted_command, decide)
          end
      end

    :ok =
      SyncFeed.append_terminal(
        repo,
        context.account_id,
        sequence,
        command,
        result,
        context.accepted_at
      )

    finalize_receipt(repo, context.account_id, command.mutation_id, result)
    {:ok, public_result(result)}
  end

  defp apply_undo_delivery(repo, command, context, apply_inverse) do
    handle_hash = :crypto.hash(:sha256, command.handle)

    case lock_undo_handle(repo, context.account_id, handle_hash) do
      nil ->
        undo_no_change(command, :unknown, "undo_unknown", "Undo unavailable", false, nil)

      %{state: "applied"} ->
        undo_no_change(
          command,
          :already_applied,
          "undo_already_applied",
          "Already undone",
          false,
          nil
        )

      %{state: "expired"} ->
        undo_no_change(command, :expired, "undo_expired", "Undo expired", false, nil)

      %{state: "stale"} ->
        undo_no_change(
          command,
          :stale,
          "undo_stale",
          "Task changed after this action",
          false,
          "review_latest_task"
        )

      handle ->
        cond do
          DateTime.compare(context.accepted_at, handle.expires_at) == :gt ->
            mark_undo_unavailable(repo, handle, context, "expired")
            undo_no_change(command, :expired, "undo_expired", "Undo expired", false, nil)

          true ->
            apply_available_undo(repo, command, context, handle, apply_inverse)
        end
    end
  end

  defp apply_available_undo(repo, command, context, handle, apply_inverse) do
    case lock_task(repo, context.account_id, handle.task_id) do
      nil ->
        undo_no_change(command, :unknown, "undo_unknown", "Undo unavailable", false, nil)

      current when current.revision != handle.produced_revision ->
        mark_undo_unavailable(repo, handle, context, "stale")

        undo_no_change(
          command,
          :stale,
          "undo_stale",
          "Task changed after this action",
          false,
          "review_latest_task"
        )

      current ->
        inverse = %{
          kind: String.to_existing_atom(handle.inverse_type),
          values: handle.inverse_payload
        }

        case apply_inverse.(current, inverse, context.accepted_at) do
          {:ok, task, activity} ->
            command = Map.put(command, :task_id, handle.task_id)
            persist_undo(repo, command, context, task, activity, handle)

          {:error, :invalid_inverse} ->
            undo_no_change(
              command,
              :uncertain,
              "undo_uncertain",
              "Undo could not be confirmed",
              true,
              "check_mutation_result"
            )
        end
    end
  end

  defp lock_undo_handle(repo, account_id, handle_hash) do
    case SQL.query!(
           repo,
           """
           SELECT id, task_id, original_activity_id, original_command_type,
                  produced_revision, inverse_type, inverse_payload,
                  expires_at, state
           FROM undo_handles
           WHERE account_id = $1 AND handle_hash = $2
           FOR UPDATE
           """,
           [account_id, handle_hash]
         ).rows do
      [
        [
          id,
          task_id,
          original_activity_id,
          original_command_type,
          produced_revision,
          inverse_type,
          inverse_payload,
          expires_at,
          state
        ]
      ] ->
        %{
          expires_at: to_datetime(expires_at),
          id: load_uuid(id),
          inverse_payload: inverse_payload,
          inverse_type: inverse_type,
          original_activity_id: original_activity_id,
          original_command_type: original_command_type,
          produced_revision: produced_revision,
          state: state,
          task_id: load_uuid(task_id)
        }

      [] ->
        nil
    end
  end

  defp mark_undo_unavailable(repo, handle, context, state) do
    %{num_rows: 1} =
      SQL.query!(
        repo,
        """
        UPDATE undo_handles SET state = $3, updated_at = $4
        WHERE account_id = $1 AND id = $2 AND state = 'available'
        """,
        [context.account_id, dump_uuid(handle.id), state, context.accepted_at]
      )

    SQL.query!(
      repo,
      """
      UPDATE task_activities SET recovery_state = $3
      WHERE account_id = $1 AND id = $2 AND recovery_state = 'available'
      """,
      [context.account_id, handle.original_activity_id, state]
    )
  end

  defp undo_no_change(command, outcome, code, title, retryable, recovery_action) do
    %{
      status: if(outcome == :unknown, do: 404, else: 200),
      body: %{
        "code" => code,
        "mutation_id" => command.mutation_id,
        "outcome" => Atom.to_string(outcome),
        "recovery_action" => recovery_action,
        "retryable" => retryable,
        "title" => title
      }
    }
  end

  defp decide_existing(repo, command, context, current, accepted_command, decide) do
    result =
      if not is_nil(current.trashed_at) and
           command.type not in [:trash_task, :restore_task] do
        {:error, {:trash_conflict, ["trashed_at"]}}
      else
        decide.(current, accepted_command)
      end

    case result do
      {:ok, task, nil, :already_satisfied, warnings} ->
        acknowledgement(
          repo,
          context.account_id,
          command,
          task,
          :already_satisfied,
          200,
          warnings
        )

      {:ok, task, activity, :accepted, warnings} ->
        persist_existing(repo, command, context, task, activity, warnings)

      {:ok, task, nil, :already_satisfied} ->
        acknowledgement(repo, context.account_id, command, task, :already_satisfied)

      {:ok, task, activity, :accepted} ->
        persist_existing(repo, command, context, task, activity)

      {:error, reason} when is_tuple(reason) ->
        if persisted_conflict_reason?(command, reason) do
          persist_command_conflict(repo, command, context, current, reason)
        else
          semantic_rejection(reason, current)
        end

      {:error, reason} ->
        semantic_rejection(reason, current)
    end
  end

  defp persisted_conflict_reason?(%{type: type}, {kind, affected_fields})
       when type in [:edit_task, :clarify_task] and
              kind in [:edit_conflict, :trash_conflict] and is_list(affected_fields),
       do: true

  defp persisted_conflict_reason?(%{type: type}, {kind, affected_fields})
       when type in [:complete_task, :reopen_task] and
              kind in [:lifecycle_conflict, :trash_conflict] and is_list(affected_fields),
       do: true

  defp persisted_conflict_reason?(%{type: type}, {:trash_conflict, affected_fields})
       when type in [:trash_task, :restore_task] and is_list(affected_fields),
       do: true

  defp persisted_conflict_reason?(_command, _reason), do: false

  defp persist_command_conflict(repo, command, context, current, reason) do
    {_kind, affected_fields} = reason
    conflict_id = Ecto.UUID.generate()

    values =
      command
      |> conflict_values(current)
      |> include_lifecycle_conflict_values(affected_fields, current)

    %{num_rows: 1} =
      SQL.query!(
        repo,
        """
        INSERT INTO persisted_conflicts (
          account_id, id, task_id, original_mutation_id, command_type,
          expected_revision, latest_revision, affected_fields, base_values,
          requested_values, current_values, inserted_at, updated_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::jsonb, $10::jsonb,
                $11::jsonb, $12, $12)
        """,
        [
          context.account_id,
          dump_uuid(conflict_id),
          dump_uuid(command.task_id),
          dump_uuid(command.mutation_id),
          Atom.to_string(command.type),
          command.expected_revision,
          current.revision,
          affected_fields,
          values.base,
          values.requested,
          values.current,
          context.accepted_at
        ]
      )

    result = semantic_rejection(reason, current)

    conflict = %{
      "fields" => conflict_field_bodies(affected_fields, values),
      "id" => conflict_id,
      "latest_revision" => current.revision
    }

    put_in(result, [:body, "conflict"], conflict)
  end

  defp conflict_values(%{type: type} = command, current)
       when type in [:edit_task, :clarify_task] do
    requested = stringify_detail_values(command.fields)

    %{
      base: stringify_detail_values(command.base_values),
      requested: requested,
      current:
        requested
        |> Map.keys()
        |> Map.new(fn field -> {field, task_field_value(current, field)} end)
    }
  end

  defp conflict_values(%{type: type, accepted_at: accepted_at}, current)
       when type in [:complete_task, :reopen_task] do
    requested = if type == :complete_task, do: utc_iso8601(accepted_at), else: nil

    %{
      base: %{"completed_at" => nil},
      requested: %{"completed_at" => requested},
      current: %{"completed_at" => optional_utc_iso8601(current.completed_at)}
    }
  end

  defp conflict_values(%{type: type, accepted_at: accepted_at}, current)
       when type in [:trash_task, :restore_task] do
    requested = if type == :trash_task, do: utc_iso8601(accepted_at), else: nil

    %{
      base: %{"trashed_at" => nil},
      requested: %{"trashed_at" => requested},
      current: %{"trashed_at" => optional_utc_iso8601(current.trashed_at)}
    }
  end

  defp conflict_field_bodies(affected_fields, values) do
    Enum.map(affected_fields, fn field ->
      %{
        "base" => Map.get(values.base, field),
        "current" => Map.get(values.current, field),
        "field" => field,
        "mine" => Map.get(values.requested, field)
      }
    end)
  end

  defp include_lifecycle_conflict_values(values, affected_fields, current) do
    values
    |> maybe_put_conflict_value(
      "completed_at",
      "completed_at" in affected_fields,
      optional_utc_iso8601(current.completed_at)
    )
    |> maybe_put_conflict_value(
      "trashed_at",
      "trashed_at" in affected_fields,
      optional_utc_iso8601(current.trashed_at)
    )
  end

  defp maybe_put_conflict_value(values, _field, false, _current), do: values

  defp maybe_put_conflict_value(values, field, true, current) do
    %{
      base: Map.put_new(values.base, field, nil),
      current: Map.put(values.current, field, current),
      requested: Map.put_new(values.requested, field, nil)
    }
  end

  defp stringify_detail_values(values) do
    Map.new(values, fn {field, value} -> {Atom.to_string(field), value} end)
  end

  defp task_field_value(task, "notes"), do: task.notes
  defp task_field_value(task, "title"), do: task.title

  defp execute_conflict_resolution(repo, command, context, accepted_command, decide) do
    case lock_persisted_conflict(repo, context.account_id, command) do
      nil ->
        conflict_not_found()

      conflict when not is_nil(conflict.resolved_by_mutation_id) ->
        conflict_already_resolved()

      conflict ->
        case lock_task(repo, context.account_id, command.task_id) do
          nil ->
            conflict_not_found()

          current ->
            resolve_locked_conflict(
              repo,
              command,
              context,
              current,
              conflict,
              accepted_command,
              decide
            )
        end
    end
  end

  defp lock_persisted_conflict(repo, account_id, command) do
    case SQL.query!(
           repo,
           """
           SELECT command_type, latest_revision, affected_fields, requested_values,
                  resolved_by_mutation_id
           FROM persisted_conflicts
           WHERE account_id = $1 AND id = $2 AND task_id = $3
           FOR UPDATE
           """,
           [account_id, dump_uuid(command.conflict_id), dump_uuid(command.task_id)]
         ).rows do
      [[command_type, latest_revision, affected_fields, requested_values, resolved_by]] ->
        %{
          affected_fields: affected_fields,
          command_type: command_type,
          latest_revision: latest_revision,
          requested_values: requested_values,
          resolved_by_mutation_id: if(resolved_by, do: load_uuid(resolved_by))
        }

      [] ->
        nil
    end
  end

  defp resolve_locked_conflict(
         repo,
         command,
         context,
         current,
         conflict,
         accepted_command,
         decide
       ) do
    cond do
      conflict.command_type not in ["edit_task", "clarify_task"] ->
        invalid_conflict_resolution()

      command.latest_revision != conflict.latest_revision or
          current.revision != conflict.latest_revision ->
        stale_conflict(current.revision)

      command.selections
      |> Map.keys()
      |> Enum.map(&Atom.to_string/1)
      |> Enum.sort() != Enum.sort(conflict.affected_fields) ->
        invalid_conflict_resolution()

      true ->
        resolved_fields = resolved_conflict_fields(current, conflict, command.selections)
        accepted_command = Map.put(accepted_command, :resolved_fields, resolved_fields)

        case decide.(current, accepted_command) do
          {:ok, task, nil, :already_satisfied} ->
            mark_conflict_resolved(repo, command, context)

            repo
            |> acknowledgement(context.account_id, command, task, :already_satisfied)
            |> put_in([:body, "resolved_conflict_id"], command.conflict_id)

          {:ok, task, activity, :accepted} ->
            result = persist_existing(repo, command, context, task, activity)
            mark_conflict_resolved(repo, command, context)
            put_in(result, [:body, "resolved_conflict_id"], command.conflict_id)

          {:error, :stale_conflict} ->
            stale_conflict(current.revision)

          {:error, _reason} ->
            invalid_conflict_resolution()
        end
    end
  end

  defp resolved_conflict_fields(current, conflict, selections) do
    conflict.requested_values
    |> Map.new(fn
      {"notes", value} -> {:notes, value}
      {"title", value} -> {:title, value}
    end)
    |> then(fn requested ->
      Enum.reduce(selections, requested, fn
        {_field, :mine}, fields -> fields
        {:notes, :current}, fields -> Map.put(fields, :notes, current.notes)
        {:title, :current}, fields -> Map.put(fields, :title, current.title)
      end)
    end)
  end

  defp mark_conflict_resolved(repo, command, context) do
    %{num_rows: 1} =
      SQL.query!(
        repo,
        """
        UPDATE persisted_conflicts
        SET resolved_by_mutation_id = $3, resolved_at = $4, updated_at = $4
        WHERE account_id = $1 AND id = $2 AND resolved_by_mutation_id IS NULL
        """,
        [
          context.account_id,
          dump_uuid(command.conflict_id),
          dump_uuid(command.mutation_id),
          context.accepted_at
        ]
      )
  end

  defp maybe_put_account_timezone(%{type: type} = command, repo, context)
       when type in [:plan_for_today, :restore_task] do
    %{rows: [[timezone]]} =
      SQL.query!(
        repo,
        "SELECT timezone FROM accounts WHERE id = $1 FOR SHARE",
        [context.account_id]
      )

    Map.put(command, :account_timezone, timezone)
  end

  defp maybe_put_account_timezone(command, _repo, _context), do: command

  defp execute_create_organization(repo, command, context, accepted_command, decide) do
    case decide.(accepted_command) do
      {:ok, organization, :accepted} ->
        case lock_organization(repo, context.account_id, command.organization_id) do
          nil ->
            if active_name_collision?(repo, context.account_id, organization, nil) do
              organization_rejection(:active_name_collision)
            else
              persist_create_organization(repo, command, context, organization)
            end

          %Organization{} = existing ->
            if existing.kind == organization.kind and
                 existing.display_name == organization.display_name do
              organization_acknowledgement(command, existing, :already_satisfied)
            else
              organization_rejection(:organization_identity_reused)
            end
        end

      {:error, reason} ->
        organization_rejection(reason)
    end
  end

  defp execute_existing_organization(repo, command, context, accepted_command, decide) do
    case lock_organization(repo, context.account_id, command.organization_id) do
      nil ->
        organization_not_found()

      current ->
        accepted_command =
          enrich_organization_command(repo, context.account_id, current, accepted_command)

        case decide.(current, accepted_command) do
          {:ok, organization, :already_satisfied} ->
            organization_acknowledgement(command, organization, :already_satisfied)

          {:ok, organization, :accepted} ->
            if active_name_collision?(repo, context.account_id, organization, current.id) do
              organization_rejection(:active_name_collision)
            else
              persist_existing_organization(repo, command, context, organization)
            end

          {:error, reason} ->
            organization_rejection(reason, current)
        end
    end
  end

  defp execute_task_assignment(repo, command, context, accepted_command, decide) do
    case lock_task_assignment(repo, context.account_id, command.task_id) do
      nil ->
        task_not_found()

      current ->
        case validate_assignment_targets(repo, context.account_id, current, command.fields) do
          :ok when not is_nil(current.trashed_at) ->
            semantic_rejection({:trash_conflict, ["trashed_at"]}, current)

          :ok ->
            case decide.(current, accepted_command) do
              {:ok, task, nil, :already_satisfied} ->
                acknowledgement(repo, context.account_id, command, task, :already_satisfied)

              {:ok, task, activity, :accepted} ->
                persist_task_assignment(repo, command, context, task, activity)

              {:error, reason} ->
                semantic_rejection(reason, current)
            end

          {:error, reason} ->
            assignment_rejection(reason)
        end
    end
  end

  defp lock_task(repo, account_id, task_id) do
    case SQL.query!(
           repo,
           """
           SELECT tasks.id, tasks.title, tasks.notes, tasks.inbox_state,
                  tasks.revision, tasks.captured_at, tasks.planned_on,
                  tasks.deadline_on, tasks.completed_at, tasks.trashed_at,
                  COALESCE((
                    SELECT max(activity.to_revision)
                    FROM task_activities AS activity
                    WHERE activity.account_id = tasks.account_id
                      AND activity.task_id = tasks.id
                      AND activity.activity_type IN ('task_completed', 'task_reopened')
                  ), 0) AS lifecycle_revision
           FROM tasks
           WHERE tasks.account_id = $1 AND tasks.id = $2
           FOR UPDATE OF tasks
           """,
           [account_id, dump_uuid(task_id)]
         ).rows do
      [row] -> task_from_row(row)
      [] -> nil
    end
  end

  defp lock_task_assignment(repo, account_id, task_id) do
    case SQL.query!(
           repo,
           """
           SELECT id, title, notes, inbox_state, revision, captured_at,
                  planned_on, deadline_on, completed_at, trashed_at, project_id
           FROM tasks
           WHERE account_id = $1 AND id = $2
           FOR UPDATE
           """,
           [account_id, dump_uuid(task_id)]
         ).rows do
      [
        [
          id,
          title,
          notes,
          inbox_state,
          revision,
          captured_at,
          planned_on,
          deadline_on,
          completed_at,
          trashed_at,
          project_id
        ]
      ] ->
        %{
          id: load_uuid(id),
          title: title,
          notes: notes,
          inbox_state: String.to_existing_atom(inbox_state),
          revision: revision,
          captured_at: to_datetime(captured_at),
          planned_on: planned_on,
          deadline_on: deadline_on,
          completed_at: optional_datetime(completed_at),
          trashed_at: optional_datetime(trashed_at),
          project_id: load_optional_uuid(project_id),
          tag_ids: load_task_tag_ids(repo, account_id, task_id)
        }

      [] ->
        nil
    end
  end

  defp lock_organization(repo, account_id, organization_id) do
    case SQL.query!(
           repo,
           """
           SELECT id, kind, display_name, name_key, name_key_version, archived_at, revision
           FROM organizations
           WHERE account_id = $1 AND id = $2
           FOR UPDATE
           """,
           [account_id, dump_uuid(organization_id)]
         ).rows do
      [row] -> organization_from_row(row)
      [] -> nil
    end
  end

  defp enrich_organization_command(repo, account_id, organization, command) do
    case command.type do
      :archive_organization ->
        Map.put(
          command,
          :active_unfinished_task_count,
          active_unfinished_task_count(repo, account_id, organization)
        )

      :unarchive_organization ->
        Map.put(
          command,
          :active_name_collision?,
          active_name_collision?(repo, account_id, organization, organization.id)
        )

      _type ->
        command
    end
  end

  defp active_unfinished_task_count(_repo, _account_id, %Organization{kind: :tag}), do: 0

  defp active_unfinished_task_count(repo, account_id, %Organization{id: organization_id}) do
    %{rows: [[count]]} =
      SQL.query!(
        repo,
        "SELECT count(*) FROM tasks WHERE account_id = $1 AND project_id = $2 AND completed_at IS NULL AND trashed_at IS NULL",
        [account_id, dump_uuid(organization_id)]
      )

    count
  end

  defp active_name_collision?(repo, account_id, organization, excluding_id) do
    params = [
      account_id,
      Atom.to_string(organization.kind),
      organization.name_key_version,
      organization.name_key
    ]

    {query, params} =
      if excluding_id do
        {
          """
          SELECT 1 FROM organizations
          WHERE account_id = $1 AND kind = $2 AND name_key_version = $3 AND name_key = $4
            AND archived_at IS NULL AND id <> $5
          LIMIT 1
          """,
          params ++ [dump_uuid(excluding_id)]
        }
      else
        {
          """
          SELECT 1 FROM organizations
          WHERE account_id = $1 AND kind = $2 AND name_key_version = $3 AND name_key = $4
            AND archived_at IS NULL
          LIMIT 1
          """,
          params
        }
      end

    SQL.query!(repo, query, params).rows != []
  end

  defp validate_assignment_targets(repo, account_id, current, fields) do
    with :ok <-
           validate_assignment_target(
             repo,
             account_id,
             fields.project_id,
             :project,
             fields.project_id == current.project_id
           ),
         :ok <-
           Enum.reduce_while(fields.tag_ids, :ok, fn tag_id, :ok ->
             case validate_assignment_target(
                    repo,
                    account_id,
                    tag_id,
                    :tag,
                    tag_id in current.tag_ids
                  ) do
               :ok -> {:cont, :ok}
               error -> {:halt, error}
             end
           end) do
      :ok
    end
  end

  defp validate_assignment_target(_repo, _account_id, nil, :project, _already_assigned), do: :ok

  defp validate_assignment_target(repo, account_id, organization_id, kind, already_assigned) do
    expected_kind = Atom.to_string(kind)

    case SQL.query!(
           repo,
           """
           SELECT kind, archived_at
           FROM organizations
           WHERE account_id = $1 AND id = $2
           FOR SHARE
           """,
           [account_id, dump_uuid(organization_id)]
         ).rows do
      [] ->
        {:error, :organization_not_found}

      [[stored_kind, _archived_at]] when stored_kind != expected_kind ->
        {:error, :organization_kind_mismatch}

      [[_stored_kind, archived_at]] when not is_nil(archived_at) and not already_assigned ->
        {:error, :archived_organization_not_assignable}

      [[_stored_kind, _archived_at]] ->
        :ok
    end
  end

  defp persist_capture(repo, command, context, task, activity) do
    inserted_task =
      SQL.query!(
        repo,
        """
        INSERT INTO tasks (
          account_id, id, title, notes, inbox_state, revision, captured_at,
          planned_on, deadline_on, inserted_at, updated_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $7, $7)
        ON CONFLICT (account_id, id) DO NOTHING
        RETURNING id, title, notes, inbox_state, revision, captured_at,
                  planned_on, deadline_on, completed_at, trashed_at
        """,
        [
          context.account_id,
          dump_uuid(task.id),
          task.title,
          task.notes,
          Atom.to_string(task.inbox_state),
          task.revision,
          task.captured_at,
          task.planned_on,
          task.deadline_on
        ]
      )

    case inserted_task.rows do
      [row] ->
        bump_task_view_revisions(repo, [:inbox], context)
        persist_activity(repo, command, context, activity)
        acknowledgement(repo, context.account_id, command, task_from_row(row), :accepted, 201)

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

  defp persist_existing(repo, command, context, task, activity, warnings \\ []) do
    %{num_rows: 1} =
      SQL.query!(
        repo,
        """
        UPDATE tasks
        SET title = $3, notes = $4, inbox_state = $5, revision = $6,
            planned_on = $7, deadline_on = $8, completed_at = $9,
            trashed_at = $10, updated_at = $11
        WHERE account_id = $1 AND id = $2
        """,
        [
          context.account_id,
          dump_uuid(task.id),
          task.title,
          task.notes,
          Atom.to_string(task.inbox_state),
          task.revision,
          task.planned_on,
          task.deadline_on,
          task.completed_at,
          task.trashed_at,
          context.accepted_at
        ]
      )

    maybe_bump_task_view_revisions(repo, command, context)
    activity_id = persist_activity(repo, command, context, activity)

    result = acknowledgement(repo, context.account_id, command, task, :accepted, 200, warnings)

    case issue_undo(repo, command, context, task, activity, activity_id) do
      nil -> result
      undo -> put_undo(result, undo)
    end
  end

  defp persist_undo(repo, command, context, task, activity, handle) do
    %{num_rows: 1} =
      SQL.query!(
        repo,
        """
        UPDATE tasks
        SET title = $3, notes = $4, inbox_state = $5, revision = $6,
            planned_on = $7, deadline_on = $8, completed_at = $9,
            trashed_at = $10, updated_at = $11
        WHERE account_id = $1 AND id = $2
        """,
        [
          context.account_id,
          dump_uuid(task.id),
          task.title,
          task.notes,
          Atom.to_string(task.inbox_state),
          task.revision,
          task.planned_on,
          task.deadline_on,
          task.completed_at,
          task.trashed_at,
          context.accepted_at
        ]
      )

    maybe_bump_task_view_revisions(
      repo,
      %{type: String.to_existing_atom(handle.original_command_type)},
      context
    )

    persist_activity(repo, command, context, activity, handle.original_activity_id)

    %{num_rows: 1} =
      SQL.query!(
        repo,
        """
        UPDATE task_activities SET recovery_state = 'undone'
        WHERE account_id = $1 AND id = $2 AND recovery_state = 'available'
        """,
        [context.account_id, handle.original_activity_id]
      )

    %{num_rows: 1} =
      SQL.query!(
        repo,
        """
        UPDATE undo_handles
        SET state = 'applied', consumed_at = $3, result_mutation_id = $4, updated_at = $3
        WHERE account_id = $1 AND id = $2 AND state = 'available'
        """,
        [
          context.account_id,
          dump_uuid(handle.id),
          context.accepted_at,
          dump_uuid(command.mutation_id)
        ]
      )

    acknowledgement(repo, context.account_id, command, task, :accepted)
  end

  defp issue_undo(repo, command, context, task, activity, activity_id) do
    case Undo.compensation(command, activity) do
      :not_supported ->
        nil

      {:ok, compensation} ->
        undo_id = Ecto.UUID.generate()
        raw_handle = raw_undo_handle(undo_id)
        expires_at = DateTime.add(context.accepted_at, Undo.valid_for_seconds(), :second)
        inverse_payload = stringify_inverse_values(compensation.inverse.values)

        %{num_rows: 1} =
          SQL.query!(
            repo,
            """
            INSERT INTO undo_handles (
              account_id, id, handle_hash, task_id, original_mutation_id,
              original_activity_id, original_command_type, produced_revision,
              inverse_type, inverse_payload, label, expires_at, state,
              inserted_at, updated_at
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10::jsonb,
                    $11, $12, 'available', $13, $13)
            """,
            [
              context.account_id,
              dump_uuid(undo_id),
              :crypto.hash(:sha256, raw_handle),
              dump_uuid(task.id),
              dump_uuid(command.mutation_id),
              activity_id,
              Atom.to_string(command.type),
              task.revision,
              Atom.to_string(compensation.inverse.kind),
              inverse_payload,
              compensation.label,
              expires_at,
              context.accepted_at
            ]
          )

        %{num_rows: 1} =
          SQL.query!(
            repo,
            """
            UPDATE task_activities SET recovery_state = 'available'
            WHERE account_id = $1 AND id = $2 AND recovery_state = 'not_available'
            """,
            [context.account_id, activity_id]
          )

        %{
          expires_at: expires_at,
          handle: raw_handle,
          label: compensation.label
        }
    end
  end

  defp stringify_inverse_values(values) do
    Map.new(values, fn
      {field, %Date{} = value} -> {field, Date.to_iso8601(value)}
      {field, %DateTime{} = value} -> {field, DateTime.to_iso8601(value)}
      pair -> pair
    end)
  end

  defp put_undo(result, undo) do
    result
    |> put_in([:body, "undo"], %{
      "expires_at" => utc_iso8601(undo.expires_at),
      "label" => undo.label
    })
    |> Map.put(:undo_handle, undo.handle)
  end

  defp persist_create_organization(repo, command, context, organization) do
    %{rows: [row]} =
      SQL.query!(
        repo,
        """
        INSERT INTO organizations (
          account_id, id, kind, display_name, name_key, name_key_version,
          archived_at, revision, inserted_at, updated_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, NULL, $7, $8, $8)
        RETURNING id, kind, display_name, name_key, name_key_version, archived_at, revision
        """,
        [
          context.account_id,
          dump_uuid(organization.id),
          Atom.to_string(organization.kind),
          organization.display_name,
          organization.name_key,
          organization.name_key_version,
          organization.revision,
          context.accepted_at
        ]
      )

    organization_acknowledgement(command, organization_from_row(row), :accepted, 201)
  end

  defp persist_existing_organization(repo, command, context, organization) do
    %{rows: [row]} =
      SQL.query!(
        repo,
        """
        UPDATE organizations
        SET display_name = $3, name_key = $4, name_key_version = $5,
            archived_at = $6, revision = $7, updated_at = $8
        WHERE account_id = $1 AND id = $2
        RETURNING id, kind, display_name, name_key, name_key_version, archived_at, revision
        """,
        [
          context.account_id,
          dump_uuid(organization.id),
          organization.display_name,
          organization.name_key,
          organization.name_key_version,
          organization.archived_at,
          organization.revision,
          context.accepted_at
        ]
      )

    bump_activity_view_revision(repo, context)
    organization_acknowledgement(command, organization_from_row(row), :accepted)
  end

  defp persist_task_assignment(repo, command, context, task, activity) do
    %{num_rows: 1} =
      SQL.query!(
        repo,
        """
        UPDATE tasks
        SET project_id = $3, revision = $4, updated_at = $5
        WHERE account_id = $1 AND id = $2
        """,
        [
          context.account_id,
          dump_uuid(task.id),
          dump_optional_uuid(task.project_id),
          task.revision,
          context.accepted_at
        ]
      )

    SQL.query!(
      repo,
      "DELETE FROM task_tags WHERE account_id = $1 AND task_id = $2",
      [context.account_id, dump_uuid(task.id)]
    )

    Enum.each(task.tag_ids, fn tag_id ->
      SQL.query!(
        repo,
        """
        INSERT INTO task_tags (account_id, task_id, tag_id, tag_kind, inserted_at)
        VALUES ($1, $2, $3, 'tag', $4)
        """,
        [context.account_id, dump_uuid(task.id), dump_uuid(tag_id), context.accepted_at]
      )
    end)

    persist_activity(repo, command, context, activity)
    acknowledgement(repo, context.account_id, command, task, :accepted)
  end

  defp persist_activity(repo, command, context, activity, undone_activity_id \\ nil) do
    actor = activity_actor(context)
    bump_activity_view_revision(repo, context)

    %{rows: [[activity_id]]} =
      SQL.query!(
        repo,
        """
        INSERT INTO task_activities (
          account_id, task_id, mutation_id, activity_type, activity_version,
          actor_type, actor_principal, actor_label, client_kind,
          from_revision, to_revision, changed_fields, recovery_state,
          undone_activity_id, accepted_at, inserted_at
        )
        VALUES (
          $1, $2, $3, $4, $5, $6, $7, $8, $9,
          $10, $11, $12::jsonb, 'not_available', $13, $14, $14
        )
        RETURNING id
        """,
        [
          context.account_id,
          dump_uuid(command.task_id),
          dump_uuid(command.mutation_id),
          Atom.to_string(activity.type),
          activity.version,
          actor.type,
          actor.principal,
          actor.label,
          context.client_kind,
          activity.from_revision,
          activity.to_revision,
          activity.changed_fields,
          undone_activity_id,
          activity.accepted_at
        ]
      )

    activity_id
  end

  defp activity_actor(%{actor_type: "user"}),
    do: %{label: "You", principal: "account_owner", type: "user"}

  defp activity_actor(%{actor_type: "agent", actor_label: label, actor_principal: principal}),
    do: %{label: label, principal: principal, type: "agent"}

  defp bump_activity_view_revision(repo, context) do
    %{num_rows: 1} =
      SQL.query!(
        repo,
        """
        UPDATE accounts
        SET activity_view_revision = activity_view_revision + 1, updated_at = $2
        WHERE id = $1
        """,
        [context.account_id, context.accepted_at]
      )
  end

  defp maybe_bump_task_view_revisions(repo, command, context)
       when command.type in [:edit_task_dates, :plan_for_today, :unplan_task] do
    bump_task_view_revisions(repo, [:today, :upcoming], context)
  end

  defp maybe_bump_task_view_revisions(repo, command, context)
       when command.type in [:clarify_task, :return_to_inbox] do
    bump_task_view_revisions(repo, [:inbox], context)
  end

  defp maybe_bump_task_view_revisions(repo, command, context)
       when command.type in [:complete_task, :reopen_task] do
    bump_task_view_revisions(repo, [:inbox, :today, :upcoming, :completed], context)
  end

  defp maybe_bump_task_view_revisions(repo, command, context)
       when command.type in [:trash_task, :restore_task] do
    bump_task_view_revisions(repo, [:inbox, :today, :upcoming, :completed, :trash], context)
  end

  defp maybe_bump_task_view_revisions(_repo, _command, _context), do: :ok

  defp bump_task_view_revisions(repo, views, context) do
    assignments =
      views
      |> Enum.map(fn view -> "#{view}_view_revision = #{view}_view_revision + 1" end)
      |> Enum.join(", ")

    %{num_rows: 1} =
      SQL.query!(
        repo,
        "UPDATE accounts SET #{assignments}, updated_at = $2 WHERE id = $1",
        [context.account_id, context.accepted_at]
      )
  end

  defp acknowledgement(
         repo,
         account_id,
         command,
         task,
         outcome,
         status \\ 200,
         warnings \\ []
       ) do
    body = %{
      "mutation_id" => command.mutation_id,
      "outcome" => Atom.to_string(outcome),
      "revision" => task.revision,
      "snapshot" => task_body(task, account_id, repo),
      "task_id" => task.id,
      "warnings" => Enum.map(warnings, &warning_body/1)
    }

    body =
      if command.type == :restore_task do
        Map.put(body, "destinations", restore_destinations(task, command))
      else
        body
      end

    %{
      status: status,
      body: body
    }
  end

  defp restore_destinations(%Task{completed_at: completed_at}, _command)
       when not is_nil(completed_at),
       do: ["Completed"]

  defp restore_destinations(task, command) do
    {:ok, account_day} = TaskDates.account_day(command.accepted_at, command.account_timezone)
    classification = TaskDates.classify(task.planned_on, task.deadline_on, account_day)

    []
    |> maybe_destination(task.inbox_state == :inbox, "Inbox")
    |> maybe_destination(classification.today_reasons != [], "Today")
    |> maybe_destination(
      Enum.any?([task.planned_on, task.deadline_on], fn
        %Date{} = date -> Date.after?(date, account_day)
        nil -> false
      end),
      "Upcoming"
    )
  end

  defp maybe_destination(destinations, true, destination), do: destinations ++ [destination]
  defp maybe_destination(destinations, false, _destination), do: destinations

  defp warning_body(:planned_after_deadline) do
    %{
      "code" => "planned_after_deadline",
      "message" => "Planned date is after the deadline. Both dates will be saved."
    }
  end

  defp organization_acknowledgement(command, organization, outcome, status \\ 200) do
    %{
      status: status,
      body: %{
        "mutation_id" => command.mutation_id,
        "organization_id" => organization.id,
        "outcome" => Atom.to_string(outcome),
        "revision" => organization.revision,
        "snapshot" => organization_body(organization)
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
      {:ok,
       attach_replay_undo(
         repo,
         context.account_id,
         command.mutation_id,
         %{status: status, body: response},
         context.accepted_at
       )}
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

  defp attach_replay_undo(repo, account_id, mutation_id, result, accepted_at) do
    case SQL.query!(
           repo,
           """
           SELECT id
           FROM undo_handles
           WHERE account_id = $1 AND original_mutation_id = $2
             AND state = 'available' AND expires_at >= $3
           """,
           [account_id, dump_uuid(mutation_id), accepted_at]
         ).rows do
      [[undo_id]] ->
        result
        |> update_in([:body, "undo"], fn
          nil -> nil
          undo -> Map.put(undo, "handle", raw_undo_handle(load_uuid(undo_id)))
        end)

      [] ->
        result
    end
  end

  defp public_result(%{undo_handle: raw_handle} = result) do
    result
    |> Map.delete(:undo_handle)
    |> update_in([:body, "undo"], &Map.put(&1, "handle", raw_handle))
  end

  defp public_result(result), do: result

  defp raw_undo_handle(undo_id) do
    endpoint_config = Application.fetch_env!(:keepling, KeeplingWeb.Endpoint)
    secret = Keyword.fetch!(endpoint_config, :secret_key_base)

    :crypto.mac(:hmac, :sha256, secret, Ecto.UUID.dump!(undo_id))
    |> Base.url_encode64(padding: false)
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

  defp semantic_rejection(:no_date_fields_touched, _current),
    do:
      problem(
        422,
        "no_date_fields_touched",
        "No task dates changed",
        "Send at least one planned date or deadline field.",
        false,
        "edit_task_dates"
      )

  defp semantic_rejection(:invalid_timezone, _current),
    do:
      problem(
        503,
        "account_timezone_unavailable",
        "Account timezone unavailable",
        "The configured account timezone could not resolve an account day.",
        true,
        "check_account_timezone"
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

  defp semantic_rejection({:assignment_conflict, affected_fields}, current) do
    problem(
      409,
      "task_assignment_conflict",
      "Task assignments changed elsewhere",
      "Review the project and tags before saving again.",
      false,
      "review_task_conflict",
      %{
        "affected_fields" => affected_fields,
        "current_revision" => current.revision
      }
    )
  end

  defp semantic_rejection({:lifecycle_conflict, affected_fields}, current) do
    problem(
      409,
      "task_lifecycle_conflict",
      "Task lifecycle changed elsewhere",
      "Refresh the task before completing or reopening it.",
      false,
      "refresh_task",
      %{
        "affected_fields" => affected_fields,
        "current_revision" => current.revision
      }
    )
  end

  defp semantic_rejection({:trash_conflict, affected_fields}, current) do
    problem(
      409,
      "task_trash_conflict",
      "Task Trash state changed elsewhere",
      "Refresh the task before moving it to Trash or restoring it.",
      false,
      "refresh_task",
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

  defp conflict_not_found do
    problem(
      404,
      "task_conflict_not_found",
      "Task conflict not found",
      "Refresh the task before trying to resolve this conflict.",
      false,
      "refresh_task"
    )
  end

  defp conflict_already_resolved do
    problem(
      409,
      "task_conflict_already_resolved",
      "Task conflict already resolved",
      "Refresh the task to see the accepted resolution.",
      false,
      "refresh_task"
    )
  end

  defp stale_conflict(current_revision) do
    problem(
      409,
      "task_conflict_stale",
      "Task changed after the conflict",
      "Review the latest task before resolving the conflict again.",
      false,
      "review_task_conflict",
      %{"current_revision" => current_revision}
    )
  end

  defp invalid_conflict_resolution do
    problem(
      422,
      "invalid_conflict_resolution",
      "Invalid task conflict resolution",
      "Choose mine or current for every affected task detail field.",
      false,
      "review_task_conflict"
    )
  end

  defp organization_not_found do
    problem(
      404,
      "organization_not_found",
      "Project or tag not found",
      "Refresh projects and tags before trying again.",
      false,
      "refresh_organizations"
    )
  end

  defp organization_rejection(reason, current \\ nil)

  defp organization_rejection(:name_required, _current),
    do:
      problem(
        422,
        "organization_name_required",
        "Name required",
        "Enter a project or tag name.",
        false,
        "edit_organization_name"
      )

  defp organization_rejection(:name_too_long, _current),
    do:
      problem(
        422,
        "organization_name_too_long",
        "Name too long",
        "Shorten the name to 200 characters or fewer.",
        false,
        "edit_organization_name"
      )

  defp organization_rejection(:active_name_collision, _current),
    do:
      problem(
        409,
        "active_organization_name_collision",
        "That active name is already in use",
        "Choose a different name or keep this item archived.",
        false,
        "edit_organization_name"
      )

  defp organization_rejection(:organization_identity_reused, _current),
    do:
      problem(
        409,
        "organization_identity_reused",
        "Project or tag identity already used",
        "Use a new organization identity for a different project or tag.",
        false,
        "create_new_organization_identity"
      )

  defp organization_rejection(:stale_organization, current),
    do:
      problem(
        409,
        "organization_revision_stale",
        "Project or tag changed elsewhere",
        "Refresh projects and tags before trying again.",
        false,
        "refresh_organizations",
        %{"current_revision" => current.revision}
      )

  defp organization_rejection({:project_archive_blocked, count}, _current),
    do:
      problem(
        409,
        "project_archive_blocked",
        "Project has active unfinished tasks",
        "Move or finish those tasks before archiving this project.",
        false,
        "review_project_tasks",
        %{"active_unfinished_task_count" => count}
      )

  defp organization_rejection(_reason, _current),
    do:
      problem(
        422,
        "invalid_organization",
        "Invalid project or tag",
        "Send a closed version 1 organization command.",
        false,
        "correct_request"
      )

  defp assignment_rejection(:organization_not_found), do: organization_not_found()

  defp assignment_rejection(:organization_kind_mismatch),
    do:
      problem(
        422,
        "organization_kind_mismatch",
        "Project or tag type does not match",
        "Choose a project for Project and tags for Tags.",
        false,
        "review_task_assignments"
      )

  defp assignment_rejection(:archived_organization_not_assignable),
    do:
      problem(
        422,
        "archived_organization_not_assignable",
        "Archived item cannot be newly assigned",
        "Choose an active project or tag.",
        false,
        "review_task_assignments"
      )

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

  defp task_from_row([
         id,
         title,
         notes,
         inbox_state,
         revision,
         captured_at,
         planned_on,
         deadline_on,
         completed_at,
         trashed_at
       ]) do
    %Task{
      id: load_uuid(id),
      title: title,
      notes: notes,
      inbox_state: String.to_existing_atom(inbox_state),
      revision: revision,
      captured_at: to_datetime(captured_at),
      completed_at: optional_datetime(completed_at),
      lifecycle_revision: 0,
      planned_on: planned_on,
      deadline_on: deadline_on,
      trashed_at: optional_datetime(trashed_at)
    }
  end

  defp task_from_row(row_and_lifecycle_revision) when length(row_and_lifecycle_revision) == 11 do
    {row, [lifecycle_revision]} = Enum.split(row_and_lifecycle_revision, 10)
    %{task_from_row(row) | lifecycle_revision: lifecycle_revision}
  end

  defp task_body_from_row(row, account_id, repo),
    do: row |> task_from_row() |> task_body(account_id, repo)

  defp task_body(task, account_id, repo) do
    assignment = load_assignment_refs(repo, account_id, task.id)

    %{
      "captured_at" => utc_iso8601(task.captured_at),
      "completed_at" => optional_utc_iso8601(task.completed_at),
      "id" => task.id,
      "inbox_state" => Atom.to_string(task.inbox_state),
      "notes" => task.notes,
      "planned_on" => optional_date(task.planned_on),
      "deadline_on" => optional_date(task.deadline_on),
      "project" => assignment.project,
      "revision" => task.revision,
      "tags" => assignment.tags,
      "title" => task.title,
      "trashed_at" => optional_utc_iso8601(task.trashed_at)
    }
  end

  defp load_assignment_refs(repo, account_id, task_id) do
    project =
      case SQL.query!(
             repo,
             """
             SELECT organizations.id, organizations.display_name, organizations.archived_at
             FROM tasks
             JOIN organizations
               ON organizations.account_id = tasks.account_id
              AND organizations.id = tasks.project_id
              AND organizations.kind = 'project'
             WHERE tasks.account_id = $1 AND tasks.id = $2
             """,
             [account_id, dump_uuid(task_id)]
           ).rows do
        [row] -> organization_reference(row)
        [] -> nil
      end

    tags =
      SQL.query!(
        repo,
        """
        SELECT organizations.id, organizations.display_name, organizations.archived_at
        FROM task_tags
        JOIN organizations
          ON organizations.account_id = task_tags.account_id
         AND organizations.id = task_tags.tag_id
         AND organizations.kind = 'tag'
        WHERE task_tags.account_id = $1 AND task_tags.task_id = $2
        ORDER BY organizations.display_name ASC, organizations.id ASC
        """,
        [account_id, dump_uuid(task_id)]
      ).rows
      |> Enum.map(&organization_reference/1)

    %{project: project, tags: tags}
  end

  defp load_task_tag_ids(repo, account_id, task_id) do
    SQL.query!(
      repo,
      """
      SELECT tag_id FROM task_tags
      WHERE account_id = $1 AND task_id = $2
      ORDER BY tag_id ASC
      """,
      [account_id, dump_uuid(task_id)]
    ).rows
    |> Enum.map(fn [tag_id] -> load_uuid(tag_id) end)
  end

  defp organization_reference([id, display_name, archived_at]) do
    %{
      "archived" => not is_nil(archived_at),
      "id" => load_uuid(id),
      "name" => display_name
    }
  end

  defp organization_from_row([
         id,
         kind,
         display_name,
         name_key,
         name_key_version,
         archived_at,
         revision
       ]) do
    %Organization{
      id: load_uuid(id),
      kind: String.to_existing_atom(kind),
      display_name: display_name,
      name_key: name_key,
      name_key_version: name_key_version,
      archived_at: optional_datetime(archived_at),
      revision: revision
    }
  end

  defp organization_body_from_row(row), do: row |> organization_from_row() |> organization_body()

  defp organization_body(organization) do
    %{
      "archived" => not is_nil(organization.archived_at),
      "assignable" => is_nil(organization.archived_at),
      "id" => organization.id,
      "kind" => Atom.to_string(organization.kind),
      "name" => organization.display_name,
      "revision" => organization.revision
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

  defp canonical_command(%{type: type, name: name} = command)
       when type in [:create_organization, :rename_organization] do
    case Organization.normalize_name(name) do
      %{display_name: display_name} -> %{command | name: display_name}
      {:error, _reason} -> command
    end
  end

  defp canonical_command(%{type: :assign_task_organizations} = command) do
    command
    |> put_in([:base_values, :tag_ids], Enum.sort(command.base_values.tag_ids))
    |> put_in([:fields, :tag_ids], Enum.sort(command.fields.tag_ids))
  end

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
  defp dump_optional_uuid(nil), do: nil
  defp dump_optional_uuid(uuid), do: dump_uuid(uuid)
  defp load_uuid(uuid), do: Ecto.UUID.load!(uuid)
  defp load_optional_uuid(nil), do: nil
  defp load_optional_uuid(uuid), do: load_uuid(uuid)
  defp to_datetime(%DateTime{} = value), do: value
  defp to_datetime(%NaiveDateTime{} = value), do: DateTime.from_naive!(value, "Etc/UTC")
  defp optional_datetime(nil), do: nil
  defp optional_datetime(value), do: to_datetime(value)
  defp optional_utc_iso8601(nil), do: nil
  defp optional_utc_iso8601(value), do: utc_iso8601(value)
  defp optional_date(nil), do: nil
  defp optional_date(%Date{} = value), do: Date.to_iso8601(value)
  defp utc_iso8601(value), do: value |> to_datetime() |> DateTime.to_iso8601()
end
