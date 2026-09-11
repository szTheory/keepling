# Security Policy

Keepling is a personal, open-source project maintained by one person. This document states what
is promised, what is not, and how to report a vulnerability.

## Reporting a vulnerability

**Use GitHub's private vulnerability reporting.** Go to this repository's **Security** tab →
**Report a vulnerability**. This is the only channel.

No email address is published for security reports. An unmonitored or bouncing inbox is worse
than none — private vulnerability reporting is the channel that is actually watched.

**The bound, stated in your favour, not a promise about response time:** I will not commit to
responding within any specific number of hours or days, because that is a promise a sole
maintainer cannot reliably keep. Instead: **if fourteen days pass with no acknowledgement from
me, assume I am unreachable and disclose publicly without further notice to me.** You cannot
breach a promise that was never made, and you should never be left waiting indefinitely on one
that was.

## Safe harbour

If you are testing against an instance you own — your own self-hosted deployment, or a local
development instance — in good faith, to find and report a vulnerability, I will not pursue or
support legal action against you for that testing. This safe harbour is scoped to instances you
control. **It cannot bind a self-hoster's instance you do not own** — testing someone else's
self-hosted Keepling without their permission is between you and them, not covered by anything
stated here.

## Security invariants

Properties Keepling is designed to hold, and that a report showing otherwise is valuable for:

| Invariant | Statement |
|---|---|
| Authorization boundary | A credential (browser session, device bearer, MCP grant) never acts outside the scopes it was actually granted, regardless of what content it processed. |
| Confirmation for high-impact writes | An action the product defines as requiring confirmation is never executed unconfirmed, including when the acting agent is an AI model. |
| Preview and undo | An action defined as previewable or undoable cannot be forced to skip that preview or undo path. |
| Redaction | Diagnostic logs, traces, and metrics never carry task titles, notes, prompts, tokens, or other content this project has committed to redacting — enforced by `packages/contracts/vectors/redaction.json` and `tooling/verify-privacy.sh`, not merely stated. |
| Data isolation | One account's tasks, projects, and tags are never readable or writable by a credential scoped to a different account. |

## Security non-goals

Properties Keepling explicitly does not claim, so a report about them is expected and welcome but
is not "the authorization boundary failed":

| Non-goal | Statement |
|---|---|
| Uninfluenceable models | Keepling does not claim any AI model it talks to cannot be persuaded, confused, or manipulated by adversarial text. It claims the authorization boundary holds regardless of what the model was convinced to want. |
| Self-hoster operational security | Keepling does not audit or attest to how a self-hoster runs their own server, database, reverse proxy, or host operating system. |
| Availability guarantees | This project makes no uptime, response-time, or service-level commitment (see `SUPPORT.md`). |
| Physical device security | Loss or compromise of a person's own unlocked device is outside what any application-layer control can address. |

## Scope: prompt injection

The scope boundary for a prompt-injection report is drawn at **authority, not persuasion**.

**In scope as a vulnerability** — content in a task, a note, or a tool result that:

- causes action outside the calling agent's granted scopes;
- bypasses a preview or undo path that should have applied;
- causes an unconfirmed write where confirmation is required;
- exfiltrates data the agent was not scoped to read; or
- reaches the underlying model despite a stated redaction guarantee.

**Out of scope by design** — that a model can be made to produce wrong, rude, or manipulated
*text*. Keepling does not claim its models are uninfluenceable; it claims the authorization
boundary holds regardless of what the model was convinced to want.

A report that defeats the existing adversarial injection lane
(`apps/server/test/keepling_web/mcp/injection_vector_test.exs` and
`apps/server/test/keepling_web/mcp/content_isolation_test.exs`) by crossing the authority
boundary — not merely producing objectionable text — is **the most valuable report this project
can receive.**

## Supported versions

The unit of support is the **protocol train**, not a marketing version number: the supported set
is the current protocol train plus the immediately previous one — the same compatibility window
the sync layer already enforces at runtime. End of support for a previous train is the inclusive
deprecation deadline published by the `/compatibility` endpoint, which is the machine-readable
source of truth. The table below is a generated, checked mirror of that source — it is never
hand-maintained, and `tooling/check-repository-integrity.sh`'s governance lane fails if the two
drift apart.

**Pre-release honesty line:** Keepling has not had a first release. Until it does, the supported
set below is empty, and this table will not list a version that was never published.

<!-- keepling:generated:supported-versions:start -->
| Protocol train | Status | Support ends |
|---|---|---|
| — | no released version yet | — |
<!-- keepling:generated:supported-versions:end -->

**Security-emergency exception:** the minimum supported protocol train may be raised before its
normal deprecation deadline, but only alongside a simultaneously published security advisory. A
floor raise with no accompanying advisory is a bug in this policy's *execution*, not a valid use
of it — if you see one, please report it as a bug via the channel above.

## CVE requests

Private vulnerability reporting and GitHub Security Advisories are enabled for this repository. A
CVE will be requested from GitHub (as CVE Numbering Authority) for any **confirmed vulnerability
in a released, distributed artifact that has a shipped fix.** CVEs are not requested for
pre-release, main-branch-only issues that never reached a distributed release — an advisory
should mean what it says. Publishing an advisory is also what notifies self-hosters through
GitHub's own dependency and security-alert surface, which is how you learn a security update
exists.
