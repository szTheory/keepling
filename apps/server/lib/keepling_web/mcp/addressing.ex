defmodule KeeplingWeb.MCP.Addressing do
  @moduledoc """
  The adapter-side disambiguation response builder (D-16). Wraps the
  closed `ambiguous_match` error member from `KeeplingWeb.MCP.Errors` with
  the bounded candidate set, each candidate projected through
  `KeeplingWeb.MCP.Redaction` exactly as every other resource payload is
  (D-10) -- the candidate list travels in a structured `data` field, never
  interpolated into the fixed human string.
  """

  alias KeeplingWeb.MCP.{Errors, Redaction}

  @doc "Builds the `ambiguous_match` JSON-RPC error, redacting every candidate row first."
  @spec ambiguous_match_response([map()]) :: map()
  def ambiguous_match_response(candidates) when is_list(candidates) do
    Errors.ambiguous_match(Enum.map(candidates, &Redaction.task/1))
  end
end
