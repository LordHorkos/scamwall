#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
#
# check.sh — run every quality gate.
#
# Each gate reports its own status. A missing tool is reported as SKIPPED, not
# as a pass: a gate that did not run has proven nothing, and recording it as
# green would be worse than not having it.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 2

PASS=0; FAIL=0; SKIP=0
ok()   { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
skip() { printf '\033[33m  SKIP\033[0m %s (%s)\n' "$1" "$2"; SKIP=$((SKIP+1)); }

run() { # run <label> <command...>
  local label="$1"; shift
  printf '\n>> %s\n' "$label"
  if "$@"; then ok "$label"; else bad "$label"; fi
}

have() { command -v "$1" >/dev/null 2>&1; }

echo "=============================================="
echo " ScamWall quality gates"
echo "=============================================="

if have go; then
  printf '\n>> gofmt\n'
  UNFORMATTED="$(gofmt -l . 2>/dev/null)"
  if [ -z "$UNFORMATTED" ]; then ok "gofmt clean"; else bad "gofmt: $UNFORMATTED"; fi

  run "go build"      go build ./...
  run "go vet"        go vet ./...
  run "go test -race" go test -race ./...
else
  skip "gofmt"        "go not installed"
  skip "go build"     "go not installed"
  skip "go vet"       "go not installed"
  skip "go test"      "go not installed"
fi

if have staticcheck; then
  run "staticcheck" staticcheck ./...
else
  skip "staticcheck" "not installed: go install honnef.co/go/tools/cmd/staticcheck@latest"
fi

if have govulncheck; then
  run "govulncheck" govulncheck ./...
else
  skip "govulncheck" "not installed: go install golang.org/x/vuln/cmd/govulncheck@latest"
fi

run "secret scan (tree)"        ./scripts/secret-scan.sh --tree
run "container security static" ./scripts/container-security-check.sh --static

if have docker && docker info >/dev/null 2>&1; then
  run "docker compose config" docker compose -f deploy/compose/compose.yaml config --quiet
  run "docker build"          docker build -f container/Dockerfile -t scamwall:local .
  run "container security runtime" ./scripts/container-security-check.sh --runtime
else
  skip "docker compose config"      "docker daemon not reachable"
  skip "docker build"               "docker daemon not reachable"
  skip "container security runtime" "docker daemon not reachable"
fi

printf '\n>> uncommitted generated artifacts\n'
DIRTY="$(git status --porcelain)"
if [ -z "$DIRTY" ]; then
  ok "working tree clean"
else
  printf '%s\n' "$DIRTY"
  bad "working tree has uncommitted changes"
fi

echo
echo "=============================================="
printf ' %d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
echo "=============================================="
[ "$FAIL" -eq 0 ] || exit 1
