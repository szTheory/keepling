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
    create_account()

    on_exit(fn ->
      reset_account_state()

      if previous,
        do: Application.put_env(:keepling, :device_grants, previous),
        else: Application.delete_env(:keepling, :device_grants)
    end)

    :ok
  end

  @tag :transport
  test "native public client completes exact PKCE exchange, rotation, listing, and revocation", %{
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
             "refresh_token" => refresh_a,
             "token_type" => "Bearer"
           } = exchanged

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

    assert Enum.map(grants, & &1["installation_id"]) == ["installation-a", "installation-b"]

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
  end

  defp reset_account_state do
    SQL.query!(Repo, "DELETE FROM account_security_audits", [])
    SQL.query!(Repo, "DELETE FROM accounts", [])
  end
end
