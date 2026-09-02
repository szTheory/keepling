#!/usr/bin/env sh
set -eu

repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
cd "$repository_root"
die() { echo "Image archive contract regression failed: $*" >&2; exit 1; }
fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/keepling-image-contract.XXXXXX")
trap 'rm -rf -- "$fixture_root"' EXIT HUP INT TERM

python3 - "$fixture_root" <<'PY'
import hashlib,json,io,os,sys,tarfile
root=sys.argv[1]
def build(name, architecture='amd64', revision='a'*40, manifests=1, valid_name=True, extra=False):
    config=json.dumps({'architecture':architecture,'os':'linux','config':{'Labels':{'org.opencontainers.image.revision':revision}}},separators=(',',':'),sort_keys=True).encode()
    digest=hashlib.sha256(config).hexdigest()
    config_name=(digest if valid_name else '0'*64)+'.json'
    manifest=[{'Config':config_name,'RepoTags':['keepling-server:plan-02-09-amd64'],'Layers':['layer.tar']} for _ in range(manifests)]
    if extra: manifest[0]['Unexpected']='value'
    with tarfile.open(os.path.join(root,name),'w:gz') as archive:
        for member_name,data in ((config_name,config),('manifest.json',json.dumps(manifest).encode()),('layer.tar',b'fixture')):
            info=tarfile.TarInfo(member_name); info.size=len(data); archive.addfile(info,io.BytesIO(data))
build('archive-a.tar.gz')
build('wrong-arch.tar.gz',architecture='arm64')
build('missing-revision.tar.gz',revision='')
build('invalid-revision.tar.gz',revision='not-a-revision')
build('multiple.tar.gz',manifests=2)
build('wrong-config-name.tar.gz',valid_name=False)
build('unexpected-field.tar.gz',extra=True)
with open(os.path.join(root,'drifted-tag-b.json'),'w') as stream:
    json.dump({'image_id':'sha256:'+'b'*64,'revision':'b'*40,'architecture':'amd64'},stream)
PY

contract=$fixture_root/archive-contract.json
./tooling/verify-host-replacement.sh --resolve-image-archive "$fixture_root/archive-a.tar.gz" "$contract" >/dev/null
[ "$(stat -f '%Lp' "$contract" 2>/dev/null || stat -c '%a' "$contract")" = 600 ] || die "archive contract is not owner-only"
jq -e '
  keys == ["architecture","archive_sha256","image_id","revision","version"] and
  .version == 1 and .architecture == "amd64" and
  (.archive_sha256 | test("^[0-9a-f]{64}$")) and
  (.image_id | test("^sha256:[0-9a-f]{64}$")) and
  (.revision | test("^[0-9a-f]{7,64}$"))
' "$contract" >/dev/null || die "archive contract is not minimal and valid"
jq -e --slurpfile contract "$contract" '
  .image_id != $contract[0].image_id and .revision != $contract[0].revision and
  .architecture == $contract[0].architecture
' "$fixture_root/drifted-tag-b.json" >/dev/null || die "drift fixture does not disagree with archive A"

expect_fail() {
  name=$1 archive=$2 output=$fixture_root/$name-output.json
  if ./tooling/verify-host-replacement.sh --resolve-image-archive "$archive" "$output" >/dev/null 2>&1; then die "$name was accepted"; fi
  [ ! -e "$output" ] || die "$name wrote a contract"
}
for name in wrong-arch missing-revision invalid-revision multiple wrong-config-name unexpected-field; do
  expect_fail "$name" "$fixture_root/$name.tar.gz"
done
printf 'not an archive\n' >"$fixture_root/malformed.tar.gz"
expect_fail malformed "$fixture_root/malformed.tar.gz"

existing=$fixture_root/existing.json
: >"$existing"
if ./tooling/verify-host-replacement.sh --resolve-image-archive "$fixture_root/archive-a.tar.gz" "$existing" >/dev/null 2>&1; then die "existing target was accepted"; fi
unsafe=$repository_root/.unsafe-image-contract-$(basename "$fixture_root").json
[ ! -e "$unsafe" ] || die "unsafe fixture target already exists"
if ./tooling/verify-host-replacement.sh --resolve-image-archive "$fixture_root/archive-a.tar.gz" "$unsafe" >/dev/null 2>&1; then die "repository output was accepted"; fi
if [ -e "$unsafe" ]; then
  rm -f -- "$unsafe"
  die "unsafe output was written"
fi

echo "Image archive contract regression passed: immutable archive A wins and drifted metadata cannot become expected identity"
