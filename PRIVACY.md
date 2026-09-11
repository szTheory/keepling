# Privacy

Most privacy policies are a promise. This one names, for every claim, the artefact that enforces
it and the command you can run yourself to check it. If an artefact is deleted, the corresponding
claim below is no longer true, and this document says so rather than continuing to assert it.

## Controller boundary

**If you self-host Keepling, you are your own data controller.** There is no
controller-processor relationship between you and the author of this project. Neither the EU
GDPR nor the California CCPA/CPRA attaches to the author by virtue of your use of
self-hosted software he does not operate, host, or have access to.

**This document does not describe any hosted service.** Keepling has no hosted offering today.
If a hosted service is ever built, it will need, and will publish, its own privacy policy — one
that describes what that service's operator actually does with your data as a processor or
controller in its own right. Nothing in this document may be cited as the privacy policy of any
hosted Keepling service, now or in the future.

## Claims, with evidence

| Claim | Enforcing mechanism | Verify it yourself |
|---|---|---|
| Diagnostic logs, metrics, and traces never contain a task title, task note, AI prompt, recovery token, or sync cursor value. | A committed list of hostile sentinel values that must never appear in any diagnostic artifact, checked by a scanning script. | `packages/contracts/vectors/redaction.json` and `tooling/verify-privacy.sh` (its `--self-test` mode demonstrates rejection of a hostile artifact and acceptance of a clean one). |
| Authentication decisions, sync resets, and error diagnostics report only bounded, non-identifying state facts (an outcome code, a count, a sanitized reason) — never the raw content that triggered them. | An ExUnit test suite that attaches real telemetry handlers to the server's authentication and sync events, injects the same hostile sentinel values, and asserts none of them appear in the emitted metadata. | `apps/server/test/keepling/telemetry_redaction_test.exs`, run with `mix test` from `apps/server`. |
| No remote telemetry is enabled by default for a self-hosted instance. | The server ships with no default OTLP/remote-telemetry endpoint configured; observability is opt-in and configured by the operator, not phoned home automatically. | `apps/server/config/config.exs` and `apps/server/config/runtime.exs`, grepped for `otlp` or any outbound telemetry endpoint. |
| Your data leaves in a plain, independently readable format whenever you ask for it — not locked into a proprietary export you cannot use elsewhere. | A neutral export command that produces a plaintext bundle (JSON files plus a manifest with per-file checksums), verified end-to-end by an independent reader that does not reuse the product's own import code. | `apps/server/lib/keepling/application/export.ex` and `tooling/verify-export-reader.mjs`. |

## What this means in practice

- **No raw task content leaves your instance for diagnostics.** Titles, notes, and AI prompts are
  never redaction-exempt; they do not appear in logs, metrics, or traces regardless of the
  outcome being reported.
- **Only bounded, sanitized facts are ever recorded for troubleshooting** — things like "sync
  reset, reason: cursor invalid" or "authentication decision: denied, reason: rate limited," never
  the credential, token, or content involved.
- **Nothing about your account is sent anywhere by default.** A self-hosted instance talks to the
  server you deployed it against and nowhere else unless you configure it to.

## Retention and deletion

Keepling stores your tasks, projects, tags, and account data for as long as your account exists.
Deleting an account is your own instance's operator responsibility (yours, if you self-host); this
document does not describe a hosted deletion process because no hosted service exists today.

## Changes to this document

This document changes when the underlying enforcement changes, never the other way around — the
evidence paths above are checked mechanically by
`tooling/check-repository-integrity.sh`'s governance lane, so a claim cannot silently drift ahead
of what actually enforces it.
