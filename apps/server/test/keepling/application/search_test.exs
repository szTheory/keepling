defmodule Keepling.Application.SearchTest do
  use ExUnit.Case, async: false

  import Keepling.ConcurrencyCase

  alias Ecto.Adapters.SQL
  alias Keepling.Adapters.Postgres.Search, as: PostgresSearch
  alias Keepling.Application.Search
  alias Keepling.Repo

  @cursor_secret String.duplicate("search-cursor-secret", 2)
  @accepted_at ~U[2026-08-31 04:30:00.000000Z]

  setup do
    account_id = insert_account()

    on_exit(fn ->
      with_connection(fn _backend_pid ->
        SQL.query!(Repo, "DELETE FROM accounts WHERE id = $1", [account_id])
      end)
    end)

    %{account_id: account_id}
  end

  test "matches title or notes, orders newest-first, and caps at the default limit", %{
    account_id: account_id
  } do
    milk_id = "11111111-1111-4111-8111-111111111111"
    notes_id = "22222222-2222-4222-8222-222222222222"
    unrelated_id = "33333333-3333-4333-8333-333333333333"

    insert_task(account_id, milk_id, "Buy milk", "", ~U[2026-08-31 04:00:00.000000Z])

    insert_task(
      account_id,
      notes_id,
      "Groceries",
      "remember milk and eggs",
      ~U[2026-08-31 04:01:00.000000Z]
    )

    insert_task(account_id, unrelated_id, "Book flight", "", ~U[2026-08-31 04:02:00.000000Z])

    assert {:ok, %{items: items, next_cursor: nil}} =
             search(context(account_id), "milk", %{limit: 20})

    assert Enum.map(items, & &1.id) == [notes_id, milk_id]
  end

  test "a limit above the maximum is clamped, not rejected", %{account_id: account_id} do
    for index <- 1..5 do
      id = mutation_uuid(index)

      insert_task(account_id, id, "Milk run #{index}", "", DateTime.add(@accepted_at, index))
    end

    assert {:ok, %{items: items}} = search(context(account_id), "milk", %{limit: 500})
    assert length(items) == 5
  end

  test "pages forward without repeating or skipping while unrelated tasks are inserted", %{
    account_id: account_id
  } do
    first_id = "44444444-4444-4444-8444-444444444444"
    second_id = "55555555-5555-4555-8555-555555555555"
    third_id = "66666666-6666-4666-8666-666666666666"

    insert_task(account_id, first_id, "Milk one", "", ~U[2026-08-31 04:00:00.000000Z])
    insert_task(account_id, second_id, "Milk two", "", ~U[2026-08-31 04:01:00.000000Z])
    insert_task(account_id, third_id, "Milk three", "", ~U[2026-08-31 04:02:00.000000Z])

    assert {:ok, %{items: [%{id: ^third_id}], next_cursor: cursor}} =
             search(context(account_id), "milk", %{limit: 1})

    refute cursor =~ third_id

    insert_task(
      account_id,
      "77777777-7777-4777-8777-777777777777",
      "Milk zero, inserted after paging began",
      "",
      ~U[2026-08-31 04:03:00.000000Z]
    )

    assert {:ok, %{items: [%{id: ^second_id}], next_cursor: cursor2}} =
             search(context(account_id), "milk", %{cursor: cursor, limit: 1})

    assert {:ok, %{items: [%{id: ^first_id}], next_cursor: nil}} =
             search(context(account_id), "milk", %{cursor: cursor2, limit: 1})
  end

  test "a cursor issued for one query decodes to an error under a different query", %{
    account_id: account_id
  } do
    id = "88888888-8888-4888-8888-888888888888"
    other_id = "99999999-9999-4999-8999-999999999999"

    insert_task(account_id, id, "Milk", "", ~U[2026-08-31 04:00:00.000000Z])
    insert_task(account_id, other_id, "Milk two", "", ~U[2026-08-31 04:01:00.000000Z])

    assert {:ok, %{next_cursor: cursor}} = search(context(account_id), "milk", %{limit: 1})
    assert is_binary(cursor)

    assert {:error, :invalid_cursor} = Search.decode_cursor(cursor, context(account_id), "bread")
  end

  test "a cursor issued for one account decodes to an error under another account", %{
    account_id: account_id
  } do
    id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    other_id = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"

    insert_task(account_id, id, "Milk", "", ~U[2026-08-31 04:00:00.000000Z])
    insert_task(account_id, other_id, "Milk two", "", ~U[2026-08-31 04:01:00.000000Z])

    assert {:ok, %{next_cursor: cursor}} = search(context(account_id), "milk", %{limit: 1})

    assert {:error, :invalid_cursor} =
             Search.decode_cursor(
               cursor,
               %{context(account_id) | account_id: Ecto.UUID.bingenerate()},
               "milk"
             )
  end

  test "a cursor with a flipped byte decodes to the same opaque error as a malformed one", %{
    account_id: account_id
  } do
    id = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
    other_id = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"

    insert_task(account_id, id, "Milk", "", ~U[2026-08-31 04:00:00.000000Z])
    insert_task(account_id, other_id, "Milk two", "", ~U[2026-08-31 04:01:00.000000Z])

    assert {:ok, %{next_cursor: cursor}} = search(context(account_id), "milk", %{limit: 1})

    flipped =
      cursor
      |> Base.url_decode64!(padding: false)
      |> flip_last_byte()
      |> Base.url_encode64(padding: false)

    assert {:error, :invalid_cursor} = Search.decode_cursor(flipped, context(account_id), "milk")

    assert {:error, :invalid_cursor} =
             Search.decode_cursor("not-a-valid-cursor", context(account_id), "milk")
  end

  test "trashed tasks are excluded; completed tasks are included and marked", %{
    account_id: account_id
  } do
    active_id = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
    completed_id = "ffffffff-ffff-4fff-8fff-ffffffffffff"
    trashed_id = "12345678-1234-4234-8234-123456789abc"

    insert_task(account_id, active_id, "Milk one", "", ~U[2026-08-31 04:00:00.000000Z])

    insert_task(
      account_id,
      completed_id,
      "Milk two",
      "",
      ~U[2026-08-31 04:01:00.000000Z],
      completed_at: ~U[2026-08-31 04:02:00.000000Z]
    )

    insert_task(
      account_id,
      trashed_id,
      "Milk three",
      "",
      ~U[2026-08-31 04:03:00.000000Z],
      trashed_at: ~U[2026-08-31 04:04:00.000000Z]
    )

    assert {:ok, %{items: items}} = search(context(account_id), "milk", %{limit: 20})

    assert Enum.map(items, &{&1.id, &1.completed}) == [
             {completed_id, true},
             {active_id, false}
           ]
  end

  test "an empty or whitespace-only query term returns an empty page", %{account_id: account_id} do
    insert_task(
      account_id,
      "23456789-1234-4234-8234-123456789abc",
      "Any task at all",
      "",
      ~U[2026-08-31 04:00:00.000000Z]
    )

    assert {:ok, %{items: [], next_cursor: nil}} = search(context(account_id), "", %{limit: 20})

    assert {:ok, %{items: [], next_cursor: nil}} =
             search(context(account_id), "   ", %{limit: 20})
  end

  defp flip_last_byte(binary) do
    prefix_size = byte_size(binary) - 1
    <<prefix::binary-size(^prefix_size), last>> = binary
    <<prefix::binary, Bitwise.bxor(last, 1)>>
  end

  defp insert_account do
    account_id = Ecto.UUID.bingenerate()

    with_connection(fn _backend_pid ->
      SQL.query!(
        Repo,
        """
        INSERT INTO accounts (
          id, singleton_key, password_hash, timezone, inserted_at, updated_at
        )
        VALUES ($1, TRUE, '$argon2id$test-fixture', 'America/New_York', $2, $2)
        """,
        [account_id, @accepted_at]
      )
    end)

    account_id
  end

  defp insert_task(account_id, id, title, notes, captured_at, options \\ []) do
    with_connection(fn _backend_pid ->
      SQL.query!(
        Repo,
        """
        INSERT INTO tasks (
          account_id, id, title, notes, inbox_state, revision, captured_at,
          completed_at, trashed_at, inserted_at, updated_at
        )
        VALUES ($1, $2, $3, $4, 'inbox', 1, $5, $6, $7, $5, $5)
        """,
        [
          account_id,
          Ecto.UUID.dump!(id),
          title,
          notes,
          captured_at,
          Keyword.get(options, :completed_at),
          Keyword.get(options, :trashed_at)
        ]
      )
    end)
  end

  defp context(account_id) do
    %{account_id: account_id, cursor_secret: @cursor_secret}
  end

  defp search(context, term, options) do
    with_connection(fn _backend_pid ->
      Search.query(context, term, options, PostgresSearch)
    end)
  end

  defp mutation_uuid(index),
    do: "00000000-0000-4000-8000-#{index |> Integer.to_string() |> String.pad_leading(12, "0")}"
end
