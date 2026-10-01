# OSS Project DNA: CI/CD and Delivery Practices

**Reviewed:** 2026-10-01

**Purpose:** Use proven practices from Jon's first-party OSS projects to improve Keepling's pull request, CI, release, and protected-operation flow.

## Scope and evidence quality

The local `~/projects` scan found 29 repository/worktree directories with GitHub Actions workflows, including a temporary validator checkout. GitHub metadata was used to screen public projects by ownership, recent activity, adoption signals, and relevance. A focused read covered LatticeStripe, ExifCleaner Electron, Threadline, Sigra, Rendro, Rulestead, MetaPresenter, and Upgrow. LatticeStripe and ExifCleaner were included at the owner's direction; Threadline, Sigra, and Rendro provide active Phoenix/BEAM delivery examples; Rulestead provides useful dependency-automation examples and counterexamples.

The rest of the portfolio received a discovery-level workflow-marker scan, not a line-by-line audit. Pattern counts only located candidates; a marker such as `continue-on-error`, `--admin`, or `if: always()` is not itself a finding. ExifCleaner, LatticeStripe, Threadline, Rendro, and Rulestead workflow files were clean in their local worktrees during review. Sigra's local workflow had a cache-version change; its HEAD retained the aggregate gate. Keepling and Crosswake worktrees had workflow edits, so their local working copies were not treated as pristine evidence.

GitHub configuration is external state. For Keepling, live `main` protection was inspected separately from YAML and changed on 2026-10-01. After PR #4, the required contexts are the stable repository, desktop, and iOS workflow summaries listed below. The protected deployment environment was also checked: its custom branch allow-list contains only `main`; its required reviewer is the repository owner, with self-review allowed; and it contains zero secrets. The follow-up preflight inspected only secret names/count, never values.

## Reference projects

| Project | Why it was reviewed | Transferable evidence | Limits |
|---|---|---|---|
| [ExifCleaner](https://github.com/szTheory/exifcleaner) | Widely adopted Electron app; 2,717 stars and 167 forks at review time | [CI workflow](https://github.com/szTheory/exifcleaner/blob/master/.github/workflows/ci.yml): PR and main CI, immutable Action pins, read-only token permissions, bounded/cancellable jobs, platform package smoke checks, one build artifact reused by downstream checks, exact source-SHA release gating, published-artifact verification | Its laptop release steps and platform-specific signing setup are not Keepling requirements. |
| [LatticeStripe](https://github.com/szTheory/lattice_stripe) | Owner-selected, production-oriented Elixir SDK | [CI workflow](https://github.com/szTheory/lattice_stripe/blob/main/.github/workflows/ci.yml): stable aggregate gate, exact commit checks before merge/publish, narrow CI permissions, a local `mix ci` contract, and release checks tied to the exact tag/SHA | Its Hex package release machinery solves a library-publishing problem; Keepling should reuse the invariants, not the workflow's full complexity. |
| [Threadline](https://github.com/szTheory/threadline) | Active Phoenix project with repository-owned merge policy | [Committed `main` ruleset](https://github.com/szTheory/threadline/blob/main/.github/rulesets/main.json) requires a PR and one stable `CI required` check; the [CI workflow](https://github.com/szTheory/threadline/blob/main/.github/workflows/ci.yml) uses `if: always()` and fails when any required lane does not succeed. [Branch protection](https://github.com/szTheory/threadline/blob/main/.github/workflows/branch-protection.yml) and [environment protection](https://github.com/szTheory/threadline/blob/main/.github/workflows/environment-protection.yml) workflows watch external settings. | Its larger compatibility matrix and release workflow are only useful if Keepling's support promises justify their runtime. |
| [Sigra](https://github.com/szTheory/sigra) | Active Phoenix authentication package | [CI workflow](https://github.com/szTheory/sigra/blob/main/.github/workflows/ci.yml) has a stable `ci-gate`; [release workflow](https://github.com/szTheory/sigra/blob/main/.github/workflows/release-please.yml) waits for the exact source revision's gate | Release Please and Hex publishing are package-specific. |
| [Rendro](https://github.com/szTheory/rendro) | Active Elixir document-generation package | [Release workflow](https://github.com/szTheory/rendro/blob/main/.github/workflows/release.yml) validates version/tag agreement and runs `mix ci` and release preflight before publishing through a protected environment | Its advisory security lane illustrates why the aggregate's dependency list must be checked directly. |
| [Rulestead](https://github.com/szTheory/rulestead) | Active feature-flag package with useful dependency automation examples | [Dependabot configuration](https://github.com/szTheory/rulestead/blob/main/.github/dependabot.yml) groups recurring updates; narrowly scoped bot auto-merge can reduce maintenance when required checks remain enforced | Its [release auto-merge](https://github.com/szTheory/rulestead/blob/main/.github/workflows/release-pr-automerge.yml) has an `--admin` fallback that can bypass protections; its [dependency-review workflow](https://github.com/szTheory/rulestead/blob/main/.github/workflows/dependency-review.yml) can continue after an unsupported-plan failure. Do not copy those controls. |

### Screened as contrast

- [MetaPresenter](https://github.com/szTheory/meta_presenter) is archived and retains a legacy Travis/manual release process. Its compatibility matrix may be useful; its release flow is not a current standard.
- [Upgrow](https://github.com/szTheory/upgrow) is labeled as a mirror and has stale inherited workflows. It is not treated as an owner-operated maturity reference.
- Crosswake, Rindle, Mailglass, Accrue, Oarlock, Chimeway, Relyra, Scoria, and other active first-party repositories remain portfolio candidates. Their workflow counts and marker signals were screened; this snapshot does not claim a deep audit of them.

## Cross-project decisions

This applies Keepling's existing automation-first verification policy to repository governance and delivery. The earlier policy prioritizes the narrowest reliable proof, recurring CI for distinct confidence, and human judgment only at boundaries automation cannot safely decide.

| Decision | Keepling recommendation | Reason and tradeoff |
|---|---|---|
| Merge to `main` | Require a PR and required CI checks, with no approval count for the solo maintainer. Keep admin enforcement, block force pushes/deletion, and require the branch to be current. | PRs provide a diff and check record while avoiding a self-approval rule that would stop a one-person project. Strict checks can cause reruns after another merge; Keepling's single-maintainer merge rate makes that tradeoff acceptable for now. |
| Required check shape | Keep check names stable and have each independently triggered workflow expose one fail-closed summary job. Avoid workflow-level path filters on required checks. | A skipped required workflow/job can be reported as successful, and a missing workflow-level check can leave a PR pending. One aggregate per workflow keeps GitHub settings small and lets lanes evolve. |
| CI on PRs | Keep ordinary PR work on `pull_request`, with `contents: read`, no production secrets, pinned Actions, bounded timeouts, and cancellation for superseded PR revisions. | This makes fork contributions safe and returns runner capacity when a new commit replaces an old one. Do not use `pull_request_target` to check out or execute contributor code. |
| Test breadth and cost | Keep the complete suite for code/workflow changes. Add a fail-closed docs-only fast path so prose/planning edits do not wait for platform integration jobs; unknown paths run the full suite. | The green PR #3 runs on 2026-09-30 took 67m41s for iOS simulator, 25m07s for desktop packaged evidence, and 3m33s for repository/Phase 2 evidence. Those ran concurrently, so iOS set the ~68-minute merge latency. Docs-only changes do not change those product boundaries. |
| Artifact identity | Build desktop artifacts once, test the downloaded bytes, and promote/publish the same digest. Tie release or deployment approval to the exact tested source SHA. | This prevents a successful test of one build from being used to approve different bytes. Keep version publication, production deployment, and PR merge as separate gates. |
| Secrets and live actions | Keep live provider credentials behind a trusted-`main` environment. Run cheap readiness checks before provider calls and report only missing symbolic secret names or policy state, never values. | CI can discover input/configuration failures before a billable or destructive step. GitHub's workflow token cannot safely reveal environment secret values; any external-state audit must use a separately controlled read-only credential or remain an operator-side preflight. |
| Tool and action maintenance | Keep exact runtime pins and frozen dependency installs. Automate pinned Action updates through grouped Dependabot PRs and let the normal checks decide whether to merge. | Immutable pins improve supply-chain review but create upkeep; automated PRs keep that maintenance visible and bounded. |
| Failure reporting | Required summaries must distinguish `success` from `failure`, `cancelled`, and `skipped`. Keep `continue-on-error` lanes out of required gates unless a named, expiring exception explains why. Retain failure logs/results as CI artifacts. | A green badge should mean every required lane actually ran and passed. Guard scripts should include negative-path self-tests where their purpose is to prevent a silent pass. |
| Automation level | Keep normal PR merge manual; consider auto-merge only for narrowly defined low-risk dependency updates after the merge policy is proven. Never use an admin-bypass fallback. | The maintainer sees the proposed diff and final merge record while still letting CI do the repeated verification. |

### Stakeholder lenses

| Lens | Finding that changed the recommendation |
|---|---|
| Solo maintainer | Require a PR and checks, with zero approvals, so the merge path creates an audit record without requiring an impossible second person. |
| Product and contributor experience | Keep check names stable and make a missing/failed lane legible; do not make contributors guess which of several unrelated workflows owns the red result. |
| CI/platform engineering | Aggregate each workflow with an always-run gate that rejects every result other than `success`; cancel stale PR jobs and preserve deploy serialization. |
| Security/supply chain | Keep fork PRs on `pull_request` with read-only permissions; pin Actions and gate live credentials behind trusted refs. Reject admin bypass and credentialed PR execution. |
| QA/reliability | Test distinct failure boundaries and the exact bytes users install; record failure artifacts and prove guard scripts reject known bad fixtures. |
| Operations/recovery | Move cheap environment/source readiness checks before provider calls; preserve explicit live authorization and prove restore/recovery on disposable data. |
| Release maintainer | Wait for the exact tag/source SHA's green gate, then verify the artifact users receive. Do not equate a green build with a verified published artifact. |
| Cost/performance | Keep current PR coverage until lane duration and defect-prevention value are measured; first reduce duplicate builds and setup overhead. |

## Keepling state and immediate adoption

On 2026-10-01, `main` already blocked force pushes and deletion and enforced branch protection for admins, but it did not require PRs or status checks. PR #3 had all relevant desktop, iOS, and repository checks green. PR #4 then made the branch rule require a pull request, an up-to-date branch, and these three stable summaries from the GitHub Actions app (ID 15368):

- `All required checks passed`
- `Desktop checks passed`
- `iOS simulator checks passed`

The rule requires zero reviewer approvals so Jon can merge his own PR after the checks pass. Admin enforcement and no-force-push/no-deletion settings remain enabled. This converts the intended PR discipline into an enforced GitHub rule; a direct push to `main` will be rejected.

PR #4 added always-run desktop and iOS summaries that account for their required jobs and fail closed when a lane is missing, skipped, cancelled, or failed. It also added a path classifier that takes the docs-only fast path only for explicitly recognized documentation paths; unknown paths run the full suite. Branch settings now require one stable context per workflow. Do not add a skipped-success shortcut to a summary.

The current Phase 2 protected Environment has a required reviewer (the repository owner, with self-review allowed), a custom policy limited to `main`, and zero secrets. The merge rule removes the source-on-trusted-main ambiguity; it does not provision provider authority. Before protected live acceptance, provide the required secrets through their approved external source. Keep values out of PR code and diagnostic output.

## Ranked Keepling actions

1. **Applied — protect `main` with PR + CI.** Require an up-to-date PR branch and the three fail-closed GitHub Actions summaries, preserve admin enforcement and no-force-push/no-delete, and require zero approvals. Verify this after workflow renames or splits.
2. **Next — make live-operation readiness cheap and explicit.** Run a local, authenticated, read-only preflight before the protected workflow can be dispatched. It checks the trusted `main` policy, required reviewer, and symbolic secret-name inventory; it never reads values or performs a mutation. The protected environment currently has zero secrets, so acceptance remains blocked until values are provisioned through approved sources. Keep fresh exact-run owner authorization as a separate gate.
3. **Keep full evidence for code changes.** Reuse existing package artifacts and dependency caches; move a platform/recovery lane to a less frequent trigger only when a distinct proof remains at merge time and evidence supports the change.
4. **Automate upkeep — create grouped Dependabot PRs for Actions and dependencies.** Let required CI decide merge eligibility. Consider narrowly scoped auto-merge only after the rule has been exercised; never grant an admin bypass.
5. **Make policy inspectable.** Threadline keeps a branch ruleset as JSON in the repository and runs a separate scheduled/post-CI verifier for branch and environment settings. Keepling's current rule is classic branch protection, which is not yet represented as a repository-owned ruleset. Migrate it to a committed ruleset contract with an independent verifier; during migration, compare both live policies and remove the duplicate only after the ruleset is verified. Do not put a repository-admin PAT into ordinary PR CI. The Actions token cannot enumerate environment secrets, so keep secret availability checks at a protected job boundary or through an operator-side preflight.

### One-shot recommendation

Keep `main` as the only integration branch. Every change enters through a PR. A small set of stable, fail-closed workflow summaries must be green on the exact, up-to-date PR revision before Jon merges it. A tested docs-only classifier may skip desktop and iOS integration work; source, workflow, lockfile, and unclassified changes continue to run the full suite. PR workflows receive read-only permissions and no production credentials. Keep a committed ruleset contract and a separate live-configuration verifier. The protected live workflow starts only from trusted `main`, checks its symbolic inputs before provider calls, and uses its separate reviewer/environment gate. Release and deployment promote the exact tested source and artifact. Optimize runner minutes by removing duplicate setup/build work and preserving every proof the changed code needs.

## Official GitHub guidance

- [Rulesets overview](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets)
- [Ruleset rules](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets)
- [Protected branches and required checks](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)
- [REST API for branch protection](https://docs.github.com/en/rest/branches/branch-protection)
- [Safely using `pull_request_target`](https://docs.github.com/en/actions/reference/security/securely-using-pull_request_target)
- [Workflow token permissions](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)
- [Deployment environments and protection rules](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments)
- [Workflow concurrency](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency)
- [Workflow artifacts](https://docs.github.com/en/actions/concepts/workflows-and-actions/workflow-artifacts)

GitHub guidance and external settings can change. Recheck the relevant official documentation before changing these rules or adopting a new deployment mechanism.
