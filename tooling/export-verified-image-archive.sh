#!/usr/bin/env sh
# Export the tested Docker image into one archive with bound Docker-save and OCI views.
set -eu
umask 077
root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
die() { printf '%s\n' "verified image export refused: $1" >&2; exit 2; }
[ "$#" -eq 2 ] || die 'usage: tooling/export-verified-image-archive.sh IMMUTABLE_IMAGE_TAG EXTERNAL_OUTPUT.tar.gz'
tag=$1 output=$2
printf '%s' "$tag" | grep -Eq '^keepling-server:plan-02-09-amd64$' || die 'candidate tag must be the fixed amd64 acceptance tag'
case "$output" in /*) ;; *) die 'output must be an absolute path';; esac
case "$output" in "$root"|"$root"/*) die 'archive must remain outside the repository';; esac
[ ! -e "$output" ] || die 'output already exists'
docker image inspect "$tag" --format '{{.Architecture}} {{.Os}}' | grep -Fxq 'amd64 linux' || die 'candidate image is not linux/amd64'
tmp=$(mktemp -d "${TMPDIR:-/tmp}/keepling-image-export.XXXXXX"); chmod 700 "$tmp"
trap 'rm -rf -- "$tmp"' EXIT HUP INT TERM
docker save "$tag" -o "$tmp/docker.tar"
python3 - "$tmp/docker.tar" "$output" "$tmp" <<'PY'
import gzip, hashlib, io, json, os, sys, tarfile
source, output, work = sys.argv[1:]
canon = lambda value: json.dumps(value, separators=(",", ":"), sort_keys=True).encode()
digest = lambda data: hashlib.sha256(data).hexdigest()
with tarfile.open(source, "r:") as inp:
    members = inp.getmembers()
    manifests = [m for m in members if m.name == "manifest.json" and m.isfile()]
    if len(manifests) != 1:
        raise SystemExit("docker save manifest is ambiguous")
    manifest_bytes = inp.extractfile(manifests[0]).read(65537)
    if len(manifest_bytes) > 65536:
        raise SystemExit("docker save manifest is oversized")
    manifest = json.loads(manifest_bytes)
    if not isinstance(manifest, list) or len(manifest) != 1 or manifest[0].get("RepoTags") != ["keepling-server:plan-02-09-amd64"]:
        raise SystemExit("docker save tag does not match the fixed acceptance candidate")
    entry = manifest[0]
    config_member = next((m for m in members if m.name == entry.get("Config") and m.isfile()), None)
    if config_member is None or config_member.size > 1024 * 1024:
        raise SystemExit("docker image config is unavailable")
    config_data = inp.extractfile(config_member).read(1024 * 1024 + 1)
    image = json.loads(config_data)
    if image.get("architecture") != "amd64" or image.get("os") != "linux":
        raise SystemExit("docker image config architecture is invalid")
    diffs = image.get("rootfs", {}).get("diff_ids")
    layers = entry.get("Layers")
    if not isinstance(layers, list) or not layers or len(layers) != len(diffs):
        raise SystemExit("docker layer inventory does not match config")
    config_sha = digest(config_data)
    if entry["Config"].rsplit("/", 1)[-1].removesuffix(".json") != config_sha:
        raise SystemExit("docker config digest is invalid")
    oci_layers = []
    compressed_paths = []
    raw_paths = []
    for index, name in enumerate(layers):
        member = next((m for m in members if m.name == name and m.isfile()), None)
        if member is None or member.size > 4 * 1024 * 1024 * 1024:
            raise SystemExit("docker layer is unavailable or oversized")
        raw_path = os.path.join(work, f"layer-{index}.tar")
        raw_hash = hashlib.sha256()
        source_layer = inp.extractfile(member)
        if source_layer.read(2) == b"\x1f\x8b":
            source_layer.seek(0)
            source_layer = gzip.GzipFile(fileobj=source_layer, mode="rb")
        else:
            source_layer.seek(0)
        with source_layer, open(raw_path, "wb") as out:
            while block := source_layer.read(1024 * 1024):
                raw_hash.update(block); out.write(block)
        if "sha256:" + raw_hash.hexdigest() != diffs[index]:
            raise SystemExit("docker layer does not match the config diff id")
        compressed_path = os.path.join(work, f"oci-layer-{index}.tar.gz")
        with open(raw_path, "rb") as raw, open(compressed_path, "wb") as out:
            with gzip.GzipFile(fileobj=out, mode="wb", mtime=0) as zipped:
                while block := raw.read(1024 * 1024): zipped.write(block)
        compressed_hash = hashlib.sha256()
        with open(compressed_path, "rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                compressed_hash.update(block)
        compressed_size = os.path.getsize(compressed_path)
        oci_layers.append({"mediaType":"application/vnd.oci.image.layer.v1.tar+gzip","digest":"sha256:"+compressed_hash.hexdigest(),"size":compressed_size})
        raw_paths.append(raw_path); compressed_paths.append(compressed_path)
    oci_manifest = canon({"schemaVersion":2,"mediaType":"application/vnd.oci.image.manifest.v1+json","config":{"mediaType":"application/vnd.oci.image.config.v1+json","digest":"sha256:"+config_sha,"size":len(config_data)},"layers":oci_layers})
    manifest_sha = digest(oci_manifest)
    index_json = canon({"schemaVersion":2,"mediaType":"application/vnd.oci.image.index.v1+json","manifests":[{"mediaType":"application/vnd.oci.image.manifest.v1+json","digest":"sha256:"+manifest_sha,"size":len(oci_manifest),"platform":{"architecture":"amd64","os":"linux"}}]})
    docker_entry = {"Config": config_sha + ".json", "RepoTags": ["keepling-server:plan-02-09-amd64"], "Layers": [f"docker-layer-{i}.tar" for i in range(len(raw_paths))]}
    with tarfile.open(output, "w:gz", compresslevel=6) as out:
        for member in members:
            # Modern Docker Engine archives may already carry an OCI view.
            # Replace that view with the deterministic one derived below.
            if member.name in ("manifest.json", "repositories", "oci-layout", "index.json", entry["Config"], *layers) or member.name.startswith("blobs/sha256/"):
                continue
            stream = inp.extractfile(member) if member.isfile() else None
            out.addfile(member, stream)
        def add_bytes(name, data):
            info = tarfile.TarInfo(name); info.size = len(data); info.mode = 0o600; info.mtime = 0
            out.addfile(info, io.BytesIO(data))
        def add_file(name, path):
            info = tarfile.TarInfo(name); info.size = os.path.getsize(path); info.mode = 0o600; info.mtime = 0
            with open(path, "rb") as stream: out.addfile(info, stream)
        add_bytes("manifest.json", canon([docker_entry]))
        add_bytes(config_sha + ".json", config_data)
        for layer_index, path in enumerate(raw_paths): add_file(f"docker-layer-{layer_index}.tar", path)
        add_bytes("oci-layout", canon({"imageLayoutVersion":"1.0.0"}))
        add_bytes("index.json", index_json)
        add_bytes("blobs/sha256/"+config_sha, config_data)
        add_bytes("blobs/sha256/"+manifest_sha, oci_manifest)
        for layer, path in zip(oci_layers, compressed_paths):
            add_file("blobs/sha256/"+layer["digest"].split(":",1)[1], path)
os.chmod(output, 0o600)
PY
"$root/tooling/verify-host-replacement.sh" --resolve-image-archive "$output" "$tmp/contract.json" >/dev/null || die 'archive did not pass the source image contract'
printf '%s\n' 'verified-image-export status=passed result=private-archive-ready'
