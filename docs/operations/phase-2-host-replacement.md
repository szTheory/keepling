# Phase 2 host-replacement setup

This is the one external-account setup batch for the final Hetzner replacement rehearsal. It deliberately creates no resources by itself and does not prove backup or restore health.

## Isolated synthetic rehearsal

The approved KPL-02 cloud rehearsal uses only a fresh synthetic database made
by `verify-deploy.sh --local`. Its private provenance is explicitly
`synthetic-rehearsal`; it must never be presented as a B2/R2 restore or proof
that Jon's personal data is recoverable. Real backup recovery remains an open
acceptance item until the supported encrypted source package is proven.

The run derives a unique hostname under the configured DNS name. After restore,
readiness, and semantic checks pass, DNS automation creates only that new A
record at a reserved sentinel address, points it to the candidate, checks
propagation and HTTPS readiness, restores the sentinel, verifies rollback,
then deletes and verifies absence of that exact run-owned record. It does not
edit the existing configured A record. The cloud replacement is manual-only;
daily and weekly disposable backup restore checks remain in CI.

## Local secret boundary

Keep all five JSON documents and two separate key files outside the checkout, for example in `~/.config/keepling/phase-2/`, mode `0600` (directories `0700`). Copy the non-secret shapes from `infra/credentials/templates/`; never copy a completed document into the repository.

Create an ignored local `.envrc` containing only:

```sh
source_env ~/.config/keepling/phase-2/env.sh
```

### Automated local preparation

All secret material already has a Keepling-owned 1Password item. The setup
command reads those items directly into external `0600` files; it never prints
their values, writes into the checkout, creates provider resources, or changes
DNS. First run its read-only check:

```sh
./tooling/materialize-phase-2-credentials.sh --check
```

It will ask for only one non-secret selection: an existing SSH public-key path.
The B2 application key is bucket-scoped, and the Cloudflare token has exactly
one accessible zone and one A record, so the command derives those targets too.
It fails closed if either account becomes ambiguous. With the key path supplied,
create the complete external boundary:

```sh
./tooling/materialize-phase-2-credentials.sh --write \
  --ssh-public-key "$HOME/.ssh/<key>.pub"
```

The command derives the B2 S3 endpoint and region from Backblaze rather than
asking you to copy them. It also uses the fixed, validated OpenTofu state key
`keepling/phase-2/terraform.tfstate` and refuses ambiguous or existing output
paths. Afterwards, do not source `env.sh` through `.envrc`, `direnv`, or a
shell. It is closed data for the safe setup command below; no credential path
needs to enter the general shell environment.

The materializer creates `env.sh` for the automated path. For a manual recovery
path, copy `.env.example` to that external location and replace only its paths.
It exports references, never token values. Verify local, non-networking setup
through the one safe command:

```sh
./tooling/phase-2-live-setup.sh check
```

It validates the external directory and exact seven-file schema, then runs the
credential/state/toolchain/dry-run checks in a constructed child environment.
It never prints secret values or private paths. Its normal result intentionally
exits **3**: live acceptance remains non-passing. It reports only these symbolic,
operator-owned categories: `ssh-agent-authority`,
`candidate-recovery-selection`, `live-change-trigger`,
`billable-apply-approval`, `dns-mutation-approval`, and
`exact-owned-destroy-approval`. Materialized credentials, repository adapters,
generated run identity/workspace, and read-only provider responses are derived
inputs, not further operator work.

Request provider/DNS reads separately and explicitly:

```sh
./tooling/phase-2-live-setup.sh preflight
```

This also exits 3 after the read-only preflight. It clears inherited live
approvals, change triggers, provider tokens, and sequence-runner values before
calling only `verify-host-replacement.sh --credentialed --preflight`; it cannot
invoke credentialed apply. The credential doctor reports only structural facts,
rejects every credential or key path under the checkout, and does not print
document contents.

## Required external accounts and policies

- Hetzner JSON: a least-privilege project token for the dedicated empty rehearsal project.
- Cloudflare DNS JSON: a token restricted to read/edit of the selected rehearsal record and its zone.
- B2 primary JSON: the encrypted pgBackRest repository. Enable B2 encryption, versioning, and a 14-day compliance Object Lock/default retention policy compatible with the backup schedule.
- R2 mirror JSON: a different Cloudflare account and bucket. Apply an append-only Bucket Lock policy for dated `snapshots/` objects. The mirror is not a mutable pgBackRest repository.
- B2 OpenTofu-state JSON: a third, dedicated bucket and state key. Enable encryption, 90-day noncurrent-version retention, and 7-day cleanup for `.tflock` versions. Do not Object-Lock mutable state or lock objects.
- Keep the SSH public key and backup cipher key as separate readable files. The cipher key needs an independently recoverable copy; neither storage provider alone is sufficient.

## State backend procedure

The checked-in S3 backend enables `encrypt` and `use_lockfile`. When the external policy is ready, generate a private backend-config file outside the checkout:

```sh
state_config=$(mktemp "${TMPDIR:-/tmp}/keepling-tofu-state.XXXXXX")
./tooling/phase-2-tofu-state.sh render-init-config "$state_config"
TF_DATA_DIR=$(mktemp -d "${TMPDIR:-/tmp}/keepling-tofu-data.XXXXXX") \
  ./tooling/phase-2-tofu-state.sh with-state-env \
    "$TOFU_BIN" -chdir=infra/tofu/hetzner init -reconfigure -backend-config="$state_config"
rm -f "$state_config"
```

OpenTofu may retain backend configuration in its data directory, so keep `TF_DATA_DIR` private and discard it after the controlled run. A later credentialed state self-test must use a uniquely owned temporary state key and clean up only that key and its lock versions.

## Final arm gate

`--credentialed --preflight` may read provider metadata and the safe DNS baseline but does not provision or mutate DNS. The actual rehearsal remains sealed until an operator supplies both explicit billable and DNS-mutation approvals plus a named change trigger. Do not treat this document, credential presence, or a local doctor pass as live-rehearsal evidence.

Before a credentialed rehearsal, run the one safe readiness command. It never
contacts a provider or changes DNS; it verifies the same three arm inputs the
credentialed entry point will require and reports every source lifecycle
contract that must be executable:

```sh
KEEPLING_LIVE_CHANGE_TRIGGER='approved-change-name' \
KEEPLING_ALLOW_BILLABLE_APPLY=yes \
KEEPLING_ALLOW_LIVE_DNS_MUTATION=yes \
  ./tooling/verify-host-replacement.sh --live-readiness
```

The command passes only when all eight source contracts and all seven concrete
sequence-runner paths are executable, including bounded authoritative/recursive
DNS propagation plus rollback and exact-owned provider teardown. It still does
not prove a live rehearsal. The credentialed entry point additionally requires
a numeric passing restore benchmark; it cannot report success without executing
the full bootstrap-through-teardown chain.

## Private orchestration bundle

Do not copy or hand-author an orchestration file. Once the materialized
boundary exists, select one exact immutable candidate document and one exact
verified recovery document (both external regular `0600` JSON files), ensure
the materialized public identity is loaded in the local SSH agent, and provide a
private empty `known_hosts` file for the new run, then run:

```sh
SSH_AUTH_SOCK="$SSH_AUTH_SOCK" \
  ./tooling/phase-2-live-setup.sh \
    --candidate-selection /private/keepling/phase-2/candidate-selection.json \
    --recovery-selection /private/keepling/phase-2/recovery-selection.json \
    prepare
```

Preparation validates the OCI archive/config/manifest/revision/architecture/
rootfs contract and one recovery provider, dump, provenance hash, and size. It
requires exactly one matching public identity from `SSH_AUTH_SOCK`; no private
key path is requested or stored. It generates a fresh external `0700` run
directory, a future (not-yet-created) workspace, strict-host-key file, all
credential references, run identity, and seven exact repository-owned runners.
The resulting closed `0600` file has no command fields and no approval values.
The command only performs local validation, returns exit 3, and does not prove
replacement, rollback, backup health, or restore health.

Only after the explicit read-only setup preflight, a reviewed passing restore
benchmark, and an explicit single-attempt approval may the same shell run the
armed command below. It creates billable provider resources and performs the
bounded DNS rollback rehearsal through the private adapter commands; it is not
a claim that live acceptance has passed.

```sh
KEEPLING_ALLOW_BILLABLE_APPLY=yes \
KEEPLING_ALLOW_LIVE_DNS_MUTATION=yes \
KEEPLING_ALLOW_PROVIDER_DESTROY=yes \
KEEPLING_LIVE_CHANGE_TRIGGER='approved-change-name' \
KEEPLING_LIVE_ORCHESTRATION_FILE='/private/keepling/phase-2/<run>/orchestration.env' \
  ./tooling/verify-host-replacement.sh --credentialed
```

The command automates until the new VM's SSH identity needs independent
verification. It then exits with status `75`, preserving the candidate and a
private run-bound checkpoint. Cloud-init prints the SHA256 fingerprint on the
Hetzner VNC console login screen. Read or copy that banner value; do not log in
to the VM or run a command there.

Re-run the same armed command with `--resume-host-trust`:

```sh
KEEPLING_ALLOW_BILLABLE_APPLY=yes \
KEEPLING_ALLOW_LIVE_DNS_MUTATION=yes \
KEEPLING_ALLOW_PROVIDER_DESTROY=yes \
KEEPLING_LIVE_CHANGE_TRIGGER='approved-change-name' \
KEEPLING_LIVE_ORCHESTRATION_FILE='/private/keepling/phase-2/<run>/orchestration.env' \
  ./tooling/verify-host-replacement.sh --credentialed --resume-host-trust
```

The resume prompt asks for the console fingerprint and compares it with the
ED25519 key collected from the candidate's address. The resume stage pins the
verified key itself; do not pre-pin it with `pin-verified-ssh-host-key.sh`.
A mismatch, changed provider identity, or ambiguous scan fails closed and
attempts exact-owned teardown. The verified known-hosts file is write-once for
the run and its digest is checked before later SSH stages. `ssh-keyscan` only
supplies a candidate key; it never establishes trust alone.

To abandon a valid paused run, use the same approvals and bundle with
`--credentialed --abort-host-trust`; this invokes the existing exact-owned
teardown adapter. DNS is unreachable until local semantic proof succeeds.
Sequence-exit cleanup calls exact-owned teardown once, and the bundle rejects a
second teardown attempt for the same workspace. Keep generated evidence in the
private workspace; do not commit it or any private configuration path. Local
fixtures prove dispatch refusal and mocked ordering only; they do not prove a
replacement, restore, DNS rehearsal, or cleanup.

Plan 02-09, DATA-03, and OPS-02 remain open. Materialized credentials, a safe
setup result, and read-only provider preflight are preparation evidence only;
none proves replacement, rollback, backup health, or restore health.
