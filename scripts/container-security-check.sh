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

cd "$(git rev-parse --show-toplevel)" || exit 2

COMPOSE="deploy/compose/compose.yaml"
DOCKERFILE="container/Dockerfile"
IMAGE="${SCAMWALL_IMAGE:-scamwall:local}"

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
require "healthcheck declared"           "grep -q '^HEALTHCHECK' $DOCKERFILE_NC"
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
  if ! docker info >/dev/null 2>&1; then
    echo "docker daemon not reachable; runtime checks skipped" >&2
    echo
    printf '%d passed, %d failed (runtime skipped)\n' "$PASS" "$FAIL"
    [ "$FAIL" -eq 0 ] || exit 1
    exit 0
  fi

  require "image exists"                 "docker image inspect $IMAGE"
  require "image user is 65532:65532"    "[ \"\$(docker image inspect -f '{{.Config.User}}' $IMAGE)\" = '65532:65532' ]"
  require "image declares healthcheck"   "docker image inspect -f '{{.Config.Healthcheck}}' $IMAGE | grep -q scamwall"
  absent  "image exposes no ports"       "docker image inspect -f '{{.Config.ExposedPorts}}' $IMAGE | grep -q ':'"
  absent  "no shell in final image"      "docker run --rm --entrypoint /bin/sh $IMAGE -c 'echo hi'"
  absent  "no busybox in final image"    "docker run --rm --entrypoint /bin/busybox $IMAGE true"

  if docker history --no-trunc --format '{{.CreatedBy}}' "$IMAGE" 2>/dev/null \
       | grep -qiE 'password|BEGIN [A-Z ]*PRIVATE KEY'; then
    bad "no credential material in image history"
  else
    ok "no credential material in image history"
  fi

  CID="$(docker compose -f "$COMPOSE" create --quiet-pull 2>/dev/null | tail -1 || true)"
  if [ -n "${CID:-}" ] && docker inspect "$CID" >/dev/null 2>&1; then
    require "container rootfs read-only"   "[ \"\$(docker inspect -f '{{.HostConfig.ReadonlyRootfs}}' $CID)\" = 'true' ]"
    require "container drops ALL caps"     "docker inspect -f '{{.HostConfig.CapDrop}}' $CID | grep -q ALL"
    require "container not privileged"     "[ \"\$(docker inspect -f '{{.HostConfig.Privileged}}' $CID)\" = 'false' ]"
    require "container no-new-privileges"  "docker inspect -f '{{.HostConfig.SecurityOpt}}' $CID | grep -q no-new-privileges"
    require "container user non-root"      "docker inspect -f '{{.Config.User}}' $CID | grep -q 65532"
    absent  "container publishes no ports" "docker inspect -f '{{.HostConfig.PortBindings}}' $CID | grep -q ':'"
    absent  "container has no docker.sock" "docker inspect -f '{{.HostConfig.Binds}}' $CID | grep -q docker.sock"
    absent  "container not on host network" "docker inspect -f '{{.HostConfig.NetworkMode}}' $CID | grep -qw host"
    docker rm -f "$CID" >/dev/null 2>&1 || true
  else
    echo "could not create a container for inspection; skipping those checks" >&2
  fi
fi

echo
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
