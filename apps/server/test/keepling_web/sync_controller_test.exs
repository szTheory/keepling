defmodule KeeplingWeb.SyncControllerTest do
  use KeeplingWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL
  alias Keepling.Adapters.Postgres.CommandStore
  alias Keepling.Application.Commands
  alias Keepling.Repo

  @now ~U[2026-09-01 12:00:00.000000Z]

  setup do
    previous = Application.get_env(:keepling, :device_grants)

    Application.put_env(:keepling, :device_grants,
      issuer: "https://issuer.keepling.invalid",
      origin: "https://server.keepling.invalid",
      server_instance: "server-instance-sync",
      redirect_uris: %{"electron" => ["keepling://authorization/callback"]}
    )

    SQL.query!(Repo, "DELETE FROM account_security_audits", [])
    SQL.query!(Repo, "DELETE FROM accounts", [])
    account_id = create_account()
    install_epoch()

    on_exit(fn ->
      if previous,
        do: Application.put_env(:keepling, :device_grants, previous),
        else: Application.delete_env(:keepling, :device_grants)
    end)

    %{account_id: account_id, credential: create_grant(account_id, 1)}
  end

  test "authenticated installation pulls bounded changes and bootstraps canonical state", %{
    account_id: account_id,
    credential: credential
  } do
    task_id = Ecto.UUID.generate()

    assert {:ok, %{status: 201}} =
             Commands.dispatch(
               %{
                 mutation_id: Ecto.UUID.generate(),
                 task_id: task_id,
                 title: "Private sync title",
                 type: :capture_task,
                 version: 1
               },
               %{
                 account_id: account_id,
                 accepted_at: @now,
                 actor_type: "user",
                 client_kind: "electron"
               },
               CommandStore
             )

    pull = bearer(build_conn(), credential) |> get("/api/v1/sync", %{"limit" => "2"})

    assert %{
             "changes" => changes,
             "coverage_cursor" => coverage_cursor,
             "has_more" => false
           } = json_response(pull, 200)

    assert length(changes) == 2
    assert is_binary(coverage_cursor)
    refute pull.resp_body =~ "Private sync title"

    bootstrap =
      bearer(build_conn(), credential)
      |> get("/api/v1/sync/bootstrap", %{"limit" => "1"})

    assert %{
             "entities" => [%{"entity_id" => ^task_id, "kind" => "task_snapshot"}],
             "high_water" => %{"ordinal" => 1, "sequence" => 1},
             "next_cursor" => nil
           } = json_response(bootstrap, 200)
  end

  test "closed inputs and cursor recovery never become empty success", %{credential: credential} do
    assert %{
             "code" => "invalid_sync_query",
             "recovery_action" => "correct_request"
           } =
             bearer(build_conn(), credential)
             |> get("/api/v1/sync", %{"limit" => "201", "subject" => Ecto.UUID.generate()})
             |> json_response(400)

    assert %{
             "code" => "sync_cursor_tampered",
             "recovery_action" => "bootstrap"
           } =
             bearer(build_conn(), credential)
             |> get("/api/v1/sync", %{"cursor" => "client-forged", "limit" => "2"})
             |> json_response(409)
  end

  test "server-derived generation and server identity fence old cursors", %{
    account_id: account_id,
    credential: credential
  } do
    task_id = Ecto.UUID.generate()

    assert {:ok, %{status: 201}} =
             Commands.dispatch(
               %{
                 mutation_id: Ecto.UUID.generate(),
                 task_id: task_id,
                 title: "Fenced title",
                 type: :capture_task,
                 version: 1
               },
               %{
                 account_id: account_id,
                 accepted_at: @now,
                 actor_type: "user",
                 client_kind: "electron"
               },
               CommandStore
             )

    old_cursor =
      bearer(build_conn(), credential)
      |> get("/api/v1/sync", %{"limit" => "1"})
      |> json_response(200)
      |> Map.fetch!("coverage_cursor")

    refreshed_credential = create_grant(account_id, 2)

    assert %{"code" => "sync_namespace_mismatch", "recovery_action" => "quarantine"} =
             bearer(build_conn(), refreshed_credential)
             |> get("/api/v1/sync", %{"cursor" => old_cursor})
             |> json_response(409)

    Application.put_env(:keepling, :device_grants,
      issuer: "https://issuer.keepling.invalid",
      origin: "https://server.keepling.invalid",
      server_instance: "replacement-server",
      redirect_uris: %{"electron" => ["keepling://authorization/callback"]}
    )

    assert %{"code" => "sync_namespace_mismatch", "recovery_action" => "quarantine"} =
             bearer(build_conn(), refreshed_credential)
             |> get("/api/v1/sync", %{"cursor" => old_cursor})
             |> json_response(409)
  end

  test "browser sessions and missing credentials cannot enter the sync namespace", %{conn: conn} do
    assert get(conn, "/api/v1/sync") |> response(401)
    assert get(build_conn(), "/api/v1/sync/bootstrap") |> response(401)
  end

  defp create_account do
    account_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()

    SQL.query!(
      Repo,
      """
      INSERT INTO accounts (id, singleton_key, password_hash, timezone, inserted_at, updated_at)
      VALUES ($1, TRUE, '$argon2id$sync-fixture', 'Etc/UTC', $2, $2)
      """,
      [account_id, @now]
    )

    account_id
  end

  defp install_epoch do
    SQL.query!(
      Repo,
      """
      INSERT INTO sync_epochs (singleton_key, epoch, finalized, inserted_at, updated_at)
      VALUES (TRUE, $1, TRUE, $2, $2)
      ON CONFLICT (singleton_key) DO UPDATE
      SET epoch = EXCLUDED.epoch, finalized = TRUE, updated_at = EXCLUDED.updated_at
      """,
      [Ecto.UUID.generate() |> Ecto.UUID.dump!(), @now]
    )
  end

  defp create_grant(account_id, generation) do
    credential = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    grant_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()
    authorization_hash = :crypto.strong_rand_bytes(32)
    expires_at = DateTime.add(@now, 90, :day)

    SQL.query!(
      Repo,
      """
      INSERT INTO device_grants (
        id, account_id, installation_id, label, client_kind, redirect_uri,
        authorization_code_hash, authorization_code_expires_at, authorization_code_consumed_at,
        state_hash, pkce_challenge, access_token_hash, access_expires_at,
        family_absolute_expires_at, generation, inserted_at, updated_at
      )
      VALUES ($1, $2, $3, 'Sync fixture', 'electron', 'keepling://authorization/callback',
              $4, $5, $6, $7, 'fixture-challenge', $8, $5, $5, $9, $6, $6)
      """,
      [
        grant_id,
        account_id,
        "sync-installation-#{generation}",
        authorization_hash,
        expires_at,
        @now,
        :crypto.strong_rand_bytes(32),
        :crypto.hash(:sha256, credential),
        generation
      ]
    )

    credential
  end

  defp bearer(conn, credential), do: put_req_header(conn, "authorization", "Bearer #{credential}")
end
