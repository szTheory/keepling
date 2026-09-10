defmodule KeeplingWeb.MCP.Scope do
  @moduledoc """
  Adapter-layer scope fast-fail (D-06). Delegates its vocabulary to
  `Keepling.Application.AgentScope` so the closed scope list is defined
  once; this module exists as its own call site so the authorization check
  runs twice on two independent paths (T-05-02) -- `KeeplingWeb.MCP.Tools`
  calls this BEFORE calling `AgentScope.require/2` again at the application
  boundary. Neither call is skipped when the other passes.
  """

  alias Keepling.Application.AgentScope

  @spec require(map(), String.t()) :: :ok | {:error, :insufficient_scope}
  def require(context, scope), do: AgentScope.require(context, scope)
end
