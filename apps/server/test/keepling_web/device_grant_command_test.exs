defmodule KeeplingWeb.DeviceGrantCommandTest do
  @moduledoc """
  D-49: the device-grant credential class MAY mutate.

  Found by O-37, which was found by pointing a real packaged Mac client at a
  real Phoenix server for the first time: the server issued the client a
  device grant, accepted it on `GET /api/v1/sync`, and refused the SAME
  credential on `POST /api/v1/commands/capture-task` and
  `GET /api/v1/mutations/:id`. So the Mac app could authorize and pull but
  could never push, and "Synced" was structurally unreachable.

  Two halves are tested here and neither is optional:

  1. A device grant can capture and read back its own exact receipt, and the
     mutation is recorded under the grant's OWN account and client kind --
     never under anything the request asserted.

  2. The BROWSER posture is unchanged, byte for byte. `require_trusted_origin`
     is a CSRF defence, and CSRF applies only to ambient cookie
     authentication; a bearer client structurally has no ambient credential
     to be ridden. Widening the credential class must therefore relax nothing
     for cookie-authenticated requests, and that is PINNED below rather than
     asserted in a comment.
  """
  use KeeplingWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL
  alias Keepling.Repo

  @now ~U[2026-09-01 12:00:00.000000Z]

  setup do
    previous = Application.get_env(:keepling, :device_grants)

    Application.put_env(:keepling, :device_grants,
      issuer: "https://issuer.keepling.invalid",
      origin: "https://server.keepling.invalid",
      server_instance: "server-instance-command",
      redirect_uris: %{"electron" => ["keepling://auth/callback"]}
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

    %{account_id: account_id, credential: create_grant(account_id, 1, "electron-1")}
  end

  test "a device grant captures a task and reads back its own exact receipt", %{
    credential: credential
  } do
    mutation_id = Ecto.UUID.generate()
    task_id = Ecto.UUID.generate()

    acknowledgement =
      build_conn()
      |> bearer(credential)
      |> post("/api/v1/commands/capture-task", %{
        "mutation_id" => mutation_id,
        "task_id" => task_id,
        "title" => "Book the ferry",
        "version" => 1
      })
      |> json_response(201)

    assert %{
             "mutation_id" => ^mutation_id,
             "outcome" => "accepted",
             "task_id" => ^task_id
           } = acknowledgement

    # The exact stored terminal result, by mutation identity -- the read the
    # Mac app's reconcile path depends on to settle without re-pushing.
    receipt =
      build_conn()
      |> bearer(credential)
      |> get("/api/v1/mutations/#{mutation_id}")
      |> json_response(200)

    assert receipt["mutation_id"] == mutation_id
    assert receipt["task_id"] == task_id
    assert receipt["outcome"] in ["accepted", "already_satisfied"]
  end

  test "the mutation is recorded under the grant's own account and client kind", %{
    account_id: account_id,
    credential: credential
  } do
    mutation_id = Ecto.UUID.generate()

    build_conn()
    |> bearer(credential)
    |> post("/api/v1/commands/capture-task", %{
      "mutation_id" => mutation_id,
      "task_id" => Ecto.UUID.generate(),
      "title" => "Recorded as electron",
      "version" => 1
    })
    |> json_response(201)

    # A Mac capture recorded as "web" would be a visible untruth in the
    # user's own activity feed, so the client kind comes from the grant.
    assert %{rows: [[recorded_account_id, "electron"]]} =
             SQL.query!(
               Repo,
               "SELECT account_id, client_kind FROM task_activities WHERE mutation_id = $1",
               [Ecto.UUID.dump!(mutation_id)]
             )

    assert recorded_account_id == account_id
  end

  test "a request cannot assert any namespace field -- the account comes only from the grant",
       %{credential: credential} do
    # HOSTILE. The five-field namespace tuple is server-derived (D-02). A
    # client that names a subject, an account, or a generation is refused
    # outright by the exact-key decoder rather than having the field quietly
    # ignored -- an ignored field is indistinguishable from an honoured one
    # to the person reading the response.
    for asserted <- ["subject", "account_id", "generation", "origin", "server_instance"] do
      body =
        Map.put(
          %{
            "mutation_id" => Ecto.UUID.generate(),
            "task_id" => Ecto.UUID.generate(),
            "title" => "Namespace assertion attempt",
            "version" => 1
          },
          asserted,
          "00000000-0000-4000-8000-00000000dead"
        )

      assert %{"code" => "invalid_command"} =
               build_conn()
               |> bearer(credential)
               |> post("/api/v1/commands/capture-task", body)
               |> json_response(400)
    end
  end

  test "a revoked grant cannot mutate, and nothing it attempted was written", %{
    account_id: account_id,
    credential: credential
  } do
    # HOSTILE. Revocation advances the grant's generation, which opens a new
    # synchronization namespace and closes the old one. A credential minted
    # under the closed generation must be dead for mutation exactly as it is
    # for reads -- otherwise revoking a lost Mac would stop it reading while
    # leaving it able to write.
    SQL.query!(
      Repo,
      """
      UPDATE device_grants
      SET revoked_at = $2, generation = generation + 1, access_token_hash = NULL
      WHERE account_id = $1
      """,
      [account_id, @now]
    )

    mutation_id = Ecto.UUID.generate()

    assert %{"code" => "device_authentication_required"} =
             build_conn()
             |> bearer(credential)
             |> post("/api/v1/commands/capture-task", %{
               "mutation_id" => mutation_id,
               "task_id" => Ecto.UUID.generate(),
               "title" => "Written by a revoked Mac",
               "version" => 1
             })
             |> json_response(401)

    # Not merely refused: nothing reached storage.
    live = create_grant(account_id, 2, "electron-2")

    assert build_conn()
           |> bearer(live)
           |> get("/api/v1/mutations/#{mutation_id}")
           |> json_response(404)
  end

  test "an expired access credential cannot mutate", %{
    account_id: account_id,
    credential: credential
  } do
    SQL.query!(
      Repo,
      "UPDATE device_grants SET access_expires_at = $2 WHERE account_id = $1",
      [account_id, DateTime.add(DateTime.utc_now(), -1, :second)]
    )

    assert %{"code" => "device_authentication_required"} =
             build_conn()
             |> bearer(credential)
             |> post("/api/v1/commands/capture-task", capture_body())
             |> json_response(401)
  end

  test "a browser session credential presented as a Bearer token is refused", %{
    account_id: account_id
  } do
    # HOSTILE, credential-class confusion. The two credential classes are
    # authenticated by different code against different tables; neither may
    # be accepted in the other's position.
    {:ok, session} = Keepling.Accounts.create_session(account_id, label: "Web", client_kind: "web")

    assert %{"code" => "device_authentication_required"} =
             build_conn()
             |> bearer(session.credential)
             |> post("/api/v1/commands/capture-task", capture_body())
             |> json_response(401)
  end

  test "no credential at all is still refused", %{} do
    assert build_conn()
           |> post("/api/v1/commands/capture-task", capture_body())
           |> response(401)
  end

  test "the browser posture is unchanged: a cookie session still needs a trusted Origin", %{
    account_id: account_id
  } do
    {:ok, session} = Keepling.Accounts.create_session(account_id, label: "Web", client_kind: "web")

    # Correct Origin: accepted, exactly as before this change.
    assert build_conn()
           |> browser_session(session)
           |> trusted_origin()
           |> post("/api/v1/commands/capture-task", capture_body())
           |> json_response(201)

    # No Origin at all: still refused. This is the assertion that stops a
    # future "the bearer path does not need an Origin" simplification from
    # quietly deleting CSRF protection for the browser as well.
    assert %{"code" => "origin_not_allowed"} =
             build_conn()
             |> browser_session(session)
             |> post("/api/v1/commands/capture-task", capture_body())
             |> json_response(403)

    # A foreign Origin: still refused.
    assert %{"code" => "origin_not_allowed"} =
             build_conn()
             |> browser_session(session)
             |> trusted_origin()
             |> put_req_header("origin", "http://attacker.example")
             |> post("/api/v1/commands/capture-task", capture_body())
             |> json_response(403)
  end

  defp capture_body do
    %{
      "mutation_id" => Ecto.UUID.generate(),
      "task_id" => Ecto.UUID.generate(),
      "title" => "Capture attempt",
      "version" => 1
    }
  end

  defp browser_session(conn, session) do
    Plug.Test.init_test_session(conn, %{session_credential: session.credential})
  end

  defp trusted_origin(conn) do
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

  defp bearer(conn, credential), do: put_req_header(conn, "authorization", "Bearer #{credential}")

  defp create_account do
    account_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()

    SQL.query!(
      Repo,
      """
      INSERT INTO accounts (id, singleton_key, password_hash, timezone, inserted_at, updated_at)
      VALUES ($1, TRUE, '$argon2id$command-fixture', 'Etc/UTC', $2, $2)
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

  defp create_grant(account_id, generation, installation_id) do
    credential = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    grant_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()
    authorization_hash = :crypto.strong_rand_bytes(32)
    expires_at = DateTime.add(DateTime.utc_now(), 90, :day)

    SQL.query!(
      Repo,
      """
      INSERT INTO device_grants (
        id, account_id, installation_id, label, client_kind, redirect_uri,
        authorization_code_hash, authorization_code_expires_at, authorization_code_consumed_at,
        state_hash, pkce_challenge, access_token_hash, access_expires_at,
        family_absolute_expires_at, generation, inserted_at, updated_at
      )
      VALUES ($1, $2, $3, 'Command fixture', 'electron', 'keepling://auth/callback',
              $4, $5, $6, $7, 'fixture-challenge', $8, $5, $5, $9, $6, $6)
      """,
      [
        grant_id,
        account_id,
        installation_id,
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
end
