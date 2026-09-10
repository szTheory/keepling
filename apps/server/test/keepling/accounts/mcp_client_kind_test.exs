defmodule Keepling.Accounts.MCPClientKindTest do
  @moduledoc """
  05-01-PLAN.md Task 2: an `mcp` device grant is a first-class client kind
  carrying a scope set (D-05/D-06), and the MCP authorization path accepts
  RFC 8707's `resource` parameter while electron/iphone stay unwidened
  (D-33).
  """
  use KeeplingWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL
  alias Keepling.Accounts
  alias Keepling.Repo

  @now ~U[2026-09-11 12:00:00.000000Z]
  @password String.duplicate("mcp-client-kind-password-", 12)
  @electron_redirect_uri "keepling://authorization/callback"
  @mcp_redirect_uri "https://server.keepling.invalid/mcp/callback"
  @mcp_resource "https://server.keepling.invalid/mcp/v1"
  @verifier String.duplicate("v", 64)
  @challenge :crypto.hash(:sha256, @verifier) |> Base.url_encode64(padding: false)
  @state :crypto.hash(:sha256, "mcp-client-kind-state") |> Base.url_encode64(padding: false)

  setup do
    previous = Application.get_env(:keepling, :device_grants)

    Application.put_env(:keepling, :device_grants,
      issuer: "https://issuer.keepling.invalid",
      origin: "https://server.keepling.invalid",
      server_instance: "server-instance-mcp-client-kind",
      redirect_uris: %{
        "electron" => [@electron_redirect_uri],
        "iphone" => [@electron_redirect_uri],
        "mcp" => [@mcp_redirect_uri]
      }
    )

    SQL.query!(Repo, "DELETE FROM account_security_audits", [])
    SQL.query!(Repo, "DELETE FROM accounts", [])
    account_id = create_account()

    on_exit(fn ->
      if previous,
        do: Application.put_env(:keepling, :device_grants, previous),
        else: Application.delete_env(:keepling, :device_grants)
    end)

    %{account_id: account_id}
  end

  test "an mcp grant issues and persists its scope", %{account_id: account_id} do
    assert {:ok, authorization} =
             Accounts.issue_device_authorization(
               account_id,
               authorization_request("mcp-installation", "mcp", scope: "tasks.read tasks.write"),
               now: @now
             )

    assert {:ok, %{rows: [[["tasks.read", "tasks.write"], "mcp"]]}} =
             SQL.query(
               Repo,
               "SELECT scope, client_kind FROM device_grants WHERE authorization_code_hash = $1",
               [:crypto.hash(:sha256, authorization.code)]
             )
  end

  test "a scope value outside the closed vocabulary is rejected by the database constraint", %{
    account_id: account_id
  } do
    grant_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()

    assert_raise Postgrex.Error, ~r/device_grants_scope_closed/, fn ->
      insert_raw_grant(grant_id, account_id, "mcp", ["tasks.destroy_everything"])
    end
  end

  test "an electron grant carrying a non-empty scope is rejected by the database constraint", %{
    account_id: account_id
  } do
    grant_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()

    assert_raise Postgrex.Error, ~r/device_grants_scope_closed/, fn ->
      insert_raw_grant(grant_id, account_id, "electron", ["tasks.read"])
    end
  end

  test "an electron authorize request carrying resource is still rejected", %{conn: conn} do
    response =
      conn
      |> login()
      |> recycle()
      |> get("/oauth/authorize", %{
        "client_id" => "electron",
        "code_challenge" => @challenge,
        "code_challenge_method" => "S256",
        "installation_id" => "electron-resource-rejected",
        "label" => "Synthetic electron installation",
        "redirect_uri" => @electron_redirect_uri,
        "resource" => @mcp_resource,
        "response_type" => "code",
        "state" => @state
      })

    assert response.status == 400
  end

  test "an mcp authorize request carrying resource is accepted", %{conn: conn} do
    response =
      conn
      |> login()
      |> recycle()
      |> get("/oauth/authorize", %{
        "client_id" => "mcp",
        "code_challenge" => @challenge,
        "code_challenge_method" => "S256",
        "installation_id" => "mcp-resource-accepted",
        "label" => "Synthetic mcp installation",
        "redirect_uri" => @mcp_redirect_uri,
        "resource" => @mcp_resource,
        "response_type" => "code",
        "scope" => "tasks.read",
        "state" => @state
      })

    assert response.status == 302
    location = response |> get_resp_header("location") |> List.first() |> URI.parse()
    assert "#{location.scheme}://#{location.host}#{location.path}" == @mcp_redirect_uri
  end

  test "an mcp authorize request whose resource names a different URI is rejected", %{conn: conn} do
    response =
      conn
      |> login()
      |> recycle()
      |> get("/oauth/authorize", %{
        "client_id" => "mcp",
        "code_challenge" => @challenge,
        "code_challenge_method" => "S256",
        "installation_id" => "mcp-resource-mismatch",
        "label" => "Synthetic mcp installation",
        "redirect_uri" => @mcp_redirect_uri,
        "resource" => "https://attacker.invalid/mcp/v1",
        "response_type" => "code",
        "scope" => "tasks.read",
        "state" => @state
      })

    assert response.status == 400
  end

  test "a redirect_uris map whose keys are not exactly the three client kinds raises at boot-validation time" do
    assert_raise ArgumentError, ~r/must name exactly electron, iphone, mcp/, fn ->
      Keepling.Application.validate_device_grants!(
        issuer: "https://issuer.keepling.invalid",
        origin: "https://server.keepling.invalid",
        server_instance: "server-instance-boot",
        redirect_uris: %{
          "electron" => [@electron_redirect_uri],
          "iphone" => [@electron_redirect_uri]
        }
      )
    end
  end

  defp authorization_request(installation_id, client_kind, opts) do
    redirect_uri =
      if client_kind == "mcp", do: @mcp_redirect_uri, else: @electron_redirect_uri

    %{
      client_kind: client_kind,
      code_challenge: @challenge,
      code_challenge_method: "S256",
      installation_id: installation_id,
      label: "Synthetic #{client_kind} installation",
      redirect_uri: redirect_uri,
      scope: Keyword.get(opts, :scope, ""),
      state: @state
    }
  end

  defp insert_raw_grant(grant_id, account_id, client_kind, scope) do
    redirect_uri = if client_kind == "mcp", do: @mcp_redirect_uri, else: @electron_redirect_uri

    SQL.query!(
      Repo,
      """
      INSERT INTO device_grants (
        id, account_id, installation_id, label, client_kind, redirect_uri,
        authorization_code_hash, authorization_code_expires_at,
        state_hash, pkce_challenge, family_absolute_expires_at, generation, scope,
        inserted_at, updated_at
      )
      VALUES ($1, $2, 'raw-installation', 'Raw fixture', $3, $4,
              $5, $6, $7, 'fixture-challenge', $6, 1, $8, $9, $9)
      """,
      [
        grant_id,
        account_id,
        client_kind,
        redirect_uri,
        :crypto.strong_rand_bytes(32),
        DateTime.add(@now, 600, :second),
        :crypto.strong_rand_bytes(32),
        scope,
        @now
      ]
    )
  end

  defp login(conn) do
    conn
    |> trusted_request()
    |> post("/api/v1/login", %{
      "client_kind" => "web",
      "label" => "MCP client kind browser",
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

    SQL.query!(
      Repo,
      """
      INSERT INTO accounts (id, singleton_key, password_hash, timezone, inserted_at, updated_at)
      VALUES ($1, TRUE, $2, 'Etc/UTC', $3, $3)
      """,
      [account_id, Argon2.hash_pwd_salt(@password), @now]
    )

    account_id
  end
end
