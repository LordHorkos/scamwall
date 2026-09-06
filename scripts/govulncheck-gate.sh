#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
#
# govulncheck-gate.sh — decide the vulnerability gate from RESULT CONTENT,
# never from exit status alone.
#
# WHY THIS SCRIPT EXISTS
#
# `govulncheck ./...` in its default text mode exits 3 when it finds something,
# so a naive `if govulncheck ./...` gate happens to work. That correctness is
# accidental — it rests on a property of one output mode. In `-format json`
# (and in `-format sarif`) govulncheck exits **0 whether or not there are
# findings**. Measured on this host with govulncheck v1.7.0:
#
#     module with 58 findings, -format json   -> exit 0
#     module with 58 findings, default text   -> exit 3
#
# A gate written against JSON and trusting the exit status therefore reports a
# vulnerable dependency set as clean. Since CI and tooling generally want the
# machine-readable format, that is a live trap, not a hypothetical one.
#
# HOW THE OUTPUT IS READ
#
# The JSON stream is a sequence of tagged objects, not an array:
#
#     {"config": ...}     exactly one, emitted before the scan
#     {"progress": ...}   informational
#     {"SBOM": ...}       the scanned module set
#     {"osv": ...}        a vulnerability DATABASE entry that was consulted
#     {"finding": ...}    an actual finding against this code
#
# The distinction between `osv` and `finding` is the whole game. A clean
# ScamWall scan emits 202 `osv` records and zero `finding` records, so a gate
# that counted `osv` would fail every single run. Only `finding` counts.
#
# Findings carry a level, read from the deepest populated element of .trace[0]:
#
#     required   the vulnerable module is in the build graph
#     imported   a vulnerable package is imported
#     called     a vulnerable symbol is reachable from this code
#
# All three fail this gate. `called` is reported separately because it is what
# an operator triages first, not because the others are acceptable.
#
# UNPARSEABLE IS NOT CLEAN
#
# If the output cannot be parsed, or carries no `config` record, the scan did
# not demonstrably run. That is reported as UNPROVEN with exit 2 — never as a
# pass.
#
# Usage:
#   scripts/govulncheck-gate.sh                 # scan ./...
#   scripts/govulncheck-gate.sh --from-file F   # evaluate a captured stream
#   scripts/govulncheck-gate.sh --self-test     # prove the gate fails on findings
#
# Exit codes: 0 clean, 1 findings, 2 could not run / unproven.

set -uo pipefail

MODE="scan"
FROM_FILE=""
case "${1:-}" in
  ""|--scan)   MODE="scan" ;;
  --from-file) MODE="file"; FROM_FILE="${2:-}"
               [ -n "$FROM_FILE" ] || { printf 'fatal: --from-file needs a path\n' >&2; exit 2; } ;;
  --self-test) MODE="selftest" ;;
  -h|--help)   sed -n '3,58p' "$0"; exit 0 ;;
  *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
esac

command -v jq >/dev/null 2>&1 || {
  printf 'BLOCKED: jq is required to evaluate govulncheck output and is not installed.\n' >&2
  exit 2; }

WORK="$(mktemp -d)" || { printf 'fatal: could not create a working directory\n' >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

# evaluate <path> <label>
#
# Prints a verdict and returns 0 clean, 1 findings, 2 unproven.
evaluate() {
  local out="$1" label="$2" total called imported required osv_count

  if [ ! -s "$out" ]; then
    printf 'UNPROVEN  %s: govulncheck produced no output\n' "$label"
    return 2
  fi
  # Every record must parse. A partially written stream is not a clean stream.
  if ! jq -e . < "$out" >/dev/null 2>&1; then
    printf 'UNPROVEN  %s: output is not valid JSON — the scan cannot be evaluated\n' "$label"
    return 2
  fi
  # The config record proves govulncheck actually started a scan rather than
  # emitting, say, a lone progress line before dying.
  if ! jq -e -s 'map(select(has("config"))) | length == 1' < "$out" >/dev/null 2>&1; then
    printf 'UNPROVEN  %s: no single config record — the scan did not demonstrably run\n' "$label"
    return 2
  fi

  osv_count="$(jq -s 'map(select(has("osv"))) | length' < "$out" 2>/dev/null)" || osv_count="?"

  if ! total="$(jq -s 'map(select(has("finding"))) | length' < "$out" 2>/dev/null)"; then
    printf 'UNPROVEN  %s: finding records could not be counted\n' "$label"
    return 2
  fi

  if [ "$total" -eq 0 ]; then
    printf 'PASS      %s: 0 findings (%s vulnerability database entries consulted)\n' "$label" "$osv_count"
    return 0
  fi

  called="$(jq -s -r '[ .[] | select(has("finding")) | .finding
                        | select((.trace[0].function // "") != "") | .osv ] | unique | length' < "$out" 2>/dev/null || echo '?')"
  imported="$(jq -s -r '[ .[] | select(has("finding")) | .finding
                          | select((.trace[0].function // "") == "" and (.trace[0].package // "") != "") | .osv ] | unique | length' < "$out" 2>/dev/null || echo '?')"
  required="$(jq -s -r '[ .[] | select(has("finding")) | .finding
                          | select((.trace[0].function // "") == "" and (.trace[0].package // "") == "") | .osv ] | unique | length' < "$out" 2>/dev/null || echo '?')"

  printf 'FAIL      %s: %s finding record(s)\n' "$label" "$total"
  printf '          reachable (called): %s | imported: %s | required only: %s  [distinct advisories]\n' \
         "$called" "$imported" "$required"

  if [ "$called" != "0" ] && [ "$called" != "?" ]; then
    printf '          reachable advisories:\n'
    jq -s -r '[ .[] | select(has("finding")) | .finding
                | select((.trace[0].function // "") != "")
                | "            \(.osv)  \(.trace[0].module // "?")  \(.trace[0].function // "")" ] | unique | .[]' \
       < "$out" 2>/dev/null | head -25
  fi
  return 1
}

# --- Self-test ----------------------------------------------------------------
#
# A gate that cannot be shown to fail is not a gate. Three fixtures cover the
# three outcomes, including the one this script exists for: a stream carrying
# findings alongside the exit status 0 that JSON mode would have produced.
if [ "$MODE" = "selftest" ]; then
  rc_all=0

  cat > "$WORK/clean.json" <<'JSON'
{"config":{"protocol_version":"v1.0.0","scanner_name":"govulncheck"}}
{"osv":{"id":"GO-0000-0001"}}
{"osv":{"id":"GO-0000-0002"}}
JSON

  cat > "$WORK/findings.json" <<'JSON'
{"config":{"protocol_version":"v1.0.0","scanner_name":"govulncheck"}}
{"osv":{"id":"GO-0000-0001"}}
{"finding":{"osv":"GO-0000-0001","fixed_version":"v1.2.3","trace":[{"module":"example.com/m","package":"example.com/m/p","function":"Vulnerable"}]}}
{"finding":{"osv":"GO-0000-0002","fixed_version":"v2.0.0","trace":[{"module":"example.com/n"}]}}
JSON

  printf 'this is not json\n' > "$WORK/broken.json"
  : > "$WORK/empty.json"
  printf '{"progress":{"message":"started"}}\n' > "$WORK/noconfig.json"

  echo "== govulncheck-gate self-test =="

  evaluate "$WORK/clean.json" "fixture: no findings"; rc=$?
  if [ "$rc" -eq 0 ]; then echo "  ok   clean stream -> clean"; else echo "  FAIL clean stream returned $rc"; rc_all=1; fi

  # The load-bearing case. In -format json govulncheck exits 0 here.
  evaluate "$WORK/findings.json" "fixture: findings present, exit status would be 0"; rc=$?
  if [ "$rc" -eq 1 ]; then echo "  ok   findings -> gate fails despite a zero exit status"; else echo "  FAIL findings returned $rc, expected 1"; rc_all=1; fi

  evaluate "$WORK/broken.json" "fixture: unparseable"; rc=$?
  if [ "$rc" -eq 2 ]; then echo "  ok   unparseable -> UNPROVEN, not clean"; else echo "  FAIL unparseable returned $rc, expected 2"; rc_all=1; fi

  evaluate "$WORK/empty.json" "fixture: empty"; rc=$?
  if [ "$rc" -eq 2 ]; then echo "  ok   empty -> UNPROVEN, not clean"; else echo "  FAIL empty returned $rc, expected 2"; rc_all=1; fi

  evaluate "$WORK/noconfig.json" "fixture: no config record"; rc=$?
  if [ "$rc" -eq 2 ]; then echo "  ok   missing config -> UNPROVEN, not clean"; else echo "  FAIL missing config returned $rc, expected 2"; rc_all=1; fi

  echo
  if [ "$rc_all" -eq 0 ]; then echo "self-test passed."; else echo "self-test FAILED."; fi
  exit "$rc_all"
fi

# --- Evaluate a captured stream -----------------------------------------------
if [ "$MODE" = "file" ]; then
  evaluate "$FROM_FILE" "captured stream $FROM_FILE"
  exit $?
fi

# --- Scan ---------------------------------------------------------------------
command -v govulncheck >/dev/null 2>&1 || {
  printf 'BLOCKED: govulncheck is not installed — the vulnerability gate could not run.\n' >&2
  exit 2; }

VER="$(govulncheck -version 2>/dev/null | tr '\n' ' ' | tr -s ' ')"
printf 'govulncheck-gate: %s\n' "${VER:-version unknown}"

OUT="$WORK/govulncheck.json"
ERR="$WORK/govulncheck.err"
# The exit status is captured and REPORTED, but is deliberately not the
# decision. It is useful context when the scan itself failed to run.
govulncheck -format json ./... > "$OUT" 2> "$ERR"
GV_RC=$?

evaluate "$OUT" "go modules (./...)"
VERDICT=$?

if [ "$VERDICT" -eq 2 ]; then
  printf '          govulncheck exit status was %d\n' "$GV_RC"
  [ -s "$ERR" ] && sed 's/^/          /' "$ERR" | head -15
fi
exit "$VERDICT"
