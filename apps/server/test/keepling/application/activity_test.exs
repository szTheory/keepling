defmodule Keepling.Application.ActivityTest do
  use ExUnit.Case, async: true

  alias Keepling.Application.Activity

  @secret :crypto.strong_rand_bytes(32)
  @account_id Ecto.UUID.generate()
  @task_id Ecto.UUID.generate()
  @accepted_at ~U[2026-08-31 01:15:00.000000Z]

  test "activity cursors bind the full keyset, account, task, and view revision" do
    cursor =
      Activity.encode_cursor(
        %{
          accepted_at: @accepted_at,
          activity_id: 42,
          view_revision: 7
        },
        %{account_id: @account_id, cursor_secret: @secret, task_id: @task_id}
      )

    assert {:ok,
            %{accepted_at: @accepted_at, activity_id: 42, view_revision: 7}} =
             Activity.decode_cursor(cursor, %{
               account_id: @account_id,
               cursor_secret: @secret,
               task_id: @task_id
             })

    assert {:error, :invalid_cursor} =
             Activity.decode_cursor(cursor, %{
               account_id: Ecto.UUID.generate(),
               cursor_secret: @secret,
               task_id: @task_id
             })

    assert {:error, :invalid_cursor} =
             Activity.decode_cursor(cursor <> "tampered", %{
               account_id: @account_id,
               cursor_secret: @secret,
               task_id: @task_id
             })
  end
end

defmodule KeeplingWeb.ActivityBoundaryTest do
  use KeeplingWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL
  alias Keepling.Adapters.Postgres.CommandStore
  alias Keepling.Application.{Activity, Commands}
  alias Keepling.Repo

  @accepted_at ~U[2026-08-31 01:15:00.000000Z]

  setup %{conn: conn} do
    account_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()

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

    previous_seed = System.get_env("KEEPLING_E2E_SEED")
    System.put_env("KEEPLING_E2E_SEED", "phase-1")

    on_exit(fn ->
      if previous_seed,
        do: System.put_env("KEEPLING_E2E_SEED", previous_seed),
        else: System.delete_env("KEEPLING_E2E_SEED")
    end)

    login = conn |> trusted_request() |> post("/api/v1/test/session")

    %{
      account_id: account_id,
      conn: login,
      csrf_token: json_response(login, 200)["csrf_token"]
    }
  end

  test "accepted facts are newest-first, exact, closed, bounded, and paginated", %{
    account_id: account_id,
    conn: conn
  } do
    task_id = Ecto.UUID.generate()
    capture_mutation_id = Ecto.UUID.generate()
    edit_mutation_id = Ecto.UUID.generate()

    assert {:ok, %{status: 201}} =
             dispatch(
               account_id,
               %{
                 mutation_id: capture_mutation_id,
                 task_id: task_id,
                 title: "<img src=x onerror=alert(1)>",
                 type: :capture_task,
                 version: 1
               },
               @accepted_at
             )

    assert {:ok, %{status: 200}} =
             dispatch(
               account_id,
               %{
                 base_values: %{notes: "", title: "<img src=x onerror=alert(1)>"},
                 expected_revision: 1,
                 fields: %{notes: "plain <script>text</script>", title: "Accepted title"},
                 mutation_id: edit_mutation_id,
                 task_id: task_id,
                 type: :edit_task,
                 version: 1
               },
               DateTime.add(@accepted_at, 60, :second)
             )

    page_one =
      conn
      |> recycle()
      |> get("/api/v1/tasks/#{task_id}/activity?limit=1")
      |> json_response(200)

    assert %{
             "account_timezone" => "America/New_York",
             "items" => [
               %{
                 "accepted_at" => "2026-08-31T01:16:00.000000Z",
                 "actor" => %{"label" => "You", "principal" => "account_owner", "type" => "user"},
                 "client_kind" => "web",
                 "from_revision" => 1,
                 "mutation_id" => ^edit_mutation_id,
                 "outcome" => "accepted",
                 "recovery_state" => "not_available",
                 "to_revision" => 2,
                 "type" => "task_details_updated",
                 "version" => 1
               }
             ],
             "next_cursor" => cursor
           } = page_one

    assert is_binary(cursor)
    assert byte_size(cursor) <= 1024

    [details] = page_one["items"]

    assert details["changes"] == [
             %{
               "field" => "notes",
               "kind" => "text",
               "new" => "plain <script>text</script>",
               "old" => ""
             },
             %{
               "field" => "title",
               "kind" => "text",
               "new" => "Accepted title",
               "old" => "<img src=x onerror=alert(1)>"
             }
           ]

    page_two =
      conn
      |> recycle()
      |> get("/api/v1/tasks/#{task_id}/activity?limit=1&cursor=#{URI.encode_www_form(cursor)}")
      |> json_response(200)

    assert %{
             "items" => [
               %{
                 "changes" => [
                   %{
                     "field" => "title",
                     "kind" => "text",
                     "new" => "<img src=x onerror=alert(1)>",
                     "old" => nil
                   }
                 ],
                 "from_revision" => nil,
                 "mutation_id" => ^capture_mutation_id,
                 "to_revision" => 1,
                 "type" => "task_captured"
               }
             ],
             "next_cursor" => nil
           } = page_two

    assert %{rows: [[2, 2]]} =
             SQL.query!(
               Repo,
               """
               SELECT count(*), count(DISTINCT mutation_id)
               FROM task_activities
               WHERE account_id = $1 AND task_id = $2
               """,
               [account_id, Ecto.UUID.dump!(task_id)]
             )
  end

  test "cursor changes are explicit and task/account scope never leaks", %{
    account_id: account_id,
    conn: conn
  } do
    task_id = Ecto.UUID.generate()

    {:ok, _result} =
      dispatch(
        account_id,
        %{
          mutation_id: Ecto.UUID.generate(),
          task_id: task_id,
          title: "First",
          type: :capture_task,
          version: 1
        },
        @accepted_at
      )

    {:ok, _result} =
      dispatch(
        account_id,
        %{
          base_values: %{title: "First"},
          expected_revision: 1,
          fields: %{title: "Second"},
          mutation_id: Ecto.UUID.generate(),
          task_id: task_id,
          type: :edit_task,
          version: 1
        },
        DateTime.add(@accepted_at, 1, :second)
      )

    %{"next_cursor" => cursor} =
      conn
      |> recycle()
      |> get("/api/v1/tasks/#{task_id}/activity?limit=1")
      |> json_response(200)

    {:ok, _result} =
      dispatch(
        account_id,
        %{
          base_values: %{title: "Second"},
          expected_revision: 2,
          fields: %{title: "Third"},
          mutation_id: Ecto.UUID.generate(),
          task_id: task_id,
          type: :edit_task,
          version: 1
        },
        DateTime.add(@accepted_at, 2, :second)
      )

    stale =
      conn
      |> recycle()
      |> get("/api/v1/tasks/#{task_id}/activity?limit=1&cursor=#{URI.encode_www_form(cursor)}")

    assert %{
             "code" => "activity_cursor_stale",
             "recovery_action" => "refresh_activity"
           } = json_response(stale, 409)

    assert {:error, :not_found} =
             Activity.list_task(
               %{
                 account_id: Ecto.UUID.generate() |> Ecto.UUID.dump!(),
                 cursor_secret: String.duplicate("x", 32)
               },
               task_id,
               %{limit: 20},
               CommandStore
             )

    assert conn |> recycle() |> get("/api/v1/tasks/#{Ecto.UUID.generate()}/activity")
           |> json_response(404) == %{
             "code" => "task_not_found",
             "detail" => "Refresh the task before trying again.",
             "recovery_action" => "refresh_task",
             "retryable" => false,
             "status" => 404,
             "title" => "Task not found",
             "type" => "/problems/task_not_found"
           }
  end

  test "authentication failures are not task history", %{account_id: account_id} do
    task_id = Ecto.UUID.generate()

    {:ok, _result} =
      dispatch(
        account_id,
        %{
          mutation_id: Ecto.UUID.generate(),
          task_id: task_id,
          title: "Private",
          type: :capture_task,
          version: 1
        },
        @accepted_at
      )

    assert build_conn() |> get("/api/v1/tasks/#{task_id}/activity") |> response(401)

    assert %{rows: [[1]]} =
             SQL.query!(
               Repo,
               "SELECT count(*) FROM task_activities WHERE account_id = $1 AND task_id = $2",
               [account_id, Ecto.UUID.dump!(task_id)]
             )
  end

  defp dispatch(account_id, command, accepted_at) do
    Commands.dispatch(
      command,
      %{
        accepted_at: accepted_at,
        account_id: account_id,
        actor_type: "user",
        client_kind: "web"
      },
      CommandStore
    )
  end

  defp trusted_request(conn) do
    conn = %{
      conn
      | host: "www.example.com",
        req_headers: [
          {"host", "www.example.com"}
          | Enum.reject(conn.req_headers, fn {name, _value} -> name == "host" end)
        ]
    }

    put_req_header(conn, "origin", "http://www.example.com")
  end
end
