#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
#
# check.sh — run every quality gate.
#
# A gate that could not run has proven nothing. Required gates therefore report
# BLOCKED and make the whole run fail, rather than being quietly skipped: a
# green summary that omits half the gates is worse than a red one, because it
# invites someone to believe the work is verified when it is not.
#
# Exit status: 0 only when every REQUIRED gate actually ran and passed.

set -uo pipefail
# Repository root.
#
# `cd "$(git rev-parse ...)" || exit` does NOT guard this: when git is missing
# or this is not a repository, the substitution is empty, and `cd ""` succeeds
# without changing directory. The checker would then run against whatever
# directory it happened to be launched from and report on the wrong tree. Each
# prerequisite is therefore asserted separately, and any failure is fatal.
command -v git >/dev/null 2>&1 || {
  printf 'fatal: git is required and was not found on PATH\n' >&2; exit 2; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  printf 'fatal: not inside a git repository\n' >&2; exit 2; }
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || {
  printf 'fatal: could not determine the repository root\n' >&2; exit 2; }
cd "$REPO_ROOT" || {
  printf 'fatal: could not enter repository root: %s\n' "$REPO_ROOT" >&2; exit 2; }

# Go tools installed with `go install` land in $(go env GOPATH)/bin, which is on
# PATH for an interactive login shell but not for a non-interactive one. Without
# this, staticcheck and govulncheck report BLOCKED ("not installed") on a host
# where they are in fact present — a false blocker, which is exactly the kind of
# unproven-but-plausible result these gates exist to prevent.
if command -v go >/dev/null 2>&1; then
  GOBIN_DIR="$(go env GOBIN)"
  [ -n "$GOBIN_DIR" ] || GOBIN_DIR="$(go env GOPATH)/bin"
  case ":$PATH:" in
    *":$GOBIN_DIR:"*) ;;
    *) PATH="$PATH:$GOBIN_DIR" ;;
  esac
  export PATH
fi

PASS=0; FAIL=0; BLOCKED=0; OPTIONAL_SKIP=0

ok()      { printf '\033[32m  PASS   \033[0m %s\n' "$1"; PASS=$((PASS+1)); }
bad()     { printf '\033[31m  FAIL   \033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
blocked() { printf '\033[31m  BLOCKED\033[0m %s (%s)\n' "$1" "$2"; BLOCKED=$((BLOCKED+1)); }
optskip() { printf '\033[33m  SKIP   \033[0m %s (%s)\n' "$1" "$2"; OPTIONAL_SKIP=$((OPTIONAL_SKIP+1)); }

have() { command -v "$1" >/dev/null 2>&1; }

# require <label> <tool> <command...>
# Runs the command if the tool exists; otherwise records BLOCKED.
require() {
  local label="$1" tool="$2"; shift 2
  if ! have "$tool"; then blocked "$label" "$tool not installed"; return; fi
  if "$@" >/tmp/gate.$$ 2>&1; then ok "$label"; else bad "$label"; sed 's/^/         /' /tmp/gate.$$ | head -25; fi
  rm -f /tmp/gate.$$
}

echo "======================================================"
echo " ScamWall quality gates"
echo "======================================================"

echo
echo "-- toolchain --"
if have go; then
  GOV="$(go version | awk '{print $3}')"
  WANT="$(awk '/^toolchain /{print $2}' go.mod)"
  printf '         go binary: %s | go.mod toolchain: %s\n' "$GOV" "${WANT:-<unset>}"
  if [ -n "$WANT" ] && [ "$GOV" = "$WANT" ]; then
    ok "toolchain matches go.mod"
  else
    bad "toolchain mismatch: running $GOV, go.mod pins ${WANT:-<unset>}"
  fi
  # Verify the toolchain still receives upstream security fixes.
  #
  # The response is captured before matching: piping curl into `grep -q` makes
  # grep exit at the first match, curl take SIGPIPE, and `set -o pipefail` then
  # report the pipeline as failed even though the match succeeded.
  SUPPORTED_JSON="$(curl -sS --max-time 15 'https://go.dev/dl/?mode=json' 2>/dev/null || true)"
  if [ -z "$SUPPORTED_JSON" ]; then
    # Unverifiable is not the same as unsupported. Say so rather than guess.
    blocked "toolchain support status" "could not reach go.dev to verify"
  elif printf '%s' "$SUPPORTED_JSON" | grep -q "\"${GOV}\""; then
    ok "toolchain $GOV is a currently supported release"
  else
    MAJOR="$(printf '%s' "$GOV" | cut -d. -f1,2)"
    if printf '%s' "$SUPPORTED_JSON" | grep -q "\"${MAJOR}\."; then
      ok "toolchain major $MAJOR is supported (running a different patch)"
    else
      bad "toolchain $GOV is NOT in the supported release set (no upstream security fixes)"
    fi
  fi
else
  blocked "toolchain check" "go not installed"
fi

echo
echo "-- go --"
if have go; then
  UNFORMATTED="$(gofmt -l . 2>/dev/null)"
  if [ -z "$UNFORMATTED" ]; then ok "gofmt clean"; else bad "gofmt: $UNFORMATTED"; fi
else
  blocked "gofmt clean" "go not installed"
fi
require "go build ./..."      go go build ./...
require "go vet ./..."        go go vet ./...
require "go test -race ./..." go go test -race -count=1 ./...

echo
echo "-- static analysis --"
require "staticcheck ./..."   staticcheck   staticcheck ./...
require "govulncheck ./..."   govulncheck   govulncheck ./...

echo
echo "-- repository hygiene --"
require "secret scan (tree)"          bash ./scripts/secret-scan.sh --tree
require "container security (static)" bash ./scripts/container-security-check.sh --static

echo
echo "-- compose definition --"
# `docker compose config` parses, interpolates and validates the definition
# entirely client-side; it never contacts the daemon. Gating it behind daemon
# reachability meant a check that CAN always run was reported as BLOCKED on
# every host without socket access, which is most of them.
#
# --env-file is explicit because Compose resolves a bare `.env` against the
# current directory, not against the compose file's directory.
COMPOSE_FILE="deploy/compose/compose.yaml"
COMPOSE_ENV_FILE="deploy/compose/.env"
COMPOSE_ENV=()
[ -f "$COMPOSE_ENV_FILE" ] && COMPOSE_ENV=(--env-file "$COMPOSE_ENV_FILE")
if have docker; then
  require "docker compose config" docker \
    docker compose "${COMPOSE_ENV[@]}" -f "$COMPOSE_FILE" config --quiet
else
  blocked "docker compose config" "docker CLI not installed"
fi

echo
echo "-- container (needs daemon) --"
if have docker && docker info >/dev/null 2>&1; then
  require "docker build"                 docker docker build -f container/Dockerfile -t scamwall:local .
  require "container security (runtime)" bash ./scripts/container-security-check.sh --runtime
else
  blocked "docker build"                 "docker daemon not reachable by $(id -un)"
  blocked "container security (runtime)" "docker daemon not reachable by $(id -un)"
fi

echo
echo "-- working tree --"
DIRTY="$(git status --porcelain)"
if [ -z "$DIRTY" ]; then
  ok "no uncommitted generated artifacts"
else
  printf '%s\n' "$DIRTY" | sed 's/^/         /'
  bad "working tree has uncommitted changes"
fi

echo
echo "======================================================"
printf ' %d passed, %d failed, %d BLOCKED, %d optional-skipped\n' \
  "$PASS" "$FAIL" "$BLOCKED" "$OPTIONAL_SKIP"
if [ "$FAIL" -gt 0 ] || [ "$BLOCKED" -gt 0 ]; then
  echo " RESULT: NOT COMPLETE — required gates failed or could not run."
  echo "======================================================"
  exit 1
fi
echo " RESULT: all required gates passed."
echo "======================================================"
