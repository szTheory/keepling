defmodule Keepling.Application.CompatibilityTest do
  use ExUnit.Case, async: true

  alias Keepling.Application.Compatibility
  alias Keepling.Application.Sync.Cursor

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

  test "current and previous receipt cursor and generated fixtures remain executable" do
    vectors = vectors()
    server_policy = server_policy(vectors, "highest distributed intersection wins")
    now = ~U[2026-09-01 12:00:00Z]
    keyring = %{active: "v1", keys: %{"v1" => String.duplicate("compat-cursor-key", 2)}}

    assert Enum.map(vectors["codec_fixtures"], & &1["protocol_train"]) == [1, 2]

    for fixture <- vectors["codec_fixtures"] do
      receipt = Jason.decode!(fixture["receipt"])
      assert receipt["protocol_train"] == fixture["protocol_train"]
      assert receipt["outcome"] == "accepted"
      assert fixture["receipt_codec"] == 1
      assert fixture["cursor_codec"] == 1

      namespace = sync_namespace(fixture["protocol_train"])
      position = %{sequence: 9, ordinal: fixture["protocol_train"]}
      cursor = Cursor.encode(position, namespace, keyring, now)
      assert {:ok, ^position} = Cursor.decode(cursor, namespace, keyring, now)

      claims = %{
        "minimum_protocol_train" => fixture["protocol_train"],
        "maximum_protocol_train" => fixture["protocol_train"]
      }

      assert Compatibility.negotiate(claims, server_policy) == fixture["generated_response"]
    end
  end

  test "every compatibility lane executes exact image schema and train inputs" do
    vectors = vectors()

    for lane <- vectors["matrix"]["lanes"] do
      policy = server_policy(vectors, lane["server_case"])
      artifact = vectors["artifacts"][lane["artifact"]]

      negotiation = Compatibility.negotiate(lane["client_range"], policy)
      artifact_result = Compatibility.artifact_compatibility(artifact, lane["target"])

      assert negotiation["recovery_code"] == lane["expected_negotiation_code"], lane["name"]
      assert artifact_result["code"] == lane["expected_artifact_code"], lane["name"]
      assert lane["case_count"] == 2
      assert artifact_result["tested_oci_digest"] == artifact["tested_oci_digest"]
      assert artifact_result["schema"] == lane["target"]["schema"]
      assert artifact_result["protocol_train"] == lane["target"]["protocol_train"]
    end

    known_bad = vectors["matrix"]["known_bad"]

    assert %{"eligible" => false, "code" => code, "retryable" => false} =
             Compatibility.artifact_compatibility(
               vectors["artifacts"][known_bad["artifact"]],
               known_bad["target"]
             )

    assert code == known_bad["expected_artifact_code"]
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

  defp vectors, do: @vectors_path |> File.read!() |> Jason.decode!()

  defp server_policy(vectors, name) do
    vectors["cases"]
    |> Enum.find(&(&1["name"] == name))
    |> Map.fetch!("policy")
  end

  defp sync_namespace(protocol_train) do
    %{
      issuer: "https://id.keepling.test",
      origin: "https://keepling.test",
      server_instance: "compatibility-fixture",
      subject: "00000000-0000-4000-8000-000000000001",
      generation: 1,
      sync_epoch: "00000000-0000-4000-8000-0000000000e1",
      protocol_train: protocol_train
    }
  end
end
