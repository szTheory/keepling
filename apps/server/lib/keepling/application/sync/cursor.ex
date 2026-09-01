defmodule Keepling.Application.Sync.Cursor do
  @moduledoc """
  Authenticated opaque cursor codec for synchronization feed positions.

  The signed payload binds one position to the complete server-derived native
  namespace, restore epoch, and protocol train. Callers receive closed recovery
  results rather than treating invalid state as an empty feed page.
  """

  @codec_version 1
  @mac_bytes 32
  @maximum_cursor_bytes 4096
  @ttl_seconds 90 * 24 * 60 * 60

  @namespace_fields [
    :issuer,
    :origin,
    :server_instance,
    :subject,
    :generation,
    :sync_epoch,
    :protocol_train
  ]

  @spec defaults() :: map()
  def defaults do
    %{
      pull_page_limit: 200,
      offline_grace_days: 30,
      pruning_batch_size: 1_000,
      destructive_pruning: false
    }
  end

  @spec encode(map(), map(), map(), DateTime.t(), keyword()) :: String.t()
  def encode(position, namespace, keyring, now, options \\ []) do
    %{sequence: sequence, ordinal: ordinal} = validate_position!(position)
    namespace = validate_namespace!(namespace)
    %{active: key_id, keys: keys} = validate_keyring!(keyring)
    secret = Map.fetch!(keys, key_id)
    codec_version = Keyword.get(options, :codec_version, @codec_version)
    issued_at = DateTime.to_unix(now, :second)
    expires_at = issued_at + Keyword.get(options, :ttl_seconds, @ttl_seconds)

    payload =
      :erlang.term_to_binary(
        {codec_version, key_id, namespace, sequence, ordinal, issued_at, expires_at},
        [:deterministic]
      )

    mac = :crypto.mac(:hmac, :sha256, secret, payload)
    Base.url_encode64(payload <> mac, padding: false)
  end

  @spec decode(String.t(), map(), map(), DateTime.t(), keyword()) ::
          {:ok, map()} | {:reset_required, map()}
  def decode(cursor, expected_namespace, keyring, now, options \\ [])

  def decode(cursor, expected_namespace, keyring, now, options)
      when is_binary(cursor) and byte_size(cursor) <= @maximum_cursor_bytes do
    with {:ok, signed} <- Base.url_decode64(cursor, padding: false),
         true <- byte_size(signed) > @mac_bytes,
         payload_size = byte_size(signed) - @mac_bytes,
         <<payload::binary-size(^payload_size), supplied_mac::binary-size(@mac_bytes)>> <- signed,
         {:ok, decoded} <- safe_payload(payload),
         {codec_version, key_id, namespace, sequence, ordinal, _issued_at, expires_at} <- decoded,
         {:ok, secret} <- key_for(keyring, key_id),
         expected_mac = :crypto.mac(:hmac, :sha256, secret, payload),
         true <- :crypto.hash_equals(supplied_mac, expected_mac) do
      validate_decoded(
        codec_version,
        namespace,
        %{sequence: sequence, ordinal: ordinal},
        expires_at,
        expected_namespace,
        now,
        options
      )
    else
      _ -> reset("tampered_cursor", "bootstrap")
    end
  rescue
    _error -> reset("tampered_cursor", "bootstrap")
  end

  def decode(_cursor, _expected_namespace, _keyring, _now, _options),
    do: reset("tampered_cursor", "bootstrap")

  defp validate_decoded(
         codec_version,
         namespace,
         position,
         expires_at,
         expected_namespace,
         now,
         options
       ) do
    supported_codecs = Keyword.get(options, :supported_codecs, [@codec_version])

    supported_protocols =
      Keyword.get(options, :supported_protocols, [expected_namespace.protocol_train])

    cond do
      codec_version not in supported_codecs ->
        reset("unsupported_codec", "upgrade")

      not valid_position?(position) or not valid_namespace?(namespace) ->
        reset("tampered_cursor", "bootstrap")

      namespace.protocol_train not in supported_protocols or
          namespace.protocol_train != expected_namespace.protocol_train ->
        reset("unsupported_protocol", "upgrade")

      namespace.sync_epoch != expected_namespace.sync_epoch ->
        reset("restore_epoch_changed", "bootstrap")

      namespace_identity(namespace) != namespace_identity(expected_namespace) ->
        reset("namespace_mismatch", "quarantine")

      not is_integer(expires_at) or DateTime.to_unix(now, :second) > expires_at ->
        reset("cursor_expired", "bootstrap")

      below_low_water?(position, Keyword.get(options, :low_water)) ->
        reset("below_low_water", "bootstrap")

      true ->
        {:ok, position}
    end
  end

  defp safe_payload(payload) do
    {:ok, :erlang.binary_to_term(payload, [:safe])}
  rescue
    _error -> {:error, :invalid_payload}
  end

  defp key_for(%{keys: keys}, key_id) when is_map(keys) and is_binary(key_id) do
    case Map.fetch(keys, key_id) do
      {:ok, secret} when is_binary(secret) and byte_size(secret) >= 32 -> {:ok, secret}
      _ -> {:error, :unknown_key}
    end
  end

  defp key_for(_keyring, _key_id), do: {:error, :invalid_keyring}

  defp validate_keyring!(%{active: active, keys: keys} = keyring)
       when is_binary(active) and is_map(keys) do
    case Map.fetch(keys, active) do
      {:ok, secret} when is_binary(secret) and byte_size(secret) >= 32 -> keyring
      _ -> raise ArgumentError, "active cursor key is missing or too short"
    end
  end

  defp validate_keyring!(_keyring), do: raise(ArgumentError, "invalid cursor keyring")

  defp validate_namespace!(namespace) do
    if valid_namespace?(namespace),
      do: Map.take(namespace, @namespace_fields),
      else: raise(ArgumentError)
  end

  defp valid_namespace?(namespace) when is_map(namespace) do
    Enum.all?([:issuer, :origin, :server_instance, :subject, :sync_epoch], fn field ->
      value = Map.get(namespace, field)
      is_binary(value) and byte_size(value) > 0
    end) and is_integer(namespace[:generation]) and namespace.generation >= 1 and
      is_integer(namespace[:protocol_train]) and namespace.protocol_train >= 1
  end

  defp valid_namespace?(_namespace), do: false

  defp namespace_identity(namespace) do
    Map.take(namespace, [:issuer, :origin, :server_instance, :subject, :generation])
  end

  defp validate_position!(position) do
    if valid_position?(position),
      do: position,
      else: raise(ArgumentError, "invalid feed position")
  end

  defp valid_position?(%{sequence: sequence, ordinal: ordinal}) do
    is_integer(sequence) and sequence >= 0 and is_integer(ordinal) and ordinal >= -1
  end

  defp valid_position?(_position), do: false

  defp below_low_water?(_position, nil), do: false

  defp below_low_water?(position, low_water) do
    valid_position?(low_water) and
      {position.sequence, position.ordinal} < {low_water.sequence, low_water.ordinal}
  end

  defp reset(reason, recovery),
    do: {:reset_required, %{reason: reason, recovery: recovery}}
end
