defmodule Keepling.Application.Compatibility do
  @moduledoc """
  Pure, server-authoritative protocol-train compatibility policy.

  Protocol trains describe only representation compatibility. Authorization,
  business invariants, conflict meaning, and feature flags are deliberately not
  inputs to negotiation.
  """

  @protocol_kinds ~w(read write sync)
  @recovery_codes ~w(continue client_update_available client_upgrade_required server_upgrade_required)
  @required_policy_keys ~w(current_protocol_train deprecation_deadline distribution emergency_override platform_minimum_builds previous_protocol_train previous_superseded_at schema_range server_release supported_protocols tested_oci_digest update_location)

  @spec validate_config!(map()) :: :ok
  def validate_config!(policy) when is_map(policy) do
    keys = Map.keys(policy) -- ["now"]

    unless Enum.sort(keys) == Enum.sort(@required_policy_keys) do
      raise ArgumentError, "compatibility policy must use the closed configuration shape"
    end

    non_empty_string!(policy["server_release"], "server release")

    unless is_binary(policy["tested_oci_digest"]) and
             Regex.match?(~r/^sha256:[0-9a-f]{64}$/, policy["tested_oci_digest"]) do
      raise ArgumentError, "compatibility policy requires an exact tested OCI digest"
    end

    distribution = policy["distribution"]

    unless distribution in ["dogfood", "distributed"] do
      raise ArgumentError, "compatibility distribution must be dogfood or distributed"
    end

    current = positive_integer!(policy["current_protocol_train"], "current protocol train")
    previous = policy["previous_protocol_train"]

    if not is_nil(previous) and previous != current - 1 do
      raise ArgumentError, "previous protocol train must be immediately before current"
    end

    for kind <- @protocol_kinds do
      range!(get_in(policy, ["supported_protocols", kind]), "supported #{kind} protocol range",
        must_include: current
      )
    end

    range!(policy["schema_range"], "schema range")
    platform_builds!(policy["platform_minimum_builds"])
    update_location!(policy["update_location"])

    case distribution do
      "dogfood" -> validate_dogfood!(policy)
      "distributed" -> validate_distributed!(policy, previous)
    end

    :ok
  end

  def validate_config!(_policy) do
    raise ArgumentError, "compatibility policy must be a map"
  end

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

  defp validate_dogfood!(policy) do
    if not is_nil(policy["deprecation_deadline"]) or
         not is_nil(policy["previous_superseded_at"]) or
         not is_nil(policy["emergency_override"]) do
      raise ArgumentError, "dogfood compatibility cannot advertise a distributed support window"
    end
  end

  defp validate_distributed!(policy, previous) do
    unless is_integer(previous) and previous >= 1 do
      raise ArgumentError, "distributed compatibility requires the immediately previous train"
    end

    superseded_at = datetime!(policy["previous_superseded_at"])
    deadline = datetime!(policy["deprecation_deadline"])
    minimum_deadline = DateTime.add(superseded_at, 90, :day)

    if DateTime.compare(deadline, minimum_deadline) == :lt and
         not valid_emergency_override?(policy["emergency_override"]) do
      raise ArgumentError,
            "distributed compatibility must retain the previous train for at least 90 days"
    end

    if not is_nil(policy["emergency_override"]) and
         not valid_emergency_override?(policy["emergency_override"]) do
      raise ArgumentError,
            "compatibility emergency override requires evidence and preserved local intent"
    end
  end

  defp valid_emergency_override?(%{
         "effective_at" => effective_at,
         "evidence" => evidence,
         "notice_location" => notice_location,
         "preserve_local_intent" => true
       }) do
    valid_datetime?(effective_at) and non_empty_string?(evidence) and valid_uri?(notice_location)
  end

  defp valid_emergency_override?(_override), do: false

  defp range!(range, label, options \\ [])

  defp range!(%{"minimum" => minimum, "maximum" => maximum}, label, options)
       when is_integer(minimum) and is_integer(maximum) and minimum >= 1 and minimum <= maximum do
    case Keyword.get(options, :must_include) do
      nil -> :ok
      value when value >= minimum and value <= maximum -> :ok
      _ -> raise ArgumentError, "#{label} must include the current protocol train"
    end
  end

  defp range!(_range, label, _options) do
    raise ArgumentError, "#{label} must be a closed increasing integer range"
  end

  defp platform_builds!(%{"electron" => electron, "iphone" => iphone})
       when is_integer(electron) and electron >= 0 and is_integer(iphone) and iphone >= 0,
       do: :ok

  defp platform_builds!(_builds) do
    raise ArgumentError, "platform minimum builds must contain only electron and iphone integers"
  end

  defp update_location!(location) do
    unless valid_uri?(location) do
      raise ArgumentError, "compatibility update location must be an absolute HTTPS URI"
    end
  end

  defp valid_uri?(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{scheme: "https", host: host} when is_binary(host) and host != "" -> true
      _ -> false
    end
  end

  defp valid_uri?(_value), do: false

  defp positive_integer!(value, _label) when is_integer(value) and value >= 1, do: value

  defp positive_integer!(_value, label) do
    raise ArgumentError, "#{label} must be a positive integer"
  end

  defp non_empty_string!(value, _label) when is_binary(value) and value != "", do: :ok

  defp non_empty_string!(_value, label) do
    raise ArgumentError, "#{label} must be a non-empty string"
  end

  defp non_empty_string?(value), do: is_binary(value) and value != ""

  defp valid_datetime?(value) do
    try do
      _datetime = datetime!(value)
      true
    rescue
      ArgumentError -> false
    end
  end

  defp datetime!(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _ -> raise ArgumentError, "invalid compatibility policy instant"
    end
  end

  defp datetime!(_value), do: raise(ArgumentError, "invalid compatibility policy instant")
end
