defmodule Keepling.Domain.TaskDatesTest do
  use ExUnit.Case, async: true

  alias Keepling.Domain.{Task, TaskDates}

  @accepted_at ~U[2026-08-31 04:30:00.000000Z]

  test "the configured IANA zone and injected instant define one account civil day" do
    assert {:ok, ~D[2026-08-30]} =
             TaskDates.account_day(@accepted_at, "America/Los_Angeles")

    assert {:ok, ~D[2026-08-31]} =
             TaskDates.account_day(@accepted_at, "America/New_York")

    assert {:ok, ~D[2026-03-07]} =
             TaskDates.account_day(~U[2026-03-08 04:59:59.999999Z], "America/New_York")

    assert {:ok, ~D[2026-03-08]} =
             TaskDates.account_day(~U[2026-03-08 05:00:00.000000Z], "America/New_York")

    assert {:error, :invalid_timezone} =
             TaskDates.account_day(@accepted_at, "UTC-08:00")
  end

  test "the versioned truth table keeps Today intent, deadlines, and upcoming separate" do
    vectors = task_date_vectors()

    assert vectors["version"] == 1
    assert vectors["date_format"] == "YYYY-MM-DD"
    assert vectors["unsupported"] == ["exact_times", "recurrence", "reminders", "start_dates"]

    for vector <- vectors["cases"] do
      planned_on = parse_optional_date(vector["planned_on"])
      deadline_on = parse_optional_date(vector["deadline_on"])
      account_day = Date.from_iso8601!(vector["account_day"])

      assert TaskDates.classify(planned_on, deadline_on, account_day) ==
               atomize_classification(vector["classification"]),
             vector["name"]
    end
  end

  test "date edits, plan Today, and unplan preserve the independent deadline and warning" do
    task = task(planned_on: nil, deadline_on: ~D[2026-08-30])

    assert {:ok, planned, planned_activity, :accepted, [:planned_after_deadline]} =
             TaskDates.plan_for_today(
               task,
               %{accepted_at: @accepted_at, base_planned_on: nil, expected_revision: 1},
               ~D[2026-08-31]
             )

    assert planned.planned_on == ~D[2026-08-31]
    assert planned.deadline_on == ~D[2026-08-30]
    assert planned.revision == 2
    assert planned_activity.type == :task_planned

    assert planned_activity.changed_fields == %{
             "planned_on" => %{"from" => nil, "to" => ~D[2026-08-31]}
           }

    assert {:ok, edited, edited_activity, :accepted, []} =
             TaskDates.edit(planned, %{
               accepted_at: @accepted_at,
               base_values: %{deadline_on: ~D[2026-08-30], planned_on: ~D[2026-08-31]},
               expected_revision: 2,
               fields: %{deadline_on: ~D[2026-09-02], planned_on: ~D[2026-08-31]}
             })

    assert edited.planned_on == ~D[2026-08-31]
    assert edited.deadline_on == ~D[2026-09-02]
    assert edited_activity.type == :task_details_updated

    assert {:ok, unplanned, unplanned_activity, :accepted, []} =
             TaskDates.unplan(edited, %{
               accepted_at: @accepted_at,
               base_planned_on: ~D[2026-08-31],
               expected_revision: 3
             })

    assert unplanned.planned_on == nil
    assert unplanned.deadline_on == ~D[2026-09-02]
    assert unplanned_activity.type == :task_unplanned
  end

  test "date changes use touched base values and never silently win an overlap" do
    task = task(planned_on: ~D[2026-09-01], deadline_on: nil, revision: 4)

    assert {:error, {:edit_conflict, ["planned_on"]}} =
             TaskDates.edit(task, %{
               accepted_at: @accepted_at,
               base_values: %{planned_on: ~D[2026-08-31]},
               expected_revision: 3,
               fields: %{planned_on: ~D[2026-09-02]}
             })

    assert {:ok, unchanged, nil, :already_satisfied, []} =
             TaskDates.edit(task, %{
               accepted_at: @accepted_at,
               base_values: %{planned_on: ~D[2026-08-31]},
               expected_revision: 3,
               fields: %{planned_on: ~D[2026-09-01]}
             })

    assert unchanged == task
  end

  test "the sole migration and closed transport artifacts own the temporal shape" do
    root = Path.expand("../../../../../", __DIR__)

    migration =
      File.read!(
        Path.join(root, "apps/server/priv/repo/migrations/20260830000600_add_task_dates.exs")
      )

    openapi = File.read!(Path.join(root, "packages/contracts/openapi/keepling.yaml"))
    generated = File.read!(Path.join(root, "packages/contracts/generated/keepling.ts"))

    assert migration =~ "add :planned_on, :date"
    assert migration =~ "add :deadline_on, :date"
    assert openapi =~ "/commands/plan-for-today:"
    assert openapi =~ "/commands/unplan-task:"
    assert openapi =~ "/commands/edit-task-dates:"
    assert openapi =~ "PlanForTodayRequest:"
    assert openapi =~ "planned_on:"
    assert openapi =~ "deadline_on:"
    assert generated =~ "PlanForTodayRequest"
  end

  defp task(overrides) do
    struct!(
      Task,
      Keyword.merge(
        [
          captured_at: ~U[2026-08-30 20:00:00.000000Z],
          deadline_on: nil,
          id: "018d8b40-2f10-7b1a-9d71-263f4af77001",
          inbox_state: :inbox,
          notes: "",
          planned_on: nil,
          revision: 1,
          title: "Keep dates distinct"
        ],
        overrides
      )
    )
  end

  defp parse_optional_date(nil), do: nil
  defp parse_optional_date(value), do: Date.from_iso8601!(value)

  defp atomize_classification(classification) do
    %{
      today_reasons: Enum.map(classification["today_reasons"], &classification_atom/1),
      today_section: optional_classification_atom(classification["today_section"]),
      upcoming_on: parse_optional_date(classification["upcoming_on"]),
      upcoming_reason: optional_classification_atom(classification["upcoming_reason"]),
      warnings: Enum.map(classification["warnings"], &classification_atom/1)
    }
  end

  defp optional_classification_atom(nil), do: nil
  defp optional_classification_atom(value), do: classification_atom(value)

  defp classification_atom("deadline"), do: :deadline
  defp classification_atom("deadline_overdue"), do: :deadline_overdue
  defp classification_atom("deadline_today"), do: :deadline_today
  defp classification_atom("overdue"), do: :overdue
  defp classification_atom("planned"), do: :planned
  defp classification_atom("planned_after_deadline"), do: :planned_after_deadline
  defp classification_atom("planned_overdue"), do: :planned_overdue
  defp classification_atom("planned_today"), do: :planned_today
  defp classification_atom("today"), do: :today

  defp task_date_vectors do
    path = Path.expand("../../../../../packages/contracts/vectors/task-dates.json", __DIR__)
    path |> File.read!() |> Jason.decode!()
  end
end

defmodule KeeplingWeb.TaskDatesBoundaryTest do
  use KeeplingWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL
  alias Keepling.Repo

  setup %{conn: conn} do
    account_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    SQL.query!(
      Repo,
      """
      INSERT INTO accounts (
        id, singleton_key, password_hash, timezone, inserted_at, updated_at
      )
      VALUES ($1, TRUE, '$argon2id$test-fixture', 'America/Los_Angeles', $2, $2)
      """,
      [account_id, now]
    )

    previous_seed = System.get_env("KEEPLING_E2E_SEED")
    System.put_env("KEEPLING_E2E_SEED", "phase-1")

    on_exit(fn ->
      if previous_seed,
        do: System.put_env("KEEPLING_E2E_SEED", previous_seed),
        else: System.delete_env("KEEPLING_E2E_SEED")
    end)

    login = conn |> trusted_request() |> post("/api/v1/test/session")

    %{conn: login, csrf_token: json_response(login, 200)["csrf_token"]}
  end

  test "closed Phoenix date commands preserve separate fields through exact acknowledgements", %{
    conn: conn,
    csrf_token: csrf_token
  } do
    task_id = Ecto.UUID.generate()

    captured =
      command(conn, csrf_token, "/api/v1/commands/capture-task", %{
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "title" => "Use civil dates",
        "version" => 1
      })

    assert %{
             "revision" => 1,
             "snapshot" => %{"deadline_on" => nil, "planned_on" => nil}
           } = json_response(captured, 201)

    before_day = account_day_now()

    planned =
      command(conn, csrf_token, "/api/v1/commands/plan-for-today", %{
        "base_planned_on" => nil,
        "expected_revision" => 1,
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "version" => 1
      })

    after_day = account_day_now()
    planned_body = json_response(planned, 200)
    planned_on = planned_body["snapshot"]["planned_on"]

    assert planned_body["revision"] == 2
    assert planned_on in Enum.uniq([before_day, after_day])

    dated =
      command(conn, csrf_token, "/api/v1/commands/edit-task-dates", %{
        "base_values" => %{"deadline_on" => nil},
        "expected_revision" => 2,
        "fields" => %{"deadline_on" => "2026-01-01"},
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "version" => 1
      })

    assert %{
             "revision" => 3,
             "snapshot" => %{
               "deadline_on" => "2026-01-01",
               "planned_on" => ^planned_on
             },
             "warnings" => [%{"code" => "planned_after_deadline"}]
           } = json_response(dated, 200)

    unplanned =
      command(conn, csrf_token, "/api/v1/commands/unplan-task", %{
        "base_planned_on" => planned_on,
        "expected_revision" => 3,
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "version" => 1
      })

    assert %{
             "revision" => 4,
             "snapshot" => %{"deadline_on" => "2026-01-01", "planned_on" => nil}
           } = json_response(unplanned, 200)

    invalid =
      command(conn, csrf_token, "/api/v1/commands/plan-for-today", %{
        "base_planned_on" => nil,
        "expected_revision" => 4,
        "mutation_id" => Ecto.UUID.generate(),
        "planned_on" => "2099-01-01",
        "task_id" => task_id,
        "version" => 1
      })

    assert %{"code" => "invalid_command"} = json_response(invalid, 400)
  end

  defp command(conn, csrf_token, path, body) do
    conn
    |> recycle()
    |> trusted_request()
    |> enforce_csrf()
    |> put_req_header("x-csrf-token", csrf_token)
    |> post(path, body)
  end

  defp account_day_now do
    DateTime.utc_now()
    |> DateTime.shift_zone!("America/Los_Angeles")
    |> DateTime.to_date()
    |> Date.to_iso8601()
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
end

defmodule Keepling.Application.TaskDatesPersistenceTest do
  use Keepling.DataCase, async: false

  alias Ecto.Adapters.SQL
  alias Keepling.Adapters.Postgres.CommandStore
  alias Keepling.Application.Commands
  alias Keepling.Repo

  @accepted_at ~U[2026-08-31 04:30:00.000000Z]

  setup do
    account_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()

    SQL.query!(
      Repo,
      """
      INSERT INTO accounts (
        id, singleton_key, password_hash, timezone, inserted_at, updated_at
      )
      VALUES ($1, TRUE, '$argon2id$test-fixture', 'America/Los_Angeles', $2, $2)
      """,
      [account_id, @accepted_at]
    )

    %{account_id: account_id}
  end

  test "semantic commands round-trip dates, warnings, revisions, and account-day acceptance", %{
    account_id: account_id
  } do
    task_id = Ecto.UUID.generate()

    assert {:ok, %{status: 201, body: %{"revision" => 1}}} =
             dispatch(account_id, @accepted_at, %{
               mutation_id: Ecto.UUID.generate(),
               task_id: task_id,
               title: "Use the account day",
               type: :capture_task,
               version: 1
             })

    plan_command = %{
      base_planned_on: nil,
      expected_revision: 1,
      mutation_id: Ecto.UUID.generate(),
      task_id: task_id,
      type: :plan_for_today,
      version: 1
    }

    assert {:ok,
            %{
              status: 200,
              body: %{
                "revision" => 2,
                "snapshot" => %{
                  "deadline_on" => nil,
                  "planned_on" => "2026-08-30"
                },
                "warnings" => []
              }
            }} = dispatch(account_id, @accepted_at, plan_command)

    assert dispatch(account_id, DateTime.add(@accepted_at, 60, :second), plan_command) ==
             dispatch(account_id, @accepted_at, plan_command)

    SQL.query!(
      Repo,
      "UPDATE accounts SET timezone = 'America/New_York' WHERE id = $1",
      [account_id]
    )

    assert %{rows: [[~D[2026-08-30], nil]]} =
             SQL.query!(
               Repo,
               "SELECT planned_on, deadline_on FROM tasks WHERE account_id = $1 AND id = $2",
               [account_id, Ecto.UUID.dump!(task_id)]
             )

    assert {:ok,
            %{
              status: 200,
              body: %{
                "revision" => 3,
                "snapshot" => %{
                  "deadline_on" => "2026-08-29",
                  "planned_on" => "2026-08-30"
                },
                "warnings" => [
                  %{
                    "code" => "planned_after_deadline",
                    "message" => "Planned date is after the deadline. Both dates will be saved."
                  }
                ]
              }
            }} =
             dispatch(account_id, DateTime.add(@accepted_at, 120, :second), %{
               base_values: %{deadline_on: nil},
               expected_revision: 2,
               fields: %{deadline_on: ~D[2026-08-29]},
               mutation_id: Ecto.UUID.generate(),
               task_id: task_id,
               type: :edit_task_dates,
               version: 1
             })

    assert {:ok,
            %{
              status: 200,
              body: %{
                "revision" => 4,
                "snapshot" => %{
                  "deadline_on" => "2026-08-29",
                  "planned_on" => nil
                },
                "warnings" => []
              }
            }} =
             dispatch(account_id, DateTime.add(@accepted_at, 180, :second), %{
               base_planned_on: ~D[2026-08-30],
               expected_revision: 3,
               mutation_id: Ecto.UUID.generate(),
               task_id: task_id,
               type: :unplan_task,
               version: 1
             })

    assert %{rows: [[4, 4, 5]]} =
             SQL.query!(
               Repo,
               """
               SELECT today_view_revision, upcoming_view_revision, activity_view_revision
               FROM accounts WHERE id = $1
               """,
               [account_id]
             )
  end

  defp dispatch(account_id, accepted_at, command) do
    Commands.dispatch(
      command,
      %{
        accepted_at: accepted_at,
        account_id: account_id,
        actor_type: "user",
        client_kind: "web"
      },
      CommandStore
    )
  end
end
