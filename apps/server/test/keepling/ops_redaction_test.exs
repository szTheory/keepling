defmodule Keepling.OpsRedactionTest do
  use ExUnit.Case, async: true

  alias Keepling.Application.Ops

  @hostile_values [
    "HOSTILE_TASK_TITLE_SENTINEL_DO_NOT_EMIT",
    "HOSTILE_TASK_NOTE_SENTINEL_DO_NOT_EMIT",
    "HOSTILE_PROMPT_SENTINEL_DO_NOT_EMIT",
    "HOSTILE_RECOVERY_TOKEN_SENTINEL_DO_NOT_EMIT",
    "HOSTILE_SYNC_CURSOR_SENTINEL_DO_NOT_EMIT",
    "00000000-0000-4000-8000-000000000099",
    "HOSTILE_PROVIDER_ERROR_SENTINEL_DO_NOT_EMIT"
  ]

  defmodule HostilePort do
    @behaviour Keepling.Application.Ops.Port

    @impl true
    def inspect(_options) do
      {:ok,
       %{
         "database" => "unavailable",
         "untrusted_provider_body" => "HOSTILE_PROVIDER_ERROR_SENTINEL_DO_NOT_EMIT",
         "untrusted_task_title" => "HOSTILE_TASK_TITLE_SENTINEL_DO_NOT_EMIT"
       }}
    end

    @impl true
    def execute(_operation, _input, _options), do: {:error, :execution_failed}
  end

  test "operator envelopes never reflect hostile diagnostic input" do
    for operation <- Ops.verbs() do
      result = Ops.run(operation, %{}, HostilePort, %{})
      serialized = Jason.encode!(result)

      assert Map.keys(result) |> Enum.sort() ==
               ~w(code exit_code facts operation remediation retryable status version)

      for hostile <- @hostile_values do
        refute serialized =~ hostile
      end
    end
  end

  test "invalid arguments never reflect hostile values" do
    serialized = Ops.invalid_result(Enum.join(@hostile_values, ":")) |> Jason.encode!()

    for hostile <- @hostile_values do
      refute serialized =~ hostile
    end

    assert Jason.decode!(serialized)["operation"] == "unknown"
  end

  test "privacy scanner covers every retained diagnostic surface" do
    root = Path.expand("../../../..", __DIR__)
    source = File.read!(Path.join(root, "tooling/verify-privacy.sh"))

    for surface <-
          ~w(logs metrics traces stdout stderr results.json manifest.json plan.tfplan backup.out doctor-bundle.txt) do
      assert source =~ surface
    end

    assert source =~ "hostile_sentinels"
    assert source =~ "grep -aF -f"
  end
end
