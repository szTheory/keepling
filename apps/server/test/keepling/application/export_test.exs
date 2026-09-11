defmodule Keepling.Application.ExportTest do
  use ExUnit.Case, async: false

  import Keepling.ConcurrencyCase

  alias Ecto.Adapters.SQL
  alias Keepling.Adapters.Postgres.CommandStore
  alias Keepling.Adapters.Postgres.Export, as: PostgresExport
  alias Keepling.Application.{AgentScope, Commands, Export, Ops}
  alias Keepling.Repo

  @accepted_at ~U[2026-09-11 12:00:00.000000Z]

  setup do
    account_id = insert_account("America/New_York")

    destination_dir =
      Path.join(
        System.tmp_dir!(),
        "keepling-export-test-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(destination_dir)

    on_exit(fn ->
      File.rm_rf!(destination_dir)

      with_connection(fn _pid ->
        SQL.query!(Repo, "DELETE FROM account_security_audits", [])
        SQL.query!(Repo, "DELETE FROM accounts WHERE id = $1", [account_id])
      end)
    end)

    %{account_id: account_id, destination_dir: destination_dir}
  end

  test "the agent scope list contains no export scope" do
    refute "export" in AgentScope.scopes()
  end

  test "an empty account exports every entity file present, empty except the singleton account-settings row",
       %{destination_dir: destination_dir} do
    assert {:ok, result} = run_export(destination_dir)

    data_entries = Enum.filter(result.files, &String.starts_with?(&1["path"], "data/"))
    assert length(data_entries) == 8

    entries = bundle_entries(result.bundle_path)

    for %{"path" => path, "rowCount" => row_count} <- data_entries do
      case path do
        "data/account-settings.ndjson" ->
          # The account itself always exists -- exactly one settings row,
          # never absent, never zero -- distinct from every other
          # collection, which is genuinely empty for a fresh account.
          assert row_count == 1
          refute entries[path] == ""

        _ ->
          assert row_count == 0, path
          assert entries[path] == "", path
      end
    end
  end

  test "two field-identical tasks export as two distinct lines with distinct ids", %{
    account_id: account_id,
    destination_dir: destination_dir
  } do
    capture(account_id, "Buy milk")
    capture(account_id, "Buy milk")

    assert {:ok, result} = run_export(destination_dir)
    entries = bundle_entries(result.bundle_path)

    lines =
      entries["data/task.ndjson"]
      |> String.trim_trailing("\n")
      |> String.split("\n")

    assert length(lines) == 2

    decoded = Enum.map(lines, &Jason.decode!/1)
    assert Enum.map(decoded, & &1["title"]) == ["Buy milk", "Buy milk"]
    assert decoded |> Enum.map(& &1["id"]) |> Enum.uniq() |> length() == 2
  end

  test "two consecutive exports of an unchanged account produce byte-identical entity files", %{
    account_id: account_id,
    destination_dir: destination_dir
  } do
    capture(account_id, "Stable task")

    first_dir = Path.join(destination_dir, "first")
    second_dir = Path.join(destination_dir, "second")
    File.mkdir_p!(first_dir)
    File.mkdir_p!(second_dir)

    assert {:ok, first} = run_export(first_dir)
    assert {:ok, second} = run_export(second_dir)

    first_entries = bundle_entries(first.bundle_path)
    second_entries = bundle_entries(second.bundle_path)

    for %{"path" => path} <- first.files, path != "manifest.json" do
      assert first_entries[path] == second_entries[path], "#{path} differed between exports"
    end

    first_manifest = Jason.decode!(first_entries["manifest.json"])
    second_manifest = Jason.decode!(second_entries["manifest.json"])

    assert Map.drop(first_manifest, ["generated_at", "keepling_version"]) ==
             Map.drop(second_manifest, ["generated_at", "keepling_version"])
  end

  test "the manifest is absent when the writer is interrupted before it", %{
    destination_dir: destination_dir
  } do
    account_id = "interrupted-account"
    poisoned_stream = Stream.map([:ok], fn _ -> raise "simulated interruption" end)

    entity_streams =
      Map.new(Export.entities(), fn
        "today-order" -> {"today-order", poisoned_stream}
        entity -> {entity, []}
      end)

    assert_raise RuntimeError, "simulated interruption", fn ->
      Export.write_bundle(account_id, destination_dir, entity_streams, %{
        "feed_high_water_sequence" => 0,
        "restore_epoch" => nil
      })
    end

    staging_dir = Path.join(destination_dir, "#{account_id}-export-staging")

    # Entities ordered before "today-order" completed and are on disk;
    # manifest.json and tasks.md are written only after every entity's
    # file, so they must be absent.
    assert File.exists?(Path.join([staging_dir, "data", "task.ndjson"]))
    refute File.exists?(Path.join(staging_dir, "manifest.json"))
    refute File.exists?(Path.join(staging_dir, "tasks.md"))
    refute File.exists?(Path.join(destination_dir, "#{account_id}-export.zip"))
  end

  test "a richly populated account round-trips through every entity with matching digests, and emits exactly one security_audit event",
       %{account_id: account_id, destination_dir: destination_dir} do
    project_id = Ecto.UUID.generate()
    tag_id = Ecto.UUID.generate()

    assert {:ok, %{status: 201}} =
             dispatch(account_id, @accepted_at, %{
               kind: :project,
               mutation_id: Ecto.UUID.generate(),
               name: "Home",
               organization_id: project_id,
               type: :create_organization,
               version: 1
             })

    assert {:ok, %{status: 201}} =
             dispatch(account_id, @accepted_at, %{
               kind: :tag,
               mutation_id: Ecto.UUID.generate(),
               name: "Errand",
               organization_id: tag_id,
               type: :create_organization,
               version: 1
             })

    task_id = capture(account_id, "Base title")

    assert {:ok, %{status: 200}} =
             dispatch(account_id, @accepted_at, %{
               base_values: %{project_id: nil, tag_ids: []},
               expected_revision: 1,
               fields: %{project_id: project_id, tag_ids: [tag_id]},
               mutation_id: Ecto.UUID.generate(),
               task_id: task_id,
               type: :assign_task_organizations,
               version: 1
             })

    with_connection(fn _pid ->
      SQL.query!(
        Repo,
        "UPDATE tasks SET title = 'Current title', revision = 3 WHERE account_id = $1 AND id = $2",
        [account_id, Ecto.UUID.dump!(task_id)]
      )
    end)

    conflict_command = %{
      type: :edit_task,
      base_values: %{notes: "", title: "Base title"},
      expected_revision: 2,
      fields: %{notes: "Keep this draft", title: "My title"},
      mutation_id: Ecto.UUID.generate(),
      task_id: task_id,
      version: 1
    }

    assert {:ok, %{status: 409}} = dispatch(account_id, @accepted_at, conflict_command)

    with_connection(fn _pid ->
      SQL.query!(
        Repo,
        """
        INSERT INTO today_task_order (account_id, task_id, section, position, inserted_at, updated_at)
        VALUES ($1, $2, 'today', 1, $3, $3)
        """,
        [account_id, Ecto.UUID.dump!(task_id), @accepted_at]
      )
    end)

    device_grant_id = Ecto.UUID.generate()

    with_connection(fn _pid ->
      SQL.query!(
        Repo,
        """
        INSERT INTO device_grants (
          id, account_id, installation_id, label, client_kind, redirect_uri,
          authorization_code_hash, authorization_code_expires_at, state_hash,
          pkce_challenge, family_absolute_expires_at, scope, inserted_at, updated_at
        ) VALUES ($1, $2, 'installation-1', 'My Mac', 'electron', 'keepling://auth/callback',
          $3, $4, $3, 'challenge', $4, ARRAY[]::text[], $5, $5)
        """,
        [
          Ecto.UUID.dump!(device_grant_id),
          account_id,
          :crypto.hash(:sha256, "code"),
          DateTime.add(@accepted_at, 600, :second),
          @accepted_at
        ]
      )

      SQL.query!(
        Repo,
        """
        INSERT INTO mcp_client_registrations (
          client_id, account_id, client_name, redirect_uris, created_at
        ) VALUES ($1, $2, 'Claude Code', ARRAY['https://example.com/callback'], $3)
        """,
        ["mcp-client-1", account_id, @accepted_at]
      )
    end)

    before_audit_count = audit_event_count()
    input = %{"destination_dir" => destination_dir}

    result =
      with_connection(fn _pid -> Ops.run("export", input, PostgresExport, %{}) end)

    assert %{
             "status" => "ok",
             "code" => "export_completed",
             "facts" => %{"bundle_path" => bundle_path, "file_count" => file_count}
           } = result

    assert file_count == 10

    entries = bundle_entries(bundle_path)
    manifest = Jason.decode!(entries["manifest.json"])

    assert manifest["export_format_version"] == 1
    assert is_binary(manifest["account_id"])
    # A finalized restore epoch always exists after the initial migration
    # (initialize_sync_epoch.exs) -- restore_epoch is only ever null before
    # any epoch has ever been finalized, which this test database is not.
    assert is_binary(manifest["restore_epoch"])
    # Every dispatched command above advanced the account's sync feed, so
    # the observed high-water sequence must be a positive citable point,
    # not the zero a never-synced account would show.
    assert is_integer(manifest["feed_high_water_sequence"]) and
             manifest["feed_high_water_sequence"] > 0

    for %{"path" => path, "sha256" => sha256, "rowCount" => row_count} <- manifest["files"] do
      content = Map.fetch!(entries, path)

      assert content |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower) ==
               sha256,
             path

      if String.starts_with?(path, "data/") do
        lines = content |> String.trim_trailing("\n") |> String.split("\n", trim: true)
        assert length(lines) == row_count, path
      end
    end

    assert [%{"kind" => "project", "display_name" => "Home"}] =
             entries["data/project.ndjson"]
             |> String.trim()
             |> String.split("\n")
             |> Enum.map(&Jason.decode!/1)

    assert [%{"kind" => "tag", "display_name" => "Errand"}] =
             entries["data/tag.ndjson"]
             |> String.trim()
             |> String.split("\n")
             |> Enum.map(&Jason.decode!/1)

    [task_line] = entries["data/task.ndjson"] |> String.trim() |> String.split("\n")
    task_row = Jason.decode!(task_line)
    assert task_row["project_id"] == project_id
    assert task_row["tag_ids"] == [tag_id]

    activity_lines =
      entries["data/task-activity.ndjson"] |> String.trim() |> String.split("\n", trim: true)

    assert length(activity_lines) >= 1

    [conflict_line] = entries["data/conflict.ndjson"] |> String.trim() |> String.split("\n")
    conflict_row = Jason.decode!(conflict_line)
    assert conflict_row["task_id"] == task_id
    assert conflict_row["affected_fields"] == ["title"]

    [today_line] = entries["data/today-order.ndjson"] |> String.trim() |> String.split("\n")

    assert Jason.decode!(today_line) == %{
             "task_id" => task_id,
             "section" => "today",
             "position" => 1
           }

    inventory_lines =
      entries["data/access-inventory.ndjson"] |> String.trim() |> String.split("\n")

    inventory = Enum.map(inventory_lines, &Jason.decode!/1)

    assert Enum.any?(
             inventory,
             &(&1["kind"] == "device_grant" and &1["client_kind"] == "electron")
           )

    assert Enum.any?(
             inventory,
             &(&1["kind"] == "mcp_registration" and &1["client_kind"] == "mcp")
           )

    settings_line = entries["data/account-settings.ndjson"] |> String.trim()
    assert Jason.decode!(settings_line) == %{"timezone" => "America/New_York"}

    after_audit_count = audit_event_count()
    assert after_audit_count - before_audit_count == 1

    stat = File.stat!(bundle_path)
    assert Integer.to_string(stat.mode, 8) |> String.slice(-3, 3) == "600"
  end

  defp run_export(destination_dir) do
    with_connection(fn _pid ->
      PostgresExport.execute("export", %{"destination_dir" => destination_dir}, %{})
    end)
  end

  defp bundle_entries(bundle_path) do
    {:ok, entries} = :zip.extract(String.to_charlist(bundle_path), [:memory])
    Map.new(entries, fn {name, content} -> {List.to_string(name), content} end)
  end

  defp audit_event_count do
    with_connection(fn _pid ->
      %{rows: [[count]]} =
        SQL.query!(
          Repo,
          "SELECT count(*) FROM account_security_audits WHERE event_type = 'export_performed'",
          []
        )

      count
    end)
  end

  defp capture(account_id, title) do
    task_id = Ecto.UUID.generate()

    assert {:ok, %{status: 201}} =
             dispatch(account_id, @accepted_at, %{
               type: :capture_task,
               mutation_id: Ecto.UUID.generate(),
               task_id: task_id,
               title: title,
               version: 1
             })

    task_id
  end

  defp dispatch(account_id, accepted_at, command) do
    with_connection(fn _pid ->
      Commands.dispatch(
        command,
        %{
          account_id: account_id,
          accepted_at: accepted_at,
          actor_type: "user",
          client_kind: "web"
        },
        CommandStore
      )
    end)
  end

  defp insert_account(timezone) do
    account_id = Ecto.UUID.bingenerate()

    with_connection(fn _pid ->
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
end
