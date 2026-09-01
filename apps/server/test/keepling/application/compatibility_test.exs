defmodule Keepling.Application.CompatibilityTest do
  use ExUnit.Case, async: true

  alias Keepling.Application.Compatibility

  @vectors_path Path.expand(
                  "../../../../../packages/contracts/vectors/compatibility.json",
                  __DIR__
                )

  test "frozen protocol-train cases select one stable outcome" do
    vectors = @vectors_path |> File.read!() |> Jason.decode!()

    for vector <- vectors["cases"] do
      assert Compatibility.negotiate(vector["claims"], vector["policy"]) == vector["expect"],
             vector["name"]
    end
  end

  test "every valid range pair has exactly one non-retrying compatibility outcome" do
    policy = policy()

    for minimum <- 0..4,
        maximum <- minimum..4 do
      result =
        Compatibility.negotiate(
          %{"minimum_protocol_train" => minimum, "maximum_protocol_train" => maximum},
          policy
        )

      assert result["compatibility_state"] in [
               "supported",
               "deprecated_but_safe",
               "unsupported"
             ]

      assert result["recovery_code"] in [
               "continue",
               "client_update_available",
               "client_upgrade_required",
               "server_upgrade_required"
             ]

      if result["compatibility_state"] == "unsupported" do
        assert result["retryable"] == false
        assert result["pending_intent"] == "preserved_locally"
        assert is_nil(result["selected_protocol_train"])
      else
        assert is_integer(result["selected_protocol_train"])
      end
    end
  end

  test "metadata is authoritative and market builds remain descriptive only" do
    metadata = Compatibility.metadata(policy())

    assert metadata["protocol_policy"] == "current_and_previous_90_days"
    assert metadata["server_release"] == "0.2.0-test"
    assert metadata["tested_oci_digest"] == "sha256:" <> String.duplicate("a", 64)
    assert metadata["supported_protocols"]["read"] == %{"minimum" => 1, "maximum" => 2}
    assert metadata["supported_protocols"]["write"] == %{"minimum" => 1, "maximum" => 2}
    assert metadata["supported_protocols"]["sync"] == %{"minimum" => 1, "maximum" => 2}
    assert metadata["schema_range"] == %{"minimum" => 1, "maximum" => 3}
    assert metadata["platform_minimum_builds"] == %{"electron" => 17, "iphone" => 23}

    changed_builds =
      policy()
      |> put_in(["platform_minimum_builds", "electron"], 9_999)
      |> put_in(["platform_minimum_builds", "iphone"], 9_999)

    claims = %{"minimum_protocol_train" => 1, "maximum_protocol_train" => 2}

    assert Compatibility.negotiate(claims, changed_builds) ==
             Compatibility.negotiate(claims, policy())
  end

  defp policy do
    %{
      "now" => "2026-09-01T12:00:00Z",
      "server_release" => "0.2.0-test",
      "tested_oci_digest" => "sha256:" <> String.duplicate("a", 64),
      "distribution" => "distributed",
      "current_protocol_train" => 2,
      "previous_protocol_train" => 1,
      "previous_superseded_at" => "2026-06-15T12:00:00Z",
      "deprecation_deadline" => "2026-09-13T12:00:00Z",
      "emergency_override" => nil,
      "supported_protocols" => %{
        "read" => %{"minimum" => 1, "maximum" => 2},
        "write" => %{"minimum" => 1, "maximum" => 2},
        "sync" => %{"minimum" => 1, "maximum" => 2}
      },
      "schema_range" => %{"minimum" => 1, "maximum" => 3},
      "platform_minimum_builds" => %{"electron" => 17, "iphone" => 23},
      "update_location" => "https://keepling.example/downloads"
    }
  end
end
