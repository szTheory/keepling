defmodule KeeplingWeb.HealthTest do
  use KeeplingWeb.ConnCase, async: false

  @operator_token String.duplicate("operator-secret-", 3)

  defmodule FakePort do
    @behaviour Keepling.Application.Ops.Port

    @impl true
    def inspect(_options), do: Process.get(:health_inspection)

    @impl true
    def execute(_operation, _input, _options), do: :ok
  end

  defmodule RaisingPort do
    @behaviour Keepling.Application.Ops.Port

    @impl true
    def inspect(_options), do: raise("liveness touched an outward dependency")

    @impl true
    def execute(_operation, _input, _options), do: raise("unexpected execution")
  end

  setup do
    previous_port = Application.get_env(:keepling, :ops_port)
    previous_hash = Application.get_env(:keepling, :operator_status_token_hash)

    Application.put_env(:keepling, :ops_port, FakePort)

    Application.put_env(
      :keepling,
      :operator_status_token_hash,
      :crypto.hash(:sha256, @operator_token)
    )

    Process.put(:health_inspection, {:ok, healthy_inspection()})

    on_exit(fn ->
      restore_env(:ops_port, previous_port)
      restore_env(:operator_status_token_hash, previous_hash)
    end)

    :ok
  end

  test "public liveness is process-only and never calls PostgreSQL", %{conn: conn} do
    Application.put_env(:keepling, :ops_port, RaisingPort)

    response = conn |> get("/health/live") |> json_response(200)

    assert response == %{"status" => "alive"}
  end

  test "public readiness is minimal and backup lag alone remains ready", %{conn: conn} do
    lagging =
      healthy_inspection()
      |> put_in(["backup"], %{"age_seconds" => 9_999, "state" => "lagging"})
      |> put_in(["wal"], %{"lag_seconds" => 9_999, "state" => "lagging"})

    Process.put(:health_inspection, {:ok, lagging})

    response = conn |> get("/health/ready") |> json_response(200)

    assert response == %{"code" => "ready", "status" => "ready"}
    refute Map.has_key?(response, "facts")
    refute Map.has_key?(response, "remediation")
  end

  test "each serving dependency independently makes readiness fail" do
    cases = [
      {{:error, :database_unavailable}, "database_unavailable"},
      {{:ok,
        put_in(healthy_inspection(), ["migrations"], %{"pending_count" => 1, "state" => "pending"})},
       "migrations_pending"},
      {{:ok, put_in(healthy_inspection(), ["schema", "current"], 2)}, "schema_incompatible"},
      {{:ok, put_in(healthy_inspection(), ["protocol_range"], %{"minimum" => 2, "maximum" => 1})},
       "protocol_incompatible"},
      {{:ok, put_in(healthy_inspection(), ["restore_epoch"], "unfinalized")},
       "restore_epoch_unfinalized"},
      {{:ok, put_in(healthy_inspection(), ["traffic"], "draining")}, "traffic_disabled"}
    ]

    for {inspection, expected_code} <- cases do
      Process.put(:health_inspection, inspection)
      response = build_conn() |> get("/health/ready") |> json_response(503)

      assert response == %{"code" => expected_code, "status" => "not_ready"}
    end
  end

  test "operator status requires the distinct configured credential", %{conn: conn} do
    assert conn |> get("/ops/status") |> json_response(401) == %{
             "code" => "operator_authentication_required",
             "status" => "unauthorized"
           }

    response =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> @operator_token)
      |> get("/ops/status")
      |> json_response(200)

    assert response["operation"] == "status"
    assert response["facts"] == healthy_inspection()
    assert response["exit_code"] == 0
  end

  test "public routes never expose operator backup or restore facts", %{conn: conn} do
    for path <- ["/health/live", "/health/ready"] do
      serialized = conn |> recycle() |> get(path) |> json_response(200) |> Jason.encode!()

      refute serialized =~ "backup"
      refute serialized =~ "wal"
      refute serialized =~ "restore"
      refute serialized =~ "remediation"
      refute serialized =~ "tested_oci_digest"
    end
  end

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
      "schema" => %{"current" => 1, "maximum" => 1, "minimum" => 1},
      "tested_oci_digest" => "sha256:" <> String.duplicate("0", 64),
      "traffic" => "accepting",
      "wal" => %{"lag_seconds" => 30, "state" => "current"}
    }
  end

  defp restore_env(key, nil), do: Application.delete_env(:keepling, key)
  defp restore_env(key, value), do: Application.put_env(:keepling, key, value)
end
