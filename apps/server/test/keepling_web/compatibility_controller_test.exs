defmodule KeeplingWeb.CompatibilityControllerTest do
  use KeeplingWeb.ConnCase, async: false

  alias Keepling.Application.Compatibility

  setup do
    previous = Application.get_env(:keepling, :compatibility)
    Application.put_env(:keepling, :compatibility, policy())

    on_exit(fn ->
      if previous,
        do: Application.put_env(:keepling, :compatibility, previous),
        else: Application.delete_env(:keepling, :compatibility)
    end)

    :ok
  end

  @tag :transport
  test "anonymous clients receive complete authoritative compatibility metadata", %{conn: conn} do
    response =
      conn
      |> get("/compatibility", %{
        "minimum_protocol_train" => "1",
        "maximum_protocol_train" => "2"
      })
      |> json_response(200)

    assert Map.keys(response) |> Enum.sort() ==
             ~w(compatibility_state deprecation_deadline pending_intent platform_minimum_builds protocol_policy recovery_code recovery_codes retryable schema_range selected_protocol_train server_release supported_protocols tested_oci_digest update_location)
             |> Enum.sort()

    assert response["compatibility_state"] == "supported"
    assert response["selected_protocol_train"] == 2
    assert response["recovery_code"] == "continue"
    assert response["retryable"] == false
    assert response["pending_intent"] == "preserved_locally"
    assert response["server_release"] == "0.2.0-test"
    assert response["tested_oci_digest"] == "sha256:" <> String.duplicate("a", 64)

    assert response["supported_protocols"] == %{
             "read" => %{"minimum" => 1, "maximum" => 2},
             "write" => %{"minimum" => 1, "maximum" => 2},
             "sync" => %{"minimum" => 1, "maximum" => 2}
           }

    assert response["schema_range"] == %{"minimum" => 1, "maximum" => 3}
    assert response["platform_minimum_builds"] == %{"electron" => 17, "iphone" => 23}
    assert response["deprecation_deadline"] == "2026-09-13T12:00:00Z"
    assert response["update_location"] == "https://keepling.example/downloads"

    serialized = Jason.encode!(response)

    for private_term <- ~w(account operator credential grant cursor session token subject) do
      refute serialized =~ private_term
    end
  end

  test "closed query rejects missing malformed inverted and extra claims" do
    invalid_queries = [
      %{},
      %{"minimum_protocol_train" => "1"},
      %{"minimum_protocol_train" => "x", "maximum_protocol_train" => "2"},
      %{"minimum_protocol_train" => "2", "maximum_protocol_train" => "1"},
      %{
        "minimum_protocol_train" => "1",
        "maximum_protocol_train" => "2",
        "account" => "client-asserted"
      }
    ]

    for query <- invalid_queries do
      response = build_conn() |> get("/compatibility", query)

      assert %{
               "code" => "invalid_compatibility_claims",
               "recovery_action" => "correct_protocol_range",
               "retryable" => false
             } = json_response(response, 400)
    end
  end

  test "older and newer non-overlap return stable non-retrying upgrade direction", %{conn: conn} do
    older =
      conn
      |> get("/compatibility", %{
        "minimum_protocol_train" => "0",
        "maximum_protocol_train" => "0"
      })
      |> json_response(200)

    assert %{
             "compatibility_state" => "unsupported",
             "selected_protocol_train" => nil,
             "recovery_code" => "client_upgrade_required",
             "retryable" => false,
             "pending_intent" => "preserved_locally"
           } = older

    newer =
      build_conn()
      |> get("/compatibility", %{
        "minimum_protocol_train" => "3",
        "maximum_protocol_train" => "4"
      })
      |> json_response(200)

    assert %{
             "compatibility_state" => "unsupported",
             "selected_protocol_train" => nil,
             "recovery_code" => "server_upgrade_required",
             "retryable" => false,
             "pending_intent" => "preserved_locally"
           } = newer
  end

  test "startup validation rejects absent tested digest and malformed support ranges" do
    assert :ok = Compatibility.validate_config!(policy())

    assert_raise ArgumentError, ~r/tested OCI digest/, fn ->
      policy() |> Map.put("tested_oci_digest", nil) |> Compatibility.validate_config!()
    end

    assert_raise ArgumentError, ~r/supported read protocol range/, fn ->
      policy()
      |> put_in(["supported_protocols", "read"], %{"minimum" => 3, "maximum" => 2})
      |> Compatibility.validate_config!()
    end

    assert_raise ArgumentError, ~r/at least 90 days/, fn ->
      policy()
      |> Map.put("deprecation_deadline", "2026-08-01T12:00:00Z")
      |> Compatibility.validate_config!()
    end
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
