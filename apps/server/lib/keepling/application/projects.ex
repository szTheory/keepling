defmodule Keepling.Application.Projects do
  @moduledoc """
  Account-scoped bounded reads over projects and their tasks.

  Mirrors `Keepling.Application.Search`'s Port/cursor construction: the same
  `@default_limit`/`@maximum_limit` pair and the same signed-cursor shape,
  pinning either the fixed `"projects"` discriminator (the project list) or
  the project's own identity (a project's task page) so a cursor cannot be
  replayed against a different project.
  """

  @cursor_version 1
  @cursor_mac_bytes 32
  @default_limit 20
  @maximum_limit 50

  defmodule Port do
    @moduledoc "Persistence port for project and project-task reads."

    @callback list_projects(map(), map()) :: {:ok, map()} | {:error, atom()}
    @callback list_project_tasks(map(), String.t(), map()) :: {:ok, map()} | {:error, atom()}
  end

  @spec list(map(), map(), module()) :: tuple()
  def list(context, options, port) do
    with {:ok, limit} <- limit(options),
         {:ok, cursor} <- cursor(options, context, "projects"),
         {:ok, page} <- port.list_projects(context, %{cursor: cursor, limit: limit}) do
      {:ok, present_page(page, context, "projects")}
    end
  end

  @spec tasks(map(), String.t(), map(), module()) :: tuple()
  def tasks(context, project_id, options, port) do
    with {:ok, limit} <- limit(options),
         {:ok, cursor} <- cursor(options, context, project_id),
         {:ok, page} <-
           port.list_project_tasks(context, project_id, %{cursor: cursor, limit: limit}) do
      {:ok, present_page(page, context, project_id)}
    end
  end

  @spec encode_cursor(map(), map(), String.t()) :: String.t()
  def encode_cursor(keyset, context, discriminator) do
    payload =
      :erlang.term_to_binary(
        {@cursor_version, context.account_id, discriminator, keyset},
        [:deterministic]
      )

    mac = :crypto.mac(:hmac, :sha256, context.cursor_secret, payload)
    Base.url_encode64(payload <> mac, padding: false)
  end

  @spec decode_cursor(String.t(), map(), String.t()) :: {:ok, map()} | {:error, :invalid_cursor}
  def decode_cursor(cursor, context, discriminator)
      when is_binary(cursor) and byte_size(cursor) <= 2048 do
    with {:ok, signed} <- Base.url_decode64(cursor, padding: false),
         true <- byte_size(signed) > @cursor_mac_bytes,
         payload_size = byte_size(signed) - @cursor_mac_bytes,
         <<payload::binary-size(^payload_size), supplied_mac::binary-size(@cursor_mac_bytes)>> <-
           signed,
         expected_mac = :crypto.mac(:hmac, :sha256, context.cursor_secret, payload),
         true <- :crypto.hash_equals(supplied_mac, expected_mac),
         {@cursor_version, account_id, ^discriminator, keyset} <-
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

  def decode_cursor(_cursor, _context, _discriminator), do: {:error, :invalid_cursor}

  defp limit(options) do
    case Map.get(options, :limit, @default_limit) do
      limit when is_integer(limit) and limit >= 1 and limit <= @maximum_limit -> {:ok, limit}
      limit when is_integer(limit) and limit > @maximum_limit -> {:ok, @maximum_limit}
      _invalid -> {:error, :invalid_limit}
    end
  end

  defp cursor(options, context, discriminator) do
    case Map.get(options, :cursor) do
      nil -> {:ok, nil}
      encoded -> decode_cursor(encoded, context, discriminator)
    end
  end

  defp present_page(page, context, discriminator) do
    next_cursor =
      case page.next_keyset do
        nil -> nil
        keyset -> encode_cursor(keyset, context, discriminator)
      end

    page
    |> Map.drop([:next_keyset])
    |> Map.put(:next_cursor, next_cursor)
  end
end
