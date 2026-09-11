defmodule KeeplingWeb.MCP.Dispatch do
  @moduledoc """
  JSON-RPC 2.0 envelope parse/dispatch/render for the pinned MCP protocol
  revision (D-01, D-02). This module owns framing and nothing else: no
  authorization, no schema validation, no command dispatch, no error
  semantics -- those stay in `KeeplingWeb.MCP.{Handshake, Tools, Errors}` and
  `Keepling.Application.*`.
  """

  use KeeplingWeb, :controller

  alias KeeplingWeb.MCP.{Errors, Handshake, Resources, Tools}

  @methods %{
    "initialize" => &Handshake.initialize/2,
    "ping" => &Handshake.ping/2,
    "tools/list" => &Tools.list/2,
    "tools/call" => &Tools.call/2,
    "resources/list" => &Resources.list/2,
    "resources/read" => &Resources.read/2
  }

  @doc "The closed set of dispatchable JSON-RPC method names (05-04-PLAN.md Task 3: bound to docs/architecture/MCP-SURFACE.md by surface_test.exs)."
  @spec implemented_methods() :: [String.t()]
  def implemented_methods, do: Map.keys(@methods)

  def handle(conn, %{"jsonrpc" => "2.0", "method" => method} = params) when is_binary(method) do
    id = Map.get(params, "id")
    request_params = normalize_params(Map.get(params, "params", %{}))

    case Map.fetch(@methods, method) do
      {:ok, handler} ->
        case handler.(request_params, context(conn)) do
          {:ok, result} -> render_result(conn, id, result)
          {:error, error} -> render_error(conn, id, error)
        end

      :error ->
        render_error(conn, id, Errors.method_not_found())
    end
  end

  def handle(conn, params) do
    conn
    |> put_status(400)
    |> render_error(Map.get(params, "id"), Errors.invalid_request())
  end

  defp normalize_params(params) when is_map(params), do: params
  defp normalize_params(_params), do: %{}

  defp render_result(conn, id, result) do
    conn |> put_status(200) |> json(%{jsonrpc: "2.0", id: id, result: result})
  end

  defp render_error(conn, id, error) do
    conn |> json(%{jsonrpc: "2.0", id: id, error: error})
  end

  defp context(conn) do
    %{
      account_id: conn.assigns.current_account_id,
      accepted_at: DateTime.utc_now() |> DateTime.truncate(:microsecond),
      actor_label: conn.assigns.current_grant_label,
      actor_principal: "authorized_grant",
      actor_type: "agent",
      client_kind: conn.assigns.current_client_kind,
      # T-06-07-01/D-38: this grant's own identity, carried through to
      # Commands.lookup_result/3 (mutation-receipt read binding) and to the
      # command store's write path (device_grants.last_used_at advance).
      device_grant_id: conn.assigns.current_device_grant_id,
      scope: conn.assigns.current_scope
    }
  end
end
