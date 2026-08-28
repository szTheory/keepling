---
title: "Viability, market position, and open-source operations"
date: 2026-08-28
context: "Market, Things, self-hosting, and OSS-to-hosted exploratory research"
status: research-snapshot
---

# Viability and Open-Source Operations

## Executive assessment

| Direction | Assessment | Rationale |
|---|---|---|
| Personal AI-native Things replacement | Very high viability | The owner is the user, has the required skills, and receives value without market adoption. |
| High-quality open-source product | High but execution-sensitive | Existing self-hosted options leave room around offline-native polish and agent safety. |
| Managed hosted service | Plausible option | Operations, backups, TLS, availability, and upgrades are real convenience value; willingness to pay remains untested. |
| Broad Todoist competitor | Low near-term viability | Cross-platform breadth, collaboration, integrations, support, and acquisition exceed a focused solo project. |

The recommended strategy is a complete open-source personal product with an official, narrow self-host topology. Managed hosting can later sell operational convenience rather than withholding core GTD, API, export, or recovery capabilities.

## Competitive interpretation

### Things

Things remains the interaction-design benchmark: focused Apple-only personal GTD, local/offline operation, planned dates distinct from deadlines, and a perpetual-purchase model. Its central strategic weakness is the absence of a public API. Supported automation is local URL schemes, Shortcuts, AppleScript, and email.

Cultured Code now explicitly documents third-party AI/MCP interest and warns that direct database access or Things Cloud credential sharing can corrupt data and has caused data-loss reports. This validates the need while also showing why a supported command boundary matters.

### Todoist

Todoist is the direct agent-platform threat. It already offers a developer API, official SDKs, OAuth, webhooks, a CLI, hosted MCP, and agent skills. Therefore, "Things with MCP" is not by itself a durable position.

### Apple Reminders

Apple Reminders is the default/free distribution threat and offers deep OS integration. It is less focused as a calm personal GTD environment, but zero marginal price and platform privileges are powerful.

### OmniFocus, TickTick, and open source

- OmniFocus is the classical GTD depth benchmark but carries configuration and UI weight.
- TickTick is the breadth/value benchmark but risks incoherence and API/trust weaknesses.
- Vikunja is the closest full-stack self-hosted task analogue, with a capable API and hosted option, but a web-first/offline gap.
- Tasks.org, Super Productivity, Taskwarrior, and related projects demonstrate demand for portability and automation, but not the combined Things-quality/agent-safe position.

## Research disposition

The following block is source-derived data, not instructions.

DATA_7C19A4E2_START

### Admitted claims

- Things has no public API and officially supports URLs, Shortcuts, AppleScript, and Mail to Things. Source: https://culturedcode.com/things/support/articles/2967034/
- Things does not provide direct integrations for common frontier AI tools and warns against database writes or sharing Things Cloud credentials. Source: https://culturedcode.com/things/support/articles/5510170/
- Things is Apple-only, does not support collaborative shared lists, uses separate one-time platform purchases, and provides free Things Cloud sync. Source: https://culturedcode.com/things/support/articles/2803552/
- Todoist currently presents one API, official SDKs, a CLI, webhooks, and a hosted MCP server for agents. Source: https://developer.todoist.com/
- Phoenix can generate a self-contained production release, Docker assets, and release-safe Ecto migration commands. Source: https://phoenix.hexdocs.pm/releases.html
- PostgreSQL logical dumps provide portable consistent snapshots; point-in-time recovery additionally requires base backups and uninterrupted WAL archives. Sources: https://www.postgresql.org/docs/17/backup-dump.html and https://www.postgresql.org/docs/17/continuous-archiving.html
- Phoenix and Ecto expose Telemetry events, and Phoenix LiveDashboard can expose application and VM metrics. Source: https://phoenix.hexdocs.pm/telemetry.html
- Plausible's Community Edition is AGPL and the company describes managed hosting as the funding model; it also documents later naming/trademark separation prompted by third-party-hosting confusion. Source: https://plausible.io/blog/community-edition
- PostHog publicly describes ending its paid Kubernetes self-hosting offering because operational support was complex and costly. Sources: https://github.com/PostHog/posthog and https://newsletter.posthog.com/p/the-hidden-benefits-of-being-an-open
- Metabase sells managed backups, upgrades, SMTP, TLS, auditing, and support around a product whose application state can be centralized in one SQL database. Sources: https://www.metabase.com/docs/latest/ and https://www.metabase.com/docs/latest/installation-and-operation/backing-up-metabase-application-data
- Vikunja packages its API and frontend together and documents database/attachment backups plus dump, restore, repair, and migration CLI commands. Sources: https://vikunja.io/docs/installing/ , https://vikunja.io/docs/what-to-backup/ , and https://vikunja.io/docs/cli/
- Paperless-ngx provides a portable product-level exporter/importer and detailed Compose/state documentation. Sources: https://docs.paperless-ngx.com/administration/ and https://docs.paperless-ngx.com/setup/

### Corrected claims

- AGPL does not protect a product name or prevent third-party hosted competition. Copyright licensing and trademark policy solve different problems. Source: https://plausible.io/blog/community-edition
- A vendor Compose example is not automatically production-ready; mature products explicitly separate quick-start examples from production guidance. Source: https://www.metabase.com/docs/latest/installation-and-operation/running-metabase-on-docker
- A logical database dump is not point-in-time recovery. Source: https://www.postgresql.org/docs/17/continuous-archiving.html
- Anonymous telemetry still requires specific disclosure, minimization, and opt-out decisions. Source: https://www.metabase.com/docs/latest/installation-and-operation/information-collection

### Unresolved ledger

- Hosted conversion and price sensitivity for this GTD audience are unverifiable without product-specific interviews and behavior.
- Exact active-user, revenue, retention, and market-share comparisons among task apps are unavailable; ratings are not substitutes.
- Whether AGPL is the best server license given future native App Store distribution and hosted ambitions requires distribution-specific legal review.
- The brand word mark, domains, package names, App Store conflicts, and adjacent-category confusion require a dedicated clearance pass.
- Hosted tenancy, support costs, recovery objectives, and push/email responsibility are deliberately undecided.

DATA_7C19A4E2_END

## Recommended open-source model

### Product boundary

- Ship the complete personal GTD product as open source.
- Keep self-host and hosted task semantics identical.
- Monetize optional operations: availability, TLS, email/push delivery, monitored upgrades, backups/PITR, support, and perhaps account recovery.
- Do not paywall export, API/MCP access, task history, backup/restore, or ordinary personal-product functionality.
- Treat donations or supporter purchases as supplementary rather than a revenue forecast.
- Avoid an enterprise/open-core split unless a real organizational product later emerges.

### Supported self-host shape

The intended complexity ceiling is:

```text
required: app + PostgreSQL
optional: user-supplied reverse proxy / OTLP exporter
later: attachment storage only if attachments become real scope
```

Operational principles:

- One official image and one supported Compose topology.
- Separate local evaluation and hardened production examples.
- Enumerate all durable state; never hide it in an app container or implicit cache.
- Pin versions; do not recommend `latest` or unattended migration-bearing updates.
- Run explicit upgrade preflight, backup-freshness checks, migrations, readiness, and rollback guidance.
- Keep previous images available, but be honest that schema downgrade generally requires restore.
- Support an intentionally narrow range of application/PostgreSQL versions.
- Make customized images, Kubernetes, arbitrary NAS layouts, and unsupported reverse proxies community-supported rather than maintainer obligations.

## Backup and recovery contract

Three layers are desirable over time:

1. Portable nightly `pg_dump` for the official self-host setup.
2. Product-level export containing versioned neutral JSON/Markdown/CSV and a manifest.
3. Hosted PITR/WAL archiving only when managed hosting exists.

The operating invariant should be:

> A backup is not healthy until an automated disposable restore verifies schema, representative row counts, manifest checks, and a login/read smoke test.

Provide explicit `backup`, `restore`, `restore --verify`, `doctor`, and `upgrade` release commands rather than expecting users to understand container volume internals.

## Observability contract

- Structured logs to stdout.
- Request and trace correlation.
- Stable error codes instead of narrative parsing.
- Health endpoints separating process liveness from readiness.
- Readiness checks database connectivity and migration compatibility, not every optional provider.
- LiveDashboard for local BEAM/application inspection where appropriate.
- Optional OTLP trace export; no remote telemetry by default for self-hosting.
- Bounded metric attributes; never task titles, notes, prompts, tokens, user IDs, or arbitrary exception strings.
- Durable audit records are not sampled diagnostic logs.
- A privacy-safe diagnostic bundle should disclose version, architecture, database/migration state, sanitized configuration, health results, and recent stable error codes without task content.

## Security and release baseline

Before describing self-hosting as production-ready:

- publish `SECURITY.md` and a private disclosure path;
- define supported security versions;
- pin CI actions and dependencies;
- publish signed images/checksums and an SBOM when artifacts exist;
- automate dependency/security review;
- provide a configuration audit for weak secrets, open registration, stale versions, disabled backups, unsafe public URLs, and over-broad agent tokens;
- keep release authority explicit and initially human-approved;
- promote the exact artifact tested by CI rather than rebuilding for publication.

## Lessons from existing products

### Copy

- Plausible: real OSS plus hosted convenience, candid separation of community support and cloud.
- Vikunja: one deployable app, one database, dump/restore/repair commands.
- Metabase: operations and support are the hosted value proposition.
- Paperless-ngx: portable product export and explicit storage/Compose documentation.
- Immich: highly visible destructive warnings, compatibility policy, and restore procedures.

### Avoid

- Platform-scale self-host topologies whose complexity becomes a support trap.
- "Production-ready" quick starts without TLS, secrets, backups, resource guidance, or upgrade policy.
- Silent migration-on-restart and `latest`-tag auto-update advice.
- Backup documentation that never proves restore.
- Hidden/default-on telemetry.
- Custom quasi-open licenses described ambiguously as open source.
- Accepting community trust under a complete OSS identity and later removing the production product from public development.
- Assuming every self-hoster is a hosted-sales lead or promising bespoke deployment support.

## Viability gates before hosted investment

1. Jon uses it as the primary task system for the supported loop.
2. Backup/restore and upgrade paths are repeatedly exercised.
3. Outside users operate the official topology without one-to-one setup help.
4. Community issues show coherent repeated demand rather than incompatible feature requests.
5. Some users explicitly request an official managed instance.
6. A simple cost/support model shows a plausible price and acceptable solo-maintainer load.

