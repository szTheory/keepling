---
title: "Current worldview: personal-first open-source GTD"
date: 2026-08-28
context: "Exploratory viability study before naming, PROJECT.md, requirements, or roadmap"
status: current-working-view
supersedes: null
---

# Current Worldview: Personal-First Open-Source GTD

This is a dated snapshot of what currently appears true. It is not a promise to preserve every conclusion. Later evidence should supersede individual decisions explicitly rather than silently rewriting why the earlier decision made sense.

## One-sentence thesis

Build Jon's excellent AI-native Things replacement openly, generalize it through dogfooding, and preserve a low-friction path to optional managed hosting without carrying SaaS, collaboration, or enterprise complexity before demand exists.

## Why this project exists

Things is already an unusually good personal task product for Jon's workflow. The motivating defect is not its basic GTD model or interaction quality; it is the lack of a supported, remotely programmable interface suitable for modern agent tooling.

The project is successful initially if it becomes Jon's dependable daily system on Mac and iPhone. Open-source adoption, GitHub stars, portfolio value, community contributions, and eventual hosted revenue are meaningful upside, not conditions for personal success.

This matters particularly because:

- Jon is highly AI-first and wants tasks accessible from Codex, Claude Code, and similar tools.
- Jon has deep Elixir/Phoenix, DevOps/SRE, open-source, native/cross-platform, CI/CD, and product/design experience to draw on.
- A polished public repository can provide career signal following a recent software-engineering layoff.
- Existing szTheory libraries and ExifCleaner release practices provide useful engineering DNA, but dogfooding must not turn the app into an integration showcase.

## Locked-for-now direction

| Decision | Current position | Why now | Revisit trigger |
|---|---|---|---|
| Primary user | Jon first | Fast feedback and immediate personal value | Repeated outside-user needs reveal a common core |
| Distribution | Fully open source | Trust, contribution, portfolio value, low expectations, free public CI | A specific licensing or commercial constraint appears |
| Business | Optional hosted convenience later | Preserve opportunity without premature billing/support/control-plane work | Self-hosted retention and outside demand are demonstrated |
| Product shape | Focused personal GTD | Quality depends on excluding adjacent work-management complexity | Strong evidence for a narrowly compatible adjacent use case |
| Collaboration | Not planned | Changes authorization, sync, UX, and product identity | Deliberate new product decision, not feature drift |
| Enterprise | Not planned | Conflicts with personal, calm, designed focus | Deliberate new product/milestone decision |
| Architecture | Phoenix/Postgres modular monolith | Best fit for domain integrity, operations, and solo ownership | Measured constraint that a monolith cannot meet |
| First clients | Electron on Mac, native SwiftUI on iPhone, online React web access | These are the surfaces Jon must use daily; native iPhone reliability and a Things-like always-open Mac client are part of personal success | Evidence shows a simpler surface can deliver the same experience |
| Hosting | Always-on replaceable cloud VM; Hetzner is the reference target | A sleeping laptop is not an acceptable sync authority; raw cloud infrastructure keeps self-hosting inspectable and lightweight | A better provider materially improves cost, recovery, or operator experience |
| Event model | Explicit commands/events/change log, snapshot persistence | Captures FP/CQRS/audit value without full event-sourcing cost | Replay/temporal requirements justify an event store |
| Repository | Monorepo | Server, Electron/web UI, sync contracts, and native iPhone will co-evolve | Components acquire independent consumers and release cadences |

## Product promise

The product should feel like a personal environment, not a project-management database.

### Experience pillars

1. Capture is nearly instantaneous.
2. Today is calm, intentional, and visually excellent.
3. Keyboard use on Mac is complete, not supplemental.
4. Touch use on iPhone is efficient and deliberate.
5. Offline behavior never feels like a broken fallback.
6. Sync is trustworthy, understandable, and recoverable.
7. Agent actions use the same domain rules as human actions.
8. Consequential agent changes are inspectable and reversible.
9. The complete user history is portable.
10. Installation, upgrades, backups, restores, and diagnosis are quiet and highly automated.
11. Accessibility, reduced motion, and native platform conventions are quality fundamentals.
12. Polish, feedback, microinteraction, and "game feel" support comprehension; they are not decorative noise.

## Strategic position

The current product wedge is:

> Things-like calm and interaction quality + trustworthy first-party programmability + offline reliability + open-source/self-hosted portability.

"Has MCP" is not a sufficient differentiator because Todoist already provides official MCP, APIs, a CLI, webhooks, and agent tooling. The harder and more interesting promise is that agent access is safe, semantic, reversible, and built into a product that remains pleasant for direct human use.

## Scope discipline

### In the initial product

- One person, multiple devices.
- A durable offline Electron client on Mac and a durable offline native SwiftUI client on iPhone.
- Online React web access sharing presentation code with Electron without becoming a third offline sync engine.
- Inbox and Today as the first high-quality views.
- Capture, clarify/edit, schedule, complete, reopen, trash, restore, and undo.
- Local data, mutation outbox, deterministic server sync, and visible conflict/recovery states.
- Read and narrow write access through MCP.
- Complete neutral export from the beginning.
- Turnkey always-on self-hosting with one Phoenix service and PostgreSQL on a replaceable cloud VM.

### Explicitly deferred

- Collaboration, assignments, shared workspaces, and enterprise administration.
- Billing, hosted control planes, sales, and paid support.
- Public App Store/TestFlight and signed/notarized Electron distribution until continuous dogfood or public adoption requires them.
- Windows and Linux Electron artifacts until actual demand justifies the release matrix.
- Durable browser-offline synchronization while Electron and iPhone already cover the primary offline workflows.
- Attachments, calendar integration, general plugins, and broad notification orchestration.
- Full event sourcing, CRDTs, microservices, Redis, Elasticsearch, Kubernetes, and bespoke orchestration.
- In-product model hosting, autonomous planning agents, agent memory, or a general AI chat surface.

## Design and brand principles

The eventual name and identity must be distinctive in sound, spelling, color, and visual language. It should not contain generic category language such as "todo," imitate Things' blue, or borrow Todoist's visual territory. It should plausibly support a protectable word mark and stand on its own as an open-source project before a commercial offering exists.

The selected emotional territory is a hybrid of **trusted steward** and **playful familiar**: a small, distinctive, friendly object or companion that quietly keeps commitments safe. The brand should remain dependable and calm rather than childish, corporate, or visually coded as generic AI software.

Brand work is required before public repository naming, but detailed identity design should follow the product thesis and naming clearance rather than delay technical exploration.

## Engineering principles

- Prefer a modular monolith and explicit boundaries over distributed services.
- Keep business rules independent of LiveView, MCP, storage, and client frameworks.
- Use semantic commands instead of arbitrary record patches.
- Prefer immutable facts, typed events, auditability, and compensating commands.
- Do not confuse a sync change feed, a security audit, and an event store.
- Live off the land: BEAM/OTP, Phoenix, Ecto, PostgreSQL, browser standards.
- Add a dependency or service only when its operational and conceptual cost has a measured payoff.
- Prefer dependency injection through narrow behaviors/protocols and explicit ports so domain behavior is testable with deterministic fakes.
- Share wire contracts, golden behavioral vectors, and design-token values across runtimes; deliberately duplicate platform persistence, lifecycle, and native UI.
- Automate recurring proof in CI; archive one-time reconciliation instead of immortalizing it as a workflow.
- Test at every layer that can catch a distinct class of failure: pure domain, property/model, persistence, API/contract, adapter integration, browser/Electron E2E, packaged artifact, simulator, and physical device.
- Cover happy paths, error paths, boundary conditions, recovery, and user-visible failure states. Every important screen must have representative populated, empty, loading, offline, denied, stale, conflict, partial, and unrecoverable states where those states are meaningful.
- Optimize the test portfolio to the point of diminishing returns, not toward a vanity coverage number. Keep required CI fast with hermetic tests, path-aware lanes, parallelism, caching, and slow-test observability; move expensive device/artifact suites to the narrowest trustworthy promotion gate.
- Build once, bind evidence to the exact revision, and promote tested artifacts when distribution begins.
- Default to privacy-safe structured telemetry and silence on the wire.
- Treat backup as unproven until restore verification succeeds.
- Keep self-host support bounded to an official topology and diagnostic contract.

## Existing szTheory components

Current fit, subject to implementation validation:

- **Sigra:** likely the only internal library worth dogfooding initially, for application identity and browser sessions.
- **Lockspire:** later, when third-party or remote MCP clients need OAuth/OIDC; it is not ordinary application login.
- **Crosswake:** later or experimentally for bounded ancillary/native surfaces; not the GTD sync engine or offline authority.
- **Threadline:** later for security/operator audit depth; not the client sync feed.
- **Accrue:** only when hosted billing/productization exists.
- **Chimeway:** only when multi-channel notification policy and delivery operations become real.
- **Rindle:** only if attachments enter scope.
- **Scrypath:** only if PostgreSQL search becomes measurably insufficient.

The governing rule is to dogfood at most Sigra plus direct Phoenix/Ecto dependencies at first. The app must remain a coherent product, not a demonstration harness for the library portfolio.

## Success signals

Personal success precedes market success:

1. Jon stops reaching for Things for the supported daily loop.
2. Mac and iPhone capture remain useful across network loss and server outage.
3. No accepted mutation is lost, silently duplicated, or silently overwritten.
4. Agent reads and writes are more useful than Things automation without requiring unsafe database access.
5. Self-host installation, upgrade, backup, restore, and diagnosis are boring.
6. The public repository communicates unusually high engineering and design quality.

Later market signals include sustained outside dogfooding, issue quality, repeat contributors, stars, and requests for managed hosting. Stars alone are distribution/portfolio evidence, not product retention.

## Principal risks

- Sync and recurrence semantics can consume the project before the core experience exists.
- Multiple durable clients can multiply sync, migration, compatibility, and release burden if contracts and tracer slices are not kept narrow.
- Shared React UI can become a lowest-common-denominator abstraction if platform interaction is forced into shared components instead of adapters.
- Self-hosting support can become unpaid bespoke infrastructure consulting.
- A broad feature checklist can erase the deliberate focus that makes Things appealing.
- The internal library portfolio can introduce coupling and coordinated-release burden.
- A beautiful clone without a distinct interaction thesis and brand can look derivative.
- Agent access can create data-loss or trust failures if safety is delegated to model obedience.
- Overbuilt CI, observability, or planning machinery can become a second product.

## Open decisions

- Exact offline guarantee and maximum disconnected period.
- Initial iOS minimum; modern-only is acceptable to Jon, with the exact floor chosen by least-surprise market expectations and framework payoff.
- Minimum viable Things parity for Jon beyond Inbox and Today.
- Temporal model: explicit Today focus, planned date, defer/start date, deadline, and reminder semantics.
- Naming criteria, candidate territories, trademark/domain/package clearance process.
- License and contributor governance.
- Backup recovery objectives and supported PostgreSQL versions.
- Exact trigger for paid Apple Developer membership; current intent is to develop free as far as practical, then enroll when continuous native dogfood requires it.
- Exact trigger for Electron signing/notarization; current intent is to defer until distribution friction or platform capabilities justify it.

## Decision changes captured on 2026-08-28

### PWA-first → native iPhone + Electron Mac

- **Previous conclusion:** an installable PWA could provide the first Mac and iPhone dogfood loop without certificates.
- **New evidence/user need:** iPhone reliability, durable offline capture, native reminders/sharing, and a Things-like phone experience are non-negotiable; Jon also needs an always-open desktop client for rapid daily feedback.
- **New conclusion:** native SwiftUI iPhone and Electron Mac are primary clients. React web access remains useful but is online-first. PWA behavior is not the mobile correctness baseline.
- **Why the old conclusion changed:** it optimized distribution cost before fully weighting the actual daily workflow.

### Laptop-hosted → always-on cloud reference

- **Previous conclusion:** a laptop plus private HTTPS could cheaply prove self-hosting.
- **New evidence/user need:** the server must remain available independently of a personal laptop, and the deployment should demonstrate turnkey IaC/operator quality.
- **New conclusion:** first-party reference deployment targets an always-on replaceable Hetzner VM provisioned through Terraform/OpenTofu, with a portable container/data contract.
- **Why the old conclusion changed:** laptop hosting was acceptable for a spike but not for the intended daily system.

### Signing as productization → signing when dogfood requires it

- **Previous conclusion:** Apple and Electron signing were productization-stage concerns.
- **New evidence/user need:** native iPhone is required, while public distribution can still be deferred.
- **New conclusion:** use free development paths first; pay Apple membership when continuous device use requires it. Defer Electron signing until its real platform/distribution benefits are needed.

## Change protocol

When this worldview changes, record:

- the previous conclusion;
- the new evidence or user need;
- the new conclusion;
- what downstream assumptions change;
- whether the earlier conclusion was wrong or merely correct for an earlier stage.
