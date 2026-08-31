defmodule Keepling.Domain.EditTaskTest do
  use ExUnit.Case, async: true

  alias Keepling.Domain.Task

  @accepted_at ~U[2026-08-30 21:00:00.000000Z]

  test "storage-neutral vectors preserve unrelated accepted fields and expose overlaps" do
    vectors = editing_vectors()

    assert vectors["version"] == 1

    assert vectors["limits"] == %{
             "notes_normalization" => "preserve_plain_text",
             "notes_unicode_scalars" => 50_000,
             "title_normalization" => "outer_whitespace_trim",
             "title_unicode_scalars" => 512
           }

    for vector <- vectors["cases"] do
      task = task_from(vector["current"])
      command = atomize_command(vector["command"])

      case vector["result"]["outcome"] do
        "accepted" ->
          operation =
            if String.starts_with?(vector["name"], "clarify"),
              do: &Task.clarify/2,
              else: &Task.edit/2

          assert {:ok, updated, activity, :accepted} = operation.(task, command)
          assert updated.title == vector["result"]["title"]
          assert updated.notes == vector["result"]["notes"]
          assert Atom.to_string(updated.inbox_state) == vector["result"]["inbox_state"]
          assert updated.revision == vector["result"]["revision"]
          assert activity.to_revision == updated.revision

        "conflict" ->
          assert {:error, {:edit_conflict, affected}} = Task.edit(task, command)
          assert Enum.sort(affected) == vector["result"]["affected_fields"]
      end
    end
  end

  test "title is trimmed, notes are preserved, and validation is versioned" do
    task =
      task_from(%{
        "title" => "Before",
        "notes" => "line one\n",
        "inbox_state" => "inbox",
        "revision" => 1
      })

    assert Task.details_version() == 1
    assert Task.details_limits() == %{notes: 50_000, title: 512}

    assert {:ok, updated, activity, :accepted} =
             Task.edit(task, %{
               accepted_at: @accepted_at,
               expected_revision: 1,
               base_values: %{title: "Before", notes: "line one\n"},
               fields: %{title: "  After  ", notes: "  line two\n"}
             })

    assert updated.title == "After"
    assert updated.notes == "  line two\n"

    assert activity.changed_fields == %{
             "notes" => %{"from" => "line one\n", "to" => "  line two\n"},
             "title" => %{"from" => "Before", "to" => "After"}
           }

    assert {:error, :title_required} =
             Task.edit(task, edit_command(:title, "Before", "   "))

    assert {:error, :notes_too_long} =
             Task.edit(task, edit_command(:notes, "line one\n", String.duplicate("n", 50_001)))
  end

  test "ordinary edits preserve Inbox and only return_to_inbox is the inverse of clarify" do
    task =
      task_from(%{"title" => "Before", "notes" => "", "inbox_state" => "inbox", "revision" => 1})

    assert {:ok, edited, _, :accepted} =
             Task.edit(task, edit_command(:title, "Before", "After"))

    assert edited.inbox_state == :inbox

    assert {:ok, clarified, activity, :accepted} =
             Task.clarify(edited, %{
               accepted_at: @accepted_at,
               expected_revision: 2,
               base_values: %{},
               fields: %{}
             })

    assert clarified.inbox_state == :clarified
    assert activity.type == :task_clarified

    assert {:ok, returned, returned_activity, :accepted} =
             Task.return_to_inbox(clarified, %{
               accepted_at: @accepted_at,
               expected_revision: clarified.revision
             })

    assert returned.inbox_state == :inbox
    assert returned_activity.type == :task_returned_to_inbox
  end

  defp edit_command(field, base, requested) do
    %{
      accepted_at: @accepted_at,
      expected_revision: 1,
      base_values: %{field => base},
      fields: %{field => requested}
    }
  end

  defp task_from(current) do
    %Task{
      captured_at: ~U[2026-08-30 20:00:00.000000Z],
      id: "018d8b40-2f10-7b1a-9d71-263f4af77001",
      inbox_state: String.to_existing_atom(current["inbox_state"]),
      notes: current["notes"],
      revision: current["revision"],
      title: current["title"]
    }
  end

  defp atomize_command(command) do
    %{
      accepted_at: @accepted_at,
      base_values:
        Map.new(command["base_values"], fn {key, value} ->
          {String.to_existing_atom(key), value}
        end),
      expected_revision: command["expected_revision"],
      fields:
        Map.new(command["fields"], fn {key, value} -> {String.to_existing_atom(key), value} end)
    }
  end

  defp editing_vectors do
    path = Path.expand("../../../../../packages/contracts/vectors/editing.json", __DIR__)
    path |> File.read!() |> Jason.decode!()
  end
end

defmodule KeeplingWeb.TaskEditingBoundaryTest do
  use KeeplingWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL
  alias Keepling.Repo

  setup %{conn: conn} do
    account_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()
    now = ~U[2026-08-30 21:30:00.000000Z]

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
      if previous_seed,
        do: System.put_env("KEEPLING_E2E_SEED", previous_seed),
        else: System.delete_env("KEEPLING_E2E_SEED")
    end)

    origin = "http://www.example.com"

    login =
      conn
      |> trusted_request(origin)
      |> post("/api/v1/test/session")

    %{account_id: account_id, conn: login, csrf_token: json_response(login, 200)["csrf_token"]}
  end

  test "title and notes cross Phoenix and PostgreSQL with rebase, clarify, and return", %{
    account_id: account_id,
    conn: conn,
    csrf_token: csrf_token
  } do
    task_id = Ecto.UUID.generate()

    captured =
      command(conn, csrf_token, "/api/v1/commands/capture-task", %{
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "title" => "Call dentist",
        "version" => 1
      })

    assert %{"revision" => 1, "snapshot" => %{"notes" => "", "inbox_state" => "inbox"}} =
             json_response(captured, 201)

    edited =
      command(conn, csrf_token, "/api/v1/commands/edit-task", %{
        "base_values" => %{"notes" => ""},
        "expected_revision" => 1,
        "fields" => %{"notes" => "Ask about Wednesday"},
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "version" => 1
      })

    assert %{
             "revision" => 2,
             "snapshot" => %{
               "inbox_state" => "inbox",
               "notes" => "Ask about Wednesday",
               "title" => "Call dentist"
             }
           } = json_response(edited, 200)

    SQL.query!(
      Repo,
      """
      UPDATE tasks
      SET title = 'Call the dentist', revision = 3, updated_at = NOW()
      WHERE account_id = $1 AND id = $2
      """,
      [account_id, Ecto.UUID.dump!(task_id)]
    )

    rebased =
      command(conn, csrf_token, "/api/v1/commands/edit-task", %{
        "base_values" => %{"notes" => "Ask about Wednesday"},
        "expected_revision" => 2,
        "fields" => %{"notes" => "Ask about Friday"},
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "version" => 1
      })

    assert %{
             "revision" => 4,
             "snapshot" => %{"notes" => "Ask about Friday", "title" => "Call the dentist"}
           } = json_response(rebased, 200)

    clarified =
      command(conn, csrf_token, "/api/v1/commands/clarify-task", %{
        "base_values" => %{"title" => "Call the dentist"},
        "expected_revision" => 4,
        "fields" => %{"title" => "Book dentist"},
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "version" => 1
      })

    assert %{"revision" => 5, "snapshot" => %{"inbox_state" => "clarified"}} =
             json_response(clarified, 200)

    inbox = conn |> recycle() |> get("/api/v1/inbox")
    assert %{"tasks" => []} = json_response(inbox, 200)

    returned =
      command(conn, csrf_token, "/api/v1/commands/return-to-inbox", %{
        "expected_revision" => 5,
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "version" => 1
      })

    assert %{"revision" => 6, "snapshot" => %{"inbox_state" => "inbox"}} =
             json_response(returned, 200)

    inbox = conn |> recycle() |> get("/api/v1/inbox")

    assert %{"tasks" => [%{"id" => ^task_id, "notes" => "Ask about Friday"}]} =
             json_response(inbox, 200)
  end

  test "overlap conflict and structural failure are stable and do not bypass receipts", %{
    account_id: account_id,
    conn: conn,
    csrf_token: csrf_token
  } do
    task_id = Ecto.UUID.generate()

    command(conn, csrf_token, "/api/v1/commands/capture-task", %{
      "mutation_id" => Ecto.UUID.generate(),
      "task_id" => task_id,
      "title" => "Original",
      "version" => 1
    })

    SQL.query!(
      Repo,
      "UPDATE tasks SET title = 'Accepted elsewhere', revision = 2 WHERE account_id = $1 AND id = $2",
      [account_id, Ecto.UUID.dump!(task_id)]
    )

    mutation_id = Ecto.UUID.generate()

    request = %{
      "base_values" => %{"title" => "Original"},
      "expected_revision" => 1,
      "fields" => %{"title" => "My draft"},
      "mutation_id" => mutation_id,
      "task_id" => task_id,
      "version" => 1
    }

    conflict = command(conn, csrf_token, "/api/v1/commands/edit-task", request)

    assert %{
             "affected_fields" => ["title"],
             "code" => "task_edit_conflict",
             "current_revision" => 2
           } = json_response(conflict, 409)

    replay = command(conn, csrf_token, "/api/v1/commands/edit-task", request)
    assert json_response(replay, 409) == json_response(conflict, 409)

    receipts_before = receipt_count(account_id)

    invalid =
      command(
        conn,
        csrf_token,
        "/api/v1/commands/edit-task",
        Map.put(request, "unexpected", true)
      )

    assert %{"code" => "invalid_command"} = json_response(invalid, 400)
    assert receipt_count(account_id) == receipts_before
  end

  defp command(conn, csrf_token, path, body) do
    conn
    |> recycle()
    |> trusted_request("http://www.example.com")
    |> enforce_csrf()
    |> put_req_header("x-csrf-token", csrf_token)
    |> post(path, body)
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
