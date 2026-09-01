defmodule Keepling.Application.Compatibility do
  @moduledoc """
  Pure, server-authoritative protocol-train compatibility policy.

  Protocol trains describe only representation compatibility. Authorization,
  business invariants, conflict meaning, and feature flags are deliberately not
  inputs to negotiation.
  """

  @protocol_kinds ~w(read write sync)
  @recovery_codes ~w(continue client_update_available client_upgrade_required server_upgrade_required)

  @spec negotiate(map(), map()) :: map()
  def negotiate(
        %{
          "minimum_protocol_train" => client_minimum,
          "maximum_protocol_train" => client_maximum
        },
        policy
      )
      when is_integer(client_minimum) and is_integer(client_maximum) and
             client_minimum >= 0 and client_minimum <= client_maximum do
    metadata = metadata(policy)
    ranges = Map.fetch!(metadata, "supported_protocols")

    server_minimum =
      ranges
      |> Map.values()
      |> Enum.map(&Map.fetch!(&1, "minimum"))
      |> Enum.max()

    server_maximum =
      ranges
      |> Map.values()
      |> Enum.map(&Map.fetch!(&1, "maximum"))
      |> Enum.min()

    intersection_minimum = max(client_minimum, server_minimum)
    intersection_maximum = min(client_maximum, server_maximum)

    if intersection_minimum <= intersection_maximum do
      supported_result(intersection_maximum, Map.fetch!(policy, "current_protocol_train"))
    else
      unsupported_result(client_maximum, server_minimum)
    end
  end

  @spec metadata(map()) :: map()
  def metadata(policy) do
    support_floor = support_floor(policy)

    supported_protocols =
      Map.new(@protocol_kinds, fn kind ->
        range = get_in(policy, ["supported_protocols", kind])

        {kind,
         %{
           "minimum" => max(Map.fetch!(range, "minimum"), support_floor),
           "maximum" => Map.fetch!(range, "maximum")
         }}
      end)

    %{
      "server_release" => Map.fetch!(policy, "server_release"),
      "tested_oci_digest" => Map.fetch!(policy, "tested_oci_digest"),
      "supported_protocols" => supported_protocols,
      "schema_range" => Map.fetch!(policy, "schema_range"),
      "platform_minimum_builds" => Map.fetch!(policy, "platform_minimum_builds"),
      "deprecation_deadline" => Map.get(policy, "deprecation_deadline"),
      "update_location" => Map.fetch!(policy, "update_location"),
      "protocol_policy" => protocol_policy(policy),
      "recovery_codes" => @recovery_codes
    }
  end

  defp supported_result(selected, current) when selected == current do
    result("supported", selected, "continue")
  end

  defp supported_result(selected, _current) do
    result("deprecated_but_safe", selected, "client_update_available")
  end

  defp unsupported_result(client_maximum, server_minimum)
       when client_maximum < server_minimum do
    result("unsupported", nil, "client_upgrade_required")
  end

  defp unsupported_result(_client_maximum, _server_minimum) do
    result("unsupported", nil, "server_upgrade_required")
  end

  defp result(state, selected, recovery_code) do
    %{
      "compatibility_state" => state,
      "selected_protocol_train" => selected,
      "recovery_code" => recovery_code,
      "retryable" => false,
      "pending_intent" => "preserved_locally"
    }
  end

  defp support_floor(%{"distribution" => "dogfood", "current_protocol_train" => current}),
    do: current

  defp support_floor(policy) do
    current = Map.fetch!(policy, "current_protocol_train")
    previous = Map.get(policy, "previous_protocol_train")

    cond do
      is_nil(previous) -> current
      emergency_active?(policy) -> current
      previous_supported?(policy) -> previous
      true -> current
    end
  end

  defp previous_supported?(policy) do
    case Map.get(policy, "deprecation_deadline") do
      deadline when is_binary(deadline) ->
        DateTime.compare(datetime!(Map.fetch!(policy, "now")), datetime!(deadline)) in [:lt, :eq]

      _ ->
        false
    end
  end

  defp emergency_active?(policy) do
    case Map.get(policy, "emergency_override") do
      %{
        "effective_at" => effective_at,
        "evidence" => evidence,
        "notice_location" => notice_location,
        "preserve_local_intent" => true
      }
      when is_binary(effective_at) and is_binary(evidence) and evidence != "" and
             is_binary(notice_location) and notice_location != "" ->
        DateTime.compare(datetime!(Map.fetch!(policy, "now")), datetime!(effective_at)) in [
          :gt,
          :eq
        ]

      _ ->
        false
    end
  end

  defp protocol_policy(%{"distribution" => "dogfood"}), do: "unstable_current_dogfood"
  defp protocol_policy(_policy), do: "current_and_previous_90_days"

  defp datetime!(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _ -> raise ArgumentError, "invalid compatibility policy instant"
    end
  end
end
