#!/usr/bin/env sh
set -eu
umask 077

root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
mode=${1:-}
case "$mode" in --verify-signal|--verify-signal-set|--wait) ;; *) printf '%s\n' 'usage: wait-for-phase-2-host-trust.sh --verify-signal FILE | --verify-signal-set FILE | --wait' >&2; exit 2;; esac
shift
case "$mode" in
  --verify-signal|--verify-signal-set) [ "$#" -eq 1 ] || exit 2; signal_file=$1 ;;
  --wait) [ "$#" -eq 0 ] || exit 2; signal_file= ;;
esac

python3 - "$mode" "$signal_file" "$root" <<'PY'
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
import io
from pathlib import Path

mode, signal_path, repository_root = sys.argv[1:]

class Refusal(Exception):
    def __init__(self, code):
        self.code = code

def refuse(code):
    raise Refusal(code)

def expected_environment():
    values = {
        "parent_run_id": os.environ.get("PHASE2_PARENT_RUN_ID", ""),
        "parent_run_attempt": os.environ.get("PHASE2_PARENT_RUN_ATTEMPT", ""),
        "logical_run_digest": os.environ.get("PHASE2_LOGICAL_RUN_DIGEST", ""),
        "challenge_nonce": os.environ.get("PHASE2_CHALLENGE_NONCE", ""),
        "owner_actor": os.environ.get("PHASE2_OWNER_ACTOR", ""),
        "fingerprint_sha256": os.environ.get("PHASE2_CURRENT_FINGERPRINT_SHA256", ""),
        "deadline": os.environ.get("PHASE2_TRUST_DEADLINE", ""),
    }
    if not re.fullmatch(r"[1-9][0-9]{0,15}", values["parent_run_id"]): refuse("parent-run-invalid")
    if values["parent_run_attempt"] != "1": refuse("parent-attempt-invalid")
    if not re.fullmatch(r"[0-9a-f]{64}", values["logical_run_digest"]): refuse("logical-digest-invalid")
    if not re.fullmatch(r"[0-9a-f]{32}", values["challenge_nonce"]): refuse("challenge-nonce-invalid")
    if not re.fullmatch(r"[A-Za-z0-9-]{1,39}", values["owner_actor"]): refuse("owner-actor-invalid")
    if not re.fullmatch(r"[0-9a-f]{64}", values["fingerprint_sha256"]): refuse("fingerprint-digest-invalid")
    if not re.fullmatch(r"[0-9]{10}", values["deadline"]): refuse("deadline-invalid")
    values["parent_run_id"] = int(values["parent_run_id"])
    values["parent_run_attempt"] = 1
    values["deadline"] = int(values["deadline"])
    if values["deadline"] <= int(time.time()) or values["deadline"] > int(time.time()) + 900:
        refuse("deadline-expired")
    return values

def validate_signal(signal, expected, now=None):
    now = int(time.time()) if now is None else now
    keys = {"version", "parent_run_id", "parent_run_attempt", "logical_run_digest", "challenge_nonce", "owner_actor", "marker_confirmed", "fingerprint_sha256", "issued_at", "expires_at"}
    if not isinstance(signal, dict) or set(signal) != keys: refuse("signal-schema-invalid")
    if signal.get("version") != 1 or isinstance(signal.get("version"), bool): refuse("signal-version-invalid")
    for field in ("parent_run_id", "parent_run_attempt", "issued_at", "expires_at"):
        if not isinstance(signal.get(field), int) or isinstance(signal.get(field), bool): refuse("signal-time-invalid")
    for field in ("parent_run_id", "parent_run_attempt", "logical_run_digest", "challenge_nonce", "owner_actor", "fingerprint_sha256"):
        if signal.get(field) != expected[field]: refuse("signal-binding-mismatch")
    if signal.get("marker_confirmed") is not True: refuse("marker-not-confirmed")
    if signal["issued_at"] > expected["deadline"] or signal["issued_at"] > now + 300: refuse("signal-issued-after-deadline")
    if signal["expires_at"] != signal["issued_at"] + 900: refuse("signal-expiry-invalid")
    if signal["expires_at"] <= now: refuse("signal-expired")
    return True

def read_fixture(path, mode):
    candidate = Path(path)
    if not candidate.is_absolute() or candidate.is_symlink() or not candidate.is_file(): refuse("signal-file-unavailable")
    try:
        if Path(repository_root) in candidate.resolve().parents: refuse("signal-file-in-repository")
    except OSError:
        refuse("signal-file-unavailable")
    if candidate.stat().st_size > 32768: refuse("signal-file-too-large")
    try:
        value = json.loads(candidate.read_text(encoding="utf-8"))
    except Exception:
        refuse("signal-json-invalid")
    if mode == "--verify-signal":
        signals = [value]
    else:
        if not isinstance(value, dict) or set(value) != {"signals"} or not isinstance(value["signals"], list): refuse("signal-set-invalid")
        signals = value["signals"]
    if len(signals) != 1: refuse("signal-replay-or-ambiguous")
    return signals[0]

def api_request(url, token=None, redirect="error", max_bytes=2 * 1024 * 1024):
    headers = {"Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2026-03-10"}
    if token:
        headers["Authorization"] = "Bearer " + token
    request = urllib.request.Request(url, headers=headers, method="GET")
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            return None
    opener = urllib.request.build_opener(NoRedirect())
    try:
        response = opener.open(request, timeout=15)
    except urllib.error.HTTPError as error:
        if error.code in (301, 302, 303, 307, 308) and redirect == "manual":
            location = error.headers.get("Location")
            if not location: refuse("artifact-redirect-missing")
            target = urllib.parse.urlparse(location)
            host = (target.hostname or "").lower()
            if target.scheme != "https" or target.username or target.password or not (host == "github.com" or host.endswith(".githubusercontent.com") or host.endswith(".blob.core.windows.net")):
                refuse("artifact-redirect-host-invalid")
            return None, location
        refuse("github-read-failed")
    except Exception:
        refuse("github-read-failed")
    try:
        data = response.read(max_bytes + 1)
    except Exception:
        refuse("github-read-failed")
    if len(data) > max_bytes: refuse("github-response-too-large")
    return data, None

def download_signal(repository, artifact, token):
    if not isinstance(artifact.get("id"), int) or artifact["id"] <= 0: refuse("signal-artifact-invalid")
    if artifact.get("expired") is not False: refuse("signal-artifact-expired")
    if not isinstance(artifact.get("size_in_bytes"), int) or artifact["size_in_bytes"] <= 0 or artifact["size_in_bytes"] > 32768: refuse("signal-artifact-size-invalid")
    digest = artifact.get("digest", "")
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", digest): refuse("signal-artifact-digest-invalid")
    _, location = api_request(f"https://api.github.com/repos/{repository}/actions/artifacts/{artifact['id']}/zip", token, redirect="manual", max_bytes=32768)
    data, _ = api_request(location, None, max_bytes=32768)
    if len(data) != artifact["size_in_bytes"] or "sha256:" + hashlib.sha256(data).hexdigest() != digest: refuse("signal-artifact-digest-mismatch")
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            members = archive.infolist()
            if len(members) != 1 or members[0].filename != "phase-2-host-trust-signal.json" or members[0].file_size > 8192: refuse("signal-artifact-layout-invalid")
            raw = archive.read(members[0])
        value = json.loads(raw.decode("utf-8"))
    except Refusal:
        raise
    except Exception:
        refuse("signal-artifact-json-invalid")
    return value

def wait_for_signal(expected):
    repository = os.environ.get("GITHUB_REPOSITORY", "")
    token = os.environ.get("GITHUB_TOKEN", "")
    if not re.fullmatch(r"[-A-Za-z0-9_.]+/[-A-Za-z0-9_.]+", repository) or not token: refuse("github-reader-unavailable")
    base = f"https://api.github.com/repos/{repository}/actions/workflows/phase-2-host-trust-approval.yml/runs"
    prefix = f"phase2-host-trust-parent-{expected['parent_run_id']}-attempt-1-digest-{expected['logical_run_digest']}-signal-"
    while int(time.time()) < expected["deadline"]:
        body, _ = api_request(base + "?branch=main&event=workflow_dispatch&per_page=100", token)
        try:
            page = json.loads(body.decode("utf-8"))
        except Exception:
            refuse("signal-run-list-invalid")
        runs = page.get("workflow_runs") if isinstance(page, dict) else None
        if not isinstance(runs, list) or page.get("total_count") != len(runs) or len(runs) > 100: refuse("signal-run-list-incomplete")
        matching = []
        for run in runs:
            if not isinstance(run, dict) or run.get("head_branch") != "main" or run.get("event") != "workflow_dispatch": continue
            if not isinstance(run.get("id"), int) or not isinstance(run.get("run_attempt"), int): continue
            artifacts_body, _ = api_request(f"https://api.github.com/repos/{repository}/actions/runs/{run['id']}/artifacts?per_page=100", token)
            try:
                artifacts_page = json.loads(artifacts_body.decode("utf-8"))
            except Exception:
                refuse("signal-artifact-list-invalid")
            artifacts = artifacts_page.get("artifacts") if isinstance(artifacts_page, dict) else None
            if not isinstance(artifacts, list) or artifacts_page.get("total_count") != len(artifacts) or len(artifacts) > 100: refuse("signal-artifact-list-incomplete")
            for artifact in artifacts:
                name = artifact.get("name") if isinstance(artifact, dict) else None
                if isinstance(name, str) and name.startswith(prefix):
                    matching.append((run, artifact))
        if len(matching) > 1: refuse("signal-replay-or-ambiguous")
        if len(matching) == 1:
            run, artifact = matching[0]
            actor = run.get("actor")
            if run.get("run_attempt") != 1 or run.get("status") != "completed" or run.get("conclusion") != "success" or not isinstance(actor, dict) or actor.get("login") != expected["owner_actor"]:
                refuse("signal-run-not-original-owner")
            if run.get("event") != "workflow_dispatch" or run.get("head_branch") != "main": refuse("signal-run-source-invalid")
            repository_identity = run.get("repository")
            head_repository = run.get("head_repository")
            if not isinstance(repository_identity, dict) or repository_identity.get("full_name") != repository: refuse("signal-run-repository-invalid")
            if not isinstance(head_repository, dict) or head_repository.get("full_name") != repository: refuse("signal-run-head-repository-invalid")
            if not re.fullmatch(r"[0-9a-f]{40}", run.get("head_sha", "")): refuse("signal-run-source-invalid")
            artifact_run = artifact.get("workflow_run")
            if not isinstance(artifact_run, dict) or artifact_run.get("id") != run.get("id"): refuse("signal-artifact-parent-mismatch")
            signal = download_signal(repository, artifact, token)
            return validate_signal(signal, expected)
        time.sleep(min(10, max(1, expected["deadline"] - int(time.time()))))
    refuse("signal-timeout")

try:
    expected = expected_environment()
    if mode == "--wait":
        wait_for_signal(expected)
    else:
        signal = read_fixture(signal_path, mode)
        validate_signal(signal, expected)
    print("host-trust status=verified signal=single-use")
except Refusal as error:
    print(f"host-trust status=NON_PASSING reason={error.code}", file=sys.stderr)
    raise SystemExit(1)
PY
