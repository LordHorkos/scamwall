#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
#
# container-security-check.sh — assert, from REPOSITORY CONTENT ALONE, the
# container security properties that docs/SECURITY_BOUNDARIES.md claims.
#
# Scope: the compose definition, the Dockerfile, and the build context. No
# Docker daemon is contacted and no image or container is inspected, so this
# runs as the unprivileged service account and is part of the ordinary gate
# suite.
#
# Runtime verification of a built image and a created container lives in
# scripts/container-runtime-verify.sh. It is operator-executed, needs daemon
# access, and deliberately has no git dependency.

set -uo pipefail

case "${1:-}" in
  ""|--static) ;;
  --runtime)
    # Runtime verification moved to scripts/container-runtime-verify.sh.
    #
    # It is a separate program because it needs the Docker daemon and must NOT
    # need git: the operator runs it as root against a repository owned by the
    # service account, where git refuses with a dubious-ownership error. This
    # script's checks are the opposite — repository content, read via git, run
    # as the service account.
    printf 'runtime verification is no longer part of this script.\n' >&2
    printf 'run the operator-executed verifier instead:\n\n' >&2
    printf '  scripts/container-runtime-verify.sh\n\n' >&2
    printf 'it requires Docker daemon access and does not use git.\n' >&2
    exit 2 ;;
  -h|--help)   sed -n '3,14p' "$0"; exit 0 ;;
  *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
esac

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

COMPOSE="deploy/compose/compose.yaml"
DOCKERFILE="container/Dockerfile"


# Comment-stripped copies.
#
# The definitions deliberately DOCUMENT the settings they omit ("no Docker
# socket is mounted"), so a naive grep over the raw file would flag its own
# explanation as a finding. Absence is therefore checked against directives
# only, with prose removed.
STRIPPED="$(mktemp -d)"
trap 'rm -rf "$STRIPPED"' EXIT
COMPOSE_NC="$STRIPPED/compose.yaml"
DOCKERFILE_NC="$STRIPPED/Dockerfile"
sed 's/#.*$//' "$COMPOSE"    > "$COMPOSE_NC"
sed 's/#.*$//' "$DOCKERFILE" > "$DOCKERFILE_NC"

# Extractions used by more than one assertion are computed ONCE, into variables,
# and matched with herestrings. They are deliberately not written as
# `grep ... FILE | grep -q ...`: under `set -o pipefail` the short-circuiting
# `grep -q` exits at the first match, the upstream grep takes SIGPIPE, and the
# pipeline reports 141 — so a satisfied assertion is read as unsatisfied. That
# race was observed in this repository (docs/VERIFICATION.md 4.1).
# These are consumed inside the `eval`-ed assertion strings below, which
# ShellCheck cannot follow. The reference is real; only the analysis is blind.
# shellcheck disable=SC2034  # used via eval in require/absent
CAP_DROP_BLOCK="$(grep -A2 -E '^[[:space:]]*cap_drop:' "$COMPOSE_NC" 2>/dev/null || true)"
# shellcheck disable=SC2034  # used via eval in require/absent
TMPFS_LINES="$(grep '/tmp:' "$COMPOSE_NC" 2>/dev/null || true)"
# shellcheck disable=SC2034  # used via eval in require/absent
FINAL_STAGE="$(awk '/^FROM scratch/,0' "$DOCKERFILE_NC" 2>/dev/null || true)"

PASS=0
FAIL=0
ok()  { printf '\033[32mPASS\033[0m %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '\033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL + 1)); }

# require: the condition MUST hold.
require() { if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }
# absent: the condition must NOT hold.
absent()  { if eval "$2" >/dev/null 2>&1; then bad "$1"; else ok "$1"; fi; }

echo "== compose: required hardening =="
require "read_only: true"                "grep -qE '^[[:space:]]*read_only:[[:space:]]*true' $COMPOSE_NC"
require "privileged: false"              "grep -qE '^[[:space:]]*privileged:[[:space:]]*false' $COMPOSE_NC"
require "init: true"                     "grep -qE '^[[:space:]]*init:[[:space:]]*true' $COMPOSE_NC"
require "cap_drop includes ALL"          "grep -qE '^[[:space:]]*-[[:space:]]*ALL' <<< \"\$CAP_DROP_BLOCK\""
require "no-new-privileges:true"         "grep -q 'no-new-privileges:true' $COMPOSE_NC"
require "runs as non-root 65532:65532"   "grep -qE '^[[:space:]]*user:[[:space:]]*\"65532:65532\"' $COMPOSE_NC"
require "tmpfs /tmp has noexec"          "grep -q noexec <<< \"\$TMPFS_LINES\""
require "tmpfs /tmp has nosuid"          "grep -q nosuid <<< \"\$TMPFS_LINES\""
require "tmpfs /tmp has nodev"           "grep -q nodev <<< \"\$TMPFS_LINES\""
require "memory limit set"               "grep -qE '^[[:space:]]*mem_limit:' $COMPOSE_NC"
require "pids limit set"                 "grep -qE '^[[:space:]]*pids_limit:' $COMPOSE_NC"
require "cpu limit set"                  "grep -qE '^[[:space:]]*cpus:' $COMPOSE_NC"
require "log file size bounded"          "grep -q 'max-size:' $COMPOSE_NC"
require "log file count bounded"         "grep -q 'max-file:' $COMPOSE_NC"
require "restart policy set"             "grep -qE '^[[:space:]]*restart:' $COMPOSE_NC"
require "API hostname pinned"            "grep -q 'pi.hole:' $COMPOSE_NC"
require "secret delivered via secrets"   "grep -q 'pihole_app_password' $COMPOSE_NC"
require "CA mounted read-only"           "grep -q 'pihole-ca.crt' $COMPOSE_NC"

echo
echo "== compose: required absences =="
absent "no published ports"              "grep -qE '^[[:space:]]*ports:' $COMPOSE_NC"
absent "no host networking"              "grep -qE 'network_mode:[[:space:]]*host' $COMPOSE_NC"
absent "no Docker socket mount"          "grep -q 'docker.sock' $COMPOSE_NC"
absent "no /etc/pihole mount"            "grep -q '/etc/pihole' $COMPOSE_NC"
absent "no added capabilities"           "grep -qE '^[[:space:]]*cap_add:' $COMPOSE_NC"
absent "no unconfined seccomp/apparmor"  "grep -qE 'seccomp:unconfined|apparmor:unconfined' $COMPOSE_NC"
absent "no privileged: true"             "grep -qE 'privileged:[[:space:]]*true' $COMPOSE_NC"
absent "no writable rootfs override"     "grep -qE 'read_only:[[:space:]]*false' $COMPOSE_NC"

echo
echo "== Dockerfile =="
require "base image pinned by digest"    "grep -qE '^FROM .*@sha256:[0-9a-f]{64}' $DOCKERFILE_NC"
require "multi-stage build"              "[ \$(grep -cE '^FROM ' $DOCKERFILE_NC) -ge 2 ]"
require "final stage is scratch"         "grep -qE '^FROM scratch' $DOCKERFILE_NC"
require "USER is non-root numeric"       "grep -qE '^USER 65532:65532' $DOCKERFILE_NC"
require "CGO disabled (static binary)"   "grep -q 'CGO_ENABLED=0' $DOCKERFILE_NC"
# CGO_ENABLED=0 is an INTENTION. The proof that the produced binary is actually
# static is a checked ELF inspection of the artifact, which the build runs and
# whose failure fails the build.
require "static linkage proven by ELF inspection" "grep -qE '^RUN .*elfcheck' $DOCKERFILE_NC"
require "the ELF checker exists"         "[ -f internal/buildcheck/elfcheck/main.go ]"
require "the ELF checker has controls"   "[ -f internal/buildcheck/elfcheck/main_test.go ]"
# `! ldd BIN | grep -q '=>'` passed for a static binary, a missing binary, a
# corrupt binary, and a missing ldd alike, and ldd may execute what it inspects.
absent  "no ldd-based linkage assertion" "grep -qE '^RUN .*ldd ' $DOCKERFILE_NC"
absent  "no producer-to-grep -q pipeline" "grep -qE '\| *grep -q' $DOCKERFILE_NC"
require "trimpath set"                   "grep -q 'trimpath' $DOCKERFILE_NC"
require "buildid stripped"               "grep -q 'buildid=' $DOCKERFILE_NC"
absent  "no secret copied into image"    "grep -qE '^COPY .*(secret|password|\.key|\.pem)' $DOCKERFILE_NC"
absent  "no ADD from a URL"              "grep -qE '^ADD +https?://' $DOCKERFILE_NC"
absent  "no apt-get in final stage"      "grep -q 'apt-get' <<< \"\$FINAL_STAGE\""

echo
echo "== build context =="
require ".dockerignore exists"           "[ -f .dockerignore ]"
require ".dockerignore denies by default" "grep -qE '^\*$' .dockerignore"
require ".dockerignore excludes keys/"   "grep -q 'keys/' .dockerignore"
require ".dockerignore excludes secrets/" "grep -q 'secrets/' .dockerignore"
require ".dockerignore excludes .git/"   "grep -q '.git/' .dockerignore"
require ".dockerignore excludes certs"   "grep -qE '\*\.crt|certs/' .dockerignore"

echo
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
