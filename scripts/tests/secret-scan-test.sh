#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
#
# secret-scan-test.sh — positive and negative controls for
# scripts/secret-scan.sh.
#
# A secret scanner is only as good as the last time someone proved it fires. A
# clean report from a scanner that silently matches nothing is worse than no
# scanner at all, because it is believed.
#
# Each case builds a throwaway git repository, stages a known input, and
# asserts the verdict. Nothing here touches the real repository.
#
# THE CASE THAT MATTERS MOST
#
# "private key in a LARGE file" is not padding. Before the herestring fix, the
# scanner used `printf '%s' "$c" | grep -qE -- "$PRIV_RE"`. Under pipefail that
# pipeline is a race: grep -q matched the marker at the head of the content and
# exited, printf took SIGPIPE, and the pipeline reported 141 — so the scanner
# concluded there was no private key. Measured at 200 misses out of 200 for a
# 1 MB file. Small files hid it, because the producer finished writing into the
# 64 KB pipe buffer before grep could exit.
#
# Usage: scripts/tests/secret-scan-test.sh
# Exit status: 0 when every case passes.

set -uo pipefail

TESTS=0; FAILURES=0
pass() { printf '\033[32mok\033[0m   %s\n' "$1"; TESTS=$((TESTS + 1)); }
fail() { printf '\033[31mFAIL\033[0m %s\n' "$1"; printf '       %s\n' "$2"
         TESTS=$((TESTS + 1)); FAILURES=$((FAILURES + 1)); }

SRC_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)" || exit 2
REPO="$(cd -- "$SRC_DIR/../.." >/dev/null 2>&1 && pwd -P)" || exit 2
SCANNER="$REPO/scripts/secret-scan.sh"
[ -f "$SCANNER" ] || { printf 'fatal: scanner not found: %s\n' "$SCANNER" >&2; exit 2; }

command -v git >/dev/null 2>&1 || { printf 'fatal: git is required\n' >&2; exit 2; }

ROOT="$(mktemp -d)" || exit 2
trap 'rm -rf "$ROOT"' EXIT

# Markers are assembled from fragments so this test file never contains a
# string its own subject would flag.
BEGIN_MARK="-----BEGIN "
PRIV_MARKER="${BEGIN_MARK}OPENSSH PRIVATE KEY-----"
CERT_MARKER="${BEGIN_MARK}CERTIFICATE-----"

# new_case <name> — a fresh repository with the scanner in place.
new_case() {
  CASE="$ROOT/$1"
  rm -rf "$CASE"
  mkdir -p "$CASE/scripts"
  cp "$SCANNER" "$CASE/scripts/secret-scan.sh"
  git -C "$CASE" init -q
  git -C "$CASE" config user.email t@example.invalid
  git -C "$CASE" config user.name  t
  git -C "$CASE" add -A >/dev/null 2>&1
}

# run_scan <mode> — capture the scanner's output and status.
run_scan() {
  OUT="$( cd "$CASE" && bash scripts/secret-scan.sh "$1" 2>&1 )"
  RC=$?
  return 0
}

expect_detect() { # label
  if [ "$RC" -eq 1 ]; then pass "$1"
  else fail "$1" "expected exit 1 (findings), got $RC. Output: $(tr '\n' '|' <<<"$OUT")"; fi
}
expect_clean() { # label
  if [ "$RC" -eq 0 ]; then pass "$1"
  else fail "$1" "expected exit 0 (clean), got $RC. Output: $(tr '\n' '|' <<<"$OUT")"; fi
}

echo "== secret-scan.sh controls =="
echo

# --- 1. Private key, small file ------------------------------------------------
echo "-- private key material --"
new_case small-key
printf '%s\nabc\n' "$PRIV_MARKER" > "$CASE/notes.txt"
git -C "$CASE" add -f notes.txt >/dev/null 2>&1
run_scan --staged
expect_detect "a private key in a small file is detected"

# --- 2. Private key, LARGE file -- the regression that mattered ----------------
new_case large-key
{
  printf '%s\n' "$PRIV_MARKER"
  # ~1 MB of filler after the marker, so a short-circuiting consumer would exit
  # long before the producer finished.
  head -c 1000000 /dev/zero | tr '\0' 'A'
  printf '\n'
} > "$CASE/big.txt"
git -C "$CASE" add -f big.txt >/dev/null 2>&1
run_scan --staged
expect_detect "a private key at the head of a 1 MB file is detected (SIGPIPE regression)"

# --- 3. Certificate body -------------------------------------------------------
new_case cert
printf '%s\nMIIB\n' "$CERT_MARKER" > "$CASE/ca.txt"
git -C "$CASE" add -f ca.txt >/dev/null 2>&1
run_scan --staged
expect_detect "a certificate body is detected"

# --- 4. Forbidden paths --------------------------------------------------------
echo
echo "-- forbidden paths --"
for p in "secrets/thing.txt" "keys/x.txt" "state/db.txt" "logs/a.txt" "a.pem" "b.key" ".env"; do
  new_case "path-$(tr -d '/.' <<<"$p")"
  mkdir -p "$CASE/$(dirname "$p")"
  printf 'placeholder\n' > "$CASE/$p"
  git -C "$CASE" add -f "$p" >/dev/null 2>&1
  run_scan --staged
  expect_detect "forbidden path is refused: $p"
done

# --- 5. High-signal credential tokens ------------------------------------------
echo
echo "-- credential tokens --"
new_case tokens
# Assembled from fragments: this test's own source must not contain a literal a
# scanner would match.
{
  printf 'aws = "%s%s%s"\n' 'AKIA' 'Z3QP7XW2' 'MNVK4TBD'
  printf 'gh  = "%s%s"\n'   'ghp_' 'Xk3mQ9zR7vT2bN8wL5jH4gF6dS1aP0cE9uY'
} > "$CASE/creds.txt"
git -C "$CASE" add -f creds.txt >/dev/null 2>&1
run_scan --staged
expect_detect "credential tokens are detected"

# --- 6. Credential literal vs placeholder --------------------------------------
echo
echo "-- assigned literals --"
new_case literal
# Assembled at runtime: this test file must not itself contain a literal its
# own subject would flag. Both scanners caught the first draft, which did.
printf 'password = "%s%s"\n' 'T9x2Lq7Z' 'vB4nKw8s' > "$CASE/conf.txt"
git -C "$CASE" add -f conf.txt >/dev/null 2>&1
run_scan --staged
expect_detect "an assigned credential literal is detected"

new_case placeholder
printf 'password = "changeme"\npassword = "[REDACTED]"\n' > "$CASE/conf.txt"
git -C "$CASE" add -f conf.txt >/dev/null 2>&1
run_scan --staged
expect_clean "documented placeholders are not flagged"

# --- 7. Public key fixture is allowed ------------------------------------------
echo
echo "-- allowed fixtures --"
new_case pubkey
mkdir -p "$CASE/testdata"
printf 'AAAAC3NzaC1lZDI1NTE5AAAAI\n' > "$CASE/testdata/feed_trust_key.pub"
git -C "$CASE" add -f testdata/feed_trust_key.pub >/dev/null 2>&1
run_scan --staged
expect_clean "an Ed25519 public key fixture under testdata/ is allowed"

# --- 8. A clean tree is clean --------------------------------------------------
new_case clean
printf 'package main\n\nfunc main() {}\n' > "$CASE/main.go"
git -C "$CASE" add -f main.go >/dev/null 2>&1
run_scan --staged
expect_clean "ordinary source is clean"

# --- 9. Modes -------------------------------------------------------------------
echo
echo "-- modes --"
new_case tree-mode
printf '%s\n' "$PRIV_MARKER" > "$CASE/k.txt"
git -C "$CASE" add -f k.txt >/dev/null 2>&1
git -C "$CASE" -c commit.gpgsign=false commit -qm x >/dev/null 2>&1
run_scan --tree
expect_detect "--tree inspects committed content"

new_case bad-arg
OUT="$( cd "$CASE" && bash scripts/secret-scan.sh --nonsense 2>&1 )"; RC=$?
if [ "$RC" -eq 2 ]; then pass "an unknown argument is a usage error, not a clean result"
else fail "an unknown argument is a usage error, not a clean result" "got $RC"; fi

echo
echo "=============================================="
printf '%d tests, %d failed\n' "$TESTS" "$FAILURES"
[ "$FAILURES" -eq 0 ] || exit 1
echo "all secret-scan controls passed"
