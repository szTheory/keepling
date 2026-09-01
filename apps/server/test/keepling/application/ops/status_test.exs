defmodule Keepling.Application.Ops.StatusTest do
  use Keepling.DataCase, async: false

  alias Keepling.Adapters.Postgres.OpsStore
  alias Keepling.Application.Ops

  @verbs ~w(preflight status doctor backup restore restore-verify deploy upgrade replace-host)
  @closed_keys ~w(code exit_code facts operation remediation retryable status version)

  defmodule FakePort do
    @behaviour Keepling.Application.Ops.Port

    @impl true
    def inspect(options), do: Map.fetch!(options, :inspection)

    @impl true
    def execute(operation, _input, options) do
      send(Map.fetch!(options, :test_pid), {:executed, operation})
      Map.get(options, :execution_result, :ok)
    end
  end

  test "all nine verbs return one closed JSON-compatible result and stable exit class" do
    options = %{inspection: {:ok, healthy_inspection()}, test_pid: self()}

    for operation <- @verbs do
      input = valid_input(operation)
      result = Ops.run(operation, input, FakePort, options)

      assert Map.keys(result) |> Enum.sort() == Enum.sort(@closed_keys)
      assert result["version"] == 1
      assert result["operation"] == operation
      assert result["status"] == "ok"
      assert result["exit_code"] == 0
      assert is_binary(result["code"])
      assert is_map(result["facts"])
      assert is_list(result["remediation"])
      assert Jason.encode!(result)
    end
  end

  test "status exposes every bounded D-43 fact without raw identifiers or content" do
    hostile = "task-title private-token account-id source-host"

    result =
      Ops.run("status", %{}, FakePort, %{
        inspection: {:ok, healthy_inspection()},
        test_pid: self(),
        ignored_hostile_value: hostile
      })

    assert result["facts"] == %{
             "backup" => %{"age_seconds" => 60, "state" => "current"},
             "database" => "available",
             "last_restore_verification" => %{
               "completed_at" => "2026-09-01T07:00:00Z",
               "state" => "passed",
               "verifier_version" => 1
             },
             "migrations" => %{"pending_count" => 0, "state" => "finalized"},
             "protocol_range" => %{"maximum" => 1, "minimum" => 1},
             "release_revision" => "dogfood",
             "restore_epoch" => "finalized",
             "schema" => %{"current" => 15, "maximum" => 15, "minimum" => 1},
             "tested_oci_digest" => "sha256:" <> String.duplicate("0", 64),
             "traffic" => "accepting",
             "wal" => %{"lag_seconds" => 30, "state" => "current"}
           }

    refute Jason.encode!(result) =~ hostile
    refute Jason.encode!(result) =~ "account_id"
    refute Jason.encode!(result) =~ "source_host"
  end

  test "backup and WAL lag degrade status and refuse deploy preflight with copyable remediation" do
    lagging =
      healthy_inspection()
      |> put_in(["backup", "age_seconds"], 301)
      |> put_in(["backup", "state"], "lagging")
      |> put_in(["wal", "lag_seconds"], 301)
      |> put_in(["wal", "state"], "lagging")

    status = Ops.run("status", %{}, FakePort, %{inspection: {:ok, lagging}, test_pid: self()})

    assert status["status"] == "degraded"
    assert status["code"] == "backup_rpo_not_met"
    assert status["exit_code"] == Ops.exit_code(:dependency)
    assert status["remediation"] == ["Run `keepling ops backup --json` and inspect archive health."]

    deploy =
      Ops.run("deploy", valid_input("deploy"), FakePort, %{
        inspection: {:ok, lagging},
        test_pid: self()
      })

    assert deploy["status"] == "refused"
    assert deploy["code"] == "deploy_backup_rpo_not_met"
    assert deploy["exit_code"] == Ops.exit_code(:refusal)
    refute_received {:executed, "deploy"}
  end

  test "unsafe destructive arguments fail closed before the outward adapter runs" do
    options = %{inspection: {:ok, healthy_inspection()}, test_pid: self()}

    for operation <- ~w(restore restore-verify deploy upgrade replace-host) do
      result = Ops.run(operation, %{"target" => "production"}, FakePort, options)

      assert result["status"] == "refused"
      assert result["exit_code"] == Ops.exit_code(:refusal)
      assert result["retryable"] == false
      assert result["remediation"] != []
      refute Jason.encode!(result) =~ "production"
      refute_received {:executed, ^operation}
    end
  end

  test "dependency failures use a bounded failure class without exception inspection" do
    result =
      Ops.run("doctor", %{}, FakePort, %{
        inspection: {:error, :database_unavailable},
        test_pid: self()
      })

    assert result == %{
             "code" => "database_unavailable",
             "exit_code" => Ops.exit_code(:dependency),
             "facts" => %{"database" => "unavailable"},
             "operation" => "doctor",
             "remediation" => ["Check PostgreSQL connectivity and retry the command."],
             "retryable" => true,
             "status" => "failed",
             "version" => 1
           }
  end

  test "PostgreSQL store retains only bounded singleton state and digested restore proof" do
    proof = %{
      source_backup_digest: :crypto.hash(:sha256, "backup-opaque-id"),
      target_recovery_point: ~U[2026-09-01 06:55:00Z],
      verifier_version: 1,
      started_at: ~U[2026-09-01 06:56:00Z],
      finished_at: ~U[2026-09-01 07:00:00Z],
      result_code: "passed"
    }

    assert :ok = OpsStore.record_restore_verification(proof)
    assert {:ok, inspection} = OpsStore.inspect(timeout_ms: 250)
    assert inspection["last_restore_verification"] == %{
             "completed_at" => "2026-09-01T07:00:00Z",
             "state" => "passed",
             "verifier_version" => 1
           }

    %{rows: [[stored_digest]]} =
      Ecto.Adapters.SQL.query!(
        Keepling.Repo,
        "SELECT source_backup_digest FROM restore_verifications ORDER BY finished_at DESC LIMIT 1",
        []
      )

    assert stored_digest == proof.source_backup_digest
    refute inspect(stored_digest) =~ "backup-opaque-id"
  end

  defp valid_input(operation) when operation in ~w(restore restore-verify) do
    %{
      "confirmed" => true,
      "source_digest" => "sha256:" <> String.duplicate("a", 64),
      "target_class" => "empty_isolated"
    }
  end

  defp valid_input(operation) when operation in ~w(deploy upgrade replace-host) do
    %{
      "confirmed" => true,
      "target_class" => "replaceable_candidate",
      "tested_oci_digest" => "sha256:" <> String.duplicate("0", 64)
    }
  end

  defp valid_input(_operation), do: %{}

  defp healthy_inspection do
    %{
      "backup" => %{"age_seconds" => 60, "state" => "current"},
      "database" => "available",
      "last_restore_verification" => %{
        "completed_at" => "2026-09-01T07:00:00Z",
        "state" => "passed",
        "verifier_version" => 1
      },
      "migrations" => %{"pending_count" => 0, "state" => "finalized"},
      "protocol_range" => %{"maximum" => 1, "minimum" => 1},
      "release_revision" => "dogfood",
      "restore_epoch" => "finalized",
      "schema" => %{"current" => 15, "maximum" => 15, "minimum" => 1},
      "tested_oci_digest" => "sha256:" <> String.duplicate("0", 64),
      "traffic" => "accepting",
      "wal" => %{"lag_seconds" => 30, "state" => "current"}
    }
  end
end
