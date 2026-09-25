#!/bin/sh
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

emit() { printf '%s\n' "$1"; }
fail() { emit "REMOTE_SEMANTIC_FAILED_STAGE=$1"; exit "${2:-50}"; }

# Tests may replace the candidate-local probe at this explicit boundary. The
# production branch below never accepts a runner or URL from its environment.
if [ "${KEEPLING_REMOTE_SEMANTIC_BOUNDARY_TEST:-}" = yes ]; then
  credential=${KEEPLING_REMOTE_RECOVERY_CREDENTIAL:-}
  [ -n "$credential" ] && [ -f "$credential" ] && [ ! -L "$credential" ] && \
    [ "$(portable_stat '%Lp' "$credential" 2>/dev/null || stat -c '%a' "$credential")" = 600 ] || fail credential
  runner=${KEEPLING_REMOTE_SEMANTIC_RUNNER:-}
  case "$runner" in /*) [ -x "$runner" ] || fail boundary ;; *) fail boundary ;; esac
  output=$(mktemp "${TMPDIR:-/tmp}/keepling-semantic.XXXXXX") || fail boundary
  trap 'rm -f -- "$output"' EXIT HUP INT TERM
  if "$runner" >"$output" 2>/dev/null && [ "$(wc -c <"$output" | tr -d ' ')" -le 256 ] && [ "$(cat "$output")" = 'LOGIN=ok READ=ok WRITE=ok UNDO=ok' ]; then
    emit 'REMOTE_SEMANTIC_STAGE=ready'
    exit 0
  fi
  fail proof 51
fi

[ "$#" -eq 0 ] || fail boundary
credential=/srv/keepling/recovery/new-login-credential
[ -f "$credential" ] && [ ! -L "$credential" ] && \
  [ "$(stat -c '%U:%G:%a' "$credential" 2>/dev/null)" = root:root:600 ] || fail credential
python3 - "$credential" <<'PY' || fail proof 51
import http.cookiejar
import json
import re
import sys
import urllib.error
import urllib.request
import uuid

BASE = "http://127.0.0.1:4000"
MAX_RESPONSE = 4194304

class LoopbackCookieJar(http.cookiejar.CookieJar):
    # The candidate app listens only on loopback; preserve its Secure session
    # cookie for this local HTTP hop without relaxing any non-loopback request.
    def return_ok_secure(self, cookie, request):
        return request.host in ("127.0.0.1:4000", "localhost:4000")

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

def request(path, method="GET", payload=None, csrf=None):
    data = None if payload is None else json.dumps(payload, separators=(",", ":")).encode()
    headers = {"Accept": "application/json", "Origin": BASE}
    if data is not None:
        headers["Content-Type"] = "application/json"
    if csrf is not None:
        headers["x-csrf-token"] = csrf
    req = urllib.request.Request(BASE + path, data=data, headers=headers, method=method)
    try:
        with opener.open(req, timeout=5) as response:
            body = response.read(MAX_RESPONSE + 1)
            if len(body) > MAX_RESPONSE:
                raise ValueError("response_bound")
            return response.status, json.loads(body), response.headers
    except (urllib.error.URLError, TimeoutError, ValueError, json.JSONDecodeError):
        raise ValueError("request_failed") from None

try:
    with open(sys.argv[1], "rb") as source:
        password = source.read(1025)
    if not password or len(password) > 1024 or b"\x00" in password or b"\n" in password.rstrip(b"\n"):
        raise ValueError("credential_shape")
    password_text = password.decode("utf-8").rstrip("\r\n")
    if not password_text:
        raise ValueError("credential_shape")
    jar = LoopbackCookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar), NoRedirect())
    status, auth, _headers = request("/api/v1/login", "POST", {
        "client_kind": "web", "label": "host-replacement-probe",
        "password": password_text, "version": 1,
    })
    if status != 200 or not isinstance(auth, dict) or auth.get("status") != "authenticated" or not isinstance(auth.get("csrf_token"), str):
        raise ValueError("login")
    csrf = auth["csrf_token"]
    if not csrf or len(csrf) > 4096 or not list(jar):
        raise ValueError("session")
    status, session, _ = request("/api/v1/session")
    if status != 200 or not isinstance(session, dict) or session.get("csrf_token") != csrf:
        raise ValueError("session")
    status, inbox, _ = request("/api/v1/inbox")
    if status != 200 or not isinstance(inbox, dict) or not isinstance(inbox.get("tasks"), list):
        raise ValueError("read")
    task_id, mutation_id = str(uuid.uuid4()), str(uuid.uuid4())
    status, acknowledgement, _ = request("/api/v1/commands/capture-task", "POST", {
        "mutation_id": mutation_id, "task_id": task_id,
        "title": "Keepling replacement semantic probe", "version": 1,
    }, csrf)
    if status != 201 or not isinstance(acknowledgement, dict):
        raise ValueError("write")
    undo = acknowledgement.get("undo")
    handle = undo.get("handle") if isinstance(undo, dict) else None
    if not isinstance(handle, str) or not re.fullmatch(r"[A-Za-z0-9_-]{43}", handle):
        raise ValueError("undo_handle")
    status, result, _ = request("/api/v1/commands/undo-task", "POST", {
        "handle": handle, "mutation_id": str(uuid.uuid4()), "version": 1,
    }, csrf)
    if status != 200 or not isinstance(result, dict) or result.get("outcome") not in ("accepted", "already_satisfied"):
        raise ValueError("undo")
    status, after, _ = request("/api/v1/inbox")
    if status != 200 or not isinstance(after, dict) or not isinstance(after.get("tasks"), list):
        raise ValueError("read_after_undo")
    if any(isinstance(task, dict) and task.get("id") == task_id for task in after["tasks"]):
        raise ValueError("undo_not_observed")
except Exception:
    print("REMOTE_SEMANTIC_FAILED_STAGE=proof")
    raise SystemExit(51)
PY
emit 'REMOTE_SEMANTIC_STAGE=ready'
