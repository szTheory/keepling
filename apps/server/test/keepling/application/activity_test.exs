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

    assert {:ok, %{accepted_at: @accepted_at, activity_id: 42, view_revision: 7}} =
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

  test "storage-neutral vectors and the application contract share one closed vocabulary" do
    path = Path.expand("../../../../../packages/contracts/vectors/activity.json", __DIR__)
    vectors = path |> File.read!() |> Jason.decode!()

    assert vectors["activity_version"] == 1
    assert vectors["types"] == Activity.activity_types()
    assert vectors["cursor"]["maximum_page_size"] == 50
    assert vectors["retention"] == "account_lifetime"

    assert vectors["actors"]["user"] == %{
             "label" => "You",
             "principal" => "account_owner",
             "type" => "user"
           }

    assert vectors["actors"]["agent"]["principal"] == "authorized_grant"
    assert vectors["actors"]["agent"]["type"] == "agent"
    assert vectors["actors"]["agent"]["label_max_chars"] == 200
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
                 "recovery_state" => "available",
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
                     "field" => "inbox_state",
                     "kind" => "state",
                     "new" => "inbox",
                     "old" => nil
                   },
                   %{
                     "field" => "notes",
                     "kind" => "text",
                     "new" => "",
                     "old" => nil
                   },
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

    assert conn
           |> recycle()
           |> get("/api/v1/tasks/#{Ecto.UUID.generate()}/activity")
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

  test "organization deltas keep stable IDs while projecting current archived labels", %{
    account_id: account_id
  } do
    task_id = Ecto.UUID.generate()
    tag_id = Ecto.UUID.generate()

    {:ok, %{status: 201}} =
      dispatch(
        account_id,
        %{
          kind: :tag,
          mutation_id: Ecto.UUID.generate(),
          name: "Errand",
          organization_id: tag_id,
          type: :create_organization,
          version: 1
        },
        @accepted_at
      )

    {:ok, %{status: 201}} =
      dispatch(
        account_id,
        %{
          mutation_id: Ecto.UUID.generate(),
          task_id: task_id,
          title: "Buy batteries",
          type: :capture_task,
          version: 1
        },
        DateTime.add(@accepted_at, 1, :second)
      )

    {:ok, %{status: 200}} =
      dispatch(
        account_id,
        %{
          base_values: %{project_id: nil, tag_ids: []},
          expected_revision: 1,
          fields: %{project_id: nil, tag_ids: [tag_id]},
          mutation_id: Ecto.UUID.generate(),
          task_id: task_id,
          type: :assign_task_organizations,
          version: 1
        },
        DateTime.add(@accepted_at, 2, :second)
      )

    {:ok, %{status: 200}} =
      dispatch(
        account_id,
        %{
          expected_revision: 1,
          mutation_id: Ecto.UUID.generate(),
          organization_id: tag_id,
          type: :archive_organization,
          version: 1
        },
        DateTime.add(@accepted_at, 3, :second)
      )

    assert {:ok, %{items: [assignment | _earlier]}} =
             Activity.list_task(
               %{account_id: account_id, cursor_secret: String.duplicate("x", 32)},
               task_id,
               %{limit: 20},
               CommandStore
             )

    assert [%{field: "tags", kind: "organizations", new: [tag], old: []}] =
             assignment.changes

    assert tag == %{"archived" => true, "id" => tag_id, "name" => "Errand"}
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

  test "the activity feed interleaves agent and human facts in one ordered stream", %{
    account_id: account_id,
    conn: conn
  } do
    task_id = Ecto.UUID.generate()

    {:ok, %{status: 201}} =
      dispatch(
        account_id,
        %{
          mutation_id: Ecto.UUID.generate(),
          task_id: task_id,
          title: "Captured by a human",
          type: :capture_task,
          version: 1
        },
        @accepted_at
      )

    {:ok, %{status: 200}} =
      dispatch_agent(
        account_id,
        %{
          base_values: %{notes: "", title: "Captured by a human"},
          expected_revision: 1,
          fields: %{notes: "", title: "Edited by an agent"},
          mutation_id: Ecto.UUID.generate(),
          task_id: task_id,
          type: :edit_task,
          version: 1
        },
        DateTime.add(@accepted_at, 1, :second)
      )

    {:ok, %{status: 200}} =
      dispatch(
        account_id,
        %{
          expected_revision: 1,
          mutation_id: Ecto.UUID.generate(),
          task_id: task_id,
          type: :complete_task,
          version: 1
        },
        DateTime.add(@accepted_at, 2, :second)
      )

    page =
      conn
      |> recycle()
      |> get("/api/v1/tasks/#{task_id}/activity?limit=10")
      |> json_response(200)

    actors = Enum.map(page["items"], & &1["actor"])

    assert actors == [
             %{"label" => "You", "principal" => "account_owner", "type" => "user"},
             %{"label" => "Test Agent Grant", "principal" => "authorized_grant", "type" => "agent"},
             %{"label" => "You", "principal" => "account_owner", "type" => "user"}
           ]

    client_kinds = Enum.map(page["items"], & &1["client_kind"])
    assert client_kinds == ["web", "mcp", "web"]
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

  defp dispatch_agent(account_id, command, accepted_at) do
    Commands.dispatch(
      command,
      %{
        accepted_at: accepted_at,
        account_id: account_id,
        actor_label: "Test Agent Grant",
        actor_principal: "authorized_grant",
        actor_type: "agent",
        client_kind: "mcp"
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
