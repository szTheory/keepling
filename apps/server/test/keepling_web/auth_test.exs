defmodule KeeplingWeb.AuthLifecycleTest do
  use KeeplingWeb.ConnCase, async: false

  import ExUnit.CaptureIO

  alias Ecto.Adapters.SQL
  alias Keepling.Accounts
  alias Keepling.Repo

  @now ~U[2026-08-30 20:00:00.000000Z]
  @password String.duplicate("password-manager-value-", 20)

  setup do
    reset_account_state()
    account_id = create_account(@password)

    on_exit(&reset_account_state/0)

    %{account_id: account_id}
  end

  test "long password login creates a hash-only tracked browser session", %{conn: conn} do
    login = login(conn, @password, "MacBook Pro")

    assert %{
             "csrf_token" => csrf_token,
             "status" => "authenticated"
           } = json_response(login, 200)

    assert is_binary(csrf_token) and csrf_token != ""

    assert %{rows: [[credential_hash, label, client_kind]]} =
             SQL.query!(
               Repo,
               "SELECT credential_hash, label, client_kind FROM sessions",
               []
             )

    assert is_binary(credential_hash) and byte_size(credential_hash) == 32
    refute credential_hash == @password
    assert label == "MacBook Pro"
    assert client_kind == "web"

    sessions =
      login
      |> recycle()
      |> get("/api/v1/sessions")
      |> json_response(200)

    assert %{
             "sessions" => [
               %{
                 "client_kind" => "web",
                 "coarse_activity" => coarse_activity,
                 "created_at" => created_at,
                 "current" => true,
                 "id" => session_id,
                 "label" => "MacBook Pro"
               }
             ]
           } = sessions

    assert coarse_activity in ["active_now", "today", "earlier"]
    assert {:ok, _datetime, 0} = DateTime.from_iso8601(created_at)
    assert {:ok, _uuid} = Ecto.UUID.cast(session_id)
  end

  test "invalid login is generic and never creates a session", %{conn: conn} do
    response = login(conn, "wrong-password-value", "Browser")

    assert %{
             "code" => "authentication_failed",
             "recovery_action" => "check_credentials",
             "retryable" => false,
             "status" => 401,
             "title" => "Authentication failed"
           } = json_response(response, 401)

    assert %{rows: [[0]]} = SQL.query!(Repo, "SELECT count(*) FROM sessions", [])
  end

  test "reauthentication rotates session state and permits label and individual revocation", %{
    conn: conn
  } do
    first = login(conn, @password, "Primary browser")
    first_csrf = json_response(first, 200)["csrf_token"]

    second = login(build_conn(), @password, "Spare browser")

    [%{"id" => second_id}, %{"id" => first_id}] =
      second
      |> recycle()
      |> get("/api/v1/sessions")
      |> json_response(200)
      |> Map.fetch!("sessions")

    reauthenticated =
      first
      |> recycle()
      |> mutation_request(first_csrf)
      |> post("/api/v1/reauthenticate", %{"password" => @password, "version" => 1})

    assert %{"csrf_token" => rotated_csrf, "status" => "recently_authenticated"} =
             json_response(reauthenticated, 200)

    assert rotated_csrf != first_csrf

    renamed =
      reauthenticated
      |> recycle()
      |> mutation_request(rotated_csrf)
      |> patch("/api/v1/sessions/#{first_id}", %{"label" => "Work browser", "version" => 1})

    assert %{"label" => "Work browser", "status" => "session_updated"} =
             json_response(renamed, 200)

    revoked =
      renamed
      |> recycle()
      |> mutation_request(rotated_csrf)
      |> delete("/api/v1/sessions/#{second_id}")

    assert %{"status" => "session_revoked"} = json_response(revoked, 200)

    assert second
           |> recycle()
           |> get("/api/v1/sessions")
           |> response(401)
  end

  test "logout revokes the current server session and clears authentication", %{conn: conn} do
    signed_in = login(conn, @password, "Browser")
    csrf = json_response(signed_in, 200)["csrf_token"]

    signed_out =
      signed_in
      |> recycle()
      |> mutation_request(csrf)
      |> post("/api/v1/logout", %{"version" => 1})

    assert %{"status" => "signed_out"} = json_response(signed_out, 200)

    assert signed_out
           |> recycle()
           |> get("/api/v1/sessions")
           |> response(401)
  end

  test "idle, absolute, and recent-auth windows are independently enforced", %{
    account_id: account_id
  } do
    assert {:ok, issued} =
             Accounts.create_session(account_id,
               now: @now,
               idle_ttl_seconds: 120,
               absolute_ttl_seconds: 300,
               recent_auth_ttl_seconds: 60,
               label: "Expiry proof",
               client_kind: "web"
             )

    assert {:ok, %{recently_authenticated?: true}} =
             Accounts.authenticate_session(issued.credential,
               now: DateTime.add(@now, 59, :second)
             )

    assert {:ok, %{recently_authenticated?: false}} =
             Accounts.authenticate_session(issued.credential,
               now: DateTime.add(@now, 61, :second)
             )

    assert {:error, :authentication_required} =
             Accounts.authenticate_session(issued.credential,
               now: DateTime.add(@now, 182, :second)
             )

    assert {:ok, absolute} =
             Accounts.create_session(account_id,
               now: @now,
               idle_ttl_seconds: 600,
               absolute_ttl_seconds: 300,
               recent_auth_ttl_seconds: 60,
               label: "Absolute expiry proof",
               client_kind: "web"
             )

    assert {:error, :authentication_required} =
             Accounts.authenticate_session(absolute.credential,
               now: DateTime.add(@now, 301, :second)
             )
  end

  test "operator recovery prints one short-lived link without password transport" do
    output =
      capture_io(fn ->
        Mix.Tasks.Keepling.Recover.run([
          "--base-url",
          "https://keepling.example",
          "--ttl-seconds",
          "900"
        ])
      end)

    assert [_url] =
             Regex.scan(~r{https://keepling\.example/recover\?token=[A-Za-z0-9_-]+}, output)

    assert output =~ "Recovery link (shown once):"
    assert output =~ "expires"
    refute String.downcase(output) =~ "password"

    assert_raise Mix.Error, fn ->
      Mix.Tasks.Keepling.Recover.run(["--password", "not-an-accepted-channel"])
    end
  end

  defp login(conn, password, label) do
    conn
    |> trusted_request()
    |> post("/api/v1/login", %{
      "client_kind" => "web",
      "label" => label,
      "password" => password,
      "version" => 1
    })
  end

  defp mutation_request(conn, csrf_token) do
    conn
    |> trusted_request()
    |> enforce_csrf()
    |> put_req_header("x-csrf-token", csrf_token)
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

  defp create_account(password) do
    account_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    SQL.query!(
      Repo,
      """
      INSERT INTO accounts (
        id, singleton_key, password_hash, timezone, inserted_at, updated_at
      )
      VALUES ($1, TRUE, $2, 'America/New_York', $3, $3)
      """,
      [account_id, Argon2.hash_pwd_salt(password), now]
    )

    account_id
  end

  defp reset_account_state do
    SQL.query!(Repo, "DELETE FROM accounts", [])
  end
end

defmodule Keepling.Accounts.RecoveryRaceTest do
  use ExUnit.Case, async: false

  import Keepling.ConcurrencyCase

  alias Ecto.Adapters.SQL
  alias Keepling.Accounts
  alias Keepling.Repo

  @now ~U[2026-08-30 21:00:00.000000Z]
  @previous_password "previous password manager value"
  @new_password "replacement password manager value"

  setup do
    reset_account_state()
    create_account(@previous_password)
    on_exit(&reset_account_state/0)
    :ok
  end

  test "independent recovery consumers have exactly one winner and the token is one-use" do
    assert {:ok, issued} = Accounts.issue_recovery_token(now: @now, ttl_seconds: 900)

    assert %{rows: [[stored_hash]]} =
             with_connection(fn _backend_pid ->
               SQL.query!(Repo, "SELECT token_hash FROM account_recovery", [])
             end)

    assert stored_hash == :crypto.hash(:sha256, issued.token)
    refute stored_hash == issued.token

    barrier = start_barrier(2)

    results =
      for _attempt <- 1..2 do
        Task.async(fn ->
          with_connection(fn backend_pid ->
            :ok = await(barrier)

            result =
              Accounts.consume_recovery(%{
                token: issued.token,
                password: @new_password,
                accepted_at: DateTime.add(@now, 30, :second),
                label: "Recovered browser",
                client_kind: "web"
              })

            {backend_pid, result}
          end)
        end)
      end
      |> Enum.map(&Task.await(&1, 20_000))

    assert results |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> length() == 2
    assert Enum.count(results, fn {_pid, result} -> match?({:ok, _}, result) end) == 1

    assert Enum.count(results, fn {_pid, result} ->
             result == {:error, :recovery_unavailable}
           end) == 1

    assert {:ok, _session} = Accounts.login(@new_password, now: DateTime.add(@now, 31, :second))
    assert {:error, :authentication_failed} =
             Accounts.login(@previous_password, now: DateTime.add(@now, 31, :second))

    assert {:error, :recovery_unavailable} =
             Accounts.consume_recovery(%{
               token: issued.token,
               password: "another replacement password value",
               accepted_at: DateTime.add(@now, 40, :second),
               label: "Browser",
               client_kind: "web"
             })
  end

  defp create_account(password) do
    account_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()

    with_connection(fn _backend_pid ->
      SQL.query!(
        Repo,
        """
        INSERT INTO accounts (
          id, singleton_key, password_hash, timezone, inserted_at, updated_at
        )
        VALUES ($1, TRUE, $2, 'America/New_York', $3, $3)
        """,
        [account_id, Argon2.hash_pwd_salt(password), @now]
      )
    end)
  end

  defp reset_account_state do
    with_connection(fn _backend_pid -> SQL.query!(Repo, "DELETE FROM accounts", []) end)
  end
end
