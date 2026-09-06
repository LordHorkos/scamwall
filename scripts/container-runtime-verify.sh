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
#   * Every prerequisite, Docker operation, search and parse is checked
#     explicitly. A check that could not run is BLOCKED or FAILED and makes the
#     exit status nonzero. It is never silently treated as a pass. In
#     particular a search distinguishes three outcomes — matched, did not
#     match, and could not be performed — because grep exit 2 read as "no
#     match" is indistinguishable from a clean result.
#   * Inspection output is captured and its exit status verified BEFORE any
#     assertion reads it. A failed `docker inspect` can therefore never be
#     mistaken for "the property is absent". An absent or empty `.Mounts` is a
#     FAILURE, not a satisfied absence.
#   * Assertions are evaluated with jq over captured JSON, not by grepping
#     command output, so error text on stderr cannot satisfy a pattern.
#   * The image is resolved ONCE to its immutable image ID, and every later
#     operation — history, filesystem enumeration, container comparison — uses
#     that ID rather than the mutable tag.
#   * Expected deployment settings are derived from `docker compose config`,
#     the resolved and interpolated configuration, using the SAME argument set
#     that creates the container. They are never re-derived by grepping .env.
#   * Resources are attributed before they are deleted. The invocation
#     identifier is unpredictable, every created resource ID is recorded, a
#     per-invocation ownership label is applied, and anything that existed
#     before this invocation is preserved — including a resource that happens
#     to carry a matching label. There is no project-wide `compose down`.
#   * Cleanup is part of the verdict: it completes before success is reported,
#     it is idempotent, it runs once on EXIT/INT/TERM, and a required cleanup
#     that fails makes the exit status nonzero and names what was left behind.
#
# What this program does NOT prove is stated where each check is made. The two
# most easily over-read are marked in the output itself: image-history scanning
# is a build-instruction pattern check and never proof of a secret-free image
# filesystem; and mount configuration never proves that the container identity
# can actually read the mounted password.
#
# Usage:
#   scripts/container-runtime-verify.sh
#
# Environment:
#   SCAMWALL_IMAGE              image to verify           (default scamwall:local)
#   SCAMWALL_EXPECTED_IMAGE_ID  if set, the resolved image ID must equal it
#
# Exit status: 0 only when every required check actually ran and passed AND
# every required cleanup completed.

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
SERVICE="scamwall"

for required in "$COMPOSE" "$REPO_ROOT/container/Dockerfile"; do
  [ -f "$required" ] || {
    printf 'fatal: expected file not found: %s\n' "$required" >&2
    printf 'fatal: %s does not look like a ScamWall checkout\n' "$REPO_ROOT" >&2
    exit 2; }
done

case "${1:-}" in
  "") ;;
  -h|--help) sed -n '3,60p' "$0"; exit 0 ;;
  *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
esac

PASS=0; FAIL=0; BLOCK=0; CLEANUP_PROBLEMS=0
ok()      { printf '\033[32mPASS\033[0m    %s\n' "$1"; PASS=$((PASS + 1)); }
bad()     { printf '\033[31mFAIL\033[0m    %s\n' "$1"; FAIL=$((FAIL + 1)); }
blocked() { printf '\033[31mBLOCKED\033[0m %s\n' "$1"; BLOCK=$((BLOCK + 1)); }
note()    { printf '        %s\n' "$1"; }

# --- Captured diagnostics -----------------------------------------------------
#
# The two commands that can fail with something worth reading — `compose config`
# and `compose create` — used to have their stderr folded onto one line and cut
# at 200 characters. Compose puts the useful part of a mount or secret error at
# the END of a multi-line message, so that cut discarded exactly the sentence
# naming the path it could not use.
#
# Compose's stderr is not trusted text: it quotes paths, service names, and
# occasionally the content of a file it failed to read. It is therefore passed
# through the same filter the gate suite uses and, if that filter is missing or
# fails, NOT printed at all. An unreadable message costs a rerun; a leaked one
# cannot be taken back.
SANITIZER="$SCRIPT_DIR/gate-diagnostics.sh"
DIAG_MAX_LINES=100
print_diagnostic() { # <captured-file>
  local file="$1" clean n line shown
  if [ ! -f "$file" ] || [ ! -s "$file" ]; then
    note "no output was captured from the failing command"
    return 0
  fi
  if [ ! -f "$SANITIZER" ]; then
    note "the captured output is NOT printed: $SANITIZER is absent, so it could not be sanitized"
    return 0
  fi
  clean="$(mktemp)" || { note "the captured output is NOT printed: no temporary file could be created"; return 0; }
  chmod 600 "$clean" 2>/dev/null || true
  if ! bash "$SANITIZER" --sanitize < "$file" > "$clean" 2>/dev/null; then
    note "the captured output is NOT printed: it could not be sanitized"
    rm -f "$clean"
    return 0
  fi
  n="$(wc -l < "$clean" 2>/dev/null)" || n=0
  n="${n//[[:space:]]/}"; [ -n "$n" ] || n=0
  shown="$n"
  [ "$shown" -le "$DIAG_MAX_LINES" ] || shown="$DIAG_MAX_LINES"
  note "captured output ($n line(s), sanitized):"
  while IFS= read -r line; do note "  $line"; done < <(sed -n "1,${shown}p" -- "$clean")
  [ "$n" -le "$DIAG_MAX_LINES" ] ||
    note "  ... $((n - DIAG_MAX_LINES)) further line(s) omitted from this message ..."
  rm -f "$clean"
  return 0
}

# --- Resource tracking --------------------------------------------------------
#
# `scamwall-verify-$$` was not proof of ownership. A PID is small, reused, and
# predictable, so a stale container from an earlier run — or one created by
# something else entirely — could carry the same project name and be destroyed
# by this invocation. Ownership is now established three ways at once:
#
#   1. an UNPREDICTABLE invocation identifier, used in the project name;
#   2. the exact resource IDs this invocation created, recorded as they are
#      created; and
#   3. a per-invocation ownership label applied through a Compose override, so
#      a resource can be attributed even if its ID was not recorded (partial
#      creation, or a service added to the definition later).
#
# Anything that already carried the label before this invocation created
# anything is treated as a COLLISION: nothing is created and nothing is
# deleted. Deletion is by exact ID after re-verifying the label — never
# `compose down -p <project>`, which deletes by name alone.
OWN_LABEL="scamwall.verify.invocation"
PROJECT_LABEL="com.docker.compose.project"
INVOCATION=""
VERIFY_PROJECT=""
WORK_DIR=""
OVERRIDE_FILE=""
RESOURCES_POSSIBLY_CREATED=0
CREATED_CONTAINERS=()
PRE_CONTAINERS=""
PRE_NETWORKS=""
PRE_VOLUMES=""
CLEANUP_DONE=0
LEFTOVERS=""
HANDLED_RESOURCES=""

cleanup_problem() {
  printf '\033[31mCLEANUP\033[0m %s\n' "$1"
  CLEANUP_PROBLEMS=$((CLEANUP_PROBLEMS + 1))
}

record_leftover() {
  LEFTOVERS="${LEFTOVERS}${LEFTOVERS:+$'\n'}$1"
}

# in_list <needle> <newline-separated list>
in_list() {
  local needle="$1" list="${2:-}" line
  [ -n "$needle" ] || return 1
  [ -n "$list" ] || return 1
  while IFS= read -r line; do
    [ "$line" = "$needle" ] && return 0
  done <<< "$list"
  return 1
}

# combine_ids <listA> <listB> — prints the sorted, de-duplicated union of two
# newline-separated id lists with blank lines removed.
#
# Returns 1 when the COMBINATION ITSELF failed. The superseded code ran
# `printf | grep -v | sort -u` and then returned success unconditionally, so a
# grep that could not run or a sort that could not write produced an empty
# string — indistinguishable from "there are no such resources". That empty
# string then told the pre-snapshot there was no collision and told cleanup
# there was nothing to sweep. An obtained-and-empty list and a list that could
# not be produced must never be the same answer.
combine_ids() {
  local filtered rc sorted
  filtered="$(printf '%s\n%s\n' "$1" "$2" | grep -v '^[[:space:]]*$')"
  rc=$?
  case "$rc" in
    0) ;;
    1) return 0 ;;   # nothing selected: a genuine empty list
    *) return 1 ;;   # grep could not do its job
  esac
  [ -n "$filtered" ] || return 0
  sorted="$(LC_ALL=C sort -u <<< "$filtered")" || return 1
  printf '%s\n' "$sorted"
  return 0
}

# label_query <kind> <label=value> — prints full IDs, one per line.
# Returns 1 when the query itself failed, so "no resources" and "could not ask"
# are never the same answer.
label_query() {
  local kind="$1" selector="$2"
  case "$kind" in
    container) docker ps -aq --no-trunc --filter "label=$selector" 2>/dev/null ;;
    network)   docker network ls -q --no-trunc --filter "label=$selector" 2>/dev/null ;;
    volume)    docker volume ls -q --filter "label=$selector" 2>/dev/null ;;
    *)         return 1 ;;
  esac
}

# owned_by_this_invocation <kind> <id>
#   0 = carries this invocation's ownership label or project label
#   1 = exists but is NOT ours — must be preserved
#   2 = ownership could not be established (inspect failed / unparseable)
owned_by_this_invocation() {
  local kind="$1" id="$2" json own proj filter
  case "$kind" in
    container) json="$(docker inspect "$id" 2>/dev/null)" || return 2
               filter='.[0].Config.Labels' ;;
    network)   json="$(docker network inspect "$id" 2>/dev/null)" || return 2
               filter='.[0].Labels' ;;
    volume)    json="$(docker volume inspect "$id" 2>/dev/null)" || return 2
               filter='.[0].Labels' ;;
    *) return 2 ;;
  esac
  own="$(jq -r "($filter // {})[\"$OWN_LABEL\"] // \"\"" <<< "$json" 2>/dev/null)" || return 2
  proj="$(jq -r "($filter // {})[\"$PROJECT_LABEL\"] // \"\"" <<< "$json" 2>/dev/null)" || return 2
  if [ "$own" = "$INVOCATION" ] || [ "$proj" = "$VERIFY_PROJECT" ]; then return 0; fi
  return 1
}

# resource_exists <kind> <id> — 0 = present, 1 = definitely gone, 2 = unknown.
resource_exists() {
  local kind="$1" id="$2" out
  case "$kind" in
    container) out="$(docker ps -aq --no-trunc --filter "id=$id" 2>/dev/null)" || return 2 ;;
    network)   out="$(docker network ls -q --no-trunc --filter "id=$id" 2>/dev/null)" || return 2 ;;
    volume)    out="$(docker volume ls -q --filter "name=$id" 2>/dev/null)" || return 2 ;;
    *) return 2 ;;
  esac
  [ -n "$out" ] && return 0
  return 1
}

# remove_owned <kind> <id> — delete only after ownership is re-established.
remove_owned() {
  local kind="$1" id="$2" rc
  # At most one destructive attempt per resource per invocation, however many
  # code paths reach it: the recorded-ID pass, the discovery sweep, and a
  # second trap all converge here.
  if in_list "$kind/$id" "$HANDLED_RESOURCES"; then return 0; fi
  HANDLED_RESOURCES="${HANDLED_RESOURCES}${HANDLED_RESOURCES:+$'\n'}$kind/$id"
  owned_by_this_invocation "$kind" "$id"; rc=$?
  case "$rc" in
    0) ;;
    1) cleanup_problem "$kind $id does not carry this invocation's ownership label — PRESERVED"
       record_leftover "$kind $id (not attributable to this invocation; left in place)"
       return 1 ;;
    *) resource_exists "$kind" "$id"; rc=$?
       case "$rc" in
         1) return 0 ;;  # already gone — cleanup is idempotent
         *) cleanup_problem "$kind $id: ownership could not be established — PRESERVED"
            record_leftover "$kind $id (ownership unknown; left in place)"
            return 1 ;;
       esac ;;
  esac
  local removed=1
  case "$kind" in
    container) docker rm -f "$id" >/dev/null 2>&1 && removed=0 ;;
    network)   docker network rm "$id" >/dev/null 2>&1 && removed=0 ;;
    volume)    docker volume rm "$id" >/dev/null 2>&1 && removed=0 ;;
  esac
  if [ "$removed" -ne 0 ]; then
    # A removal that failed may or may not have taken effect. Re-ask.
    resource_exists "$kind" "$id"; rc=$?
    if [ "$rc" -eq 1 ]; then return 0; fi
    cleanup_problem "removal of $kind $id failed"
    record_leftover "$kind $id (removal failed)"
    return 1
  fi
  return 0
}

# sweep <kind> <pre-existing list> — remove every labelled resource of this
# kind that was NOT present before this invocation created anything.
sweep() {
  local kind="$1" pre="$2" ids extra id
  ids="$(label_query "$kind" "$PROJECT_LABEL=$VERIFY_PROJECT")" || {
    cleanup_problem "could not list ${kind}s carrying this invocation's project label — leftovers may remain"
    return 1; }
  extra="$(label_query "$kind" "$OWN_LABEL=$INVOCATION")" || {
    cleanup_problem "could not list ${kind}s carrying this invocation's ownership label — leftovers may remain"
    return 1; }
  if ! ids="$(combine_ids "$ids" "$extra")"; then
    cleanup_problem "the ${kind} lists carrying this invocation's labels could not be combined — leftovers may remain"
    record_leftover "${kind}s of this invocation (list processing failed; not swept)"
    return 1
  fi
  [ -n "$ids" ] || return 0
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    if in_list "$id" "$pre"; then
      note "pre-existing $kind $id carries a matching label and is PRESERVED"
      continue
    fi
    remove_owned "$kind" "$id"
  done <<< "$ids"
  return 0
}

# run_cleanup — idempotent, and part of the verdict rather than an afterthought.
# Invoked directly before the summary and through the EXIT/INT/TERM traps.
# shellcheck disable=SC2329  # also reached indirectly via trap
run_cleanup() {
  [ "$CLEANUP_DONE" -eq 0 ] || return 0
  CLEANUP_DONE=1
  printf '\n== cleanup ==\n'

  local id
  if [ "$RESOURCES_POSSIBLY_CREATED" -eq 1 ]; then
    # Recorded IDs first: these are the resources this invocation is known to
    # have created, and they are removed whether or not a later discovery
    # query works.
    for id in ${CREATED_CONTAINERS[@]+"${CREATED_CONTAINERS[@]}"}; do
      [ -n "$id" ] || continue
      in_list "$id" "$PRE_CONTAINERS" && continue
      remove_owned container "$id"
    done
    # Then discovery, which catches resources created by a partially completed
    # `compose create` whose IDs this program never saw.
    sweep container "$PRE_CONTAINERS"
    sweep network   "$PRE_NETWORKS"
    sweep volume    "$PRE_VOLUMES"
  else
    note "no Docker resources were created by this invocation"
  fi

  if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
    if ! rm -rf "$WORK_DIR"; then
      cleanup_problem "the rendered-configuration directory could not be removed: $WORK_DIR"
      record_leftover "directory $WORK_DIR (removal failed)"
    fi
  fi

  if [ "$CLEANUP_PROBLEMS" -eq 0 ]; then
    printf '\033[32mPASS\033[0m    cleanup complete: every resource this invocation created was removed\n'
  else
    printf '\033[31mFAIL\033[0m    cleanup INCOMPLETE — %d problem(s). Remaining resources:\n' "$CLEANUP_PROBLEMS"
    printf '%s\n' "$LEFTOVERS" | sed 's/^/          /'
    note "no credential, environment or configuration content is printed above; identifiers only"
  fi
  return 0
}

summary_and_exit() {
  # Cleanup completes BEFORE the verdict is printed, and its outcome counts
  # towards that verdict. Previously the success line was printed first and
  # cleanup errors were discarded entirely.
  run_cleanup
  printf '\n%d passed, %d failed, %d blocked, %d cleanup problem(s)\n' \
    "$PASS" "$FAIL" "$BLOCK" "$CLEANUP_PROBLEMS"
  if [ "$FAIL" -gt 0 ] || [ "$BLOCK" -gt 0 ]; then
    printf 'RESULT: runtime verification INCOMPLETE — required checks failed or could not run.\n'
    exit 1
  fi
  if [ "$CLEANUP_PROBLEMS" -gt 0 ]; then
    printf 'RESULT: checks passed but REQUIRED CLEANUP FAILED — resources listed above remain.\n'
    exit 1
  fi
  printf 'RESULT: all required runtime checks passed and cleanup completed.\n'
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
  # operations happen exactly once no matter how many traps fire.
  exit "$2"
}

trap on_exit EXIT
trap 'on_signal INT 130' INT
trap 'on_signal TERM 143' TERM

# --- Checked search -----------------------------------------------------------
#
# Three outcomes, never two. `grep -q PATTERN FILE` returning 2 means grep
# could not do its job — an unreadable file, a bad pattern, an I/O error — and
# reading that as "no match" is how the history check reported a search it
# never performed as a clean result.
#
# The file form is used deliberately: `producer | grep -q` lets grep exit at
# the first match while the producer takes SIGPIPE, which under `pipefail`
# turns a match into a failure (docs/VERIFICATION.md 4.1).
search_file() { # pattern file [-i] -> 0 matched, 1 no match, 2 could not search
  local pattern="$1" file="$2" ci="${3:-}" rc
  [ -f "$file" ] && [ -r "$file" ] || return 2
  if [ "$ci" = "-i" ]; then
    grep -qiE -- "$pattern" "$file"
  else
    grep -qE -- "$pattern" "$file"
  fi
  rc=$?
  case "$rc" in
    0|1) return "$rc" ;;
    *)   return 2 ;;
  esac
}

# count_matches <pattern> <file> — prints the count; returns 1 if the search
# could not be performed. grep -c exits 1 for a zero count, which is not an
# error; 2 or more is.
count_matches() {
  local pattern="$1" file="$2" hits rc
  [ -f "$file" ] && [ -r "$file" ] || return 1
  hits="$(grep -cE -- "$pattern" "$file")"
  rc=$?
  if [ "$rc" -gt 1 ]; then return 1; fi
  case "$hits" in
    ''|*[!0-9]*) return 1 ;;
  esac
  printf '%s' "$hits"
  return 0
}

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
assert_empty_list() { # label file filter
  local label="$1" file="$2" filter="$3" got
  if ! got="$(jq -r "$filter" < "$file" 2>/dev/null)"; then
    bad "$label (inspection JSON could not be parsed)"; return
  fi
  if [ -z "$got" ]; then ok "$label"
  else bad "$label — found: $got"; fi
}

# jq_read <file> <filter> — capture a value, distinguishing a parse failure
# from a value. Callers MUST test the return status.
jq_read() {
  jq -r "$2" < "$1" 2>/dev/null
}

# --- Required inspection fields -----------------------------------------------
#
# `// 0`, `// ""` and `// []` were used to make assertions total. They also made
# them vacuous: `(.State.Pid // 0) == 0` is satisfied when the daemon reported
# no Pid at all, and `(.HostConfig.NetworkMode // "") != "host"` is satisfied
# when NetworkMode is missing. A default cannot stand in for evidence — a field
# that is absent, or present with the wrong type, means the property was never
# observed, and that is a FAILURE.
#
# A default is retained ONLY where Docker's own representation genuinely uses
# null for "none" and the requirement is satisfied by that null; each such case
# is marked where it appears.
require_field() { # label file filter permitted-types(csv)
  local label="$1" file="$2" filter="$3" types="$4" got
  if ! got="$(jq -r "($filter) | type" < "$file" 2>/dev/null)"; then
    bad "$label: the inspection JSON could not be parsed — field UNPROVEN"
    return 1
  fi
  case ",$types," in
    *",$got,"*) return 0 ;;
  esac
  bad "$label: required inspection field is absent or of the wrong type (observed '$got', expected $types)"
  return 1
}

# require_fields <file> <label-prefix> <filter:types>... — reports every
# missing field rather than stopping at the first, and returns 1 if any is
# missing so the caller can say the evaluation that follows is unproven.
require_fields() {
  local file="$1" prefix="$2" spec filter types rc=0
  shift 2
  for spec in "$@"; do
    filter="${spec%%::*}"; types="${spec##*::}"
    require_field "$prefix $filter" "$file" "$filter" "$types" || rc=1
  done
  return "$rc"
}

# --- Numeric and option parsing -----------------------------------------------
#
# Finding the substring `size=` proves only that the letters are present. These
# parse the value and reject anything that is not a bounded quantity, so
# `size=0`, `size=`, `size=abc` and `size=999g` are all rejected.
#
# Two further defects were found here and are fixed below:
#
#   * `$(( ))` reads a leading zero as OCTAL. `size=010k` was evaluated as
#     8 * 1024, not 10 * 1024, so a configured bound was silently understated —
#     and `09` is not a valid octal literal at all, which makes the shell emit
#     an error and the surrounding arithmetic produce nothing. Leading zeros
#     are now stripped and every value is read explicitly in base 10.
#   * The multiplication was performed BEFORE any bound was applied. Bash
#     arithmetic is 64-bit and wraps silently, so `size=18014398509483008k`
#     evaluated to 1048576 — one mebibyte — and passed the tmpfs bound while
#     actually requesting sixteen pebibytes. The multiplicand is now bounded
#     first, so a product that could wrap is rejected before it is computed.
#
# SIZE_MAX_BYTES is an absolute ceiling for any parsed size. It is far above
# anything this deployment permits; its only job is to keep every product well
# inside the 64-bit range so no arithmetic below can wrap.
SIZE_MAX_BYTES=$((1024 * 1024 * 1024 * 1024))   # 1 TiB

# to_decimal <digits> [max] — prints the value in base 10.
# Returns 1 when the input is not a run of decimal digits, when it is longer
# than the shell can multiply safely, or when it exceeds <max>. Every numeric
# input this program acts on goes through here; nothing is fed to `$(( ))`
# straight from Docker or Compose output.
to_decimal() {
  local v="$1" max="${2:-}" d
  case "$v" in
    ''|*[!0-9]*) return 1 ;;
  esac
  # Leading zeros are permitted on input and are read as DECIMAL, never octal.
  d="$v"
  while [ "${#d}" -gt 1 ] && [ "${d:0:1}" = '0' ]; do d="${d:1}"; done
  # 18 significant digits keeps every value, and every product formed from a
  # bounded multiplicand below, inside the signed 64-bit range.
  [ "${#d}" -le 18 ] || return 1
  if [ -n "$max" ] && [ "$d" -gt "$max" ]; then return 1; fi
  printf '%s' "$d"
  return 0
}

size_to_bytes() { # value -> bytes on stdout; 1 if malformed or out of range
  local v="$1" num unit mult
  if [[ "$v" =~ ^([0-9]+)([bkmgBKMG]?)$ ]]; then
    num="${BASH_REMATCH[1]}"; unit="${BASH_REMATCH[2]}"
  else
    return 1
  fi
  case "$unit" in
    ''|b|B) mult=1 ;;
    k|K)    mult=1024 ;;
    m|M)    mult=$((1024 * 1024)) ;;
    g|G)    mult=$((1024 * 1024 * 1024)) ;;
    *)      return 1 ;;
  esac
  # Bound the multiplicand BEFORE multiplying, not the product afterwards.
  num="$(to_decimal "$num" "$((SIZE_MAX_BYTES / mult))")" || return 1
  printf '%s' "$((num * mult))"
  return 0
}

is_uint() { # value [min] [max]
  local v="$1" min="${2:-0}" max="${3:-}" d
  d="$(to_decimal "$v")" || return 1
  [ "$d" -ge "$min" ] || return 1
  [ -z "$max" ] || [ "$d" -le "$max" ] || return 1
  return 0
}

# TMPFS_MAX_BYTES: a scratch tmpfs is charged against the container's memory
# limit, so an unbounded or oversized one defeats the memory bound.
TMPFS_MAX_BYTES=$((64 * 1024 * 1024))
LOG_MAX_SIZE_BYTES=$((100 * 1024 * 1024))
LOG_MAX_TOTAL_BYTES=$((512 * 1024 * 1024))
MEM_MAX_BYTES=$((512 * 1024 * 1024))

# validate_tmpfs_options <label> <option string>
# Requires noexec, nosuid, nodev and a parseable, bounded, nonzero size, and
# rejects any option it does not recognise rather than ignoring it.
validate_tmpfs_options() {
  local label="$1" opts="$2" tok bytes
  local have_noexec=0 have_nosuid=0 have_nodev=0 size_seen=0
  if [ -z "$opts" ]; then
    bad "$label: no tmpfs options recorded — /tmp hardening UNPROVEN"; return
  fi
  local -a toks=()
  IFS=',' read -r -a toks <<< "$opts"
  for tok in ${toks[@]+"${toks[@]}"}; do
    case "$tok" in
      noexec) have_noexec=1 ;;
      nosuid) have_nosuid=1 ;;
      nodev)  have_nodev=1 ;;
      rw|ro)  ;;
      exec|suid|dev)
        bad "$label: option '$tok' re-enables what noexec/nosuid/nodev forbid"; return ;;
      mode=*) ;;
      size=*)
        size_seen=1
        if ! bytes="$(size_to_bytes "${tok#size=}")"; then
          bad "$label: size option '$tok' is not a parseable size"; return
        fi
        if [ "$bytes" -le 0 ] || [ "$bytes" -gt "$TMPFS_MAX_BYTES" ]; then
          bad "$label: size $bytes bytes is outside the permitted bound (1..$TMPFS_MAX_BYTES)"; return
        fi ;;
      '') ;;
      *) bad "$label: unrecognised tmpfs option '$tok' — not accepted"; return ;;
    esac
  done
  if [ "$have_noexec" -eq 1 ] && [ "$have_nosuid" -eq 1 ] && [ "$have_nodev" -eq 1 ] && [ "$size_seen" -eq 1 ]; then
    ok "$label ($opts)"
  else
    bad "$label: missing one of noexec/nosuid/nodev/size in '$opts'"
  fi
}

# --- The approved mount set ---------------------------------------------------
#
# These four destinations are the ENTIRE set of mounts this deployment is
# permitted to have, and they are fixed HERE rather than derived from the
# configuration. Deriving the expectation from `docker compose config` and then
# comparing it with `docker inspect` proves only that the two AGREE. A fifth
# mount added to compose.yaml appears in both, the comparison finds neither a
# missing nor an extra entry, and every mount assertion passes while the
# container has a mount nobody approved.
#
# The scratch tmpfs at /tmp is deliberately NOT in this list: Docker records it
# through HostConfig.Tmpfs, where its options live, and it is validated
# separately by validate_tmpfs_options.
APPROVED_MOUNT_DESTS='/etc/scamwall/certs/pihole-ca.crt
/etc/scamwall/config.json
/etc/scamwall/feed.json
/run/secrets/pihole_app_password'
APPROVED_MOUNT_COUNT=4

# approved_mount_problems <file> — prints a description of everything wrong
# with a `type|source|destination|ro|rw` mount listing, or nothing when the
# listing is exactly the approved set. Returns 1 if the file could not be read,
# which is a failure to check and never an absence of problems.
approved_mount_problems() {
  local file="$1" line type source dest mode seen="" n=0 problems=""
  local -a fields
  [ -f "$file" ] && [ -r "$file" ] || return 1
  while IFS= read -r line; do
    [ -n "${line//[[:space:]]/}" ] || continue
    n=$((n + 1))
    IFS='|' read -r -a fields <<< "$line"
    if [ "${#fields[@]}" -ne 4 ]; then
      problems="${problems}${problems:+; }unparseable mount record '$line'"; continue
    fi
    type="${fields[0]}"; source="${fields[1]}"; dest="${fields[2]}"; mode="${fields[3]}"
    if ! in_list "$dest" "$APPROVED_MOUNT_DESTS"; then
      problems="${problems}${problems:+; }'$dest' is not an approved mount destination"; continue
    fi
    if in_list "$dest" "$seen"; then
      problems="${problems}${problems:+; }'$dest' is mounted more than once"; continue
    fi
    seen="${seen}${seen:+$'\n'}$dest"
    [ "$type" = "bind" ] ||
      problems="${problems}${problems:+; }'$dest' is a '$type' mount, not a bind"
    [ "$mode" = "ro" ] ||
      problems="${problems}${problems:+; }'$dest' is not read-only"
    case "$source" in
      /?*) ;;
      *) problems="${problems}${problems:+; }'$dest' has no resolved absolute source (observed '$source')" ;;
    esac
  done < "$file"
  while IFS= read -r dest; do
    [ -n "$dest" ] || continue
    in_list "$dest" "$seen" ||
      problems="${problems}${problems:+; }'$dest' is not mounted"
  done <<< "$APPROVED_MOUNT_DESTS"
  if [ "$n" -ne "$APPROVED_MOUNT_COUNT" ]; then
    problems="${problems}${problems:+; }expected exactly $APPROVED_MOUNT_COUNT mounts, found $n"
  fi
  printf '%s' "$problems"
  return 0
}

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
if ! chmod 700 "$WORK_DIR" 2>/dev/null; then
  blocked "could not restrict the working directory $WORK_DIR"; summary_and_exit
fi
WORK_MODE="$(stat -c '%a' "$WORK_DIR" 2>/dev/null)" || WORK_MODE=""
if [ "$WORK_MODE" = "700" ]; then
  ok "rendered configuration is kept in a private directory (mode 700)"
else
  blocked "working directory permissions could not be confirmed (observed '${WORK_MODE:-unknown}')"
  summary_and_exit
fi

# An UNPREDICTABLE invocation identifier. $$ was not one: PIDs are small and
# reused, so a stale resource could carry this run's project name.
INVOCATION=""
if [ -r /dev/urandom ]; then
  INVOCATION="$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')" || INVOCATION=""
fi
if [ -z "$INVOCATION" ]; then
  # mktemp -d names are generated from the same entropy source and are created
  # with O_EXCL, so the suffix is a sound fallback. If neither is available we
  # stop rather than fall back to something guessable.
  INVOCATION="$(basename "$WORK_DIR" 2>/dev/null | tr -cd 'a-zA-Z0-9')"
fi
INVOCATION="$(printf '%s' "$INVOCATION" | tr '[:upper:]' '[:lower:]' | cut -c1-32)"
if [ "${#INVOCATION}" -lt 16 ]; then
  blocked "could not obtain an unpredictable invocation identifier — refusing to guess ownership"
  summary_and_exit
fi
VERIFY_PROJECT="scamwall-verify-$INVOCATION"
ok "unpredictable invocation identifier obtained (${#INVOCATION} characters)"

# --- Image identity -----------------------------------------------------------
echo
echo "== image identity =="
note "Docker distinguishes several identifiers, which are NOT interchangeable:"
note "  .Id          the local image identifier (config digest in the classic"
note "               image store). This is what a container records in .Image."
note "  .RepoDigests registry MANIFEST digests, empty for a locally built image."
note "  a manifest-LIST digest identifies a multi-platform index, not an image."
note "Only .Id is used for comparison here, and every later Docker operation is"
note "given that .Id rather than the tag, so a tag moved mid-run cannot swap"
note "another image into the middle of this verification."

IMAGE_JSON="$WORK_DIR/image.json"
if ! docker image inspect "$IMAGE" > "$IMAGE_JSON" 2>/dev/null; then
  blocked "image '$IMAGE' could not be inspected (build it first, or set SCAMWALL_IMAGE)"
  summary_and_exit
fi
if ! jq -e 'type == "array" and length == 1' < "$IMAGE_JSON" >/dev/null 2>&1; then
  blocked "image inspection output is not a single-element JSON array — image identity UNPROVEN"
  summary_and_exit
fi
if ! IMAGE_ID="$(jq_read "$IMAGE_JSON" '.[0].Id')"; then
  blocked "image ID could not be parsed from inspection output"
  summary_and_exit
fi
if ! [[ "$IMAGE_ID" =~ ^sha256:[0-9a-f]{64}$ ]]; then
  blocked "resolved image identifier '$IMAGE_ID' is not a sha256 digest — refusing to proceed"
  summary_and_exit
fi
ok "image '$IMAGE' resolves to $IMAGE_ID"

IMAGE_REPO_TAGS="$(jq_read "$IMAGE_JSON" '(.[0].RepoTags // []) | join(", ")')" || IMAGE_REPO_TAGS="<unreadable>"
IMAGE_REPO_DIGESTS="$(jq_read "$IMAGE_JSON" '(.[0].RepoDigests // []) | join(", ")')" || IMAGE_REPO_DIGESTS="<unreadable>"
note "RepoTags:    ${IMAGE_REPO_TAGS:-<none>}"
note "RepoDigests: ${IMAGE_REPO_DIGESTS:-<none> (expected for a locally built image)}"

if [ -n "${SCAMWALL_EXPECTED_IMAGE_ID:-}" ]; then
  if ! [[ "${SCAMWALL_EXPECTED_IMAGE_ID}" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    bad "SCAMWALL_EXPECTED_IMAGE_ID is not a sha256 digest — the pin cannot be evaluated"
  elif [ "$IMAGE_ID" = "$SCAMWALL_EXPECTED_IMAGE_ID" ]; then
    ok "resolved image ID matches SCAMWALL_EXPECTED_IMAGE_ID"
  else
    bad "resolved image ID does not match SCAMWALL_EXPECTED_IMAGE_ID (expected $SCAMWALL_EXPECTED_IMAGE_ID)"
  fi
else
  note "SCAMWALL_EXPECTED_IMAGE_ID is not set; the tag was trusted to name the"
  note "intended image. Set it to bind this run to a specific build."
fi

# Required before evaluation, for the same reason as the container fields:
# `.Config.User` missing must not be read as "no user requirement stated".
require_fields "$IMAGE_JSON" "image inspection field" \
  '.[0].Config::object' \
  '.[0].Config.User::string' \
  && ok "every required image inspection field is present with the expected type"
assert_eq   "image user"                    "$IMAGE_JSON" '.[0].Config.User' '65532:65532'
# Healthcheck and ExposedPorts are absent-or-null in a compliant image, and
# that null IS the requirement, so it is asserted directly.
assert_eq   "image declares no healthcheck" "$IMAGE_JSON" '.[0].Config.Healthcheck' 'null'
assert_eq   "image exposes no ports"        "$IMAGE_JSON" '(.[0].Config.ExposedPorts // {}) | length' '0'

# --- Image history: a LIMITED pattern check -----------------------------------
echo
echo "== image history (limited pattern check) =="
note "Scans build-instruction text only. It cannot see layer contents, so it is"
note "evidence against a pasted credential in a build command — NOT proof that"
note "the image filesystem contains no secret."

HISTORY_OUT="$WORK_DIR/history.txt"
if ! docker history --no-trunc --format '{{.CreatedBy}}' "$IMAGE_ID" > "$HISTORY_OUT" 2>/dev/null; then
  bad "image history could not be read (docker history failed) — build instructions UNSCANNED"
elif [ ! -s "$HISTORY_OUT" ]; then
  bad "image history could not be read (no output) — build instructions UNSCANNED"
else
  search_file 'password|passwd=|BEGIN [A-Z ]*PRIVATE KEY|api[_-]?key' "$HISTORY_OUT" -i
  case $? in
    0) bad "credential pattern matched in image build instructions" ;;
    1) ok "no credential pattern in image build instructions" ;;
    *) bad "image history could not be searched — the scan did not run, so its result is UNPROVEN" ;;
  esac
fi

# --- Resource ownership pre-snapshot ------------------------------------------
#
# Taken BEFORE anything is created. Any resource already carrying this
# invocation's project or ownership label is, by construction, not ours: the
# identifier is unpredictable and was chosen moments ago. Such a resource is
# recorded so cleanup preserves it, and — because Compose would ADOPT a
# container that already carries the project label rather than create a new
# one — this invocation creates nothing at all in that case.
echo
echo "== resource ownership =="

# snapshot_kind <kind> -> newline-separated ids on stdout.
# Returns 1 when either query OR the combination of their results failed. The
# caller treats that as BLOCKED: an empty snapshot is only trustworthy when it
# was actually obtained.
snapshot_kind() {
  local kind="$1" by_project by_invocation
  by_project="$(label_query "$kind" "$PROJECT_LABEL=$VERIFY_PROJECT")" || return 1
  by_invocation="$(label_query "$kind" "$OWN_LABEL=$INVOCATION")" || return 1
  combine_ids "$by_project" "$by_invocation" || return 1
  return 0
}

COLLISIONS=""
for kind in container network volume; do
  if ! snapshot="$(snapshot_kind "$kind")"; then
    blocked "pre-existing ${kind}s could not be enumerated or processed — ownership cannot be established, so nothing will be created or deleted"
    summary_and_exit
  fi
  case "$kind" in
    container) PRE_CONTAINERS="$snapshot" ;;
    network)   PRE_NETWORKS="$snapshot" ;;
    volume)    PRE_VOLUMES="$snapshot" ;;
  esac
  if [ -n "$snapshot" ]; then
    COLLISIONS="${COLLISIONS}${COLLISIONS:+; }$kind: $(printf '%s' "$snapshot" | tr '\n' ' ')"
  fi
done

if [ -n "$COLLISIONS" ]; then
  blocked "resources already carry this invocation's labels ($COLLISIONS) — they are NOT ours, so nothing is created and nothing is deleted"
  note "this is a name collision, not a leftover: re-run to obtain a fresh identifier"
  summary_and_exit
fi
ok "no pre-existing container, network or volume carries this invocation's labels"
note "resources belonging to the real deployment are never queried, listed or"
note "removed: every query is filtered by a label unique to this invocation."

# --- Image filesystem enumeration ---------------------------------------------
echo
echo "== image filesystem (enumerated paths) =="

FS_TAR="$WORK_DIR/image.tar"
FS_RAW="$WORK_DIR/image-fs-raw.txt"
FS_LIST="$WORK_DIR/image-fs.txt"
FS_OK=0

# Created from the resolved IMAGE ID, not the tag, and labelled with this
# invocation so it can be attributed later even if this shell dies before the
# ID is recorded.
RESOURCES_POSSIBLY_CREATED=1
FS_CREATE_OUT="$WORK_DIR/fs-create.txt"
if ! docker create --label "$OWN_LABEL=$INVOCATION" "$IMAGE_ID" > "$FS_CREATE_OUT" 2>/dev/null; then
  bad "image filesystem could not be enumerated (docker create failed) — path absence UNPROVEN"
else
  FS_CID="$(tr -d '\r' < "$FS_CREATE_OUT" | grep -E '^[0-9a-f]{12,64}$' | tail -1)" || FS_CID=""
  if [ -z "${FS_CID:-}" ]; then
    bad "docker create returned no usable container ID — path absence UNPROVEN"
  else
    CREATED_CONTAINERS+=("$FS_CID")
    if ! docker export "$FS_CID" > "$FS_TAR" 2>/dev/null || [ ! -s "$FS_TAR" ]; then
      bad "image filesystem could not be enumerated (docker export failed) — path absence UNPROVEN"
    elif ! tar -tf "$FS_TAR" > "$FS_RAW" 2>/dev/null || [ ! -s "$FS_RAW" ]; then
      bad "image filesystem could not be enumerated (tar listing failed) — path absence UNPROVEN"
    elif ! sed -e 's#^\./##' -e 's#^/##' "$FS_RAW" > "$FS_LIST" 2>/dev/null || [ ! -s "$FS_LIST" ]; then
      # Normalisation happens ONCE, here, so every pattern below matches a
      # single canonical form. The previous patterns began with `^\./?`, which
      # requires a leading dot: an archive written without the `./` prefix —
      # `bin/sh`, `usr/bin/bash`, `etc/shadow` — matched nothing at all, and
      # every absence assertion passed vacuously.
      bad "image filesystem listing could not be normalised — path absence UNPROVEN"
    else
      search_file '^usr/local/bin/scamwall$' "$FS_LIST"
      case $? in
        0) FS_OK=1
           ok "image filesystem enumerated ($(wc -l < "$FS_LIST") entries; scamwall binary present)" ;;
        1) # Anchor: without the one file the image is known to contain, the
           # listing is not trustworthy, and every absence derived from it
           # would pass vacuously.
           bad "filesystem listing is untrustworthy (scamwall binary absent from listing) — path absence UNPROVEN" ;;
        *) bad "filesystem listing could not be searched — path absence UNPROVEN" ;;
      esac
    fi
  fi
fi

if [ "$FS_OK" -eq 1 ]; then
  # These assert that SPECIFIC PATHS are absent. They do not, and cannot, rule
  # out an executable placed under some other name.
  note "Absence below is of the ENUMERATED PATHS ONLY, after normalising away a"
  note "leading './' or '/'. An arbitrarily renamed executable is not ruled out."
  absent_path() { # label pattern
    local label="$1" pattern="$2" hits
    if ! hits="$(count_matches "$pattern" "$FS_LIST")"; then
      bad "$label (listing could not be searched — result UNPROVEN)"; return
    fi
    if [ "$hits" -eq 0 ]; then ok "$label"
    else bad "$label — $hits matching path(s) present"; fi
  }
  SHELL_PATTERN='^(usr/)?(local/)?s?bin/(sh|bash|dash|ash|zsh|ksh)$'
  absent_path "no shell at checked paths (sh/bash/dash/ash/zsh/ksh)" "$SHELL_PATTERN"
  absent_path "no busybox at checked paths"                         '^(usr/)?(local/)?s?bin/busybox$'
  absent_path "no package manager at checked paths"                 '^(usr/)?(local/)?s?bin/(apt|apt-get|dpkg|apk|yum|dnf|rpm)$'
  absent_path "no dynamic loader / libc at checked paths"           '^(usr/)?lib.*/(libc|ld-linux)[-.]'
  absent_path "no /etc/passwd"                                      '^etc/passwd$'
  absent_path "no /etc/shadow"                                      '^etc/shadow$'
fi

# --- Resolved deployment configuration ----------------------------------------
#
# ONE argument set resolves the configuration, creates the container and lists
# it. Creation and cleanup previously disagreed — cleanup omitted --env-file —
# so the two commands could be describing different deployments.
#
# The expected values below come from `docker compose config`, which performs
# the same interpolation Compose performs when creating. Re-deriving them by
# grepping .env, stripping quotes by hand, reimplements Compose's precedence
# rules (shell environment over .env, defaults, ${VAR:-x} forms) and gets them
# wrong in exactly the cases that matter.
echo
echo "== resolved deployment configuration =="

OVERRIDE_FILE="$WORK_DIR/verify-ownership-override.yaml"
cat > "$OVERRIDE_FILE" <<OVERRIDE_YAML
# Written by scripts/container-runtime-verify.sh. It adds ONE label, so the
# resources this invocation creates can be attributed to it. It changes no
# security-relevant setting.
services:
  $SERVICE:
    labels:
      $OWN_LABEL: "$INVOCATION"
OVERRIDE_YAML
if [ ! -s "$OVERRIDE_FILE" ]; then
  blocked "the ownership override could not be written — refusing to create unattributable resources"
  summary_and_exit
fi

COMPOSE_ARGS=(-p "$VERIFY_PROJECT")
if [ -f "$ENV_FILE" ]; then
  # Explicit, because Compose resolves a bare .env against the CURRENT WORKING
  # DIRECTORY, not against the compose file's directory. The same array is used
  # for config, create and ps; nothing may use a different set.
  COMPOSE_ARGS+=(--env-file "$ENV_FILE")
  ok "deployment .env supplied explicitly to every Compose invocation"
else
  note "no deployment .env present; Compose defaults apply to every invocation"
fi
COMPOSE_ARGS+=(-f "$COMPOSE" -f "$OVERRIDE_FILE")

CONFIG_JSON="$WORK_DIR/compose-config.json"
CONFIG_ERR="$WORK_DIR/compose-config.err"
if ! docker compose "${COMPOSE_ARGS[@]}" config --format json > "$CONFIG_JSON" 2>"$CONFIG_ERR"; then
  blocked "the deployment configuration could not be resolved"
  print_diagnostic "$CONFIG_ERR"
  summary_and_exit
fi
if ! jq -e 'type == "object"' < "$CONFIG_JSON" >/dev/null 2>&1; then
  blocked "the resolved configuration is not a JSON object — deployment settings UNPROVEN"
  summary_and_exit
fi
ok "deployment configuration resolved and parsed"
note "the resolved configuration is kept in $WORK_DIR (mode 700) and is never printed"

cfg() { jq_read "$CONFIG_JSON" "$1"; }

# --- Configuration features that could escape project isolation ---------------
#
# A private project name only isolates resources that Compose actually names
# after the project. These do not:
#   container_name    fixed, project-independent; it can collide with the real
#                     deployment container and be adopted or removed
#   external: true    the resource is not created or owned by this project
#   extra services    would be created and would need attributing too
CONF_ISSUES=""
conf_issue() { CONF_ISSUES="${CONF_ISSUES}${CONF_ISSUES:+; }$1"; }

if ! SERVICE_NAMES="$(cfg '(.services // {}) | keys | join(",")')"; then
  blocked "the resolved service list could not be read"; summary_and_exit
fi
if [ "$SERVICE_NAMES" = "$SERVICE" ]; then
  ok "exactly one service is defined ($SERVICE)"
else
  bad "unexpected service set '$SERVICE_NAMES' — every service would need attributing before deletion"
  conf_issue "unexpected services: $SERVICE_NAMES"
fi

FIXED_NAMES="$(cfg '[ (.services // {}) | to_entries[] | select(.value.container_name != null) | .key ] | join(",")')" || FIXED_NAMES="<unreadable>"
if [ -z "$FIXED_NAMES" ]; then
  ok "no service sets container_name (project isolation is not bypassed)"
else
  bad "container_name is set on: $FIXED_NAMES — such a container is NOT project-scoped"
  conf_issue "container_name set"
fi

EXTERNALS="$(cfg '[ (.networks // {}), (.volumes // {}), (.secrets // {}) | to_entries[] | select(.value.external == true) | .key ] | join(",")')" || EXTERNALS="<unreadable>"
if [ -z "$EXTERNALS" ]; then
  ok "no externally named networks, volumes or secrets"
else
  bad "externally named resources present: $EXTERNALS — they are not owned by this project"
  conf_issue "external resources: $EXTERNALS"
fi

# `external: true` is only ONE of the two ways a resource escapes the project
# namespace. A network or volume may also carry an explicit `name:` while
# remaining non-external — and Compose then creates OR ADOPTS a resource by
# that exact name. An adopted resource is one the real deployment may own: it
# would be attached to this verification container, could have its
# configuration reconciled, and would be a deletion candidate for any
# name-based teardown. The superseded check inspected `external` only and saw
# nothing wrong with `networks: {default: {name: pihole_net}}`.
#
# So every RESOLVED name is inspected, external or not, and must be exactly the
# name Compose derives from this invocation's private project — `<project>_<key>`.
# Anything else is rejected BEFORE `compose create` runs, which is what makes
# "no pre-existing resource is adopted, changed or deleted" true rather than
# hoped for: nothing is created at all, so nothing can be attached or
# reconciled, and cleanup only ever removes resources this invocation recorded
# or that carry its unpredictable label.
check_namespaced_names() { # section (networks|volumes)
  local section="$1" entries key name expected issues="" line
  if ! entries="$(cfg "[ (.$section // {}) | to_entries[] | .key + \"=\" + ((.value.name // \"\") | tostring) ] | join(\"\n\")")"; then
    blocked "the resolved $section could not be read — resource naming cannot be checked, so nothing is created"
    summary_and_exit
  fi
  [ -n "$entries" ] || { ok "no $section are declared, so none can be adopted"; return 0; }
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    key="${line%%=*}"; name="${line#*=}"
    expected="${VERIFY_PROJECT}_${key}"
    if [ -z "$name" ]; then
      issues="${issues}${issues:+; }$section.$key has no resolved name, so it cannot be shown to be project-scoped"
    elif [ "$name" != "$expected" ]; then
      issues="${issues}${issues:+; }$section.$key resolves to '$name', outside this invocation's namespace (expected '$expected')"
    fi
  done <<< "$entries"
  if [ -z "$issues" ]; then
    ok "every declared $section name lies inside this invocation's namespace"
    return 0
  fi
  bad "a resolved $section name would escape project isolation: $issues"
  conf_issue "$section naming: $issues"
  return 1
}
check_namespaced_names networks
check_namespaced_names volumes

TOP_VOLUMES="$(cfg '(.volumes // {}) | keys | join(",")')" || TOP_VOLUMES="<unreadable>"
if [ -z "$TOP_VOLUMES" ]; then
  ok "no named volumes are declared"
else
  note "named volumes declared: $TOP_VOLUMES (these are removed only if this invocation created them)"
fi

OWN_LABEL_VALUE="$(cfg ".services.\"$SERVICE\".labels.\"$OWN_LABEL\" // \"\"")" || OWN_LABEL_VALUE=""
if [ "$OWN_LABEL_VALUE" = "$INVOCATION" ]; then
  ok "per-invocation ownership label is present in the resolved configuration"
else
  blocked "the ownership label did not survive configuration resolution — refusing to create unattributable resources"
  summary_and_exit
fi

if [ -n "$CONF_ISSUES" ]; then
  blocked "the configuration contains features that escape project isolation ($CONF_ISSUES) — refusing to create resources"
  summary_and_exit
fi

# --- Expected settings, derived from the resolved configuration ---------------
echo
echo "-- expected settings derived from the resolved configuration --"

derive_fail() { bad "$1"; DERIVE_FAILED=1; }
DERIVE_FAILED=0

# Supplementary group. Validated as a value, not merely read: a non-numeric or
# zero gid would grant nothing or grant root's group.
EXPECTED_GID=""
GID_COUNT="$(cfg "(.services.\"$SERVICE\".group_add // []) | length")" || GID_COUNT="?"
if [ "$GID_COUNT" = "1" ]; then
  EXPECTED_GID="$(cfg "(.services.\"$SERVICE\".group_add // [])[0] | tostring")" || EXPECTED_GID=""
fi
if ! is_uint "${EXPECTED_GID:-x}" 1 65535; then
  derive_fail "supplementary group is not a single valid gid (observed count=$GID_COUNT value='${EXPECTED_GID:-none}')"
  EXPECTED_GID=""
else
  ok "supplementary group resolves to a single valid non-root gid ($EXPECTED_GID)"
fi

# Container identity. Derived from the resolved configuration rather than
# assumed: the readability judgement made below is a judgement ABOUT this
# identity, so a guessed uid would make it assert nothing. Anything other than
# a numeric "uid:gid" is refused rather than defaulted — a name would have to
# be resolved inside the image, which this program never starts.
EXPECTED_UID=""
EXPECTED_PRIMARY_GID=""
USER_SPEC="$(cfg ".services.\"$SERVICE\".user // \"\" | tostring")" || USER_SPEC=""
case "$USER_SPEC" in
  *:*) EXPECTED_UID="${USER_SPEC%%:*}"; EXPECTED_PRIMARY_GID="${USER_SPEC#*:}" ;;
esac
if ! is_uint "${EXPECTED_UID:-x}" 1 65535 || ! is_uint "${EXPECTED_PRIMARY_GID:-x}" 1 65535; then
  derive_fail "the container identity is not a single numeric uid:gid (observed '${USER_SPEC:-none}')"
  EXPECTED_UID=""
  EXPECTED_PRIMARY_GID=""
else
  ok "container identity resolves to a numeric non-root uid:gid ($EXPECTED_UID:$EXPECTED_PRIMARY_GID)"
fi

# Hostname pinning. Compose renders extra_hosts as "host=addr" (and older
# versions as a "host:addr" list, or as a map); all three are accepted, and
# anything else is rejected rather than defaulted.
EXPECTED_HOST_ENTRY=""
HOSTS_RAW="$(cfg "
  (.services.\"$SERVICE\".extra_hosts // [])
  | if type == \"object\" then [ to_entries[] | .key + \"=\" + (.value|tostring) ]
    elif type == \"array\" then .
    else [] end
  | map(if test(\"=\") then . else sub(\":\"; \"=\") end)
  | join(\"\n\")")" || HOSTS_RAW=""
HOST_COUNT=0
if [ -n "$HOSTS_RAW" ]; then
  HOST_COUNT="$(printf '%s\n' "$HOSTS_RAW" | grep -c '[^[:space:]]')" || HOST_COUNT=0
fi
if [ "$HOST_COUNT" -ne 1 ]; then
  derive_fail "the API hostname pin is not a single extra_hosts entry (observed $HOST_COUNT)"
else
  PIN_HOST="${HOSTS_RAW%%=*}"
  PIN_ADDR="${HOSTS_RAW#*=}"
  if [ "$PIN_HOST" != "pi.hole" ]; then
    derive_fail "the pinned hostname is '$PIN_HOST', expected 'pi.hole'"
  elif [ -z "$PIN_ADDR" ]; then
    derive_fail "the pinned address for pi.hole is empty"
  elif [ "$PIN_ADDR" = "host-gateway" ] || [[ "$PIN_ADDR" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ "$PIN_ADDR" =~ ^[0-9a-fA-F:]+$ ]]; then
    EXPECTED_HOST_ENTRY="$PIN_HOST:$PIN_ADDR"
    ok "API hostname pin resolves to a single entry ($EXPECTED_HOST_ENTRY)"
  else
    derive_fail "the pinned address '$PIN_ADDR' is neither host-gateway nor an IP literal"
  fi
fi

# Logging bounds.
EXPECTED_LOG_DRIVER="$(cfg ".services.\"$SERVICE\".logging.driver // \"\"")" || EXPECTED_LOG_DRIVER=""
EXPECTED_LOG_MAXSIZE="$(cfg "(.services.\"$SERVICE\".logging.options.\"max-size\" // \"\") | tostring")" || EXPECTED_LOG_MAXSIZE=""
EXPECTED_LOG_MAXFILE="$(cfg "(.services.\"$SERVICE\".logging.options.\"max-file\" // \"\") | tostring")" || EXPECTED_LOG_MAXFILE=""
case "$EXPECTED_LOG_DRIVER" in
  json-file|local) ok "log driver is a bounded local driver ($EXPECTED_LOG_DRIVER)" ;;
  "")  derive_fail "no log driver is configured — log growth is unbounded" ;;
  *)   derive_fail "log driver '$EXPECTED_LOG_DRIVER' is not one this deployment permits" ;;
esac
LOG_SIZE_BYTES=""
LOG_MAXFILE_N=""
if ! LOG_SIZE_BYTES="$(size_to_bytes "$EXPECTED_LOG_MAXSIZE")"; then
  derive_fail "max-size '$EXPECTED_LOG_MAXSIZE' is missing or not a parseable size"
elif [ "$LOG_SIZE_BYTES" -le 0 ] || [ "$LOG_SIZE_BYTES" -gt "$LOG_MAX_SIZE_BYTES" ]; then
  derive_fail "max-size $LOG_SIZE_BYTES bytes is outside the permitted bound"
elif ! LOG_MAXFILE_N="$(to_decimal "$EXPECTED_LOG_MAXFILE" 10)" || [ "$LOG_MAXFILE_N" -lt 1 ]; then
  # Normalised before it is multiplied: `max-file: "09"` is a valid Compose
  # value and an INVALID octal literal, so `$((LOG_SIZE_BYTES * 09))` is a
  # shell error rather than a bound.
  derive_fail "max-file '$EXPECTED_LOG_MAXFILE' is missing or not an integer in 1..10"
elif [ $((LOG_SIZE_BYTES * LOG_MAXFILE_N)) -gt "$LOG_MAX_TOTAL_BYTES" ]; then
  derive_fail "the total log bound ($((LOG_SIZE_BYTES * LOG_MAXFILE_N)) bytes) exceeds the permitted maximum"
else
  ok "log size is bounded (max-size=$EXPECTED_LOG_MAXSIZE, max-file=$EXPECTED_LOG_MAXFILE)"
fi

# tmpfs options, parsed rather than substring-matched.
EXPECTED_TMPFS="$(cfg "
  [ (.services.\"$SERVICE\".tmpfs // []) | (if type == \"string\" then [.] else . end)[]
    | select(startswith(\"/tmp:\")) | sub(\"^/tmp:\"; \"\") ] | first // \"\"")" || EXPECTED_TMPFS=""
validate_tmpfs_options "configured /tmp tmpfs options are bounded and hardened" "$EXPECTED_TMPFS"

# Resource bounds.
EXPECTED_MEM=""
MEM_RAW="$(cfg "(.services.\"$SERVICE\".mem_limit // \"\") | tostring")" || MEM_RAW=""
if ! EXPECTED_MEM="$(size_to_bytes "$MEM_RAW")"; then
  derive_fail "mem_limit '$MEM_RAW' is missing or not a parseable size"
elif [ "$EXPECTED_MEM" -le 0 ] || [ "$EXPECTED_MEM" -gt "$MEM_MAX_BYTES" ]; then
  derive_fail "mem_limit $EXPECTED_MEM bytes is outside the permitted bound"
else
  ok "memory limit is bounded ($EXPECTED_MEM bytes)"
fi
EXPECTED_MEMSWAP=""
MEMSWAP_RAW="$(cfg "(.services.\"$SERVICE\".memswap_limit // \"\") | tostring")" || MEMSWAP_RAW=""
if ! EXPECTED_MEMSWAP="$(size_to_bytes "$MEMSWAP_RAW")"; then
  derive_fail "memswap_limit '$MEMSWAP_RAW' is missing or not a parseable size"
elif [ -n "$EXPECTED_MEM" ] && [ "$EXPECTED_MEMSWAP" -ne "$EXPECTED_MEM" ]; then
  derive_fail "memswap_limit ($EXPECTED_MEMSWAP) differs from mem_limit ($EXPECTED_MEM): swap would be available"
else
  ok "swap is not additional to the memory limit"
fi
EXPECTED_PIDS="$(cfg "(.services.\"$SERVICE\".pids_limit // \"\") | tostring")" || EXPECTED_PIDS=""
if ! is_uint "$EXPECTED_PIDS" 1 1024; then
  derive_fail "pids_limit '$EXPECTED_PIDS' is missing or outside 1..1024"
else
  ok "pid count is bounded ($EXPECTED_PIDS)"
fi
EXPECTED_NANOCPUS="$(cfg "((.services.\"$SERVICE\".cpus // 0) * 1000000000) | round | tostring")" || EXPECTED_NANOCPUS=""
if ! is_uint "$EXPECTED_NANOCPUS" 1 2000000000; then
  derive_fail "cpus is missing or outside the permitted bound (resolved nanocpus '$EXPECTED_NANOCPUS')"
else
  ok "cpu share is bounded ($EXPECTED_NANOCPUS nanocpus)"
fi

# Mounts: the configuration and secret bind mounts that MUST be present.
EXPECTED_MOUNTS="$WORK_DIR/expected-mounts.txt"
if ! cfg "
  [ (.services.\"$SERVICE\".volumes // [])[]
      | (.type // \"?\") + \"|\" + (.source // \"?\") + \"|\" + (.target // \"?\") + \"|\"
        + (if .read_only == true then \"ro\" else \"rw\" end) ]
  + [ (.services.\"$SERVICE\".secrets // [])[] as \$s
      | \"bind|\" + ((.secrets[\$s.source].file) // \"?\") + \"|\"
        + (\$s.target // (\"/run/secrets/\" + \$s.source)) + \"|ro\" ]
  | sort | .[]" > "$EXPECTED_MOUNTS"; then
  derive_fail "the expected mount set could not be derived from the resolved configuration"
  : > "$EXPECTED_MOUNTS"
fi
# Exactly the approved set — not "at least the four required ones". A count
# floor accepted any number of additional mounts as long as the four were
# among them.
if ! CONFIG_MOUNT_PROBLEMS="$(approved_mount_problems "$EXPECTED_MOUNTS")"; then
  derive_fail "the expected mount set could not be examined against the approved set"
elif [ -n "$CONFIG_MOUNT_PROBLEMS" ]; then
  derive_fail "the resolved configuration does not declare exactly the approved mounts: $CONFIG_MOUNT_PROBLEMS"
else
  ok "the resolved configuration declares exactly the $APPROVED_MOUNT_COUNT approved mounts, each a read-only bind with a resolved source"
fi
for required_dest in /etc/scamwall/certs/pihole-ca.crt /etc/scamwall/config.json /etc/scamwall/feed.json /run/secrets/pihole_app_password; do
  search_file "\\|${required_dest}\\|ro\$" "$EXPECTED_MOUNTS"
  case $? in
    0) ok "the configuration requires a read-only mount at $required_dest" ;;
    1) derive_fail "the configuration does not require a read-only mount at $required_dest" ;;
    *) derive_fail "the expected mount set could not be searched for $required_dest" ;;
  esac
done
# The secret's source is examined by the SAME prohibited-path rule as the
# volumes. It was previously exempt, because it is declared under a different
# key — and it is the one source with an environment override
# (SCAMWALL_SECRET_FILE), so it is the one most easily pointed somewhere it
# should not go. `${SCAMWALL_CA_FILE}` is a second such override now, and it
# lives under .volumes, so it is covered by the existing arm.
if ! MOUNT_SOURCE_ISSUES="$(cfg "
  [ ((.services.\"$SERVICE\".volumes // [])[] | { source: (.source // \"\"), target: (.target // \"\") }),
    ((.secrets // {}) | to_entries[] | { source: (.value.file // \"\"), target: (\"secret \" + .key) })
      | select((.source | test(\"docker\\\\.sock|^/etc/pihole|^/var/lib/docker|^/var/run/docker|^/proc|^/sys|^/dev(/|\$)|^/\$|^/etc\$|^/root|^/home\$\"))
               or (.target | test(\"docker\\\\.sock|^/etc/pihole\")))
      | .source + \" -> \" + .target ] | join(\"; \")")"; then
  derive_fail "the configured mount sources could not be examined"
elif [ -n "$MOUNT_SOURCE_ISSUES" ]; then
  derive_fail "the configuration mounts a prohibited path: $MOUNT_SOURCE_ISSUES"
else
  ok "no prohibited path appears in the configured mounts or in the secret source"
fi

# --- Mount sources on this host ------------------------------------------------
#
# Every approved mount is a FILE. Two ways a deployment can satisfy every
# assertion so far and still be wrong:
#
#   * the source does not exist. Docker's default is to CREATE an empty
#     directory at a missing bind source and mount that, so a deployment with
#     no CA and no password file still produces a container whose mount set,
#     destinations and read-only flags are all exactly as required.
#     `bind.create_host_path: false` in compose.yaml now refuses that, but the
#     refusal surfaces as a Compose error part-way through creation; naming the
#     path here, before anything is created, is what makes it diagnosable.
#   * the source exists and is a DIRECTORY. `create_host_path` says nothing
#     about this one: the mount succeeds, and the container gets an empty
#     directory where its trust anchor or its credential should be.
#
# This is the check that makes a hosted runner and the operator's host
# comparable. Neither environment is exempt from it, and CI passes it by
# materialising throwaway fixtures rather than by skipping the assertion.
MOUNT_SOURCE_STATE=""
while IFS='|' read -r _mtype msource mdest _mmode; do
  [ -n "${mdest:-}" ] || continue
  [ -n "${msource:-}" ] || { MOUNT_SOURCE_STATE="${MOUNT_SOURCE_STATE}${MOUNT_SOURCE_STATE:+; }$mdest has no source"; continue; }
  if [ ! -e "$msource" ]; then
    MOUNT_SOURCE_STATE="${MOUNT_SOURCE_STATE}${MOUNT_SOURCE_STATE:+; }$mdest <- '$msource' does not exist"
  elif [ -d "$msource" ]; then
    MOUNT_SOURCE_STATE="${MOUNT_SOURCE_STATE}${MOUNT_SOURCE_STATE:+; }$mdest <- '$msource' is a directory, not a file"
  elif [ ! -f "$msource" ]; then
    MOUNT_SOURCE_STATE="${MOUNT_SOURCE_STATE}${MOUNT_SOURCE_STATE:+; }$mdest <- '$msource' is not a regular file"
  fi
done < "$EXPECTED_MOUNTS"
if [ -z "$MOUNT_SOURCE_STATE" ]; then
  ok "every approved mount resolves to an existing regular file on this host"
else
  derive_fail "a configured mount source is missing or is not a regular file: $MOUNT_SOURCE_STATE"
fi

# The application password must not be readable by every account on the host.
#
# Mode alone is not the answer: a 0644 file inside a 0750 directory is not
# world-readable, and a 0640 file whose directory is 0777 still is not. What
# matters is REACHABILITY — the file's own other-read bit AND an
# other-executable bit on every directory above it — so that is what is
# computed. `stat` failing is neither verdict: it is reported as undetermined.
secret_world_reachable() { # <file> -> 0 reachable, 1 not, 2 undetermined
  local f="$1" mode dir parent
  mode="$(stat -c '%a' -- "$f" 2>/dev/null)" || return 2
  [ -n "$mode" ] || return 2
  case "${mode: -1}" in
    4|5|6|7) ;;
    *) return 1 ;;
  esac
  dir="$(dirname -- "$f")" || return 2
  while :; do
    mode="$(stat -c '%a' -- "$dir" 2>/dev/null)" || return 2
    [ -n "$mode" ] || return 2
    case "${mode: -1}" in
      1|3|5|7) ;;
      *) return 1 ;;
    esac
    [ "$dir" != "/" ] || break
    parent="$(dirname -- "$dir")" || return 2
    [ "$parent" != "$dir" ] || break
    dir="$parent"
  done
  return 0
}
SECRET_SOURCE="$(cfg '[ (.secrets // {}) | to_entries[] | (.value.file // "") ] | first // ""')" || SECRET_SOURCE=""
if [ -z "$SECRET_SOURCE" ]; then
  derive_fail "the application password source could not be read from the resolved configuration"
else
  secret_world_reachable "$SECRET_SOURCE"
  case $? in
    0) derive_fail "the application password file is readable by every account on this host" ;;
    1) ok "the application password file is not world-readable through its path" ;;
    *) derive_fail "the application password file's permissions could not be determined — its exposure is UNPROVEN" ;;
  esac
fi

# --- Can the container identity read the application password? ----------------
#
# This is a METADATA judgement, and the distinction is load-bearing.
#
# What it establishes: that the file's owner, owning group and permission bits
# are such that a process running as the configured uid, with the configured
# primary and supplementary groups, WOULD be granted read by the ordinary UNIX
# permission check. That is the property the supplementary group exists to
# provide, and until now the verifier asserted the group's VALUE without ever
# relating it to the file the group is supposed to open.
#
# What it does NOT establish: that a read actually succeeds inside the
# container. This program never starts one. Four assumptions stand between the
# metadata and the outcome, and each is checked or stated rather than ignored:
#
#   * POSIX ACLs. An ACL mask can reduce the effective group permission below
#     what the mode bits show, and a named ACL entry can grant access the mode
#     bits do not. Both are examined where `getfacl` is available; where it is
#     not, and the file carries an extended ACL, the result is UNDETERMINED
#     rather than a pass.
#   * User-namespace remapping. Under `userns-remap`, the uid and gid inside
#     the container map to different host ids, so host metadata no longer
#     predicts container access. Asked of the daemon below rather than assumed.
#   * Rootless Docker. The same shift applies, by a different mechanism.
#   * Path traversal. Not a factor for the container: the daemon resolves the
#     bind source as root before the mount exists, so the ancestor directory
#     modes gate the HOST, not the container. They are checked above for a
#     different reason — world-reachability — and not re-checked here.
#
# The actual read, performed by a started container against a disposable
# deployment, is Phase 2 work order item 5 and stays open.

# secret_identity_read <file> <uid> <primary-gid> <supplementary-gid>
#   0 read would be granted   1 read would be refused   2 undetermined
# On success SECRET_READ_PATH names which permission class granted it.
SECRET_READ_PATH=""
SECRET_META=""
secret_identity_read() {
  local f="$1" uid="$2" gid1="$3" gid2="$4"
  local statline fu fg fmode owner group
  SECRET_READ_PATH=""
  statline="$(stat -c '%u %g %a' -- "$f" 2>/dev/null)" || return 2
  read -r fu fg fmode <<<"$statline"
  [ -n "${fu:-}" ] && [ -n "${fg:-}" ] && [ -n "${fmode:-}" ] || return 2
  # Normalise to four octal digits so the positional extraction is exact:
  # `stat -c %a` prints "640", not "0640", and prints four digits when a
  # setuid, setgid or sticky bit is present.
  while [ "${#fmode}" -lt 4 ]; do fmode="0$fmode"; done
  owner="${fmode: -3:1}"
  group="${fmode: -2:1}"
  SECRET_META="uid=$fu gid=$fg mode=$fmode"
  if [ "$fu" = "$uid" ]; then
    case "$owner" in
      4|5|6|7) SECRET_READ_PATH="the file's owner uid ($uid)"; return 0 ;;
    esac
  fi
  if [ "$fg" = "$gid1" ] || [ "$fg" = "$gid2" ]; then
    case "$group" in
      4|5|6|7) SECRET_READ_PATH="the owning group gid ($fg)"; return 0 ;;
    esac
  fi
  return 1
}

# secret_acl_verdict <file>
#   0 no extended ACL, or one that does not change the answer
#   1 an ACL mask strips read from the group class
#   2 undetermined: an extended ACL is present and cannot be read
# ACL_NOTE carries a printable summary; it contains permission metadata only.
ACL_NOTE=""
secret_acl_verdict() {
  local f="$1" lsline acl mask
  ACL_NOTE=""
  lsline="$(ls -ld -- "$f" 2>/dev/null)" || return 2
  case "$lsline" in
    ??????????+*) ;;
    *) ACL_NOTE="no extended ACL"; return 0 ;;
  esac
  command -v getfacl >/dev/null 2>&1 || { ACL_NOTE="an extended ACL is present and getfacl is not installed"; return 2; }
  acl="$(getfacl -c -- "$f" 2>/dev/null)" || { ACL_NOTE="an extended ACL is present and could not be read"; return 2; }
  mask="$(sed -n 's/^mask::\(.*\)$/\1/p' <<<"$acl" | head -n 1)"
  if [ -z "$mask" ]; then
    ACL_NOTE="an extended ACL is present with no mask entry"
    return 0
  fi
  ACL_NOTE="extended ACL present, mask::$mask"
  case "$mask" in
    r*) return 0 ;;
    *)  return 1 ;;
  esac
}

if [ -n "${SECRET_SOURCE:-}" ] && [ -n "${EXPECTED_UID:-}" ] && [ -n "${EXPECTED_GID:-}" ]; then
  secret_identity_read "$SECRET_SOURCE" "$EXPECTED_UID" "$EXPECTED_PRIMARY_GID" "$EXPECTED_GID"
  case $? in
    0)
      secret_acl_verdict "$SECRET_SOURCE"
      case $? in
        0) ok "the application password would be readable by the container identity through $SECRET_READ_PATH ($SECRET_META; $ACL_NOTE)" ;;
        1) derive_fail "an ACL mask on the application password strips read from the group class, so $SECRET_READ_PATH does not in fact grant it ($SECRET_META; $ACL_NOTE)" ;;
        *) derive_fail "the application password's effective permissions are UNPROVEN: $ACL_NOTE ($SECRET_META)" ;;
      esac
      ;;
    1)
      derive_fail "the application password would NOT be readable by the container identity: $SECRET_META, but the container runs as uid $EXPECTED_UID with groups $EXPECTED_PRIMARY_GID and $EXPECTED_GID — the supplementary group does not own the file, or the file's group-read bit is unset"
      ;;
    *)
      derive_fail "the application password's ownership and mode could not be determined — its readability by the container identity is UNPROVEN"
      ;;
  esac
  note "this is a judgement on HOST METADATA. It says the permission check"
  note "would grant a read; it does not say a read was performed. This"
  note "program never starts the container, so nothing here opens the file."
else
  derive_fail "the application password's readability could not be judged: one of the secret source, the container uid or the supplementary gid was not derived"
fi

# User-namespace remapping shifts every id between the host and the container,
# which would invalidate the judgement above. The daemon reports it, so it is
# asked rather than assumed. A daemon that cannot be asked leaves the
# assumption stated rather than checked.
USERNS_MODE="$(docker info --format '{{.SecurityOptions}}' 2>/dev/null)" || USERNS_MODE=""
case "$USERNS_MODE" in
  *userns*)
    derive_fail "this daemon reports user-namespace remapping, so host uid/gid metadata does not describe what the container identity can read"
    ;;
  "")
    note "the daemon could not be asked about user-namespace remapping; the"
    note "readability judgement above assumes host ids are container ids."
    ;;
  *)
    ok "the daemon reports no user-namespace remapping, so host ids are container ids"
    ;;
esac
case "$USERNS_MODE" in
  *rootless*)
    derive_fail "this daemon is rootless, so the bind source is presented under a shifted id map and the readability judgement above does not apply"
    ;;
esac

if [ "$DERIVE_FAILED" -ne 0 ]; then
  blocked "expected settings could not be derived from the resolved configuration — container assertions would compare against guesses"
  summary_and_exit
fi

# --- Deployment container -----------------------------------------------------
echo
echo "== deployment container =="
note "private Compose project: $VERIFY_PROJECT"
note "created with the SAME argument set used to resolve the configuration"

# Creation status is checked EXPLICITLY. Previously the status was discarded
# and the container id looked up afterwards, so a pre-existing container could
# stand in for one that was never created.
CREATE_LOG="$WORK_DIR/create.log"
if ! docker compose "${COMPOSE_ARGS[@]}" create --no-build --quiet-pull > "$CREATE_LOG" 2>&1; then
  bad "compose create failed — container assertions UNPROVEN"
  print_diagnostic "$CREATE_LOG"
  note "any resource this partial creation did produce is removed by cleanup below"
  summary_and_exit
fi
ok "compose create succeeded (exit 0)"

# The authoritative list is a LABEL query, not a name query: it finds every
# container this invocation caused to exist, including one created by a service
# that was added to the definition after this program was written.
if ! PROJECT_CONTAINERS="$(label_query container "$PROJECT_LABEL=$VERIFY_PROJECT")"; then
  bad "containers created by this invocation could not be listed — container assertions UNPROVEN"
  summary_and_exit
fi
PROJECT_CONTAINER_COUNT="$(printf '%s\n' "$PROJECT_CONTAINERS" | grep -c '[^[:space:]]')" || PROJECT_CONTAINER_COUNT=0
if [ "$PROJECT_CONTAINER_COUNT" -ne 1 ]; then
  bad "expected exactly 1 container in project $VERIFY_PROJECT, found $PROJECT_CONTAINER_COUNT — UNPROVEN"
  summary_and_exit
fi
CID="$(printf '%s\n' "$PROJECT_CONTAINERS" | grep '[^[:space:]]' | tail -1)"
CREATED_CONTAINERS+=("$CID")

# Compose's own view must agree with the label query. If it does not, the
# container being inspected is not the one Compose created for this service.
if ! COMPOSE_CID_LIST="$(docker compose "${COMPOSE_ARGS[@]}" ps -aq "$SERVICE" 2>/dev/null)"; then
  bad "the created service container could not be listed by Compose — container assertions UNPROVEN"
  summary_and_exit
fi
COMPOSE_CID_COUNT="$(printf '%s\n' "$COMPOSE_CID_LIST" | grep -c '[^[:space:]]')" || COMPOSE_CID_COUNT=0
COMPOSE_CID="$(printf '%s\n' "$COMPOSE_CID_LIST" | grep '[^[:space:]]' | tail -1)"
if [ "$COMPOSE_CID_COUNT" -ne 1 ]; then
  bad "Compose reports $COMPOSE_CID_COUNT containers for service $SERVICE, expected 1 — UNPROVEN"
  summary_and_exit
fi
if [ "${CID:0:12}" != "${COMPOSE_CID:0:12}" ]; then
  bad "the labelled container ($CID) is not the one Compose reports ($COMPOSE_CID) — UNPROVEN"
  summary_and_exit
fi
ok "inspection container created (not started) and attributed to this invocation"

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

echo
echo "-- required inspection fields --"
# Every field the assertions below read must EXIST, with the right type, before
# any of them is evaluated. Optional-by-Docker fields are listed with null
# among their permitted types and only where null genuinely means "none":
#   CapAdd            null when no capability was added — which is the requirement
#   Config.Labels     null when the container carries no label at all
require_fields "$CJSON" "inspection field" \
  '.[0].Image::string' \
  '.[0].State::object' \
  '.[0].State.Status::string' \
  '.[0].State.Running::boolean' \
  '.[0].State.Pid::number' \
  '.[0].State.StartedAt::string' \
  '.[0].RestartCount::number' \
  '.[0].Config::object' \
  '.[0].Config.User::string' \
  '.[0].Config.Labels::object,null' \
  '.[0].HostConfig::object' \
  '.[0].HostConfig.GroupAdd::array' \
  '.[0].HostConfig.CapDrop::array' \
  '.[0].HostConfig.CapAdd::array,null' \
  '.[0].HostConfig.Privileged::boolean' \
  '.[0].HostConfig.SecurityOpt::array' \
  '.[0].HostConfig.Init::boolean' \
  '.[0].HostConfig.ReadonlyRootfs::boolean' \
  '.[0].HostConfig.Tmpfs::object' \
  '.[0].HostConfig.NetworkMode::string' \
  '.[0].HostConfig.ExtraHosts::array' \
  '.[0].HostConfig.PortBindings::object' \
  '.[0].HostConfig.LogConfig::object' \
  '.[0].HostConfig.LogConfig.Type::string' \
  '.[0].HostConfig.LogConfig.Config::object' \
  '.[0].HostConfig.Memory::number' \
  '.[0].HostConfig.MemorySwap::number' \
  '.[0].HostConfig.PidsLimit::number' \
  '.[0].HostConfig.NanoCpus::number' \
  '.[0].HostConfig.RestartPolicy::object' \
  '.[0].HostConfig.RestartPolicy.Name::string' \
  '.[0].NetworkSettings::object' \
  '.[0].NetworkSettings.Ports::object' \
  && ok "every required inspection field is present with the expected type"

assert_eq "container carries this invocation's ownership label" "$CJSON" \
  "(.[0].Config.Labels // {})[\"$OWN_LABEL\"] // \"<absent>\"" "$INVOCATION"

# --- Image identity of the created container ----------------------------------
#
# Compose creates from the TAG in the compose file. This comparison is what
# detects a tag that moved between resolution and creation: the container would
# then record a different image ID than the one every image-level assertion
# above was made against.
if ! CONTAINER_IMAGE="$(jq_read "$CJSON" '.[0].Image')"; then
  bad "the container's image identifier could not be read — image identity UNPROVEN"
elif [ "$CONTAINER_IMAGE" = "$IMAGE_ID" ]; then
  ok "container image matches the resolved image ID ($IMAGE_ID)"
else
  # Not automatically a mismatch. Docker's image stores do not all record the
  # same identifier: with the containerd store, `docker image inspect` may
  # report a manifest digest where a container records the config digest. The
  # question is whether both identifiers name the SAME image, so ask the daemon
  # to resolve the container's identifier and compare the resolutions.
  RESOLVED_FROM_CONTAINER=""
  if CONTAINER_IMAGE_JSON="$(docker image inspect "$CONTAINER_IMAGE" 2>/dev/null)"; then
    RESOLVED_FROM_CONTAINER="$(jq -r '.[0].Id // ""' <<< "$CONTAINER_IMAGE_JSON" 2>/dev/null)" || RESOLVED_FROM_CONTAINER=""
  fi
  if [ -n "$RESOLVED_FROM_CONTAINER" ] && [ "$RESOLVED_FROM_CONTAINER" = "$IMAGE_ID" ]; then
    ok "container image resolves to the verified image (container records $CONTAINER_IMAGE, which resolves to $IMAGE_ID)"
  else
    MISMATCH_DETAIL=""
    [ -n "$RESOLVED_FROM_CONTAINER" ] && MISMATCH_DETAIL=" (that identifier resolves to $RESOLVED_FROM_CONTAINER)"
    bad "container image mismatch: the container records $CONTAINER_IMAGE, verification resolved $IMAGE_ID$MISMATCH_DETAIL"
    note "a tag moved between image resolution and container creation would look exactly like this"
  fi
fi
REQUESTED_REF="$(jq_read "$CJSON" '.[0].Config.Image // ""')" || REQUESTED_REF="<unreadable>"
note "the container recorded the requested reference as '${REQUESTED_REF:-<none>}' (a tag; not an identity)"

echo
echo "-- no application execution --"
# `docker compose create` and `docker create` do not start a process. These
# assertions state that positively rather than assuming it.
# No `//` defaults: the fields were required above, and a default here would
# turn "the daemon reported no Pid" into "the process id is zero".
assert_eq   "container is created, not running" "$CJSON" '.[0].State.Status' 'created'
assert_true "container has never run"           "$CJSON" '.[0].State.Running == false'
assert_eq   "no process id is recorded"         "$CJSON" '.[0].State.Pid | tostring' '0'
assert_true "no start time is recorded"         "$CJSON" '(.[0].State.StartedAt | type == "string") and (.[0].State.StartedAt | (. == "" or startswith("0001-01-01")))'
assert_eq   "restart count is zero"             "$CJSON" '.[0].RestartCount | tostring' '0'

echo
echo "-- identity and privileges --"
assert_eq   "container user"                "$CJSON" '.[0].Config.User' '65532:65532'
assert_eq   "supplementary group"           "$CJSON" '.[0].HostConfig.GroupAdd | join(",")' "$EXPECTED_GID"
assert_eq   "exactly one supplementary group" "$CJSON" '.[0].HostConfig.GroupAdd | length | tostring' '1'
assert_eq   "capabilities dropped"          "$CJSON" '.[0].HostConfig.CapDrop | join(",")' 'ALL'
# CapAdd is the one list Docker genuinely renders as null when nothing was
# added, and null IS the requirement here, so the default is permitted.
assert_eq   "no capabilities added"         "$CJSON" '(.[0].HostConfig.CapAdd // []) | length | tostring' '0'
assert_true "not privileged"                "$CJSON" '.[0].HostConfig.Privileged == false'
assert_true "no-new-privileges set"         "$CJSON" '(.[0].HostConfig.SecurityOpt | map(select(. == "no-new-privileges:true")) | length) == 1'
assert_true "no unconfined seccomp/apparmor" "$CJSON" '(.[0].HostConfig.SecurityOpt | map(select(test("unconfined"))) | length) == 0'
assert_true "init process enabled"          "$CJSON" '.[0].HostConfig.Init == true'

echo
echo "-- filesystem and mounts --"
assert_true "rootfs read-only" "$CJSON" '.[0].HostConfig.ReadonlyRootfs == true'

# .Mounts must be a NON-EMPTY array before any absence claim is made about it.
# An absent or empty .Mounts previously satisfied both "every mount is
# read-only" and "no prohibited mounts" without a single mount being examined,
# and it also hid the absence of the mounts the deployment requires.
MOUNTS_OK=0
MOUNTS_TYPE="$(jq_read "$CJSON" '.[0].Mounts | type')" || MOUNTS_TYPE=""
MOUNTS_LEN="$(jq_read "$CJSON" '(.[0].Mounts // []) | length | tostring')" || MOUNTS_LEN="0"
if [ "$MOUNTS_TYPE" != "array" ]; then
  bad "mount information is absent from the inspection output (.Mounts is '${MOUNTS_TYPE:-missing}') — every mount requirement is UNPROVEN"
elif ! is_uint "$MOUNTS_LEN" 1; then
  bad "the container records no mounts at all — the configuration, feed, CA and password mounts are all missing"
else
  MOUNTS_OK=1
  ok "mount information present ($MOUNTS_LEN mounts recorded)"
fi

if [ "$MOUNTS_OK" -eq 1 ]; then
  OBSERVED_MOUNTS="$WORK_DIR/observed-mounts.txt"
  # tmpfs at /tmp is excluded here and validated separately below: Docker
  # represents a compose `tmpfs:` entry through HostConfig.Tmpfs, and its
  # appearance in .Mounts carries no source or options to compare.
  if ! jq -r '[ .[0].Mounts[]
                | select((((.Type // "") == "tmpfs") and ((.Destination // "") == "/tmp")) | not)
                | ((.Type // "?") + "|" + (.Source // "?") + "|" + (.Destination // "?") + "|"
                   + (if .RW == false then "ro" else "rw" end)) ] | sort | .[]' \
       < "$CJSON" > "$OBSERVED_MOUNTS" 2>/dev/null; then
    bad "the observed mount set could not be extracted — mount requirements UNPROVEN"
  else
    # The observed set is held to the SAME fixed approved set as the
    # configuration, and not merely to agreement with it. An extra mount
    # present in both compose.yaml and `docker inspect` is invisible to the
    # comparison below — the two sides agree — but it is still a mount this
    # deployment does not permit, and it is caught here.
    if ! OBSERVED_MOUNT_PROBLEMS="$(approved_mount_problems "$OBSERVED_MOUNTS")"; then
      bad "the observed mount set could not be examined against the approved set — mount requirements UNPROVEN"
    elif [ -n "$OBSERVED_MOUNT_PROBLEMS" ]; then
      bad "the container does not have exactly the approved mounts: $OBSERVED_MOUNT_PROBLEMS"
    else
      ok "the container has exactly the $APPROVED_MOUNT_COUNT approved mounts, each a read-only bind with a resolved source"
    fi

    # A sort or a comparison that could not run is a FAILED gate, never a
    # clean one. `sort ... || true` discarded the status of the very step the
    # comparison depends on, and an unsorted operand makes `comm` report
    # arbitrary differences — or none at all.
    MOUNT_COMPARE_OK=1
    if ! LC_ALL=C sort -o "$OBSERVED_MOUNTS" "$OBSERVED_MOUNTS"; then
      bad "the observed mount set could not be sorted — the mount comparison did not run and is UNPROVEN"
      MOUNT_COMPARE_OK=0
    fi
    if ! LC_ALL=C sort -o "$EXPECTED_MOUNTS" "$EXPECTED_MOUNTS"; then
      bad "the expected mount set could not be sorted — the mount comparison did not run and is UNPROVEN"
      MOUNT_COMPARE_OK=0
    fi
    if [ "$MOUNT_COMPARE_OK" -eq 1 ]; then
      if ! MISSING_MOUNTS="$(LC_ALL=C comm -23 "$EXPECTED_MOUNTS" "$OBSERVED_MOUNTS" | tr '\n' ' ')"; then
        bad "the mount comparison failed (comm could not compare the two sets) — mount requirements UNPROVEN"
        MOUNT_COMPARE_OK=0
      elif ! EXTRA_MOUNTS="$(LC_ALL=C comm -13 "$EXPECTED_MOUNTS" "$OBSERVED_MOUNTS" | tr '\n' ' ')"; then
        bad "the mount comparison failed (comm could not compare the two sets) — mount requirements UNPROVEN"
        MOUNT_COMPARE_OK=0
      fi
    fi
    if [ "$MOUNT_COMPARE_OK" -eq 1 ]; then
      if [ -z "${MISSING_MOUNTS// /}" ]; then
        ok "every required mount is present with the expected type, resolved source and read-only status"
      else
        bad "required mount(s) missing or differing (type|source|destination|mode): $MISSING_MOUNTS"
      fi
      if [ -z "${EXTRA_MOUNTS// /}" ]; then
        ok "no unexpected mounts (only the tmpfs at /tmp is runtime-managed and is checked separately)"
      else
        bad "unexpected mount(s) present: $EXTRA_MOUNTS"
      fi
    fi
  fi

  assert_eq "no duplicate mount destinations" "$CJSON" \
    '[ .[0].Mounts[].Destination ] | group_by(.) | map(select(length > 1)) | length | tostring' '0'

  # Every mount EXCEPT the runtime-managed scratch tmpfs, which is writable by
  # design and is validated separately (noexec, nosuid, nodev, bounded size).
  # Naming the one exception here keeps "read-only" an exact claim rather than
  # one with an unstated exemption.
  assert_empty_list "every mount except the /tmp scratch tmpfs is read-only" "$CJSON" \
    '[ .[0].Mounts[]
       | select((((.Type // "") == "tmpfs") and ((.Destination // "") == "/tmp")) | not)
       | select(.RW != false) | (.Destination // "?") ] | join(", ")'

  # Prohibited mounts are detected through .Mounts, which covers bind mounts,
  # volumes and tmpfs alike. .HostConfig.Binds only reflects one way of asking
  # for a mount and misses the others entirely.
  assert_empty_list "no prohibited mount source or destination" "$CJSON" \
    '[ .[0].Mounts[]
       | select(((.Source // "") | test("docker\\.sock|^/etc/pihole|^/var/lib/docker|^/var/run/docker|^/proc|^/sys|^/dev(/|$)|^/$|^/etc$|^/root|^/home$"))
                or ((.Destination // "") | test("docker\\.sock|^/etc/pihole|^/proc|^/sys|^/dev(/|$)")))
       | ((.Source // "?") + " -> " + (.Destination // "?")) ] | join("; ")'

  note "A read-only mount at /run/secrets/pihole_app_password does NOT prove the"
  note "container identity can read it. That depends on the host file's owner,"
  note "group and mode, which this program does not inspect and does not claim."
fi

# /tmp is validated from HostConfig.Tmpfs, where Docker records the options.
OBSERVED_TMPFS="$(jq_read "$CJSON" '((.[0].HostConfig.Tmpfs // {})["/tmp"] // "")')" || OBSERVED_TMPFS="<unreadable>"
if [ "$OBSERVED_TMPFS" = "<unreadable>" ]; then
  bad "tmpfs options could not be read from the inspection output — /tmp hardening UNPROVEN"
else
  validate_tmpfs_options "container /tmp tmpfs is hardened and size-bounded" "$OBSERVED_TMPFS"
  if [ "$OBSERVED_TMPFS" = "$EXPECTED_TMPFS" ]; then
    ok "container tmpfs options match the resolved configuration"
  else
    bad "container tmpfs options '$OBSERVED_TMPFS' differ from the configured '$EXPECTED_TMPFS'"
  fi
fi

echo
echo "-- network --"
# `// ""` here made an ABSENT NetworkMode satisfy both assertions: the empty
# string is neither "host" nor a "container:" prefix. The field is required
# above and is read without a default.
assert_true "not on host network"    "$CJSON" '(.[0].HostConfig.NetworkMode | type == "string") and (.[0].HostConfig.NetworkMode != "host")'
assert_true "not sharing a container netns" "$CJSON" '(.[0].HostConfig.NetworkMode | type == "string") and ((.[0].HostConfig.NetworkMode | startswith("container:")) == false)'
# The type is part of the expected value: jq reports `null | length` as 0, so a
# bare length check treats a MISSING port map as an empty one.
assert_eq   "no published port bindings" "$CJSON" '(.[0].HostConfig.PortBindings | type) + ":" + (.[0].HostConfig.PortBindings | length | tostring)' 'object:0'
assert_eq   "no exposed container ports" "$CJSON" '(.[0].NetworkSettings.Ports | type) + ":" + (.[0].NetworkSettings.Ports | length | tostring)' 'object:0'

# Hostname pinning. ScamWall must never authenticate to whatever happens to
# answer DNS for the API name, so the mapping is asserted exactly: one entry,
# for the expected name, with the resolved address from the configuration.
assert_eq "API hostname pinned to exactly one address" "$CJSON" \
  '(.[0].HostConfig.ExtraHosts | type) + ":" + (.[0].HostConfig.ExtraHosts | length | tostring)' 'array:1'
assert_eq "API hostname pin matches the resolved configuration" "$CJSON" \
  '.[0].HostConfig.ExtraHosts | join(",")' "$EXPECTED_HOST_ENTRY"

echo
echo "-- logging --"
assert_eq "log driver" "$CJSON" '.[0].HostConfig.LogConfig.Type' "$EXPECTED_LOG_DRIVER"
# A missing bound is reported as `<absent>`, which no configured value equals,
# rather than as an empty string that a configuration could also produce.
assert_eq "log max-size" "$CJSON" '(.[0].HostConfig.LogConfig.Config["max-size"] // "<absent>") | tostring' "$EXPECTED_LOG_MAXSIZE"
assert_eq "log max-file" "$CJSON" '(.[0].HostConfig.LogConfig.Config["max-file"] // "<absent>") | tostring' "$EXPECTED_LOG_MAXFILE"

echo
echo "-- resource bounds --"
assert_eq "memory limit"      "$CJSON" '.[0].HostConfig.Memory | tostring'     "$EXPECTED_MEM"
assert_eq "memory+swap limit" "$CJSON" '.[0].HostConfig.MemorySwap | tostring' "$EXPECTED_MEMSWAP"
assert_eq "pids limit"        "$CJSON" '.[0].HostConfig.PidsLimit | tostring'  "$EXPECTED_PIDS"
assert_eq "cpu limit"         "$CJSON" '.[0].HostConfig.NanoCpus | tostring'   "$EXPECTED_NANOCPUS"
assert_eq "restart policy"    "$CJSON" '.[0].HostConfig.RestartPolicy.Name' 'no'

summary_and_exit
