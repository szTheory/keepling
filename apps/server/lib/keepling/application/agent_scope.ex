defmodule Keepling.Application.AgentScope do
  @moduledoc """
  D-06: the closed agent scope vocabulary and the authoritative,
  application-boundary scope gate.

  `KeeplingWeb.MCP.Scope` performs the same check as an adapter-layer
  fast-fail; this module is the check that actually decides authority. Both
  layers run for every MCP write so a bug in the adapter alone cannot widen
  what an agent grant may do (T-05-02).

  Permanently outside this vocabulary, by design, never by omission: account
  credentials, session and device-grant administration, recovery, export,
  and permanent deletion.
  """

  @agent_scopes ~w(tasks.read tasks.write tasks.bulk)

  @doc "The closed agent scope vocabulary, in the exact spelling grants persist."
  @spec scopes() :: [String.t()]
  def scopes, do: @agent_scopes

  @doc """
  Requires `scope` to be both a member of the closed vocabulary and present
  on `context.scope` -- the scope list the MCP pipeline assigned from the
  loaded device grant, never from the JSON-RPC request body (D-24).
  """
  @spec require(map(), String.t()) :: :ok | {:error, :insufficient_scope}
  def require(%{scope: granted}, scope)
      when is_list(granted) and scope in @agent_scopes do
    if scope in granted, do: :ok, else: {:error, :insufficient_scope}
  end

  def require(_context, _scope), do: {:error, :insufficient_scope}
end
