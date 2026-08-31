defmodule Keepling.Adapters.Postgres.CommandStore do
  @moduledoc """
  PostgreSQL interpreter for semantic commands and stable command results.

  The account-scoped receipt uniqueness constraint arbitrates first delivery.
  Accepted task, activity, and terminal acknowledgement commit together.
  """

  @behaviour Keepling.Application.Commands.Port

  alias Ecto.Adapters.SQL
  alias Keepling.Application.Activity
  alias Keepling.Domain.{Organization, Task}
  alias Keepling.Repo

  @behaviour Activity.Port

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
           SELECT id, title, notes, inbox_state, revision, captured_at, planned_on, deadline_on
           FROM tasks
           WHERE account_id = $1 AND inbox_state = 'inbox'
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
      [[_mutation_id]] -> execute_first_delivery(repo, command, context, decide)
      [] -> replay(repo, command, context, fingerprint)
    end
  end

  defp execute_first_delivery(repo, command, context, decide) do
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

      {:error, reason} ->
        semantic_rejection(reason, current)
    end
  end

  defp maybe_put_account_timezone(%{type: :plan_for_today} = command, repo, context) do
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
           SELECT id, title, notes, inbox_state, revision, captured_at, planned_on, deadline_on
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

  defp lock_task_assignment(repo, account_id, task_id) do
    case SQL.query!(
           repo,
           """
           SELECT id, title, notes, inbox_state, revision, captured_at,
                  planned_on, deadline_on, project_id
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
        "SELECT count(*) FROM tasks WHERE account_id = $1 AND project_id = $2",
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
        RETURNING id, title, notes, inbox_state, revision, captured_at, planned_on, deadline_on
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
            planned_on = $7, deadline_on = $8, updated_at = $9
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
          context.accepted_at
        ]
      )

    maybe_bump_temporal_view_revisions(repo, command, context)
    persist_activity(repo, command, context, activity)
    acknowledgement(repo, context.account_id, command, task, :accepted, 200, warnings)
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

  defp persist_activity(repo, command, context, activity) do
    actor = activity_actor(context)
    bump_activity_view_revision(repo, context)

    SQL.query!(
      repo,
      """
      INSERT INTO task_activities (
        account_id, task_id, mutation_id, activity_type, activity_version,
        actor_type, actor_principal, actor_label, client_kind,
        from_revision, to_revision, changed_fields, recovery_state,
        accepted_at, inserted_at
      )
      VALUES (
        $1, $2, $3, $4, $5, $6, $7, $8, $9,
        $10, $11, $12::jsonb, 'not_available', $13, $13
      )
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
        activity.accepted_at
      ]
    )
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

  defp maybe_bump_temporal_view_revisions(repo, command, context)
       when command.type in [:edit_task_dates, :plan_for_today, :unplan_task] do
    %{num_rows: 1} =
      SQL.query!(
        repo,
        """
        UPDATE accounts
        SET today_view_revision = today_view_revision + 1,
            upcoming_view_revision = upcoming_view_revision + 1,
            updated_at = $2
        WHERE id = $1
        """,
        [context.account_id, context.accepted_at]
      )
  end

  defp maybe_bump_temporal_view_revisions(_repo, _command, _context), do: :ok

  defp acknowledgement(
         repo,
         account_id,
         command,
         task,
         outcome,
         status \\ 200,
         warnings \\ []
       ) do
    %{
      status: status,
      body: %{
        "mutation_id" => command.mutation_id,
        "outcome" => Atom.to_string(outcome),
        "revision" => task.revision,
        "snapshot" => task_body(task, account_id, repo),
        "task_id" => task.id,
        "warnings" => Enum.map(warnings, &warning_body/1)
      }
    }
  end

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
         deadline_on
       ]) do
    %Task{
      id: load_uuid(id),
      title: title,
      notes: notes,
      inbox_state: String.to_existing_atom(inbox_state),
      revision: revision,
      captured_at: to_datetime(captured_at),
      planned_on: planned_on,
      deadline_on: deadline_on
    }
  end

  defp task_body_from_row(row, account_id, repo),
    do: row |> task_from_row() |> task_body(account_id, repo)

  defp task_body(task, account_id, repo) do
    assignment = load_assignment_refs(repo, account_id, task.id)

    %{
      "captured_at" => utc_iso8601(task.captured_at),
      "id" => task.id,
      "inbox_state" => Atom.to_string(task.inbox_state),
      "notes" => task.notes,
      "planned_on" => optional_date(task.planned_on),
      "deadline_on" => optional_date(task.deadline_on),
      "project" => assignment.project,
      "revision" => task.revision,
      "tags" => assignment.tags,
      "title" => task.title
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
  defp optional_date(nil), do: nil
  defp optional_date(%Date{} = value), do: Date.to_iso8601(value)
  defp utc_iso8601(value), do: value |> to_datetime() |> DateTime.to_iso8601()
end
