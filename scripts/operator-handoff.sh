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
# STEPS ARE ORDERED, AND THE ORDER IS ENFORCED FROM RECORDED STATE
#
# Each step records one of: not_started, running, passed, failed, interrupted,
# indeterminate. A later step accepts only `passed`, and only when the earlier
# step's recorded identities — source commit, image id, resolved-configuration
# digest — match the ones this step is using. A rebuild invalidates every
# downstream acceptance before it starts, so a failed rebuild cannot leave an
# earlier success usable. `--authorise-authenticated-read` is the operator's
# intent and is never accepted as evidence that a prerequisite passed.
#
# THE WORK DIRECTORY
#
#   <work>/state.env    the identities and step states. Mode 600, ours, no
#                       symlink, one hard link.
#   <work>/raw/         UNSANITIZED command output. DO NOT SHARE.
#   <work>/evidence/    the same output through the gate sanitizer. Shareable,
#                       subject to that filter being deny-by-pattern.
#
# Exit status: 0 only when every check of the step actually ran and passed AND
# every required cleanup completed. That is also the only case in which the
# step is recorded as `passed` and the identities it produced are written.

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

# state_apply — ONE atomic replacement carrying an ARBITRARY NUMBER of changes.
#
# Every write to the state file goes through here, and every write installs a
# COMPLETE new version of the file with a single rename(2). Whatever moment a
# reader looks — this program's next step, or an operator's `grep` — it sees
# either the whole set of changes or none of it.
#
# WHY IT HAS TO BE ONE RENAME
#
# record_step_outcome used to write the terminal status first and the identity
# bindings afterwards, each through its own rewrite-and-rename. Between those
# renames the state file said
#
#     STEP_STATUS_PROBE=passed
#
# and said nothing whatever about the image or the configuration that step had
# passed against. A step interrupted in that window left exactly that record
# behind: a pass carrying no bindings, which every later step then read as an
# acceptance it could build on — and assert_prereq_identities, which was
# supposed to catch it, skipped every component the record did not happen to
# contain. The status and the bindings are ONE fact, so they are one write.
#
# Each argument is either "+KEY=VALUE" (record, replacing any existing record
# of KEY) or "-KEY" (remove every record of KEY). Keys are matched as literal
# prefixes at position 1, never as patterns, so no metacharacter in a key can
# widen the match.
#
# STATED LIMIT: rename(2) is atomic against concurrent readers and against
# this process dying at any point. It is not a durability barrier — a host
# that loses power between the rename and the filesystem's own flush can come
# back holding the older version. That is tolerable here, because the older
# version never claims more than the newer one does, and it is not claimed to
# be more than that.
state_apply() { # +KEY=VALUE | -KEY ...
  local tmp keyfile arg key rest old
  [ -n "$STATE" ] || refuse "no state file is open"
  [ "$#" -gt 0 ] || return 0

  tmp="$(mktemp -- "${STATE}.XXXXXX")" ||
    refuse "a temporary file for the state update could not be created next to $STATE"
  chmod 600 -- "$tmp" 2>/dev/null || true
  keyfile="$(mktemp -- "${STATE}.keys.XXXXXX")" || {
    rm -f -- "$tmp"
    refuse "a temporary file for the state update could not be created next to $STATE"
  }

  # Validate the whole change set BEFORE touching anything. A malformed change
  # must not be able to produce a half-applied write.
  for arg in "$@"; do
    case "$arg" in
      +*) rest="${arg#+}"; key="${rest%%=*}" ;;
      -*) key="${arg#-}" ;;
      *)  rm -f -- "$tmp" "$keyfile"
          refuse "a state change was requested in a form this program does not write: $arg" ;;
    esac
    if [ -z "$key" ] || [ "$key" != "${key//[!A-Za-z0-9_]/}" ]; then
      rm -f -- "$tmp" "$keyfile"
      refuse "a state change was requested for an unusable key: '$key'"
    fi
    if ! printf '%s\n' "$key" >> "$keyfile"; then
      rm -f -- "$tmp" "$keyfile"
      refuse "the state update could not be prepared: $STATE"
    fi
  done

  # Every key being written or removed is dropped from the carried-over content
  # in ONE pass, so the new version is derived from the old one exactly once.
  if [ -f "$STATE" ]; then
    if ! awk -v kf="$keyfile" '
        BEGIN { while ((getline k < kf) > 0) if (k != "") keys[k] = 1 }
        { for (k in keys) if (index($0, k "=") == 1) next
          print }' "$STATE" > "$tmp"; then
      rm -f -- "$tmp" "$keyfile"
      refuse "the state file could not be rewritten: $STATE"
    fi
  fi
  rm -f -- "$keyfile"

  for arg in "$@"; do
    case "$arg" in
      +*) rest="${arg#+}"
          old="$(state_get "${rest%%=*}")" || old=""
          if [ -n "$old" ] && [ "$old" != "${rest#*=}" ]; then
            note "${rest%%=*} was already recorded with a different value; it is REPLACED, and every later step will use the new one"
          fi
          if ! printf '%s=%s\n' "${rest%%=*}" "${rest#*=}" >> "$tmp"; then
            rm -f -- "$tmp"
            refuse "the state file could not be written: $STATE"
          fi ;;
    esac
  done

  # The one moment at which the recorded state changes.
  if ! mv -f -- "$tmp" "$STATE"; then
    rm -f -- "$tmp"
    refuse "the updated state file could not be installed: $STATE"
  fi
  return 0
}

# state_put REPLACES any existing record of the key rather than appending one.
#
# It appended, and state_get returned the FIRST match. A step may legitimately
# be re-run into the same work directory — a second `build` after a failed or
# corrected first attempt is the case that matters — and the second run appended
# a new IMAGE_ID while every later step kept reading the first. Steps B, C and D
# would then have created their containers from the PREVIOUS build's image while
# step A's report named the new one, and each would still have passed its own
# `.Image` comparison, because it compared against the same stale value it was
# created from.
#
# That is FINDING-44 arriving by a different route: a result bound to one
# identity while the operation was performed on another. The image id is pinned
# so that cannot happen, so the pin itself must not be able to go stale.
#
# It is now the one-change spelling of state_apply. Routing it through the same
# primitive is what stops a future site from inventing a second, non-atomic way
# to write this file.
state_put() { # key value
  state_apply "+$1=$2"
}

# state_get reads the LAST record of the key. state_put keeps at most one, so
# this differs only for a state file written by an older revision of this
# program — where the last record is the current one, and the first is the stale
# one the defect above returned.
state_get() { # key -> prints value, returns 1 if absent or empty
  local value
  [ -n "$STATE" ] && [ -f "$STATE" ] || return 1
  value="$(awk -v key="$1" '
    index($0, key "=") == 1 { v = substr($0, length(key) + 2) }
    END { print v }' "$STATE" 2>/dev/null)" || return 1
  [ -n "$value" ] || return 1
  printf '%s' "$value"
}

state_require() { # key -> prints value or refuses
  local v
  v="$(state_get "$1")" ||
    refuse "$1 is not recorded in $STATE — run the earlier step first"
  [ -n "$v" ] || refuse "$1 is recorded empty in $STATE"
  printf '%s' "$v"
}

# A "-KEY" change to state_apply REMOVES the key entirely, so that a later
# state_get answers "absent" rather than "recorded empty". The distinction
# matters: an identity that was INVALIDATED must not read as an identity that
# exists and happens to be blank. Every site that voids a record — a rebuild's
# invalidation, a step that did not pass, the start of a step that is about to
# re-establish its own bindings — expresses it that way, inside the same
# replacement that carries the rest of that site's changes.

# state_append_word adds one whitespace-free word to a space-separated list,
# once. The invocation register is the only such list, and it must ACCUMULATE
# across steps rather than be replaced by each of them: step Z has to be able
# to look for the leftovers of every step that ran, including the ones that
# crashed.
state_append_word() { # key word
  local key="$1" word="$2" cur
  cur="$(state_get "$key")" || cur=""
  case " $cur " in
    *" $word "*) return 0 ;;
  esac
  state_put "$key" "${cur}${cur:+ }${word}"
}

# --- Step state machine -------------------------------------------------------
#
# WHY THIS EXISTS
#
# A step is one invocation of this program, and the operator runs six of them.
# Nothing recorded what a step DID. The only trace a step left behind was the
# output on the operator's terminal and whatever identities it happened to
# write on its way past, and those were written unconditionally — so:
#
#   * a step that FAILED and a step that was NEVER RUN were indistinguishable
#     to every later step;
#   * step A recorded IMAGE_ID and then went on to FAIL its own runtime
#     verification, and steps B, C and D read that image id as though it had
#     been verified;
#   * step D's refusal said it runs "only after steps A, B and C have passed
#     and been read", and checked nothing of the sort. It checked a flag.
#
# Five states, written to the state file and read by every later step:
#
#   not_started    no record exists
#   running        the step began and has not recorded a verdict
#   passed         every required check ran AND passed AND cleanup completed
#   failed         a required check failed, could not run, or cleanup failed
#   interrupted    a signal arrived while the step was running
#   indeterminate  the step ended without recording a verdict — a refusal after
#                  it began, or the process died. NOT a synonym for failed:
#                  what the step established is unknown, and it is refused as a
#                  prerequisite in those words rather than in failure's.
#
# `passed` is the only state a later step accepts, and it is written in exactly
# ONE place — record_step_outcome, reached from summary_and_exit AFTER
# run_cleanup has returned and its problems have been counted.
STEP_NAME=""
STEP_STARTED=0
STAGED_RESULTS=()

# Key names are derived, never typed at each site, so a later step cannot read
# a key an earlier step wrote under a slightly different name.
step_key() { # <prefix> <step>
  local up
  up="$(printf '%s' "$2" | tr '[:lower:]-' '[:upper:]_')"
  printf '%s_%s' "$1" "$up"
}

step_status_of() { # <step> -> prints the recorded status, or not_started
  local v
  v="$(state_get "$(step_key STEP_STATUS "$1")")" || v="not_started"
  [ -n "$v" ] || v="not_started"
  printf '%s' "$v"
}

# The identities THIS step is being performed against. Each is set as it
# becomes known, all are recorded if the step passes, and every step that
# depends on this one compares against them.
BIND_COMMIT=""
BIND_IMAGE=""
BIND_CONFIG=""

# begin_step — the transition into `running`, taken before anything the step
# does can matter. It needs an open state file, so it follows the work
# directory being opened and validated.
begin_step() { # <step>
  local prior kind
  local -a changes=()
  STEP_NAME="$1"
  prior="$(step_status_of "$STEP_NAME")"
  # `running` and the REMOVAL of this step's previous bindings, in one
  # replacement. A step that has begun has not yet passed against anything, so
  # the identities a previous run of the same step recorded must not outlive
  # the moment this one starts: leaving them there is a binding sitting beside
  # a status that does not entitle anything to read it, which is the shape of
  # the defect this whole section exists to remove.
  changes=("+$(step_key STEP_STATUS "$STEP_NAME")=running")
  for kind in commit image config; do
    changes+=("-$(step_key "$(binding_key_prefix "$kind")" "$STEP_NAME")")
  done
  state_apply "${changes[@]}"
  STEP_STARTED=1
  case "$prior" in
    not_started) ;;
    passed) note "step $STEP_NAME was already recorded as passed; that record is SUPERSEDED by this run" ;;
    *)      note "step $STEP_NAME was previously recorded as $prior; that record is SUPERSEDED by this run" ;;
  esac
}

# stage_result — an identity this step PRODUCED. Held until the step's verdict
# is known, and written only if that verdict is `passed`.
#
# Step A used to write IMAGE_ID, BUILD_COMMIT and BUILD_DATE unconditionally,
# immediately before computing a verdict that could be FAILED. A build whose
# runtime verification failed still published the image id that steps B, C and
# D then created their containers from.
stage_result() { # key value
  STAGED_RESULTS+=("$1=$2")
}

# Staged results are published by record_step_outcome, inside the SAME atomic
# replacement that publishes the terminal status and the identity bindings.
#
# There is deliberately no function that writes them on their own any more. A
# staged result installed by a rename of its own is a moment at which the file
# holds some of a step's results and not the rest, and that moment is the whole
# of the defect this section exists to remove.

discard_staged_results() {
  local n kv
  n="${#STAGED_RESULTS[@]}"
  if [ "$n" -gt 0 ]; then
    note "this step did not pass, so the $n identity/identities it produced are NOT recorded:"
    for kv in ${STAGED_RESULTS[@]+"${STAGED_RESULTS[@]}"}; do
      note "  ${kv%%=*} — NOT RECORDED"
    done
    note "no later step can read them, which is the point: a later step must not run"
    note "against an identity produced by a step that did not pass."
  fi
  STAGED_RESULTS=()
}

# record_step_outcome — the ONLY writer of a terminal step state.
#
# Reached from summary_and_exit after run_cleanup, from the signal handler
# after run_cleanup, and from the EXIT trap for a step that ended without a
# verdict. It clears STEP_STARTED first, so whichever arrives first wins and a
# later handler cannot overwrite a recorded verdict.
# --- What each step is REQUIRED to be bound to --------------------------------
#
# The bindings are not "whichever identities the step happened to establish".
# Each step has a stated, required set, and both halves of the state machine
# are checked against it:
#
#   * record_step_outcome will not publish `passed` unless every required
#     binding for that step is established and well-formed; and
#   * require_step_passed and assert_prereq_identities will not ACCEPT a
#     `passed` record unless every required binding for that step is present,
#     well-formed and equal to the identity this step is using.
#
# The old rule compared only the components both sides happened to have, and
# reported "step build passed against exactly these identities (source commit)"
# when the image binding was absent entirely. A commit that matched was enough
# to carry an acceptance forward to a container built from an image nothing had
# compared. Absence is now refused, not skipped.
#
#   preflight  the checkout it validated
#   build      the checkout it built, and the image it produced
#   probe      the checkout, the image it ran, and the resolved deployment
#   secret     as probe
#   status     as probe
#   closeout   none — it creates nothing and no step depends on it
step_required_bindings() { # <step> -> prints the required kinds, space separated
  case "$1" in
    preflight)           printf 'commit' ;;
    build)               printf 'commit image' ;;
    probe|secret|status) printf 'commit image config' ;;
    closeout)            printf '' ;;
    *) return 1 ;;
  esac
}

binding_key_prefix() { # <kind>
  case "$1" in
    commit) printf 'STEP_COMMIT' ;;
    image)  printf 'STEP_IMAGE' ;;
    config) printf 'STEP_CONFIG' ;;
    *) return 1 ;;
  esac
}

binding_name() { # <kind> — how the operator is told about it
  case "$1" in
    commit) printf 'source commit' ;;
    image)  printf 'image id' ;;
    config) printf 'configuration digest' ;;
    *) return 1 ;;
  esac
}

binding_current() { # <kind> -> the value THIS step has established, if any
  case "$1" in
    commit) printf '%s' "$BIND_COMMIT" ;;
    image)  printf '%s' "$BIND_IMAGE" ;;
    config) printf '%s' "$BIND_CONFIG" ;;
    *) return 1 ;;
  esac
}

# binding_wellformed — an identity that is present but not of the right SHAPE
# is not an identity. A truncated image id or a 7-character commit compares
# unequal against the real thing and would be reported as staleness; worse, a
# value that is merely non-empty would satisfy a presence check while
# establishing nothing. Shape is checked wherever presence is.
binding_wellformed() { # <kind> <value>
  local hex
  case "$1" in
    commit)
      case "$2" in *[!0-9a-f]* | '') return 1 ;; esac
      [ "${#2}" -eq 40 ] ;;
    config)
      case "$2" in *[!0-9a-f]* | '') return 1 ;; esac
      [ "${#2}" -eq 64 ] ;;
    image)
      case "$2" in sha256:*) ;; *) return 1 ;; esac
      hex="${2#sha256:}"
      case "$hex" in *[!0-9a-f]* | '') return 1 ;; esac
      [ "${#hex}" -eq 64 ] ;;
    *) return 1 ;;
  esac
}

# assert_recorded_bindings_complete — a `passed` record is usable only WITH the
# identities that step was required to pass against.
#
# This is the historical-record case as much as the interruption case. A state
# file written by an earlier revision of this program, or one interrupted
# between the status write and the binding writes, can hold
# STEP_STATUS_BUILD=passed and nothing else. That record is refused here rather
# than being carried into a comparison that silently skips what is missing.
#
# state_get returns nonzero for absent, empty AND unreadable alike, and all
# three are refused in the same words: what that step passed against cannot be
# read, so it is UNPROVEN either way.
assert_recorded_bindings_complete() { # <step>
  local step="$1" kinds kind key val
  kinds="$(step_required_bindings "$step")" || kinds=""
  for kind in $kinds; do
    key="$(step_key "$(binding_key_prefix "$kind")" "$step")"
    if ! val="$(state_get "$key")"; then
      refuse "step $step is recorded as passed, but the $(binding_name "$kind") it passed against ($key) is missing, empty or unreadable in $STATE. That is an INCOMPLETE pass record — what step $step established cannot be attributed to anything — and it is refused rather than skipped. Re-run step $step"
    fi
    if ! binding_wellformed "$kind" "$val"; then
      refuse "step $step is recorded as passed, but its recorded $(binding_name "$kind") ($key) is malformed. That is a CORRUPT pass record and it is refused. Re-run step $step"
    fi
  done
  return 0
}

# assert_bindings_publishable — called by summary_and_exit BEFORE it computes
# the verdict, so that a step which cannot say what it passed against fails in
# the ordinary way: counted, printed, and exited nonzero.
#
# Checking it only inside record_step_outcome would record `failed` while the
# program still exited 0 and told the operator every check had passed. The
# recorded state and the reported result have to be the same statement.
assert_bindings_publishable() {
  local kinds kind val
  kinds="$(step_required_bindings "$STEP_NAME")" || kinds=""
  for kind in $kinds; do
    val="$(binding_current "$kind")"
    if [ -z "$val" ]; then
      bad "this step established no $(binding_name "$kind"), which it is required to be bound to — a pass that cannot say what it passed against is not publishable"
    elif ! binding_wellformed "$kind" "$val"; then
      bad "this step's $(binding_name "$kind") is malformed — a pass cannot be bound to it"
    fi
  done
  return 0
}

# record_step_outcome — the ONLY writer of a terminal step state, and it writes
# the whole terminal record in ONE atomic replacement.
#
# Reached from summary_and_exit after run_cleanup, from the signal handler
# after run_cleanup, and from the EXIT trap for a step that ended without a
# verdict. It clears STEP_STARTED first, so whichever arrives first wins and a
# later handler cannot overwrite a recorded verdict.
#
# Two things happen here that did not before:
#
#   1. A `passed` outcome is CHECKED against the step's required bindings
#      before it is published. A step whose checks all passed but which cannot
#      say what it passed against is recorded as `failed`, not as `passed`.
#   2. The status, the bindings and the staged results are installed by a
#      single state_apply. There is no window in which the file says `passed`
#      and does not yet say what against.
record_step_outcome() { # <passed|failed|interrupted|indeterminate>
  local outcome="$1" kinds kind key val missing="" kv
  local -a changes=()
  [ "$STEP_STARTED" -eq 1 ] || return 0
  STEP_STARTED=0
  [ -n "$STATE" ] && [ -f "$STATE" ] || return 0
  kinds="$(step_required_bindings "$STEP_NAME")" || kinds=""

  if [ "$outcome" = "passed" ]; then
    for kind in $kinds; do
      val="$(binding_current "$kind")"
      if [ -z "$val" ]; then
        missing="${missing}${missing:+, }$(binding_name "$kind") (never established)"
      elif ! binding_wellformed "$kind" "$val"; then
        missing="${missing}${missing:+, }$(binding_name "$kind") (malformed)"
      fi
    done
    if [ -n "$missing" ]; then
      # summary_and_exit checks this BEFORE it computes the verdict, so the
      # exit status and the printed result agree with what gets recorded. This
      # is the last line of defence for any path that does not go through it.
      printf 'RESULT: this step cannot be recorded as passed: %s\n' "$missing"
      printf 'STEP STATUS: recorded as failed instead — a pass is publishable only\n'
      printf 'together with every identity it was performed against.\n'
      outcome="failed"
    fi
  fi

  changes=("+$(step_key STEP_STATUS "$STEP_NAME")=$outcome")
  if [ "$outcome" = "passed" ]; then
    # The identities the step was performed against, recorded WITH the pass, so
    # a later step can tell "step B passed" from "step B passed against the
    # image and the configuration I am about to use". A component this step
    # never established is REMOVED rather than left at whatever an earlier run
    # of the same step recorded under the same key.
    for kind in commit image config; do
      key="$(step_key "$(binding_key_prefix "$kind")" "$STEP_NAME")"
      val="$(binding_current "$kind")"
      if [ -n "$val" ]; then changes+=("+$key=$val"); else changes+=("-$key"); fi
    done
    for kv in ${STAGED_RESULTS[@]+"${STAGED_RESULTS[@]}"}; do
      changes+=("+$kv")
    done
    STAGED_RESULTS=()
  else
    # A non-passing step leaves behind no binding that could be mistaken for one.
    for kind in commit image config; do
      changes+=("-$(step_key "$(binding_key_prefix "$kind")" "$STEP_NAME")")
    done
    discard_staged_results
  fi
  state_apply "${changes[@]}"
  return 0
}

# require_step_passed — a PREREQUISITE, checked against what the earlier step
# recorded. Each non-passing state is refused in its own words, because
# "interrupted" and "failed" call for different operator actions.
require_step_passed() { # <step> <why this step needs it>
  local step="$1" why="$2" status
  status="$(step_status_of "$step")"
  case "$status" in
    passed) ;;
    not_started)
      refuse "step $step has not been run in this work directory, and $why. Run it first — an authorisation flag is not evidence that a prerequisite passed" ;;
    running)
      refuse "step $step is recorded as RUNNING: it began and never recorded a verdict, so it did not pass. Re-run it" ;;
    indeterminate)
      refuse "step $step is recorded as INDETERMINATE: it began and ended without recording a verdict, so what it established is unknown. Re-run it" ;;
    interrupted)
      refuse "step $step was INTERRUPTED and did not complete, so it did not pass. Re-run it" ;;
    failed)
      refuse "step $step is recorded as FAILED, and $why. Correct the failure and re-run it" ;;
    *)
      refuse "step $step has an unrecognised recorded status '$status'; it is not 'passed', so it is refused" ;;
  esac
  # `passed` is a claim; the bindings are what the claim is ABOUT. A record
  # carrying the first and not the second is refused here, before this step
  # does anything — including before it requires Docker, creates a container,
  # or offers a credential to one.
  assert_recorded_bindings_complete "$step"
  ok "prerequisite: step $step is recorded as passed in this work directory, with every identity it was required to pass against"
}

# assert_prereq_identities — the earlier step passed, but against WHAT?
#
# Called once the identities this step will use are known. Every component the
# earlier step recorded and this step also has must agree; a component only one
# of them has is not compared, and the report names the ones that were.
assert_prereq_identities() { # <step>
  local step="$1" compared="" kinds kind key rec cur required
  kinds="$(step_required_bindings "$step")" || kinds=""
  for kind in commit image config; do
    key="$(step_key "$(binding_key_prefix "$kind")" "$step")"
    rec="$(state_get "$key")" || rec=""
    cur="$(binding_current "$kind")"
    required=0
    case " $kinds " in *" $kind "*) required=1 ;; esac

    if [ "$required" -eq 1 ]; then
      # A component the earlier step was REQUIRED to bind is compared, or this
      # step refuses. It is not skipped because one side is absent: skipping
      # is what let a matching commit alone carry an acceptance forward to an
      # image and a deployment configuration that nothing had compared.
      if [ -z "$rec" ]; then
        bad "step $step recorded no $(binding_name "$kind"), which it is required to have passed against — its acceptance is UNUSABLE, not merely unverified"
        return 1
      fi
      if ! binding_wellformed "$kind" "$rec"; then
        bad "step $step recorded a malformed $(binding_name "$kind") — its acceptance is UNUSABLE"
        return 1
      fi
      if [ -z "$cur" ]; then
        bad "this step has established no $(binding_name "$kind") to compare against step $step's — refusing to carry that acceptance forward UNCHECKED"
        return 1
      fi
      if ! binding_wellformed "$kind" "$cur"; then
        bad "this step's $(binding_name "$kind") is malformed, so the comparison against step $step cannot be made — its acceptance is UNPROVEN here"
        return 1
      fi
    else
      # Not required of that step. Compared anyway when both sides have it,
      # which costs nothing and catches a drift the table does not model.
      { [ -n "$rec" ] && [ -n "$cur" ]; } || continue
    fi

    if [ "$rec" != "$cur" ]; then
      case "$kind" in
        config) bad "step $step passed against a different resolved deployment configuration (was $rec, now $cur) — its acceptance is STALE" ;;
        *)      bad "step $step passed against $(binding_name "$kind") $rec, but this step is using $cur — its acceptance is STALE" ;;
      esac
      return 1
    fi
    compared="${compared}${compared:+, }$(binding_name "$kind")"
  done

  if [ -z "$compared" ]; then
    blocked "step $step recorded no identity this step can compare against — what it passed against is UNPROVEN"
    return 1
  fi
  ok "step $step passed against exactly these identities ($compared)"
  return 0
}

# invalidate_after_rebuild — a rebuild voids every downstream acceptance, and
# it does so BEFORE the build runs.
#
# Doing it first is what makes a FAILED rebuild safe. If it ran only on
# success, a build that failed halfway would leave the PREVIOUS build's
# IMAGE_ID in the state file with the previous B/C/D passes standing beside it,
# and the operator's next step would create containers from an image no step in
# this work directory ever verified — while every step reported a pass.
DOWNSTREAM_OF_BUILD="probe secret status"
invalidate_after_rebuild() { # <reason>
  local s status kind touched=0
  local -a changes=()
  for s in $DOWNSTREAM_OF_BUILD; do
    status="$(step_status_of "$s")"
    [ "$status" = "not_started" ] && continue
    changes+=("+$(step_key STEP_STATUS "$s")=not_started")
    for kind in commit image config; do
      changes+=("-$(step_key "$(binding_key_prefix "$kind")" "$s")")
    done
    note "step $s was recorded as $status; that acceptance is INVALIDATED by $1, and step $s must be re-run"
    touched=1
  done
  if state_get IMAGE_ID >/dev/null 2>&1; then
    changes+=("-IMAGE_ID" "-BUILD_COMMIT" "-BUILD_DATE")
    note "the previously recorded IMAGE_ID is INVALIDATED by $1"
    note "if this build does not pass, no image id is recorded and steps B, C and D refuse"
    touched=1
  fi
  # ONE replacement, like every other write to this file. A rebuild interrupted
  # partway through the invalidation must not be able to leave some downstream
  # acceptances voided and others standing beside a stale image pin — which is
  # precisely the arrangement that would let the next step create a container
  # from an image no step in this work directory ever verified.
  if [ "$touched" -eq 1 ]; then
    state_apply "${changes[@]}"
    ok "downstream acceptance invalidated before the rebuild starts"
  fi
  return 0
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
  BIND_COMMIT="$expected"

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
# THIS RUNS UNDER sudo. Every path below is opened by uid 0, and the directory
# it opens is named on the command line by the operator, so the program has to
# establish that the thing it found is the thing it was meant to find.
#
# What it did before: `mkdir -p -- "$requested"`, then `chmod 700` on it, then
# `stat` the mode. Each of those is a defect when the path is not already
# trusted:
#
#   * `mkdir -p` on an existing SYMLINK succeeds silently, and the `chmod 700`
#     that follows then applies to the link's TARGET. A symlink at the named
#     path pointed root's chmod at any directory on the host.
#   * OWNERSHIP was never checked. A directory belonging to another account,
#     mode 700, passed the mode check unchanged — root can enter it — and the
#     run then wrote its evidence into a directory that account can read, and
#     read its state back out of a file that account can write.
#   * The state file was reached with `[ -f "$STATE" ]`, which FOLLOWS
#     symlinks. A `state.env` symlinked at any root-readable file made this
#     program parse that file, and the values it took out of it became
#     EXPECTED_COMMIT, REPO_ROOT and IMAGE_ID — the identities every other
#     check is performed against.
#   * The ANCESTORS were never considered. A work directory inside a directory
#     another account can write is a directory that account can replace between
#     two of this program's own syscalls.
#
# So: no symlink anywhere on the path, owned by the account running the step,
# mode 700, a state file that is a regular non-linked file of mode 600, and an
# ancestor chain no other account can write.
#
# STATED LIMIT: these are checks, not locks. Between a check and the use that
# follows it, a sufficiently privileged account could still substitute a
# component. The ancestor rule is what closes the practical version of that —
# an unprivileged attacker needs a writable ancestor to perform the swap — and
# it is not claimed to be more than that.

# assert_not_symlink <path> <what it is>
assert_not_symlink() {
  if [ -L "$1" ]; then
    refuse "$2 is a symbolic link: $1 — refusing to operate through it as $(id -un)"
  fi
  return 0
}

# mode_is_writable_by_others <mode-digits> — group- or other-writable, and the
# sticky bit is not set. /tmp is 1777 and is fine: sticky means another account
# cannot rename or remove our directory even though it can create its own.
mode_is_writable_by_others() { # <stat -c %a output>
  local m="$1" perm sticky=0 g o
  perm="${m: -3}"
  if [ "${#m}" -ge 4 ]; then
    case "${m:$((${#m} - 4)):1}" in 1|3|5|7) sticky=1 ;; esac
  fi
  g="${perm:1:1}"; o="${perm:2:1}"
  [ "$sticky" -eq 1 ] && return 1
  [ $(( g & 2 )) -ne 0 ] && return 0
  [ $(( o & 2 )) -ne 0 ] && return 0
  return 1
}

# assert_ancestors_trusted <dir> — every directory from <dir>'s parent to / is
# owned by root or by us, and is not writable by anyone else without the sticky
# bit.
assert_ancestors_trusted() {
  local dir="$1" me parent owner mode
  me="$(id -u)"
  parent="$dir"
  while [ "$parent" != "/" ]; do
    parent="$(dirname -- "$parent")"
    owner="$(stat -c '%u' -- "$parent" 2>/dev/null)" ||
      refuse "an ancestor of the work directory could not be examined: $parent"
    mode="$(stat -c '%a' -- "$parent" 2>/dev/null)" ||
      refuse "an ancestor of the work directory could not be examined: $parent"
    if [ "$owner" != "0" ] && [ "$owner" != "$me" ]; then
      refuse "the work directory's ancestor $parent is owned by uid $owner, which is neither root nor the uid running this step ($me) — it could be substituted underneath this run"
    fi
    if mode_is_writable_by_others "$mode"; then
      refuse "the work directory's ancestor $parent is mode $mode: writable by another account without the sticky bit, so the work directory could be replaced underneath this run"
    fi
  done
  return 0
}

# assert_work_dir_trusted <resolved dir>
assert_work_dir_trusted() {
  local dir="$1" me owner mode
  me="$(id -u)"
  assert_not_symlink "$dir" "the work directory"
  [ -d "$dir" ] || refuse "the work directory is not a directory: $dir"
  owner="$(stat -c '%u' -- "$dir" 2>/dev/null)" ||
    refuse "the work directory's owner could not be read: $dir"
  [ "$owner" = "$me" ] ||
    refuse "the work directory is owned by uid $owner, not by uid $me which is running this step: $dir — refusing to read state from, or write evidence into, a directory this run does not own"
  mode="$(stat -c '%a' -- "$dir" 2>/dev/null)" ||
    refuse "the work directory's mode could not be read: $dir"
  [ "${mode: -3}" = "700" ] ||
    refuse "the work directory is mode $mode, not 700: $dir — refusing to write evidence into it"
  assert_ancestors_trusted "$dir"
  return 0
}

# assert_state_file_trusted — the state file carries the identities every other
# check is made against, so it is validated as strictly as the directory.
assert_state_file_trusted() {
  local me owner mode links
  me="$(id -u)"
  assert_not_symlink "$STATE" "the state file"
  [ -f "$STATE" ] || refuse "no state file in $WORK — run the preflight step first"
  owner="$(stat -c '%u' -- "$STATE" 2>/dev/null)" ||
    refuse "the state file's owner could not be read: $STATE"
  [ "$owner" = "$me" ] ||
    refuse "the state file is owned by uid $owner, not by uid $me which is running this step: $STATE — its contents are not this run's identities"
  mode="$(stat -c '%a' -- "$STATE" 2>/dev/null)" ||
    refuse "the state file's mode could not be read: $STATE"
  [ "${mode: -3}" = "600" ] ||
    refuse "the state file is mode $mode, not 600: $STATE"
  links="$(stat -c '%h' -- "$STATE" 2>/dev/null)" || links=""
  [ "$links" = "1" ] ||
    refuse "the state file has $links hard links, not 1: $STATE — another name for it exists, so its content is not solely this run's"
  return 0
}

# --- Raw captures and sanitized evidence, kept apart --------------------------
#
# They were the same files. `capture_run` wrote a command's UNMODIFIED output
# into the work directory, `print_diagnostic` sanitized only what it printed to
# the terminal, and the closing summary then told the operator:
#
#     "Evidence and sanitized logs remain in: <work dir>"
#
# The logs in that directory were not sanitized. An operator following that
# sentence would return a build log, a doctor log and a runtime-verifier log
# exactly as the commands emitted them.
#
# Two directories now, and they mean different things:
#
#   raw/       what the command actually wrote. Unsanitized, mode 700/600, for
#              diagnosis on this host. NOT shareable.
#   evidence/  the same output through scripts/gate-diagnostics.sh --sanitize.
#              This is what leaves the host.
#
# STATED LIMIT, unchanged by this: the sanitizer is deny-by-pattern. It
# establishes what its patterns catch, and a credential of an unanticipated
# shape would pass through it. Separating the two directories does not make the
# filter complete; it stops the UNFILTERED file from being labelled as the
# filtered one.
RAW=""
EVID=""

# make_work_subdir <path> <what> — created 700 by mkdir itself, so there is no
# window in which it exists with a wider mode, then validated like any other
# directory this program writes into.
make_work_subdir() {
  local dir="$1" what="$2" me owner mode
  me="$(id -u)"
  assert_not_symlink "$dir" "$what"
  if [ ! -d "$dir" ]; then
    mkdir -m 700 -- "$dir" || refuse "$what could not be created: $dir"
  fi
  assert_not_symlink "$dir" "$what"
  chmod 700 -- "$dir" || refuse "$what's mode could not be set: $dir"
  owner="$(stat -c '%u' -- "$dir" 2>/dev/null)" ||
    refuse "$what's owner could not be read: $dir"
  [ "$owner" = "$me" ] ||
    refuse "$what is owned by uid $owner, not by uid $me: $dir"
  mode="$(stat -c '%a' -- "$dir" 2>/dev/null)" ||
    refuse "$what's mode could not be read back: $dir"
  [ "${mode: -3}" = "700" ] || refuse "$what is mode $mode, not 700: $dir"
  return 0
}

init_evidence_dirs() {
  RAW="$WORK/raw"
  EVID="$WORK/evidence"
  make_work_subdir "$RAW"  "the raw-capture directory"
  make_work_subdir "$EVID" "the sanitized-evidence directory"
  # The marker is written every time, because the directory it labels may have
  # been created by an earlier step and the label is what an operator reads.
  if ! printf '%s\n' \
      'UNSANITIZED command output. It may contain credential material.' \
      'DO NOT SHARE THE FILES IN THIS DIRECTORY.' \
      'The sanitized copies are in ../evidence/.' > "$RAW/README-DO-NOT-SHARE.txt"; then
    refuse "the raw-capture directory could not be labelled: $RAW"
  fi
  chmod 600 -- "$RAW/README-DO-NOT-SHARE.txt" 2>/dev/null || true
  if ! printf '%s\n' \
      'Each file here is a raw capture from ../raw/ passed through' \
      'scripts/gate-diagnostics.sh --sanitize. These are the files to return.' \
      'The filter is deny-by-pattern: it establishes what its patterns catch,' \
      'and a credential of an unanticipated shape would pass through it.' > "$EVID/README.txt"; then
    refuse "the sanitized-evidence directory could not be labelled: $EVID"
  fi
  chmod 600 -- "$EVID/README.txt" 2>/dev/null || true
  return 0
}

# --- One invocation at a time, per work directory ------------------------------
#
# Two invocations sharing a work directory raced. Every read of the state file
# and every write to it was unsynchronised, so:
#
#   * step B could read STEP_STATUS_BUILD=passed and its bindings while a
#     concurrent `build` was midway through invalidating exactly those records;
#   * two steps could each read-modify-write the invocation register and one of
#     the two registrations would be lost — leaving containers behind that step
#     Z would never know to look for;
#   * `preflight` removes and recreates the state file, which another step
#     could be reading through at that moment.
#
# rename(2) makes each individual write atomic. It does not make a
# read-decide-write SEQUENCE atomic, and a prerequisite check is exactly that:
# read the earlier step's record, decide it is usable, act on it. The lock is
# what makes the decision and the action refer to the same state.
#
# It is taken BEFORE the first read of the state file and held for the whole
# step, and it is released when the process exits — including when it is
# killed, because the kernel drops an flock with the descriptor that holds it.
#
# STATED LIMIT: the descriptor is inherited by the commands this program runs.
# Every one of them is short-lived and waited for, so none outlives the step
# and none can hold the lock past this program's exit; a future call site that
# spawned something detached would have to close it.
WORK_LOCK_HELD=0
LOCK_WAIT_SECONDS=0

acquire_work_lock() {
  local lock opened present otype
  [ -n "$WORK" ] || refuse "no work directory is open"
  command -v flock >/dev/null 2>&1 ||
    refuse "flock is not available, so two invocations sharing this work directory could not be excluded — refusing rather than racing the state file"
  lock="$WORK/.handoff.lock"

  # The directory is already established as mode 700, owned by this uid, not a
  # symlink, and with no ancestor another account can write, so only this
  # account can place anything at this path. The checks below are the rest of
  # the answer: the path is not a symlink before it is opened, and the
  # descriptor that was actually opened is the same regular file that path
  # names. A component substituted between the check and the open is caught
  # here rather than followed — which is the lock-file symlink defect that a
  # naive `: > "$WORK/lock"` would have introduced.
  assert_not_symlink "$lock" "the work-directory lock file"
  if ! ( umask 077; : >> "$lock" ); then
    refuse "the work-directory lock file could not be created: $lock"
  fi
  chmod 600 -- "$lock" 2>/dev/null || true
  assert_not_symlink "$lock" "the work-directory lock file"

  exec 9>>"$lock" ||
    refuse "the work-directory lock file could not be opened: $lock"
  opened="$(stat -Lc '%d:%i:%u:%a' -- /proc/self/fd/9 2>/dev/null)" ||
    refuse "the opened work-directory lock could not be examined — refusing to serialise against a descriptor whose identity is unknown"
  present="$(stat -c '%d:%i:%u:%a' -- "$lock" 2>/dev/null)" ||
    refuse "the work-directory lock file could not be examined: $lock"
  [ "$opened" = "$present" ] ||
    refuse "the work-directory lock file was substituted while it was being opened: $lock — refusing to serialise against something other than the file that path names"
  # The TYPE is read separately, and both of `stat %F`'s spellings for a
  # regular file are accepted, because it says "regular empty file" for a
  # zero-length one. It is deliberately not part of the identity comparison
  # above: a file's length can change between the two calls without the file
  # having been substituted, and that must not read as a substitution.
  otype="$(stat -Lc '%F' -- /proc/self/fd/9 2>/dev/null)" ||
    refuse "the type of the opened work-directory lock could not be read: $lock"
  case "$otype" in
    "regular file" | "regular empty file") ;;
    *) refuse "the work-directory lock is not a regular file (it is a $otype): $lock" ;;
  esac

  # Nonblocking. Two steps in one work directory at once is an operator error,
  # not a queue: reporting it is more useful than silently serialising two runs
  # the operator believes are independent.
  if ! flock -w "$LOCK_WAIT_SECONDS" 9; then
    refuse "another invocation of this program is running in $WORK and holds its lock. Two steps sharing one work directory would read and write the same state file with no ordering between them; wait for that step to finish, or give this one its own work directory"
  fi
  WORK_LOCK_HELD=1
  ok "this invocation holds the work directory's lock; no other invocation can read or write its state while this step runs"
}

# shellcheck disable=SC2329  # reached from the EXIT trap
# release_work_lock — the descriptor is closed on exit in any case and the
# kernel releases the lock with it. Doing it explicitly, AFTER the terminal
# state has been recorded, is what makes the ordering visible: the next
# invocation cannot begin reading until this one's verdict is on disk.
release_work_lock() {
  [ "$WORK_LOCK_HELD" -eq 1 ] || return 0
  WORK_LOCK_HELD=0
  flock -u 9 2>/dev/null || true
  exec 9>&- 2>/dev/null || true
  return 0
}

create_work_dir() {
  local requested="${1:-}"
  if [ -n "$requested" ]; then
    # The symlink check comes BEFORE mkdir, because mkdir -p on an existing
    # symlink succeeds and the chmod that used to follow it landed on the
    # link's target.
    assert_not_symlink "$requested" "the requested work directory"
    if [ -e "$requested" ]; then
      [ -d "$requested" ] ||
        refuse "the requested work directory exists and is not a directory: $requested"
    else
      # The parents, then the directory itself with its mode applied BY mkdir.
      # `mkdir -p -m 700` would apply the mode to the deepest component only
      # and leave the intermediates at the default — and a create-then-chmod on
      # the final component leaves a window in which it exists mode 755.
      local parent
      parent="$(dirname -- "$requested")"
      [ -d "$parent" ] || mkdir -p -- "$parent" ||
        refuse "the parent of the requested work directory could not be created: $parent"
      mkdir -m 700 -- "$requested" ||
        refuse "the requested work directory could not be created: $requested"
    fi
    assert_not_symlink "$requested" "the requested work directory"
    chmod 700 -- "$requested" || refuse "the work directory's mode could not be set: $requested"
    WORK="$(cd -- "$requested" >/dev/null 2>&1 && pwd -P)" ||
      refuse "the requested work directory could not be resolved: $requested"
  else
    WORK="$(mktemp -d)" || refuse "a private work directory could not be created"
    chmod 700 -- "$WORK" || refuse "the work directory's mode could not be set: $WORK"
  fi
  assert_work_dir_trusted "$WORK"
  acquire_work_lock
  ok "private work directory created: mode 700, owned by this run, no symlink, no ancestor another account can write"
  note "work directory: $WORK"
  init_evidence_dirs
  ok "raw captures and sanitized evidence have separate directories"
}

open_work_dir() { # <dir>
  [ -n "$1" ] || refuse "--work-dir is required for this step"
  assert_not_symlink "$1" "the work directory"
  WORK="$(cd -- "$1" >/dev/null 2>&1 && pwd -P)" ||
    refuse "the work directory does not exist or cannot be entered: $1"
  assert_work_dir_trusted "$WORK"
  # Before the state file is opened, let alone read. Every prerequisite this
  # step is about to check, and every record it is about to write, happens
  # under this lock.
  acquire_work_lock
  STATE="$WORK/state.env"
  assert_state_file_trusted
  init_evidence_dirs
}

# --- Log capture, kept distinct from the command's own status -----------------
#
# The command's status is read from the COMMAND, never through `tee` or a
# pipeline, and the capture's usability is a SEPARATE result. A build that
# succeeded and a log that was not written are two different facts; the
# superseded procedure conflated them by reading ${PIPESTATUS[0]} out of a tee
# pipeline and never checking that anything landed in the file.
#
# The capture goes to raw/ and is sanitized into evidence/ by this function
# rather than by its callers, so that no future capture site can forget to do
# it. `raw_log` and `evidence_log` name the two halves; every caller passes a
# BASENAME and never a path, which is what keeps a raw capture from being
# written into the shareable directory by mistake.
LAST_RC=0

raw_log()      { printf '%s/%s' "$RAW"  "$1"; }
evidence_log() { printf '%s/%s' "$EVID" "$1"; }

# publish_evidence <basename> — the raw capture through the gate sanitizer.
# A sanitizer that is absent or that fails produces NO evidence file: an
# unreadable evidence set costs a rerun, and a file wrongly labelled sanitized
# cannot be taken back.
publish_evidence() { # <basename>
  local src dst
  src="$(raw_log "$1")"
  dst="$(evidence_log "$1")"
  [ -f "$src" ] || return 0
  rm -f -- "$dst" 2>/dev/null || true
  if [ ! -f "$SANITIZER" ]; then
    note "no sanitized copy of $1 was made: $SANITIZER is absent"
    return 1
  fi
  assert_not_symlink "$dst" "the evidence file"
  if ! ( umask 077; : > "$dst" ); then
    note "no sanitized copy of $1 was made: $dst could not be created"
    return 1
  fi
  chmod 600 -- "$dst" 2>/dev/null || true
  if ! bash "$SANITIZER" --sanitize < "$src" > "$dst" 2>/dev/null; then
    rm -f -- "$dst"
    note "no sanitized copy of $1 was made: the sanitizer failed"
    return 1
  fi
  return 0
}

capture_run() { # <basename> <command...>
  local name="$1" log; shift
  log="$(raw_log "$name")"
  assert_not_symlink "$log" "the capture file"
  : > "$log" || { blocked "the capture file could not be created: $log"; LAST_RC=125; return 1; }
  chmod 600 -- "$log" 2>/dev/null || true
  "$@" > "$log" 2>&1
  LAST_RC=$?
  publish_evidence "$name" || true
  return 0
}

assert_capture_usable() { # <label> <basename>
  if [ ! -s "$(raw_log "$2")" ]; then
    blocked "$1: nothing was captured, so the output cannot be checked (this is separate from the command's exit status)"
    return 1
  fi
  ok "$1: output captured"
  return 0
}

# --- Verdict ------------------------------------------------------------------
#
# The order here is the whole of the second defect. run_cleanup runs FIRST, its
# problems are counted INTO the verdict, and only then is the outcome recorded.
# A step that passed every check and failed to remove a container it created is
# recorded as `failed`, because the next step must not build on it.
summary_and_exit() {
  local outcome rc
  run_cleanup
  # A pass must be publishable together with the identities this step was
  # required to be bound to. Checked HERE, before the verdict is computed, so
  # that a step which cannot say what it passed against is counted, printed
  # and exited nonzero like any other failure.
  if [ "$FAIL" -eq 0 ] && [ "$BLOCK" -eq 0 ] && [ "$CLEANUP_PROBLEMS" -eq 0 ]; then
    assert_bindings_publishable
  fi
  printf '\n%d passed, %d failed, %d blocked, %d cleanup problem(s)\n' \
    "$PASS" "$FAIL" "$BLOCK" "$CLEANUP_PROBLEMS"
  if [ "$FAIL" -gt 0 ] || [ "$BLOCK" -gt 0 ] || [ "$CLEANUP_PROBLEMS" -gt 0 ]; then
    outcome="failed"; rc=1
  else
    outcome="passed"; rc=0
  fi
  record_step_outcome "$outcome"
  report_work_dir
  if [ "$FAIL" -gt 0 ] || [ "$BLOCK" -gt 0 ]; then
    printf 'RESULT: step INCOMPLETE — required checks failed or could not run.\n'
    printf 'STEP STATUS: %s is recorded as %s; no later step will accept it as a prerequisite.\n' \
      "${STEP_NAME:-this step}" "$outcome"
    exit "$rc"
  fi
  if [ "$CLEANUP_PROBLEMS" -gt 0 ]; then
    printf 'RESULT: checks passed but REQUIRED CLEANUP FAILED — resources listed above remain.\n'
    printf 'STEP STATUS: %s is recorded as %s, because completion requires cleanup as well as checks.\n' \
      "${STEP_NAME:-this step}" "$outcome"
    exit "$rc"
  fi
  printf 'RESULT: every check in this step ran and passed, and cleanup completed.\n'
  printf 'STEP STATUS: %s is recorded as passed.\n' "${STEP_NAME:-this step}"
  exit "$rc"
}

# report_work_dir — says what is in the work directory, accurately.
#
# The sentence it replaces was "Evidence and sanitized logs remain in: <dir>".
# Nothing in that directory had been sanitized.
report_work_dir() {
  [ -n "$WORK" ] || return 0
  printf '\nThis step'\''s files are in: %s (mode 700)\n' "$WORK"
  if [ -n "$RAW" ] && [ -d "$RAW" ]; then
    printf '  %s\n' "$RAW"
    printf '      UNSANITIZED command output, exactly as the commands wrote it.\n'
    printf '      It may contain credential material. DO NOT SHARE IT.\n'
  fi
  if [ -n "$EVID" ] && [ -d "$EVID" ]; then
    printf '  %s\n' "$EVID"
    printf '      the same output through scripts/gate-diagnostics.sh --sanitize.\n'
    printf '      These are the files to return. The filter is deny-by-pattern:\n'
    printf '      it establishes what its patterns catch, and nothing wider.\n'
  fi
  printf 'Remove the whole directory with:  rm -rf -- %s\n' "$WORK"
  printf 'Do that only after the recorded values have been copied out.\n'
}

# shellcheck disable=SC2329  # reached indirectly via trap
on_exit() {
  local rc=$?
  run_cleanup
  # A step that reached here still `running` ended without recording a verdict:
  # a refusal after it began, or a death. That is INDETERMINATE and not
  # `failed`, because what it established is unknown — and a later step refuses
  # it in those words rather than in failure's.
  if [ "$STEP_STARTED" -eq 1 ]; then
    printf '\nthis step ended without recording a verdict; it is recorded as INDETERMINATE\n'
    record_step_outcome indeterminate
  fi
  release_work_lock
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
  record_step_outcome interrupted
  # `exit` re-enters on_exit, where run_cleanup is a no-op and STEP_STARTED is
  # already cleared: the destructive operations and the state write each happen
  # exactly once however many traps fire, and the recorded outcome stays
  # `interrupted` rather than being overwritten with `indeterminate`.
  exit "$2"
}

# Installed here, before any step body runs and therefore before anything can
# create a resource.
trap on_exit EXIT
trap 'on_signal INT 130' INT
trap 'on_signal TERM 143' TERM

# --- Invocation identity ------------------------------------------------------
#
# RECORD_INVOCATION is 1 for every step that can create a Docker resource, and 0
# for step Z, which creates none and must not add itself to the register it is
# about to search.
RECORD_INVOCATION=1
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

  # -- the invocation register -------------------------------------------------
  #
  # Recorded HERE, before anything can be created, and never cleared by a
  # failure or an invalidation. This is not a completion record — it is a
  # resource-attribution record, and step Z needs it most for the steps that
  # did NOT finish.
  #
  # Step Z used to call begin_invocation itself and then enumerate resources
  # carrying ITS OWN freshly generated project label. begin_invocation has
  # already refused if anything carries that label, so the enumeration was
  # guaranteed to find nothing: "no container of this handoff remains" was a
  # tautology, printed as a pass, for every closeout that ever ran. The step
  # even said so — "this step can only speak for its own" — which was an
  # accurate description of a check that established nothing.
  if [ "$RECORD_INVOCATION" -eq 1 ] && [ -n "$STATE" ] && [ -f "$STATE" ]; then
    state_append_word HANDOFF_INVOCATIONS "${STEP_NAME:-unknown}:$INVOCATION:$VERIFY_PROJECT"
    ok "this invocation's ownership identities are recorded for step Z to search for"
  fi
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
  local err digest
  # Both live in raw/. The resolved configuration contains the deployment's
  # real host paths, which is exactly the kind of thing the shareable directory
  # must not accumulate, and it is deliberately never printed either way.
  CONFIG_JSON="$RAW/compose-config.json"
  err="$RAW/compose-config.err"
  assert_not_symlink "$CONFIG_JSON" "the resolved-configuration file"
  assert_not_symlink "$err" "the resolved-configuration error file"
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
  note "the resolved configuration stays in the raw directory and is never printed"

  # -- the configuration's IDENTITY --------------------------------------------
  #
  # A digest of the RESOLVED configuration, recorded with whichever step passes
  # against it. Steps B, C and D each verify properties of the deployment as
  # Compose resolves it; if that resolution changes between them — an edited
  # .env, an edited compose.yaml, a changed default — then B's acceptance is
  # about a deployment that no longer exists, and step D must not treat it as
  # covering the one it is authenticating against.
  #
  # The digest is over the resolved JSON, not over the source files, because
  # the source files are not what the steps checked.
  if digest="$(sha256sum -- "$CONFIG_JSON" 2>/dev/null)"; then
    BIND_CONFIG="${digest%% *}"
    if [ "${#BIND_CONFIG}" -eq 64 ]; then
      ok "the resolved configuration has an identity (sha256, first 12: ${BIND_CONFIG:0:12})"
    else
      BIND_CONFIG=""
      blocked "the resolved configuration's digest is malformed — configuration identity UNPROVEN"
    fi
  else
    BIND_CONFIG=""
    blocked "the resolved configuration could not be hashed — configuration identity UNPROVEN"
  fi
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
# --- Pre-start assertions, and the start they gate ----------------------------
#
# These assertions exist to establish that a container is isolated the way its
# step requires BEFORE it runs: that the credential-free probe has no
# credential to read, and that the offline probe has no network to reach.
#
# Their return values were DISCARDED. Every call site read like this:
#
#     assert_no_mount "no credential is mounted into the connectivity probe" ...
#     assert_network_mode "the probe has network access" bridge
#     capture_run doctor.log docker start -a "$PROBE_CID"
#
# so a container whose isolation assertion FAILED was started anyway. The step
# reported the failure and then did the thing the failure said not to do: step
# B would have started a container with the real password mounted while
# printing that no credential was mounted, and step C would have started a
# container with network access while printing that it had none. The report was
# accurate and the program ignored it.
#
# PROBE_BLOCKED is raised by any pre-start assertion that fails OR that cannot
# be evaluated — an unreadable mount list is not permission to start, it is the
# absence of the evidence that starting requires — and start_probe refuses
# while it is nonzero.
PROBE_BLOCKED=0
probe_precondition_failed() { PROBE_BLOCKED=$((PROBE_BLOCKED + 1)); }

# start_probe <label> <capture basename> — the ONLY place a probe container is
# started.
start_probe() {
  if [ "$PROBE_BLOCKED" -ne 0 ]; then
    bad "$1: the container was NOT started — $PROBE_BLOCKED pre-start isolation assertion(s) did not pass"
    note "a container whose isolation could not be established is not started, whatever else"
    note "this step would have gone on to check. The container is removed by cleanup below."
    return 1
  fi
  capture_run "$2" docker start -a "$PROBE_CID"
  return 0
}

PROBE_CID=""
create_probe() { # <expected-image-id> <label> <args...>
  local expected="$1" label="$2"; shift 2
  local err actual
  PROBE_CID=""
  PROBE_BLOCKED=0
  err="$RAW/create.err"
  assert_not_symlink "$err" "the container-creation error file"
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
    bad "$label: the created container's image could not be read — identity UNPROVEN"
    probe_precondition_failed
    return 1; }
  if [ "$actual" != "$expected" ]; then
    bad "$label: the created container runs image $actual, not the verified $expected"
    probe_precondition_failed
    return 1
  fi
  ok "$label: the created container runs exactly the image verified in step A"
  return 0
}

# assert_no_mount <label> <destination that must NOT be mounted>
assert_no_mount() {
  local dests
  dests="$(docker inspect -f '{{range .Mounts}}{{.Destination}}{{"\n"}}{{end}}' "$PROBE_CID" 2>/dev/null)" || {
    blocked "$1 (the container's mounts could not be listed — result UNPROVEN)"
    probe_precondition_failed
    return 1; }
  if in_list "$2" "$dests"; then
    bad "$1 — $2 IS mounted"
    probe_precondition_failed
    return 1
  fi
  ok "$1"
  return 0
}

assert_network_mode() { # <label> <expected>
  local mode
  mode="$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$PROBE_CID" 2>/dev/null)" || {
    blocked "$1 (the container's network mode could not be read — result UNPROVEN)"
    probe_precondition_failed
    return 1; }
  if [ "$mode" = "$2" ]; then ok "$1 ($2)"; return 0; fi
  bad "$1: network mode is '$mode', expected '$2'"
  probe_precondition_failed
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
  # Created fresh. This is preflight: the identities and step states of any
  # earlier run in this directory must not survive into a new one, and a
  # state file left behind by something else must not be adopted.
  assert_not_symlink "$STATE" "the state file"
  rm -f -- "$STATE" || refuse "an existing state file could not be removed: $STATE"
  ( umask 077; : > "$STATE" ) || refuse "the state file could not be created: $STATE"
  chmod 600 -- "$STATE" || refuse "the state file's mode could not be set: $STATE"
  assert_state_file_trusted
  begin_step preflight
  stage_result EXPECTED_COMMIT "$expected"
  stage_result REPO_ROOT "$REPO_ROOT"
  stage_result REPO_OWNER "$REPO_OWNER"
  ok "source and expected-checkout identity will be recorded if this step passes"

  # The deployment secret's BASELINE metadata, recorded HERE — before any step
  # has run — because step Z compares against "the values recorded earlier in
  # the same work directory" and nothing was recording them.
  #
  # step_closeout used to take its own baseline when it found none, print "no
  # earlier metadata was recorded", and report `ok`. On a single pass — 0, A, B,
  # C, D, Z, which is the whole procedure — that was every run: the comparison
  # never happened and the step reported a pass for it anyway. A check that
  # cannot have run must not read as one that passed.
  #
  # This is metadata only: owner, group, mode, size, mtime. No credential is
  # opened, here or in step Z's default path.
  local secret_meta
  if secret_meta="$(stat -c '%u:%g %a %s %Y' -- "$EXPECTED_SECRET_SOURCE" 2>/dev/null)"; then
    stage_result SECRET_META "$secret_meta"
    ok "the deployment secret's baseline metadata is recorded (uid:gid mode size mtime; content NOT read)"
  else
    # NOT a failure of this step. Preflight deliberately requires neither Docker
    # nor the deployment — it checks identity and environment — and failing here
    # would make it unusable on any host where the deployment is absent.
    #
    # The absence is RECORDED instead, and step Z turns it into UNPROVEN there.
    # That is where it belongs: the claim being made is step Z's, so the step
    # that cannot support it is the step that must report so.
    stage_result SECRET_META_UNAVAILABLE "1"
    note "the deployment secret's metadata could not be read at $EXPECTED_SECRET_SOURCE"
    note "this is recorded, not failed, because preflight does not require the deployment."
    note "Step Z will report its comparison as UNPROVEN rather than taking a baseline of its own."
  fi
  note "pass --work-dir $WORK to every following step"
  summary_and_exit
}

step_build() { # step A
  local expected image prior after version build_date
  printf '== step A: build the candidate and verify the deployment against it ==\n'
  # Prerequisite first, and it is about what an earlier step RECORDED, not
  # about which files happen to exist.
  require_step_passed preflight "step A must know which checkout it is building and where the state for it lives"
  begin_step build
  # A rebuild voids every downstream acceptance, and the previous IMAGE_ID with
  # it, BEFORE the build runs. See invalidate_after_rebuild.
  invalidate_after_rebuild "this rebuild"
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
  capture_run "build.log" \
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
  assert_capture_usable "build log" "build.log"
  if [ "$build_rc" -ne 0 ]; then
    bad "the image build failed (exit $build_rc)"
    print_diagnostic "$(raw_log build.log)"
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
  BIND_IMAGE="$image"
  # STAGED, not written, and staged HERE — where the identity becomes known —
  # rather than at the end of the step. summary_and_exit records them only if
  # this step is recorded as passed, which requires every check below AND
  # cleanup. Writing them at all was what let a build whose runtime
  # verification FAILED publish the image id that steps B, C and D then created
  # their containers from; staging them early is what makes the withholding
  # visible to the operator in the step's own output.
  stage_result IMAGE_ID "$image"
  stage_result BUILD_COMMIT "$expected"
  stage_result BUILD_DATE "$build_date"
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
    if start_probe "the version probe" "version.log"; then
      printf 'VERSION exit=%d\n' "$LAST_RC"
      if [ "$LAST_RC" -ne 0 ]; then
        bad "the built binary did not run"
        print_diagnostic "$(raw_log version.log)"
      elif assert_capture_usable "version output" "version.log"; then
        expect_in_file "the binary reports the expected commit $expected" \
          "^commit[[:space:]]+$expected\$" "$(raw_log version.log)"
        expect_in_file "the binary reports enforcement as NOT compiled in" \
          '^enforcement compiled in[[:space:]]+false$' "$(raw_log version.log)"
      fi
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
  capture_run "verify.log" \
    env SCAMWALL_IMAGE="$image" SCAMWALL_EXPECTED_IMAGE_ID="$image" \
        bash "$VERIFIER"
  printf 'VERIFY exit=%d\n' "$LAST_RC"
  if [ "$LAST_RC" -eq 0 ]; then
    ok "the runtime verifier passed against the verified image"
  else
    bad "the runtime verifier did not pass (exit $LAST_RC)"
    print_diagnostic "$(raw_log verify.log)"
  fi
  assert_capture_usable "runtime verifier log" "verify.log"
  # The FINDING-29 line is the evidence this renewal exists to produce.
  expect_in_file "the password-readability judgement was evaluated (FINDING-29)" \
    'the application password would be readable by the container identity' "$(raw_log verify.log)"

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
  n="$(sed -n "s|^#\([0-9][0-9]*\) \[[^]]*\] RUN .*${needle}.*|\1|p" "$(raw_log build.log)" 2>/dev/null | head -1)"
  if [ -z "$n" ]; then
    bad "$label: no build step matched \"$needle\" — the assertion cannot be shown to have run"
    note "read $(raw_log build.log) in full"
    return 1
  fi
  steps="$(grep -E "^#${n}( |\$)" "$(raw_log build.log)" 2>/dev/null)"
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
  require_step_passed preflight "step B must know which checkout and which work directory it belongs to"
  require_step_passed build "step B must run the image that step A built and verified"
  begin_step probe
  assert_no_overrides
  resolve_repo_owner
  expected="$(state_require EXPECTED_COMMIT)"
  image="$(state_require IMAGE_ID)"
  BIND_IMAGE="$image"
  assert_source_identity "$expected"
  # Step A passed — but against WHICH commit and WHICH image? A recorded pass
  # is not a binding, and only the binding makes that pass transferable here.
  assert_prereq_identities build || summary_and_exit
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

  start_probe "the connectivity probe" "doctor.log" || summary_and_exit
  printf 'DOCTOR exit=%d\n' "$LAST_RC"
  assert_capture_usable "doctor output" "doctor.log" || summary_and_exit

  # The run must show that it did NOT read the credential. This is the line the
  # superseded procedure contradicted: it claimed no password was read while
  # its own expected output reported the password as readable.
  expect_in_file "doctor reports the credential check as SKIPPED, not as passed" \
    '^SKIP[[:space:]]+application password' "$(raw_log doctor.log)"
  expect_absent_from_file "doctor makes no claim that the credential is readable" \
    '^ok[[:space:]]+application password' "$(raw_log doctor.log)"

  expect_in_file "the mounted CA parsed as a real certificate" \
    '^ok[[:space:]]+certificate authority' "$(raw_log doctor.log)"
  if search_file '^ok[[:space:]]+pi-hole connectivity' "$(raw_log doctor.log)"; then
    ok "the pinned destination answered, the chain verified against the private CA, and the certificate is valid for pi.hole"
  else
    bad "the connectivity or TLS check did not pass — do NOT proceed to step D"
    print_diagnostic "$(raw_log doctor.log)"
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
  require_step_passed preflight "step C must know which checkout and which work directory it belongs to"
  require_step_passed build "step C must open the credential inside the image that step A verified"
  begin_step secret
  assert_no_overrides
  resolve_repo_owner
  expected="$(state_require EXPECTED_COMMIT)"
  image="$(state_require IMAGE_ID)"
  BIND_IMAGE="$image"
  assert_source_identity "$expected"
  # Step A passed — but against WHICH commit and WHICH image? A recorded pass
  # is not a binding, and only the binding makes that pass transferable here.
  assert_prereq_identities build || summary_and_exit
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

  start_probe "the secret probe" "secret.log" || summary_and_exit
  printf 'DOCTOR-OFFLINE exit=%d\n' "$LAST_RC"
  assert_capture_usable "doctor --offline output" "secret.log" || summary_and_exit

  if search_file '^ok[[:space:]]+application password[[:space:]]+readable' "$(raw_log secret.log)"; then
    ok "the container identity opened the mounted secret (uid 65532 with the configured supplementary group)"
  elif search_file '^FAIL[[:space:]]+application password' "$(raw_log secret.log)"; then
    bad "the container identity could NOT open the mounted secret"
    note "if step A's readability judgement passed and this failed, the two disagree,"
    note "and that disagreement outranks either result. The likely causes are the ones"
    note "step A names as assumptions: an ACL, a user-namespace remap, or a rootless daemon."
    print_diagnostic "$(raw_log secret.log)"
  else
    blocked "the credential check did not appear in the output at all"
    print_diagnostic "$(raw_log secret.log)"
  fi
  expect_absent_from_file "no credential length is disclosed" \
    'application password.*bytes' "$(raw_log secret.log)"
  if [ "$LAST_RC" -ne 0 ]; then
    bad "doctor --offline exited $LAST_RC"
  fi
  summary_and_exit
}

step_status() { # step D — the one authenticated operation
  local expected image
  printf '== step D: ONE reviewed authenticated read-only operation ==\n'
  # TWO independent gates, and neither substitutes for the other.
  #
  # The flag is the operator's INTENT: it says a human decided this run may
  # authenticate. The prerequisites are the EVIDENCE: they say steps A, B and C
  # actually passed, in this work directory, against these identities.
  #
  # This refusal already claimed both — "only after steps A, B and C have
  # passed and been read" — while checking only the flag. An operator who ran
  # step B, watched it fail, and then passed the flag got an authenticated
  # request to the live appliance and a program that had told them it would not
  # do that.
  if [ "${AUTHORISED_D:-0}" -ne 1 ]; then
    refuse "step D authenticates to the live Pi-hole. It runs only with --authorise-authenticated-read, and only after steps A, B and C have passed and been read."
  fi
  ok "the operator authorised one authenticated read-only operation on this invocation"
  note "that flag is intent, not evidence. The prerequisites below are the evidence,"
  note "and they are checked before anything is sent."
  require_step_passed preflight "step D must know which checkout and which work directory it belongs to"
  require_step_passed build  "step D must authenticate from the image that step A built and verified"
  require_step_passed probe  "step D must not authenticate before connectivity and TLS have been shown to work WITHOUT a credential"
  require_step_passed secret "step D must not authenticate before the container identity has been shown to open the credential OFFLINE"
  begin_step status
  assert_no_overrides
  resolve_repo_owner
  expected="$(state_require EXPECTED_COMMIT)"
  image="$(state_require IMAGE_ID)"
  BIND_IMAGE="$image"
  assert_source_identity "$expected"
  # Step A passed — but against WHICH commit and WHICH image? A recorded pass
  # is not a binding, and only the binding makes that pass transferable here.
  assert_prereq_identities build || summary_and_exit
  require_docker
  begin_invocation
  resolve_deployment_config
  assert_deployment_sources || summary_and_exit

  # Steps B and C passed — but against this image and THIS resolved deployment
  # configuration? An edited .env or compose.yaml between step B and step D
  # means B established something about a deployment that no longer exists.
  assert_prereq_identities probe  || summary_and_exit
  assert_prereq_identities secret || summary_and_exit

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

  start_probe "the status probe" "status.log" || summary_and_exit
  printf 'STATUS exit=%d\n' "$LAST_RC"
  assert_capture_usable "status output" "status.log" || summary_and_exit

  # Three different claims, kept apart.
  if search_file 'session logout ACCEPTED by Pi-hole' "$(raw_log status.log)"; then
    ok "the session teardown request was ACCEPTED by Pi-hole"
    note "that is a fact about a REQUEST. It is not independent confirmation that the"
    note "appliance's session table no longer holds the session — see below."
  elif search_file 'session ALREADY ABSENT' "$(raw_log status.log)"; then
    ok "Pi-hole reported no such session to destroy, which is the desired end state"
  elif search_file 'session logout FAILED' "$(raw_log status.log)"; then
    bad "the session teardown FAILED — a session may remain valid on the appliance until it expires"
  else
    blocked "the output makes no statement about the session teardown — result UNPROVEN"
  fi
  if [ "$LAST_RC" -ne 0 ]; then
    bad "status exited $LAST_RC"
    print_diagnostic "$(raw_log status.log)"
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
  begin_step closeout
  # Step Z creates nothing, so it must not enter the register it is about to
  # search: a closeout looking for its own leftovers is the tautology this step
  # used to be.
  RECORD_INVOCATION=0
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
    # No baseline. This step must NOT take one and call that a pass: a baseline
    # recorded at the end of the handoff is compared against nothing and
    # establishes nothing about what happened during it. The preflight step is
    # what records it, and if it could not, this is UNPROVEN.
    blocked "the secret's metadata cannot be compared: no baseline was recorded by the preflight step"
    if state_get SECRET_META_UNAVAILABLE >/dev/null 2>&1; then
      note "the preflight step recorded that it could not read $EXPECTED_SECRET_SOURCE"
    else
      note "run the preflight step for this work directory before closing out"
    fi
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
          stage_result SECRET_DIGEST "$digest_after"
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

  # -- nothing of THE EARLIER STEPS is left behind ----------------------------
  #
  # This is the check that was a tautology.
  #
  # Step Z called begin_invocation, which generates a NEW unpredictable
  # identifier and then REFUSES if anything already carries it. It then
  # enumerated resources carrying that same brand-new label — so the query was
  # guaranteed by construction to return nothing, and printed:
  #
  #     PASS    no container of this handoff remains
  #
  # for every closeout that has ever run, whatever steps A to D had left on the
  # host. The trailing note even described the defect accurately: "this step
  # can only speak for its own". It was speaking for an invocation that created
  # nothing.
  #
  # What it must examine is the identities of the invocations that ACTUALLY
  # created resources. Each of those recorded itself in the state file at
  # begin_invocation, before it could create anything, and that register is not
  # cleared by a failure, an interruption or an invalidation — a step that died
  # halfway is exactly the one whose leftovers matter.
  printf '\n-- leftovers from the steps that actually ran --\n'
  local kind found entry step inv proj rest searched=0
  local register
  register="$(state_get HANDOFF_INVOCATIONS)" || register=""
  if [ -z "$register" ]; then
    # NOT a pass. No step in this work directory recorded an invocation, so
    # either none ran or they ran somewhere else; either way this step has
    # nothing to search for and must not report a clean host.
    blocked "no step recorded an invocation identity in this work directory — leftovers are UNPROVEN"
    note "steps A to D record their ownership identities as they begin. If they were run,"
    note "they were run against a different work directory, and THAT directory's state file"
    note "is the one that can close them out."
  else
    for entry in $register; do
      step="${entry%%:*}"; rest="${entry#*:}"
      inv="${rest%%:*}"; proj="${rest##*:}"
      [ -n "$inv" ] && [ -n "$proj" ] || {
        blocked "a malformed invocation record was found in the state file — leftovers are UNPROVEN"
        continue; }
      note "searching for resources of step $step (invocation ${inv:0:8}…, project $proj)"
      for kind in container network volume; do
        # Both labels, because a resource may carry either: the ownership label
        # is applied directly, the project label through Compose.
        if ! found="$(label_query "$kind" "$PROJECT_LABEL=$proj")"; then
          blocked "${kind}s of step $step could not be enumerated by project label — leftovers are UNPROVEN"
          continue
        fi
        local found_own
        if ! found_own="$(label_query "$kind" "$OWN_LABEL=$inv")"; then
          blocked "${kind}s of step $step could not be enumerated by ownership label — leftovers are UNPROVEN"
          continue
        fi
        if ! found="$(combine_ids "$found" "$found_own")"; then
          blocked "the ${kind} lists for step $step could not be combined — leftovers are UNPROVEN"
          continue
        fi
        searched=$((searched + 1))
        if [ -z "$found" ]; then
          ok "no ${kind} of step $step remains"
        else
          bad "${kind}s of step $step REMAIN:"
          printf '%s\n' "$found" | sed 's/^/          /'
          note "remove them yourself after recording their identities; this step does not delete"
          note "resources it did not create."
        fi
      done
    done
    if [ "$searched" -eq 0 ]; then
      blocked "the invocation register was present but nothing could be enumerated — leftovers are UNPROVEN"
    fi
  fi
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
