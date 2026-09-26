#!/usr/bin/env sh
set -eu
portable_stat() {
  format=$1; path=$2
  case "$(uname -s)" in
    Darwin) stat -f "$format" "$path" ;;
    *)
      case "$format" in
        %Lp) stat -c '%a' "$path" ;;
        %Su:%Sg) stat -c '%U:%G' "$path" ;;
        %u) stat -c '%u' "$path" ;;
        *) stat -c "$format" "$path" ;;
      esac ;;
  esac
}

repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/keepling-phase2-materialize.XXXXXX")
trap 'rm -rf -- "$fixture"' EXIT HUP INT TERM
mkdir "$fixture/bin" "$fixture/output"
printf '%s\n' 'ssh-ed25519 fixture-public-key' >"$fixture/replacement.pub"

cat >"$fixture/bin/op" <<'OP'
#!/usr/bin/env sh
set -eu
[ "$1" = read ] && [ "$2" = --no-newline ]
case "$3" in
  */token) printf '%s' fixture-token ;;
  */keyID|*/access_key_id) printf '%s' fixture-access ;;
  */applicationKey|*/secret_access_key) printf '%s' fixture-secret ;;
  */endpoint) printf '%s' https://fixture.example.invalid ;;
  */bucket) printf '%s' fixture-bucket ;;
  */region) printf '%s' auto ;;
  */cipher_passphrase) printf '%s' fixture-cipher ;;
  *) exit 1 ;;
esac
OP
cat >"$fixture/bin/curl" <<'CURL'
#!/usr/bin/env sh
config=$(cat)
case "$config" in
  *'/zones?per_page=50'*) printf '%s' '{"result":[{"id":"fixture-zone"}]}' ;;
  *'/dns_records?type=A&per_page=100'*) printf '%s' '{"result":[{"name":"rehearsal.example.invalid"}]}' ;;
  *) printf '%s' '{"apiInfo":{"storageApi":{"s3ApiUrl":"https://s3.us-west-004.backblazeb2.com","bucketName":"primary-bucket"}}}' ;;
esac
CURL
chmod 700 "$fixture/bin/op" "$fixture/bin/curl"

common="OP_BIN=$fixture/bin/op CURL_BIN=$fixture/bin/curl ./tooling/materialize-phase-2-credentials.sh"
if sh -c "$common --check" >"$fixture/missing.out" 2>&1; then
  echo "materializer accepted missing operator selections" >&2; exit 1
fi
grep -Fqx 'needed: --ssh-public-key' "$fixture/missing.out"
! grep -F 'fixture-secret' "$fixture/missing.out"

sh -c "$common --write --directory '$fixture/output' --ssh-public-key '$fixture/replacement.pub'" >"$fixture/write.out"
! grep -E 'fixture-(token|secret|cipher|access)' "$fixture/write.out"
for file in hetzner.json cloudflare-dns.json b2-primary.json r2-mirror.json b2-tofu-state.json replacement-run.pub backup-cipher.key env.sh; do
  [ -f "$fixture/output/$file" ] || { echo "missing materialized $file" >&2; exit 1; }
  case "$(portable_stat '%Lp' "$fixture/output/$file" 2>/dev/null || stat -c '%a' "$fixture/output/$file")" in 600) ;; *) echo "unsafe mode on $file" >&2; exit 1 ;; esac
done
jq -e '.version == 1 and .bucket == "primary-bucket" and .region == "us-west-004"' "$fixture/output/b2-primary.json" >/dev/null
jq -e '.version == 1 and .key == "keepling/phase-2/terraform.tfstate"' "$fixture/output/b2-tofu-state.json" >/dev/null
if sh -c "$common --write --directory '$fixture/output' --ssh-public-key '$fixture/replacement.pub'" >/dev/null 2>&1; then
  echo "materializer overwrote existing external files" >&2; exit 1
fi
if sh -c "$common --write --directory '$repository_root/unsafe-materialization' --ssh-public-key '$fixture/replacement.pub'" >/dev/null 2>&1; then
  echo "materializer accepted a repository target" >&2; exit 1
fi

echo "Phase 2 credential materializer fixtures passed: missing selections, external files, modes, redaction, and overwrite boundary"
