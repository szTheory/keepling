#!/usr/bin/env sh
set -eu
root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
materializer=$root/tooling/materialize-phase-2-hosted-inputs.sh
fixture=$(mktemp -d "${TMPDIR:-/tmp}/keepling-hosted-inputs.XXXXXX")
chmod 700 "$fixture"
trap 'rm -rf -- "$fixture"' EXIT HUP INT TERM
inputs='{"version":1,"dns_zone_id":"fixture-zone","dns_record_name":"tasks.example.invalid","b2_primary_endpoint":"https://s3.us-west-004.backblazeb2.com","b2_primary_region":"us-west-004","b2_primary_bucket":"fixture-bucket","server_image_id":"12345","admin_source_cidrs":["192.0.2.10/32"],"candidate_source":"rebuilt-archive","recovery_source":"same-run-synthetic-capture","login_source":"same-run-synthetic-capture"}'
identity='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFixturePublicIdentity keepling-fixture'
target=$fixture/private
run_materializer() {
  env -i PATH="$PATH" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" \
    HCLOUD_TOKEN='fixture-hcloud-token-123456789' CLOUDFLARE_API_TOKEN='FixtureSentinelCloudflareToken' \
    KEEPLING_BACKUP_PRIMARY_ACCESS_KEY='FixturePrimaryAccess' KEEPLING_BACKUP_PRIMARY_SECRET_KEY='FixturePrimarySecret' \
    KEEPLING_HOSTED_B2_PRIMARY_ENDPOINT='https://s3.us-west-004.backblazeb2.com' \
    KEEPLING_HOSTED_B2_PRIMARY_REGION='us-west-004' KEEPLING_HOSTED_B2_PRIMARY_BUCKET='fixture-bucket' \
    KEEPLING_BACKUP_MIRROR_ACCESS_KEY='FixtureMirrorAccess' KEEPLING_BACKUP_MIRROR_SECRET_KEY='FixtureMirrorSecret' \
    KEEPLING_BACKUP_MIRROR_ENDPOINT='https://fixture.r2.example.invalid' KEEPLING_BACKUP_MIRROR_REGION='auto' KEEPLING_BACKUP_MIRROR_BUCKET='fixture-mirror' \
    KEEPLING_TOFU_STATE_ACCESS_KEY='FixtureStateAccess' KEEPLING_TOFU_STATE_SECRET_KEY='FixtureStateSecret' \
    KEEPLING_TOFU_STATE_ENDPOINT='https://fixture.state.example.invalid' KEEPLING_TOFU_STATE_REGION='us-east-1' KEEPLING_TOFU_STATE_BUCKET='fixture-state' \
    KEEPLING_BACKUP_CIPHER_PASSPHRASE='FixtureSentinelCipherValue' \
    sh "$materializer" --directory "$target" --inputs-json "$1" --ssh-public-identity "$identity"
}

if run_materializer "$inputs" >"$fixture/out" 2>"$fixture/err"; then
  test -x "$materializer" || { printf '%s\n' 'not ok - the hosted materializer must accept the exact clean-runner input contract'; exit 1; }
else
  cat "$fixture/out" "$fixture/err"
  printf '%s\n' 'not ok - the hosted materializer must accept the exact clean-runner input contract'
  exit 1
fi

[ "$(stat -f '%Lp' "$target" 2>/dev/null || stat -c '%a' "$target")" = 700 ] || { echo 'not ok - private directory mode'; exit 1; }
expected='export KEEPLING_HETZNER_CREDENTIAL_FILE="'"$target"'/hetzner.json"
export KEEPLING_CLOUDFLARE_DNS_CREDENTIAL_FILE="'"$target"'/cloudflare-dns.json"
export KEEPLING_BACKUP_PRIMARY_CREDENTIAL_FILE="'"$target"'/b2-primary.json"
export KEEPLING_BACKUP_MIRROR_CREDENTIAL_FILE="'"$target"'/r2-mirror.json"
export KEEPLING_TOFU_STATE_CREDENTIAL_FILE="'"$target"'/b2-tofu-state.json"
export KEEPLING_SSH_PUBLIC_KEY_FILE="'"$target"'/replacement-run.pub"
export KEEPLING_BACKUP_CIPHER_FILE="'"$target"'/backup-cipher.key"'
[ "$(cat "$target/env.sh")" = "$expected" ] || { echo 'not ok - exact seven-line environment manifest'; exit 1; }
[ "$(find "$target" -maxdepth 1 -type f | wc -l | tr -d ' ')" = 8 ] || { echo 'not ok - exact private file inventory'; exit 1; }
for f in "$target"/*; do [ ! -L "$f" ] && [ "$(stat -f '%Lp' "$f" 2>/dev/null || stat -c '%a' "$f")" = 600 ] || { echo 'not ok - private regular file mode'; exit 1; }; done
jq -e '(keys|sort)==["token","version"] and .version==1' "$target/hetzner.json" >/dev/null
jq -e '(keys|sort)==["api_token","record_name","version","zone_id"] and .zone_id=="fixture-zone" and .record_name=="tasks.example.invalid"' "$target/cloudflare-dns.json" >/dev/null
jq -e '(keys|sort)==["access_key_id","bucket","endpoint","region","secret_access_key","version"] and .endpoint=="https://s3.us-west-004.backblazeb2.com" and .region=="us-west-004" and .bucket=="fixture-bucket"' "$target/b2-primary.json" >/dev/null
jq -e '(keys|sort)==["access_key_id","bucket","endpoint","region","secret_access_key","version"] and .endpoint=="https://fixture.r2.example.invalid" and .bucket=="fixture-mirror"' "$target/r2-mirror.json" >/dev/null
jq -e '.key=="keepling/phase-2/terraform.tfstate"' "$target/b2-tofu-state.json" >/dev/null
[ "$(cat "$target/replacement-run.pub")" = "$identity" ] || { echo 'not ok - ssh public identity'; exit 1; }
if grep -E 'FixtureSentinel|FixturePrimary|FixtureMirror|FixtureState|fixture-hcloud-token' "$fixture/out" "$fixture/err" "$target/env.sh" "$target/replacement-run.pub"; then echo 'not ok - secret sentinel escaped'; exit 1; fi
printf '%s\n' 'ok - exact private hosted input bundle materialized with no secret output'

# Run the real setup checker in an isolated source mirror. Only its local
# toolchain and provider dry-run adapters are stubbed; credential/schema/path
# checks and code-3 non-passing status remain the production implementations.
mirror=$fixture/repo
mkdir -p "$mirror/tooling" "$fixture/bin" "$fixture/plugins"; chmod 700 "$mirror" "$mirror/tooling" "$fixture/bin" "$fixture/plugins"
for script in phase-2-live-setup.sh phase-2-credentials.sh phase-2-tofu-state.sh phase-2-toolchain-doctor.sh; do cp "$root/tooling/$script" "$mirror/tooling/$script"; done
cat >"$mirror/tooling/verify-host-replacement.sh" <<'SH'
#!/usr/bin/env sh
case "${1:-}" in --dry-run) exit 0;; --print-live-registry) printf '%s\n' 'phase2-registry status=fixture'; exit 0;; *) exit 1;; esac
SH
chmod 700 "$mirror/tooling/verify-host-replacement.sh"
printf '%s\n' '#!/usr/bin/env sh' 'if [ "${1:-}" = version ] && [ "${2:-}" = -json ]; then echo "{\"terraform_version\":\"1.12.6\"}"; elif [ "${1:-}" = version ]; then echo "OpenTofu v1.12.6"; else exit 0; fi' >"$fixture/bin/tofu"
printf '%s\n' '#!/usr/bin/env sh' 'if [ "${1:-}" = --version ]; then echo fixture-cloud-init-schema-1.0; else exit 0; fi' >"$fixture/bin/cloud-init-schema"
printf '%s\n' '#!/usr/bin/env sh' 'exit 0' >"$fixture/plugins/terraform-provider-hcloud_v1.68.0"
chmod 700 "$fixture/bin/tofu" "$fixture/bin/cloud-init-schema" "$fixture/plugins/terraform-provider-hcloud_v1.68.0"
set +e
env -i PATH="$fixture/bin:$PATH" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" TOFU_BIN="$fixture/bin/tofu" \
  CLOUD_INIT_SCHEMA_BIN="$fixture/bin/cloud-init-schema" CLOUD_INIT_SCHEMA_VERSION=fixture-cloud-init-schema-1.0 \
  HCLOUD_PROVIDER_PLUGIN_DIR="$fixture/plugins" \
  sh "$mirror/tooling/phase-2-live-setup.sh" --directory "$target" check >"$fixture/setup-out" 2>"$fixture/setup-err"
setup_status=$?
set -e
[ "$setup_status" -eq 3 ] || { printf 'not ok - existing setup checker returned code %s\n' "$setup_status"; cat "$fixture/setup-out" "$fixture/setup-err"; exit 1; }
grep -Fq 'phase2-live-setup status=local-check result=passed' "$fixture/setup-out" || { echo 'not ok - setup checker rejected materialized credentials'; exit 1; }
grep -Fq 'phase2-live-setup status=remaining-inputs result=required code=3' "$fixture/setup-out" || { echo 'not ok - setup checker lost documented remaining-inputs fence'; exit 1; }
! grep -E 'FixtureSentinel|FixturePrimary|FixtureMirror|FixtureState|fixture-hcloud-token' "$fixture/setup-out" "$fixture/setup-err" >/dev/null || { echo 'not ok - setup checker exposed fixture secret'; exit 1; }
printf '%s\n' 'ok - real setup checker accepts exact bundle and remains non-passing at code 3 with isolated pinned-tool fixtures'

rm -rf -- "$target"
invalid=${inputs%\}}',"unexpected":"value"}'
if run_materializer "$invalid" >"$fixture/out" 2>"$fixture/err"; then echo 'not ok - extra hosted input key must refuse'; exit 1; fi
[ ! -e "$target" ] || { echo 'not ok - invalid hosted inputs created private state'; exit 1; }
printf '%s\n' 'ok - extra hosted input key refused before private state'
