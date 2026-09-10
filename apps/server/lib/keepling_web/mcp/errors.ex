defmodule KeeplingWeb.MCP.Errors do
  @moduledoc """
  Closed JSON-RPC error mapping (D-14). The top-level `code`/`message` stay
  inside the standard JSON-RPC range; Keepling's own closed, stable,
  model-correctable vocabulary lives inside `error.data.keepling_code` and
  its fixed sibling fields (`title`, `detail?`, `retryable`,
  `recovery_action`) -- the same finite field set every other adapter's
  problem+json response already uses (D-14, T-05-06). No stack trace and no
  internal detail ever reach `data`.

  This plan needs three members: insufficient scope, invalid arguments, and
  infrastructure failure. Later plans add members; nobody adds a second
  error shape.
  """

  @spec parse_error() :: map()
  def parse_error do
    envelope(-32_700, "Parse error", %{
      keepling_code: "invalid_command",
      title: "Malformed JSON-RPC request",
      retryable: false,
      recovery_action: "correct_request"
    })
  end

  @spec invalid_request() :: map()
  def invalid_request do
    envelope(-32_600, "Invalid Request", %{
      keepling_code: "invalid_command",
      title: "Invalid JSON-RPC request",
      retryable: false,
      recovery_action: "correct_request"
    })
  end

  @spec method_not_found() :: map()
  def method_not_found do
    envelope(-32_601, "Method not found", %{
      keepling_code: "method_not_found",
      title: "Unknown MCP method",
      retryable: false,
      recovery_action: "correct_request"
    })
  end

  @spec invalid_params() :: map()
  def invalid_params do
    envelope(-32_602, "Invalid params", %{
      keepling_code: "invalid_command",
      title: "Invalid tool arguments",
      detail: "Send a closed version 1 semantic tool argument shape.",
      retryable: false,
      recovery_action: "correct_request"
    })
  end

  @spec insufficient_scope() :: map()
  def insufficient_scope do
    envelope(-32_602, "Invalid params", %{
      keepling_code: "insufficient_scope",
      title: "Grant does not carry the required scope",
      retryable: false,
      recovery_action: "reauthorize_device"
    })
  end

  @spec infrastructure_failure() :: map()
  def infrastructure_failure do
    envelope(-32_000, "Server error", %{
      keepling_code: "service_unavailable",
      title: "Keepling is temporarily unavailable",
      detail: "Your request was not confirmed. Check again with the same mutation identity.",
      retryable: true,
      recovery_action: "check_mutation_result"
    })
  end

  defp envelope(code, message, data) do
    %{code: code, message: message, data: compact(data)}
  end

  defp compact(data), do: data |> Enum.reject(fn {_key, value} -> is_nil(value) end) |> Map.new()
end
