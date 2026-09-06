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
#
# Output goes to a mktemp file rather than /tmp/gate.$$. A PID-derived name in a
# world-writable directory is predictable, so another local user can pre-create
# it as a symlink and redirect this write. mktemp with O_EXCL cannot be
# hijacked that way.
require() {
  local label="$1" tool="$2"; shift 2
  if ! have "$tool"; then blocked "$label" "$tool not installed"; return; fi
  local out
  out="$(mktemp)" || { blocked "$label" "could not create a temporary file"; return; }
  if "$@" >"$out" 2>&1; then
    ok "$label"
  else
    bad "$label"
    sed 's/^/         /' "$out" | head -25
  fi
  rm -f "$out"
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
  elif grep -q "\"${GOV}\"" <<<"$SUPPORTED_JSON"; then
    ok "toolchain $GOV is a currently supported release"
  else
    MAJOR="$(printf '%s' "$GOV" | cut -d. -f1,2)"
    if grep -q "\"${MAJOR}\." <<<"$SUPPORTED_JSON"; then
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
# --severity=style is the strictest level ShellCheck offers. Findings are fixed
# rather than silenced; the handful of inline `disable=` directives in this tree
# each carry a written reason on the line above.
mapfile -t SHELL_FILES < <(git ls-files '*.sh')
if [ "${#SHELL_FILES[@]}" -eq 0 ]; then
  blocked "shellcheck (all scripts)" "no shell scripts are tracked — nothing would be analysed"
else
  require "shellcheck (all scripts)" shellcheck \
    shellcheck --severity=style --shell=bash "${SHELL_FILES[@]}"
fi
# The vulnerability gate decides from RESULT CONTENT, not from exit status.
# `govulncheck -format json` exits 0 even when it has findings, so a gate that
# trusted the status would report a vulnerable dependency set as clean.
# scripts/govulncheck-gate.sh parses the stream and treats an unparseable
# result as UNPROVEN rather than as a pass. Its own --self-test proves it fails
# on a findings-present stream.
require "govulncheck self-test"       bash          bash ./scripts/govulncheck-gate.sh --self-test
require "govulncheck (by content)"    govulncheck   bash ./scripts/govulncheck-gate.sh

echo
echo "-- repository hygiene --"
# Two secret scanners, deliberately. The project scanner knows ScamWall (which
# paths must never be tracked, that the Pi-hole password lives at a fixed
# location, that a certificate body means the private CA leaked). The
# independent detector knows the world's credential formats. Neither is a
# superset of the other, so both are required.
require "secret scan (tree)"          bash ./scripts/secret-scan.sh --tree
require "secret scan controls"        bash ./scripts/tests/secret-scan-test.sh
require "independent secret scan self-test" gitleaks bash ./scripts/independent-secret-scan.sh --self-test
require "independent secret scan"     gitleaks bash ./scripts/independent-secret-scan.sh
require "container security (static)" bash ./scripts/container-security-check.sh --static
# A short-circuiting consumer at the end of a pipeline cannot be allowed to
# decide a condition in a pipefail script: grep -q exits on the first match, the
# producer takes SIGPIPE, and the pipeline reports 141 — turning a match into a
# non-match. It produced a 100% false-clean in the secret scanner for files over
# the pipe buffer, and a silent false PASS in a regression test.
require "no SIGPIPE-decided conditions" bash ./scripts/tests/pipefail-sigpipe-test.sh

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
echo "-- runtime verifier regression tests --"
# The runtime verifier's failure modes are all FALSE PASSES, which by
# definition do not announce themselves. These tests drive it against a
# scripted fake Docker so each one is reproduced deliberately, and they need
# no daemon — so they run here, as the service account, on every gate run.
require "runtime-verify regression tests" bash ./scripts/tests/runtime-verify-test.sh

echo
echo "-- container runtime (operator-executed, needs daemon) --"
# Runtime verification is a separate program: it needs the daemon and has no
# git dependency, so the operator can run it as root in this user-owned
# repository without a safe.directory exception.
#
# When the daemon is unreachable it is BLOCKED, never skipped: the exit status
# of this suite must not suggest the image was verified when it was not.
if have docker && docker info >/dev/null 2>&1; then
  require "docker build"        docker docker build -f container/Dockerfile -t scamwall:local .
  require "container runtime verification" bash ./scripts/container-runtime-verify.sh
else
  blocked "docker build"                    "docker daemon not reachable by $(id -un)"
  blocked "container runtime verification"  "docker daemon not reachable by $(id -un) — run scripts/container-runtime-verify.sh as the operator"
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
