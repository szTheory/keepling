defmodule Keepling.Adapters.Postgres.TaskViews do
  @moduledoc """
  PostgreSQL task-list projections with account-scoped keysets and Today locks.
  """

  @behaviour Keepling.Application.TaskViews.Port

  alias Ecto.Adapters.SQL
  alias Keepling.Domain.TaskDates
  alias Keepling.Repo

  @maximum_today_section 500

  @impl true
  def list_tasks(%{account_id: account_id, accepted_at: accepted_at}, view, options) do
    case Repo.transact(fn repo ->
           with {:ok, scope} <- account_scope(repo, account_id, accepted_at, view),
                :ok <- cursor_revision(options.cursor, scope),
                {:ok, items, next_keyset} <-
                  page(repo, account_id, view, scope, options.cursor, options.limit) do
             {:ok,
              %{
                account_day: Date.to_iso8601(scope.account_day),
                account_timezone: scope.account_timezone,
                items: items,
                next_keyset: add_revisions(next_keyset, scope),
                order_revision: scope.order_revision
              }}
           else
             {:error, reason} -> Repo.rollback(reason)
           end
         end) do
      {:ok, page} -> {:ok, page}
      {:error, reason} when reason in [:stale_cursor, :not_found] -> {:error, reason}
      {:error, _reason} -> {:error, :infrastructure_failure}
    end
  rescue
    _error in [DBConnection.ConnectionError, Postgrex.Error] ->
      {:error, :infrastructure_failure}
  end

  @impl true
  def lookup_today_result(%{account_id: account_id}, mutation_id) do
    case SQL.query(
           Repo,
           """
           SELECT task_id, outcome, order_revision
           FROM today_order_receipts
           WHERE account_id = $1 AND mutation_id = $2
           """,
           [account_id, dump_uuid(mutation_id)]
         ) do
      {:ok, %{rows: [[task_id, "accepted", revision]]}} when not is_nil(task_id) ->
        {:ok,
         %{
           mutation_id: mutation_id,
           order_revision: revision,
           task_id: Ecto.UUID.load!(task_id)
         }}

      {:ok, %{rows: []}} ->
        {:error, :not_found}

      {:ok, %{rows: [[_task_id, _outcome, _revision]]}} ->
        {:error, :not_found}

      {:error, _reason} ->
        {:error, :infrastructure_failure}
    end
  rescue
    _error in [ArgumentError, DBConnection.ConnectionError, Postgrex.Error] ->
      {:error, :infrastructure_failure}
  end

  @impl true
  def move_today(
        %{account_id: account_id, accepted_at: accepted_at},
        %{
          task_id: task_id,
          direction: direction,
          expected_order_revision: expected_revision,
          mutation_id: mutation_id
        }
      ) do
    fingerprint =
      :crypto.hash(
        :sha256,
        :erlang.term_to_binary({task_id, direction, expected_revision}, [:deterministic])
      )

    case Repo.transact(fn repo ->
           with {:ok, timezone, order_revision} <- lock_today_scope(repo, account_id) do
             case today_move_replay(repo, account_id, mutation_id, fingerprint) do
               {:replay, result} ->
                 {:ok, result}

               :new ->
                 result =
                   execute_today_move(
                     repo,
                     account_id,
                     task_id,
                     direction,
                     expected_revision,
                     order_revision,
                     timezone,
                     accepted_at
                   )

                 case result do
                   {:error, :not_found} ->
                     Repo.rollback(:not_found)

                   {:error, :infrastructure_failure} ->
                     Repo.rollback(:infrastructure_failure)

                   terminal ->
                     persist_today_move_receipt(
                       repo,
                       account_id,
                       mutation_id,
                       task_id,
                       fingerprint,
                       terminal,
                       accepted_at
                     )

                     {:ok, terminal}
                 end

               :identity_reused ->
                 {:ok, {:error, :mutation_identity_reused}}
             end
           else
             {:error, reason} -> Repo.rollback(reason)
           end
         end) do
      {:ok, {:ok, result}} when is_map(result) ->
        {:ok, result}

      {:ok, {:error, reason}}
      when reason in [
             :mutation_identity_reused,
             :order_stale,
             :today_section_too_large
           ] ->
        {:error, reason}

      {:error, reason} when reason in [:order_stale, :not_found, :today_section_too_large] ->
        {:error, reason}

      {:error, _reason} ->
        {:error, :infrastructure_failure}
    end
  rescue
    _error in [DBConnection.ConnectionError, Postgrex.Error] ->
      {:error, :infrastructure_failure}
  end

  defp execute_today_move(
         repo,
         account_id,
         task_id,
         direction,
         expected_revision,
         order_revision,
         timezone,
         accepted_at
       ) do
    with :ok <- expected_order_revision(expected_revision, order_revision),
         {:ok, account_day} <- TaskDates.account_day(accepted_at, timezone),
         {:ok, section} <- today_section(repo, account_id, task_id, account_day),
         {:ok, task_ids} <- today_section_task_ids(repo, account_id, section, account_day),
         {:ok, moved_ids} <- move(task_ids, task_id, direction) do
      if moved_ids == task_ids do
        {:ok, %{order_revision: order_revision}}
      else
        persist_today_order(repo, account_id, section, moved_ids, accepted_at)

        %{rows: [[next_revision]]} =
          SQL.query!(
            repo,
            """
            UPDATE accounts
            SET today_order_revision = today_order_revision + 1, updated_at = $2
            WHERE id = $1
            RETURNING today_order_revision
            """,
            [account_id, accepted_at]
          )

        {:ok, %{order_revision: next_revision}}
      end
    end
  end

  defp today_move_replay(repo, account_id, mutation_id, fingerprint) do
    case SQL.query!(
           repo,
           """
           SELECT fingerprint, outcome, order_revision
           FROM today_order_receipts
           WHERE account_id = $1 AND mutation_id = $2
           """,
           [account_id, dump_uuid(mutation_id)]
         ).rows do
      [] -> :new
      [[^fingerprint, "accepted", revision]] -> {:replay, {:ok, %{order_revision: revision}}}
      [[^fingerprint, outcome, nil]] -> {:replay, {:error, String.to_existing_atom(outcome)}}
      [[_other, _outcome, _revision]] -> :identity_reused
    end
  end

  defp persist_today_move_receipt(
         repo,
         account_id,
         mutation_id,
         task_id,
         fingerprint,
         result,
         accepted_at
       ) do
    {outcome, revision} =
      case result do
        {:ok, %{order_revision: revision}} -> {"accepted", revision}
        {:error, reason} -> {Atom.to_string(reason), nil}
      end

    SQL.query!(
      repo,
      """
      INSERT INTO today_order_receipts (
        account_id, mutation_id, task_id, fingerprint, outcome, order_revision, inserted_at
      ) VALUES ($1, $2, $3, $4, $5, $6, $7)
      """,
      [
        account_id,
        dump_uuid(mutation_id),
        dump_uuid(task_id),
        fingerprint,
        outcome,
        revision,
        accepted_at
      ]
    )
  end

  defp account_scope(repo, account_id, accepted_at, view) do
    case SQL.query(
           repo,
           """
           SELECT timezone, inbox_view_revision, today_view_revision,
                  upcoming_view_revision, completed_view_revision, today_order_revision
           FROM accounts
           WHERE id = $1
           FOR SHARE
           """,
           [account_id]
         ) do
      {:ok, %{rows: [[timezone, inbox, today, upcoming, completed, order]]}} ->
        with {:ok, account_day} <- TaskDates.account_day(accepted_at, timezone) do
          {:ok,
           %{
             account_day: account_day,
             account_timezone: timezone,
             order_revision: if(view == :today, do: order, else: nil),
             view_revision:
               %{inbox: inbox, today: today, upcoming: upcoming, completed: completed}[view]
           }}
        end

      {:ok, %{rows: []}} ->
        {:error, :not_found}

      {:error, _reason} ->
        {:error, :infrastructure_failure}
    end
  end

  defp cursor_revision(nil, _scope), do: :ok

  defp cursor_revision(cursor, scope) do
    if cursor.view_revision == scope.view_revision and
         Map.get(cursor, :order_revision) == scope.order_revision,
       do: :ok,
       else: {:error, :stale_cursor}
  end

  defp add_revisions(nil, _scope), do: nil

  defp add_revisions(keyset, scope) do
    keyset
    |> Map.put(:view_revision, scope.view_revision)
    |> Map.put(:order_revision, scope.order_revision)
  end

  defp page(repo, account_id, :inbox, _scope, cursor, limit) do
    {predicate, keyset_params} =
      case cursor do
        nil ->
          {"", []}

        cursor ->
          {"AND (captured_at < $2 OR (captured_at = $2 AND id < $3))",
           [cursor.captured_at, dump_uuid(cursor.id)]}
      end

    limit_parameter = 2 + length(keyset_params)

    rows =
      SQL.query!(
        repo,
        """
        SELECT id, title, revision, captured_at, planned_on, deadline_on
        FROM tasks
        WHERE account_id = $1 AND inbox_state = 'inbox'
          AND completed_at IS NULL AND trashed_at IS NULL
        #{predicate}
        ORDER BY captured_at DESC, id DESC
        LIMIT $#{limit_parameter}
        """,
        [account_id] ++ keyset_params ++ [limit + 1]
      ).rows

    page_rows(rows, limit, &inbox_item/1, fn row ->
      %{captured_at: to_datetime(Enum.at(row, 3)), id: load_uuid(Enum.at(row, 0))}
    end)
  end

  defp page(repo, account_id, :today, scope, cursor, limit) do
    {predicate, keyset_params} = today_predicate(cursor)
    limit_parameter = 3 + length(keyset_params)

    rows =
      SQL.query!(
        repo,
        """
        WITH eligible AS (
          SELECT tasks.id, tasks.title, tasks.revision, tasks.captured_at,
                 tasks.planned_on, tasks.deadline_on,
                 CASE
                   WHEN tasks.planned_on < $2 OR tasks.deadline_on < $2 THEN 0
                   ELSE 1
                 END AS section_rank,
                 CASE
                   WHEN tasks.planned_on < $2 OR tasks.deadline_on < $2 THEN 'overdue'
                   ELSE 'today'
                 END AS section,
                 COALESCE(today_task_order.position, 2147483647) AS sort_position
          FROM tasks
          LEFT JOIN today_task_order
            ON today_task_order.account_id = tasks.account_id
           AND today_task_order.task_id = tasks.id
           AND today_task_order.section = CASE
             WHEN tasks.planned_on < $2 OR tasks.deadline_on < $2 THEN 'overdue'
             ELSE 'today'
           END
          WHERE tasks.account_id = $1 AND tasks.completed_at IS NULL
            AND tasks.trashed_at IS NULL
            AND (tasks.planned_on <= $2 OR tasks.deadline_on <= $2)
        )
        SELECT id, title, revision, captured_at, planned_on, deadline_on,
               section_rank, section, sort_position
        FROM eligible
        WHERE TRUE #{predicate}
        ORDER BY section_rank ASC, sort_position ASC, captured_at DESC, id DESC
        LIMIT $#{limit_parameter}
        """,
        [account_id, scope.account_day] ++ keyset_params ++ [limit + 1]
      ).rows

    page_rows(rows, limit, &today_item(&1, scope.account_day), &today_keyset/1)
  end

  defp page(repo, account_id, :upcoming, scope, cursor, limit) do
    {predicate, keyset_params} = upcoming_predicate(cursor)
    limit_parameter = 3 + length(keyset_params)

    rows =
      SQL.query!(
        repo,
        """
        WITH eligible AS (
          SELECT id, title, revision, captured_at, planned_on, deadline_on,
                 CASE
                   WHEN planned_on > $2 THEN planned_on
                   WHEN deadline_on > $2 THEN deadline_on
                 END AS group_on,
                 CASE WHEN planned_on > $2 THEN 'planned' ELSE 'deadline' END AS upcoming_reason
          FROM tasks
          WHERE account_id = $1 AND completed_at IS NULL AND trashed_at IS NULL
            AND (planned_on > $2 OR deadline_on > $2)
        )
        SELECT id, title, revision, captured_at, planned_on, deadline_on,
               group_on, upcoming_reason
        FROM eligible
        WHERE TRUE #{predicate}
        ORDER BY group_on ASC, captured_at DESC, id DESC
        LIMIT $#{limit_parameter}
        """,
        [account_id, scope.account_day] ++ keyset_params ++ [limit + 1]
      ).rows

    page_rows(rows, limit, &upcoming_item(&1, scope.account_day), &upcoming_keyset/1)
  end

  defp page(repo, account_id, :completed, scope, cursor, limit) do
    {predicate, keyset_params} =
      case cursor do
        nil ->
          {"", []}

        cursor ->
          {"AND (completed_at < $2 OR (completed_at = $2 AND id < $3))",
           [cursor.completed_at, dump_uuid(cursor.id)]}
      end

    limit_parameter = 2 + length(keyset_params)

    rows =
      SQL.query!(
        repo,
        """
        SELECT id, title, revision, captured_at, planned_on, deadline_on, completed_at
        FROM tasks
        WHERE account_id = $1 AND completed_at IS NOT NULL AND trashed_at IS NULL
        #{predicate}
        ORDER BY completed_at DESC, id DESC
        LIMIT $#{limit_parameter}
        """,
        [account_id] ++ keyset_params ++ [limit + 1]
      ).rows

    page_rows(rows, limit, &completed_item(&1, scope), fn row ->
      %{completed_at: to_datetime(Enum.at(row, 6)), id: load_uuid(Enum.at(row, 0))}
    end)
  end

  defp page_rows(rows, limit, item, keyset) do
    {selected, extra} = Enum.split(rows, limit)
    items = Enum.map(selected, item)

    next_keyset =
      case {selected, extra} do
        {[], _} -> nil
        {_, []} -> nil
        {page, [_ | _]} -> page |> List.last() |> keyset.()
      end

    {:ok, items, next_keyset}
  end

  defp inbox_item([id, title, revision, captured_at, planned_on, deadline_on]) do
    base_item(id, title, revision, captured_at, planned_on, deadline_on)
  end

  defp today_item(
         [id, title, revision, captured_at, planned_on, deadline_on, _rank, section, _position],
         account_day
       ) do
    classification = TaskDates.classify(planned_on, deadline_on, account_day)

    base_item(id, title, revision, captured_at, planned_on, deadline_on)
    |> Map.merge(%{
      reasons: Enum.map(classification.today_reasons, &Atom.to_string/1),
      section: section
    })
  end

  defp upcoming_item(
         [id, title, revision, captured_at, planned_on, deadline_on, group_on, reason],
         account_day
       ) do
    base_item(id, title, revision, captured_at, planned_on, deadline_on)
    |> Map.merge(%{
      group_on: Date.to_iso8601(group_on),
      reasons: all_date_reasons(planned_on, deadline_on, account_day),
      upcoming_reason: reason
    })
  end

  defp completed_item(
         [id, title, revision, captured_at, planned_on, deadline_on, completed_at],
         scope
       ) do
    completed_at = to_datetime(completed_at)

    completed_on =
      completed_at |> DateTime.shift_zone!(scope.account_timezone) |> DateTime.to_date()

    base_item(id, title, revision, captured_at, planned_on, deadline_on)
    |> Map.merge(%{
      completed_at: DateTime.to_iso8601(completed_at),
      completed_on: Date.to_iso8601(completed_on),
      section: if(completed_on == scope.account_day, do: "today", else: "earlier")
    })
  end

  defp base_item(id, title, revision, captured_at, planned_on, deadline_on) do
    %{
      captured_at: captured_at |> to_datetime() |> DateTime.to_iso8601(),
      deadline_on: optional_date(deadline_on),
      id: load_uuid(id),
      planned_on: optional_date(planned_on),
      revision: revision,
      title: title
    }
  end

  defp all_date_reasons(planned_on, deadline_on, account_day) do
    TaskDates.classify(planned_on, deadline_on, account_day).today_reasons
    |> Enum.map(&Atom.to_string/1)
    |> Kernel.++(future_reason("planned", planned_on, account_day))
    |> Kernel.++(future_reason("deadline", deadline_on, account_day))
  end

  defp future_reason(prefix, %Date{} = date, account_day) do
    if Date.after?(date, account_day), do: [prefix <> "_future"], else: []
  end

  defp future_reason(_prefix, _date, _account_day), do: []

  defp today_predicate(nil), do: {"", []}

  defp today_predicate(cursor) do
    {"""
     AND (
       section_rank > $3 OR
       (section_rank = $3 AND sort_position > $4) OR
       (section_rank = $3 AND sort_position = $4 AND captured_at < $5) OR
       (section_rank = $3 AND sort_position = $4 AND captured_at = $5 AND id < $6)
     )
     """, [cursor.section_rank, cursor.sort_position, cursor.captured_at, dump_uuid(cursor.id)]}
  end

  defp upcoming_predicate(nil), do: {"", []}

  defp upcoming_predicate(cursor) do
    {"""
     AND (
       group_on > $3 OR
       (group_on = $3 AND captured_at < $4) OR
       (group_on = $3 AND captured_at = $4 AND id < $5)
     )
     """, [cursor.group_on, cursor.captured_at, dump_uuid(cursor.id)]}
  end

  defp today_keyset(row) do
    %{
      captured_at: row |> Enum.at(3) |> to_datetime(),
      id: row |> Enum.at(0) |> load_uuid(),
      section_rank: Enum.at(row, 6),
      sort_position: Enum.at(row, 8)
    }
  end

  defp upcoming_keyset(row) do
    %{
      captured_at: row |> Enum.at(3) |> to_datetime(),
      group_on: Enum.at(row, 6),
      id: row |> Enum.at(0) |> load_uuid()
    }
  end

  defp lock_today_scope(repo, account_id) do
    case SQL.query(
           repo,
           "SELECT timezone, today_order_revision FROM accounts WHERE id = $1 FOR UPDATE",
           [account_id]
         ) do
      {:ok, %{rows: [[timezone, revision]]}} -> {:ok, timezone, revision}
      {:ok, %{rows: []}} -> {:error, :not_found}
      {:error, _reason} -> {:error, :infrastructure_failure}
    end
  end

  defp expected_order_revision(revision, revision), do: :ok
  defp expected_order_revision(_expected, _actual), do: {:error, :order_stale}

  defp today_section(repo, account_id, task_id, account_day) do
    case SQL.query(
           repo,
           """
           SELECT CASE
             WHEN planned_on < $3 OR deadline_on < $3 THEN 'overdue'
             ELSE 'today'
           END
           FROM tasks
           WHERE account_id = $1 AND id = $2
             AND completed_at IS NULL AND trashed_at IS NULL
             AND (planned_on <= $3 OR deadline_on <= $3)
           """,
           [account_id, dump_uuid(task_id), account_day]
         ) do
      {:ok, %{rows: [[section]]}} -> {:ok, section}
      {:ok, %{rows: []}} -> {:error, :not_found}
      {:error, _reason} -> {:error, :infrastructure_failure}
    end
  end

  defp today_section_task_ids(repo, account_id, section, account_day) do
    rows =
      SQL.query!(
        repo,
        """
        SELECT tasks.id
        FROM tasks
        LEFT JOIN today_task_order
          ON today_task_order.account_id = tasks.account_id
         AND today_task_order.task_id = tasks.id
         AND today_task_order.section = $2
        WHERE tasks.account_id = $1 AND tasks.completed_at IS NULL
          AND tasks.trashed_at IS NULL
          AND (tasks.planned_on <= $3 OR tasks.deadline_on <= $3)
          AND (CASE WHEN tasks.planned_on < $3 OR tasks.deadline_on < $3 THEN 'overdue'
                    ELSE 'today' END) = $2
        ORDER BY COALESCE(today_task_order.position, 2147483647),
                 tasks.captured_at DESC, tasks.id DESC
        LIMIT #{@maximum_today_section + 1}
        """,
        [account_id, section, account_day]
      ).rows

    if length(rows) > @maximum_today_section,
      do: {:error, :today_section_too_large},
      else: {:ok, Enum.map(rows, fn [id] -> load_uuid(id) end)}
  end

  defp move(ids, task_id, direction) do
    case Enum.find_index(ids, &(&1 == task_id)) do
      nil -> {:error, :not_found}
      index -> {:ok, swap(ids, index, direction)}
    end
  end

  defp swap(ids, 0, :earlier), do: ids
  defp swap(ids, index, :later) when index == length(ids) - 1, do: ids

  defp swap(ids, index, direction) do
    other = if direction == :earlier, do: index - 1, else: index + 1
    first = Enum.at(ids, index)
    second = Enum.at(ids, other)

    ids
    |> List.replace_at(index, second)
    |> List.replace_at(other, first)
  end

  defp persist_today_order(repo, account_id, section, task_ids, accepted_at) do
    SQL.query!(
      repo,
      "DELETE FROM today_task_order WHERE account_id = $1 AND section = $2",
      [account_id, section]
    )

    task_ids
    |> Enum.with_index(1)
    |> Enum.each(fn {task_id, position} ->
      SQL.query!(
        repo,
        """
        INSERT INTO today_task_order (
          account_id, task_id, section, position, inserted_at, updated_at
        ) VALUES ($1, $2, $3, $4, $5, $5)
        """,
        [account_id, dump_uuid(task_id), section, position, accepted_at]
      )
    end)
  end

  defp optional_date(nil), do: nil
  defp optional_date(%Date{} = date), do: Date.to_iso8601(date)

  defp dump_uuid(uuid) when is_binary(uuid) do
    case Ecto.UUID.cast(uuid) do
      {:ok, canonical} -> Ecto.UUID.dump!(canonical)
      :error -> uuid
    end
  end

  defp load_uuid(uuid), do: Ecto.UUID.load!(uuid)

  defp to_datetime(%DateTime{} = value), do: value

  defp to_datetime(%NaiveDateTime{} = value),
    do: DateTime.from_naive!(value, "Etc/UTC")
end
