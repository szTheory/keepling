# Trust Soak: Measuring Defect Absence (D-44/D-45/D-46/D-47/D-48/D-49/D-50/D-51/D-52)

This document extends `desktop-dogfood.md` and `ios-dogfood.md`. **It does not replace either
one, and the existing ruling in both stands unchanged: sustained daily use is not automatable, is
not a gate, has no checklist, no sign-off, no required cadence, no required duration, no active-day
count, and nobody counts it.** Nothing below narrows that ruling, and nothing below turns informal
feedback into evidence or a gate — the only permitted path from a piece of dogfood feedback to
this document's evidence is that the feedback becomes a new invariant or a new chaos operator, and
the whole corpus is re-run from there.

What those two documents never covered is the other half of "no unresolved defects": the
**absence** of data loss, silent overwrite, and recovery-severity defects was previously an
assumption, not a measurement. This document is that measurement, and it states its own limits
rather than letting them be inferred.

## The three pieces

| Component | File | What it does |
|---|---|---|
| The oracle | `tooling/trust-lanes/oracle.mjs` | Takes three **independent** reads (server via read endpoints + a select-only database identity; desktop store read-only; iOS store pulled from the device) and never writes anywhere. |
| The invariants | `tooling/trust-lanes/invariants.mjs` | Eight schema-level predicates (`I1`-`I8`) evaluated over the oracle's dataset, emitting only closed-vocabulary, keyed-digest violation records — never plaintext task content. |
| The chaos corpus | `tooling/trust-lanes/chaos.mjs` | Ten named, seeded, adversarial operators run against the real two-client stack, with the invariants as the assertion layer. |
| The census | `tooling/trust-lanes/census.mjs` | Records per-day exposure (never adoption) and labels a day below the mutation floor a **thin day**. |
| The gate | `tooling/verify-trust-soak.mjs` | Produces a digest-bound evidence artifact with three honest verdicts: `PASS`, `DISCLOSED-NOT-PROVEN`, `BLOCKED`. |

## The eight invariants

| ID | Name | What it catches |
|---|---|---|
| I1 | No unsettled intent | An outbox row stuck in-flight while no client process is running. |
| I2 | Receipt closure | A mutation id absent from both a client's outbox and the server's receipts — silent loss. |
| I3 | Refusal durability | A refused or conflicted receipt with no durable local home. **This is the invariant that catches the class plan 06-06 closed** (`refusal_records`). |
| I4 | Projection agreement | A client projection that disagrees with the server at the entity revision, unexplained by an outbox row. |
| I5 | Feed continuity | A gap in the ordered feed's sequence/ordinal, or a client cursor moving backward. |
| I6 | Revision monotonicity | A revision that goes backward for the same entity, on either side, across runs. |
| I7 | Tombstone/restore coherence | A restore timestamp preceding the trash timestamp it is supposed to follow. |
| I8 | Activity completeness | An accepted mutation with no matching activity record — the direction `task_activities`' own foreign key does not cover. |

## The detection floor and the permanent blind spot

**The oracle sees only durable state.** Loss between a keystroke and a commit — before a
mutation reaches its own client's durable outbox — is entirely outside its reach. That window
belongs to the end-to-end and accessibility lanes (`apps/desktop/test/e2e`,
`apps/ios/Tests/KeeplingUITests`), never to this oracle. Naming this here is what stops coverage
from being inferred where none exists: the trust-soak gate proves durable-state reconciliation, and
nothing about the keystroke-to-commit path.

The evidence artifact (`.artifacts/trust-soak/trust-soak-evidence.json`) states its own detection
floor, computed from the corpus's actual accumulated sample count rather than asserted — a per-cycle
manifestation probability the corpus can detect at a stated confidence, and nothing rarer than
that. A verdict is never upgraded past what the accumulated evidence actually supports.

## Verdicts

- **PASS** — every invariant has a positive sample count and zero unexplained violations, the
  census floor is met, and the open-defect register shows zero open items in the three named
  classes.
- **DISCLOSED-NOT-PROVEN** — reported per invariant, with a named reason, when the evidence cannot
  support a pass but no violation was found either.
- **BLOCKED** — reported for any zero-sample lane, an unqueried defect register, an interrupted
  run, or two overlapping runs. `BLOCKED` always exits non-zero. A verdict that cannot be
  supported is never upgraded, no matter how green the surrounding lanes look.

## What adoption is, and is not

The census records exposure: locally-originated mutations, distinct task ids touched, offline
minutes, completed sync rounds, and distinct screens reached, per day. **It is never a measure of
whether the owner likes the product (D-52), and adoption is reported as an outcome, never gated.**
A thin day is a day of insufficient exposure, not a day of insufficient enthusiasm; the two claims
are kept structurally separate, on purpose, so a quiet fortnight cannot be misread as either a
clean fortnight or a verdict on the product itself.

## Running it

```sh
node tooling/trust-lanes/oracle.mjs --server-db-url "$KEEPLING_TRUST_SOAK_AUDITOR_URL" \
  --desktop-store-path /path/to/desktop-store.sqlite --json
node tooling/trust-lanes/chaos.mjs --list-operators
node tooling/trust-lanes/chaos.mjs --seed 1 --iterations 20
node tooling/trust-lanes/census.mjs --self-check
node tooling/verify-trust-soak.mjs --self-test
node tooling/verify-trust-soak.mjs --gate
```

`--server-db-url` must point at the `keepling_auditor` role provisioned by
`20260912000300_add_auditor_role.exs` — never at the application's own write-capable role. The
oracle refuses to run against a role that can write (see `tooling/verify-trust-soak.mjs`'s own
self-test fixture for this exact case).
