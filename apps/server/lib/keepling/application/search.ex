defmodule Keepling.Application.Search do
  @moduledoc """
  Account-scoped, query-bound bounded full-text search over task title and notes.

  A sibling of `Keepling.Application.TaskViews`, not an extension of it (D-35):
  `TaskViews.@views` is closed to four named unfiltered views and its cursor
  shape assumes one. Search cursors bind the account AND a digest of the
  normalized query term, so a cursor issued for one search cannot be replayed
  against a different query or a foreign account.
  """

  @cursor_version 1
  @cursor_mac_bytes 32
  @default_limit 20
  @maximum_limit 50

  defmodule Port do
    @moduledoc "Persistence port for full-text task search."

    @callback search_tasks(map(), String.t(), map()) :: {:ok, map()} | {:error, atom()}
  end

  @spec query(map(), String.t(), map(), module()) :: tuple()
  def query(context, term, options, port) do
    normalized = normalize_term(term)

    with {:ok, limit} <- limit(options) do
      if normalized == "" do
        {:ok, present_page(%{items: [], next_keyset: nil}, context, normalized)}
      else
        with {:ok, cursor} <- cursor(options, context, normalized),
             {:ok, page} <-
               port.search_tasks(context, normalized, %{cursor: cursor, limit: limit}) do
          {:ok, present_page(page, context, normalized)}
        end
      end
    end
  end

  @spec encode_cursor(map(), map(), String.t()) :: String.t()
  def encode_cursor(keyset, context, normalized_term) do
    digest = query_digest(normalized_term)

    payload =
      :erlang.term_to_binary(
        {@cursor_version, context.account_id, digest, keyset},
        [:deterministic]
      )

    mac = :crypto.mac(:hmac, :sha256, context.cursor_secret, payload)
    Base.url_encode64(payload <> mac, padding: false)
  end

  @spec decode_cursor(String.t(), map(), String.t()) :: {:ok, map()} | {:error, :invalid_cursor}
  def decode_cursor(cursor, context, normalized_term)
      when is_binary(cursor) and byte_size(cursor) <= 2048 do
    digest = query_digest(normalized_term)

    with {:ok, signed} <- Base.url_decode64(cursor, padding: false),
         true <- byte_size(signed) > @cursor_mac_bytes,
         payload_size = byte_size(signed) - @cursor_mac_bytes,
         <<payload::binary-size(^payload_size), supplied_mac::binary-size(@cursor_mac_bytes)>> <-
           signed,
         expected_mac = :crypto.mac(:hmac, :sha256, context.cursor_secret, payload),
         true <- :crypto.hash_equals(supplied_mac, expected_mac),
         {@cursor_version, account_id, ^digest, keyset} <-
           :erlang.binary_to_term(payload, [:safe]),
         true <- account_id == context.account_id,
         true <- is_map(keyset) do
      {:ok, keyset}
    else
      _ -> {:error, :invalid_cursor}
    end
  rescue
    _error -> {:error, :invalid_cursor}
  end

  def decode_cursor(_cursor, _context, _normalized_term), do: {:error, :invalid_cursor}

  defp query_digest(normalized_term), do: :crypto.hash(:sha256, normalized_term)

  defp normalize_term(term) when is_binary(term), do: String.trim(term)
  defp normalize_term(_term), do: ""

  defp limit(options) do
    case Map.get(options, :limit, @default_limit) do
      limit when is_integer(limit) and limit >= 1 and limit <= @maximum_limit -> {:ok, limit}
      limit when is_integer(limit) and limit > @maximum_limit -> {:ok, @maximum_limit}
      _invalid -> {:error, :invalid_limit}
    end
  end

  defp cursor(options, context, normalized_term) do
    case Map.get(options, :cursor) do
      nil -> {:ok, nil}
      encoded -> decode_cursor(encoded, context, normalized_term)
    end
  end

  defp present_page(page, context, normalized_term) do
    next_cursor =
      case page.next_keyset do
        nil -> nil
        keyset -> encode_cursor(keyset, context, normalized_term)
      end

    page
    |> Map.drop([:next_keyset])
    |> Map.put(:next_cursor, next_cursor)
  end
end
