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

  # -- D-07 lane 2: golden vector byte comparison (06-08-PLAN.md Task 3) ----

  @golden_vector_path Path.expand(
                         "../../../../../packages/contracts/vectors/export-golden.json",
                         __DIR__
                       )
  @external_resource @golden_vector_path

  test "the export bundle matches its registered golden vector, byte for byte", %{
    destination_dir: destination_dir
  } do
    golden = @golden_vector_path |> File.read!() |> Jason.decode!()
    fixture = golden["fixture"]
    expected = golden["expected"]

    entity_streams = Map.new(Export.entities(), fn entity -> {entity, fixture["entities"][entity]} end)

    assert {:ok, result} =
             Export.write_bundle(
               fixture["account_id"],
               destination_dir,
               entity_streams,
               fixture["manifest_extra"]
             )

    entries = bundle_entries(result.bundle_path)

    for {path, expected_content} <- expected["files"] do
      assert entries[path] == expected_content, "#{path} did not match the golden vector"
    end

    format_md_path =
      Path.expand("../../../../../packages/contracts/schemas/export/FORMAT.md", __DIR__)

    assert entries["FORMAT.md"] == File.read!(format_md_path),
           "FORMAT.md in the bundle no longer matches the checked-in copy verbatim"

    manifest = Jason.decode!(entries["manifest.json"])
    assert Map.drop(manifest, ["generated_at", "keepling_version"]) == expected["manifest"]
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

  # -- D-07 lane 1: schema-driven completeness (06-08-PLAN.md Task 1) --------

  @classification_path Path.expand(
                          "../../../../../packages/contracts/schemas/export/classification.json",
                          __DIR__
                        )
  @external_resource @classification_path

  # Every "in" classified column's corresponding field in the entity schema
  # it is exported into. `nil` means the column is scoping-only (folded into
  # the export's own account_id, or into another field with no 1:1 name
  # match) and is intentionally not checked against a schema field.
  @in_schema_targets %{
    {"accounts", "id"} => nil,
    {"accounts", "timezone"} => [{"account-settings", "timezone"}],
    {"tasks", "account_id"} => nil,
    {"tasks", "id"} => [{"task", "id"}],
    {"tasks", "title"} => [{"task", "title"}],
    {"tasks", "notes"} => [{"task", "notes"}],
    {"tasks", "inbox_state"} => [{"task", "inbox_state"}],
    {"tasks", "revision"} => [{"task", "revision"}],
    {"tasks", "captured_at"} => [{"task", "captured_at"}],
    {"tasks", "planned_on"} => [{"task", "planned_on"}],
    {"tasks", "deadline_on"} => [{"task", "deadline_on"}],
    {"tasks", "completed_at"} => [{"task", "completed_at"}],
    {"tasks", "trashed_at"} => [{"task", "trashed_at"}],
    {"tasks", "project_id"} => [{"task", "project_id"}],
    {"organizations", "account_id"} => nil,
    {"organizations", "id"} => [{"project", "id"}, {"tag", "id"}],
    {"organizations", "kind"} => [{"project", "kind"}, {"tag", "kind"}],
    {"organizations", "display_name"} => [{"project", "display_name"}, {"tag", "display_name"}],
    {"organizations", "archived_at"} => [{"project", "archived_at"}, {"tag", "archived_at"}],
    {"task_tags", "account_id"} => nil,
    {"task_tags", "task_id"} => [{"task", "tag_ids"}],
    {"task_tags", "tag_id"} => [{"task", "tag_ids"}],
    {"task_activities", "id"} => [{"task-activity", "id"}],
    {"task_activities", "account_id"} => nil,
    {"task_activities", "task_id"} => [{"task-activity", "task_id"}],
    {"task_activities", "activity_type"} => [{"task-activity", "activity_type"}],
    {"task_activities", "activity_version"} => [{"task-activity", "activity_version"}],
    {"task_activities", "actor_type"} => [{"task-activity", "actor_type"}],
    {"task_activities", "client_kind"} => [{"task-activity", "client_kind"}],
    {"task_activities", "from_revision"} => [{"task-activity", "from_revision"}],
    {"task_activities", "to_revision"} => [{"task-activity", "to_revision"}],
    {"task_activities", "changed_fields"} => [{"task-activity", "changed_fields"}],
    {"task_activities", "accepted_at"} => [{"task-activity", "accepted_at"}],
    {"persisted_conflicts", "account_id"} => nil,
    {"persisted_conflicts", "id"} => [{"conflict", "id"}],
    {"persisted_conflicts", "task_id"} => [{"conflict", "task_id"}],
    {"persisted_conflicts", "original_mutation_id"} => [{"conflict", "original_mutation_id"}],
    {"persisted_conflicts", "command_type"} => [{"conflict", "command_type"}],
    {"persisted_conflicts", "expected_revision"} => [{"conflict", "expected_revision"}],
    {"persisted_conflicts", "latest_revision"} => [{"conflict", "latest_revision"}],
    {"persisted_conflicts", "affected_fields"} => [{"conflict", "affected_fields"}],
    {"persisted_conflicts", "base_values"} => [{"conflict", "base_values"}],
    {"persisted_conflicts", "requested_values"} => [{"conflict", "requested_values"}],
    {"persisted_conflicts", "current_values"} => [{"conflict", "current_values"}],
    {"persisted_conflicts", "inserted_at"} => [{"conflict", "inserted_at"}],
    {"today_task_order", "account_id"} => nil,
    {"today_task_order", "task_id"} => [{"today-order", "task_id"}],
    {"today_task_order", "section"} => [{"today-order", "section"}],
    {"today_task_order", "position"} => [{"today-order", "position"}],
    {"device_grants", "id"} => [{"access-inventory", "id"}],
    {"device_grants", "account_id"} => nil,
    {"device_grants", "client_kind"} => [{"access-inventory", "client_kind"}],
    {"device_grants", "label"} => [{"access-inventory", "label"}],
    {"device_grants", "scope"} => [{"access-inventory", "scope"}],
    {"device_grants", "inserted_at"} => [{"access-inventory", "inserted_at"}],
    {"device_grants", "revoked_at"} => [{"access-inventory", "revoked_at"}],
    {"mcp_client_registrations", "client_id"} => [{"access-inventory", "id"}],
    {"mcp_client_registrations", "account_id"} => nil,
    {"mcp_client_registrations", "client_name"} => [{"access-inventory", "label"}],
    {"mcp_client_registrations", "created_at"} => [{"access-inventory", "inserted_at"}],
    {"mcp_client_registrations", "revoked_at"} => [{"access-inventory", "revoked_at"}]
  }

  defp classification_manifest do
    @classification_path |> File.read!() |> Jason.decode!()
  end

  defp entity_schemas do
    schemas_dir =
      Path.expand("../../../../../packages/contracts/schemas/export", __DIR__)

    Export.entities()
    |> Enum.map(fn entity ->
      path = Path.join(schemas_dir, "#{entity}.schema.json")
      {entity, path |> File.read!() |> Jason.decode!()}
    end)
    |> Map.new()
  end

  # Returns the set of {table, column} pairs `classification` accounts for --
  # either an explicit per-column entry, or every column of a table carrying
  # a single table-wide disposition.
  defp classified?(classification, table, column) do
    Enum.find_value(classification["tables"], false, fn
      %{"table" => ^table, "columns" => columns} ->
        Enum.any?(columns, &(&1["column"] == column))

      %{"table" => ^table, "disposition" => _} ->
        true

      _ ->
        false
    end)
  end

  defp unclassified_columns(classification, live_columns) do
    for [table, column] <- live_columns, not classified?(classification, table, column) do
      "#{table}.#{column}"
    end
  end

  defp live_public_columns do
    with_connection(fn _pid ->
      %{rows: rows} =
        SQL.query!(
          Repo,
          "SELECT table_name, column_name FROM information_schema.columns WHERE table_schema = 'public' ORDER BY table_name, column_name",
          []
        )

      rows
    end)
  end

  @tag :completeness
  test "every live public-schema column is classified in or out (D-07 lane 1)" do
    classification = classification_manifest()
    live_columns = live_public_columns()

    assert live_columns != [], "information_schema.columns returned nothing -- check test DB connection"

    missing = unclassified_columns(classification, live_columns)

    assert missing == [],
           "unclassified column(s) present in the live schema but absent from " <>
             "classification.json (a future migration must classify every new " <>
             "column): #{Enum.join(missing, ", ")}"
  end

  @tag :completeness
  test "the completeness check fails in the stated direction when a column is removed from a copy of the manifest (negative fixture)" do
    classification = classification_manifest()
    live_columns = live_public_columns()

    # Sanity: with the real, checked-in manifest, nothing is missing.
    assert unclassified_columns(classification, live_columns) == []

    mutated =
      update_in(classification["tables"], fn tables ->
        Enum.map(tables, fn
          %{"table" => "tasks", "columns" => columns} = table ->
            %{table | "columns" => Enum.reject(columns, &(&1["column"] == "title"))}

          table ->
            table
        end)
      end)

    assert "tasks.title" in unclassified_columns(mutated, live_columns),
           "removing tasks.title from a copy of the manifest must surface it as unclassified -- " <>
             "the completeness check does not actually detect a missing column"
  end

  @tag :completeness
  test "every column classified 'in' also appears in its corresponding exported entity schema (D-07 lane 1)" do
    classification = classification_manifest()
    schemas = entity_schemas()

    missing =
      for %{"table" => table, "columns" => columns} <- classification["tables"],
          %{"column" => column, "disposition" => "in"} <- columns,
          targets = Map.fetch!(@in_schema_targets, {table, column}),
          targets != nil,
          {schema_name, field} <- targets,
          schema = Map.fetch!(schemas, schema_name),
          not Map.has_key?(schema["properties"] || %{}, field) do
        "#{table}.#{column} -> #{schema_name}.#{field}"
      end

    assert missing == [],
           "column(s) classified 'in' but absent from their exported entity schema: #{Enum.join(missing, ", ")}"
  end

  # -- D-07 lane 4: no-secrets assertion (06-08-PLAN.md Task 1) --------------

  @tag :"no-secrets"
  test "an export from a credential-bearing account carries none of that account's credential material",
       %{account_id: account_id, destination_dir: destination_dir} do
    unique = System.unique_integer([:positive, :monotonic])

    session_credential = "no-secrets-fixture-session-credential-#{unique}"
    session_credential_hash = :crypto.hash(:sha256, session_credential)

    recovery_code = "no-secrets-fixture-recovery-code-#{unique}"
    recovery_code_hash = :crypto.hash(:sha256, recovery_code)

    authorization_code = "no-secrets-fixture-authorization-code-#{unique}"
    authorization_code_hash = :crypto.hash(:sha256, authorization_code)

    state_value = "no-secrets-fixture-state-#{unique}"
    state_hash = :crypto.hash(:sha256, state_value)

    pkce_challenge = "no-secrets-fixture-pkce-challenge-#{unique}"

    access_token = "no-secrets-fixture-access-token-#{unique}"
    access_token_hash = :crypto.hash(:sha256, access_token)

    with_connection(fn _pid ->
      SQL.query!(
        Repo,
        """
        INSERT INTO sessions (
          id, account_id, credential_hash, created_at, expires_at, label, client_kind,
          idle_ttl_seconds, absolute_expires_at, recent_authenticated_at, recent_auth_expires_at,
          inserted_at, updated_at
        ) VALUES ($1, $2, $3, $4, $5, 'Browser', 'web', 2592000, $6, $4, $7, $4, $4)
        """,
        [
          Ecto.UUID.bingenerate(),
          account_id,
          session_credential_hash,
          @accepted_at,
          DateTime.add(@accepted_at, 3600, :second),
          DateTime.add(@accepted_at, 86_400, :second),
          DateTime.add(@accepted_at, 900, :second)
        ]
      )

      SQL.query!(
        Repo,
        """
        INSERT INTO account_recovery (account_id, token_hash, issued_at, expires_at, inserted_at, updated_at)
        VALUES ($1, $2, $3, $4, $3, $3)
        """,
        [account_id, recovery_code_hash, @accepted_at, DateTime.add(@accepted_at, 3600, :second)]
      )

      SQL.query!(
        Repo,
        """
        INSERT INTO device_grants (
          id, account_id, installation_id, label, client_kind, redirect_uri,
          authorization_code_hash, authorization_code_expires_at, state_hash,
          pkce_challenge, access_token_hash, access_expires_at, family_absolute_expires_at,
          scope, inserted_at, updated_at
        ) VALUES ($1, $2, 'installation-secrets-fixture', 'My Mac', 'electron',
          'keepling://auth/callback', $3, $4, $5, $6, $7, $4, $4, ARRAY[]::text[], $8, $8)
        """,
        [
          Ecto.UUID.bingenerate(),
          account_id,
          authorization_code_hash,
          DateTime.add(@accepted_at, 600, :second),
          state_hash,
          pkce_challenge,
          access_token_hash,
          @accepted_at
        ]
      )
    end)

    assert {:ok, result} = run_export(destination_dir)
    entries = bundle_entries(result.bundle_path)
    raw_bytes = entries |> Map.values() |> Enum.join()

    plaintext_secrets = [
      session_credential,
      recovery_code,
      authorization_code,
      state_value,
      pkce_challenge,
      access_token
    ]

    for secret <- plaintext_secrets do
      refute raw_bytes =~ secret, "bundle raw bytes leaked plaintext fixture secret: #{secret}"
    end

    hashed_secrets_hex =
      [
        session_credential_hash,
        recovery_code_hash,
        authorization_code_hash,
        state_hash,
        access_token_hash
      ]
      |> Enum.map(&Base.encode16(&1, case: :lower))

    for secret_hex <- hashed_secrets_hex do
      refute raw_bytes =~ secret_hex, "bundle raw bytes leaked a fixture credential hash"
    end

    inventory_lines =
      entries["data/access-inventory.ndjson"]
      |> String.trim()
      |> String.split("\n", trim: true)
      |> Enum.map(&Jason.decode!/1)

    assert inventory_lines != [], "access-inventory should contain at least the fixture grant"

    excluded_device_grant_keys =
      ~w(installation_id redirect_uri authorization_code_hash authorization_code_expires_at
         authorization_code_consumed_at state_hash pkce_challenge access_token_hash
         access_expires_at refresh_inactivity_expires_at family_absolute_expires_at
         generation last_refreshed_at resource updated_at)

    excluded_mcp_keys = ~w(redirect_uris)

    for record <- inventory_lines, key <- excluded_device_grant_keys ++ excluded_mcp_keys do
      refute Map.has_key?(record, key),
             "access-inventory record leaked excluded column #{key}: #{inspect(record)}"
    end
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
