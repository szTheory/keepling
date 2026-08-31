defmodule Keepling.Domain.OrganizationTest do
  use ExUnit.Case, async: true

  alias Keepling.Domain.Organization

  @accepted_at ~U[2026-08-30 22:00:00.000000Z]

  test "versioned name equivalence preserves display text and stable identity" do
    assert %{display_name: "Café", key: "café", version: 1} =
             Organization.normalize_name("  Cafe\u0301  ")

    assert %{key: "strasse", version: 1} = Organization.normalize_name("Straße")

    organization_id = Ecto.UUID.generate()

    assert {:ok, project, :accepted} =
             Organization.create(%{
               accepted_at: @accepted_at,
               kind: :project,
               name: "Home",
               organization_id: organization_id
             })

    assert project.id == organization_id
    assert project.display_name == "Home"
    assert project.name_key == "home"
    assert project.name_key_version == 1
    assert project.revision == 1

    assert {:ok, renamed, :accepted} =
             Organization.rename(project, %{accepted_at: @accepted_at, name: "Household"})

    assert renamed.id == project.id
    assert renamed.revision == 2
    assert renamed.display_name == "Household"
  end

  test "project and tag archive rules are explicit and collision-safe" do
    project = organization(:project, "Home")
    tag = organization(:tag, "Errand")

    assert {:error, {:project_archive_blocked, 2}} =
             Organization.archive(project, %{
               accepted_at: @accepted_at,
               active_unfinished_task_count: 2
             })

    assert project.archived_at == nil
    assert project.revision == 1

    assert {:ok, archived_tag, :accepted} =
             Organization.archive(tag, %{
               accepted_at: @accepted_at,
               active_unfinished_task_count: 20
             })

    assert archived_tag.archived_at == @accepted_at
    assert archived_tag.revision == 2

    assert {:error, :active_name_collision} =
             Organization.unarchive(archived_tag, %{
               accepted_at: @accepted_at,
               active_name_collision?: true
             })

    assert archived_tag.archived_at == @accepted_at
    assert archived_tag.revision == 2
  end

  test "task organization assignment uses stable IDs and narrow stale detection" do
    project_id = Ecto.UUID.generate()
    tag_id = Ecto.UUID.generate()

    current = %{
      id: Ecto.UUID.generate(),
      project_id: nil,
      revision: 4,
      tag_ids: []
    }

    command = %{
      accepted_at: @accepted_at,
      base_values: %{project_id: nil, tag_ids: []},
      expected_revision: 4,
      fields: %{project_id: project_id, tag_ids: [tag_id]}
    }

    assert {:ok, assigned, activity, :accepted} = Organization.assign_task(current, command)
    assert assigned.project_id == project_id
    assert assigned.tag_ids == [tag_id]
    assert assigned.revision == 5
    assert activity.type == :task_details_updated

    assert {:error, :invalid_expected_revision} =
             Organization.assign_task(current, %{command | expected_revision: 5})

    stale = %{
      command
      | base_values: %{project_id: nil, tag_ids: []},
        expected_revision: 4,
        fields: %{project_id: nil, tag_ids: []}
    }

    assert {:error, {:assignment_conflict, ["project_id", "tag_ids"]}} =
             Organization.assign_task(assigned, stale)
  end

  test "organization vectors pin validation and equivalence version" do
    vectors = organization_vectors()

    assert vectors["name_equivalence_version"] == Organization.name_equivalence_version()

    for vector <- vectors["name_equivalence"] do
      expected_display_name = vector["display_name"]
      expected_key = vector["key"]

      assert %{display_name: ^expected_display_name, key: ^expected_key, version: 1} =
               Organization.normalize_name(vector["input"])
    end

    assert {:error, :name_required} = Organization.normalize_name(" \n\t ")
    assert {:error, :name_too_long} = Organization.normalize_name(String.duplicate("a", 201))
  end

  defp organization(kind, name) do
    {:ok, organization, :accepted} =
      Organization.create(%{
        accepted_at: @accepted_at,
        kind: kind,
        name: name,
        organization_id: Ecto.UUID.generate()
      })

    organization
  end

  defp organization_vectors do
    path = Path.expand("../../../../../packages/contracts/vectors/organizations.json", __DIR__)
    path |> File.read!() |> Jason.decode!()
  end
end

defmodule KeeplingWeb.OrganizationBoundaryTest do
  use KeeplingWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL
  alias Keepling.Adapters.Postgres.CommandStore
  alias Keepling.Application.Commands
  alias Keepling.Repo

  setup %{conn: conn} do
    account_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()
    now = ~U[2026-08-30 22:15:00.000000Z]

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

    login =
      conn
      |> trusted_request()
      |> post("/api/v1/test/session")

    %{
      account_id: account_id,
      conn: login,
      csrf_token: json_response(login, 200)["csrf_token"]
    }
  end

  test "stable organization commands cross Phoenix and PostgreSQL without task revision churn", %{
    account_id: account_id,
    conn: conn,
    csrf_token: csrf_token
  } do
    project_id = Ecto.UUID.generate()
    tag_id = Ecto.UUID.generate()
    task_id = Ecto.UUID.generate()

    assert %{"organization_id" => ^project_id, "revision" => 1} =
             conn
             |> create_organization(csrf_token, project_id, "project", "Home")
             |> json_response(201)

    assert %{"organization_id" => ^tag_id, "revision" => 1} =
             conn
             |> create_organization(csrf_token, tag_id, "tag", "Errand")
             |> json_response(201)

    assert %{"revision" => 1} =
             conn
             |> command(csrf_token, "/api/v1/commands/capture-task", %{
               "mutation_id" => Ecto.UUID.generate(),
               "task_id" => task_id,
               "title" => "Buy batteries",
               "version" => 1
             })
             |> json_response(201)

    assigned =
      command(conn, csrf_token, "/api/v1/commands/assign-task-organizations", %{
        "base_values" => %{"project_id" => nil, "tag_ids" => []},
        "expected_revision" => 1,
        "fields" => %{"project_id" => project_id, "tag_ids" => [tag_id]},
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "version" => 1
      })

    assert %{
             "revision" => 2,
             "snapshot" => %{
               "project" => %{"id" => ^project_id, "name" => "Home"},
               "tags" => [%{"id" => ^tag_id, "name" => "Errand"}]
             }
           } = json_response(assigned, 200)

    renamed =
      command(conn, csrf_token, "/api/v1/commands/rename-organization", %{
        "expected_revision" => 1,
        "mutation_id" => Ecto.UUID.generate(),
        "name" => "Household",
        "organization_id" => project_id,
        "version" => 1
      })

    assert %{
             "organization_id" => ^project_id,
             "revision" => 2,
             "snapshot" => %{"name" => "Household"}
           } = json_response(renamed, 200)

    assert %{rows: [[2]]} =
             SQL.query!(
               Repo,
               "SELECT revision FROM tasks WHERE account_id = $1 AND id = $2",
               [account_id, Ecto.UUID.dump!(task_id)]
             )

    inbox = conn |> recycle() |> get("/api/v1/inbox")

    assert %{
             "tasks" => [
               %{
                 "id" => ^task_id,
                 "project" => %{"id" => ^project_id, "name" => "Household"},
                 "revision" => 2
               }
             ]
           } = json_response(inbox, 200)
  end

  test "project archive blockers and tag archive history are exact", %{
    conn: conn,
    csrf_token: csrf_token
  } do
    project_id = Ecto.UUID.generate()
    tag_id = Ecto.UUID.generate()
    task_id = Ecto.UUID.generate()

    create_organization(conn, csrf_token, project_id, "project", "Home")
    create_organization(conn, csrf_token, tag_id, "tag", "Errand")

    command(conn, csrf_token, "/api/v1/commands/capture-task", %{
      "mutation_id" => Ecto.UUID.generate(),
      "task_id" => task_id,
      "title" => "Buy batteries",
      "version" => 1
    })

    command(conn, csrf_token, "/api/v1/commands/assign-task-organizations", %{
      "base_values" => %{"project_id" => nil, "tag_ids" => []},
      "expected_revision" => 1,
      "fields" => %{"project_id" => project_id, "tag_ids" => [tag_id]},
      "mutation_id" => Ecto.UUID.generate(),
      "task_id" => task_id,
      "version" => 1
    })

    blocked =
      command(conn, csrf_token, "/api/v1/commands/archive-organization", %{
        "expected_revision" => 1,
        "mutation_id" => Ecto.UUID.generate(),
        "organization_id" => project_id,
        "version" => 1
      })

    assert %{"active_unfinished_task_count" => 1, "code" => "project_archive_blocked"} =
             json_response(blocked, 409)

    archived =
      command(conn, csrf_token, "/api/v1/commands/archive-organization", %{
        "expected_revision" => 1,
        "mutation_id" => Ecto.UUID.generate(),
        "organization_id" => tag_id,
        "version" => 1
      })

    assert %{"snapshot" => %{"archived" => true}, "revision" => 2} =
             json_response(archived, 200)

    assert %{"tasks" => [%{"tags" => [%{"id" => ^tag_id, "archived" => true}]}]} =
             conn |> recycle() |> get("/api/v1/inbox") |> json_response(200)

    assert %{"organizations" => organizations} =
             conn |> recycle() |> get("/api/v1/organizations") |> json_response(200)

    assert Enum.find(organizations, &(&1["id"] == tag_id))["assignable"] == false
  end

  test "unarchive collision, stale assignment replay, and cross-account probes change nothing", %{
    account_id: account_id,
    conn: conn,
    csrf_token: csrf_token
  } do
    archived_tag_id = Ecto.UUID.generate()
    active_tag_id = Ecto.UUID.generate()
    project_id = Ecto.UUID.generate()
    task_id = Ecto.UUID.generate()

    create_organization(conn, csrf_token, archived_tag_id, "tag", "Waiting")

    command(conn, csrf_token, "/api/v1/commands/archive-organization", %{
      "expected_revision" => 1,
      "mutation_id" => Ecto.UUID.generate(),
      "organization_id" => archived_tag_id,
      "version" => 1
    })

    create_organization(conn, csrf_token, active_tag_id, "tag", "waiting")
    create_organization(conn, csrf_token, project_id, "project", "Home")

    collision =
      command(conn, csrf_token, "/api/v1/commands/unarchive-organization", %{
        "expected_revision" => 2,
        "mutation_id" => Ecto.UUID.generate(),
        "organization_id" => archived_tag_id,
        "version" => 1
      })

    assert %{"code" => "active_organization_name_collision"} = json_response(collision, 409)

    command(conn, csrf_token, "/api/v1/commands/capture-task", %{
      "mutation_id" => Ecto.UUID.generate(),
      "task_id" => task_id,
      "title" => "Pack",
      "version" => 1
    })

    command(conn, csrf_token, "/api/v1/commands/assign-task-organizations", %{
      "base_values" => %{"project_id" => nil, "tag_ids" => []},
      "expected_revision" => 1,
      "fields" => %{"project_id" => project_id, "tag_ids" => []},
      "mutation_id" => Ecto.UUID.generate(),
      "task_id" => task_id,
      "version" => 1
    })

    stale_mutation_id = Ecto.UUID.generate()

    stale_request = %{
      "base_values" => %{"project_id" => nil, "tag_ids" => []},
      "expected_revision" => 1,
      "fields" => %{"project_id" => nil, "tag_ids" => []},
      "mutation_id" => stale_mutation_id,
      "task_id" => task_id,
      "version" => 1
    }

    stale = command(conn, csrf_token, "/api/v1/commands/assign-task-organizations", stale_request)

    assert %{"affected_fields" => ["project_id"], "code" => "task_assignment_conflict"} =
             json_response(stale, 409)

    replay =
      command(conn, csrf_token, "/api/v1/commands/assign-task-organizations", stale_request)

    assert json_response(replay, 409) == json_response(stale, 409)

    other_account_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()

    assert {:ok, []} =
             Commands.list_organizations(%{account_id: other_account_id}, CommandStore)

    assert {:error, :not_found} =
             Commands.lookup_result(
               %{account_id: other_account_id},
               stale_mutation_id,
               CommandStore
             )

    assert %{rows: [["Home"]]} =
             SQL.query!(
               Repo,
               "SELECT display_name FROM organizations WHERE account_id = $1 AND id = $2",
               [account_id, Ecto.UUID.dump!(project_id)]
             )
  end

  defp create_organization(conn, csrf_token, organization_id, kind, name) do
    command(conn, csrf_token, "/api/v1/commands/create-organization", %{
      "kind" => kind,
      "mutation_id" => Ecto.UUID.generate(),
      "name" => name,
      "organization_id" => organization_id,
      "version" => 1
    })
  end

  defp command(conn, csrf_token, path, body) do
    conn
    |> recycle()
    |> trusted_request()
    |> enforce_csrf()
    |> put_req_header("x-csrf-token", csrf_token)
    |> post(path, body)
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

  defp enforce_csrf(conn),
    do: %{conn | private: Map.delete(conn.private, :plug_skip_csrf_protection)}
end
