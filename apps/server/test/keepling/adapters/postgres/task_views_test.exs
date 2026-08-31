defmodule Keepling.Adapters.Postgres.TaskViewsTest do
  use ExUnit.Case, async: false

  import Keepling.ConcurrencyCase

  alias Ecto.Adapters.SQL
  alias Keepling.Adapters.Postgres.TaskViews, as: PostgresTaskViews
  alias Keepling.Application.TaskViews
  alias Keepling.Repo

  @cursor_secret String.duplicate("view-cursor-secret", 2)
  @accepted_at ~U[2026-08-31 04:30:00.000000Z]

  setup do
    account_id = insert_account("America/New_York")

    on_exit(fn ->
      with_connection(fn _backend_pid ->
        SQL.query!(Repo, "DELETE FROM accounts WHERE id = $1", [account_id])
      end)
    end)

    %{account_id: account_id}
  end

  test "Inbox uses the complete newest-first tuple and account-bound stale cursors", %{
    account_id: account_id
  } do
    captured_at = ~U[2026-08-31 04:00:00.000000Z]
    first_id = "ffffffff-ffff-4fff-8fff-ffffffffffff"
    second_id = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
    third_id = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"

    insert_task(account_id, third_id, "Third", captured_at)
    insert_task(account_id, first_id, "First", captured_at)
    insert_task(account_id, second_id, "Second", captured_at)

    context = context(account_id)

    assert {:ok,
            %{
              account_day: "2026-08-31",
              account_timezone: "America/New_York",
              items: [%{id: ^first_id}, %{id: ^second_id}],
              next_cursor: cursor,
              view: "inbox"
            }} = list_view(:inbox, context, %{limit: 2})

    refute cursor =~ first_id

    assert {:error, :invalid_cursor} =
             TaskViews.decode_cursor(
               cursor,
               %{context | account_id: Ecto.UUID.bingenerate()},
               :inbox
             )

    assert {:ok, %{items: [%{id: ^third_id}], next_cursor: nil}} =
             list_view(:inbox, context, %{cursor: cursor, limit: 2})

    bump_view_revision(account_id, "inbox_view_revision")

    assert {:error, :stale_cursor} =
             list_view(:inbox, context, %{cursor: cursor, limit: 2})
  end

  test "Today and Upcoming use the account day, fixed groups, and explicit independent reasons",
       %{
         account_id: account_id
       } do
    overdue_id = "11111111-1111-4111-8111-111111111111"
    today_id = "22222222-2222-4222-8222-222222222222"
    overlap_id = "33333333-3333-4333-8333-333333333333"

    insert_task(account_id, overdue_id, "Overdue planned", @accepted_at,
      planned_on: ~D[2026-08-30]
    )

    insert_task(account_id, today_id, "Due today", @accepted_at, deadline_on: ~D[2026-08-31])

    insert_task(account_id, overlap_id, "Today and later", @accepted_at,
      planned_on: ~D[2026-08-31],
      deadline_on: ~D[2026-09-02]
    )

    assert {:ok, today} =
             list_view(:today, context(account_id), %{limit: 20})

    assert Enum.map(today.items, &{&1.id, &1.section, &1.reasons}) == [
             {overdue_id, "overdue", ["planned_overdue"]},
             {overlap_id, "today", ["planned_today"]},
             {today_id, "today", ["deadline_today"]}
           ]

    assert today.order_revision == 1

    assert {:ok, upcoming} =
             list_view(:upcoming, context(account_id), %{limit: 20})

    assert Enum.map(upcoming.items, &{&1.id, &1.group_on, &1.upcoming_reason, &1.reasons}) == [
             {overlap_id, "2026-09-02", "deadline", ["planned_today", "deadline_future"]}
           ]
  end

  test "Completed is a deterministic account-timezone projection", %{account_id: account_id} do
    older_id = "44444444-4444-4444-8444-444444444444"
    newer_id = "55555555-5555-4555-8555-555555555555"
    same_instant = ~U[2026-08-31 03:59:00.000000Z]

    insert_task(account_id, older_id, "Older identity", @accepted_at, completed_at: same_instant)

    insert_task(account_id, newer_id, "Newer identity", @accepted_at, completed_at: same_instant)

    assert {:ok, completed} =
             list_view(:completed, context(account_id), %{limit: 20})

    assert Enum.map(completed.items, &{&1.id, &1.section, &1.completed_on}) == [
             {newer_id, "earlier", "2026-08-30"},
             {older_id, "earlier", "2026-08-30"}
           ]
  end

  test "concurrent Today moves have one revision winner and preserve unique positions", %{
    account_id: account_id
  } do
    first_id = "66666666-6666-4666-8666-666666666666"
    second_id = "77777777-7777-4777-8777-777777777777"
    third_id = "88888888-8888-4888-8888-888888888888"

    for {id, title} <- [{first_id, "First"}, {second_id, "Second"}, {third_id, "Third"}] do
      insert_task(account_id, id, title, @accepted_at, planned_on: ~D[2026-08-31])
    end

    barrier = start_barrier(2)

    moves =
      [
        %{task_id: first_id, direction: :earlier, expected_order_revision: 1},
        %{task_id: third_id, direction: :later, expected_order_revision: 1}
      ]
      |> Enum.map(fn command ->
        Task.async(fn ->
          with_connection(fn backend_pid ->
            :ok = await(barrier)
            {backend_pid, TaskViews.move_today(command, context(account_id), PostgresTaskViews)}
          end)
        end)
      end)
      |> Enum.map(&Task.await(&1, 10_000))

    assert moves |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> length() == 2

    assert Enum.sort(Enum.map(moves, &elem(&1, 1))) ==
             Enum.sort([{:ok, %{order_revision: 2}}, {:error, :order_stale}])

    assert %{rows: [[3, 3]]} =
             with_connection(fn _backend_pid ->
               SQL.query!(
                 Repo,
                 """
                 SELECT count(*), count(DISTINCT position)
                 FROM today_task_order
                 WHERE account_id = $1 AND section = 'today'
                 """,
                 [account_id]
               )
             end)
  end

  defp insert_account(timezone) do
    account_id = Ecto.UUID.bingenerate()

    with_connection(fn _backend_pid ->
      SQL.query!(
        Repo,
        """
        INSERT INTO accounts (
          id, singleton_key, password_hash, timezone, inserted_at, updated_at
        )
        VALUES ($1, TRUE, '$argon2id$test-fixture', $2, $3, $3)
        """,
        [account_id, timezone, @accepted_at]
      )
    end)

    account_id
  end

  defp insert_task(account_id, id, title, captured_at, options \\ []) do
    with_connection(fn _backend_pid ->
      SQL.query!(
        Repo,
        """
        INSERT INTO tasks (
          account_id, id, title, notes, inbox_state, revision, captured_at,
          planned_on, deadline_on, completed_at, inserted_at, updated_at
        )
        VALUES ($1, $2, $3, '', 'inbox', 1, $4, $5, $6, $7, $4, $4)
        """,
        [
          account_id,
          Ecto.UUID.dump!(id),
          title,
          captured_at,
          Keyword.get(options, :planned_on),
          Keyword.get(options, :deadline_on),
          Keyword.get(options, :completed_at)
        ]
      )
    end)
  end

  defp bump_view_revision(account_id, field) do
    with_connection(fn _backend_pid ->
      SQL.query!(Repo, "UPDATE accounts SET #{field} = #{field} + 1 WHERE id = $1", [account_id])
    end)
  end

  defp context(account_id) do
    %{account_id: account_id, accepted_at: @accepted_at, cursor_secret: @cursor_secret}
  end

  defp list_view(view, context, options) do
    with_connection(fn _backend_pid ->
      TaskViews.list(view, context, options, PostgresTaskViews)
    end)
  end
end
