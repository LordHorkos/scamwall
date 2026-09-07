#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
#
# gate-diagnostics.sh — report a failing gate's output, safely and completely.
#
# WHY THIS EXISTS
#
# scripts/check.sh used to print a failing gate's capture with `head -25`. That
# keeps the FIRST twenty-five lines. A gate that reports progressively — first
# its prerequisites, then its assertions, then its cleanup, then its verdict —
# puts everything that succeeded at the top and everything that failed at the
# bottom, so head-truncation discards precisely the diagnosis. It did exactly
# that to the first hosted CI run (docs/VERIFICATION.md §4.9, FINDING-23): the
# log contains twenty-five PASS lines from the runtime verifier and no statement
# of what failed.
#
# The fix is not "print everything". A gate's output is untrusted text that may
# quote a file, a header, or an environment value, and a CI log is public.
# Everything printed here is therefore SANITIZED first, and a capture that
# cannot be sanitized is not printed at all — an unreadable log is recoverable,
# a leaked credential is not.
#
# WHAT IT GUARANTEES
#
#   * The failure reason, the verdict and the cleanup result are printed
#     UNCONDITIONALLY, before any length limit applies, because they are the
#     lines the reader needs and they are always at the end.
#   * The complete sanitized capture follows, inside a collapsible CI group.
#   * If a length limit does apply, the truncation is STATED, both halves are
#     shown, and the omitted material is preserved in a sanitized artifact whose
#     path is printed.
#   * It never changes a verdict. It is called after the gate's status has
#     already been recorded, and its own exit status is not consulted.
#
# USAGE
#   gate-diagnostics.sh --report <label> <status> <capture-file>
#   gate-diagnostics.sh --sanitize            # stdin -> stdout
#   gate-diagnostics.sh --self-test
#
# ENVIRONMENT
#   SCAMWALL_GATE_DIAG_DIR   directory for retained sanitized captures. When
#                            set, every failing gate's full sanitized capture is
#                            written there (this is what CI uploads). When
#                            unset, a directory is created only if a capture is
#                            actually truncated, and its path is printed.
#   SCAMWALL_GATE_MAX_LINES  inline output cap (default 400, minimum 60).
#   GITHUB_ACTIONS           when "true", emits ::group::/::endgroup:: markers.

set -uo pipefail

INDENT='         '
DEFAULT_MAX_LINES=400
MIN_MAX_LINES=60

# --- Sanitization -------------------------------------------------------------
#
# Deny-by-pattern and deliberately blunt: it would rather redact an image digest
# that happens to sit alone on a line than emit a token.
#
# Mostly line-oriented, with ONE stateful rule. Every other rule decides about a
# line by looking only at that line, which is what made the PEM handling wrong:
# the BEGIN and END markers each had their own rule, and the body in between was
# left to the long-opaque-value rule, which requires 40 characters. A PEM body
# wraps at 64 characters, so every line but the last is caught — and the LAST
# line is the remainder, which is routinely shorter than 40. That line survived
# and was printed. It is real key material, so this was a leak and not merely a
# limit (docs/VERIFICATION.md, FINDING-48).
#
# The fix is a range: between a BEGIN marker and its END marker, any line that
# is nothing but base64 is redacted whatever its length. The markers themselves
# contain `-`, so they never match the body pattern and their own rules still
# apply. Two consequences are deliberate:
#
#   * An unterminated block — a capture cut off mid-key — leaves the range open
#     to end of input, so base64-shaped lines after it are redacted too. That is
#     the fail-closed direction, and it costs nothing that matters: the digest
#     lines this program must always show (FAIL, BLOCKED, RESULT:, counts) all
#     contain spaces or punctuation and cannot match a pure-base64 line.
#   * A bare single-word line inside an open block is redacted. Inside a
#     well-formed PEM there are no such lines, and outside one the rule is not
#     active at all.
#
# ANSI escapes are removed as well. They are not a security problem, but a
# digest line that begins with an escape sequence does not match an anchored
# pattern, and the verdict lines this program must always show are coloured.
#
# One `sed` process, no pipeline: a filter whose reader exits early would take
# SIGPIPE and, under `pipefail`, report failure for output it had in fact
# produced. That defect is what scripts/tests/pipefail-sigpipe-test.sh exists to
# prevent, and it is not reintroduced here.
sanitize_stream() { # stdin -> stdout; returns nonzero if sed itself failed
  LC_ALL=C sed -E \
    -e 's/\x1b\[[0-9;]*[a-zA-Z]//g' \
    -e 's/\r$//' \
    -e '/-----BEGIN[[:space:]]*[A-Z0-9 ]*-----/,/-----END[[:space:]]*[A-Z0-9 ]*-----/ s/^[[:space:]]*[A-Za-z0-9+/]+={0,2}[[:space:]]*$/<redacted: PEM body line>/' \
    -e 's/-----BEGIN[[:space:]]+[A-Z0-9 ]*-----.*/<redacted: PEM block>/' \
    -e 's/-----END[[:space:]]+[A-Z0-9 ]*-----//' \
    -e 's#(://)[^[:space:]/@]+:[^[:space:]/@]+@#\1<redacted>@#g' \
    -e 's/([Aa]uthorization|[Pp]roxy-[Aa]uthorization|[Xx]-[Ff][Tt][Ll]-[Ss][Ii][Dd]|[Cc]ookie|[Ss]et-[Cc]ookie)([[:space:]]*:[[:space:]]*).*$/\1\2<redacted>/' \
    -e 's/([Bb]earer|[Bb]asic)[[:space:]]+[A-Za-z0-9._~+/=-]{8,}/\1 <redacted>/g' \
    -e 's/(^|[^A-Za-z0-9])([Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Pp][Aa][Ss][Ss][Ww][Dd]|[Pp][Aa][Ss][Ss][Pp][Hh][Rr][Aa][Ss][Ee]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Tt][Oo][Kk][Ee][Nn]|[Aa][Pp][Ii][_-]?[Kk][Ee][Yy]|[Aa][Cc][Cc][Ee][Ss][Ss][_-]?[Kk][Ee][Yy]|[Ss][Ii][Dd]|[Pp][Ww][Dd])([\"'"'"']?[[:space:]]*[:=][[:space:]]*[\"'"'"']?)[^[:space:],;)"'"'"']+/\1\2\3<redacted>/g' \
    -e 's/^[[:space:]]*[A-Za-z0-9+/]{40,}={0,2}[[:space:]]*$/<redacted: long opaque value>/' \
    -e 's/(gh[pousr]_)[A-Za-z0-9]{16,}/\1<redacted>/g' \
    -e 's/(AKIA)[0-9A-Z]{12,}/\1<redacted>/g'
}

# --- Digest -------------------------------------------------------------------
#
# The lines a reader needs first: what failed, what could not run, what could
# not be cleaned up, and the verdict. These are printed before any cap applies,
# so a length limit can never hide them.
DIGEST_PATTERN='^[[:space:]]*(FAIL|BLOCKED|ERROR|FATAL|fatal|error|panic:|--- FAIL|RESULT:|Error)|cleanup INCOMPLETE|REQUIRED CLEANUP FAILED|UNPROVEN|could not be removed|removal failed|[0-9]+ passed, [0-9]+ failed'
DIGEST_MAX=60

emit() { printf '%s%s\n' "$INDENT" "$1"; }

group_open() {
  if [ "${GITHUB_ACTIONS:-}" = "true" ]; then printf '::group::%s\n' "$1"; fi
}
group_close() {
  if [ "${GITHUB_ACTIONS:-}" = "true" ]; then printf '::endgroup::\n'; fi
}

# diag_dir [create-even-if-unset] -> prints a usable directory, or nothing.
#
# Created with mode 700 and never with a predictable name: a captured gate
# output may quote a path or a hostname, and this directory is the one place it
# is retained on disk.
DIAG_DIR_RESOLVED=""
diag_dir() {
  local force="${1:-0}"
  if [ -n "$DIAG_DIR_RESOLVED" ]; then printf '%s' "$DIAG_DIR_RESOLVED"; return 0; fi
  if [ -n "${SCAMWALL_GATE_DIAG_DIR:-}" ]; then
    # `mkdir -p -m` applies the mode to the DEEPEST component only, so any
    # parent it creates would take the ambient umask. The mode is therefore set
    # afterwards, explicitly, and its failure is fatal: this directory holds
    # captured gate output.
    mkdir -p -- "$SCAMWALL_GATE_DIAG_DIR" 2>/dev/null || return 1
    chmod 700 -- "$SCAMWALL_GATE_DIAG_DIR" 2>/dev/null || return 1
    DIAG_DIR_RESOLVED="$SCAMWALL_GATE_DIAG_DIR"
    printf '%s' "$DIAG_DIR_RESOLVED"; return 0
  fi
  [ "$force" = "1" ] || return 1
  DIAG_DIR_RESOLVED="$(mktemp -d -t scamwall-gate-diag.XXXXXXXX)" || { DIAG_DIR_RESOLVED=""; return 1; }
  chmod 700 -- "$DIAG_DIR_RESOLVED" 2>/dev/null || true
  printf '%s' "$DIAG_DIR_RESOLVED"; return 0
}

# slug <label> -> a filename-safe form. Never derived from untrusted input in a
# way that could escape the directory: everything outside [A-Za-z0-9._-] goes.
slug() {
  local s
  s="$(printf '%s' "$1" | LC_ALL=C tr -c 'A-Za-z0-9._-' '-')"
  s="${s#-}"; s="${s%-}"
  [ -n "$s" ] || s='gate'
  printf '%s' "${s:0:60}"
}

report() { # label status capture-file
  local label="$1" status="$2" capture="$3"
  local clean total shown_head shown_tail omitted max artifact dir rc

  if [ ! -f "$capture" ] || [ ! -r "$capture" ]; then
    emit "the gate's output could not be read (${capture}); no diagnosis is available"
    return 0
  fi

  max="${SCAMWALL_GATE_MAX_LINES:-$DEFAULT_MAX_LINES}"
  case "$max" in
    ''|*[!0-9]*) max="$DEFAULT_MAX_LINES" ;;
  esac
  [ "$max" -ge "$MIN_MAX_LINES" ] || max="$MIN_MAX_LINES"

  clean="$(mktemp -t scamwall-gate-clean.XXXXXXXX)" || {
    emit "a temporary file for the sanitized output could not be created;"
    emit "the raw output is NOT printed, because it has not been sanitized"
    return 0; }
  chmod 600 -- "$clean" 2>/dev/null || true
  # Fail closed. If sanitization did not complete, nothing is printed: an
  # unreadable log can be recovered from a rerun, a leaked credential cannot.
  if ! sanitize_stream < "$capture" > "$clean"; then
    emit "the gate's output could not be sanitized; it is therefore NOT printed"
    emit "(exit status $status was still recorded, and the gate still failed)"
    rm -f -- "$clean"
    return 0
  fi

  total="$(wc -l < "$clean" 2>/dev/null)" || total=0
  total="${total//[[:space:]]/}"
  [ -n "$total" ] || total=0

  # 1. The reason, the verdict and the cleanup result — always, uncapped by the
  #    inline limit, and outside the collapsible group so they are visible
  #    without expanding anything.
  emit "--- why it failed (exit status $status) ---"
  local digest
  digest="$(mktemp -t scamwall-gate-digest.XXXXXXXX)" || digest=""
  if [ -n "$digest" ]; then
    chmod 600 -- "$digest" 2>/dev/null || true
    LC_ALL=C grep -E "$DIGEST_PATTERN" -- "$clean" > "$digest" 2>/dev/null
    rc=$?
    if [ "$rc" -gt 1 ]; then
      emit "(the output could not be searched for failure lines; the full capture follows)"
    elif [ ! -s "$digest" ]; then
      emit "(no line matched a failure or verdict pattern; the full capture follows)"
    else
      local dn
      dn="$(wc -l < "$digest")"; dn="${dn//[[:space:]]/}"
      sed -n "1,${DIGEST_MAX}p" -- "$digest" | while IFS= read -r line; do emit "$line"; done
      if [ "${dn:-0}" -gt "$DIGEST_MAX" ]; then
        emit "... $((dn - DIGEST_MAX)) further failure line(s) appear in the full capture below ..."
      fi
    fi
    rm -f -- "$digest"
  fi

  # 2. The complete sanitized capture, or an explicitly truncated view of it.
  if [ "$total" -le "$max" ]; then
    emit "--- full output ($total line(s), sanitized) ---"
    group_open "gate output: $label"
    while IFS= read -r line; do emit "$line"; done < "$clean"
    group_close
    # An explicitly requested diagnostics directory means the caller intends to
    # retain and publish captures, so retain even an untruncated one.
    if [ -n "${SCAMWALL_GATE_DIAG_DIR:-}" ] && dir="$(diag_dir 0)"; then
      artifact="$dir/$(slug "$label").log"
      if cp -- "$clean" "$artifact" 2>/dev/null; then
        chmod 600 -- "$artifact" 2>/dev/null || true
        emit "sanitized capture retained at: $artifact"
      fi
    fi
  else
    shown_head=$(( max / 3 ))
    shown_tail=$(( max - shown_head ))
    omitted=$(( total - shown_head - shown_tail ))
    artifact=""
    if dir="$(diag_dir 1)"; then
      artifact="$dir/$(slug "$label").log"
      if cp -- "$clean" "$artifact" 2>/dev/null; then
        chmod 600 -- "$artifact" 2>/dev/null || true
      else
        artifact=""
      fi
    fi
    emit "--- full output TRUNCATED: $total line(s) sanitized, showing the first $shown_head and the last $shown_tail ---"
    group_open "gate output (truncated): $label"
    sed -n "1,${shown_head}p" -- "$clean" | while IFS= read -r line; do emit "$line"; done
    if [ -n "$artifact" ]; then
      emit "... $omitted line(s) OMITTED HERE — the complete sanitized capture is at $artifact ..."
    else
      emit "... $omitted line(s) OMITTED HERE — and could NOT be preserved: no diagnostics directory could be created ..."
    fi
    sed -n "$((total - shown_tail + 1)),${total}p" -- "$clean" | while IFS= read -r line; do emit "$line"; done
    group_close
    if [ -n "$artifact" ]; then
      emit "complete sanitized capture retained at: $artifact (mode 600)"
    fi
  fi

  rm -f -- "$clean"
  return 0
}

# --- Self-test ----------------------------------------------------------------
#
# Proves the two properties the rest of the suite depends on: that a failure
# below the old 25-line cut is reported, and that credential-shaped material in
# a gate's output does not reach the log.
self_test() {
  local t rc=0 out dir
  t="$(mktemp -d)" || return 2
  # shellcheck disable=SC2064  # $t must expand now, not at trap time
  trap "rm -rf -- '$t'" EXIT

  st_ok()   { printf 'ok   %s\n' "$1"; }
  st_bad()  { printf 'FAIL %s\n' "$1"; printf '     %s\n' "${2:-}"; rc=1; }
  st_has()  { if grep -qE -- "$2" <<<"$3"; then st_ok "$1"; else st_bad "$1" "missing /$2/"; fi; }
  st_lacks(){ if grep -qE -- "$2" <<<"$3"; then st_bad "$1" "unexpectedly matched /$2/"; else st_ok "$1"; fi; }

  # A capture shaped like the runtime verifier's: many PASS lines, then the
  # failure, the cleanup result and the verdict at the very end.
  {
    for i in $(seq 1 40); do printf '\033[32mPASS\033[0m    check %s\n' "$i"; done
    printf '\033[31mFAIL\033[0m    compose create failed — container assertions UNPROVEN\n'
    printf '\033[31mFAIL\033[0m    cleanup INCOMPLETE — 1 problem(s). Remaining resources:\n'
    printf '          container dec222222222 (removal failed)\n'
    printf '\n41 passed, 2 failed, 0 blocked, 1 cleanup problem(s)\n'
    printf 'RESULT: runtime verification INCOMPLETE — required checks failed or could not run.\n'
  } > "$t/verifier.log"

  unset SCAMWALL_GATE_DIAG_DIR
  out="$(report 'container runtime verification' 1 "$t/verifier.log")"
  st_has   "a failure below the first 25 lines is reported" 'compose create failed' "$out"
  st_has   "the verdict line is reported"                   'RESULT: runtime verification INCOMPLETE' "$out"
  st_has   "the cleanup result is reported"                 'cleanup INCOMPLETE' "$out"
  st_has   "the leftover resource is named"                 'dec222222222' "$out"
  st_has   "the exit status is reported"                    'exit status 1' "$out"
  st_lacks "no ANSI escape survives into the report"        $'\033\\[3' "$out"

  # Credential-shaped decoys must not reach the log.
  #
  # Each marker is ASSEMBLED at run time rather than written as a literal.
  # scripts/secret-scan.sh scans this repository for exactly these shapes and
  # refuses a commit containing one — correctly, since it cannot tell a decoy
  # from the real thing by looking. Splitting the marker keeps that scanner
  # strict while the string the sanitizer actually sees is identical. The same
  # device is used in the scanner itself.
  local pem_begin='-----BEGIN' pem_end='-----END' gh_prefix='ghp' akia_prefix='AKIA'
  {
    printf 'PASS    ordinary line\n'
    printf 'password=hunter2-decoy-value\n'
    printf 'PIHOLE_PASSWORD: "%s"\n' 's3cr3t-decoy-value'
    printf 'Authorization: Bearer AbCdEf0123456789decoy\n'
    printf 'X-FTL-SID: sid-decoy-0123456789abcdef\n'
    printf 'sid=abcdef0123456789decoyvalue\n'
    printf 'api_key = %s%s\n' "$akia_prefix" 'IOSFODNN7DECOY1'
    printf '%s_0123456789abcdefghijklmnopqrstuvwx\n' "$gh_prefix"
    printf -- '%s RSA PRIVATE KEY-----\n' "$pem_begin"
    printf 'MIIEowIBAAKCAQEA0decoydecoydecoydecoydecoydecoydecoydecoydecoydec\n'
    printf 'ZZZZshortTailDecoy09==\n'
    printf -- '%s RSA PRIVATE KEY-----\n' "$pem_end"
    printf 'https://admin:hunter2decoy@pi.hole/api\n'
    printf 'FAIL    something went wrong\n'
  } > "$t/secrets.log"

  out="$(report 'decoy gate' 3 "$t/secrets.log")"
  st_lacks "a password value is not printed"        'hunter2-decoy-value' "$out"
  st_lacks "a quoted password value is not printed" 's3cr3t-decoy-value' "$out"
  st_lacks "a bearer token is not printed"          'AbCdEf0123456789decoy' "$out"
  st_lacks "an FTL session id is not printed"       'sid-decoy-0123456789abcdef' "$out"
  st_lacks "a sid assignment is not printed"        'abcdef0123456789decoyvalue' "$out"
  st_lacks "an access key is not printed"           "${akia_prefix}IOSFODNN7DECOY1" "$out"
  st_lacks "a GitHub token is not printed"          "${gh_prefix}_0123456789abcdefghijklmnopqrstuvwx" "$out"
  st_lacks "private key material is not printed"    'MIIEowIBAAKCAQEA0decoy' "$out"
  # FINDING-48: the line above is 64 characters and was caught by the
  # long-opaque-value rule. A PEM's LAST body line is the remainder of the wrap
  # and is routinely shorter than that rule's 40-character threshold.
  st_lacks "a short final PEM body line is not printed" 'ZZZZshortTailDecoy09' "$out"
  st_lacks "URL userinfo is not printed"            'hunter2decoy' "$out"
  st_has   "the failure itself is still reported"   'something went wrong' "$out"

  # Truncation is explicit and the omitted material is preserved.
  dir="$t/diag"
  : > "$t/big.log"
  for i in $(seq 1 500); do printf 'noise line %s\n' "$i" >> "$t/big.log"; done
  printf 'FAIL    the real problem is at the very end\n' >> "$t/big.log"
  printf 'RESULT: INCOMPLETE\n' >> "$t/big.log"
  out="$(SCAMWALL_GATE_DIAG_DIR="$dir" SCAMWALL_GATE_MAX_LINES=60 report 'big gate' 7 "$t/big.log")"
  st_has   "truncation is stated explicitly"        'TRUNCATED' "$out"
  st_has   "the omitted line count is stated"       '[0-9]+ line\(s\) OMITTED HERE' "$out"
  st_has   "the trailing failure survives"          'the real problem is at the very end' "$out"
  st_has   "the artifact path is printed"           'complete sanitized capture retained at' "$out"
  if [ -f "$dir/big-gate.log" ]; then
    st_ok "the sanitized artifact exists"
    if grep -q 'noise line 250' "$dir/big-gate.log"; then
      st_ok "the artifact contains the omitted material"
    else
      st_bad "the artifact contains the omitted material" "line 250 absent"
    fi
    case "$(stat -c '%a' "$dir/big-gate.log" 2>/dev/null)" in
      600) st_ok "the artifact is not readable by other accounts" ;;
      *)   st_bad "the artifact is not readable by other accounts" "mode $(stat -c '%a' "$dir/big-gate.log" 2>/dev/null)" ;;
    esac
    case "$(stat -c '%a' "$dir" 2>/dev/null)" in
      700) st_ok "the diagnostics directory is private" ;;
      *)   st_bad "the diagnostics directory is private" "mode $(stat -c '%a' "$dir" 2>/dev/null)" ;;
    esac
  else
    st_bad "the sanitized artifact exists" "not found at $dir/big-gate.log"
  fi

  # PRE-FIX CONTROL. The superseded reporter is applied to the same fixture and
  # asserted to exhibit the defect. Without this, the test above proves only
  # that the new code agrees with itself.
  local prefix
  prefix="$(sed 's/^/         /' "$t/verifier.log" | head -25)"
  if grep -q 'compose create failed' <<<"$prefix"; then
    st_bad "PRE-FIX CONTROL: head -25 hides the failure" "the superseded form showed it, so the fixture does not reproduce FINDING-23"
  else
    st_ok "PRE-FIX CONTROL: head -25 hides the failure, the replacement does not"
  fi

  if [ "$rc" -eq 0 ]; then printf '\nall gate-diagnostics self-tests passed\n'
  else printf '\ngate-diagnostics SELF-TEST FAILED\n'; fi
  return "$rc"
}

case "${1:-}" in
  --sanitize)
    sanitize_stream; exit $? ;;
  --self-test)
    self_test; exit $? ;;
  --report)
    shift
    [ "$#" -eq 3 ] || { printf 'usage: %s --report <label> <status> <capture-file>\n' "$0" >&2; exit 2; }
    report "$1" "$2" "$3"; exit 0 ;;
  -h|--help|'')
    sed -n '3,45p' "$0"; exit 0 ;;
  *)
    printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
esac
