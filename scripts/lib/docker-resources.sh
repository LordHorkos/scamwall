#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
#
# docker-resources.sh — attribution and cleanup for Docker resources created by
# an operator-executed script. SOURCED, never executed.
#
# This was extracted verbatim from container-runtime-verify.sh so that a second
# operator script could not grow a second, weaker copy of it. Every rule below
# exists because its absence produced a wrong result, and the reasoning is kept
# with the code rather than restated somewhere else.
#
# The sourcing script must, BEFORE sourcing this file:
#   * set `set -uo pipefail`;
#   * define `note <message>` for indented informational output;
#   * initialise `CLEANUP_PROBLEMS=0`;
#   * have `docker` and `jq` on PATH (or accept BLOCKED results from them).
#
# The sourcing script must, AFTER sourcing this file and BEFORE creating any
# resource:
#   * set INVOCATION to an unpredictable per-invocation identifier;
#   * set VERIFY_PROJECT to the Compose project name derived from it;
#   * take the pre-existing-resource snapshot;
#   * install traps that reach run_cleanup.
#
# CLEANUP_WORK_DIR controls whether run_cleanup deletes WORK_DIR. It defaults
# to 1, which is what the runtime verifier has always done. An operator
# procedure that must leave sanitized logs behind for evidence sets it to 0 and
# reports the path itself; erasing a failure log before the operator has read
# it is a defect, not tidiness.
CLEANUP_WORK_DIR="${CLEANUP_WORK_DIR:-1}"

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

  if [ "$CLEANUP_WORK_DIR" -eq 1 ] && [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
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
