defmodule Keepling.SecurityAuditTest do
  use KeeplingWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL
  alias Keepling.Accounts.RateLimit
  alias Keepling.Repo

  @password "correct password manager value"
  @fast_policy %{account: {60_000, 1}, source: {60_000, 1}, max_backoff_ms: 60_000}

  setup do
    reset_account_state()
    create_account(@password)
    clear_rate_limit_table()

    previous_policy = Application.get_env(:keepling, :rate_limit_policy)

    on_exit(fn ->
      reset_account_state()
      clear_rate_limit_table()

      if previous_policy do
        Application.put_env(:keepling, :rate_limit_policy, previous_policy)
      else
        Application.delete_env(:keepling, :rate_limit_policy)
      end
    end)

    :ok
  end

  @tag rate_limit: true
  test "the application permanently supervises Hammer and restores usable ETS state" do
    first_pid = limiter_pid()
    assert is_pid(first_pid) and Process.alive?(first_pid)
    assert :ok = RateLimit.admit(:login, {127, 0, 0, 1})

    Process.exit(first_pid, :kill)

    second_pid = await_restarted_limiter(first_pid)
    assert is_pid(second_pid) and second_pid != first_pid
    assert Process.alive?(second_pid)
    assert :ok = RateLimit.admit(:login, {127, 0, 0, 1})
  end

  @tag rate_limit: true
  test "flow, account, and source buckets are isolated and backoff stays bounded" do
    source_one = {192, 0, 2, 9}
    source_two = {198, 51, 100, 19}

    assert :ok = RateLimit.admit(:login, source_one, policy: @fast_policy)

    assert {:error, :rate_limited, retry_after_ms} =
             RateLimit.admit(:login, source_one, policy: @fast_policy)

    assert retry_after_ms > 0 and retry_after_ms <= 60_000
    assert :ok = RateLimit.admit(:setup, source_one, policy: @fast_policy)

    clear_rate_limit_table()

    source_limited_policy = %{
      account: {60_000, 10},
      source: {60_000, 1},
      max_backoff_ms: 60_000
    }

    assert :ok = RateLimit.admit(:recovery, source_one, policy: source_limited_policy)

    assert {:error, :rate_limited, _backoff} =
             RateLimit.admit(:recovery, source_one, policy: source_limited_policy)

    assert :ok = RateLimit.admit(:recovery, source_two, policy: source_limited_policy)

    serialized_entries = RateLimit |> :ets.tab2list() |> inspect()

    for namespace <- [
          "setup:account",
          "setup:source",
          "login:account",
          "login:source",
          "recovery:account",
          "recovery:source"
        ] do
      assert serialized_entries =~ namespace
    end

    refute serialized_entries =~ "192.0.2.9"
    refute serialized_entries =~ "198.51.100.19"
  end

  @tag rate_limit: true
  test "limited and invalid login responses are identical and audits stay closed", %{conn: conn} do
    Application.put_env(:keepling, :rate_limit_policy, %{login: @fast_policy})

    first = login(conn, "incorrect password value")
    second = login(build_conn(), "another incorrect password value")

    assert first.status == 401
    assert second.status == 401
    assert first.resp_body == second.resp_body

    assert Jason.decode!(first.resp_body) == %{
             "code" => "authentication_failed",
             "recovery_action" => "check_credentials",
             "retryable" => false,
             "status" => 401,
             "title" => "Authentication failed",
             "type" => "/problems/authentication_failed"
           }

    assert %{rows: audit_rows} =
             SQL.query!(
               Repo,
               "SELECT event_type, event_version FROM account_security_audits ORDER BY id",
               []
             )

    assert [
             ["login_failed", 1],
             ["rate_limited", 1]
           ] = audit_rows
  end

  test "every cookie-authenticated mutation enforces both CSRF and origin", %{conn: conn} do
    signed_in = login(conn, @password)
    csrf = json_response(signed_in, 200)["csrf_token"]

    session_id =
      signed_in
      |> recycle()
      |> get("/api/v1/sessions")
      |> json_response(200)
      |> Map.fetch!("sessions")
      |> hd()
      |> Map.fetch!("id")

    mutations = [
      {:post, "/api/v1/reauthenticate", %{"password" => @password, "version" => 1}},
      {:post, "/api/v1/logout", %{"version" => 1}},
      {:patch, "/api/v1/sessions/#{session_id}", %{"label" => "Browser", "version" => 1}},
      {:delete, "/api/v1/sessions/#{session_id}", %{}},
      {:post, "/api/v1/commands/capture-task",
       %{
         "mutation_id" => Ecto.UUID.generate(),
         "task_id" => Ecto.UUID.generate(),
         "title" => "CSRF boundary fixture",
         "version" => 1
       }}
    ]

    for {method, path, body} <- mutations do
      without_origin =
        signed_in
        |> recycle()
        |> enforce_csrf()
        |> put_req_header("x-csrf-token", csrf)
        |> dispatch_mutation(method, path, body)

      assert response(without_origin, 403)

      assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
        signed_in
        |> recycle()
        |> trusted_request()
        |> enforce_csrf()
        |> dispatch_mutation(method, path, body)
      end
    end
  end

  defp login(conn, password) do
    conn
    |> trusted_request()
    |> post("/api/v1/login", %{
      "client_kind" => "web",
      "label" => "Security test browser",
      "password" => password,
      "version" => 1
    })
  end

  defp dispatch_mutation(conn, :post, path, body), do: post(conn, path, body)
  defp dispatch_mutation(conn, :patch, path, body), do: patch(conn, path, body)
  defp dispatch_mutation(conn, :delete, path, _body), do: delete(conn, path)

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

  defp limiter_pid do
    Keepling.Supervisor
    |> Supervisor.which_children()
    |> Enum.find_value(fn
      {RateLimit, pid, :worker, _modules} -> pid
      _child -> nil
    end)
  end

  defp await_restarted_limiter(previous_pid, attempts \\ 100)

  defp await_restarted_limiter(_previous_pid, 0), do: nil

  defp await_restarted_limiter(previous_pid, attempts) do
    case limiter_pid() do
      pid when is_pid(pid) and pid != previous_pid ->
        pid

      _ ->
        Process.sleep(10)
        await_restarted_limiter(previous_pid, attempts - 1)
    end
  end

  defp clear_rate_limit_table do
    if :ets.whereis(RateLimit) != :undefined, do: :ets.delete_all_objects(RateLimit)
  end

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
  end

  defp reset_account_state do
    SQL.query!(Repo, "DELETE FROM accounts", [])
  end
end
