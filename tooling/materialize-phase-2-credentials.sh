#!/usr/bin/env sh
# Create Phase 2's external-only credential files from the Keepling 1Password
# items. This command never provisions infrastructure or mutates DNS.
set -eu

repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
op_bin=${OP_BIN:-op}
curl_bin=${CURL_BIN:-curl}
target_dir="$HOME/.config/keepling/phase-2"
dns_zone_id=""
dns_record_name=""
ssh_public_key=""
mode=check

usage() {
  cat <<'USAGE'
usage: tooling/materialize-phase-2-credentials.sh [--check|--write] [options]

--dns-zone-id ID            Override the automatically resolved Cloudflare zone
--dns-record-name NAME      Override the automatically resolved rehearsal A record
--ssh-public-key PATH       Existing public key to attach to the disposable host
--directory PATH            External target directory (default: ~/.config/keepling/phase-2)

--check verifies 1Password sources and reports missing non-secret selections.
--write requires every option, creates external 0600 credential files and env.sh,
and refuses to overwrite existing files.
USAGE
}

die() { printf '%s\n' "phase-2-materialize: $*" >&2; exit 1; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) mode=check ;;
    --write) mode=write ;;
    --dns-zone-id|--dns-record-name|--ssh-public-key|--directory)
      [ "$#" -ge 2 ] || die "$1 requires a value"
      case "$1" in
        --dns-zone-id) dns_zone_id=$2 ;;
        --dns-record-name) dns_record_name=$2 ;;
        --ssh-public-key) ssh_public_key=$2 ;;
        --directory) target_dir=$2 ;;
      esac
      shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

command -v "$op_bin" >/dev/null 2>&1 || die "1Password CLI is unavailable"
command -v jq >/dev/null 2>&1 || die "jq is unavailable"
command -v "$curl_bin" >/dev/null 2>&1 || die "curl is unavailable"

# UUID references are intentionally stable names, never credentials. They are
# the same Keepling-owned records already declared in tooling/release-secrets.map.
read_op() { "$op_bin" read --no-newline "$1"; }
hetzner_ref='op://Personal/oi7dzaxhzlqtynnmdypmkzaa6y/token'
cloudflare_ref='op://Personal/n4aewxzk6kbcqlmwsoearpmcti/token'
b2_key_id_ref='op://Personal/pvdsx37purgqzwndrokc5pif4a/keyID'
b2_application_key_ref='op://Personal/pvdsx37purgqzwndrokc5pif4a/applicationKey'
r2_prefix='op://Personal/phsuyqlsbtm5x7yro5axoqugpm'
state_prefix='op://Personal/igukyq5cbhhyedbnnc6ss353ee'
cipher_ref='op://Personal/qeqfg3v7tpavtmsj7ifkln7sma/cipher_passphrase'

check_ref() {
  if read_op "$1" >/dev/null 2>&1; then
    printf 'available: %s\n' "$2"
  else
    die "cannot read required 1Password field: $2"
  fi
}

for pair in \
  "$hetzner_ref|Hetzner token" "$cloudflare_ref|Cloudflare API token" \
  "$b2_key_id_ref|B2 key ID" "$b2_application_key_ref|B2 application key" \
  "$r2_prefix/access_key_id|R2 access key" "$r2_prefix/secret_access_key|R2 secret key" \
  "$r2_prefix/endpoint|R2 endpoint" "$r2_prefix/bucket|R2 bucket" "$r2_prefix/region|R2 region" \
  "$state_prefix/access_key_id|OpenTofu state access key" "$state_prefix/secret_access_key|OpenTofu state secret key" \
  "$state_prefix/endpoint|OpenTofu state endpoint" "$state_prefix/bucket|OpenTofu state bucket" "$state_prefix/region|OpenTofu state region" \
  "$cipher_ref|backup cipher"; do
  reference=${pair%%|*}; label=${pair#*|}; check_ref "$reference" "$label"
done

# The DNS token is intentionally restricted to the rehearsal surface. Resolve
# its target only when there is exactly one accessible zone and one A record;
# any broader token fails closed rather than guessing a production record.
resolve_dns_target() {
  [ -n "$dns_zone_id" ] && [ -n "$dns_record_name" ] && return 0
  cf_token=$(read_op "$cloudflare_ref")
  zones=$(printf 'header = "Authorization: Bearer %s"\nurl = "https://api.cloudflare.com/client/v4/zones?per_page=50"\n' "$cf_token" | "$curl_bin" --silent --show-error --fail --config -) || die "Cloudflare zone discovery failed"
  zone_count=$(printf '%s' "$zones" | jq -er '.result | length') || die "Cloudflare returned an invalid zone response"
  [ "$zone_count" -eq 1 ] || die "Cloudflare discovery requires exactly one accessible zone; pass --dns-zone-id and --dns-record-name explicitly"
  discovered_zone=$(printf '%s' "$zones" | jq -er '.result[0].id')
  records=$(printf 'header = "Authorization: Bearer %s"\nurl = "https://api.cloudflare.com/client/v4/zones/%s/dns_records?type=A&per_page=100"\n' "$cf_token" "$discovered_zone" | "$curl_bin" --silent --show-error --fail --config -) || die "Cloudflare A-record discovery failed"
  record_count=$(printf '%s' "$records" | jq -er '.result | length') || die "Cloudflare returned an invalid DNS response"
  [ "$record_count" -eq 1 ] || die "Cloudflare discovery requires exactly one accessible A record; pass --dns-zone-id and --dns-record-name explicitly"
  dns_zone_id=${dns_zone_id:-$discovered_zone}
  dns_record_name=${dns_record_name:-$(printf '%s' "$records" | jq -er '.result[0].name')}
  unset cf_token zones zone_count discovered_zone records record_count
  printf '%s\n' 'derived: Cloudflare zone and rehearsal A record'
}
resolve_dns_target

missing=0
for pair in "--ssh-public-key|$ssh_public_key"; do
  option=${pair%%|*}; value=${pair#*|}
  if [ -z "$value" ]; then printf 'needed: %s\n' "$option"; missing=1; fi
done
if [ -n "$ssh_public_key" ] && [ ! -r "$ssh_public_key" ]; then die "--ssh-public-key is unreadable"; fi
[ "$missing" -eq 0 ] || exit 2

if [ "$mode" = check ]; then
  printf '%s\n' 'Phase 2 materialization is ready; re-run with --write and the same selections.'
  exit 0
fi

target_parent=$(CDPATH='' cd -P "$(dirname "$target_dir")" 2>/dev/null && pwd) || die "target parent does not exist"
target_dir=$target_parent/$(basename "$target_dir")
case "$target_dir" in "$repository_root"|"$repository_root"/*) die "target directory must remain outside the repository" ;; esac
mkdir -p "$target_dir"; chmod 700 "$target_dir"
for name in hetzner.json cloudflare-dns.json b2-primary.json r2-mirror.json b2-tofu-state.json replacement-run.pub backup-cipher.key env.sh; do
  [ ! -e "$target_dir/$name" ] || die "refusing to overwrite $target_dir/$name"
done

b2_key_id=$(read_op "$b2_key_id_ref")
b2_application_key=$(read_op "$b2_application_key_ref")
b2_authorization=$(printf 'user = "%s:%s"\nurl = "https://api.backblazeb2.com/b2api/v3/b2_authorize_account"\n' "$b2_key_id" "$b2_application_key" | "$curl_bin" --silent --show-error --fail --config - 2>/dev/null) || die "Backblaze rejected the primary application key"
b2_endpoint=$(printf '%s' "$b2_authorization" | jq -er '.apiInfo.storageApi.s3ApiUrl // .s3ApiUrl') || die "Backblaze did not return an S3 endpoint"
b2_region=$(printf '%s' "$b2_endpoint" | jq -Rer 'capture("https://s3\\.(?<region>[^.]+)\\.").region') || die "could not derive the B2 region"
b2_bucket=$(printf '%s' "$b2_authorization" | jq -er '.apiInfo.storageApi.bucketName // .allowed.bucketName') || die "Backblaze did not return the bucket scoped to the primary application key"

umask 077
temporary=$(mktemp -d "$target_dir/.materialize.XXXXXX")
cleanup() { rm -rf -- "$temporary"; }
trap cleanup EXIT HUP INT TERM
write_json() { jq -n "$@" >"$temporary/$1"; }

jq -n --arg token "$(read_op "$hetzner_ref")" '{version:1,token:$token}' >"$temporary/hetzner.json"
jq -n --arg token "$(read_op "$cloudflare_ref")" --arg zone "$dns_zone_id" --arg name "$dns_record_name" \
  '{version:1,api_token:$token,zone_id:$zone,record_name:$name}' >"$temporary/cloudflare-dns.json"
jq -n --arg endpoint "$b2_endpoint" --arg region "$b2_region" --arg bucket "$b2_bucket" --arg access "$b2_key_id" --arg secret "$b2_application_key" \
  '{version:1,endpoint:$endpoint,region:$region,bucket:$bucket,access_key_id:$access,secret_access_key:$secret}' >"$temporary/b2-primary.json"
for kind in r2-mirror b2-tofu-state; do
  prefix=$r2_prefix; [ "$kind" = b2-tofu-state ] && prefix=$state_prefix
  jq -n --arg endpoint "$(read_op "$prefix/endpoint")" --arg region "$(read_op "$prefix/region")" --arg bucket "$(read_op "$prefix/bucket")" \
    --arg access "$(read_op "$prefix/access_key_id")" --arg secret "$(read_op "$prefix/secret_access_key")" \
    '{version:1,endpoint:$endpoint,region:$region,bucket:$bucket,access_key_id:$access,secret_access_key:$secret}' >"$temporary/$kind.json"
done
jq --arg key 'keepling/phase-2/terraform.tfstate' '. + {key:$key}' "$temporary/b2-tofu-state.json" >"$temporary/state.json"
mv "$temporary/state.json" "$temporary/b2-tofu-state.json"
cat "$ssh_public_key" >"$temporary/replacement-run.pub"
read_op "$cipher_ref" >"$temporary/backup-cipher.key"
cat >"$temporary/env.sh" <<EOF
export KEEPLING_HETZNER_CREDENTIAL_FILE="$target_dir/hetzner.json"
export KEEPLING_CLOUDFLARE_DNS_CREDENTIAL_FILE="$target_dir/cloudflare-dns.json"
export KEEPLING_BACKUP_PRIMARY_CREDENTIAL_FILE="$target_dir/b2-primary.json"
export KEEPLING_BACKUP_MIRROR_CREDENTIAL_FILE="$target_dir/r2-mirror.json"
export KEEPLING_TOFU_STATE_CREDENTIAL_FILE="$target_dir/b2-tofu-state.json"
export KEEPLING_SSH_PUBLIC_KEY_FILE="$target_dir/replacement-run.pub"
export KEEPLING_BACKUP_CIPHER_FILE="$target_dir/backup-cipher.key"
EOF
chmod 600 "$temporary"/*
for name in hetzner.json cloudflare-dns.json b2-primary.json r2-mirror.json b2-tofu-state.json replacement-run.pub backup-cipher.key env.sh; do mv "$temporary/$name" "$target_dir/$name"; done
rmdir "$temporary"; trap - EXIT HUP INT TERM

env KEEPLING_HETZNER_CREDENTIAL_FILE="$target_dir/hetzner.json" \
  KEEPLING_CLOUDFLARE_DNS_CREDENTIAL_FILE="$target_dir/cloudflare-dns.json" \
  KEEPLING_BACKUP_PRIMARY_CREDENTIAL_FILE="$target_dir/b2-primary.json" \
  KEEPLING_BACKUP_MIRROR_CREDENTIAL_FILE="$target_dir/r2-mirror.json" \
  KEEPLING_TOFU_STATE_CREDENTIAL_FILE="$target_dir/b2-tofu-state.json" \
  KEEPLING_SSH_PUBLIC_KEY_FILE="$target_dir/replacement-run.pub" \
  KEEPLING_BACKUP_CIPHER_FILE="$target_dir/backup-cipher.key" \
  "$repository_root/tooling/phase-2-credentials.sh" doctor >/dev/null
printf '%s\n' "Phase 2 credentials materialized outside the repository: $target_dir"
