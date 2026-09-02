#!/usr/bin/env sh
set -eu

repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
cd "$repository_root"
die() { echo "Image archive contract regression failed: $*" >&2; exit 1; }
fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/keepling-image-contract.XXXXXX")
trap 'rm -rf -- "$fixture_root"' EXIT HUP INT TERM

python3 - "$fixture_root" <<'PY'
import gzip,hashlib,io,json,os,sys,tarfile
root=sys.argv[1]
tag='keepling-server:plan-02-09-amd64'
def canon(value): return json.dumps(value,separators=(',',':'),sort_keys=True).encode()
def digest(data): return hashlib.sha256(data).hexdigest()
def member(archive,name,data):
    info=tarfile.TarInfo(name); info.size=len(data); archive.addfile(info,io.BytesIO(data))
def build(name, mutation=None):
    layers=[b'layer-one',b'layer-two']
    diff_ids=['sha256:'+digest(layer) for layer in layers]
    config={'architecture':'amd64','os':'linux','rootfs':{'type':'layers','diff_ids':diff_ids},'config':{'Labels':{'org.opencontainers.image.revision':'a'*40}}}
    config_bytes=canon(config); config_hex=digest(config_bytes)
    oci_layers=[]; blobs={}
    for layer in layers:
        compressed=gzip.compress(layer,mtime=0); layer_hex=digest(compressed)
        blobs['blobs/sha256/'+layer_hex]=compressed
        oci_layers.append({'mediaType':'application/vnd.oci.image.layer.v1.tar+gzip','digest':'sha256:'+layer_hex,'size':len(compressed)})
    manifest={'schemaVersion':2,'mediaType':'application/vnd.oci.image.manifest.v1+json','config':{'mediaType':'application/vnd.oci.image.config.v1+json','digest':'sha256:'+config_hex,'size':len(config_bytes)},'layers':oci_layers}
    manifest_bytes=canon(manifest); manifest_hex=digest(manifest_bytes)
    index={'schemaVersion':2,'mediaType':'application/vnd.oci.image.index.v1+json','manifests':[{'mediaType':'application/vnd.oci.image.manifest.v1+json','digest':'sha256:'+manifest_hex,'size':len(manifest_bytes),'platform':{'architecture':'amd64','os':'linux'}}]}
    docker={'Config':config_hex+'.json','RepoTags':[tag],'Layers':['docker-layer-1.tar','docker-layer-2.tar']}
    files={'manifest.json':canon([docker]),'oci-layout':canon({'imageLayoutVersion':'1.0.0'}),'index.json':canon(index),config_hex+'.json':config_bytes,'blobs/sha256/'+config_hex:config_bytes,'blobs/sha256/'+manifest_hex:manifest_bytes,'docker-layer-1.tar':layers[0],'docker-layer-2.tar':layers[1],**blobs}
    if mutation == 'config-size': manifest['config']['size']+=1; files['blobs/sha256/'+manifest_hex]=canon(manifest)
    elif mutation == 'manifest-digest': index['manifests'][0]['digest']='sha256:'+'f'*64; files['index.json']=canon(index)
    elif mutation == 'layer-digest': manifest['layers'][0]['digest']='sha256:'+'f'*64; files['blobs/sha256/'+manifest_hex]=canon(manifest)
    elif mutation == 'docker-layer-conflict': files['docker-layer-1.tar']=b'other-layer'
    elif mutation == 'oci-config-conflict': files['blobs/sha256/'+config_hex]=b'{}'
    elif mutation == 'multiple-manifests': index['manifests'].append(dict(index['manifests'][0])); files['index.json']=canon(index)
    elif mutation == 'wrong-platform': index['manifests'][0]['platform']['architecture']='arm64'; files['index.json']=canon(index)
    elif mutation == 'absent-platform': del index['manifests'][0]['platform']; files['index.json']=canon(index)
    elif mutation == 'wrong-media': index['manifests'][0]['mediaType']='application/octet-stream'; files['index.json']=canon(index)
    elif mutation == 'extra-docker-view': files['manifest.json']=canon([docker,dict(docker)])
    elif mutation == 'missing-revision': config['config']['Labels']={}; changed=canon(config); files[config_hex+'.json']=changed; files['blobs/sha256/'+config_hex]=changed
    elif mutation == 'traversal': files['../escape']=b'x'
    elif mutation == 'oversized-index': files['index.json']=b' '*70000
    with tarfile.open(os.path.join(root,name),'w:gz') as archive:
        for member_name,data in files.items(): member(archive,member_name,data)
        if mutation == 'duplicate': member(archive,'index.json',files['index.json'])
build('good.tar.gz')
build('absent-platform.tar.gz','absent-platform')
for case in ('config-size','manifest-digest','layer-digest','docker-layer-conflict','oci-config-conflict','multiple-manifests','wrong-platform','wrong-media','extra-docker-view','missing-revision','duplicate','traversal','oversized-index'):
    build(case+'.tar.gz',case)
PY

contract=$fixture_root/archive-contract.json
./tooling/verify-host-replacement.sh --resolve-image-archive "$fixture_root/good.tar.gz" "$contract" >/dev/null
[ "$(stat -f '%Lp' "$contract" 2>/dev/null || stat -c '%a' "$contract")" = 600 ] || die "archive contract is not owner-only"
jq -e 'keys == ["architecture","archive_sha256","config_image_id","manifest_digest","os","revision","rootfs_diff_ids","version"] and .version == 2 and .architecture == "amd64" and .os == "linux" and (.archive_sha256 | test("^[0-9a-f]{64}$")) and (.config_image_id | test("^sha256:[0-9a-f]{64}$")) and (.manifest_digest | test("^sha256:[0-9a-f]{64}$")) and (.revision | test("^[0-9a-f]{7,64}$")) and (.rootfs_diff_ids | length == 2) and all(.rootfs_diff_ids[]; test("^sha256:[0-9a-f]{64}$"))' "$contract" >/dev/null || die "archive contract is not minimal and valid"
./tooling/verify-host-replacement.sh --resolve-image-archive "$fixture_root/absent-platform.tar.gz" "$fixture_root/absent-platform.json" >/dev/null || die "config-bound platform without an index hint was rejected"

expect_fail() {
  name=$1; output=$fixture_root/$name-output.json
  if ./tooling/verify-host-replacement.sh --resolve-image-archive "$fixture_root/$name.tar.gz" "$output" >/dev/null 2>&1; then die "$name was accepted"; fi
  [ ! -e "$output" ] || die "$name wrote a contract"
}
for name in config-size manifest-digest layer-digest docker-layer-conflict oci-config-conflict multiple-manifests wrong-platform wrong-media extra-docker-view missing-revision duplicate traversal oversized-index; do expect_fail "$name"; done
printf 'not an archive\n' >"$fixture_root/malformed.tar.gz"; expect_fail malformed

existing=$fixture_root/existing.json; : >"$existing"
if ./tooling/verify-host-replacement.sh --resolve-image-archive "$fixture_root/good.tar.gz" "$existing" >/dev/null 2>&1; then die "existing target was accepted"; fi

echo "Image archive contract regression passed: Docker and OCI views bind one config, manifest, platform, and layer chain"
