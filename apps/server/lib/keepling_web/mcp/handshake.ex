defmodule KeeplingWeb.MCP.Handshake do
  @moduledoc """
  `initialize` and `ping` for the pinned MCP protocol revision (D-04/D-30).

  `@protocol_revision` is declared exactly once here and returned verbatim --
  this module never negotiates down to whatever revision the client offers.
  """

  @protocol_revision "2025-06-18"

  @spec protocol_revision() :: String.t()
  def protocol_revision, do: @protocol_revision

  @spec initialize(map(), map()) :: {:ok, map()}
  def initialize(_params, _context) do
    {:ok,
     %{
       protocolVersion: @protocol_revision,
       capabilities: %{
         tools: %{},
         resources: %{subscribe: false, listChanged: false}
       },
       serverInfo: %{
         name: "keepling",
         version: "1"
       }
     }}
  end

  @spec ping(map(), map()) :: {:ok, map()}
  def ping(_params, _context), do: {:ok, %{}}
end
