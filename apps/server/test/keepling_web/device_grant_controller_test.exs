defmodule KeeplingWeb.DeviceGrantControllerTest do
  use KeeplingWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL
  alias Keepling.Repo

  @password String.duplicate("native-grant-password-", 12)
  @redirect_uri "keepling://authorization/callback"
  @mcp_redirect_uri "https://server.keepling.invalid/mcp/callback"
  @mcp_resource "https://server.keepling.invalid/mcp/v1"
  @verifier String.duplicate("v", 64)
  @challenge :crypto.hash(:sha256, @verifier) |> Base.url_encode64(padding: false)
  @state :crypto.hash(:sha256, "transport-state") |> Base.url_encode64(padding: false)

  setup do
    previous = Application.get_env(:keepling, :device_grants)

    Application.put_env(:keepling, :device_grants,
      issuer: "https://issuer.keepling.invalid",
      origin: "https://server.keepling.invalid",
      server_instance: "server-instance-transport",
      redirect_uris: %{
        "electron" => [@redirect_uri],
        "iphone" => [@redirect_uri],
        "mcp" => [@mcp_redirect_uri]
      }
    )

    reset_account_state()
    account_id = create_account()

    on_exit(fn ->
      reset_account_state()

      if previous,
        do: Application.put_env(:keepling, :device_grants, previous),
        else: Application.delete_env(:keepling, :device_grants)
    end)

    %{account_id: account_id, configured_device_grants: previous}
  end

  # O-18 closure: the two tests below are the ONLY ones in this file that
  # exercise the configuration a REAL server boots with. Every other test
  # here runs against the fixture block installed by `setup` above, which is
  # exactly why the device-grant flow could be fully green while being
  # unreachable outside the test suite.
  test "real runtime configuration -- not test setup -- issues and exchanges an electron grant", %{
    account_id: account_id,
    configured_device_grants: configured,
    conn: conn
  } do
    assert is_list(configured),
           "config/runtime.exs must supply :keepling, :device_grants for a real server"

    Application.put_env(:keepling, :device_grants, configured)

    issuer = Keyword.fetch!(configured, :issuer)
    origin = Keyword.fetch!(configured, :origin)
    server_instance = Keyword.fetch!(configured, :server_instance)

    [redirect_uri | _] =
      configured |> Keyword.fetch!(:redirect_uris) |> Map.fetch!("electron")

    assert redirect_uri == "keepling://auth/callback"

    response =
      conn
      |> login()
      |> recycle()
      |> get("/oauth/authorize", %{
        "client_id" => "electron",
        "code_challenge" => @challenge,
        "code_challenge_method" => "S256",
        "installation_id" => "real-configuration-installation",
        "label" => "Real configuration installation",
        "redirect_uri" => redirect_uri,
        "response_type" => "code",
        "state" => @state
      })

    assert response.status == 302
    location = response |> get_resp_header("location") |> List.first() |> URI.parse()
    assert "#{location.scheme}://#{location.host}#{location.path}" == redirect_uri
    code = URI.decode_query(location.query) |> Map.fetch!("code")

    exchanged =
      build_conn()
      |> post("/oauth/token", %{
        "code" => code,
        "code_verifier" => @verifier,
        "grant_type" => "authorization_code",
        "redirect_uri" => redirect_uri,
        "state" => @state
      })
      |> json_response(200)

    assert %{
             "namespace" => %{
               "account_subject" => account_subject,
               "generation" => 1,
               "issuer" => ^issuer,
               "origin" => ^origin,
               "server_instance" => ^server_instance
             }
           } = exchanged

    assert Ecto.UUID.cast!(account_subject) == Ecto.UUID.cast!(account_id)
  end

  test "a server whose device-grant configuration is absent or malformed refuses to boot" do
    previous = Application.get_env(:keepling, :device_grants)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:keepling, :device_grants, previous),
        else: Application.delete_env(:keepling, :device_grants)
    end)

    Application.delete_env(:keepling, :device_grants)

    assert_raise ArgumentError, ~r/device grant configuration/, fn ->
      Keepling.Application.start(:normal, [])
    end

    for {malformed, expected} <- [
          {[issuer: "", origin: "https://o.invalid", server_instance: "s", redirect_uris: %{}],
           ~r/device grant issuer/},
          {[issuer: "https://i.invalid", origin: "not a url", server_instance: "s", redirect_uris: %{}],
           ~r/device grant origin/},
          {[issuer: "https://i.invalid", origin: "https://o.invalid", server_instance: "  ", redirect_uris: %{}],
           ~r/device grant server instance/},
          {[issuer: "https://i.invalid", origin: "https://o.invalid", server_instance: "s"],
           ~r/device grant redirect/},
          {[
             issuer: "https://i.invalid",
             origin: "https://o.invalid",
             server_instance: "s",
             redirect_uris: %{"electron" => []}
           ], ~r/device grant redirect/},
          {[
             issuer: "https://i.invalid",
             origin: "https://o.invalid",
             server_instance: "s",
             redirect_uris: %{"browser" => ["keepling://auth/callback"]}
           ], ~r/device grant redirect/},
          {[
             issuer: "https://i.invalid",
             origin: "https://o.invalid",
             server_instance: "s",
             redirect_uris: %{"electron" => ["https://phishing.invalid/callback"]}
           ], ~r/device grant redirect/}
        ] do
      Application.put_env(:keepling, :device_grants, malformed)

      assert_raise ArgumentError, expected, fn ->
        Keepling.Application.start(:normal, [])
      end
    end
  end

  @tag :transport
  test "native public client completes exact PKCE exchange, rotation, listing, and revocation", %{
    account_id: account_id,
    conn: conn
  } do
    browser = login(conn)

    authorization = authorize(browser, "installation-a", "electron")
    assert authorization.state == @state

    for {field, value} <- [
          {"redirect_uri", "keepling://wrong/callback"},
          {"state", @state <> "changed"},
          {"code_verifier", String.duplicate("x", 64)}
        ] do
      response =
        build_conn()
        |> post("/oauth/token", exchange_params(authorization.code) |> Map.put(field, value))

      assert %{"code" => "invalid_authorization_code"} = json_response(response, 401)
      refute response.resp_body =~ authorization.code
      refute response.resp_body =~ @verifier
    end

    exchanged =
      build_conn()
      |> post("/oauth/token", exchange_params(authorization.code))
      |> json_response(200)

    assert %{
             "access_token" => access_a,
             "expires_in" => 900,
             "namespace" => %{
               "account_subject" => account_subject,
               "generation" => 1,
               "issuer" => "https://issuer.keepling.invalid",
               "origin" => "https://server.keepling.invalid",
               "server_instance" => "server-instance-transport"
             },
             "refresh_token" => refresh_a,
             "token_type" => "Bearer"
           } = exchanged

    assert Ecto.UUID.cast!(account_subject) == Ecto.UUID.cast!(account_id)

    assert byte_size(Base.url_decode64!(access_a, padding: false)) == 32
    assert byte_size(Base.url_decode64!(refresh_a, padding: false)) == 32

    replay = build_conn() |> post("/oauth/token", exchange_params(authorization.code))
    assert %{"code" => "invalid_authorization_code"} = json_response(replay, 401)

    rotated =
      build_conn()
      |> post("/oauth/token", %{
        "grant_type" => "refresh_token",
        "refresh_token" => refresh_a
      })
      |> json_response(200)

    refute rotated["access_token"] == access_a
    refute rotated["refresh_token"] == refresh_a
    assert rotated["namespace"] == exchanged["namespace"]

    asserted_namespace_authorization = authorize(browser, "namespace-assertion", "electron")

    asserted_namespace =
      exchange_params(asserted_namespace_authorization.code)
      |> Map.put("namespace", %{
        "account_subject" => Ecto.UUID.generate(),
        "generation" => 999,
        "issuer" => "https://client.invalid",
        "origin" => "https://client.invalid",
        "server_instance" => "client-server"
      })

    assert build_conn() |> post("/oauth/token", asserted_namespace) |> response(401)

    fenced =
      build_conn()
      |> post("/oauth/token", %{
        "grant_type" => "refresh_token",
        "refresh_token" => refresh_a
      })

    assert %{"code" => "refresh_replay_detected"} = json_response(fenced, 401)

    assert bearer(build_conn(), rotated["access_token"])
           |> get("/api/v1/device-grants")
           |> response(401)

    grant_b = browser |> authorize("installation-b", "iphone") |> exchange()

    assert %{"device_grants" => grants} =
             bearer(build_conn(), grant_b["access_token"])
             |> get("/api/v1/device-grants")
             |> json_response(200)

    assert Enum.map(grants, & &1["installation_id"]) == [
             "installation-a",
             "installation-b",
             "namespace-assertion"
           ]

    refute Enum.any?(
             grants,
             &(Map.has_key?(&1, "access_token") or Map.has_key?(&1, "refresh_token"))
           )

    revoked =
      bearer(build_conn(), grant_b["access_token"])
      |> delete("/api/v1/device-grants/installation-a")

    assert %{
             "installation_id" => "installation-a",
             "status" => "device_grant_revoked"
           } = json_response(revoked, 200)

    revoked_again =
      bearer(build_conn(), grant_b["access_token"])
      |> delete("/api/v1/device-grants/installation-a")

    assert %{
             "installation_id" => "installation-a",
             "status" => "device_grant_revoked"
           } = json_response(revoked_again, 200)

    assert bearer(build_conn(), grant_b["access_token"])
           |> delete("/api/v1/device-grants/installation-b")
           |> json_response(200)

    assert bearer(build_conn(), grant_b["access_token"])
           |> get("/api/v1/device-grants")
           |> response(401)
  end

  # D-38/T-06-07-03. A newly created grant publishes a non-null
  # `authorized_at`, an empty `scope` array (never `null`, per D-38's
  # widened `grant_response/1`), and a null `last_used_at`. A pure read is a
  # NON-qualifying event and must not advance `last_used_at`; a mutation is
  # the qualifying event Task 1's checkpoint decided.
  test "the response publishes real scope/authorized_at/last_used_at, and last_used_at advances only on a mutation",
       %{account_id: account_id, conn: conn} do
    browser = login(conn)
    grant = browser |> authorize("last-used-installation", "electron") |> exchange()

    assert %{"device_grants" => [summary]} =
             bearer(build_conn(), grant["access_token"])
             |> get("/api/v1/device-grants")
             |> json_response(200)

    assert summary["scope"] == []
    assert is_binary(summary["authorized_at"])
    assert summary["last_used_at"] == nil

    # A pure read -- the non-qualifying event -- leaves last_used_at unchanged.
    assert %{"device_grants" => [after_read]} =
             bearer(build_conn(), grant["access_token"])
             |> get("/api/v1/device-grants")
             |> json_response(200)

    assert after_read["last_used_at"] == nil

    # A mutation -- the qualifying event -- advances it.
    assert %{"outcome" => "accepted"} =
             bearer(build_conn(), grant["access_token"])
             |> post("/api/v1/commands/capture-task", %{
               "mutation_id" => Ecto.UUID.generate(),
               "task_id" => Ecto.UUID.generate(),
               "title" => "Advance last_used_at",
               "version" => 1
             })
             |> json_response(201)

    assert %{"device_grants" => [after_mutation]} =
             bearer(build_conn(), grant["access_token"])
             |> get("/api/v1/device-grants")
             |> json_response(200)

    assert is_binary(after_mutation["last_used_at"])
  end

  test "bearer pipeline assigns only the server-authenticated grant namespace", %{
    conn: conn,
    account_id: account_id
  } do
    grant = conn |> login() |> authorize("namespace-installation", "electron") |> exchange()

    response =
      build_conn()
      |> bearer(grant["access_token"])
      |> put_req_header("x-keepling-issuer", "https://client-asserted.invalid")
      |> put_req_header("x-keepling-origin", "https://client-origin.invalid")
      |> put_req_header("x-keepling-server-instance", "client-server")
      |> put_req_header("x-keepling-account-subject", Ecto.UUID.generate())
      |> put_req_header("x-keepling-generation", "999")
      |> get("/api/v1/device-grants", %{
        "issuer" => "https://query-asserted.invalid",
        "generation" => "999"
      })

    assert response.status == 200
    assert is_binary(response.assigns.current_device_grant_id)

    assert response.assigns.device_grant_namespace == %{
             generation: 1,
             issuer: "https://issuer.keepling.invalid",
             origin: "https://server.keepling.invalid",
             server_instance: "server-instance-transport",
             subject: Ecto.UUID.load!(account_id)
           }
  end

  test "bearer boundary rejects every non-current credential form and ignores browser cookies", %{
    conn: conn
  } do
    browser = login(conn)
    grant = browser |> authorize("boundary-installation", "iphone") |> exchange()

    assert browser |> recycle() |> get("/api/v1/device-grants") |> response(401)
    assert get(build_conn(), "/api/v1/device-grants") |> response(401)

    for malformed <- ["Basic opaque", "Bearer", "Bearer ", "bearer #{grant["access_token"]}"] do
      assert build_conn()
             |> put_req_header("authorization", malformed)
             |> get("/api/v1/device-grants")
             |> response(401)
    end

    assert build_conn()
           |> put_req_header("authorization", "Bearer #{grant["access_token"]}")
           |> prepend_req_headers([{"authorization", "Bearer another"}])
           |> get("/api/v1/device-grants")
           |> response(401)

    expired = browser |> authorize("expired-installation", "electron") |> exchange()

    SQL.query!(
      Repo,
      "UPDATE device_grants SET access_expires_at = $2 WHERE access_token_hash = $1",
      [
        :crypto.hash(:sha256, expired["access_token"]),
        DateTime.utc_now() |> DateTime.add(-1, :second) |> DateTime.truncate(:microsecond)
      ]
    )

    assert build_conn()
           |> bearer(expired["access_token"])
           |> get("/api/v1/device-grants")
           |> response(401)

    rotated =
      build_conn()
      |> post("/oauth/token", %{
        "grant_type" => "refresh_token",
        "refresh_token" => grant["refresh_token"]
      })
      |> json_response(200)

    assert build_conn()
           |> bearer(grant["access_token"])
           |> get("/api/v1/device-grants")
           |> response(401)

    assert build_conn()
           |> bearer(rotated["access_token"])
           |> get("/api/v1/device-grants")
           |> response(200)

    assert build_conn()
           |> post("/oauth/token", %{
             "grant_type" => "refresh_token",
             "refresh_token" => grant["refresh_token"]
           })
           |> response(401)

    assert build_conn()
           |> bearer(rotated["access_token"])
           |> get("/api/v1/device-grants")
           |> response(401)
  end

  # T-05-13 / WINDOWS #70. Grant administration is the escalation's sharpest
  # edge: the probe that found this revoked another installation with an
  # agent credential scoped `tasks.read`, after which the victim grant 401'd
  # on `/mcp/v1`. In production that is an agent switching off the owner's
  # iPhone -- the phase goal's "recovery model" clause, attacked by the very
  # credential the phase issues.
  #
  # This test does NOT relax the bearer boundary asserted above; it adds the
  # kind boundary inside it. `/api/v1/device-grants` stays bearer-only and
  # still ignores browser cookies; the owner's browser reaches grant
  # administration through `/api/v1/account/device-grants` instead (see the
  # owner-session test below).
  test "an mcp agent grant can neither enumerate nor revoke device grants, while first-party grants still can",
       %{conn: conn} do
    browser = login(conn)

    victim = browser |> authorize("victim-iphone", "iphone") |> exchange()
    agent = mcp_grant_credential(browser, "agent-installation", "tasks.read")

    assert %{
             "code" => "device_authentication_required",
             "recovery_action" => "reauthorize_device"
           } =
             build_conn() |> bearer(agent) |> get("/api/v1/device-grants") |> json_response(401)

    assert %{
             "code" => "device_authentication_required",
             "recovery_action" => "reauthorize_device"
           } =
             build_conn()
             |> bearer(agent)
             |> delete("/api/v1/device-grants/victim-iphone")
             |> json_response(401)

    # Proof the refused revocation did nothing, read back from the server:
    # the victim credential still authenticates and both installations are
    # still present and unrevoked.
    assert %{"device_grants" => grants} =
             build_conn()
             |> bearer(victim["access_token"])
             |> get("/api/v1/device-grants")
             |> json_response(200)

    assert Enum.sort(Enum.map(grants, & &1["installation_id"])) ==
             ["agent-installation", "victim-iphone"]

    refute Enum.any?(grants, & &1["revoked"])

    # ... and the first-party clients still administer grants, including
    # revoking the agent -- the direction that must keep working.
    owner_mac = browser |> authorize("owner-mac", "electron") |> exchange()

    assert %{
             "installation_id" => "agent-installation",
             "status" => "device_grant_revoked"
           } =
             build_conn()
             |> bearer(owner_mac["access_token"])
             |> delete("/api/v1/device-grants/agent-installation")
             |> json_response(200)
  end

  test "the owner's browser session administers grants through its own route", %{conn: conn} do
    browser = login(conn)
    browser |> authorize("session-managed-iphone", "iphone") |> exchange()
    mcp_grant_credential(browser, "session-managed-agent", "tasks.read")

    assert %{"device_grants" => grants} =
             browser
             |> recycle()
             |> get("/api/v1/account/device-grants")
             |> json_response(200)

    assert Enum.sort(Enum.map(grants, & &1["installation_id"])) ==
             ["session-managed-agent", "session-managed-iphone"]

    assert Enum.any?(grants, &(&1["client_kind"] == "mcp"))

    refute Enum.any?(
             grants,
             &(Map.has_key?(&1, "access_token") or Map.has_key?(&1, "refresh_token"))
           )

    assert %{
             "installation_id" => "session-managed-agent",
             "status" => "device_grant_revoked"
           } =
             browser
             |> recycle()
             |> trusted_request()
             |> delete("/api/v1/account/device-grants/session-managed-agent")
             |> json_response(200)

    assert %{"device_grants" => after_revocation} =
             browser |> recycle() |> get("/api/v1/account/device-grants") |> json_response(200)

    assert Enum.find(after_revocation, &(&1["installation_id"] == "session-managed-agent"))[
             "revoked"
           ] == true
  end

  test "the owner-session grant routes are session-only and origin-guarded", %{conn: conn} do
    browser = login(conn)
    grant = browser |> authorize("owner-route-boundary", "electron") |> exchange()

    # No session at all.
    assert get(build_conn(), "/api/v1/account/device-grants") |> response(401)

    # A device-grant BEARER must not reach the owner-session route either --
    # this route is the browser's, and admitting a bearer here would just
    # rebuild the hole on a different path.
    assert build_conn()
           |> bearer(grant["access_token"])
           |> get("/api/v1/account/device-grants")
           |> response(401)

    # The delete carries `:mutation`, so a cross-origin browser request is
    # refused even with a valid session.
    assert browser
           |> recycle()
           |> delete("/api/v1/account/device-grants/owner-route-boundary")
           |> response(403)
  end

  defp mcp_grant_credential(conn, installation_id, scope) do
    response =
      conn
      |> recycle()
      |> get("/oauth/authorize", %{
        "client_id" => "mcp",
        "code_challenge" => @challenge,
        "code_challenge_method" => "S256",
        "installation_id" => installation_id,
        "label" => "Synthetic mcp installation #{installation_id}",
        "redirect_uri" => @mcp_redirect_uri,
        "resource" => @mcp_resource,
        "response_type" => "code",
        "scope" => scope,
        "state" => @state
      })

    assert response.status == 302
    query = response |> get_resp_header("location") |> List.first() |> URI.parse()
    code = query.query |> URI.decode_query() |> Map.fetch!("code")

    build_conn()
    |> post("/oauth/token", %{
      "code" => code,
      "code_verifier" => @verifier,
      "grant_type" => "authorization_code",
      "redirect_uri" => @mcp_redirect_uri,
      "resource" => @mcp_resource,
      "state" => @state
    })
    |> json_response(200)
    |> Map.fetch!("access_token")
  end

  defp authorize(conn, installation_id, client_id) do
    response =
      conn
      |> recycle()
      |> get("/oauth/authorize", %{
        "client_id" => client_id,
        "code_challenge" => @challenge,
        "code_challenge_method" => "S256",
        "installation_id" => installation_id,
        "label" => "Synthetic #{client_id} installation",
        "redirect_uri" => @redirect_uri,
        "response_type" => "code",
        "state" => @state
      })

    assert response.status == 302
    location = response |> get_resp_header("location") |> List.first() |> URI.parse()
    assert "#{location.scheme}://#{location.host}#{location.path}" == @redirect_uri

    query = URI.decode_query(location.query)
    assert query["state"] == @state
    assert is_binary(query["code"])

    %{code: query["code"], state: query["state"]}
  end

  defp exchange(authorization) do
    build_conn()
    |> post("/oauth/token", exchange_params(authorization.code))
    |> json_response(200)
  end

  defp exchange_params(code) do
    %{
      "code" => code,
      "code_verifier" => @verifier,
      "grant_type" => "authorization_code",
      "redirect_uri" => @redirect_uri,
      "state" => @state
    }
  end

  defp bearer(conn, credential), do: put_req_header(conn, "authorization", "Bearer #{credential}")

  defp login(conn) do
    conn
    |> trusted_request()
    |> post("/api/v1/login", %{
      "client_kind" => "web",
      "label" => "Authorization browser",
      "password" => @password,
      "version" => 1
    })
    |> tap(&json_response(&1, 200))
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

  defp create_account do
    account_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    SQL.query!(
      Repo,
      """
      INSERT INTO accounts (id, singleton_key, password_hash, timezone, inserted_at, updated_at)
      VALUES ($1, TRUE, $2, 'Etc/UTC', $3, $3)
      """,
      [account_id, Argon2.hash_pwd_salt(@password), now]
    )

    account_id
  end

  defp reset_account_state do
    SQL.query!(Repo, "DELETE FROM account_security_audits", [])
    SQL.query!(Repo, "DELETE FROM accounts", [])
  end
end
