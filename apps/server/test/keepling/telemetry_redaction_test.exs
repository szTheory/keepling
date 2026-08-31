defmodule Keepling.TelemetryRedactionTest do
  use KeeplingWeb.ConnCase, async: false

  import ExUnit.CaptureLog

  alias Ecto.Adapters.SQL
  alias Keepling.Accounts.RateLimit
  alias Keepling.Repo

  @password "telemetry proof password manager value"
  @hostile_password "HOSTILE_PASSWORD_SENTINEL_DO_NOT_EMIT"
  @hostile_token "HOSTILE_RECOVERY_TOKEN_SENTINEL_DO_NOT_EMIT"
  @hostile_title "HOSTILE_TASK_TITLE_SENTINEL_DO_NOT_EMIT"
  @hostile_identifier "00000000-0000-4000-8000-000000000099"

  setup do
    SQL.query!(Repo, "DELETE FROM account_security_audits", [])
    SQL.query!(Repo, "DELETE FROM accounts", [])
    create_account(@password)
    if :ets.whereis(RateLimit) != :undefined, do: :ets.delete_all_objects(RateLimit)

    handler_id = "auth-redaction-#{System.unique_integer([:positive])}"
    parent = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:keepling, :authentication, :decision],
        fn event, measurements, metadata, _config ->
          send(parent, {:auth_telemetry, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn ->
      :telemetry.detach(handler_id)
      SQL.query!(Repo, "DELETE FROM account_security_audits", [])
      SQL.query!(Repo, "DELETE FROM accounts", [])
    end)

    :ok
  end

  test "hostile credentials, tokens, task content, and identifiers never enter diagnostics", %{
    conn: conn
  } do
    log =
      capture_log(fn ->
        conn
        |> trusted_request()
        |> post("/api/v1/login", %{
          "client_kind" => "web",
          "label" => "Browser",
          "password" => @hostile_password,
          "version" => 1
        })
        |> response(401)

        conn
        |> trusted_request()
        |> post("/api/v1/recovery", %{
          "client_kind" => "web",
          "label" => "Browser",
          "password" => @hostile_password,
          "token" => @hostile_token,
          "version" => 1
        })
        |> response(422)

        authenticated = login(build_conn(), @password)
        csrf = json_response(authenticated, 200)["csrf_token"]

        authenticated
        |> recycle()
        |> trusted_request()
        |> enforce_csrf()
        |> put_req_header("x-csrf-token", csrf)
        |> post("/api/v1/commands/capture-task", %{
          "mutation_id" => @hostile_identifier,
          "task_id" => Ecto.UUID.generate(),
          "title" => @hostile_title,
          "version" => 1
        })
        |> response(201)
      end)

    telemetry = collect_auth_telemetry([])
    assert telemetry != []

    for {event, measurements, metadata} <- telemetry do
      assert event == [:keepling, :authentication, :decision]
      assert measurements == %{count: 1}
      assert Map.keys(metadata) |> Enum.sort() == [:flow, :outcome]
      assert metadata.flow in [:login, :recovery]
      assert metadata.outcome in [:accepted, :invalid, :limited]
    end

    diagnostic_text = inspect(telemetry) <> log

    for forbidden <- [
          @hostile_password,
          @hostile_token,
          @hostile_title,
          @hostile_identifier
        ] do
      refute diagnostic_text =~ forbidden
    end

    assert %{rows: rows} =
             SQL.query!(
               Repo,
               "SELECT event_type, event_version, account_id FROM account_security_audits ORDER BY id",
               []
             )

    assert Enum.all?(rows, fn [event_type, version, account_id] ->
             event_type in ["login_failed", "login_succeeded"] and version == 1 and
               is_nil(account_id)
           end)
  end

  test "every production diagnostic event is allow-listed and test controls are absent from production" do
    root = Path.expand("../../", __DIR__)

    telemetry_sources =
      root
      |> Path.join("lib/**/*.ex")
      |> Path.wildcard()
      |> Enum.filter(&(File.read!(&1) =~ ":telemetry.execute"))
      |> Enum.map(&Path.relative_to(&1, root))

    assert telemetry_sources == ["lib/keepling/accounts/rate_limit.ex"]

    rate_limit_source = File.read!(Path.join(root, "lib/keepling/accounts/rate_limit.ex"))
    assert rate_limit_source =~ "[:keepling, :authentication, :decision]"
    assert rate_limit_source =~ "%{flow: flow, outcome: outcome}"
    refute rate_limit_source =~ "task_id"
    refute rate_limit_source =~ "mutation_id"
    refute rate_limit_source =~ "token"

    router = File.read!(Path.join(root, "lib/keepling_web/router.ex"))
    assert router =~ "if Mix.env() == :test do"
    assert router =~ ~s(scope "/api/v1/test")
    assert router =~ "if Mix.env() == :test,"
  end

  defp collect_auth_telemetry(acc) do
    receive do
      {:auth_telemetry, event, measurements, metadata} ->
        collect_auth_telemetry([{event, measurements, metadata} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp login(conn, password) do
    conn
    |> trusted_request()
    |> post("/api/v1/login", %{
      "client_kind" => "web",
      "label" => "Telemetry test browser",
      "password" => password,
      "version" => 1
    })
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
  end
end
