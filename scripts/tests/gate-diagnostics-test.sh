#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
#
# gate-diagnostics-test.sh — regression tests for FINDING-23.
#
# The defect these cover was a LOST DIAGNOSIS, not a false pass: scripts/check.sh
# recorded the right verdict and then printed the wrong twenty-five lines of the
# capture, so a red run could not be explained from its own log. The first
# hosted CI run (docs/VERIFICATION.md §3.8) failed exactly that way.
#
# The fix moves failure reporting into scripts/gate-diagnostics.sh, which
# sanitizes before printing. That introduces a second, opposite risk — printing
# MORE of an untrusted capture — so half of these cases are decoys that must not
# appear in the report.
#
# `require` is lifted out of scripts/check.sh and driven directly, rather than
# by running the whole suite: the properties under test are "the status is
# preserved", "the verdict is right" and "the diagnosis is visible", and running
# `go test -race` first would prove none of them.
#
# Exit status: 0 when every case passes.

set -uo pipefail

TESTS=0; FAILURES=0
pass() { printf '\033[32mok\033[0m   %s\n' "$1"; TESTS=$((TESTS + 1)); }
fail() { printf '\033[31mFAIL\033[0m %s\n' "$1"; printf '       %s\n' "$2"; TESTS=$((TESTS + 1)); FAILURES=$((FAILURES + 1)); }

SRC_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)" || exit 2
REPO_ROOT="$(cd -- "$SRC_DIR/../.." >/dev/null 2>&1 && pwd -P)" || exit 2
CHECK="$REPO_ROOT/scripts/check.sh"
GATE_DIAG="$REPO_ROOT/scripts/gate-diagnostics.sh"
for f in "$CHECK" "$GATE_DIAG"; do
  [ -f "$f" ] || { printf 'fatal: not found: %s\n' "$f" >&2; exit 2; }
done

ROOT="$(mktemp -d)" || exit 2
trap 'rm -rf -- "$ROOT"' EXIT

# The reporter's environment is CLEARED before any case runs, and each case that
# needs one supplies its own. Without this the suite inherits the caller's
# SCAMWALL_GATE_DIAG_DIR — in CI, the directory whose contents are uploaded as
# the run's diagnostics — and every synthetic fixture below would be published
# alongside the real captures. A file named `progressive-gate.log` containing
# "compose create failed" sitting in a CI artifact is worse than no artifact.
unset SCAMWALL_GATE_DIAG_DIR SCAMWALL_GATE_MAX_LINES

# --- The subject under test ---------------------------------------------------
#
# The reporting machinery is taken from check.sh verbatim. If check.sh's
# definitions move or are renamed, these evals produce nothing and the cases
# below fail loudly rather than silently testing a stale copy — which is why
# each extraction is asserted.
extract() { # <sed-range> <name>
  local text
  text="$(sed -n "$1" "$CHECK")"
  [ -n "$text" ] || { printf 'fatal: could not extract %s from check.sh\n' "$2" >&2; exit 2; }
  printf '%s\n' "$text"
}
PASS=0; FAIL=0; BLOCKED=0
eval "$(extract '/^ok()/p'              'ok')"
eval "$(extract '/^bad()/p'             'bad')"
eval "$(extract '/^blocked()/p'         'blocked')"
eval "$(extract '/^have()/p'            'have')"
eval "$(extract '/^report_failure()/,/^}$/p' 'report_failure')"
eval "$(extract '/^require()/,/^}$/p'   'require')"

# run_require <tool> <command...> — drives the extracted require() and captures
# both the printed report and the resulting counters.
#
# The output is REDIRECTED to a file rather than captured with `$( )`. Command
# substitution runs its body in a subshell, so require()'s increments to PASS,
# FAIL and BLOCKED would be discarded — and every counter assertion below would
# read 0 and be satisfied for the wrong reason. That is the same class of defect
# these tests exist to catch, so it is not permitted in the harness either.
CAPTURE="$ROOT/require-output.txt"
run_require() {
  PASS=0; FAIL=0; BLOCKED=0
  require "$LABEL" "$1" "$@" > "$CAPTURE" 2>&1
  OUT="$(cat "$CAPTURE")"
  return 0
}
# run_require_capped <diag-dir> <max-lines|-> <tool> <command...>
#
# Same, with the reporter's two environment inputs set for one call only. They
# are exported and unset around the call rather than prefixed to it, because a
# `VAR=x require ...` prefix is not permitted on a shell function invocation
# without also making the call a subshell.
run_require_capped() {
  local dir="$1" max="$2"; shift 2
  PASS=0; FAIL=0; BLOCKED=0
  export SCAMWALL_GATE_DIAG_DIR="$dir"
  [ "$max" = "-" ] || export SCAMWALL_GATE_MAX_LINES="$max"
  require "$LABEL" "$1" "$@" > "$CAPTURE" 2>&1
  unset SCAMWALL_GATE_DIAG_DIR SCAMWALL_GATE_MAX_LINES
  OUT="$(cat "$CAPTURE")"
  return 0
}

has()   { grep -qE -- "$2" <<<"$1"; }
expect_has() { # label haystack pattern
  if has "$2" "$3"; then pass "$1"; else fail "$1" "no match for /$3/ in: $(tr '\n' '|' <<<"$2" | cut -c1-400)"; fi
}
expect_lacks() { # label haystack pattern
  if has "$2" "$3"; then fail "$1" "unexpected match for /$3/"; else pass "$1"; fi
}
expect_eq() { # label actual expected
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected '$3', got '$2'"; fi
}

echo "== gate reporting regression tests (FINDING-23) =="
echo

# --- 1. A failure below the first 25 lines is still reported -------------------
#
# The exact shape that defeated the superseded reporter: a progressive reporter
# whose PASS lines come first and whose failure, cleanup result and verdict come
# last. Forty leading PASS lines is well past the old cut of twenty-five.
PROGRESSIVE="$ROOT/progressive.sh"
cat > "$PROGRESSIVE" <<'GATE_EOF'
#!/usr/bin/env bash
for i in $(seq 1 40); do printf 'PASS    prerequisite %s\n' "$i"; done
printf 'FAIL    compose create failed - container assertions UNPROVEN\n'
printf 'FAIL    cleanup INCOMPLETE - 1 problem(s). Remaining resources:\n'
printf '          container dec222222222 (removal failed)\n'
printf '\n40 passed, 2 failed, 0 blocked, 1 cleanup problem(s)\n'
printf 'RESULT: runtime verification INCOMPLETE - required checks failed or could not run.\n'
exit 1
GATE_EOF
chmod +x "$PROGRESSIVE"

LABEL="progressive gate"
run_require bash "$PROGRESSIVE"
expect_has   "the failure below line 25 is visible"      "$OUT" 'compose create failed'
expect_has   "the verdict line is visible"               "$OUT" 'RESULT: runtime verification INCOMPLETE'
expect_has   "the cleanup failure is visible"            "$OUT" 'cleanup INCOMPLETE'
expect_has   "the leftover resource is named"            "$OUT" 'dec222222222'
expect_eq    "the gate is recorded as failed"            "$FAIL" 1
expect_eq    "the gate is not recorded as passed"        "$PASS" 0
expect_eq    "the gate is not recorded as blocked"       "$BLOCKED" 0

# PRE-FIX CONTROL. The superseded reporter is applied to the same output and
# asserted to exhibit the defect. Without it, the cases above prove only that
# the current code agrees with itself.
PREFIX_OUT="$(bash "$PROGRESSIVE" 2>&1 | sed 's/^/         /' | head -25)"
expect_lacks "PRE-FIX CONTROL: head -25 hid the failure"  "$PREFIX_OUT" 'compose create failed'
expect_lacks "PRE-FIX CONTROL: head -25 hid the verdict"  "$PREFIX_OUT" 'RESULT:'
expect_lacks "PRE-FIX CONTROL: head -25 hid the cleanup"  "$PREFIX_OUT" 'cleanup INCOMPLETE'

# --- 2. The original nonzero status is preserved and reported ------------------
#
# The superseded form used the status only as an `if` condition and discarded
# it, so a gate that exited 2 (a tool that could not run) was indistinguishable
# in the log from one that exited 1 (a check that failed).
for want in 1 2 7 42; do
  STATUS_GATE="$ROOT/status-$want.sh"
  printf '#!/usr/bin/env bash\nprintf "boom\\n"\nexit %s\n' "$want" > "$STATUS_GATE"
  chmod +x "$STATUS_GATE"
  LABEL="status gate $want"
  run_require bash "$STATUS_GATE"
  expect_has "exit status $want is reported verbatim" "$OUT" "exit status $want"
  expect_eq  "exit status $want is recorded as a failure" "$FAIL" 1
done

# A gate that exits 0 is still a pass, and prints no diagnosis at all.
ZERO_GATE="$ROOT/zero.sh"
printf '#!/usr/bin/env bash\nprintf "quiet success\\n"\nexit 0\n' > "$ZERO_GATE"
chmod +x "$ZERO_GATE"
LABEL="zero gate"
run_require bash "$ZERO_GATE"
expect_eq    "a successful gate is recorded as passed"  "$PASS" 1
expect_eq    "a successful gate is not recorded failed" "$FAIL" 0
expect_lacks "a successful gate prints no diagnosis"    "$OUT" 'why it failed'

# --- 3. Large output does not create a false pass -----------------------------
#
# Two ways this could go wrong, and both are asserted: the verdict could be
# taken from the reporter rather than the command, and a capture larger than the
# inline cap could be dropped so that nothing indicates a failure at all.
BIG_GATE="$ROOT/big.sh"
cat > "$BIG_GATE" <<'GATE_EOF'
#!/usr/bin/env bash
for i in $(seq 1 5000); do printf 'noise line %s\n' "$i"; done
printf 'FAIL    the real problem is at the very end\n'
printf 'RESULT: INCOMPLETE\n'
exit 1
GATE_EOF
chmod +x "$BIG_GATE"

LABEL="big gate"
DIAG_DIR="$ROOT/diag-big"
run_require_capped "$DIAG_DIR" 120 bash "$BIG_GATE"
expect_eq    "5000 lines of output still fail the gate"   "$FAIL" 1
expect_eq    "5000 lines of output do not pass the gate"  "$PASS" 0
expect_has   "the trailing failure survives truncation"   "$OUT" 'the real problem is at the very end'
expect_has   "truncation is stated explicitly"            "$OUT" 'TRUNCATED'
expect_has   "the omitted line count is stated"           "$OUT" '[0-9]+ line\(s\) OMITTED HERE'
expect_has   "the diagnostic artifact path is printed"    "$OUT" 'complete sanitized capture retained at'
if [ -f "$DIAG_DIR/big-gate.log" ]; then
  pass "the omitted material is preserved in an artifact"
  if grep -q 'noise line 2500' "$DIAG_DIR/big-gate.log"; then
    pass "the artifact contains material omitted from the log"
  else
    fail "the artifact contains material omitted from the log" "line 2500 absent"
  fi
  expect_eq "the artifact is not readable by other accounts" "$(stat -c '%a' "$DIAG_DIR/big-gate.log" 2>/dev/null)" "600"
  expect_eq "the diagnostics directory is private"           "$(stat -c '%a' "$DIAG_DIR" 2>/dev/null)" "700"
else
  fail "the omitted material is preserved in an artifact" "no file at $DIAG_DIR/big-gate.log"
fi

# The same volume of output on a SUCCESSFUL gate must remain a pass: the cap is
# a reporting limit, not a verdict.
BIG_OK="$ROOT/big-ok.sh"
cat > "$BIG_OK" <<'GATE_EOF'
#!/usr/bin/env bash
for i in $(seq 1 5000); do printf 'noise line %s\n' "$i"; done
exit 0
GATE_EOF
chmod +x "$BIG_OK"
LABEL="big passing gate"
run_require bash "$BIG_OK"
expect_eq "a large successful capture is still a pass" "$PASS" 1

# --- 4. Cleanup failures remain visible and affect the verdict ----------------
#
# scripts/container-runtime-verify.sh forces a nonzero exit when cleanup fails
# even though every check passed (SW-P1-16). That verdict is carried by the LAST
# lines of its output, which is precisely what head-truncation discarded.
CLEANUP_GATE="$ROOT/cleanup.sh"
cat > "$CLEANUP_GATE" <<'GATE_EOF'
#!/usr/bin/env bash
for i in $(seq 1 60); do printf 'PASS    check %s\n' "$i"; done
printf '\n== cleanup ==\n'
printf 'FAIL    cleanup INCOMPLETE - 2 problem(s). Remaining resources:\n'
printf '          container abc123456789 (removal failed)\n'
printf '          network   net987654321 (removal failed)\n'
printf '\n60 passed, 0 failed, 0 blocked, 2 cleanup problem(s)\n'
printf 'RESULT: checks passed but REQUIRED CLEANUP FAILED - resources listed above remain.\n'
exit 1
GATE_EOF
chmod +x "$CLEANUP_GATE"

LABEL="cleanup gate"
run_require bash "$CLEANUP_GATE"
expect_eq  "a cleanup-only failure still fails the gate"  "$FAIL" 1
expect_eq  "a cleanup-only failure is not a pass"         "$PASS" 0
expect_has "the cleanup verdict is visible"               "$OUT" 'REQUIRED CLEANUP FAILED'
expect_has "the first leftover resource is named"         "$OUT" 'abc123456789'
expect_has "the second leftover resource is named"        "$OUT" 'net987654321'
expect_lacks "success is not claimed anywhere"            "$OUT" 'all required runtime checks passed'

# The same, with the cleanup report pushed past the inline cap: an artifact is
# not a substitute for the verdict, so the verdict must still be printed inline.
LABEL="cleanup gate capped"
run_require_capped "$ROOT/diag-cleanup" 60 bash "$CLEANUP_GATE"
expect_eq  "a capped cleanup failure still fails the gate" "$FAIL" 1
expect_has "the cleanup verdict survives the cap"          "$OUT" 'REQUIRED CLEANUP FAILED'
expect_has "the leftover resources survive the cap"        "$OUT" 'abc123456789'

# --- 5. Secret decoys are not exposed through the new diagnostics -------------
#
# Printing more of a capture is the risk this fix introduces. Each decoy below
# is a credential SHAPE the gates could plausibly encounter — a mounted password
# file quoted in an error, an API header echoed by a failing client test, a
# private key pasted into a fixture. None may reach the log.
#
# Each marker is ASSEMBLED from parts rather than written as a literal.
# scripts/secret-scan.sh scans this repository for exactly these shapes and
# refuses a commit containing one — correctly, because it cannot tell a decoy
# from the real thing by looking at it. Splitting the marker keeps that scanner
# strict while the bytes the sanitizer sees are identical; the scanner itself
# uses the same device on its own patterns.
GH_PREFIX='ghp'
AKIA_PREFIX='AKIA'
PEM_BEGIN='-----BEGIN'
PEM_END='-----END'
DECOY_GATE="$ROOT/decoy.sh"
cat > "$DECOY_GATE" <<GATE_EOF
#!/usr/bin/env bash
printf 'PASS    ordinary line\n'
printf 'password=hunter2-decoy-value\n'
printf 'PIHOLE_PASSWORD: "%s"\n' 's3cr3t-decoy-value'
printf 'SCAMWALL_SECRET=decoy-secret-material\n'
printf 'Authorization: Bearer AbCdEf0123456789decoytoken\n'
printf 'X-FTL-SID: sid-decoy-0123456789abcdef\n'
printf 'sid=abcdef0123456789decoysession\n'
printf 'api_key = %s%s\n' '${AKIA_PREFIX}' 'IOSFODNN7DECOY1'
printf 'token: ${GH_PREFIX}_0123456789abcdefghijklmnopqrstuvwx\n'
printf -- '${PEM_BEGIN} RSA PRIVATE KEY-----\n'
printf 'MIIEowIBAAKCAQEA0decoydecoydecoydecoydecoydecoydecoydecoydecoydec\n'
printf -- '${PEM_END} RSA PRIVATE KEY-----\n'
printf 'https://admin:hunter2decoyurl@pi.hole/api/auth\n'
printf 'FAIL    the check that actually failed\n'
exit 1
GATE_EOF
chmod +x "$DECOY_GATE"

LABEL="decoy gate"
DIAG_DIR="$ROOT/diag-decoy"
run_require_capped "$DIAG_DIR" - bash "$DECOY_GATE"
expect_eq    "the decoy gate still fails"                    "$FAIL" 1
expect_has   "the real failure is still reported"            "$OUT" 'the check that actually failed'
expect_lacks "a bare password value is not printed"          "$OUT" 'hunter2-decoy-value'
expect_lacks "a quoted password value is not printed"        "$OUT" 's3cr3t-decoy-value'
expect_lacks "a secret assignment is not printed"            "$OUT" 'decoy-secret-material'
expect_lacks "a bearer token is not printed"                 "$OUT" 'AbCdEf0123456789decoytoken'
expect_lacks "an FTL session header is not printed"          "$OUT" 'sid-decoy-0123456789abcdef'
expect_lacks "a session id assignment is not printed"        "$OUT" 'abcdef0123456789decoysession'
expect_lacks "an access key id is not printed"               "$OUT" "${AKIA_PREFIX}IOSFODNN7DECOY1"
expect_lacks "a forge token is not printed"                  "$OUT" "${GH_PREFIX}_0123456789abcdefghijklmnopqrstuvwx"
expect_lacks "private key material is not printed"           "$OUT" 'MIIEowIBAAKCAQEA0decoy'
expect_lacks "URL userinfo is not printed"                   "$OUT" 'hunter2decoyurl'

# The retained artifact is the same sanitized text, not the raw capture: it is
# uploaded from CI, so an unsanitized copy there would defeat the whole point.
if [ -f "$DIAG_DIR/decoy-gate.log" ]; then
  ART="$(cat "$DIAG_DIR/decoy-gate.log")"
  expect_lacks "the retained artifact is sanitized too"      "$ART" 'hunter2-decoy-value|AbCdEf0123456789decoytoken|MIIEowIBAAKCAQEA0decoy'
  expect_eq    "the retained artifact is mode 600"           "$(stat -c '%a' "$DIAG_DIR/decoy-gate.log" 2>/dev/null)" "600"
else
  fail "the retained artifact is sanitized too" "no file at $DIAG_DIR/decoy-gate.log"
fi

# --- 6. Reporting cannot turn a failed gate into a successful one -------------
#
# The reporter is invoked after the verdict is recorded and its status is not
# consulted. Both failure modes are exercised: a reporter that exits nonzero,
# and one that is missing entirely. In each case the gate must stay failed, and
# the missing-reporter case must not fall back to printing an unsanitized
# capture.
BROKEN_DIAG="$ROOT/broken-diag.sh"
printf '#!/usr/bin/env bash\nprintf "reporter exploded\\n" >&2\nexit 9\n' > "$BROKEN_DIAG"
chmod +x "$BROKEN_DIAG"
LABEL="broken reporter gate"
SAVED_DIAG="$GATE_DIAG"
GATE_DIAG="$BROKEN_DIAG"
run_require bash "$PROGRESSIVE"
expect_eq  "a failing reporter leaves the gate failed"    "$FAIL" 1
expect_eq  "a failing reporter does not pass the gate"    "$PASS" 0
expect_has "the reporter failure is stated"               "$OUT" 'diagnostics reporter itself failed'

GATE_DIAG="$ROOT/does-not-exist.sh"
LABEL="missing reporter gate"
run_require bash "$DECOY_GATE"
expect_eq    "a missing reporter leaves the gate failed"  "$FAIL" 1
expect_has   "the missing reporter is stated"             "$OUT" 'is missing'
expect_lacks "no unsanitized capture is printed instead"  "$OUT" 'hunter2-decoy-value'
GATE_DIAG="$SAVED_DIAG"

# --- 7. No temporary file is left behind --------------------------------------
BEFORE="$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'scamwall-gate-*' 2>/dev/null | wc -l)"
LABEL="leak check gate"
run_require bash "$PROGRESSIVE"
AFTER="$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'scamwall-gate-*' 2>/dev/null | wc -l)"
expect_eq "reporting leaves no temporary file behind" "$AFTER" "$BEFORE"

echo
printf '%d test(s), %d failure(s)\n' "$TESTS" "$FAILURES"
[ "$FAILURES" -eq 0 ] || exit 1
