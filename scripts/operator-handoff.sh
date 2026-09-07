#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
#
# operator-handoff.sh — the executable form of docs/VERIFICATION.md section 6.5.
#
# WHY THIS IS A PROGRAM AND NOT A COPY-AND-PASTE BLOCK
#
# The previous form of section 6.5 was ~200 lines of shell for an operator to
# paste into an interactive root shell. Nothing tested it, so its defects were
# invisible: a hardcoded HEAD that the documentation commit itself invalidated,
# `exit 1` statements that would close the operator's shell, a status read
# through `tee` rather than from Docker, a claim that a step read no password
# beside an expected output line showing the password being read, and a
# project-wide `compose down --remove-orphans` that deletes by name.
#
# It is one program now, with scripts/tests/operator-handoff-test.sh driving it
# against a scripted fake Docker and a scripted fake git. The documentation
# wraps it rather than duplicating it.
#
# WHAT IT DOES NOT DO
#
#   * It never pushes, merges, tags, releases, publishes, edits the deployment,
#     enables enforcement, or runs `sync` against the appliance.
#   * It never resets, checks out, or otherwise moves the working tree. If HEAD
#     is not the commit the operator named, it REFUSES; it does not "fix" it.
#   * It never adds a git safe.directory exception. Repository metadata is read
#     as the account that owns the tree.
#   * Step D authenticates to the live appliance and is refused unless the
#     operator passes --authorise-authenticated-read on that specific step.
#
# Usage:
#   operator-handoff.sh preflight --expected-commit <40-hex-sha> [--work-dir DIR]
#   operator-handoff.sh build    --work-dir DIR [--version-label LABEL]
#   operator-handoff.sh probe    --work-dir DIR
#   operator-handoff.sh secret   --work-dir DIR
#   operator-handoff.sh status   --work-dir DIR --authorise-authenticated-read
#   operator-handoff.sh closeout --work-dir DIR [--verify-secret-integrity]
#
# The steps map onto section 6.5 as: preflight = step 0, build = A, probe = B,
# secret = C, status = D, closeout = Z.
#
# Exit status: 0 only when every check of the step actually ran and passed AND
# every required cleanup completed.

set -uo pipefail

# --- Repository root, without git ---------------------------------------------
#
# Same reasoning as container-runtime-verify.sh: this runs as the operator, in a
# tree owned by the service account, and git would refuse on dubious ownership.
# The location is derived from this script and then CONFIRMED by the files the
# tree must contain, so a wrong directory is a refusal rather than a report
# about something else.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)" || {
  printf 'fatal: could not resolve this script'\''s directory\n' >&2; exit 2; }
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd -P)" || {
  printf 'fatal: could not resolve the repository root\n' >&2; exit 2; }

COMPOSE_FILE="$REPO_ROOT/deploy/compose/compose.yaml"
ENV_FILE="$REPO_ROOT/deploy/compose/.env"
DOCKERFILE="$REPO_ROOT/container/Dockerfile"
VERIFIER="$REPO_ROOT/scripts/container-runtime-verify.sh"
SERVICE="scamwall"
TAG="scamwall:local"

# Container-side paths. These are fixed by the image and by config.go; they are
# never derived from the environment, because a redirectable credential path
# turns a configuration mistake into a disclosure.
CT_SECRET_PATH="/run/secrets/pihole_app_password"
CT_CA="/etc/scamwall/certs/pihole-ca.crt"
CT_CONFIG="/etc/scamwall/config.json"
CT_FEED="/etc/scamwall/feed.json"

for required in "$COMPOSE_FILE" "$DOCKERFILE" "$VERIFIER"; do
  [ -f "$required" ] || {
    printf 'fatal: expected file not found: %s\n' "$required" >&2
    printf 'fatal: %s does not look like a ScamWall checkout\n' "$REPO_ROOT" >&2
    exit 2; }
done

PASS=0; FAIL=0; BLOCK=0; CLEANUP_PROBLEMS=0
ok()      { printf '\033[32mPASS\033[0m    %s\n' "$1"; PASS=$((PASS + 1)); }
bad()     { printf '\033[31mFAIL\033[0m    %s\n' "$1"; FAIL=$((FAIL + 1)); }
blocked() { printf '\033[31mBLOCKED\033[0m %s\n' "$1"; BLOCK=$((BLOCK + 1)); }
note()    { printf '        %s\n' "$1"; }

# refuse — a precondition failed. Nothing has been created, so there is nothing
# to clean up and no verdict to compute.
#
# It exits the PROGRAM. That is the point of making this a program: the
# superseded procedure put bare `exit 1` into a block the operator was told to
# paste into their own interactive shell, where it would close the shell they
# were working in.
refuse() {
  printf '\033[31mREFUSING\033[0m %s\n' "$1" >&2
  exit 2
}

# --- Resource tracking and cleanup --------------------------------------------
#
# The reviewed implementation, shared with container-runtime-verify.sh. It is
# sourced BEFORE anything can create a resource, so there is no window in which
# a container exists and no cleanup handler does.
#
# CLEANUP_WORK_DIR=0: the work directory holds this step's sanitized logs, and
# they are the evidence the operator has to return. Erasing them at the end of
# a FAILING run would destroy the diagnosis. The path is reported instead, with
# the command to remove it.
CLEANUP_WORK_DIR=0
RESOURCE_LIB="$SCRIPT_DIR/lib/docker-resources.sh"
[ -f "$RESOURCE_LIB" ] ||
  refuse "resource-tracking library not found: $RESOURCE_LIB — refusing to create Docker resources with no cleanup implementation"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/docker-resources.sh
. "$RESOURCE_LIB" || refuse "the resource-tracking library could not be sourced: $RESOURCE_LIB"

# --- Diagnostics --------------------------------------------------------------
#
# Captured output is passed through the same sanitizer the gate suite uses, and
# is NOT printed at all if that sanitizer is missing or fails. An unreadable
# message costs a rerun; a leaked one cannot be taken back.
SANITIZER="$SCRIPT_DIR/gate-diagnostics.sh"
DIAG_MAX_LINES=120
print_diagnostic() { # <captured-file>
  local file="$1" clean n
  if [ ! -f "$file" ] || [ ! -s "$file" ]; then
    note "no output was captured from that command"
    return 0
  fi
  if [ ! -f "$SANITIZER" ]; then
    note "the captured output is NOT printed: $SANITIZER is absent, so it could not be sanitized"
    return 0
  fi
  clean="$(mktemp)" || { note "the captured output is NOT printed: no temporary file could be created"; return 0; }
  chmod 600 "$clean" 2>/dev/null || true
  if ! bash "$SANITIZER" --sanitize < "$file" > "$clean" 2>/dev/null; then
    note "the captured output is NOT printed: the sanitizer failed"
    rm -f "$clean"
    return 0
  fi
  n="$(wc -l < "$clean" 2>/dev/null)" || n=0
  if [ "$n" -gt "$DIAG_MAX_LINES" ]; then
    note "showing the last $DIAG_MAX_LINES of $n sanitized lines; the whole capture is in the work directory"
    tail -n "$DIAG_MAX_LINES" "$clean" | sed 's/^/        | /'
  else
    sed 's/^/        | /' "$clean"
  fi
  rm -f "$clean"
  return 0
}

# --- Checked search -----------------------------------------------------------
#
# Three outcomes, never two. grep exit 2 means grep could not do its job, and
# reading that as "no match" is how a search that never ran becomes a clean
# result. The file form is deliberate: `producer | grep -q` lets grep exit at
# the first match and the producer take SIGPIPE, which under pipefail turns a
# match into a failure (docs/VERIFICATION.md 4.1).
search_file() { # pattern file -> 0 matched, 1 no match, 2 could not search
  local pattern="$1" file="$2" rc
  [ -f "$file" ] && [ -r "$file" ] || return 2
  grep -qE -- "$pattern" "$file"
  rc=$?
  case "$rc" in 0|1) return "$rc" ;; *) return 2 ;; esac
}

# expect_in_file <label> <pattern> <file>
expect_in_file() {
  search_file "$2" "$3"
  case $? in
    0) ok "$1" ;;
    1) bad "$1" ;;
    *) blocked "$1 (the capture could not be searched — result UNPROVEN)" ;;
  esac
}

# expect_absent_from_file <label> <pattern> <file>
expect_absent_from_file() {
  search_file "$2" "$3"
  case $? in
    0) bad "$1 — the pattern is present" ;;
    1) ok "$1" ;;
    *) blocked "$1 (the capture could not be searched — result UNPROVEN)" ;;
  esac
}

# --- State carried between steps ----------------------------------------------
#
# Each step is a separate invocation, so the identities established by an
# earlier one are written to a file in the private work directory rather than
# left in the operator's environment, where an unrelated export could collide
# with them.
WORK=""
STATE=""

state_put() { # key value
  printf '%s=%s\n' "$1" "$2" >> "$STATE" ||
    refuse "the state file could not be written: $STATE"
}

state_get() { # key -> prints value, returns 1 if absent
  local line
  line="$(grep -m1 -E "^$1=" "$STATE" 2>/dev/null)" || return 1
  [ -n "$line" ] || return 1
  printf '%s' "${line#*=}"
}

state_require() { # key -> prints value or refuses
  local v
  v="$(state_get "$1")" ||
    refuse "$1 is not recorded in $STATE — run the earlier step first"
  [ -n "$v" ] || refuse "$1 is recorded empty in $STATE"
  printf '%s' "$v"
}

# --- Environment hygiene ------------------------------------------------------
#
# CI passes throwaway fixture paths through these variables. Compose gives the
# shell environment precedence over --env-file, so one still exported here
# would silently redirect a bind SOURCE and every step would verify a fixture
# while reporting the deployment.
#
# The VALUE is never echoed. It is a path, and a path in an operator's evidence
# log is an unnecessary disclosure; naming the variable is enough to fix it.
OVERRIDABLE_VARS=(SCAMWALL_CA_FILE SCAMWALL_SECRET_FILE SCAMWALL_CONFIG SCAMWALL_FEED
                  SCAMWALL_IMAGE SCAMWALL_EXPECTED_IMAGE_ID SCAMWALL_VERSION
                  SCAMWALL_COMMIT SCAMWALL_BUILD_DATE PIHOLE_HOST_IP SCAMWALL_SECRET_GID)
assert_no_overrides() {
  local v set_vars=""
  for v in "${OVERRIDABLE_VARS[@]}"; do
    if [ -n "${!v:-}" ]; then set_vars="${set_vars}${set_vars:+, }$v"; fi
  done
  if [ -n "$set_vars" ]; then
    refuse "these variables are set in this environment and would redirect the run: $set_vars (values not shown)"
  fi
  ok "no fixture-path or build-metadata override is set in this environment"
}

# --- Repository identity, read as the tree's owner ----------------------------
#
# git is run as the account that OWNS the tree. Running it as root in a tree
# owned by someone else hits git's dubious-ownership refusal, and the fix for
# that — a safe.directory exception — is a permanent widening for a momentary
# convenience.
REPO_OWNER=""
git_as_owner() { # <git args...>
  if [ "$(id -un)" = "$REPO_OWNER" ]; then
    git -C "$REPO_ROOT" "$@"
  else
    sudo -n -u "$REPO_OWNER" git -C "$REPO_ROOT" "$@"
  fi
}

resolve_repo_owner() {
  REPO_OWNER="$(stat -c '%U' "$REPO_ROOT" 2>/dev/null)" ||
    refuse "the owner of $REPO_ROOT could not be determined"
  [ -n "$REPO_OWNER" ] && [ "$REPO_OWNER" != "UNKNOWN" ] ||
    refuse "the owner of $REPO_ROOT could not be determined"
}

# assert_source_identity <expected-sha> — HEAD is what the operator named, and
# the tree is clean.
#
# Every step re-checks this. Passing preflight does not freeze the tree, and a
# build started against a commit that moved between steps would name the wrong
# source in its own evidence.
assert_source_identity() {
  local expected="$1" head dirty
  head="$(git_as_owner rev-parse HEAD 2>/dev/null)" ||
    refuse "repository metadata could not be read as $REPO_OWNER (git failed); source identity is UNKNOWN"
  [ -n "$head" ] ||
    refuse "git produced no HEAD; source identity is UNKNOWN"
  if [ "$head" != "$expected" ]; then
    refuse "HEAD is $head but the expected checkout is $expected — check out the expected commit yourself; this program will not move the tree"
  fi
  ok "HEAD is the expected checkout $expected"

  # `status --porcelain` exits 0 with output when the tree is dirty, so "git
  # failed" and "the tree is dirty" are two different facts and both are
  # checked. Collapsing them would report an unreadable tree as a clean one.
  if ! dirty="$(git_as_owner status --porcelain 2>/dev/null)"; then
    refuse "the working tree state could not be read as $REPO_OWNER; attributability is UNKNOWN"
  fi
  if [ -n "$dirty" ]; then
    printf '%s\n' "$dirty" | sed 's/^/        /'
    refuse "the working tree is not clean — an artifact built from it is attributable to no commit"
  fi
  ok "the working tree is clean"
}

# --- Private working directory ------------------------------------------------
#
# mktemp -d, then the mode is SET and then READ BACK. chmod can fail, and a
# world-readable directory holding a build log is exactly the kind of thing
# that is assumed rather than checked.
create_work_dir() {
  local requested="${1:-}" mode
  if [ -n "$requested" ]; then
    mkdir -p -- "$requested" || refuse "the requested work directory could not be created: $requested"
    WORK="$(cd -- "$requested" >/dev/null 2>&1 && pwd -P)" ||
      refuse "the requested work directory could not be resolved: $requested"
  else
    WORK="$(mktemp -d)" || refuse "a private work directory could not be created"
  fi
  chmod 700 -- "$WORK" || refuse "the work directory's mode could not be set: $WORK"
  mode="$(stat -c '%a' -- "$WORK" 2>/dev/null)" ||
    refuse "the work directory's mode could not be read back: $WORK"
  [ "$mode" = "700" ] ||
    refuse "the work directory is mode $mode, not 700: $WORK"
  ok "private work directory created, mode 700"
  note "work directory: $WORK"
}

open_work_dir() { # <dir>
  local mode
  [ -n "$1" ] || refuse "--work-dir is required for this step"
  WORK="$(cd -- "$1" >/dev/null 2>&1 && pwd -P)" ||
    refuse "the work directory does not exist or cannot be entered: $1"
  mode="$(stat -c '%a' -- "$WORK" 2>/dev/null)" ||
    refuse "the work directory's mode could not be read: $WORK"
  [ "$mode" = "700" ] ||
    refuse "the work directory is mode $mode, not 700: $WORK — refusing to write evidence into it"
  STATE="$WORK/state.env"
  [ -f "$STATE" ] || refuse "no state file in $WORK — run the preflight step first"
}

# --- Log capture, kept distinct from the command's own status -----------------
#
# The command's status is read from the COMMAND, never through `tee` or a
# pipeline, and the capture's usability is a SEPARATE result. A build that
# succeeded and a log that was not written are two different facts; the
# superseded procedure conflated them by reading ${PIPESTATUS[0]} out of a tee
# pipeline and never checking that anything landed in the file.
LAST_RC=0
capture_run() { # <logfile> <command...>
  local log="$1"; shift
  : > "$log" || { blocked "the capture file could not be created: $log"; LAST_RC=125; return 1; }
  chmod 600 -- "$log" 2>/dev/null || true
  "$@" > "$log" 2>&1
  LAST_RC=$?
  return 0
}

assert_capture_usable() { # <label> <logfile>
  if [ ! -s "$2" ]; then
    blocked "$1: nothing was captured, so the output cannot be checked (this is separate from the command's exit status)"
    return 1
  fi
  ok "$1: output captured"
  return 0
}

# --- Verdict ------------------------------------------------------------------
summary_and_exit() {
  run_cleanup
  printf '\n%d passed, %d failed, %d blocked, %d cleanup problem(s)\n' \
    "$PASS" "$FAIL" "$BLOCK" "$CLEANUP_PROBLEMS"
  if [ -n "$WORK" ]; then
    printf '\nEvidence and sanitized logs remain in: %s (mode 700)\n' "$WORK"
    printf 'Remove them with:  rm -rf -- %s\n' "$WORK"
    printf 'Do that only after the recorded values have been copied out.\n'
  fi
  if [ "$FAIL" -gt 0 ] || [ "$BLOCK" -gt 0 ]; then
    printf 'RESULT: step INCOMPLETE — required checks failed or could not run.\n'
    exit 1
  fi
  if [ "$CLEANUP_PROBLEMS" -gt 0 ]; then
    printf 'RESULT: checks passed but REQUIRED CLEANUP FAILED — resources listed above remain.\n'
    exit 1
  fi
  printf 'RESULT: every check in this step ran and passed, and cleanup completed.\n'
  exit 0
}

# shellcheck disable=SC2329  # reached indirectly via trap
on_exit() {
  local rc=$?
  run_cleanup
  if [ "$CLEANUP_PROBLEMS" -gt 0 ] && [ "$rc" -eq 0 ]; then
    printf 'RESULT: REQUIRED CLEANUP FAILED — exit status forced nonzero.\n'
    exit 1
  fi
  exit "$rc"
}

# shellcheck disable=SC2329  # reached indirectly via trap
on_signal() { # name status
  printf '\ninterrupted by %s — cleaning up before exiting\n' "$1"
  run_cleanup
  # `exit` re-enters on_exit, where run_cleanup is a no-op: the destructive
  # operations happen exactly once however many traps fire.
  exit "$2"
}

# Installed here, before any step body runs and therefore before anything can
# create a resource.
trap on_exit EXIT
trap 'on_signal INT 130' INT
trap 'on_signal TERM 143' TERM

# --- Invocation identity ------------------------------------------------------
#
# Unpredictable, and CHECKED. A PID is small, reused and predictable; an
# identifier that silently came out empty would make every label match
# everything.
begin_invocation() {
  INVOCATION="$(head -c 16 /dev/urandom 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')" ||
    refuse "an unpredictable invocation identifier could not be generated"
  [ "${#INVOCATION}" -eq 32 ] ||
    refuse "the invocation identifier is ${#INVOCATION} characters, not 32 — refusing to create unattributable resources"
  VERIFY_PROJECT="scamwall-handoff-${INVOCATION:0:16}"
  ok "invocation identifier established (unpredictable, 32 hex characters)"

  # Anything already carrying this label is a collision: nothing is created and
  # nothing is deleted.
  PRE_CONTAINERS="$(label_query container "$OWN_LABEL=$INVOCATION")" ||
    refuse "pre-existing containers carrying this invocation's label could not be enumerated"
  PRE_NETWORKS="$(label_query network "$OWN_LABEL=$INVOCATION")" ||
    refuse "pre-existing networks carrying this invocation's label could not be enumerated"
  PRE_VOLUMES="$(label_query volume "$OWN_LABEL=$INVOCATION")" ||
    refuse "pre-existing volumes carrying this invocation's label could not be enumerated"
  if [ -n "$PRE_CONTAINERS$PRE_NETWORKS$PRE_VOLUMES" ]; then
    refuse "resources already carry this invocation's ownership label — refusing to create or delete anything"
  fi
  ok "no pre-existing resource carries this invocation's ownership label"
}

require_docker() {
  command -v docker >/dev/null 2>&1 || refuse "docker is not on PATH"
  command -v jq >/dev/null 2>&1 || refuse "jq is required to read Docker and Compose output"
  docker info >/dev/null 2>&1 || refuse "the Docker daemon is not reachable by $(id -un)"
}

# --- Resolved deployment configuration ----------------------------------------
#
# Derived from `docker compose config`, which performs Compose's own
# interpolation. Re-deriving it by grepping .env reimplements Compose's
# precedence rules and gets them wrong in exactly the cases that matter.
CONFIG_JSON=""
COMPOSE_ENV_ARGS=()

resolve_deployment_config() {
  local err
  CONFIG_JSON="$WORK/compose-config.json"
  err="$WORK/compose-config.err"
  COMPOSE_ENV_ARGS=()
  if [ -f "$ENV_FILE" ]; then
    # Explicit: Compose resolves a bare .env against the CURRENT directory, not
    # against the compose file's directory.
    COMPOSE_ENV_ARGS=(--env-file "$ENV_FILE")
  fi
  if ! docker compose "${COMPOSE_ENV_ARGS[@]}" -f "$COMPOSE_FILE" config --format json > "$CONFIG_JSON" 2> "$err"; then
    blocked "the deployment configuration could not be resolved"
    print_diagnostic "$err"
    summary_and_exit
  fi
  if ! jq -e 'type == "object"' < "$CONFIG_JSON" >/dev/null 2>&1; then
    blocked "the resolved configuration is not a JSON object — deployment settings UNPROVEN"
    summary_and_exit
  fi
  ok "deployment configuration resolved and parsed"
  note "the resolved configuration stays in the work directory and is never printed"
}

cfg() { # <jq filter> -> prints, returns 1 if the read failed
  jq -er "$1" < "$CONFIG_JSON" 2>/dev/null
}

# assert_deployment_sources — the bind sources and the secret source are the
# real deployment's, not a test fixture's.
#
# assert_no_overrides catches an exported variable. This catches the same
# redirection arriving any other way — a committed .env, a default that moved,
# a fixture path baked into the file — by checking the RESOLVED result rather
# than the mechanism.
EXPECTED_CA_SOURCE="/etc/scamwall/certs/pihole-ca.crt"
EXPECTED_SECRET_SOURCE="/etc/scamwall/secrets/pihole_app_password"
assert_deployment_sources() {
  # cred_src, not `secret`: scripts/secret-scan.sh flags an assignment whose
  # key reads as a credential name, and it is right to — a scanner that
  # exempted this file would be exempting the one that handles the real
  # credential path. The name says what the value is: a source PATH.
  local ca cred_src
  ca="$(cfg ".services.\"$SERVICE\".volumes[] | select(.target == \"$CT_CA\") | .source")" || {
    bad "the CA bind source could not be read from the resolved configuration"; return 1; }
  cred_src="$(cfg '.secrets.pihole_app_password.file')" || {
    bad "the credential source could not be read from the resolved configuration"; return 1; }
  if [ "$ca" = "$EXPECTED_CA_SOURCE" ]; then
    ok "the CA bind source is the deployment's ($EXPECTED_CA_SOURCE)"
  else
    bad "the CA bind source is not the deployment's — this run would report on a fixture"
    return 1
  fi
  if [ "$cred_src" = "$EXPECTED_SECRET_SOURCE" ]; then
    ok "the credential source is the deployment's ($EXPECTED_SECRET_SOURCE)"
  else
    bad "the credential source is not the deployment's — this run would report on a fixture"
    return 1
  fi
  return 0
}

# --- Probe container construction ---------------------------------------------
#
# `docker compose run` cannot do what steps B and C require. It cannot pin the
# image (compose.yaml names the mutable tag `scamwall:local`), it cannot REMOVE
# the secret mount for a credential-free probe, and it creates project
# resources whose attribution then has to be reconstructed. So the probe
# containers are created explicitly, with settings DERIVED from the resolved
# deployment configuration and with the image pinned to the immutable ID that
# step A verified.
#
# The deliberate differences from the deployment, both documented in section
# 6.5, are: the probe attaches to the default bridge rather than a Compose
# project network, and step B mounts no secret at all.
PROBE_ARGS=()
build_probe_args() { # <image-id> <network-mode> <with-secret: yes|no>
  local image="$1" network="$2" with_secret="$3"
  local user group_add hosts pids mem cpus src ro
  PROBE_ARGS=()

  user="$(cfg ".services.\"$SERVICE\".user")" || { bad "the container user could not be read"; return 1; }
  [ "$user" = "65532:65532" ] || { bad "the resolved container user is '$user', not 65532:65532"; return 1; }
  PROBE_ARGS+=(--user "$user")

  # The supplementary group is the whole reason a non-root process can read the
  # password without it ever becoming world-readable (FINDING-29).
  group_add="$(cfg ".services.\"$SERVICE\".group_add[0] | tostring")" || {
    bad "the supplementary group could not be read from the resolved configuration"; return 1; }
  [ -n "$group_add" ] || { bad "the supplementary group resolved empty"; return 1; }
  PROBE_ARGS+=(--group-add "$group_add")

  PROBE_ARGS+=(--read-only --cap-drop ALL --security-opt no-new-privileges:true)
  PROBE_ARGS+=(--tmpfs "/tmp:rw,noexec,nosuid,nodev,size=16m")

  pids="$(cfg ".services.\"$SERVICE\".pids_limit | tostring")" || pids=""
  [ -n "$pids" ] && PROBE_ARGS+=(--pids-limit "$pids")
  mem="$(cfg ".services.\"$SERVICE\".mem_limit | tostring")" || mem=""
  [ -n "$mem" ] && PROBE_ARGS+=(--memory "$mem")
  cpus="$(cfg ".services.\"$SERVICE\".cpus | tostring")" || cpus=""
  [ -n "$cpus" ] && PROBE_ARGS+=(--cpus "$cpus")

  # The hostname mapping is the deployment's, read through Compose's own
  # interpolation rather than re-derived from .env.
  # Compose renders extra_hosts as an ARRAY of "name=address" in current
  # versions and as an OBJECT in older ones. Both are handled, and the array
  # form's `=` is normalised to the `:` that `docker --add-host` takes. The
  # canned fixture in the test suite is cross-checked against the real Compose
  # CLI precisely so a rendering change like this is caught here rather than
  # against the appliance.
  hosts="$(cfg ".services.\"$SERVICE\".extra_hosts | if type == \"object\" then (to_entries | map(\"\(.key):\(.value)\") | .[]) elif type == \"array\" then (.[] | sub(\"=\"; \":\")) else empty end")" || hosts=""
  if [ -z "$hosts" ]; then
    bad "the pi.hole address mapping could not be read from the resolved configuration"
    return 1
  fi
  local h
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    PROBE_ARGS+=(--add-host "$h")
  done <<< "$hosts"

  # The three read-only binds, by their fixed container-side destinations.
  local target
  for target in "$CT_CA" "$CT_CONFIG" "$CT_FEED"; do
    src="$(cfg ".services.\"$SERVICE\".volumes[] | select(.target == \"$target\") | .source")" || {
      bad "the bind source for $target could not be read"; return 1; }
    [ -n "$src" ] || { bad "the bind source for $target resolved empty"; return 1; }
    ro="$(cfg ".services.\"$SERVICE\".volumes[] | select(.target == \"$target\") | .read_only | tostring")" || ro="false"
    [ "$ro" = "true" ] || { bad "the mount at $target is not read-only in the resolved configuration"; return 1; }
    PROBE_ARGS+=(--mount "type=bind,source=$src,target=$target,readonly")
  done

  if [ "$with_secret" = "yes" ]; then
    src="$(cfg '.secrets.pihole_app_password.file')" || {
      bad "the secret source could not be read"; return 1; }
    [ -n "$src" ] || { bad "the secret source resolved empty"; return 1; }
    PROBE_ARGS+=(--mount "type=bind,source=$src,target=$CT_SECRET_PATH,readonly")
  fi

  PROBE_ARGS+=(--network "$network")
  PROBE_ARGS+=(--label "$OWN_LABEL=$INVOCATION")
  PROBE_ARGS+=(--label "$PROJECT_LABEL=$VERIFY_PROJECT")
  PROBE_ARGS+=("$image")
  return 0
}

# create_probe <image-id> <label> <docker create args...> — creates, records the
# id for cleanup, and verifies the created container's image identity BEFORE it
# is started.
PROBE_CID=""
create_probe() { # <expected-image-id> <label> <args...>
  local expected="$1" label="$2"; shift 2
  local err actual
  PROBE_CID=""
  err="$WORK/create.err"
  RESOURCES_POSSIBLY_CREATED=1
  PROBE_CID="$(docker create "$@" 2>"$err")" || {
    bad "$label: the container could not be created"
    print_diagnostic "$err"
    return 1; }
  [ -n "$PROBE_CID" ] || { bad "$label: docker create produced no container id"; return 1; }
  CREATED_CONTAINERS+=("$PROBE_CID")

  # The image is re-read FROM THE CREATED CONTAINER. Resolving a tag and then
  # trusting that the container got that image is exactly the substitution the
  # tag-movement case exists to catch.
  actual="$(docker inspect -f '{{.Image}}' "$PROBE_CID" 2>/dev/null)" || {
    bad "$label: the created container's image could not be read — identity UNPROVEN"; return 1; }
  if [ "$actual" != "$expected" ]; then
    bad "$label: the created container runs image $actual, not the verified $expected"
    return 1
  fi
  ok "$label: the created container runs exactly the image verified in step A"
  return 0
}

# assert_probe_mounts <label> <must-not-contain destination>
assert_no_mount() { # <label> <destination>
  local dests
  dests="$(docker inspect -f '{{range .Mounts}}{{.Destination}}{{"\n"}}{{end}}' "$PROBE_CID" 2>/dev/null)" || {
    blocked "$1 (the container's mounts could not be listed — result UNPROVEN)"; return 1; }
  if in_list "$2" "$dests"; then
    bad "$1 — $2 IS mounted"
    return 1
  fi
  ok "$1"
  return 0
}

assert_network_mode() { # <label> <expected>
  local mode
  mode="$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$PROBE_CID" 2>/dev/null)" || {
    blocked "$1 (the container's network mode could not be read — result UNPROVEN)"; return 1; }
  if [ "$mode" = "$2" ]; then ok "$1 ($2)"; return 0; fi
  bad "$1: network mode is '$mode', expected '$2'"
  return 1
}

# ==============================================================================
# Steps
# ==============================================================================

step_preflight() { # <expected-commit> <requested work dir>
  local expected="$1"
  printf '== step 0: preflight ==\n'
  case "$expected" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
    *) refuse "--expected-commit must be a full 40-character lowercase hex object name" ;;
  esac
  assert_no_overrides
  resolve_repo_owner
  ok "repository metadata will be read as $REPO_OWNER (no safe.directory exception is added)"
  assert_source_identity "$expected"
  create_work_dir "$2"
  STATE="$WORK/state.env"
  : > "$STATE" || refuse "the state file could not be created: $STATE"
  chmod 600 -- "$STATE" || refuse "the state file's mode could not be set: $STATE"
  state_put EXPECTED_COMMIT "$expected"
  state_put REPO_ROOT "$REPO_ROOT"
  state_put REPO_OWNER "$REPO_OWNER"
  ok "source and expected-checkout identity recorded for the later steps"
  note "pass --work-dir $WORK to every following step"
  summary_and_exit
}

step_build() { # step A
  local expected image prior after version build_date
  printf '== step A: build the candidate and verify the deployment against it ==\n'
  assert_no_overrides
  resolve_repo_owner
  expected="$(state_require EXPECTED_COMMIT)"
  assert_source_identity "$expected"
  require_docker
  begin_invocation

  version="${VERSION_LABEL:-dev}"
  # A build date is recorded so the artifact carries one. It is generated here
  # rather than being left at the Dockerfile's "unknown" default.
  build_date="$(date -u +%Y-%m-%dT%H:%M:%SZ)" || {
    blocked "a build date could not be generated"; summary_and_exit; }

  # What holds the tag now. Recorded for the record, and NOT asserted against
  # the post-build id: see below.
  prior="$(docker image inspect -f '{{.Id}}' "$TAG" 2>/dev/null)" || prior="none"
  note "before this build, $TAG = $prior"

  # --no-cache and --pull are used, and here is what they are and are not for.
  #
  # NOT for source identity: a cached layer is keyed on the build context, so
  # cache reuse means the inputs were identical, not that a different source
  # was built. The claim that "a layer cached from an earlier candidate would
  # produce an image that is not this source" was wrong.
  #
  # They are used because the two in-build assertions are RUN steps. A cached
  # RUN step does not execute, so its assertion produces no evidence for THIS
  # collection — the step would be reported CACHED and prove nothing. --pull
  # additionally re-resolves the digest-pinned base image.
  #
  # --progress=plain is required because the step output below is parsed. The
  # default TTY progress rewrites lines in place and is not parseable.
  printf '\n-- build --\n'
  capture_run "$WORK/build.log" \
    docker build --no-cache --pull --progress=plain \
      --build-arg "VERSION=$version" \
      --build-arg "COMMIT=$expected" \
      --build-arg "BUILD_DATE=$build_date" \
      -f "$DOCKERFILE" -t "$TAG" "$REPO_ROOT"
  local build_rc=$LAST_RC
  printf 'BUILD exit=%d\n' "$build_rc"
  # The two are separate results. A build that succeeded with no captured log
  # is not a failed build, and a failed build whose log was captured is not a
  # capture problem.
  assert_capture_usable "build log" "$WORK/build.log"
  if [ "$build_rc" -ne 0 ]; then
    bad "the image build failed (exit $build_rc)"
    print_diagnostic "$WORK/build.log"
    note "the tag $TAG may still point at a STALE image from an earlier build; nothing below is run against it"
    summary_and_exit
  fi
  ok "the image build succeeded"

  # -- the two in-build assertions, per step, from the build's own output ------
  printf '\n-- in-build assertions --\n'
  assert_build_step "ELF linkage assertion (SW-P1-20)" 'elfcheck'
  assert_build_step "enforcement-absent assertion"     '/out/scamwall version'

  # -- image identity ---------------------------------------------------------
  printf '\n-- image identity --\n'
  image="$(docker image inspect -f '{{.Id}}' "$TAG" 2>/dev/null)" || {
    bad "the built image could not be resolved to an immutable id"; summary_and_exit; }
  case "$image" in
    sha256:[0-9a-f]*) [ "${#image}" -eq 71 ] || { bad "the resolved image id is malformed"; summary_and_exit; } ;;
    *) bad "the resolved image id is not a sha256 digest: $image"; summary_and_exit ;;
  esac
  ok "the image resolved to an immutable id"
  note "IMAGE_ID=$image"
  note "source commit $expected was built into that image; both identities are recorded together"

  # The assertion that the new id must DIFFER from the prior one has been
  # removed. It was wrong: an image id is the digest of its content, so a build
  # producing identical output legitimately keeps the same id, and a
  # reproducible build is a goal here rather than a fault. What matters is that
  # the tag resolves, that the resolved id is used from here on, and that the
  # binary inside it reports this commit — all of which are checked.
  if [ "$image" = "$prior" ]; then
    note "the image id is unchanged from before the build; identical inputs produce an identical image, which is not a fault"
  fi

  # -- what the binary itself says --------------------------------------------
  #
  # The build log is the builder's account of the build. This asks the artifact.
  # It runs with no network, no mounts and no credential: `version` needs none
  # of them, so anything it did need would be a finding.
  printf '\n-- the built binary'\''s own report --\n'
  if create_probe "$image" "version probe" \
      --network none --user 65532:65532 --read-only --cap-drop ALL \
      --security-opt no-new-privileges:true \
      --label "$OWN_LABEL=$INVOCATION" --label "$PROJECT_LABEL=$VERIFY_PROJECT" \
      "$image" version; then
    assert_no_mount "the version probe mounts no credential" "$CT_SECRET_PATH"
    capture_run "$WORK/version.log" docker start -a "$PROBE_CID"
    printf 'VERSION exit=%d\n' "$LAST_RC"
    if [ "$LAST_RC" -ne 0 ]; then
      bad "the built binary did not run"
      print_diagnostic "$WORK/version.log"
    elif assert_capture_usable "version output" "$WORK/version.log"; then
      expect_in_file "the binary reports the expected commit $expected" \
        "^commit[[:space:]]+$expected\$" "$WORK/version.log"
      expect_in_file "the binary reports enforcement as NOT compiled in" \
        '^enforcement compiled in[[:space:]]+false$' "$WORK/version.log"
    fi
  fi

  # -- the tag may have moved under us ----------------------------------------
  after="$(docker image inspect -f '{{.Id}}' "$TAG" 2>/dev/null)" || after=""
  if [ -z "$after" ]; then
    blocked "$TAG could not be re-resolved, so tag movement could not be ruled out"
  elif [ "$after" != "$image" ]; then
    bad "$TAG now points at $after, not the image verified here ($image) — something rebuilt or retagged it during this step"
  else
    ok "$TAG still points at the verified image"
  fi

  # -- the deployment, pinned to exactly that image ---------------------------
  #
  # SCAMWALL_EXPECTED_IMAGE_ID makes the verifier refuse if what it resolves is
  # not what this step verified, so a tag moving between the two programs is a
  # refusal rather than a silent substitution.
  printf '\n-- deployment verification, pinned to the verified image --\n'
  capture_run "$WORK/verify.log" \
    env SCAMWALL_IMAGE="$image" SCAMWALL_EXPECTED_IMAGE_ID="$image" \
        bash "$VERIFIER"
  printf 'VERIFY exit=%d\n' "$LAST_RC"
  if [ "$LAST_RC" -eq 0 ]; then
    ok "the runtime verifier passed against the verified image"
  else
    bad "the runtime verifier did not pass (exit $LAST_RC)"
    print_diagnostic "$WORK/verify.log"
  fi
  assert_capture_usable "runtime verifier log" "$WORK/verify.log"
  # The FINDING-29 line is the evidence this renewal exists to produce.
  expect_in_file "the password-readability judgement was evaluated (FINDING-29)" \
    'the application password would be readable by the container identity' "$WORK/verify.log"

  state_put IMAGE_ID "$image"
  state_put BUILD_COMMIT "$expected"
  state_put BUILD_DATE "$build_date"
  summary_and_exit
}

# assert_build_step <label> <substring of the RUN command>
#
# Matched per STEP, not by grepping the whole log for a string. A build log
# that merely CONTAINS the text of an assertion proves nothing: the text is in
# the Dockerfile, so it appears in the log whether the step executed or was
# reused from cache. The step number is found from its header line and then the
# lines belonging to that step are examined for a CACHED marker.
assert_build_step() {
  local label="$1" needle="$2" n steps
  n="$(sed -n "s|^#\([0-9][0-9]*\) \[[^]]*\] RUN .*${needle}.*|\1|p" "$WORK/build.log" 2>/dev/null | head -1)"
  if [ -z "$n" ]; then
    bad "$label: no build step matched \"$needle\" — the assertion cannot be shown to have run"
    note "read $WORK/build.log in full"
    return 1
  fi
  steps="$(grep -E "^#${n}( |\$)" "$WORK/build.log" 2>/dev/null)"
  case $? in
    0) ;;
    1) bad "$label: build step #$n has no output lines"; return 1 ;;
    *) blocked "$label: the build log could not be searched — result UNPROVEN"; return 1 ;;
  esac
  if grep -qE "^#${n} CACHED" <<< "$steps"; then
    bad "$label: build step #$n was CACHED and therefore did not execute for this build"
    return 1
  fi
  if ! grep -qE "^#${n} DONE" <<< "$steps"; then
    bad "$label: build step #$n did not report DONE"
    return 1
  fi
  ok "$label: build step #$n executed for this build"
  return 0
}

step_probe() { # step B — credential-free connectivity and TLS
  local expected image
  printf '== step B: unauthenticated connectivity and TLS, with NO credential ==\n'
  note "this step mounts no password, opens no password, and hashes no password"
  note "it sends one GET /api/auth, which docs/PIHOLE_API_CONTRACT.md section 3.4"
  note "documents as requiring no credential. It does not authenticate."
  assert_no_overrides
  resolve_repo_owner
  expected="$(state_require EXPECTED_COMMIT)"
  image="$(state_require IMAGE_ID)"
  assert_source_identity "$expected"
  require_docker
  begin_invocation
  resolve_deployment_config
  assert_deployment_sources || summary_and_exit

  build_probe_args "$image" bridge no || summary_and_exit
  create_probe "$image" "connectivity probe" "${PROBE_ARGS[@]}" doctor --no-credential ||
    summary_and_exit

  # The boundary is checked on the CREATED container, before it starts. A claim
  # that no password is read is worth much less than a container that has no
  # password to read.
  assert_no_mount "no credential is mounted into the connectivity probe" "$CT_SECRET_PATH"
  assert_network_mode "the probe has network access, as this step requires" "bridge"

  capture_run "$WORK/doctor.log" docker start -a "$PROBE_CID"
  printf 'DOCTOR exit=%d\n' "$LAST_RC"
  assert_capture_usable "doctor output" "$WORK/doctor.log" || summary_and_exit

  # The run must show that it did NOT read the credential. This is the line the
  # superseded procedure contradicted: it claimed no password was read while
  # its own expected output reported the password as readable.
  expect_in_file "doctor reports the credential check as SKIPPED, not as passed" \
    '^SKIP[[:space:]]+application password' "$WORK/doctor.log"
  expect_absent_from_file "doctor makes no claim that the credential is readable" \
    '^ok[[:space:]]+application password' "$WORK/doctor.log"

  expect_in_file "the mounted CA parsed as a real certificate" \
    '^ok[[:space:]]+certificate authority' "$WORK/doctor.log"
  if search_file '^ok[[:space:]]+pi-hole connectivity' "$WORK/doctor.log"; then
    ok "the pinned destination answered, the chain verified against the private CA, and the certificate is valid for pi.hole"
  else
    bad "the connectivity or TLS check did not pass — do NOT proceed to step D"
    print_diagnostic "$WORK/doctor.log"
  fi
  if [ "$LAST_RC" -ne 0 ]; then
    bad "doctor exited $LAST_RC"
  fi
  note "the negative control for the CA — that a WRONG CA is refused — is covered by"
  note "TestTLSFailureWithWrongCA and TestHostnameMismatchIsRefused, and is deliberately"
  note "not repeated against the live appliance: it would mean editing the deployment."
  summary_and_exit
}

step_secret() { # step C — offline secret read
  local expected image
  printf '== step C: the container identity can open the mounted secret, offline ==\n'
  note "this step mounts the real password and OPENS it. It never prints its content,"
  note "and it does not report its length. The network is disabled at the container"
  note "level, so nothing read here can leave the host."
  assert_no_overrides
  resolve_repo_owner
  expected="$(state_require EXPECTED_COMMIT)"
  image="$(state_require IMAGE_ID)"
  assert_source_identity "$expected"
  require_docker
  begin_invocation
  resolve_deployment_config
  assert_deployment_sources || summary_and_exit

  build_probe_args "$image" none yes || summary_and_exit
  create_probe "$image" "secret probe" "${PROBE_ARGS[@]}" doctor --offline ||
    summary_and_exit

  # `--offline` is a CLI flag: it makes the program skip its connectivity
  # checks. It is not an isolation boundary. `--network none` is, and it is
  # asserted on the created container before it starts.
  assert_network_mode "the secret probe has no network at all" "none"

  capture_run "$WORK/secret.log" docker start -a "$PROBE_CID"
  printf 'DOCTOR-OFFLINE exit=%d\n' "$LAST_RC"
  assert_capture_usable "doctor --offline output" "$WORK/secret.log" || summary_and_exit

  if search_file '^ok[[:space:]]+application password[[:space:]]+readable' "$WORK/secret.log"; then
    ok "the container identity opened the mounted secret (uid 65532 with the configured supplementary group)"
  elif search_file '^FAIL[[:space:]]+application password' "$WORK/secret.log"; then
    bad "the container identity could NOT open the mounted secret"
    note "if step A's readability judgement passed and this failed, the two disagree,"
    note "and that disagreement outranks either result. The likely causes are the ones"
    note "step A names as assumptions: an ACL, a user-namespace remap, or a rootless daemon."
    print_diagnostic "$WORK/secret.log"
  else
    blocked "the credential check did not appear in the output at all"
    print_diagnostic "$WORK/secret.log"
  fi
  expect_absent_from_file "no credential length is disclosed" \
    'application password.*bytes' "$WORK/secret.log"
  if [ "$LAST_RC" -ne 0 ]; then
    bad "doctor --offline exited $LAST_RC"
  fi
  summary_and_exit
}

step_status() { # step D — the one authenticated operation
  local expected image
  printf '== step D: ONE reviewed authenticated read-only operation ==\n'
  if [ "${AUTHORISED_D:-0}" -ne 1 ]; then
    refuse "step D authenticates to the live Pi-hole. It runs only with --authorise-authenticated-read, and only after steps A, B and C have passed and been read."
  fi
  assert_no_overrides
  resolve_repo_owner
  expected="$(state_require EXPECTED_COMMIT)"
  image="$(state_require IMAGE_ID)"
  assert_source_identity "$expected"
  require_docker
  begin_invocation
  resolve_deployment_config
  assert_deployment_sources || summary_and_exit

  # What this can send, stated as it actually is.
  #
  # The bound is the PERMITTED SET, not a request count. `status` performs three
  # logical operations — POST /api/auth, GET /api/info/version, DELETE
  # /api/auth — but GET /api/info/version is retryable, so a Pi-hole answering
  # 429/500/502/503/504 or a transport failure produces up to 1+MaxRetries
  # attempts of it, and each logical request may follow up to two same-origin
  # redirects whose method and path are re-checked against the same table. With
  # the shipped defaults that is at most 15 HTTP requests, every one of them to
  # the pinned origin and within the four permitted operations.
  note "permitted operations: POST /api/auth, GET /api/info/version, DELETE /api/auth"
  note "GET /api/info/version is RETRYABLE (max_retries=2 by default), and each request"
  note "may follow up to two same-origin redirects, so this is not 'exactly three requests'."
  note "The real bound is the permitted set, enforced before any packet is sent."

  build_probe_args "$image" bridge yes || summary_and_exit
  create_probe "$image" "status probe" "${PROBE_ARGS[@]}" status || summary_and_exit
  assert_network_mode "the status probe uses the deployment's network mapping" "bridge"

  capture_run "$WORK/status.log" docker start -a "$PROBE_CID"
  printf 'STATUS exit=%d\n' "$LAST_RC"
  assert_capture_usable "status output" "$WORK/status.log" || summary_and_exit

  # Three different claims, kept apart.
  if search_file 'session logout ACCEPTED by Pi-hole' "$WORK/status.log"; then
    ok "the session teardown request was ACCEPTED by Pi-hole"
    note "that is a fact about a REQUEST. It is not independent confirmation that the"
    note "appliance's session table no longer holds the session — see below."
  elif search_file 'session ALREADY ABSENT' "$WORK/status.log"; then
    ok "Pi-hole reported no such session to destroy, which is the desired end state"
  elif search_file 'session logout FAILED' "$WORK/status.log"; then
    bad "the session teardown FAILED — a session may remain valid on the appliance until it expires"
  else
    blocked "the output makes no statement about the session teardown — result UNPROVEN"
  fi
  if [ "$LAST_RC" -ne 0 ]; then
    bad "status exited $LAST_RC"
    print_diagnostic "$WORK/status.log"
  fi

  printf '\n-- independent confirmation is NOT available from here --\n'
  note "ScamWall cannot list Pi-hole's sessions: the endpoint that would do so is"
  note "outside the permitted set and adding it would widen this client's reach."
  note "Whether the appliance's UI shows a per-session user agent, and where that list"
  note "lives in the menu, has NOT been verified for any Pi-hole version by this"
  note "repository. Do not treat a remembered menu path as evidence."
  note "Record the Core/Web/FTL versions this step printed, then confirm against THAT"
  note "version's own documentation. If no supported method exists for it, record the"
  note "session teardown as 'request accepted, not independently confirmed'."
  summary_and_exit
}

step_closeout() { # step Z
  local before after digest_before digest_after
  printf '== step Z: close out ==\n'
  require_docker
  begin_invocation

  # -- the deployment's secret is as it was -----------------------------------
  #
  # METADATA is compared by default: owner, group, mode, size, and modification
  # time. That is what can be established without reading a credential, and it
  # is stated as what it is. It does not prove the content is unchanged: a
  # same-length rewrite with a restored mtime would pass.
  printf '\n-- the deployment secret --\n'
  # A metadata read that fails is a FAILURE, and it does NOT end the step. The
  # leftover enumeration below is the other half of closing out, and skipping
  # it because of an unrelated failure would leave resources unaccounted for
  # while the run still reported a reason to stop looking.
  if ! after="$(stat -c '%u:%g %a %s %Y' -- "$EXPECTED_SECRET_SOURCE" 2>/dev/null)"; then
    bad "the secret's metadata could not be read: $EXPECTED_SECRET_SOURCE"
    after=""
  fi
  before="$(state_get SECRET_META)" || before=""
  if [ -z "$after" ]; then
    : # already reported above; nothing to compare
  elif [ -z "$before" ]; then
    state_put SECRET_META "$after"
    note "no earlier metadata was recorded; this run records it as the baseline"
    ok "secret metadata recorded (uid:gid mode size mtime)"
  elif [ "$before" = "$after" ]; then
    ok "the secret's metadata is unchanged (uid:gid, mode, size, mtime)"
    note "this does NOT prove the content is unchanged; it proves those five properties are"
  else
    bad "the secret's metadata CHANGED during this handoff"
  fi

  if [ "${VERIFY_SECRET_INTEGRITY:-0}" -eq 1 ]; then
    printf '\n-- optional content integrity --\n'
    note "THIS READS THE CREDENTIAL. It is off by default and is not needed to prove"
    note "that a step was credential-free. The digest is compared, never printed."
    # sha256sum's own status is checked BEFORE anything parses its output: a cut
    # of a failed command's empty output is an empty string, and comparing two
    # empty strings is a pass.
    if ! digest_after="$(sha256sum -- "$EXPECTED_SECRET_SOURCE" 2>/dev/null)"; then
      bad "the secret could not be hashed — integrity is UNPROVEN"
    else
      digest_after="${digest_after%% *}"
      if [ "${#digest_after}" -ne 64 ]; then
        bad "the computed digest is malformed — integrity is UNPROVEN"
      else
        digest_before="$(state_get SECRET_DIGEST)" || digest_before=""
        if [ -z "$digest_before" ]; then
          state_put SECRET_DIGEST "$digest_after"
          note "no earlier digest was recorded; this run records it as the baseline"
          ok "secret digest recorded (never printed)"
        elif [ "$digest_before" = "$digest_after" ]; then
          ok "the secret's content is unchanged"
        else
          bad "the secret's content CHANGED during this handoff"
        fi
      fi
    fi
  fi

  # -- nothing of these invocations is left behind ----------------------------
  #
  # Enumeration failure and an empty result are different answers. A `docker ps`
  # that could not run prints nothing, and reading that as "nothing remains" is
  # the false clean this whole suite exists to prevent.
  printf '\n-- leftovers --\n'
  local kind found
  for kind in container network volume; do
    if ! found="$(label_query "$kind" "$PROJECT_LABEL=$VERIFY_PROJECT")"; then
      blocked "${kind}s of this handoff could not be enumerated — leftovers are UNPROVEN"
      continue
    fi
    if [ -z "$found" ]; then
      ok "no ${kind} of this handoff remains"
    else
      bad "${kind}s remain:"
      printf '%s\n' "$found" | sed 's/^/          /'
    fi
  done
  note "resources from EARLIER steps carried their own per-invocation labels and were"
  note "removed by those steps. This step can only speak for its own."
  summary_and_exit
}

# ==============================================================================
# Argument handling
# ==============================================================================

usage() {
  sed -n '/^# Usage:/,/^# Exit status/p' "$0" | sed 's/^# \{0,1\}//'
}

STEP="${1:-}"
[ -n "$STEP" ] || { usage >&2; exit 2; }
shift

EXPECTED_COMMIT_ARG=""
WORK_DIR_ARG=""
VERSION_LABEL=""
AUTHORISED_D=0
VERIFY_SECRET_INTEGRITY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --expected-commit) [ $# -ge 2 ] || refuse "--expected-commit needs a value"; EXPECTED_COMMIT_ARG="$2"; shift 2 ;;
    --work-dir)        [ $# -ge 2 ] || refuse "--work-dir needs a value";        WORK_DIR_ARG="$2";        shift 2 ;;
    --version-label)   [ $# -ge 2 ] || refuse "--version-label needs a value";   VERSION_LABEL="$2";       shift 2 ;;
    --authorise-authenticated-read) AUTHORISED_D=1; shift ;;
    --verify-secret-integrity)      VERIFY_SECRET_INTEGRITY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) refuse "unknown argument: $1" ;;
  esac
done

case "$STEP" in
  preflight)
    [ -n "$EXPECTED_COMMIT_ARG" ] || refuse "preflight requires --expected-commit <40-hex-sha>, supplied by the handoff and not read from HEAD"
    step_preflight "$EXPECTED_COMMIT_ARG" "$WORK_DIR_ARG"
    ;;
  build)    open_work_dir "$WORK_DIR_ARG"; step_build ;;
  probe)    open_work_dir "$WORK_DIR_ARG"; step_probe ;;
  secret)   open_work_dir "$WORK_DIR_ARG"; step_secret ;;
  status)   open_work_dir "$WORK_DIR_ARG"; step_status ;;
  closeout) open_work_dir "$WORK_DIR_ARG"; step_closeout ;;
  -h|--help) usage; exit 0 ;;
  *) printf 'unknown step: %s\n\n' "$STEP" >&2; usage >&2; exit 2 ;;
esac
