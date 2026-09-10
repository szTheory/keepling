# MCP Surface Coverage

**Pinned protocol revision:** `2025-06-18` (D-04, D-30). `KeeplingWeb.MCP.Handshake` declares this
verbatim in `initialize` and never negotiates down to whatever revision a client offers. Per D-30,
this pin must be re-checked against **live representative host behaviour** before the transport is
changed -- not re-verified against this document. See `05-01-SUMMARY.md`'s "Decisions Made" for the
open item: the live-host re-check itself could not be performed in this execution environment.

This document is the phase's explicit, test-enforced decision about which parts of the pinned
revision's surface this server implements. `test/keepling_web/mcp/surface_test.exs` binds the
"implemented" rows below to `KeeplingWeb.MCP.Dispatch`'s closed `@methods` list byte for byte --
a method added to the code without a row here, or a row here with no matching code, fails that
test. "Not implementing this, because the dogfood use case does not need it" is a complete and
expected reason for every `not_implemented` row; the goal of this document is that every gap is a
decision, not something a host discovers by probing.

## Canonical resource URI

`{configured device-grant origin}/mcp/v1` -- the same value `05-01-SUMMARY.md` records as the
canonical MCP resource URI, matching the mounted `POST /mcp/v1` path and the RFC 8707 `resource`
parameter every `mcp` client must send on `/oauth/authorize` and `/oauth/token`.

## Agent scopes and which methods each admits

| Scope | Admits |
|---|---|
| `tasks.read` | `resources/list`, `resources/read`, `keepling.search_tasks` (a `tools/call` invocation) |
| `tasks.write` | `keepling.capture_task`, `keepling.update_task`, `keepling.complete_task`, `keepling.reopen_task` |
| `tasks.bulk` | `keepling.preview_bulk_change`, `keepling.commit_bulk_change` |

`tools/list` and `resources/list` themselves require no scope beyond a valid `mcp` bearer grant --
they enumerate the closed, fixed tool/resource set, not account data. Every read and write above
is checked twice: once at the adapter fast-fail (`KeeplingWeb.MCP.Scope`) and once again at the
application boundary (`Keepling.Application.AgentScope`), per D-06/T-05-19.

## Page sizes

| | Value |
|---|---|
| Default page size (all bounded reads: task views, search, projects) | 20 |
| Maximum page size (clamped, never rejected, above this) | 50 |

## Method and capability coverage

| Method / capability | Status | Reason |
|---|---|---|
| `initialize` | implemented | Handshake -- declares the pinned protocol revision and capabilities. |
| `ping` | implemented | Liveness check. |
| `resources/list` | implemented | MCP-01: enumerates the seven bounded read resources. |
| `resources/read` | implemented | MCP-01: reads a bounded, cursor-paged, redacted page for any of the seven resources. |
| `resources/templates/list` | not_implemented | The seven read resources are a small, fixed set fully enumerated by `resources/list` (two entries carry a literal `{task_id}`/`{project_id}` placeholder); no dynamic template discovery is needed for the dogfood use case. |
| `resources/subscribe` | not_implemented | No push/subscription model exists in this phase; a host re-reads a resource to see fresh state. Declared `false` in the `initialize` capability object. |
| `resources/unsubscribe` | not_implemented | Follows `resources/subscribe`; nothing to unsubscribe from. |
| `tools/list` | implemented | Enumerates the closed six-tool set (MCP-02's four write verbs, `keepling.search_tasks`, and the MCP-05 preview/commit pair) with their closed input schemas. |
| `tools/call` | implemented | MCP-02/MCP-05: dispatches to a named tool with a closed, validated argument shape. |
| `prompts/list` | not_implemented | Keepling ships no server-authored prompt templates; the dogfood use case does not need one. |
| `prompts/get` | not_implemented | Follows `prompts/list`. |
| `completion/complete` | not_implemented | No argument-completion UX is offered; every tool/resource argument is a closed, small, opaque-identity-addressed shape a model does not need assisted completion for. |
| `logging/setLevel` | not_implemented | Server-side log verbosity is an operator concern (structured `Logger`/`Telemetry`, per `PROJECT.md`'s Observability stack choice), not something a remote MCP client controls. |
| `roots` | not_implemented (client capability) | `roots` is a capability the MCP *client* declares to the server, not something this server implements. Keepling's MCP surface has no filesystem-root concept to request. |
| `sampling` | not_implemented (client capability) | `sampling` is a capability the MCP *client* declares (letting the server ask the client's model for a completion). This server never asks a client to sample on its behalf. |
| Notification families (`notifications/resources/list_changed`, `notifications/tools/list_changed`, `notifications/cancelled`, `notifications/progress`, `notifications/message`) | not_implemented | No push notifications in this phase (matches `resources/subscribe` above). The tool and resource set is fixed at deploy time -- there is nothing for `list_changed` to announce -- and every tool call in this phase completes synchronously within a single request, so there is no long-running operation for `notifications/progress`/`notifications/cancelled` to report on. |

## D-30 re-check obligation

The pinned revision above must be verified against **live host behaviour** (a real `initialize`
round trip with a representative host such as Claude Code or Claude Desktop) before this transport
is changed -- never against this document alone, since the document only records what this server
was built against, not what a live client currently negotiates. See the open item recorded in
`05-01-SUMMARY.md`.
