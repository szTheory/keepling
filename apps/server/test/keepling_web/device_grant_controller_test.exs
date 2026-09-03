defmodule KeeplingWeb.DeviceGrantControllerTest do
  use KeeplingWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL
  alias Keepling.Repo

  @password String.duplicate("native-grant-password-", 12)
  @redirect_uri "keepling://authorization/callback"
  @verifier String.duplicate("v", 64)
  @challenge :crypto.hash(:sha256, @verifier) |> Base.url_encode64(padding: false)
  @state :crypto.hash(:sha256, "transport-state") |> Base.url_encode64(padding: false)

  setup do
    previous = Application.get_env(:keepling, :device_grants)

    Application.put_env(:keepling, :device_grants,
      issuer: "https://issuer.keepling.invalid",
      origin: "https://server.keepling.invalid",
      server_instance: "server-instance-transport",
      redirect_uris: %{"electron" => [@redirect_uri], "iphone" => [@redirect_uri]}
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
