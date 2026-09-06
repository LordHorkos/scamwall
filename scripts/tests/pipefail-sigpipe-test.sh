#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
#
# pipefail-sigpipe-test.sh — refuse to let a short-circuiting consumer decide a
# condition inside a `pipefail` script.
#
# THE BUG THIS PREVENTS
#
# Under `set -o pipefail`:
#
#     if producer | grep -q PATTERN; then ...
#
# is a race, not a test. `grep -q` exits as soon as it matches. If the producer
# has not finished writing, it takes SIGPIPE and dies with 141, and pipefail
# makes that the status of the whole pipeline. The `if` then reads false — for
# input that DID match.
#
# Measured in this repository: a private-key marker at the head of a 1 MB
# string was missed by `printf '%s' "$c" | grep -qE -- "$PRIV_RE"` on 200 runs
# out of 200, while `grep -qE -- "$PRIV_RE" <<<"$c"` caught it every time.
#
# Which direction the error goes depends on the caller, and both are bad:
#
#   * `if ... grep -q X; then report_finding` — a real finding is silently
#     dropped. This is what scripts/secret-scan.sh did.
#   * `if ... grep -q X; then fail; else pass` — a violation is recorded as a
#     PASS. This is what runtime-verify-test.sh's expect_no_output did.
#
# The second is the dangerous one: it is a false pass in a security regression
# test, and it announces nothing.
#
# THE RULE
#
# In any script that sets `pipefail`, a pipeline whose LAST stage
# short-circuits (`grep -q`, `grep -l`, `head`) must not be used as a
# condition. Use a herestring (`grep -q PAT <<<"$var"`), pass the file
# directly (`grep -q PAT file`), or capture the producer's output first.
#
# Diagnostic uses — printing a truncated tail with `| head` — are unaffected,
# because their status is discarded. Only conditions are checked here.
#
# Usage: scripts/tests/pipefail-sigpipe-test.sh
# Exit status: 0 clean, 1 violations found, 2 environment error.

set -uo pipefail

command -v git >/dev/null 2>&1 || {
  printf 'fatal: git is required and was not found on PATH\n' >&2; exit 2; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  printf 'fatal: not inside a git repository\n' >&2; exit 2; }
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || { printf 'fatal: could not determine the repository root\n' >&2; exit 2; }
cd "$REPO_ROOT" || { printf 'fatal: could not enter %s\n' "$REPO_ROOT" >&2; exit 2; }

# A pipeline ending in a short-circuiting consumer, used as a CONDITION:
# after `if`, `elif`, `&&`, `||`, or `!`.
COND_PIPE='(^|[[:space:]])(if|elif|&&|\|\|)[[:space:]].*\|[[:space:]]*(grep[[:space:]]+-[a-zA-Z]*q|head)([[:space:]]|$)'

VIOLATIONS=0
CHECKED=0

# Tracked scripts AND untracked-but-not-ignored ones.
#
# `git ls-files` alone lists only what is in the index. A script added to the
# working tree but not yet staged would then be invisible to this check, and
# the check would report a clean result over a smaller file set than the reader
# assumes. That happened during Phase 1: two new scripts were analysed as clean
# while they were untracked, and one of them was in violation.
mapfile -t SCRIPTS < <( { git ls-files '*.sh'; git ls-files --others --exclude-standard '*.sh'; } | sort -u )
if [ "${#SCRIPTS[@]}" -eq 0 ]; then
  printf 'fatal: no shell scripts are tracked — nothing was checked\n' >&2
  exit 2
fi

echo "== pipefail / SIGPIPE condition check =="

for f in "${SCRIPTS[@]}"; do
  # Only scripts that actually enable pipefail can hit this.
  grep -qE '^[[:space:]]*set[[:space:]].*pipefail' "$f" || continue
  CHECKED=$((CHECKED + 1))

  # Comment lines are excluded: this file, and several others, DESCRIBE the bad
  # pattern in prose so that nobody reintroduces it out of ignorance.
  hits="$(grep -nE "$COND_PIPE" "$f" | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
  if [ -n "$hits" ]; then
    printf 'FAIL %s\n' "$f"
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      printf '     %s\n' "$line"
      VIOLATIONS=$((VIOLATIONS + 1))
    done <<< "$hits"
  fi
done

if [ "$CHECKED" -eq 0 ]; then
  printf 'fatal: no pipefail script was examined — the check proved nothing\n' >&2
  exit 2
fi

# --- Positive control ---------------------------------------------------------
#
# A checker that never fires is indistinguishable from a clean tree. Prove the
# pattern is actually detected before trusting a clean result.
CTRL="$(mktemp)" || { printf 'fatal: could not create a control file\n' >&2; exit 2; }
trap 'rm -f "$CTRL"' EXIT
{
  echo '#!/usr/bin/env bash'
  echo 'set -uo pipefail'
  # shellcheck disable=SC2016  # the control is a literal bad-pattern sample
  echo 'if printf "%s" "$x" | grep -q needle; then echo yes; fi'
} > "$CTRL"
if grep -qE "$COND_PIPE" "$CTRL"; then
  CONTROL="ok"
else
  CONTROL="BROKEN"
fi

echo
printf '%d pipefail script(s) checked, %d violation(s); positive control: %s\n' \
  "$CHECKED" "$VIOLATIONS" "$CONTROL"

if [ "$CONTROL" != "ok" ]; then
  printf 'FAIL: the detector did not fire on a known-bad control — a clean result here means nothing.\n'
  exit 1
fi
if [ "$VIOLATIONS" -gt 0 ]; then
  printf 'FAIL: replace each pipeline above with a herestring, a direct file argument,\n'
  printf '      or a captured variable. See the header of this script.\n'
  exit 1
fi
echo "PASS: no short-circuiting pipeline decides a condition in a pipefail script."
exit 0
