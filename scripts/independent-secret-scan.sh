#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
#
# independent-secret-scan.sh — run a third-party secret detector over exactly
# what this PUBLIC repository would publish.
#
# This complements scripts/secret-scan.sh; it does not replace it. The project
# scanner encodes ScamWall-specific knowledge (forbidden paths, the Pi-hole
# password, private CA material). This one carries a large corpus of generic
# vendor credential formats that a hand-written scanner will never cover.
# Neither is a superset of the other, so both are required gates.
#
# WHAT IS SCANNED
#
#   history   every commit reachable from HEAD
#   tree      the publishable tree, materialised with `git archive`
#
# The tree scan deliberately does NOT scan the working directory. A raw
# directory scan reports the operator's correctly-gitignored local key material
# as a finding, and a detector that cries wolf about files that can never be
# published is a detector people learn to ignore. `git archive` produces
# exactly the bytes a clone would receive.
#
# Usage:
#   scripts/independent-secret-scan.sh            # history + HEAD tree
#   scripts/independent-secret-scan.sh --staged   # history + the staged index
#   scripts/independent-secret-scan.sh --self-test  # prove the detector fires
#
# Exit codes: 0 clean, 1 findings, 2 usage or environment error.

set -uo pipefail

MODE="head"
case "${1:-}" in
  ""|--head)  MODE="head" ;;
  --staged)   MODE="staged" ;;
  --self-test) MODE="selftest" ;;
  -h|--help)  sed -n '3,29p' "$0"; exit 0 ;;
  *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
esac

# Repository root. Each prerequisite is asserted separately: `cd "$(git ...)"`
# succeeds with an empty argument when git is absent, which would silently scan
# whatever directory this happened to be launched from.
command -v git >/dev/null 2>&1 || {
  printf 'fatal: git is required and was not found on PATH\n' >&2; exit 2; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  printf 'fatal: not inside a git repository\n' >&2; exit 2; }
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || {
  printf 'fatal: could not determine the repository root\n' >&2; exit 2; }
cd "$REPO_ROOT" || {
  printf 'fatal: could not enter repository root: %s\n' "$REPO_ROOT" >&2; exit 2; }

if ! command -v gitleaks >/dev/null 2>&1; then
  # BLOCKED, not skipped. A detector that did not run has proven nothing, and
  # the caller must not read this exit status as "clean".
  printf 'BLOCKED: gitleaks is not installed — the independent secret scan could not run.\n' >&2
  printf 'Install it, then rerun. This is a required gate and is not optional.\n' >&2
  exit 2
fi

CONFIG="$REPO_ROOT/.gitleaks.toml"
[ -f "$CONFIG" ] || { printf 'fatal: %s not found\n' "$CONFIG" >&2; exit 2; }

WORK="$(mktemp -d)" || { printf 'fatal: could not create a working directory\n' >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

GITLEAKS_VERSION="$(gitleaks version 2>/dev/null | tr -d '\r')"
printf 'independent-secret-scan: gitleaks %s, mode=%s\n\n' "${GITLEAKS_VERSION:-unknown}" "$MODE"

FINDINGS=0
FAILED=0

# run_scan <label> <report-name> <gitleaks args...>
#
# gitleaks exits 1 when it finds something and 0 when it does not, but it also
# exits nonzero on a configuration or IO error. Those must not be conflated: a
# scanner that could not start is not a clean scanner. The report file is
# therefore parsed, and an unreadable report is an error rather than a pass.
run_scan() {
  local label="$1" name="$2"; shift 2
  local report="$WORK/$name.json" log="$WORK/$name.log" rc count

  "$@" --config "$CONFIG" --no-banner --redact \
       --report-format json --report-path "$report" >"$log" 2>&1
  rc=$?

  if [ ! -f "$report" ]; then
    printf 'ERROR  %s: gitleaks produced no report (exit %d)\n' "$label" "$rc"
    sed 's/^/       /' "$log" | head -20
    FAILED=$((FAILED + 1))
    return
  fi
  if ! count="$(jq 'length' < "$report" 2>/dev/null)"; then
    printf 'ERROR  %s: report could not be parsed — result UNPROVEN\n' "$label"
    FAILED=$((FAILED + 1))
    return
  fi

  # jq succeeded, but assert the result is actually a number before comparing.
  # `[ "" -eq 0 ]` is a shell error, not a false — and an error here would be
  # read as "there were findings", or worse, printed as a nonsense count. An
  # uncountable report means the scan was not evaluated.
  case "$count" in
    ''|*[!0-9]*)
      printf 'ERROR  %s: finding count %q is not a number — result UNPROVEN\n' "$label" "$count"
      FAILED=$((FAILED + 1))
      return ;;
  esac

  if [ "$count" -eq 0 ]; then
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then
      # No findings, but the tool still failed. Something went wrong before or
      # during the scan; reporting "clean" here is exactly the false pass this
      # script exists to avoid.
      printf 'ERROR  %s: gitleaks exited %d with an empty report — result UNPROVEN\n' "$label" "$rc"
      sed 's/^/       /' "$log" | head -20
      FAILED=$((FAILED + 1))
      return
    fi
    printf 'PASS   %s: no findings\n' "$label"
    return
  fi

  printf 'FAIL   %s: %d finding(s)\n' "$label" "$count"
  # Values are redacted by --redact; only rule, location and description print.
  jq -r '.[] | "       \(.RuleID)  \(.File):\(.StartLine)  \(.Description)"' \
     < "$report" 2>/dev/null | head -40
  FINDINGS=$((FINDINGS + count))
}

# --- Self-test: prove the detector actually fires ------------------------------
#
# A scanner that reports "clean" because it silently matched nothing is
# indistinguishable from a working one until the day it matters. This plants a
# synthetic credential in a throwaway repository and requires a hit.
if [ "$MODE" = "selftest" ]; then
  CTRL="$WORK/control"
  mkdir -p "$CTRL"
  # A syntactically valid but entirely fictional AWS access key id. It matches
  # no real account.
  #
  # The value is ASSEMBLED FROM FRAGMENTS so that this script's own source
  # never contains a string a secret scanner would match. Whitelisting the
  # scanner's own source would create exactly the blind spot the scanner
  # exists to close.
  #
  # It is also deliberately NOT one of the well-known documentation keys that
  # AWS publishes in its own examples: gitleaks allowlists those by design, so
  # a control built from one would "fail" while the detector was working
  # perfectly — and, worse, could be "fixed" by weakening the config.
  printf 'aws_access_key_id = "%s%s%s"\n' 'AKIA' 'Z3QP7XW2' 'MNVK4TBD' > "$CTRL/planted.txt"

  gitleaks dir "$CTRL" --config "$CONFIG" --no-banner --redact \
    --report-format json --report-path "$WORK/control.json" >"$WORK/control.log" 2>&1
  ctrl_count="$(jq 'length' < "$WORK/control.json" 2>/dev/null || echo 0)"
  if [ "${ctrl_count:-0}" -ge 1 ]; then
    printf 'PASS   positive control: planted credential detected (%s finding(s))\n' "$ctrl_count"
    printf '\nself-test passed: the detector fires on a known-bad input.\n'
    exit 0
  fi
  printf 'FAIL   positive control: planted credential NOT detected\n'
  sed 's/^/       /' "$WORK/control.log" | head -10
  printf '\nself-test FAILED: a clean result from this detector cannot be trusted.\n'
  exit 1
fi

# --- 1. History ---------------------------------------------------------------
# Anything ever committed is public forever once pushed, so history is scanned
# in full rather than only the current tip.
run_scan "history (all commits)" history gitleaks git "$REPO_ROOT"

# --- 2. Publishable tree ------------------------------------------------------
TREE="$WORK/tree"
mkdir -p "$TREE"
case "$MODE" in
  head)   ARCHIVE_REF="HEAD" ;;
  staged) ARCHIVE_REF="$(git write-tree)" || {
            printf 'fatal: could not write the index tree\n' >&2; exit 2; } ;;
esac

if ! git archive --format=tar "$ARCHIVE_REF" 2>"$WORK/archive.err" | tar -x -C "$TREE" 2>>"$WORK/archive.err"; then
  printf 'ERROR  publishable tree: could not be materialised — result UNPROVEN\n'
  sed 's/^/       /' "$WORK/archive.err" | head -10
  FAILED=$((FAILED + 1))
else
  # The config must travel with the tree: gitleaks resolves relative allowlist
  # paths against the scan root.
  cp "$CONFIG" "$TREE/.gitleaks.toml" 2>/dev/null || true
  run_scan "publishable tree ($MODE)" tree gitleaks dir "$TREE"
fi

# --- Result -------------------------------------------------------------------
echo
if [ "$FAILED" -gt 0 ]; then
  printf 'independent-secret-scan: %d scan(s) could not complete. Result UNPROVEN.\n' "$FAILED"
  exit 2
fi
if [ "$FINDINGS" -gt 0 ]; then
  printf 'independent-secret-scan: %d finding(s). Commit refused.\n' "$FINDINGS"
  printf 'A false positive is fixed by a JUSTIFIED, narrowly scoped entry in .gitleaks.toml.\n'
  exit 1
fi
printf 'independent-secret-scan: clean (gitleaks %s).\n' "${GITLEAKS_VERSION:-unknown}"
exit 0
