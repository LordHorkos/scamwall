#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
#
# secret-scan.sh — refuse to let credentials, trust material, logs, or runtime
# state reach this PUBLIC repository.
#
# .gitignore is a safety net, not a control: a file added with `git add -f`, or
# a secret pasted into an otherwise-legitimate source file, sails straight past
# it. This script inspects actual content.
#
# Usage:
#   scripts/secret-scan.sh            # scan staged content (pre-commit)
#   scripts/secret-scan.sh --tree     # scan all tracked files
#   scripts/secret-scan.sh --all      # scan tracked + untracked (excl. ignored)
#
# Exit codes: 0 clean, 1 findings, 2 usage/environment error.

set -euo pipefail

MODE="staged"
case "${1:-}" in
  ""|--staged) MODE="staged" ;;
  --tree)      MODE="tree" ;;
  --all)       MODE="all" ;;
  -h|--help)   sed -n '3,17p' "$0"; exit 0 ;;
  *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
esac

command -v git >/dev/null 2>&1 || { echo "git not found" >&2; exit 2; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repository" >&2; exit 2; }
cd "$(git rev-parse --show-toplevel)"

FINDINGS=0
note() { printf '  [%s] %s\n' "$1" "$2"; }
fail() { FINDINGS=$((FINDINGS + 1)); printf '\033[31mFAIL\033[0m %s\n' "$1"; }

# --- Which files are in scope -------------------------------------------------
case "$MODE" in
  staged) mapfile -t FILES < <(git diff --cached --name-only --diff-filter=ACMR) ;;
  tree)   mapfile -t FILES < <(git ls-files) ;;
  all)    mapfile -t FILES < <(git ls-files; git ls-files --others --exclude-standard) ;;
esac

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "secret-scan: nothing to scan (mode: $MODE)"
  exit 0
fi

echo "secret-scan: mode=$MODE files=${#FILES[@]}"

# Read a file's in-scope content: staged blob when staged, worktree otherwise.
content_of() {
  if [ "$MODE" = "staged" ]; then git show ":$1" 2>/dev/null || true
  else cat "$1" 2>/dev/null || true
  fi
}

# --- 1. Forbidden paths -------------------------------------------------------
# These must never be tracked, regardless of content.
PATH_DENY='(^|/)(secrets?|keys?|state|logs|data)/|\.(key|pem|crt|cer|der|p12|pfx|jks|keystore|csr|log|db|sqlite3?|ed25519|priv)$|(^|/)pihole_app_password|(^|/)\.env$|coverage\.(out|html|txt)$|(^|/)\.netrc$'
for f in "${FILES[@]}"; do
  # An Ed25519 *public* key fixture is safe and required as a committed trust anchor.
  case "$f" in testdata/*.pub|testdata/*_public*) continue ;; esac
  if printf '%s' "$f" | grep -qE "$PATH_DENY"; then
    fail "forbidden path staged: $f"
    note "why" "credentials, trust material, logs, or runtime state must never be committed"
  fi
done

# --- 2. Private keys and certificates in content ------------------------------
# Markers are assembled from fragments so this script never matches its own
# source. Whitelisting the scanner would create exactly the blind spot an
# attacker would aim for.
BEGIN_MARK="-----BEGIN "
PRIV_RE="${BEGIN_MARK}[A-Z0-9 ]*PRIVATE KEY-----"
CERT_RE="${BEGIN_MARK}CERTIFICATE-----"
for f in "${FILES[@]}"; do
  c="$(content_of "$f")"
  [ -n "$c" ] || continue
  if printf '%s' "$c" | grep -qE -- "$PRIV_RE"; then
    fail "private key material in $f"
  fi
  if printf '%s' "$c" | grep -qE -- "$CERT_RE"; then
    fail "certificate body in $f"
    note "why" "the Pi-hole CA is installation-specific; test CAs are generated at test time"
  fi
done

# --- 3. High-signal credential tokens -----------------------------------------
# Each pattern is specific enough that a hit is almost certainly a real secret.
declare -a TOKEN_PATTERNS=(
  'gh[pousr]_[A-Za-z0-9]{20,}'                 'GitHub token'
  'github_pat_[A-Za-z0-9_]{20,}'               'GitHub fine-grained PAT'
  'AKIA[0-9A-Z]{16}'                           'AWS access key id'
  'xox[abposr]-[A-Za-z0-9-]{10,}'              'Slack token'
  'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.' 'JWT'
)
for f in "${FILES[@]}"; do
  c="$(content_of "$f")"
  [ -n "$c" ] || continue
  i=0
  while [ $i -lt ${#TOKEN_PATTERNS[@]} ]; do
    pat="${TOKEN_PATTERNS[$i]}"; desc="${TOKEN_PATTERNS[$((i+1))]}"
    if printf '%s' "$c" | grep -qE -- "$pat"; then
      fail "$desc detected in $f"
    fi
    i=$((i + 2))
  done
done

# --- 4. Assigned credential literals ------------------------------------------
# Flags an assignment of a credential-shaped key to a real quoted value, while
# allowing obvious placeholders, field names, struct tags, and redaction
# constants.
ASSIGN='(password|passwd|secret|api[_-]?key|auth[_-]?token|sid|csrf)[[:space:]]*[:=][[:space:]]*"[^"]{6,}"'
PLACEHOLDER='"(\[REDACTED\]|redacted|placeholder|example|changeme|your[_-]|<[^"]*>|\$\{[^"]*\}|test-?(password|secret)|hunter2|xxx+|\*+|dummy|fake|sample|none|null|)"'
for f in "${FILES[@]}"; do
  c="$(content_of "$f")"
  [ -n "$c" ] || continue
  hits="$(printf '%s' "$c" | grep -niE "$ASSIGN" || true)"
  [ -n "$hits" ] || continue
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if printf '%s' "$line" | grep -qiE "$PLACEHOLDER"; then continue; fi
    # Struct tags and JSON schema keys are declarations, not values.
    if printf '%s' "$line" | grep -qE '`json:|`yaml:|"type"[[:space:]]*:|omitempty'; then continue; fi
    fail "possible credential literal in $f"
    note "line" "$(printf '%s' "$line" | cut -c1-100)"
  done <<< "$hits"
done

# --- 5. Site-specific network detail (warning) --------------------------------
# Private addresses are not secrets, but publishing internal topology from a
# named account is avoidable exposure. Documented examples are allowed.
ALLOW_IPS='127\.0\.0\.1|0\.0\.0\.0|172\.17\.0\.1|255\.255|192\.0\.2\.|198\.51\.100\.|203\.0\.113\.'
WARNINGS=0
for f in "${FILES[@]}"; do
  c="$(content_of "$f")"
  [ -n "$c" ] || continue
  ips="$(printf '%s' "$c" \
    | grep -oE '\b(10\.[0-9]{1,3}|192\.168|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]{1,3}\.[0-9]{1,3}\b' \
    | grep -vE "$ALLOW_IPS" || true)"
  if [ -n "$ips" ]; then
    WARNINGS=$((WARNINGS + 1))
    printf '\033[33mWARN\033[0m site-specific private IP in %s: %s\n' \
      "$f" "$(printf '%s' "$ips" | sort -u | tr '\n' ' ')"
  fi
done

# --- Result -------------------------------------------------------------------
echo
if [ "$FINDINGS" -gt 0 ]; then
  printf '\033[31msecret-scan: %d finding(s). Commit refused.\033[0m\n' "$FINDINGS"
  echo "Review with: git diff --cached"
  exit 1
fi
if [ "$WARNINGS" -gt 0 ]; then
  printf '\033[33msecret-scan: clean, %d warning(s) above.\033[0m\n' "$WARNINGS"
else
  echo "secret-scan: clean."
fi
exit 0
