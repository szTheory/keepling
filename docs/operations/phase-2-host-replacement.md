# Phase 2 host-replacement setup

This is the one external-account setup batch for the final Hetzner replacement rehearsal. It deliberately creates no resources by itself and does not prove backup or restore health.

## Developer image-verification loop

On Apple Silicon, use the local Docker engine's native ARM64 image for the fast
inner loop:

```sh
buildx_config=$(mktemp -d "${TMPDIR:-/tmp}/keepling-buildx.XXXXXX")
chmod 700 "$buildx_config"
BUILDX_CONFIG="$buildx_config" KEEPLING_IMAGE_PLATFORM=linux/arm64 \
  ./tooling/test-phase-2.sh --lane image-compose-deploy
```

This checks local image build, Compose, readiness, and deployment behavior. A
pass is development feedback for that source tree; it does not prove the
`linux/amd64` image or close Plan 02-20 Gate B. In particular, do not treat an
Apple Silicon x86 emulator or VM as native x86 evidence. The private Buildx
config keeps builder metadata writes outside the repository and avoids the
Docker Desktop default-config permission failure seen on this host.

The pull-request `image-compose-deploy` job in
`.github/workflows/repository-integrity.yml` uses a standard GitHub-hosted
`ubuntu-24.04` x86_64 runner and sets `KEEPLING_IMAGE_PLATFORM=linux/amd64`.
That is the preferred target-architecture lane; no maintained local x86 VM or
persistent self-hosted runner is needed. Its current build/Compose/deploy pass
does not by itself close Gate B because it does not export and reload the final
archive or prove recovery from the exact deployed image.

For Gate B, one future source-owned x64 job must bind a single checked-out
revision through one image build, final archive export, removal and reload,
archive identity validation, deployment using the reloaded image, and matching
synthetic capture and restore. Keep the archive, dump, rehearsal credential,
and raw logs in runner temporary storage; upload only a privacy-checked,
sanitized result. Do not give this job provider, SSH, remote-backup, DNS, or
teardown credentials. This synthetic CI proof remains separate from live host
replacement acceptance.

## Current host-trust gate (2026-09-27)

Plan 02-17's one authorized run is consumed and NON_PASSING. The supplied
Hetzner console fingerprint did not match the candidate's SSH ED25519 key;
SSH, restore, and DNS were not reached. Exact-owned teardown passed and provider
absence was proven. The cause of the mismatch is unresolved. Do not reuse the
run, candidate, or its authorization, and do not retry with another transcription
or a repeated console read. The banner's repeat handling is now deterministic,
but that does not explain the earlier mismatch.

Any later live attempt requires a separate reviewed plan and a fresh explicit
owner checkpoint naming its exact run, tested source/image/recovery bundle,
provider and billable apply, independent host-trust approval and SSH, synthetic
credentialed restore, run-owned DNS actions, and exact-owned teardown. Before
that plan can propose a run, the owner must identify the exact candidate in the
independent Hetzner console and establish through independently reviewed
provenance that the displayed fingerprint is the current ED25519 key served by
that candidate. A matching string or a second transcription alone is not this
provenance. This document does not authorize or start another external attempt.

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

## Plan 02-19 live attempt (2026-09-28)

The separately authorized single attempt is consumed and NON_PASSING. The
credentialed lane passed runner readiness but refused at bootstrap because the
pinned OpenTofu executable was unavailable in the invocation environment; it
stopped before provider apply. Exact run-labeled post-attempt queries found no
server, volume, primary IP, network, firewall, or SSH key. Automatic cleanup
recorded `NO_RESOURCE`; there was nothing to destroy. Candidate-console trust,
SSH, restore and epoch, candidate runtime, semantic proof, RPO/RTO, and DNS
cutover/rollback/deletion were not reached. Do not retry this run or reuse its
authorization. Any new attempt requires a separately reviewed run and fresh
approval, with the pinned OpenTofu executable and provider plugin directory
available to that execution environment. DATA-03, OPS-02, and OPS-03 remain
open.

## Plan 02-20 preparation disposition (2026-09-29)

The same-invocation host-trust continuation was superseded by the explicit
pause, separate resume, and abort checkpoint retained in this branch. This
follow-on adds the pinned OpenTofu/provider preflight and its sanitized local
regression; that regression passes without making provider, SSH, or DNS calls.
Plan 02-20 remains `NOT_STARTED` / `NON_PASSING` for live acceptance: no fresh
run or private bundle was prepared, no approval was requested, and no live
provider, SSH, restore, or DNS action occurred. DATA-03, OPS-02, and OPS-03
remain open. Do not treat the earlier artifact or any consumed run approval as
authority for a future attempt.

## Protected hosted input contract (Plan 02-28)

The protected workflow accepts four required dispatch fields: `authorization_json`, `authorization_sha256`, `hosted_inputs_json`, and `hosted_inputs_sha256`. Compute each SHA-256 over the exact UTF-8 bytes entered, with no newline added. `authorization_json.hosted_inputs_sha256` must equal the hosted-input digest; its selection must also agree with the closed input object. Any edit after review requires a fresh authorization. The job runs only from `main` after the `phase-2-protected-environment` reviewer gate.

The closed hosted object contains `version: 1`, `dns_zone_id`, `dns_record_name`, sorted canonical `admin_source_cidrs`, string `server_image_id`, `candidate_source: "rebuilt-archive"`, `recovery_source: "same-run-synthetic-capture"`, `login_source: "same-run-synthetic-capture"`, and explicit `b2_primary_endpoint`, `b2_primary_region`, and `b2_primary_bucket`. The authorization separately pins the measured `nbg1` / `cx33` / 160 GB choice and matching server image, exact source/archive identities, SSH-agent public-key digest, actor, run, attempt, freshness window, and full action-class list.

Configure these environment secrets before requesting a run: `HCLOUD_TOKEN`, `CLOUDFLARE_API_TOKEN`, `KEEPLING_BACKUP_PRIMARY_ACCESS_KEY`, `KEEPLING_BACKUP_PRIMARY_SECRET_KEY`, `KEEPLING_BACKUP_MIRROR_ACCESS_KEY`, `KEEPLING_BACKUP_MIRROR_SECRET_KEY`, `KEEPLING_BACKUP_MIRROR_ENDPOINT`, `KEEPLING_BACKUP_MIRROR_REGION`, `KEEPLING_BACKUP_MIRROR_BUCKET`, `KEEPLING_TOFU_STATE_ACCESS_KEY`, `KEEPLING_TOFU_STATE_SECRET_KEY`, `KEEPLING_TOFU_STATE_ENDPOINT`, `KEEPLING_TOFU_STATE_REGION`, `KEEPLING_TOFU_STATE_BUCKET`, `KEEPLING_BACKUP_CIPHER_PASSPHRASE`, and the disposable-run `KEEPLING_SSH_PRIVATE_KEY`. Never put secret values in dispatch inputs. The runner starts one private agent after authorization, requires exactly one ED25519 identity matching the authorized fingerprint, and writes only its public identity to the private setup directory.

The materializer creates an external mode-0700 directory with five mode-0600 provider credential JSON files, `replacement-run.pub`, `backup-cipher.key`, and the exact seven-line `env.sh` consumed by setup. The same job binds candidate selection to its rebuilt archive, generates and validates a synthetic deploy/recovery capture, and prepares the orchestration bundle. Diagnostics remain private and are deleted by the same-job cleanup trap. Uploaded status is sanitized and emitted only after private cleanup; refusal status contains a bounded reason and does not include secret values, raw identifiers, or private paths. Local fixture success is preparation evidence only. DATA-03, OPS-02, and OPS-03 remain non-passing pending Plans 02-25 through 02-27 and their human-gated live evidence.

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
not prove a live rehearsal and does not satisfy the separate-plan and fresh
exact-run authorization gate above. The credentialed entry point additionally
requires a numeric passing restore benchmark; it cannot report success without
executing the full bootstrap-through-teardown chain.

## CI-tested candidate image

The `image-compose-deploy` job publishes the `phase2-verified-image` artifact
only after the exact image, Compose, and deploy lane passes. It contains the
OCI/Docker archive, its machine-verified contract, and a run-binding record
with the workflow run/attempt, source revision, archive SHA-256, and OCI
manifest digest. The build fails closed unless the checked-out source equals
`GITHUB_SHA`, and the exported image contract names that same revision.

For the later local preparation, use only this artifact from the exact
completed-success workflow run and attempt. The matching image lane must also
have passed. Do not substitute `image-compose-deploy-timing` or an archive from
another run. Download and revalidate the artifact outside the checkout:

```sh
image_dir=$(mktemp -d /private/tmp/phase2-ci-image.XXXXXX)
chmod 700 "$image_dir"
gh run download "$run_id" --repo szTheory/keepling \
  --name phase2-verified-image --dir "$image_dir"
chmod 600 "$image_dir"/*
attempt=$(jq -r .run_attempt "$image_dir/run-binding.json")
gh api "repos/szTheory/keepling/actions/runs/$run_id" | \
  jq -e --arg run_id "$run_id" --arg attempt "$attempt" \
    '(.id|tostring) == $run_id and (.run_attempt|tostring) == $attempt and .status == "completed" and .conclusion == "success" and .name == "Repository integrity and Phase 2 evidence"' >/dev/null
./tooling/verify-host-replacement.sh --resolve-image-archive \
  "$image_dir/keepling-server-amd64.tar.gz" "$image_dir/local-image-contract.json"
jq -e --arg run_id "$run_id" --arg attempt "$attempt" \
  --slurpfile ci "$image_dir/image-contract.json" \
  --slurpfile binding "$image_dir/run-binding.json" \
  '.revision == $ci[0].revision and .revision == $binding[0].source_revision and
   .archive_sha256 == $ci[0].archive_sha256 and .archive_sha256 == $binding[0].archive_sha256 and
   .manifest_digest == $ci[0].manifest_digest and .manifest_digest == $binding[0].image_manifest_digest and
   $ci[0].version == 2 and $binding[0].version == 1 and
   ($binding[0] | keys | sort) == ["archive_sha256","image_manifest_digest","run_attempt","run_id","source_revision","version"] and
   ($binding[0].source_revision | test("^[0-9a-f]{40}$")) and
   $binding[0].run_id == $run_id and $binding[0].run_attempt == $attempt' \
  "$image_dir/local-image-contract.json" >/dev/null
jq --arg archive "$image_dir/keepling-server-amd64.tar.gz" \
  '. + {image_archive:$archive,version:1}' "$image_dir/image-contract.json" \
  > "$image_dir/candidate-selection.json"
chmod 600 "$image_dir/candidate-selection.json"
```

The resulting candidate selection is run-bound, archive-verified, and already
shaped for `phase-2-live-setup.sh`. Keep the directory private and outside the
repository. This read-only artifact step is still not provider/DNS approval.

## Sanitized OpenTofu and provider inputs

The live lane requires explicit absolute `TOFU_BIN` and
`HCLOUD_PROVIDER_PLUGIN_DIR` values. Every sanitized child must forward both
values; neither may fall back to `PATH` or a global provider cache. The
source-owned entry runs `--toolchain-preflight` before it reports
`LIVE_ACCEPTANCE_STATUS=ATTEMPTED`, and the credentialed command repeats that
local gate before provider access. It checks OpenTofu 1.12.6, agreement between
the tracked provider constraint and lockfile, and an executable hcloud plugin
from the locked version. This check makes no provider, SSH, or DNS calls.

Use this same read-only check inside the sanitized environment that will start
the live lane:

```sh
env -i PATH="$PATH" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" \
  TOFU_BIN='/absolute/path/to/tofu' \
  HCLOUD_PROVIDER_PLUGIN_DIR='/absolute/path/to/pinned/hcloud/plugins' \
  ./tooling/verify-host-replacement.sh --toolchain-preflight
```

`phase-2-live-setup.sh` explicitly forwards these variables through `env -i`;
the required `opentofu-host-fixtures` lane also tests the positive delivery and
the absent, relative, symlinked, non-executable, and wrong-version refusals in
a sanitized child.

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

Only execute this example after the separate reviewed plan and fresh exact-run
authorization described above. The command automates until the new VM's SSH
identity needs independent verification. It then exits with status `75`,
preserving the candidate and a private run-bound checkpoint. Cloud-init prints
the SHA256 fingerprint on the Hetzner VNC console login screen. Establish that
the banner belongs to the exact candidate and its current ED25519 key under the
reviewed trust-provenance procedure; do not log in to the VM or run a command
there.

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

If sequence cleanup fails during read-only ownership/state preflight, first
restore access to the private provider and state credentials, then run the
same-run recovery path with billable and exact-destroy approval:

```sh
KEEPLING_ALLOW_BILLABLE_APPLY=yes \
KEEPLING_ALLOW_PROVIDER_DESTROY=yes \
KEEPLING_LIVE_CHANGE_TRIGGER='approved-recovery-name' \
KEEPLING_LIVE_ORCHESTRATION_FILE='/private/keepling/phase-2/<run>/orchestration.env' \
  ./tooling/phase-2-live-orchestration.sh recover-teardown
```

This path re-reads exact ownership and state and cannot provision a candidate
or reach DNS. It refuses once `.teardown-destroy-started` exists or teardown
evidence has been written. OpenTofu initialization diagnostics stay in the
mode-0600 private workspace. Do not delete a fence or retry after destructive
start; preserve the workspace for a separately reviewed recovery.

Plan 02-09, DATA-03, and OPS-02 remain open. Materialized credentials, a safe
setup result, and read-only provider preflight are preparation evidence only;
none proves replacement, rollback, backup health, or restore health.
