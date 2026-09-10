defmodule KeeplingWeb.MCP.Errors do
  @moduledoc """
  Closed JSON-RPC error mapping (D-14). The top-level `code`/`message` stay
  inside the standard JSON-RPC range; Keepling's own closed, stable,
  model-correctable vocabulary lives inside `error.data.keepling_code` and
  its fixed sibling fields (`title`, `detail?`, `retryable`,
  `recovery_action`) -- the same finite field set every other adapter's
  problem+json response already uses (D-14).

  `@mcp_error_codes` (05-05-PLAN.md Task 3) is the closed vocabulary
  covering everything the phase's tools can return: insufficient scope,
  invalid arguments, an unknown tool, a task that does not exist, every
  revision conflict shape the shared command store's own closed conflict
  vocabulary produces (`task_edit_conflict`, `task_assignment_conflict`,
  `task_lifecycle_conflict`, `task_trash_conflict` -- reused verbatim
  rather than collapsed into a single generic code, so a stale write
  renders the exact body the HTTP path renders for the identical
  situation, byte for byte, per 05-05-PLAN.md Task 2), the not-yet-wired
  ambiguity and preview/commit members later plans in this phase reach
  (`ambiguous_match`, `no_match`, `too_many_matches`, `preview_stale`),
  `rate_limited`, and `service_unavailable`. Every member has a fixed
  literal title and a fixed literal recovery action selected by code --
  never interpolated, never formatted, never carrying a per-run value.
  Structured detail a model genuinely needs to correct itself (a candidate
  set, a current revision number) lives in a separate structured field of
  `data`, never inside the human string.

  `parse_error/0`, `invalid_request/0`, and `method_not_found/0` are
  JSON-RPC FRAMING errors -- they fire before any tool is ever identified
  -- and stay outside `@mcp_error_codes`, which is scoped to what a tool
  CALL can return.
  """

  @mcp_error_codes ~w(
    insufficient_scope
    invalid_command
    unknown_tool
    task_not_found
    task_edit_conflict
    task_assignment_conflict
    task_lifecycle_conflict
    task_trash_conflict
    ambiguous_match
    no_match
    too_many_matches
    preview_stale
    rate_limited
    service_unavailable
  )

  @spec mcp_error_codes() :: [String.t()]
  def mcp_error_codes, do: @mcp_error_codes

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

  @spec unknown_tool() :: map()
  def unknown_tool do
    envelope(-32_602, "Invalid params", %{
      keepling_code: "unknown_tool",
      title: "Unknown MCP tool",
      detail: "Call tools/list for the closed set of available tools.",
      retryable: false,
      recovery_action: "correct_request"
    })
  end

  @spec task_not_found() :: map()
  def task_not_found do
    envelope(-32_602, "Invalid params", %{
      keepling_code: "task_not_found",
      title: "Task not found",
      detail: "Refresh the view before trying again.",
      retryable: false,
      recovery_action: "refresh_view"
    })
  end

  @spec ambiguous_match([map()]) :: map()
  def ambiguous_match(candidates) when is_list(candidates) do
    envelope(-32_602, "Invalid params", %{
      keepling_code: "ambiguous_match",
      title: "Multiple tasks match this request",
      detail: "Narrow the request to exactly one task using its stable identity.",
      retryable: false,
      recovery_action: "disambiguate_request",
      candidates: candidates
    })
  end

  @spec no_match() :: map()
  def no_match do
    envelope(-32_602, "Invalid params", %{
      keepling_code: "no_match",
      title: "No task matches this request",
      detail: "Confirm the task exists and is visible to this grant.",
      retryable: false,
      recovery_action: "correct_request"
    })
  end

  @spec too_many_matches() :: map()
  def too_many_matches do
    envelope(-32_602, "Invalid params", %{
      keepling_code: "too_many_matches",
      title: "Too many tasks match this request",
      detail: "Narrow the request -- the candidate set exceeds the bounded limit.",
      retryable: false,
      recovery_action: "narrow_request"
    })
  end

  @spec preview_stale() :: map()
  def preview_stale do
    envelope(-32_602, "Invalid params", %{
      keepling_code: "preview_stale",
      title: "Preview is no longer valid",
      detail: "The previewed targets changed or expired. Request a new preview.",
      retryable: false,
      recovery_action: "request_new_preview"
    })
  end

  @spec rate_limited() :: map()
  def rate_limited do
    envelope(-32_000, "Server error", %{
      keepling_code: "rate_limited",
      title: "Too many requests",
      detail: "Wait before retrying this request.",
      retryable: true,
      recovery_action: "retry_after_backoff"
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

  # 05-05-PLAN.md Task 2: `execute/3` returns EVERY domain refusal (task
  # not found, a stale-expected-revision conflict, invalid task details,
  # ...) as `{:ok, %{status:, body:}}` -- the identical shape the HTTP
  # command endpoints render as an `application/problem+json` body --
  # rather than an `{:error, reason}` tuple. `from_problem/2` maps that
  # same body into the JSON-RPC error envelope so an MCP client sees the
  # same code/title/detail/retryable/recovery_action, plus any structured
  # extension fields (affected_fields, current_revision) a model needs to
  # correct itself (D-14), that the HTTP path returns for the identical
  # setup. `status`/`type` are HTTP-transport fields with no JSON-RPC
  # equivalent and are dropped. The `code` this body carries is always one
  # of the closed `task_edit_conflict` / `task_assignment_conflict` /
  # `task_lifecycle_conflict` / `task_trash_conflict` / `task_not_found`
  # members -- reused verbatim, never re-worded, because a body this
  # function is fed always originates from the shared command store's own
  # fixed-literal `problem/6`/`semantic_rejection/2` construction.
  @spec from_problem(integer(), map()) :: map()
  def from_problem(status, %{"code" => code} = body) do
    data =
      body
      |> Map.drop(["code", "status", "type"])
      |> Map.new(fn {key, value} -> {String.to_atom(key), value} end)
      |> Map.put(:keepling_code, code)

    if status >= 500 do
      envelope(-32_000, "Server error", data)
    else
      envelope(-32_602, "Invalid params", data)
    end
  end

  defp envelope(code, message, data) do
    %{code: code, message: message, data: compact(data)}
  end

  defp compact(data), do: data |> Enum.reject(fn {_key, value} -> is_nil(value) end) |> Map.new()
end
