defmodule Keepling.Accounts.SetupTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO
  import Keepling.ConcurrencyCase

  alias Ecto.Adapters.SQL
  alias Keepling.Accounts
  alias Keepling.Repo

  @now ~U[2026-08-30 18:00:00.000000Z]

  setup do
    reset_account_state()
    on_exit(&reset_account_state/0)
    :ok
  end

  @tag setup: true
  test "operator issuance stores only a hash and setup atomically creates the sole account" do
    assert {:ok, issued} =
             call(fn -> Accounts.issue_setup_token(now: @now, ttl_seconds: 900) end)

    assert is_binary(issued.token)
    assert byte_size(Base.url_decode64!(issued.token, padding: false)) == 32
    refute inspect_setup_state().token_hash == issued.token
    assert inspect_setup_state().token_hash == :crypto.hash(:sha256, issued.token)
    assert inspect_setup_state().expires_at == ~U[2026-08-30 18:15:00.000000Z]

    assert {:ok, %{timezone: "America/New_York"}} =
             call(fn ->
               Accounts.consume_setup(%{
                 token: issued.token,
                 password: "correct horse battery staple",
                 timezone: "America/New_York",
                 accepted_at: DateTime.add(@now, 60, :second)
               })
             end)

    assert %{accounts: 1, disabled: true} = setup_counts()

    assert %{rows: [[password_hash, timezone]]} =
             query!("SELECT password_hash, timezone FROM accounts WHERE singleton_key = TRUE")

    assert String.starts_with?(password_hash, "$argon2id$")
    refute password_hash == "correct horse battery staple"
    assert timezone == "America/New_York"

    assert {:error, :setup_unavailable} =
             call(fn ->
               Accounts.consume_setup(%{
                 token: issued.token,
                 password: "another correct horse battery staple",
                 timezone: "America/Chicago",
                 accepted_at: DateTime.add(@now, 120, :second)
               })
             end)

    assert {:error, :setup_disabled} =
             call(fn ->
               Accounts.issue_setup_token(now: DateTime.add(@now, 120, :second))
             end)

    assert %{accounts: 1, disabled: true} = setup_counts()
  end

  @tag setup: true
  test "invalid zones and expired capabilities create no account" do
    assert {:ok, issued} =
             call(fn -> Accounts.issue_setup_token(now: @now, ttl_seconds: 60) end)

    assert {:error, :invalid_timezone} =
             call(fn ->
               Accounts.consume_setup(%{
                 token: issued.token,
                 password: "correct horse battery staple",
                 timezone: "UTC-05:00",
                 accepted_at: DateTime.add(@now, 10, :second)
               })
             end)

    assert %{accounts: 0, disabled: false} = setup_counts()

    assert {:error, :setup_unavailable} =
             call(fn ->
               Accounts.consume_setup(%{
                 token: issued.token,
                 password: "correct horse battery staple",
                 timezone: "America/New_York",
                 accepted_at: DateTime.add(@now, 61, :second)
               })
             end)

    assert %{accounts: 0, disabled: false} = setup_counts()
  end

  @tag setup: true
  test "concurrent issuance leaves exactly one usable capability" do
    barrier = start_barrier(2)

    results =
      for _attempt <- 1..2 do
        Task.async(fn ->
          with_connection(fn backend_pid ->
            :ok = await(barrier)
            {backend_pid, Accounts.issue_setup_token(now: @now, ttl_seconds: 900)}
          end)
        end)
      end
      |> Enum.map(&Task.await(&1, 10_000))

    assert results |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> length() == 2

    assert [{:error, :setup_token_active}, {:ok, winner}] =
             results |> Enum.map(&elem(&1, 1)) |> Enum.sort()

    state = inspect_setup_state()
    assert state.token_hash == :crypto.hash(:sha256, winner.token)
    assert %{accounts: 0, disabled: false} = setup_counts()
  end

  @tag setup: true
  test "concurrent consumption has one winner and permanently disables setup" do
    assert {:ok, issued} =
             call(fn -> Accounts.issue_setup_token(now: @now, ttl_seconds: 900) end)

    barrier = start_barrier(2)

    results =
      for timezone <- ["America/New_York", "America/Chicago"] do
        Task.async(fn ->
          with_connection(fn backend_pid ->
            :ok = await(barrier)

            result =
              Accounts.consume_setup(%{
                token: issued.token,
                password: "correct horse battery staple",
                timezone: timezone,
                accepted_at: DateTime.add(@now, 30, :second)
              })

            {backend_pid, result}
          end)
        end)
      end
      |> Enum.map(&Task.await(&1, 20_000))

    assert results |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> length() == 2
    assert 1 == Enum.count(results, fn {_pid, result} -> match?({:ok, _}, result) end)

    assert 1 ==
             Enum.count(results, fn {_pid, result} ->
               result == {:error, :setup_unavailable}
             end)

    assert %{accounts: 1, disabled: true} = setup_counts()
  end

  @tag setup: true
  test "operator task prints one setup URL and no credential in surrounding output" do
    output =
      capture_io(fn ->
        call(fn ->
          Mix.Tasks.Keepling.SetupToken.run([
            "--base-url",
            "https://keepling.example",
            "--ttl-seconds",
            "900"
          ])
        end)
      end)

    assert [url] = Regex.scan(~r{https://keepling\.example/setup\?token=[A-Za-z0-9_-]+}, output)
    assert output =~ "Setup link (shown once):"
    assert output =~ "expires"
    refute output =~ "password"
    refute output =~ "account"
    assert url != ""
  end

  @tag setup: true
  test "issuance is bounded short-lived and an existing account durably disables setup" do
    assert {:error, :invalid_ttl} =
             call(fn -> Accounts.issue_setup_token(now: @now, ttl_seconds: 59) end)

    assert {:error, :invalid_ttl} =
             call(fn -> Accounts.issue_setup_token(now: @now, ttl_seconds: 3_601) end)

    account_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()

    query!(
      """
      INSERT INTO accounts (
        id, singleton_key, password_hash, timezone, inserted_at, updated_at
      )
      VALUES ($1, TRUE, '$argon2id$test-fixture', 'Etc/UTC', $2, $2)
      """,
      [account_id, @now]
    )

    assert {:error, :setup_disabled} =
             call(fn -> Accounts.issue_setup_token(now: @now, ttl_seconds: 900) end)

    assert inspect_setup_state().consumed_at == @now
    assert inspect_setup_state().disabled_at == @now
  end

  @tag setup: true
  test "database rejects future account rows without setup-owned credential and timezone" do
    account_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()

    assert_raise Postgrex.Error, fn ->
      query!(
        """
        INSERT INTO accounts (id, singleton_key, inserted_at, updated_at)
        VALUES ($1, TRUE, $2, $2)
        """,
        [account_id, @now]
      )
    end
  end

  @tag setup: true
  test "vendored timezone data never starts a remote updater" do
    assert Application.fetch_env(:tzdata, :autoupdate) == {:ok, :disabled}
    refute Process.whereis(:tzdata_release_updater)
  end

  defp inspect_setup_state do
    %{rows: [[token_hash, expires_at, consumed_at, disabled_at]]} =
      query!("SELECT token_hash, expires_at, consumed_at, disabled_at FROM account_setup")

    %{
      consumed_at: as_utc(consumed_at),
      disabled_at: as_utc(disabled_at),
      expires_at: as_utc(expires_at),
      token_hash: token_hash
    }
  end

  defp setup_counts do
    %{rows: [[accounts, disabled]]} =
      query!("""
      SELECT
        (SELECT count(*) FROM accounts),
        COALESCE((SELECT disabled_at IS NOT NULL FROM account_setup), FALSE)
      """)

    %{accounts: accounts, disabled: disabled}
  end

  defp reset_account_state do
    with_connection(fn _backend_pid ->
      SQL.query!(Repo, "DELETE FROM accounts", [])
      SQL.query!(Repo, "DELETE FROM account_setup", [])
    end)
  end

  defp query!(statement, params \\ []) do
    with_connection(fn _backend_pid -> SQL.query!(Repo, statement, params) end)
  end

  defp call(fun), do: with_connection(fn _backend_pid -> fun.() end)

  defp as_utc(%DateTime{} = value), do: value
  defp as_utc(%NaiveDateTime{} = value), do: DateTime.from_naive!(value, "Etc/UTC")
  defp as_utc(nil), do: nil
end

defmodule KeeplingWeb.SetupControllerTest do
  use KeeplingWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL
  alias Keepling.Accounts
  alias Keepling.Repo

  setup do
    SQL.query!(Repo, "DELETE FROM accounts", [])
    SQL.query!(Repo, "DELETE FROM account_setup", [])
    :ok
  end

  @tag setup: true
  test "versioned setup endpoint returns no account or credential identifiers", %{conn: conn} do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    assert {:ok, issued} = Accounts.issue_setup_token(now: now)

    response =
      conn
      |> post("/api/v1/setup", %{
        "password" => "correct horse battery staple",
        "timezone" => "America/New_York",
        "token" => issued.token,
        "version" => 1
      })
      |> json_response(201)

    assert response == %{"status" => "setup_complete", "timezone" => "America/New_York"}
    refute inspect(response) =~ issued.token

    unavailable =
      build_conn()
      |> post("/api/v1/setup", %{
        "password" => "correct horse battery staple",
        "timezone" => "America/New_York",
        "token" => issued.token,
        "version" => 1
      })
      |> json_response(422)

    assert unavailable["code"] == "setup_unavailable"
    refute inspect(unavailable) =~ issued.token
  end
end

defmodule Keepling.Accounts.TimezoneTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO
  import Keepling.ConcurrencyCase

  alias Ecto.Adapters.SQL
  alias Keepling.Accounts
  alias Keepling.Repo

  @now ~U[2026-08-30 19:00:00.000000Z]

  setup do
    reset_account_state()
    create_account("America/New_York")
    on_exit(&reset_account_state/0)
    :ok
  end

  @tag timezone: true
  test "timezone change reinterprets the account day without rewriting task time" do
    boundary = ~U[2026-03-08 07:30:00.000000Z]
    task_id = insert_task(boundary)

    assert {:ok, ~D[2026-03-08]} = call(fn -> Accounts.account_date_at(boundary) end)

    assert {:ok,
            %{
              activity_view_revision: 2,
              timezone: "America/Los_Angeles",
              today_view_revision: 2,
              upcoming_view_revision: 2
            }} =
             call(fn ->
               Accounts.change_timezone("America/Los_Angeles", accepted_at: @now)
             end)

    assert {:ok, ~D[2026-03-07]} = call(fn -> Accounts.account_date_at(boundary) end)
    assert stored_task_time(task_id) == boundary

    assert %{rows: [["timezone_changed", 1, accepted_at]]} =
             query!("SELECT event_type, event_version, accepted_at FROM account_security_audits")

    assert as_utc(accepted_at) == @now
  end

  @tag timezone: true
  test "invalid IANA names and fixed offsets are exact no-ops" do
    before = account_setting_state()

    for invalid <- ["UTC-05:00", "+05:00", "device-default", "America/Not_A_Zone"] do
      assert {:error, :invalid_timezone} =
               call(fn -> Accounts.change_timezone(invalid, accepted_at: @now) end)
    end

    assert account_setting_state() == before
    assert %{rows: [[0]]} = query!("SELECT count(*) FROM account_security_audits")
  end

  @tag timezone: true
  test "concurrent changes serialize and invalidate every affected projection" do
    barrier = start_barrier(2)

    results =
      for timezone <- ["America/Chicago", "America/Los_Angeles"] do
        Task.async(fn ->
          with_connection(fn backend_pid ->
            :ok = await(barrier)

            {backend_pid,
             Accounts.change_timezone(timezone,
               accepted_at: DateTime.add(@now, 30, :second)
             )}
          end)
        end)
      end
      |> Enum.map(&Task.await(&1, 10_000))

    assert results |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> length() == 2
    assert Enum.all?(results, fn {_pid, result} -> match?({:ok, _}, result) end)

    state = account_setting_state()
    assert state.timezone in ["America/Chicago", "America/Los_Angeles"]
    assert state.today_view_revision == 3
    assert state.upcoming_view_revision == 3
    assert state.activity_view_revision == 3
    assert %{rows: [[2]]} = query!("SELECT count(*) FROM account_security_audits")
  end

  @tag timezone: true
  test "operator task uses the shared command and prints no account identifier" do
    raw_account_id = account_setting_state().id |> Ecto.UUID.load!()

    output =
      capture_io(fn ->
        call(fn -> Mix.Tasks.Keepling.Timezone.run(["America/Chicago"]) end)
      end)

    assert output =~ "Account timezone updated."
    assert output =~ "Affected views will refresh."
    refute output =~ raw_account_id
    assert account_setting_state().timezone == "America/Chicago"
  end

  defp create_account(timezone) do
    issued =
      call(fn -> Accounts.issue_setup_token(now: @now, ttl_seconds: 900) end)
      |> then(fn {:ok, issued} -> issued end)

    assert {:ok, %{timezone: ^timezone}} =
             call(fn ->
               Accounts.consume_setup(%{
                 token: issued.token,
                 password: "correct horse battery staple",
                 timezone: timezone,
                 accepted_at: DateTime.add(@now, 1, :second)
               })
             end)
  end

  defp insert_task(captured_at) do
    task_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()
    account_id = account_setting_state().id

    query!(
      """
      INSERT INTO tasks (
        account_id, id, title, inbox_state, revision, captured_at, inserted_at, updated_at
      )
      VALUES ($1, $2, 'Keep the exact instant', 'inbox', 1, $3, $3, $3)
      """,
      [account_id, task_id, captured_at]
    )

    task_id
  end

  defp stored_task_time(task_id) do
    %{rows: [[captured_at]]} = query!("SELECT captured_at FROM tasks WHERE id = $1", [task_id])
    as_utc(captured_at)
  end

  defp account_setting_state do
    %{rows: [[id, timezone, today, upcoming, activity]]} =
      query!("""
      SELECT id, timezone, today_view_revision, upcoming_view_revision,
             activity_view_revision
      FROM accounts
      WHERE singleton_key = TRUE
      """)

    %{
      activity_view_revision: activity,
      id: id,
      timezone: timezone,
      today_view_revision: today,
      upcoming_view_revision: upcoming
    }
  end

  defp reset_account_state do
    with_connection(fn _backend_pid ->
      SQL.query!(Repo, "DELETE FROM accounts", [])
      SQL.query!(Repo, "DELETE FROM account_setup", [])
    end)
  end

  defp query!(statement, params \\ []) do
    with_connection(fn _backend_pid -> SQL.query!(Repo, statement, params) end)
  end

  defp call(fun), do: with_connection(fn _backend_pid -> fun.() end)

  defp as_utc(%DateTime{} = value), do: value
  defp as_utc(%NaiveDateTime{} = value), do: DateTime.from_naive!(value, "Etc/UTC")
end
