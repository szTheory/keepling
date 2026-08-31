defmodule Keepling.Adapters.Postgres.IdempotencyTest do
  use ExUnit.Case, async: false

  import Keepling.ConcurrencyCase

  alias Ecto.Adapters.SQL
  alias Keepling.Adapters.Postgres.CommandStore
  alias Keepling.Application.Commands
  alias Keepling.Repo

  setup do
    account_id = insert_account()

    on_exit(fn ->
      with_connection(fn _backend_pid ->
        SQL.query!(Repo, "DELETE FROM accounts WHERE id = $1", [account_id])
      end)
    end)

    %{account_id: account_id}
  end

  test "independent first deliveries converge on one stored envelope", %{account_id: account_id} do
    mutation_id = Ecto.UUID.generate()
    task_id = Ecto.UUID.generate()
    accepted_at = ~U[2026-08-30 20:00:00.000000Z]

    command = %{
      mutation_id: mutation_id,
      task_id: task_id,
      title: "  Keep one exact result  ",
      type: :capture_task,
      version: 1
    }

    context = context(account_id, accepted_at)
    barrier = start_barrier(2)

    deliveries =
      for _delivery <- 1..2 do
        Task.async(fn ->
          with_connection(fn backend_pid ->
            :ok = await(barrier)
            {backend_pid, Commands.dispatch(command, context, CommandStore)}
          end)
        end)
      end
      |> Enum.map(&Task.await(&1, 10_000))

    assert deliveries |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> length() == 2

    assert [stored_envelope] =
             deliveries
             |> Enum.map(&elem(&1, 1))
             |> Enum.uniq()

    assert {:ok,
            %{
              status: 201,
              body: %{
                "mutation_id" => ^mutation_id,
                "outcome" => "accepted",
                "revision" => 1,
                "snapshot" => %{
                  "id" => ^task_id,
                  "inbox_state" => "inbox",
                  "title" => "Keep one exact result"
                },
                "task_id" => ^task_id,
                "warnings" => []
              }
            }} = stored_envelope

    semantic_replay = %{command | title: "Keep one exact result"}

    assert stored_envelope ==
             with_connection(fn _backend_pid ->
               Commands.dispatch(semantic_replay, context, CommandStore)
             end)

    changed_command = %{command | title: "Keep a different result"}

    assert {:ok,
            %{
              status: 409,
              body: %{
                "code" => "mutation_identity_reused",
                "recovery_action" => "use_original_command",
                "retryable" => false
              }
            }} =
             with_connection(fn _backend_pid ->
               Commands.dispatch(changed_command, context, CommandStore)
             end)

    assert %{activities: 1, receipts: 1, tasks: 1} == stored_counts(account_id)
  end

  test "authenticated semantic rejection is terminal and replayable", %{account_id: account_id} do
    mutation_id = Ecto.UUID.generate()

    command = %{
      mutation_id: mutation_id,
      task_id: Ecto.UUID.generate(),
      title: "   ",
      type: :capture_task,
      version: 1
    }

    context = context(account_id, ~U[2026-08-30 20:01:00.000000Z])

    rejected =
      with_connection(fn _backend_pid ->
        Commands.dispatch(command, context, CommandStore)
      end)

    assert {:ok,
            %{
              status: 422,
              body: %{
                "code" => "title_required",
                "recovery_action" => "edit_title",
                "retryable" => false
              }
            }} = rejected

    assert rejected ==
             with_connection(fn _backend_pid ->
               Commands.dispatch(command, context, CommandStore)
             end)

    assert {:ok, result} =
             with_connection(fn _backend_pid ->
               Commands.lookup_result(context, mutation_id, CommandStore)
             end)

    assert elem(rejected, 1) == result
    assert %{activities: 0, receipts: 1, tasks: 0} == stored_counts(account_id)
  end

  test "authoritative lookup is account scoped, includes clarified and completed tasks, and excludes Trash",
       %{account_id: account_id} do
    accepted_at = ~U[2026-08-30 20:05:00.000000Z]
    task_id = Ecto.UUID.generate()
    context = context(account_id, accepted_at)

    capture = %{
      mutation_id: Ecto.UUID.generate(),
      task_id: task_id,
      title: "Authoritative detail",
      type: :capture_task,
      version: 1
    }

    assert {:ok, %{body: %{"revision" => 1}}} =
             with_connection(fn _backend_pid ->
               Commands.dispatch(capture, context, CommandStore)
             end)

    clarify = %{
      base_values: %{},
      expected_revision: 1,
      fields: %{},
      mutation_id: Ecto.UUID.generate(),
      task_id: task_id,
      type: :clarify_task,
      version: 1
    }

    assert {:ok, %{body: %{"revision" => 2}}} =
             with_connection(fn _backend_pid ->
               Commands.dispatch(clarify, context, CommandStore)
             end)

    complete = %{
      expected_revision: 2,
      mutation_id: Ecto.UUID.generate(),
      task_id: task_id,
      type: :complete_task,
      version: 1
    }

    assert {:ok, %{body: %{"revision" => 3}}} =
             with_connection(fn _backend_pid ->
               Commands.dispatch(complete, context, CommandStore)
             end)

    assert {:ok, %{"id" => ^task_id, "inbox_state" => "clarified", "revision" => 3}} =
             with_connection(fn _backend_pid ->
               Commands.get_task(context, task_id, CommandStore)
             end)

    other_account_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()
    other_context = context(other_account_id, accepted_at)

    assert {:error, :not_found} =
             with_connection(fn _backend_pid ->
               Commands.get_task(other_context, task_id, CommandStore)
             end)

    trash = %{
      expected_revision: 3,
      mutation_id: Ecto.UUID.generate(),
      task_id: task_id,
      type: :trash_task,
      version: 1
    }

    assert {:ok, %{body: %{"revision" => 4}}} =
             with_connection(fn _backend_pid ->
               Commands.dispatch(trash, context, CommandStore)
             end)

    assert {:error, :not_found} =
             with_connection(fn _backend_pid ->
               Commands.get_task(context, task_id, CommandStore)
             end)
  end

  defp insert_account do
    account_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()
    now = ~U[2026-08-30 19:59:00.000000Z]

    with_connection(fn _backend_pid ->
      SQL.query!(
        Repo,
        """
        INSERT INTO accounts (
          id, singleton_key, password_hash, timezone, inserted_at, updated_at
        )
        VALUES ($1, TRUE, '$argon2id$test-fixture', 'Etc/UTC', $2, $2)
        """,
        [account_id, now]
      )
    end)

    account_id
  end

  defp stored_counts(account_id) do
    with_connection(fn _backend_pid ->
      %{rows: [[tasks, receipts, activities]]} =
        SQL.query!(
          Repo,
          """
          SELECT
            (SELECT count(*) FROM tasks WHERE account_id = $1),
            (SELECT count(*) FROM command_receipts WHERE account_id = $1),
            (SELECT count(*) FROM task_activities WHERE account_id = $1)
          """,
          [account_id]
        )

      %{activities: activities, receipts: receipts, tasks: tasks}
    end)
  end

  defp context(account_id, accepted_at) do
    %{
      accepted_at: accepted_at,
      account_id: account_id,
      actor_type: "user",
      client_kind: "web"
    }
  end
end

defmodule KeeplingWeb.UntrustedReceiptBoundaryTest do
  use KeeplingWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL
  alias Keepling.Repo

  setup do
    account_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()
    now = ~U[2026-08-30 20:02:00.000000Z]

    SQL.query!(
      Repo,
      """
      INSERT INTO accounts (
        id, singleton_key, password_hash, timezone, inserted_at, updated_at
      )
      VALUES ($1, TRUE, '$argon2id$test-fixture', 'Etc/UTC', $2, $2)
      """,
      [account_id, now]
    )

    previous_seed = System.get_env("KEEPLING_E2E_SEED")
    System.put_env("KEEPLING_E2E_SEED", "phase-1")

    on_exit(fn ->
      if previous_seed do
        System.put_env("KEEPLING_E2E_SEED", previous_seed)
      else
        System.delete_env("KEEPLING_E2E_SEED")
      end
    end)

    %{account_id: account_id}
  end

  test "pre-authentication, origin, CSRF, and structural failures create no receipts", %{
    account_id: account_id,
    conn: conn
  } do
    origin = "http://www.example.com"
    path = "/api/v1/commands/capture-task"

    command = %{
      "mutation_id" => Ecto.UUID.generate(),
      "task_id" => Ecto.UUID.generate(),
      "title" => "Never receipt an untrusted request",
      "version" => 1
    }

    unauthenticated =
      build_conn()
      |> trusted_request(origin)
      |> post(path, command)

    assert response(unauthenticated, 401)
    assert receipt_count(account_id) == 0

    login =
      conn
      |> trusted_request(origin)
      |> post("/api/v1/test/session")

    csrf_token = json_response(login, 200)["csrf_token"]

    untrusted_origin =
      login
      |> recycle()
      |> enforce_csrf()
      |> put_req_header("x-csrf-token", csrf_token)
      |> post(path, command)

    assert response(untrusted_origin, 403)
    assert receipt_count(account_id) == 0

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      login
      |> recycle()
      |> trusted_request(origin)
      |> enforce_csrf()
      |> post(path, command)
    end

    assert receipt_count(account_id) == 0

    invalid_shape =
      login
      |> recycle()
      |> trusted_request(origin)
      |> enforce_csrf()
      |> put_req_header("x-csrf-token", csrf_token)
      |> post(path, Map.delete(command, "task_id"))

    assert %{"code" => "invalid_command"} = json_response(invalid_shape, 400)
    assert receipt_count(account_id) == 0
  end

  defp receipt_count(account_id) do
    %{rows: [[count]]} =
      SQL.query!(Repo, "SELECT count(*) FROM command_receipts WHERE account_id = $1", [account_id])

    count
  end

  defp trusted_request(conn, origin) do
    conn = %{
      conn
      | host: "www.example.com",
        req_headers: [
          {"host", "www.example.com"}
          | Enum.reject(conn.req_headers, fn {name, _value} -> name == "host" end)
        ]
    }

    put_req_header(conn, "origin", origin)
  end

  defp enforce_csrf(conn),
    do: %{conn | private: Map.delete(conn.private, :plug_skip_csrf_protection)}
end
