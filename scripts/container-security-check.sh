#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
#
# container-security-check.sh — assert the container security properties that
# docs/SECURITY_BOUNDARIES.md claims.
#
# Modes:
#   --static   inspect the compose definition and Dockerfile only (no daemon)
#   --runtime  additionally inspect a built image and a created container
#
# Static mode is the default: it needs no Docker daemon access, and the
# properties it checks are the ones most easily regressed in review.

set -uo pipefail

MODE="static"
case "${1:-}" in
  ""|--static) MODE="static" ;;
  --runtime)   MODE="runtime" ;;
  -h|--help)   sed -n '3,13p' "$0"; exit 0 ;;
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
IMAGE="${SCAMWALL_IMAGE:-scamwall:local}"

# Site-specific values live in deploy/compose/.env, which is gitignored.
#
# Compose reads `.env` from the CURRENT working directory, and this script runs
# from the repository root — so the file sitting beside the compose definition
# is silently ignored unless named explicitly. That is not cosmetic: without it
# group_add resolves to its 65532 default instead of the site's secret-owning
# GID, and the container inspected here is not the container the operator
# actually deploys.
ENV_FILE="deploy/compose/.env"
COMPOSE_ENV=()
[ -f "$ENV_FILE" ] && COMPOSE_ENV=(--env-file "$ENV_FILE")

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
require "cap_drop includes ALL"          "grep -A2 -E '^[[:space:]]*cap_drop:' $COMPOSE_NC | grep -qE '^[[:space:]]*-[[:space:]]*ALL'"
require "no-new-privileges:true"         "grep -q 'no-new-privileges:true' $COMPOSE_NC"
require "runs as non-root 65532:65532"   "grep -qE '^[[:space:]]*user:[[:space:]]*\"65532:65532\"' $COMPOSE_NC"
require "tmpfs /tmp has noexec"          "grep '/tmp:' $COMPOSE_NC | grep -q noexec"
require "tmpfs /tmp has nosuid"          "grep '/tmp:' $COMPOSE_NC | grep -q nosuid"
require "tmpfs /tmp has nodev"           "grep '/tmp:' $COMPOSE_NC | grep -q nodev"
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
require "trimpath set"                   "grep -q 'trimpath' $DOCKERFILE_NC"
require "buildid stripped"               "grep -q 'buildid=' $DOCKERFILE_NC"
absent  "no secret copied into image"    "grep -qE '^COPY .*(secret|password|\.key|\.pem)' $DOCKERFILE_NC"
absent  "no ADD from a URL"              "grep -qE '^ADD +https?://' $DOCKERFILE_NC"
absent  "no apt-get in final stage"      "awk '/^FROM scratch/,0' $DOCKERFILE_NC | grep -q 'apt-get'"

echo
echo "== build context =="
require ".dockerignore exists"           "[ -f .dockerignore ]"
require ".dockerignore denies by default" "grep -qE '^\*$' .dockerignore"
require ".dockerignore excludes keys/"   "grep -q 'keys/' .dockerignore"
require ".dockerignore excludes secrets/" "grep -q 'secrets/' .dockerignore"
require ".dockerignore excludes .git/"   "grep -q '.git/' .dockerignore"
require ".dockerignore excludes certs"   "grep -qE '\*\.crt|certs/' .dockerignore"

if [ "$MODE" = "runtime" ]; then
  echo
  echo "== runtime =="

  # An inspection that could not run has proven nothing.
  #
  # Every failure in this section is a FAIL, never a skip. --runtime was asked
  # for explicitly, so the caller is entitled to a real answer or a red one; a
  # green summary that quietly omits the runtime assertions is worse than a red
  # one, because it invites someone to believe the image was inspected when it
  # was not.
  #
  # This matters most for the `absent` assertions below: they pass when their
  # command fails, so an unreachable daemon or a missing image would otherwise
  # turn "we could not look" into "we looked and found nothing".
  fatal() {
    bad "$1"
    echo
    printf '%d passed, %d failed\n' "$PASS" "$FAIL"
    exit 1
  }

  docker info >/dev/null 2>&1 \
    || fatal "runtime inspection could run (docker daemon not reachable by $(id -un))"

  docker image inspect "$IMAGE" >/dev/null 2>&1 \
    || fatal "image $IMAGE exists (build it first, or set SCAMWALL_IMAGE)"
  ok "image $IMAGE exists"

  require "image user is 65532:65532"    "[ \"\$(docker image inspect -f '{{.Config.User}}' $IMAGE)\" = '65532:65532' ]"
  absent  "image exposes no ports"       "docker image inspect -f '{{.Config.ExposedPorts}}' $IMAGE | grep -q ':'"

  # Absence of a shell is established by ENUMERATING THE IMAGE FILESYSTEM, not
  # by trying to execute something.
  #
  # The previous approach ran `docker run --entrypoint /bin/sh` and read the
  # exit status. That conflates two different facts. Exit 126 in particular
  # means "found, but could not be executed" — a binary that is present but
  # non-executable for this user, or built for another architecture, would be
  # reported as ABSENT. Exit 127 is likewise the runtime's report, not a
  # filesystem fact, and any other execution failure proves nothing at all.
  #
  # `docker export` streams the container's flattened filesystem, so the
  # question becomes "does this path exist in the image", which is what the
  # security property actually claims. If the enumeration itself fails, the
  # absence assertions are reported as UNPROVEN rather than passing by default.
  IMAGE_FS="$STRIPPED/image-fs.txt"
  FS_CID="$(docker create "$IMAGE" 2>/dev/null | tail -1)"
  if [ -n "${FS_CID:-}" ] && docker export "$FS_CID" 2>/dev/null | tar -t > "$IMAGE_FS" 2>/dev/null && [ -s "$IMAGE_FS" ]; then
    docker rm -f "$FS_CID" >/dev/null 2>&1 || true

    # Sanity anchor: if the listing did not capture the one file the image is
    # known to contain, it is not a trustworthy listing, and every absence
    # assertion derived from it would pass vacuously.
    if grep -qE '^\.?/?usr/local/bin/scamwall$' "$IMAGE_FS"; then
      ok "image filesystem enumerated ($(wc -l < "$IMAGE_FS") entries; scamwall binary present)"

      # absent_path: the path must not exist in the enumerated filesystem.
      absent_path() {
        if grep -qE "$2" "$IMAGE_FS"; then bad "$1"; else ok "$1"; fi
      }
      absent_path "no shell in final image"    '^\.?/?(usr/)?s?bin/(sh|bash|dash|ash|zsh|ksh)$'
      absent_path "no busybox in final image"  '^\.?/?(usr/)?s?bin/busybox$'
      absent_path "no package manager in image" '^\.?/?(usr/)?s?bin/(apt|apt-get|dpkg|apk|yum|dnf|rpm)$'
      absent_path "no libc in final image"     '^\.?/?(usr/)?lib.*/(libc|ld-linux)[-.]'
      absent_path "no /etc/passwd in image"    '^\.?/?etc/passwd$'
    else
      bad "image filesystem enumeration is trustworthy (scamwall binary not found in listing) — shell/busybox absence UNPROVEN"
    fi
  else
    docker rm -f "${FS_CID:-}" >/dev/null 2>&1 || true
    bad "image filesystem could be enumerated (docker create/export failed) — shell/busybox absence UNPROVEN"
  fi

  HISTORY="$(docker history --no-trunc --format '{{.CreatedBy}}' "$IMAGE" 2>&1)"
  if [ -z "$HISTORY" ]; then
    bad "image history could be read (docker history returned nothing)"
  elif printf '%s' "$HISTORY" | grep -qiE 'password|BEGIN [A-Z ]*PRIVATE KEY'; then
    bad "no credential material in image history"
  else
    ok "no credential material in image history"
  fi

  # A container is created (not started) purely so the effective HostConfig can
  # be inspected. Creation failing is itself a finding: it means the deployment
  # definition cannot produce a container on this host, so none of the
  # hardening it declares has been demonstrated.
  CREATE_ERR="$(docker compose "${COMPOSE_ENV[@]}" -f "$COMPOSE" create --no-build --quiet-pull 2>&1)"
  CID="$(docker compose "${COMPOSE_ENV[@]}" -f "$COMPOSE" ps -aq scamwall 2>/dev/null | tail -1)"
  if [ -n "${CID:-}" ] && docker inspect "$CID" >/dev/null 2>&1; then
    ok "container created for inspection"
    require "container rootfs read-only"   "[ \"\$(docker inspect -f '{{.HostConfig.ReadonlyRootfs}}' $CID)\" = 'true' ]"
    require "container drops ALL caps"     "docker inspect -f '{{.HostConfig.CapDrop}}' $CID | grep -q ALL"
    require "container not privileged"     "[ \"\$(docker inspect -f '{{.HostConfig.Privileged}}' $CID)\" = 'false' ]"
    require "container no-new-privileges"  "docker inspect -f '{{.HostConfig.SecurityOpt}}' $CID | grep -q no-new-privileges"
    require "container user non-root"      "docker inspect -f '{{.Config.User}}' $CID | grep -q 65532"
    absent  "container publishes no ports" "docker inspect -f '{{.HostConfig.PortBindings}}' $CID | grep -q ':'"
    absent  "container has no docker.sock" "docker inspect -f '{{.HostConfig.Binds}}' $CID | grep -q docker.sock"
    absent  "container not on host network" "docker inspect -f '{{.HostConfig.NetworkMode}}' $CID | grep -qw host"
    docker compose "${COMPOSE_ENV[@]}" -f "$COMPOSE" rm -fs >/dev/null 2>&1 || docker rm -f "$CID" >/dev/null 2>&1 || true
  else
    bad "container created for inspection ($(printf '%s' "$CREATE_ERR" | tr '\n' ' ' | cut -c1-160))"
  fi
fi

echo
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
