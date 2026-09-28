#!/usr/bin/env sh
set -eu
root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/keepling-live-setup.XXXXXX")
trap 'rm -rf -- "$fixture"' EXIT HUP INT TERM
die() { printf '%s\n' "Phase 2 live setup fixture failed: $*" >&2; exit 1; }
mkdir "$fixture/boundary" "$fixture/bin"; chmod 700 "$fixture" "$fixture/boundary" "$fixture/bin"
for f in hetzner.json cloudflare-dns.json b2-primary.json r2-mirror.json b2-tofu-state.json backup-cipher.key; do printf x >"$fixture/boundary/$f"; chmod 600 "$fixture/boundary/$f"; done
jq -n '{version:1,api_token:"fixture-only",zone_id:"fixture-zone",record_name:"example.invalid"}' >"$fixture/boundary/cloudflare-dns.json"; chmod 600 "$fixture/boundary/cloudflare-dns.json"
printf '%s\n' '192.0.2.10/32' >"$fixture/boundary/admin-source-cidrs.txt"; chmod 600 "$fixture/boundary/admin-source-cidrs.txt"
printf '%s\n' '{"version":1,"os":"ubuntu-24.04","image_id":"12345"}' >"$fixture/boundary/server-image.json"; chmod 600 "$fixture/boundary/server-image.json"
printf '%s\n' 'fixture-login-credential' >"$fixture/boundary/login-credential"; chmod 600 "$fixture/boundary/login-credential"
: >"$fixture/boundary/known-hosts"; chmod 600 "$fixture/boundary/known-hosts"
identity='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFixtureIdentity keepling-fixture'
printf '%s\n' "$identity" >"$fixture/boundary/replacement-run.pub"; chmod 600 "$fixture/boundary/replacement-run.pub"
for pair in 'KEEPLING_HETZNER_CREDENTIAL_FILE hetzner.json' 'KEEPLING_CLOUDFLARE_DNS_CREDENTIAL_FILE cloudflare-dns.json' 'KEEPLING_BACKUP_PRIMARY_CREDENTIAL_FILE b2-primary.json' 'KEEPLING_BACKUP_MIRROR_CREDENTIAL_FILE r2-mirror.json' 'KEEPLING_TOFU_STATE_CREDENTIAL_FILE b2-tofu-state.json' 'KEEPLING_SSH_PUBLIC_KEY_FILE replacement-run.pub' 'KEEPLING_BACKUP_CIPHER_FILE backup-cipher.key'; do set -- $pair; printf 'export %s="%s"\n' "$1" "$fixture/boundary/$2"; done >"$fixture/boundary/env.sh"; chmod 600 "$fixture/boundary/env.sh"
python3 - "$fixture/image.tar.gz" <<'PY'
import gzip,hashlib,io,json,sys,tarfile
o=sys.argv[1]; canon=lambda x:json.dumps(x,separators=(',',':'),sort_keys=True).encode(); digest=lambda x:hashlib.sha256(x).hexdigest()
layers=[b'fixture-one',b'fixture-two']; diffs=['sha256:'+digest(x) for x in layers]
config=canon({'architecture':'amd64','os':'linux','rootfs':{'type':'layers','diff_ids':diffs},'config':{'Labels':{'org.opencontainers.image.revision':'a'*40}}}); ch=digest(config)
blobs={}; descriptors=[]
for layer in layers:
 compressed=gzip.compress(layer,mtime=0); h=digest(compressed); blobs['blobs/sha256/'+h]=compressed; descriptors.append({'mediaType':'application/vnd.oci.image.layer.v1.tar+gzip','digest':'sha256:'+h,'size':len(compressed)})
manifest=canon({'schemaVersion':2,'mediaType':'application/vnd.oci.image.manifest.v1+json','config':{'mediaType':'application/vnd.oci.image.config.v1+json','digest':'sha256:'+ch,'size':len(config)},'layers':descriptors}); mh=digest(manifest)
index=canon({'schemaVersion':2,'mediaType':'application/vnd.oci.image.index.v1+json','manifests':[{'mediaType':'application/vnd.oci.image.manifest.v1+json','digest':'sha256:'+mh,'size':len(manifest),'platform':{'architecture':'amd64','os':'linux'}}]})
docker=canon([{'Config':ch+'.json','RepoTags':['keepling-server:plan-02-09-amd64'],'Layers':['docker-layer-1.tar','docker-layer-2.tar']}])
files={'manifest.json':docker,'oci-layout':canon({'imageLayoutVersion':'1.0.0'}),'index.json':index,ch+'.json':config,'blobs/sha256/'+ch:config,'blobs/sha256/'+mh:manifest,'docker-layer-1.tar':layers[0],'docker-layer-2.tar':layers[1],**blobs}
with tarfile.open(o,'w:gz') as t:
 for n,v in files.items(): q=tarfile.TarInfo(n); q.size=len(v); t.addfile(q,io.BytesIO(v))
PY
chmod 600 "$fixture/image.tar.gz"; "$root/tooling/verify-host-replacement.sh" --resolve-image-archive "$fixture/image.tar.gz" "$fixture/contract.json" >/dev/null; chmod 600 "$fixture/contract.json"
jq --arg image "$fixture/image.tar.gz" '(.version=1) + {image_archive:$image}' "$fixture/contract.json" >"$fixture/candidate.json"; chmod 600 "$fixture/candidate.json"
printf dump >"$fixture/dump"; chmod 600 "$fixture/dump"; sha=$(shasum -a 256 "$fixture/dump"|awk '{print $1}'); bytes=$(wc -c <"$fixture/dump"|tr -d ' ')
jq -n --arg sha "$sha" --argjson bytes "$bytes" '{version:1,source_kind:"b2-primary",ciphertext_sha256:("b"*64),plaintext_sha256:$sha,ciphertext_bytes:1,plaintext_bytes:$bytes,verification:{head:true,get:true,package_manifest:true,decrypt:true,plaintext:true}}' >"$fixture/provenance"; chmod 600 "$fixture/provenance"
jq -n --arg dump "$fixture/dump" --arg provenance "$fixture/provenance" '{version:1,source_kind:"b2-primary",dump_file:$dump,provenance_file:$provenance}' >"$fixture/recovery.json"; chmod 600 "$fixture/recovery.json"
printf '#!/usr/bin/env sh\nawk '\''NF >= 2 { print $1 " " $2 " agent-comment" }'\'' "%s"\n' "$fixture/boundary/replacement-run.pub" >"$fixture/bin/ssh-add"; chmod 700 "$fixture/bin/ssh-add"
python3 - "$fixture/agent.sock" <<'PY' &
import socket,sys,time
s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); time.sleep(20)
PY
pid=$!; sleep 1; set +e
PATH="$fixture/bin:$PATH" SSH_AUTH_SOCK="$fixture/agent.sock" KEEPLING_ALLOW_BILLABLE_APPLY=yes KEEPLING_SEQUENCE_DNS_RUNNER=/injected "$root/tooling/phase-2-live-setup.sh" --directory "$fixture/boundary" --candidate-selection "$fixture/candidate.json" --recovery-selection "$fixture/recovery.json" --admin-source-cidrs "$fixture/boundary/admin-source-cidrs.txt" --server-image-selection "$fixture/boundary/server-image.json" --login-credential "$fixture/boundary/login-credential" --ssh-known-hosts "$fixture/boundary/known-hosts" prepare >"$fixture/out" 2>"$fixture/err"; status=$?
set -e; kill "$pid" 2>/dev/null || true
[ "$status" = 3 ] || die 'prepare did not retain exit-3 live fence'; grep -Fqx 'phase2-live-setup status=prepared result=ready' "$fixture/out" || die 'prepare lacked result'; ! grep -E 'FixtureIdentity|image.tar|/injected' "$fixture/out" "$fixture/err" >/dev/null || die 'private fixture data leaked'
run=$(find "$fixture/boundary/runs" -mindepth 1 -maxdepth 1 -type d -print); [ "$(stat -f '%Lp' "$run" 2>/dev/null || stat -c '%a' "$run")" = 700 ] || die 'run directory mode'; [ ! -e "$run/workspace" ] || die 'workspace created'; bundle=$run/orchestration.env; [ "$(stat -f '%Lp' "$bundle" 2>/dev/null || stat -c '%a' "$bundle")" = 600 ] || die 'bundle mode'; "$root/tooling/phase-2-live-orchestration.sh" --validate "$bundle" >/dev/null || die 'bundle invalid'; ! grep -Eq 'COMMAND=|ALLOW_|CHANGE_TRIGGER|/injected' "$bundle" || die 'bundle retained authority'
python3 - "$root" <<'PY' || die 'cloud-init did not install exact source-owned probe bytes'
import base64, hashlib, pathlib, re, sys
root=pathlib.Path(sys.argv[1])
main=(root/'infra/tofu/hetzner/main.tf').read_text()
template=(root/'infra/tofu/hetzner/cloud-init.yml').read_text()
sources={
  'runtime':'tooling/remote-runtime-probe.sh',
  'semantic':'tooling/remote-semantic-proof.sh',
}
values={
  'tested_oci_digest':'sha256:'+'a'*64,
  'architecture':'x86_64',
}
for name,path in sources.items():
    source=(root/path).read_bytes()
    assert f'base64encode(file("${{path.module}}/../../../{path}"))' in main
    assert f'filesha256("${{path.module}}/../../../{path}")' in main
    values[name+'_probe_base64']=base64.b64encode(source).decode()
    values[name+'_probe_sha256']=hashlib.sha256(source).hexdigest()
rendered=template
for key,value in values.items(): rendered=rendered.replace('${'+key+'}',value)
for name,path in sources.items():
    fixed='/usr/local/libexec/keepling-'+name+'-probe' if name=='runtime' else '/usr/local/libexec/keepling-semantic-proof'
    block=re.search(r'(?ms)^  - path: '+re.escape(fixed)+r'\n(.*?)(?=^  - path:|^runcmd:)',rendered)
    assert block and 'owner: root:root' in block.group(1) and 'permissions: "0755"' in block.group(1) and 'encoding: b64' in block.group(1)
    payload=re.search(r'(?m)^    content: ([A-Za-z0-9+/=]+)$',block.group(1))
    assert payload and base64.b64decode(payload.group(1))== (root/path).read_bytes()
    assert values[name+'_probe_sha256'] in rendered
    altered=bytearray(base64.b64decode(payload.group(1))); altered[0]^=1
    assert hashlib.sha256(altered).hexdigest()!=values[name+'_probe_sha256']
assert '/usr/local/libexec/keepling-runtime-probe)" = "root:root:755"' in rendered
assert '/usr/local/libexec/keepling-semantic-proof)" = "root:root:755"' in rendered
assert 'bootstrap-complete.json' in rendered and 'runtime_probe_sha256' in rendered and 'semantic_probe_sha256' in rendered
PY
printf '%s\n' 'stale.example ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFixtureStale' >"$fixture/boundary/known-hosts"
set +e
PATH="$fixture/bin:$PATH" "$root/tooling/phase-2-live-setup.sh" --directory "$fixture/boundary" --candidate-selection "$fixture/candidate.json" --recovery-selection "$fixture/recovery.json" --admin-source-cidrs "$fixture/boundary/admin-source-cidrs.txt" --server-image-selection "$fixture/boundary/server-image.json" --login-credential "$fixture/boundary/login-credential" --ssh-known-hosts "$fixture/boundary/known-hosts" prepare >"$fixture/stale-out" 2>"$fixture/stale-err"
stale_status=$?
set -e
[ "$stale_status" -eq 2 ] || die 'prepare accepted a nonempty stale known-hosts file'
grep -F 'ssh-known-hosts-must-be-empty-before-provisioning' "$fixture/stale-err" >/dev/null || die 'stale known-hosts refusal was not specific'
echo 'Phase 2 live setup fixtures passed: sealed bundle, SSH authority, permissions, redaction, and no dispatch'
