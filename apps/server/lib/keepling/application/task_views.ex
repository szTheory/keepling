defmodule Keepling.Application.TaskViews do
  @moduledoc """
  Account-scoped application contract for deterministic task-list projections.

  Cursors are authenticated, bind the account and complete keyset to a named
  view, and carry the projection revisions that made the page authoritative.
  """

  @cursor_version 1
  @cursor_mac_bytes 32
  @default_limit 20
  @maximum_limit 50
  @views ~w(inbox today upcoming completed)a

  defmodule Port do
    @moduledoc "Persistence port for task-list reads and scoped Today moves."

    @callback list_tasks(map(), atom(), map()) :: {:ok, map()} | {:error, atom()}
    @callback move_today(map(), map()) :: {:ok, map()} | {:error, atom()}
  end

  @spec list(atom(), map(), map(), module()) :: tuple()
  def list(view, context, options, port) when view in @views do
    with {:ok, limit} <- limit(options),
         {:ok, cursor} <- cursor(options, context, view),
         {:ok, page} <- port.list_tasks(context, view, %{cursor: cursor, limit: limit}) do
      {:ok, present_page(page, context, view)}
    end
  end

  def list(_view, _context, _options, _port), do: {:error, :invalid_view}

  @spec move_today(map(), map(), module()) :: tuple()
  def move_today(
        %{task_id: task_id, direction: direction, expected_order_revision: revision} = command,
        context,
        port
      )
      when direction in [:earlier, :later] and is_integer(revision) and revision > 0 and
             is_binary(task_id) do
    port.move_today(context, command)
  end

  def move_today(_command, _context, _port), do: {:error, :invalid_move}

  @spec encode_cursor(map(), map(), atom()) :: String.t()
  def encode_cursor(keyset, context, view) when view in @views do
    payload =
      :erlang.term_to_binary(
        {@cursor_version, context.account_id, view, keyset},
        [:deterministic]
      )

    mac = :crypto.mac(:hmac, :sha256, context.cursor_secret, payload)
    Base.url_encode64(payload <> mac, padding: false)
  end

  @spec decode_cursor(String.t(), map(), atom()) :: {:ok, map()} | {:error, :invalid_cursor}
  def decode_cursor(cursor, context, view)
      when is_binary(cursor) and byte_size(cursor) <= 2048 and view in @views do
    with {:ok, signed} <- Base.url_decode64(cursor, padding: false),
         true <- byte_size(signed) > @cursor_mac_bytes,
         payload_size = byte_size(signed) - @cursor_mac_bytes,
         <<payload::binary-size(^payload_size), supplied_mac::binary-size(@cursor_mac_bytes)>> <-
           signed,
         expected_mac = :crypto.mac(:hmac, :sha256, context.cursor_secret, payload),
         true <- :crypto.hash_equals(supplied_mac, expected_mac),
         {@cursor_version, account_id, ^view, keyset} <-
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

  def decode_cursor(_cursor, _context, _view), do: {:error, :invalid_cursor}

  defp limit(options) do
    case Map.get(options, :limit, @default_limit) do
      limit when is_integer(limit) and limit >= 1 and limit <= @maximum_limit -> {:ok, limit}
      _invalid -> {:error, :invalid_limit}
    end
  end

  defp cursor(options, context, view) do
    case Map.get(options, :cursor) do
      nil -> {:ok, nil}
      encoded -> decode_cursor(encoded, context, view)
    end
  end

  defp present_page(page, context, view) do
    next_cursor =
      case page.next_keyset do
        nil -> nil
        keyset -> encode_cursor(keyset, context, view)
      end

    page
    |> Map.drop([:next_keyset])
    |> Map.merge(%{next_cursor: next_cursor, view: Atom.to_string(view)})
  end
end
