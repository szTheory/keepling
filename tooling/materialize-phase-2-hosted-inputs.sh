#!/usr/bin/env sh
# Materialize the protected runner's closed private-input bundle. Values arrive
# from the reviewed environment and are never printed or written to the checkout.
set -eu
umask 077
root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
directory=
inputs_json=${KEEPLING_HOSTED_INPUTS_JSON:-}
identity=${KEEPLING_SSH_PUBLIC_IDENTITY:-}
die() { printf '%s\n' "phase2-hosted-inputs status=NON_PASSING reason=$1" >&2; exit 1; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    --directory) [ "$#" -ge 2 ] || die usage; directory=$2; shift 2 ;;
    --inputs-json) [ "$#" -ge 2 ] || die usage; inputs_json=$2; shift 2 ;;
    --ssh-public-identity) [ "$#" -ge 2 ] || die usage; identity=$2; shift 2 ;;
    *) die usage ;;
  esac
done
[ -n "$directory" ] && [ -n "$inputs_json" ] && [ -n "$identity" ] || die inputs-missing
case "$directory" in /*) ;; *) die directory-invalid;; esac
case "$directory" in "$root"|"$root"/*) die directory-in-repository;; esac
[ ! -e "$directory" ] && [ ! -L "$directory" ] || die directory-already-exists

# Keep the secret-bearing child environment deliberately narrow. Python parses
# the closed contract and writes files with O_EXCL and fixed permissions.
env -i PATH="$PATH" LC_ALL=C TARGET_DIRECTORY="$directory" HOSTED_INPUTS_JSON="$inputs_json" \
  SSH_PUBLIC_IDENTITY="$identity" \
  HCLOUD_TOKEN="${HCLOUD_TOKEN:-}" CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-}" \
  PRIMARY_ACCESS="${KEEPLING_BACKUP_PRIMARY_ACCESS_KEY:-}" PRIMARY_SECRET="${KEEPLING_BACKUP_PRIMARY_SECRET_KEY:-}" \
  PRIMARY_ENDPOINT="${KEEPLING_HOSTED_B2_PRIMARY_ENDPOINT:-}" PRIMARY_REGION="${KEEPLING_HOSTED_B2_PRIMARY_REGION:-}" PRIMARY_BUCKET="${KEEPLING_HOSTED_B2_PRIMARY_BUCKET:-}" \
  MIRROR_ACCESS="${KEEPLING_BACKUP_MIRROR_ACCESS_KEY:-}" MIRROR_SECRET="${KEEPLING_BACKUP_MIRROR_SECRET_KEY:-}" \
  MIRROR_ENDPOINT="${KEEPLING_BACKUP_MIRROR_ENDPOINT:-}" MIRROR_REGION="${KEEPLING_BACKUP_MIRROR_REGION:-}" MIRROR_BUCKET="${KEEPLING_BACKUP_MIRROR_BUCKET:-}" \
  STATE_ACCESS="${KEEPLING_TOFU_STATE_ACCESS_KEY:-}" STATE_SECRET="${KEEPLING_TOFU_STATE_SECRET_KEY:-}" \
  STATE_ENDPOINT="${KEEPLING_TOFU_STATE_ENDPOINT:-}" STATE_REGION="${KEEPLING_TOFU_STATE_REGION:-}" STATE_BUCKET="${KEEPLING_TOFU_STATE_BUCKET:-}" \
  CIPHER="${KEEPLING_BACKUP_CIPHER_PASSPHRASE:-}" python3 - <<'PY' || die materialization-refused
import ipaddress, json, os, re, secrets, stat

target = os.environ["TARGET_DIRECTORY"]
root = os.path.realpath(os.path.join(os.path.dirname(__file__), "..")) if "__file__" in globals() else None
def fail(): raise SystemExit(1)
def text(name, pattern=None, maximum=4096):
    value=os.environ.get(name, "")
    if not value or len(value)>maximum or "\n" in value or "\r" in value or "\x00" in value: fail()
    if pattern and not re.fullmatch(pattern, value): fail()
    return value
def endpoint(name):
    value=text(name, r"https://[A-Za-z0-9.-]+(?::[0-9]{1,5})?")
    return value
try:
    raw=os.environ["HOSTED_INPUTS_JSON"]
    if len(raw)>16384: fail()
    def no_dupes(pairs):
        result={}
        for key,value in pairs:
            if key in result: fail()
            result[key]=value
        return result
    inputs=json.loads(raw, object_pairs_hook=no_dupes)
    keys={"version","dns_zone_id","dns_record_name","server_image_id","admin_source_cidrs","candidate_source","recovery_source","login_source","b2_primary_endpoint","b2_primary_region","b2_primary_bucket"}
    if not isinstance(inputs,dict) or set(inputs)!=keys or inputs["version"] != 1 or isinstance(inputs["version"],bool): fail()
    if inputs["candidate_source"]!="rebuilt-archive" or inputs["recovery_source"]!="same-run-synthetic-capture" or inputs["login_source"]!="same-run-synthetic-capture": fail()
    if not isinstance(inputs["dns_zone_id"],str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,128}",inputs["dns_zone_id"]): fail()
    if not isinstance(inputs["dns_record_name"],str) or not re.fullmatch(r"(?=.{1,253}$)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}",inputs["dns_record_name"]): fail()
    if not isinstance(inputs["server_image_id"],str) or not re.fullmatch(r"[1-9][0-9]{0,19}",inputs["server_image_id"]): fail()
    cidrs=inputs["admin_source_cidrs"]
    if not isinstance(cidrs,list) or not 1<=len(cidrs)<=32 or len(set(cidrs))!=len(cidrs): fail()
    for cidr in cidrs:
        if not isinstance(cidr,str) or str(ipaddress.ip_network(cidr,strict=True))!=cidr or ipaddress.ip_network(cidr,strict=True).prefixlen==0: fail()
    primary_endpoint=text("PRIMARY_ENDPOINT")
    if inputs["b2_primary_endpoint"]!=primary_endpoint or not re.fullmatch(r"https://[A-Za-z0-9.-]+(?::[0-9]{1,5})?",primary_endpoint): fail()
    if inputs["b2_primary_region"]!=text("PRIMARY_REGION",r"[A-Za-z0-9-]{1,64}") or inputs["b2_primary_bucket"]!=text("PRIMARY_BUCKET",r"[A-Za-z0-9._-]{1,255}"): fail()
    ssh=text("SSH_PUBLIC_IDENTITY",r"ssh-ed25519 [A-Za-z0-9+/=]+(?: [A-Za-z0-9_.@+-]{1,128})?",1024)
    secrets={
      "hetzner.json":{"version":1,"token":text("HCLOUD_TOKEN",r"[A-Za-z0-9_-]{16,512}")},
      "cloudflare-dns.json":{"version":1,"api_token":text("CLOUDFLARE_API_TOKEN"),"zone_id":inputs["dns_zone_id"],"record_name":inputs["dns_record_name"]},
      "b2-primary.json":{"version":1,"endpoint":primary_endpoint,"region":inputs["b2_primary_region"],"bucket":inputs["b2_primary_bucket"],"access_key_id":text("PRIMARY_ACCESS"),"secret_access_key":text("PRIMARY_SECRET")},
      "r2-mirror.json":{"version":1,"endpoint":endpoint("MIRROR_ENDPOINT"),"region":text("MIRROR_REGION",r"[A-Za-z0-9-]{1,64}"),"bucket":text("MIRROR_BUCKET",r"[A-Za-z0-9._-]{1,255}"),"access_key_id":text("MIRROR_ACCESS"),"secret_access_key":text("MIRROR_SECRET")},
      "b2-tofu-state.json":{"version":1,"endpoint":endpoint("STATE_ENDPOINT"),"region":text("STATE_REGION",r"[A-Za-z0-9-]{1,64}"),"bucket":text("STATE_BUCKET",r"[A-Za-z0-9._-]{1,255}"),"key":"keepling/phase-2/terraform.tfstate","access_key_id":text("STATE_ACCESS"),"secret_access_key":text("STATE_SECRET")},
      "replacement-run.pub":ssh,
      "backup-cipher.key":text("CIPHER"),
    }
    os.mkdir(target,0o700)
    def write(name,data):
        fd=os.open(os.path.join(target,name),os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
        with os.fdopen(fd,"w",encoding="utf-8",newline="\n") as out:
            if isinstance(data,dict): json.dump(data,out,sort_keys=True,separators=(",",":")); out.write("\n")
            else: out.write(data+"\n")
    for name,data in secrets.items(): write(name,data)
    names=["KEEPLING_HETZNER_CREDENTIAL_FILE","KEEPLING_CLOUDFLARE_DNS_CREDENTIAL_FILE","KEEPLING_BACKUP_PRIMARY_CREDENTIAL_FILE","KEEPLING_BACKUP_MIRROR_CREDENTIAL_FILE","KEEPLING_TOFU_STATE_CREDENTIAL_FILE","KEEPLING_SSH_PUBLIC_KEY_FILE","KEEPLING_BACKUP_CIPHER_FILE"]
    files=["hetzner.json","cloudflare-dns.json","b2-primary.json","r2-mirror.json","b2-tofu-state.json","replacement-run.pub","backup-cipher.key"]
    write("env.sh","\n".join(f'export {name}="{target}/{filename}"' for name,filename in zip(names,files)))
except Exception:
    try:
        for name in os.listdir(target): os.unlink(os.path.join(target,name))
        os.rmdir(target)
    except OSError: pass
    fail()
PY
printf '%s\n' 'phase2-hosted-inputs status=materialized result=private-bundle-ready'
