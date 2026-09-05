#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
#
# container-runtime-verify.sh — OPERATOR-EXECUTED runtime verification of the
# ScamWall image and its deployment container.
#
# This is deliberately a separate program from container-security-check.sh.
# That script inspects repository content and uses git; this one talks to the
# Docker daemon and NEVER invokes git. The service account cannot reach the
# daemon, so this runs as the operator — and an operator running as root inside
# a repository owned by `scamwall` would hit git's dubious-ownership refusal.
# Rather than add a safe.directory exception, change repository ownership, or
# put the service account in the `docker` group, the daemon path simply has no
# git dependency: the repository root is derived from this script's own
# location and then confirmed by the files it must contain.
#
# Design rules, each of which exists because its absence produced a false pass:
#
#   * Every prerequisite, Docker operation and parse is checked explicitly.
#     A check that could not run is BLOCKED and makes the exit status nonzero.
#     It is never silently treated as a pass.
#   * Inspection output is captured and its exit status verified BEFORE any
#     assertion reads it. A failed `docker inspect` can therefore never be
#     mistaken for "the property is absent".
#   * Assertions are evaluated with jq over captured JSON, not by grepping
#     command output, so error text on stderr cannot satisfy a pattern.
#   * The requested image is resolved to its immutable image ID, and the
#     inspected container's .Image must equal it.
#   * The inspection container is created under a PRIVATE Compose project name
#     unique to this invocation, and only resources this invocation created are
#     removed — including on failure or interruption. A pre-existing deployment
#     container is never stopped, removed, or inspected in place of ours.
#
# Usage:
#   scripts/container-runtime-verify.sh
#
# Environment:
#   SCAMWALL_IMAGE              image to verify           (default scamwall:local)
#   SCAMWALL_EXPECTED_IMAGE_ID  if set, the resolved image ID must equal it
#
# Exit status: 0 only when every required check actually ran and passed.

set -uo pipefail

# --- Repository root, without git ---------------------------------------------
#
# Derived from this script's location, then CONFIRMED by the presence of the
# files it must contain. If the layout is not what we expect we stop, rather
# than verifying something else and reporting it as ScamWall.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)" || {
  printf 'fatal: could not resolve this script'\''s directory\n' >&2; exit 2; }
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd -P)" || {
  printf 'fatal: could not resolve the repository root\n' >&2; exit 2; }

COMPOSE="$REPO_ROOT/deploy/compose/compose.yaml"
ENV_FILE="$REPO_ROOT/deploy/compose/.env"
IMAGE="${SCAMWALL_IMAGE:-scamwall:local}"

for required in "$COMPOSE" "$REPO_ROOT/container/Dockerfile"; do
  [ -f "$required" ] || {
    printf 'fatal: expected file not found: %s\n' "$required" >&2
    printf 'fatal: %s does not look like a ScamWall checkout\n' "$REPO_ROOT" >&2
    exit 2; }
done

case "${1:-}" in
  "") ;;
  -h|--help) sed -n '3,44p' "$0"; exit 0 ;;
  *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
esac

PASS=0; FAIL=0; BLOCK=0
ok()      { printf '\033[32mPASS\033[0m    %s\n' "$1"; PASS=$((PASS + 1)); }
bad()     { printf '\033[31mFAIL\033[0m    %s\n' "$1"; FAIL=$((FAIL + 1)); }
blocked() { printf '\033[31mBLOCKED\033[0m %s\n' "$1"; BLOCK=$((BLOCK + 1)); }
note()    { printf '        %s\n' "$1"; }

summary_and_exit() {
  printf '\n%d passed, %d failed, %d blocked\n' "$PASS" "$FAIL" "$BLOCK"
  if [ "$FAIL" -gt 0 ] || [ "$BLOCK" -gt 0 ]; then
    printf 'RESULT: runtime verification INCOMPLETE — required checks failed or could not run.\n'
    exit 1
  fi
  printf 'RESULT: all required runtime checks passed.\n'
  exit 0
}

# --- Resource tracking and cleanup --------------------------------------------
#
# Only what THIS invocation created is removed. The Compose project name is
# private to this run, so `compose down` cannot reach the real deployment.
WORK_DIR=""
VERIFY_PROJECT=""
CREATED_CONTAINERS=()

cleanup() {
  local c
  for c in ${CREATED_CONTAINERS[@]+"${CREATED_CONTAINERS[@]}"}; do
    [ -n "$c" ] && docker rm -f "$c" >/dev/null 2>&1
  done
  if [ -n "$VERIFY_PROJECT" ]; then
    docker compose -p "$VERIFY_PROJECT" -f "$COMPOSE" down \
      --remove-orphans --volumes >/dev/null 2>&1
  fi
  [ -n "$WORK_DIR" ] && rm -rf "$WORK_DIR"
  return 0
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM

# --- Prerequisites ------------------------------------------------------------
echo "== prerequisites =="

for tool in docker jq tar; do
  if command -v "$tool" >/dev/null 2>&1; then
    ok "$tool available"
  else
    blocked "$tool not installed — runtime verification cannot run"
  fi
done
[ "$BLOCK" -eq 0 ] || summary_and_exit

if docker info >/dev/null 2>&1; then
  ok "docker daemon reachable"
else
  blocked "docker daemon not reachable by $(id -un) — runtime verification cannot run"
  summary_and_exit
fi

if docker compose version >/dev/null 2>&1; then
  ok "docker compose plugin available"
else
  blocked "docker compose plugin unavailable — runtime verification cannot run"
  summary_and_exit
fi

WORK_DIR="$(mktemp -d)" || { blocked "could not create a working directory"; summary_and_exit; }

# --- Assertion helpers --------------------------------------------------------
#
# Each reads CAPTURED json. A jq failure is reported as a parse failure, never
# as a satisfied assertion.
assert_eq() { # label file filter expected
  local label="$1" file="$2" filter="$3" want="$4" got
  if ! got="$(jq -r "$filter" < "$file" 2>/dev/null)"; then
    bad "$label (inspection JSON could not be parsed)"; return
  fi
  if [ "$got" = "$want" ]; then ok "$label ($want)"
  else bad "$label: expected '$want', observed '$got'"; fi
}

assert_true() { # label file filter
  local label="$1" file="$2" filter="$3" got
  if ! got="$(jq -r "$filter" < "$file" 2>/dev/null)"; then
    bad "$label (inspection JSON could not be parsed)"; return
  fi
  case "$got" in
    true)  ok "$label" ;;
    false) bad "$label" ;;
    *)     bad "$label (expected a boolean, observed '$got')" ;;
  esac
}

# assert_empty_list: the filter must yield a joined string; empty means clean.
assert_empty_list() { # label file filter empty-message
  local label="$1" file="$2" filter="$3" got
  if ! got="$(jq -r "$filter" < "$file" 2>/dev/null)"; then
    bad "$label (inspection JSON could not be parsed)"; return
  fi
  if [ -z "$got" ]; then ok "$label"
  else bad "$label — found: $got"; fi
}

# --- Image identity -----------------------------------------------------------
echo
echo "== image identity =="

IMAGE_JSON="$WORK_DIR/image.json"
if ! docker image inspect "$IMAGE" > "$IMAGE_JSON" 2>/dev/null; then
  blocked "image '$IMAGE' could not be inspected (build it first, or set SCAMWALL_IMAGE)"
  summary_and_exit
fi
if ! IMAGE_ID="$(jq -r '.[0].Id' < "$IMAGE_JSON" 2>/dev/null)" || [ -z "$IMAGE_ID" ] || [ "$IMAGE_ID" = "null" ]; then
  blocked "image ID could not be parsed from inspection output"
  summary_and_exit
fi
ok "image '$IMAGE' resolves to $IMAGE_ID"

if [ -n "${SCAMWALL_EXPECTED_IMAGE_ID:-}" ]; then
  if [ "$IMAGE_ID" = "$SCAMWALL_EXPECTED_IMAGE_ID" ]; then
    ok "resolved image ID matches SCAMWALL_EXPECTED_IMAGE_ID"
  else
    bad "resolved image ID does not match SCAMWALL_EXPECTED_IMAGE_ID (expected $SCAMWALL_EXPECTED_IMAGE_ID)"
  fi
fi

assert_eq   "image user"            "$IMAGE_JSON" '.[0].Config.User' '65532:65532'
assert_eq   "image declares no healthcheck" "$IMAGE_JSON" '.[0].Config.Healthcheck' 'null'
assert_eq   "image exposes no ports" "$IMAGE_JSON" '(.[0].Config.ExposedPorts // {}) | length' '0'

# --- Image history: a LIMITED pattern check -----------------------------------
echo
echo "== image history (limited pattern check) =="
note "Scans build-instruction text only. It cannot see layer contents, so it is"
note "evidence against a pasted credential in a build command — NOT proof that"
note "the image filesystem contains no secret."

HISTORY_OUT="$WORK_DIR/history.txt"
if ! docker history --no-trunc --format '{{.CreatedBy}}' "$IMAGE" > "$HISTORY_OUT" 2>/dev/null; then
  bad "image history could not be read (docker history failed)"
elif [ ! -s "$HISTORY_OUT" ]; then
  bad "image history could not be read (no output)"
elif grep -qiE 'password|passwd=|BEGIN [A-Z ]*PRIVATE KEY|api[_-]?key' "$HISTORY_OUT"; then
  bad "credential pattern matched in image build instructions"
else
  ok "no credential pattern in image build instructions"
fi

# --- Image filesystem enumeration ---------------------------------------------
echo
echo "== image filesystem (enumerated paths) =="

FS_TAR="$WORK_DIR/image.tar"
FS_LIST="$WORK_DIR/image-fs.txt"
FS_OK=0

if ! FS_CID="$(docker create "$IMAGE" 2>/dev/null | tail -1)" || [ -z "${FS_CID:-}" ]; then
  bad "image filesystem could not be enumerated (docker create failed) — path absence UNPROVEN"
else
  CREATED_CONTAINERS+=("$FS_CID")
  if ! docker export "$FS_CID" > "$FS_TAR" 2>/dev/null || [ ! -s "$FS_TAR" ]; then
    bad "image filesystem could not be enumerated (docker export failed) — path absence UNPROVEN"
  elif ! tar -tf "$FS_TAR" > "$FS_LIST" 2>/dev/null || [ ! -s "$FS_LIST" ]; then
    bad "image filesystem could not be enumerated (tar listing failed) — path absence UNPROVEN"
  elif ! grep -qE '^\./?usr/local/bin/scamwall$|^usr/local/bin/scamwall$' "$FS_LIST"; then
    # Anchor: without the one file the image is known to contain, the listing is
    # not trustworthy, and every absence derived from it would pass vacuously.
    bad "filesystem listing is untrustworthy (scamwall binary absent from listing) — path absence UNPROVEN"
  else
    FS_OK=1
    ok "image filesystem enumerated ($(wc -l < "$FS_LIST") entries; scamwall binary present)"
  fi
fi

if [ "$FS_OK" -eq 1 ]; then
  # These assert that SPECIFIC PATHS are absent. They do not, and cannot, rule
  # out an executable placed under some other name.
  note "Absence below is of the ENUMERATED PATHS ONLY. An arbitrarily renamed"
  note "executable is not ruled out by these checks."
  absent_path() { # label pattern
    local label="$1" pattern="$2" hits rc
    hits="$(grep -cE "$pattern" "$FS_LIST" 2>/dev/null)"; rc=$?
    # grep -c exits 1 when the count is zero; 2 or more is a real error.
    if [ "$rc" -gt 1 ]; then bad "$label (listing could not be searched)"; return; fi
    if [ "${hits:-0}" -eq 0 ]; then ok "$label"
    else bad "$label — $hits matching path(s) present"; fi
  }
  absent_path "no shell at checked paths (sh/bash/dash/ash/zsh/ksh)" '^\./?(usr/)?s?bin/(sh|bash|dash|ash|zsh|ksh)$'
  absent_path "no busybox at checked paths"                         '^\./?(usr/)?s?bin/busybox$'
  absent_path "no package manager at checked paths"                 '^\./?(usr/)?s?bin/(apt|apt-get|dpkg|apk|yum|dnf|rpm)$'
  absent_path "no dynamic loader / libc at checked paths"           '^\./?(usr/)?lib.*/(libc|ld-linux)[-.]'
  absent_path "no /etc/passwd"                                      '^\./?etc/passwd$'
  absent_path "no /etc/shadow"                                      '^\./?etc/shadow$'
fi

# --- Deployment container -----------------------------------------------------
echo
echo "== deployment container =="

# A private project name. `compose down` in cleanup is scoped to it, so no
# pre-existing deployment container can be stopped or removed by this run.
VERIFY_PROJECT="scamwall-verify-$$"
note "private Compose project: $VERIFY_PROJECT (isolated from the deployment)"

COMPOSE_ARGS=(-p "$VERIFY_PROJECT" -f "$COMPOSE")
if [ -f "$ENV_FILE" ]; then
  # Explicit, because Compose resolves a bare .env against the current working
  # directory. Only the values needed for assertions are ever printed; the file
  # itself is never echoed.
  COMPOSE_ARGS=(-p "$VERIFY_PROJECT" --env-file "$ENV_FILE" -f "$COMPOSE")
  ok "deployment .env supplied explicitly"
else
  note "no deployment .env present; Compose defaults apply"
fi

EXPECTED_GID="65532"
if [ -f "$ENV_FILE" ]; then
  gid_line="$(grep -E '^[[:space:]]*SCAMWALL_SECRET_GID[[:space:]]*=' "$ENV_FILE" 2>/dev/null | tail -1)"
  if [ -n "$gid_line" ]; then
    gid_val="${gid_line#*=}"
    gid_val="$(printf '%s' "$gid_val" | tr -d '"'"'"' \t\r')"
    [ -n "$gid_val" ] && EXPECTED_GID="$gid_val"
  fi
fi

# Creation status is checked EXPLICITLY. Previously the status was discarded
# and the container id looked up afterwards, so a pre-existing container could
# stand in for one that was never created.
CREATE_LOG="$WORK_DIR/create.log"
if ! docker compose "${COMPOSE_ARGS[@]}" create --no-build --quiet-pull > "$CREATE_LOG" 2>&1; then
  bad "compose create failed — container assertions UNPROVEN: $(tr '\n' ' ' < "$CREATE_LOG" | cut -c1-200)"
  summary_and_exit
fi
ok "compose create succeeded (exit 0)"

if ! CID_LIST="$(docker compose "${COMPOSE_ARGS[@]}" ps -aq scamwall 2>/dev/null)"; then
  bad "created container could not be listed — container assertions UNPROVEN"
  summary_and_exit
fi
CID_COUNT="$(printf '%s\n' "$CID_LIST" | grep -c '[^[:space:]]')"
if [ "$CID_COUNT" -ne 1 ]; then
  bad "expected exactly 1 container in project $VERIFY_PROJECT, found $CID_COUNT — UNPROVEN"
  summary_and_exit
fi
CID="$(printf '%s\n' "$CID_LIST" | grep '[^[:space:]]' | tail -1)"
CREATED_CONTAINERS+=("$CID")
ok "inspection container created (not started)"

CJSON="$WORK_DIR/container.json"
if ! docker inspect "$CID" > "$CJSON" 2>/dev/null; then
  bad "container inspection failed — container assertions UNPROVEN"
  summary_and_exit
fi
if ! jq -e 'type == "array" and length == 1' < "$CJSON" >/dev/null 2>&1; then
  bad "container inspection output is not a single-element JSON array — UNPROVEN"
  summary_and_exit
fi
ok "container inspection captured and parsed"

# Identity: the inspected container must run the image we resolved above.
assert_eq "container image matches resolved image ID" "$CJSON" '.[0].Image' "$IMAGE_ID"

# The application must not have been started.
assert_eq "container is created, not running" "$CJSON" '.[0].State.Status' 'created'

echo
echo "-- identity and privileges --"
assert_eq   "container user"                "$CJSON" '.[0].Config.User' '65532:65532'
assert_eq   "supplementary group"           "$CJSON" '(.[0].HostConfig.GroupAdd // []) | join(",")' "$EXPECTED_GID"
assert_eq   "capabilities dropped"          "$CJSON" '(.[0].HostConfig.CapDrop // []) | join(",")' 'ALL'
assert_eq   "no capabilities added"         "$CJSON" '(.[0].HostConfig.CapAdd // []) | length' '0'
assert_true "not privileged"                "$CJSON" '.[0].HostConfig.Privileged == false'
assert_true "no-new-privileges set"         "$CJSON" '((.[0].HostConfig.SecurityOpt // []) | map(select(. == "no-new-privileges:true")) | length) == 1'
assert_true "no unconfined seccomp/apparmor" "$CJSON" '((.[0].HostConfig.SecurityOpt // []) | map(select(test("unconfined"))) | length) == 0'
assert_true "init process enabled"          "$CJSON" '.[0].HostConfig.Init == true'

echo
echo "-- filesystem --"
assert_true "rootfs read-only"              "$CJSON" '.[0].HostConfig.ReadonlyRootfs == true'
assert_empty_list "every mount is read-only" "$CJSON" \
  '[ .[0].Mounts[]? | select(.RW != false) | (.Destination // "?") ] | join(", ")'

# Prohibited mounts are detected through .Mounts, which covers bind mounts,
# volumes and tmpfs alike. .HostConfig.Binds only reflects one way of asking
# for a mount and misses the others entirely.
assert_empty_list "no prohibited mounts (.Mounts inspected)" "$CJSON" \
  '[ .[0].Mounts[]?
     | select(((.Source // "") | test("docker\\.sock|^/etc/pihole|^/var/lib/docker|^/var/run/docker|^/proc|^/sys|^/dev(/|$)|^/$|^/etc$|^/root|^/home$"))
              or ((.Destination // "") | test("docker\\.sock|^/etc/pihole")))
     | ((.Source // "?") + " -> " + (.Destination // "?")) ] | join("; ")'

assert_true "tmpfs /tmp has noexec" "$CJSON" '((.[0].HostConfig.Tmpfs // {})["/tmp"] // "") | test("noexec")'
assert_true "tmpfs /tmp has nosuid" "$CJSON" '((.[0].HostConfig.Tmpfs // {})["/tmp"] // "") | test("nosuid")'
assert_true "tmpfs /tmp has nodev"  "$CJSON" '((.[0].HostConfig.Tmpfs // {})["/tmp"] // "") | test("nodev")'
assert_true "tmpfs /tmp is size-bounded" "$CJSON" '((.[0].HostConfig.Tmpfs // {})["/tmp"] // "") | test("size=")'

echo
echo "-- network --"
assert_true "not on host network"    "$CJSON" '(.[0].HostConfig.NetworkMode // "") != "host"'
assert_true "not sharing a container netns" "$CJSON" '((.[0].HostConfig.NetworkMode // "") | startswith("container:")) == false'
assert_eq   "no published port bindings" "$CJSON" '(.[0].HostConfig.PortBindings // {}) | length' '0'
assert_eq   "no exposed container ports" "$CJSON" '(.[0].NetworkSettings.Ports // {}) | length' '0'

echo
echo "-- resource bounds --"
assert_eq "memory limit"      "$CJSON" '.[0].HostConfig.Memory'     '134217728'
assert_eq "memory+swap limit" "$CJSON" '.[0].HostConfig.MemorySwap' '134217728'
assert_eq "pids limit"        "$CJSON" '.[0].HostConfig.PidsLimit'  '64'
assert_eq "cpu limit"         "$CJSON" '.[0].HostConfig.NanoCpus'   '500000000'
assert_eq "restart policy"    "$CJSON" '.[0].HostConfig.RestartPolicy.Name' 'no'

summary_and_exit
