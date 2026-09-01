defmodule Keepling.Application.Sync do
  @moduledoc """
  Inward application contract for authorized, gap-free synchronization bootstrap.

  Bootstrap captures one feed high-water, keyset-enumerates canonical entities,
  and carries the immutable high-water through a distinct authenticated cursor.
  Feed catch-up begins strictly after that position.
  """

  @bootstrap_codec 1
  @mac_bytes 32
  @maximum_cursor_bytes 4096
  @default_limit 50
  @maximum_limit 100

  defmodule Port do
    @moduledoc "Persistence port for synchronization bootstrap reads."

    @callback authorize_bootstrap(map()) :: :ok | {:error, atom()}
    @callback capture_high_water(map()) :: {:ok, map()} | {:error, atom()}
    @callback bootstrap_page(map(), map(), nil | map(), pos_integer()) ::
                {:ok, map()} | {:error, atom()}
    @callback list_after(binary(), nil | map(), pos_integer()) ::
                {:ok, map()} | {:error, atom()}
  end

  alias Keepling.Application.Sync.Cursor

  @spec pull(map(), map(), module()) ::
          {:ok, map()} | {:quarantined, atom()} | {:reset_required, map()} | {:error, atom()}
  def pull(context, options, port) when is_map(context) and is_map(options) do
    with {:ok, limit} <- pull_limit(options),
         :ok <- authorize(port, context),
         {:ok, position} <- pull_position(context, options),
         {:ok, page} <- port.list_after(context.account_id, position, limit) do
      coverage_cursor =
        case page.high_water do
          nil ->
            Map.get(options, :cursor)

          high_water ->
            Cursor.encode(high_water, context.namespace, context.cursor_keyring, context.now)
        end

      {:ok,
       %{
         changes: page.changes,
         coverage_cursor: coverage_cursor,
         has_more: Map.get(page, :has_more, false)
       }}
    else
      {:error, :namespace_mismatch} -> {:quarantined, :namespace_mismatch}
      {:reset_required, reason} -> {:reset_required, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  def pull(_context, _options, _port), do: {:error, :invalid_pull}

  @spec bootstrap(map(), map(), module()) ::
          {:ok, map()} | {:quarantined, atom()} | {:reset_required, map()} | {:error, atom()}
  def bootstrap(context, options, port) when is_map(context) and is_map(options) do
    with {:ok, limit} <- limit(options),
         :ok <- authorize(port, context),
         {:ok, high_water, keyset} <- bootstrap_position(context, options, port),
         {:ok, page} <- port.bootstrap_page(context, high_water, keyset, limit) do
      {:ok,
       %{
         entities: page.entities,
         high_water: high_water,
         next_cursor: next_cursor(page.next_keyset, high_water, context)
       }}
    else
      {:error, :namespace_mismatch} -> {:quarantined, :namespace_mismatch}
      {:reset_required, reason} -> {:reset_required, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  def bootstrap(_context, _options, _port), do: {:error, :invalid_bootstrap}

  defp authorize(port, context) do
    port.authorize_bootstrap(context)
  end

  defp bootstrap_position(context, options, port) do
    case Map.get(options, :cursor) do
      nil ->
        with {:ok, high_water} <- port.capture_high_water(context) do
          {:ok, high_water, nil}
        end

      cursor ->
        decode_bootstrap_cursor(cursor, context)
    end
  end

  defp next_cursor(nil, _high_water, _context), do: nil

  defp next_cursor(keyset, high_water, context) do
    key_id = context.cursor_keyring.active
    secret = Map.fetch!(context.cursor_keyring.keys, key_id)
    namespace = cursor_namespace(context.namespace)

    payload =
      :erlang.term_to_binary(
        {:bootstrap, @bootstrap_codec, key_id, namespace, high_water, keyset},
        [:deterministic]
      )

    mac = :crypto.mac(:hmac, :sha256, secret, payload)
    Base.url_encode64(payload <> mac, padding: false)
  end

  defp decode_bootstrap_cursor(cursor, context)
       when is_binary(cursor) and byte_size(cursor) <= @maximum_cursor_bytes do
    with {:ok, signed} <- Base.url_decode64(cursor, padding: false),
         true <- byte_size(signed) > @mac_bytes,
         payload_size = byte_size(signed) - @mac_bytes,
         <<payload::binary-size(^payload_size), supplied_mac::binary-size(@mac_bytes)>> <- signed,
         {:ok, decoded} <- safe_payload(payload),
         {:bootstrap, @bootstrap_codec, key_id, namespace, high_water, keyset} <- decoded,
         {:ok, secret} <- Map.fetch(context.cursor_keyring.keys, key_id),
         expected_mac = :crypto.mac(:hmac, :sha256, secret, payload),
         true <- :crypto.hash_equals(supplied_mac, expected_mac) do
      validate_bootstrap_namespace(namespace, context.namespace, high_water, keyset)
    else
      _ -> {:reset_required, %{reason: "tampered_cursor", recovery: "bootstrap"}}
    end
  rescue
    _error -> {:reset_required, %{reason: "tampered_cursor", recovery: "bootstrap"}}
  end

  defp decode_bootstrap_cursor(_cursor, _context),
    do: {:reset_required, %{reason: "tampered_cursor", recovery: "bootstrap"}}

  defp validate_bootstrap_namespace(namespace, expected, high_water, keyset) do
    expected = cursor_namespace(expected)

    cond do
      namespace.protocol_train != expected.protocol_train ->
        {:reset_required, %{reason: "unsupported_protocol", recovery: "upgrade"}}

      namespace.sync_epoch != expected.sync_epoch ->
        {:reset_required, %{reason: "restore_epoch_changed", recovery: "bootstrap"}}

      namespace != expected ->
        {:reset_required, %{reason: "namespace_mismatch", recovery: "quarantine"}}

      not valid_position?(high_water) or not valid_keyset?(keyset) ->
        {:reset_required, %{reason: "tampered_cursor", recovery: "bootstrap"}}

      true ->
        {:ok, high_water, keyset}
    end
  end

  defp cursor_namespace(namespace) do
    Map.take(namespace, [
      :issuer,
      :origin,
      :server_instance,
      :subject,
      :generation,
      :sync_epoch,
      :protocol_train
    ])
  end

  defp safe_payload(payload) do
    {:ok, :erlang.binary_to_term(payload, [:safe])}
  rescue
    _error -> {:error, :invalid_payload}
  end

  defp valid_position?(%{sequence: sequence, ordinal: ordinal}),
    do: is_integer(sequence) and sequence >= 0 and is_integer(ordinal) and ordinal >= -1

  defp valid_position?(_position), do: false

  defp valid_keyset?(%{entity_type: entity_type, entity_id: entity_id}),
    do: entity_type in ["organization", "task"] and is_binary(entity_id)

  defp valid_keyset?(_keyset), do: false

  defp limit(options) do
    case Map.get(options, :limit, @default_limit) do
      limit when is_integer(limit) and limit >= 1 and limit <= @maximum_limit -> {:ok, limit}
      _invalid -> {:error, :invalid_limit}
    end
  end

  defp pull_limit(options) do
    case Map.get(options, :limit, 200) do
      limit when is_integer(limit) and limit >= 1 and limit <= 200 -> {:ok, limit}
      _invalid -> {:error, :invalid_limit}
    end
  end

  defp pull_position(_context, %{cursor: nil}), do: {:ok, nil}
  defp pull_position(_context, options) when not is_map_key(options, :cursor), do: {:ok, nil}

  defp pull_position(context, %{cursor: cursor}) do
    Cursor.decode(cursor, context.namespace, context.cursor_keyring, context.now,
      low_water: Map.get(context, :low_water)
    )
  end
end
