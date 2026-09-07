#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
#
# operator-handoff-test.sh — regression tests for scripts/operator-handoff.sh.
#
# The operator handoff used to be a documentation code block. Nothing executed
# it before an operator did, so its defects were only discoverable by running it
# against the household Pi-hole — which is the one place a defect in it is
# expensive. These tests drive the program against a scripted fake `docker` and
# a scripted fake `git`, so every failure mode below is reproduced deliberately,
# with no daemon, no network, and no appliance.
#
# Each case asserts that a BROKEN world produces a nonzero exit and says why —
# not merely that the program printed something.
#
# Exit status: 0 when every case passes.

set -uo pipefail

TESTS=0; FAILURES=0
pass() { printf '\033[32mok\033[0m   %s\n' "$1"; TESTS=$((TESTS + 1)); }
fail() { printf '\033[31mFAIL\033[0m %s\n' "$1"; printf '       %s\n' "$2"; TESTS=$((TESTS + 1)); FAILURES=$((FAILURES + 1)); }

SRC_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)" || exit 2
REPO="$(cd -- "$SRC_DIR/../.." >/dev/null 2>&1 && pwd -P)" || exit 2
HANDOFF="$REPO/scripts/operator-handoff.sh"
[ -f "$HANDOFF" ] || { printf 'fatal: handoff script not found: %s\n' "$HANDOFF" >&2; exit 2; }

ROOT="$(mktemp -d)" || exit 2
trap 'rm -rf "$ROOT"' EXIT

HEAD_SHA="1111111111111111111111111111111111111111"
OTHER_SHA="2222222222222222222222222222222222222222"
IMAGE_A="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
IMAGE_B="sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
CT_SECRET_PATH="/run/secrets/pihole_app_password"

# --- Synthetic checkout -------------------------------------------------------
#
# The program derives its repository root from its own location, so it is
# copied into a checkout the test controls. The runtime verifier is replaced by
# a stub: it has its own 358-case suite, and what matters here is that its exit
# status and its output reach the handoff's verdict.
CHECKOUT="$ROOT/checkout"
mkdir -p "$CHECKOUT/scripts/lib" "$CHECKOUT/scripts/tests" "$CHECKOUT/container" "$CHECKOUT/deploy/compose"
cp "$HANDOFF" "$CHECKOUT/scripts/operator-handoff.sh"
chmod +x "$CHECKOUT/scripts/operator-handoff.sh"
cp "$REPO/scripts/lib/docker-resources.sh" "$CHECKOUT/scripts/lib/docker-resources.sh"
cp "$REPO/scripts/gate-diagnostics.sh"     "$CHECKOUT/scripts/gate-diagnostics.sh"
cp "$REPO/container/Dockerfile"            "$CHECKOUT/container/Dockerfile"
cp "$REPO/deploy/compose/compose.yaml"     "$CHECKOUT/deploy/compose/compose.yaml"
printf 'SCAMWALL_SECRET_GID=989\n' > "$CHECKOUT/deploy/compose/.env"

cat > "$CHECKOUT/scripts/container-runtime-verify.sh" <<'STUB_EOF'
#!/usr/bin/env bash
# Stub standing in for the real runtime verifier, which has its own suite.
printf 'SCAMWALL_IMAGE=%s\n' "${SCAMWALL_IMAGE:-unset}"
printf 'SCAMWALL_EXPECTED_IMAGE_ID=%s\n' "${SCAMWALL_EXPECTED_IMAGE_ID:-unset}"
cat "$FAKE_DIR/verify-output" 2>/dev/null
exit "$(cat "$FAKE_DIR/rc.verify" 2>/dev/null || echo 0)"
STUB_EOF
chmod +x "$CHECKOUT/scripts/container-runtime-verify.sh"

# --- Fake git -----------------------------------------------------------------
#
# It answers only the two questions the handoff asks, and each can be made to
# fail independently — because "git could not tell us" and "the tree is dirty"
# are different facts and the program must not collapse them.
BIN="$ROOT/bin"
mkdir -p "$BIN"
cat > "$BIN/git" <<'GIT_EOF'
#!/usr/bin/env bash
D="$FAKE_DIR"
printf 'git %s\n' "$*" >> "$D/log"
args=("$@")
# Skip a leading -C <dir>.
if [ "${args[0]:-}" = "-C" ]; then args=("${args[@]:2}"); fi
case "${args[0]:-}" in
  rev-parse)
    [ -f "$D/rc.git-rev-parse" ] && exit "$(cat "$D/rc.git-rev-parse")"
    cat "$D/head-sha"
    ;;
  status)
    [ -f "$D/rc.git-status" ] && exit "$(cat "$D/rc.git-status")"
    cat "$D/porcelain" 2>/dev/null
    ;;
  *) exit 1 ;;
esac
exit 0
GIT_EOF
chmod +x "$BIN/git"

# --- Fake docker --------------------------------------------------------------
#
# It models container lifetime rather than replaying canned output: a container
# exists once `create` returns its id and stops existing when `rm` succeeds, so
# "cleanup is idempotent" and "a leftover is reported" are real assertions.
#
# Every created container's full argument list is recorded, which is what lets a
# case assert that a credential was never even offered to a container rather
# than only that the program said so.
cat > "$BIN/docker" <<'DOCKER_EOF'
#!/usr/bin/env bash
D="$FAKE_DIR"
printf '%s\n' "$*" >> "$D/log"

rc_of() { cat "$D/rc.$1" 2>/dev/null || echo 0; }

# `docker compose ...`
if [ "${1:-}" = "compose" ]; then
  for a in "$@"; do
    if [ "$a" = "config" ]; then
      exit_code="$(rc_of compose-config)"
      [ "$exit_code" = "0" ] || { printf 'compose config failed\n' >&2; exit "$exit_code"; }
      cat "$D/compose-config.json"
      exit 0
    fi
  done
  exit 0
fi

case "${1:-}" in
  info) exit "$(rc_of info)" ;;

  build)
    cat "$D/build-output" 2>/dev/null
    # A build that "succeeds" may still have replaced the tag.
    [ -f "$D/image-id-after-build" ] && cp "$D/image-id-after-build" "$D/image-id"
    exit "$(rc_of build)"
    ;;

  image)
    # image inspect -f '{{.Id}}' <ref>
    if [ "${2:-}" = "inspect" ]; then
      if [ -f "$D/image-inspect-calls" ]; then
        n="$(cat "$D/image-inspect-calls")"
      else
        n=0
      fi
      n=$((n + 1)); printf '%s' "$n" > "$D/image-inspect-calls"
      # A tag that moves AFTER the program resolved it: the nth call onwards
      # answers with a different image.
      if [ -f "$D/tag-moves-at" ] && [ "$n" -ge "$(cat "$D/tag-moves-at")" ]; then
        cat "$D/image-id-moved"; exit 0
      fi
      [ -s "$D/image-id" ] || exit 1
      cat "$D/image-id"
      exit 0
    fi
    exit 1
    ;;

  create)
    ec="$(rc_of create)"
    [ "$ec" = "0" ] || { printf 'create refused\n' >&2; exit "$ec"; }
    if [ -f "$D/next-cid" ]; then n="$(cat "$D/next-cid")"; else n=1; fi
    printf '%s' "$((n + 1))" > "$D/next-cid"
    cid="$(printf 'cid%09d' "$n")"
    printf '%s\n' "$*" > "$D/container-$cid.args"
    printf '%s\n' "$cid" >> "$D/live"
    printf '%s\n' "$cid"
    exit 0
    ;;

  start)
    # start -a <cid>
    cid="${*: -1}"
    # A deliberate interruption, delivered at the one moment a container
    # exists and cleanup has something real to do.
    if [ -f "$D/interrupt" ]; then
      kill -TERM "$PPID" 2>/dev/null
      sleep 5
      exit 0
    fi
    args="$(cat "$D/container-$cid.args" 2>/dev/null)"
    case "$args" in
      *" version") out="version-output" ;;
      *"doctor --no-credential") out="doctor-output" ;;
      *"doctor --offline") out="secret-output" ;;
      *" status") out="status-output" ;;
      *) out="version-output" ;;
    esac
    cat "$D/$out" 2>/dev/null
    exit "$(rc_of start)"
    ;;

  inspect)
    # inspect -f <fmt> <id>, or inspect <id> for the ownership check.
    if [ "${2:-}" = "-f" ]; then
      fmt="$3"; id="$4"
      grep -qx "$id" "$D/live" 2>/dev/null || exit 1
      case "$fmt" in
        *".Image"*)
          if [ -f "$D/container-image-mismatch" ]; then cat "$D/container-image-mismatch"
          else cat "$D/image-id"; fi ;;
        *".Mounts"*)
          args="$(cat "$D/container-$id.args" 2>/dev/null)"
          # Report exactly the destinations the create call asked for, plus a
          # forced one when a case is testing the credential boundary.
          printf '%s\n' "$args" | tr ' ' '\n' | sed -n 's/^type=bind,source=[^,]*,target=\([^,]*\),readonly$/\1/p'
          [ -f "$D/force-secret-mount" ] && printf '/run/secrets/pihole_app_password\n'
          ;;
        *"NetworkMode"*)
          if [ -f "$D/force-network-mode" ]; then cat "$D/force-network-mode"
          else
            args="$(cat "$D/container-$id.args" 2>/dev/null)"
            printf '%s\n' "$args" | sed -n 's/.*--network \([^ ]*\).*/\1/p'
          fi ;;
        *) printf '\n' ;;
      esac
      exit 0
    fi
    # `inspect <id>` with no format: the ownership check. The labels come back
    # from what `create` was actually asked for, so attribution is modelled
    # rather than asserted by the fake. A case can override them to simulate a
    # resource that is NOT this invocation's.
    id="${2:-}"
    grep -qx "$id" "$D/live" 2>/dev/null || exit 1
    args="$(cat "$D/container-$id.args" 2>/dev/null)"
    own="$(printf '%s\n' "$args" | sed -n 's/.*--label scamwall\.verify\.invocation=\([^ ]*\).*/\1/p')"
    proj="$(printf '%s\n' "$args" | sed -n 's/.*--label com\.docker\.compose\.project=\([^ ]*\).*/\1/p')"
    [ -f "$D/own-label" ]     && own="$(cat "$D/own-label")"
    [ -f "$D/project-label" ] && proj="$(cat "$D/project-label")"
    printf '[{"Config":{"Labels":{"scamwall.verify.invocation":"%s","com.docker.compose.project":"%s"}}}]\n' \
      "$own" "$proj"
    exit 0
    ;;

  ps)
    # ps -aq --no-trunc --filter <selector>
    sel=""
    for ((i=1; i<=$#; i++)); do
      if [ "${!i}" = "--filter" ]; then j=$((i+1)); sel="${!j}"; fi
    done
    case "$sel" in
      label=com.docker.compose.project=*)
        [ "$(rc_of project-query)" = "0" ] || exit 1
        cat "$D/project-containers" 2>/dev/null ;;
      label=*) [ "$(rc_of own-query)" = "0" ] || exit 1 ;;
      id=*) id="${sel#id=}"; grep -qx "$id" "$D/live" 2>/dev/null && printf '%s\n' "$id" ;;
    esac
    exit 0
    ;;

  network|volume)
    sub="${2:-}"
    if [ "$sub" = "ls" ]; then
      sel=""
      for ((i=1; i<=$#; i++)); do
        if [ "${!i}" = "--filter" ]; then j=$((i+1)); sel="${!j}"; fi
      done
      case "$sel" in
        label=com.docker.compose.project=*) [ "$(rc_of project-query)" = "0" ] || exit 1 ;;
        label=*) [ "$(rc_of own-query)" = "0" ] || exit 1 ;;
      esac
      exit 0
    fi
    exit 0
    ;;

  rm)
    ec="$(rc_of rm)"
    [ "$ec" = "0" ] || exit "$ec"
    id="${*: -1}"
    if [ -f "$D/live" ]; then grep -vx "$id" "$D/live" > "$D/live.new" 2>/dev/null; mv "$D/live.new" "$D/live"; fi
    exit 0
    ;;
esac
exit 0
DOCKER_EOF
chmod +x "$BIN/docker"

# --- The resolved deployment configuration ------------------------------------
#
# Shaped as `docker compose config --format json` renders this definition. A
# case that redirects a bind source rewrites it.
COMPOSE_JSON_DEPLOYMENT=$(cat <<'JSON_EOF'
{
  "name": "scamwall",
  "services": {
    "scamwall": {
      "image": "scamwall:local",
      "user": "65532:65532",
      "group_add": ["989"],
      "read_only": true,
      "pids_limit": 64,
      "mem_limit": "134217728",
      "cpus": 0.5,
      "extra_hosts": ["pi.hole=host-gateway"],
      "volumes": [
        {"type":"bind","source":"/etc/scamwall/certs/pihole-ca.crt","target":"/etc/scamwall/certs/pihole-ca.crt","read_only":true,"bind":{"create_host_path":false}},
        {"type":"bind","source":"/opt/scamwall/config.json","target":"/etc/scamwall/config.json","read_only":true,"bind":{"create_host_path":false}},
        {"type":"bind","source":"/opt/scamwall/feed.json","target":"/etc/scamwall/feed.json","read_only":true,"bind":{"create_host_path":false}}
      ]
    }
  },
  "secrets": {
    "pihole_app_password": {"file": "/etc/scamwall/secrets/pihole_app_password"}
  }
}
JSON_EOF
)

# --- Case scaffolding ---------------------------------------------------------
FAKE_DIR=""
WORK=""
setup_case() { # <name>
  FAKE_DIR="$ROOT/fake-$1"
  rm -rf "$FAKE_DIR"; mkdir -p "$FAKE_DIR"
  : > "$FAKE_DIR/log"
  : > "$FAKE_DIR/live"
  printf '%s' "$HEAD_SHA"  > "$FAKE_DIR/head-sha"
  : > "$FAKE_DIR/porcelain"
  printf '%s' "$IMAGE_A"   > "$FAKE_DIR/image-id"
  printf '%s' "$COMPOSE_JSON_DEPLOYMENT" > "$FAKE_DIR/compose-config.json"

  # A build log in BuildKit --progress=plain shape, with both in-build
  # assertion steps executing rather than being reused from cache.
  cat > "$FAKE_DIR/build-output" <<'BUILD_EOF'
#1 [internal] load build definition from Dockerfile
#1 DONE 0.0s
#11 [build 6/8] RUN go run ./internal/buildcheck/elfcheck /out/scamwall
#11 DONE 1.4s
#12 [build 7/8] RUN /out/scamwall version > /out/version.txt       && grep -qE "enforcement compiled in[[:space:]]+false" /out/version.txt
#12 DONE 0.3s
#15 exporting to image
#15 DONE 0.1s
BUILD_EOF

  printf 'scamwall  dev\ncommit    %s\nbuilt     2026-01-01T00:00:00Z\nenforcement compiled in  false\nmode      read-only, dry-run\n' \
    "$HEAD_SHA" > "$FAKE_DIR/version-output"
  printf 'PASS    the application password would be readable by the container identity (uid=65532 gid=989 mode=640)\n' \
    > "$FAKE_DIR/verify-output"
  cat > "$FAKE_DIR/doctor-output" <<'DOC_EOF'
ok    configuration           loaded (dry_run=true)
ok    enforcement absent      not compiled in
SKIP  application password    NOT READ (--no-credential): this run makes no claim about the credential
ok    certificate authority   loaded and parsed: /etc/scamwall/certs/pihole-ca.crt
ok    feed                    signature and manifest valid: /etc/scamwall/feed.json
ok    pi-hole connectivity    reachable over TLS; authentication required

6 checks, 0 failed, 1 skipped
DOC_EOF
  cat > "$FAKE_DIR/secret-output" <<'SEC_EOF'
ok    configuration           loaded (dry_run=true)
ok    enforcement absent      not compiled in
ok    application password    readable
ok    certificate authority   loaded and parsed: /etc/scamwall/certs/pihole-ca.crt
ok    feed                    signature and manifest valid: /etc/scamwall/feed.json

5 checks, 0 failed, 0 skipped
SEC_EOF
  cat > "$FAKE_DIR/status-output" <<'ST_EOF'
component  local   branch  remote
core       v6.0.4  master  v6.0.4

session logout ACCEPTED by Pi-hole
  This records that the DELETE was accepted. It is not independent
  confirmation that the appliance's session table no longer holds it.
ST_EOF

  WORK="$ROOT/work-$1"
  rm -rf "$WORK"
}

OUT=""; RC=0
run_step() { # <args...>
  OUT="$(env -u SCAMWALL_CA_FILE -u SCAMWALL_SECRET_FILE -u SCAMWALL_CONFIG \
             -u SCAMWALL_FEED -u SCAMWALL_IMAGE -u SCAMWALL_EXPECTED_IMAGE_ID \
             -u SCAMWALL_VERSION -u SCAMWALL_COMMIT -u SCAMWALL_BUILD_DATE \
             -u PIHOLE_HOST_IP -u SCAMWALL_SECRET_GID \
             PATH="$BIN:$PATH" FAKE_DIR="$FAKE_DIR" \
             "$CHECKOUT/scripts/operator-handoff.sh" "$@" 2>&1)"
  RC=$?
  return 0
}

# preflight_then <step args...> — the common "get to a later step" path.
# reset_log — forget the fake daemon's history so far.
#
# Several cases have to reach a later step, and getting there legitimately
# creates and removes containers. Without this, "nothing was created" would be
# asserted against a log that already records the setup's own containers, and
# the assertion would fail for the wrong reason — or, worse, pass for one.
reset_log() { : > "$FAKE_DIR/log"; }

preflight_ok() {
  run_step preflight --expected-commit "$HEAD_SHA" --work-dir "$WORK"
  [ "$RC" -eq 0 ] || { fail "setup: preflight should have passed" "rc=$RC: $(tail -5 <<<"$OUT" | tr '\n' '|')"; return 1; }
  return 0
}
build_ok() {
  preflight_ok || return 1
  run_step build --work-dir "$WORK"
  [ "$RC" -eq 0 ] || { fail "setup: build should have passed" "rc=$RC: $(tail -8 <<<"$OUT" | tr '\n' '|')"; return 1; }
  return 0
}

matches() { # pattern -> 0 match, 1 no match, 2 grep failed
  local rc
  grep -qE "$1" <<<"$OUT"
  rc=$?
  case "$rc" in 0|1) return "$rc" ;; *) return 2 ;; esac
}
expect_rc_nonzero() { if [ "$RC" -ne 0 ]; then pass "$1"; else fail "$1" "expected nonzero exit, got 0. Tail: $(tail -6 <<<"$OUT" | tr '\n' '|')"; fi; }
expect_rc_zero()    { if [ "$RC" -eq 0 ]; then pass "$1"; else fail "$1" "expected exit 0, got $RC. Tail: $(tail -8 <<<"$OUT" | tr '\n' '|')"; fi; }
expect_rc()         { if [ "$RC" -eq "$2" ]; then pass "$1"; else fail "$1" "expected exit $2, got $RC. Tail: $(tail -6 <<<"$OUT" | tr '\n' '|')"; fi; }
expect_output()     { matches "$2"; case $? in 0) pass "$1" ;; 1) fail "$1" "output did not match /$2/. Tail: $(tail -8 <<<"$OUT" | tr '\n' '|')" ;; *) fail "$1" "grep failed — UNPROVEN" ;; esac; }
expect_no_output()  { matches "$2"; case $? in 0) fail "$1" "output unexpectedly matched /$2/" ;; 1) pass "$1" ;; *) fail "$1" "grep failed — UNPROVEN" ;; esac; }
log_has()   { if grep -qE "$2" "$FAKE_DIR/log"; then pass "$1"; else fail "$1" "log lacked /$2/: $(tr '\n' '|' < "$FAKE_DIR/log")"; fi; }
log_lacks() { if grep -qE "$2" "$FAKE_DIR/log"; then fail "$1" "log unexpectedly matched /$2/: $(tr '\n' '|' < "$FAKE_DIR/log")"; else pass "$1"; fi; }

echo "======================================================"
echo " operator-handoff.sh regression tests"
echo "======================================================"

# --- 1. Source identity -------------------------------------------------------
echo
echo "-- source identity --"

setup_case head-ok
run_step preflight --expected-commit "$HEAD_SHA" --work-dir "$WORK"
expect_rc_zero "preflight passes when HEAD is the expected checkout"
expect_output  "the expected checkout is named" "HEAD is the expected checkout $HEAD_SHA"

setup_case head-wrong
printf '%s' "$OTHER_SHA" > "$FAKE_DIR/head-sha"
run_step preflight --expected-commit "$HEAD_SHA" --work-dir "$WORK"
expect_rc_nonzero "an unexpected HEAD is refused"
expect_output "the refusal names both the actual and the expected commit" "HEAD is $OTHER_SHA but the expected checkout is $HEAD_SHA"
expect_output "the program refuses to move the tree itself" "will not move the tree"
log_lacks "nothing is built when HEAD is unexpected" '^build'

# The defect this replaces: the expected commit used to be hardcoded INSIDE the
# documentation commit, so revising that document invalidated the SHA it named
# and the procedure refused its own documented checkout. It is now an argument.
setup_case head-supplied
run_step preflight --work-dir "$WORK"
expect_rc_nonzero "preflight refuses without an explicit expected commit"
expect_output "the expected commit must be supplied by the operator" "requires --expected-commit"

setup_case head-malformed
run_step preflight --expected-commit "7e11419" --work-dir "$WORK"
expect_rc_nonzero "an abbreviated object name is refused"
expect_output "the refusal explains the required form" "40-character lowercase hex"

setup_case dirty
printf ' M docs/VERIFICATION.md\n' > "$FAKE_DIR/porcelain"
run_step preflight --expected-commit "$HEAD_SHA" --work-dir "$WORK"
expect_rc_nonzero "a dirty tree is refused"
expect_output "the refusal explains why attributability matters" "attributable to no commit"
expect_output "the dirty paths are shown" "docs/VERIFICATION.md"

setup_case git-rev-parse-fails
printf '1' > "$FAKE_DIR/rc.git-rev-parse"
run_step preflight --expected-commit "$HEAD_SHA" --work-dir "$WORK"
expect_rc_nonzero "a git metadata failure is refused"
expect_output "the failure is reported as unknown identity, not as a mismatch" "source identity is UNKNOWN"
expect_no_output "a failed rev-parse is not reported as a clean tree" "the working tree is clean"

setup_case git-status-fails
printf '1' > "$FAKE_DIR/rc.git-status"
run_step preflight --expected-commit "$HEAD_SHA" --work-dir "$WORK"
expect_rc_nonzero "a git status failure is refused"
expect_output "an unreadable tree state is not reported as clean" "attributability is UNKNOWN"
expect_no_output "an unreadable tree state is not reported as clean (positive line absent)" "the working tree is clean"

# --- 2. Environment and fixture redirection -----------------------------------
echo
echo "-- fixture redirection --"

setup_case exported-override
OUT="$(PATH="$BIN:$PATH" FAKE_DIR="$FAKE_DIR" SCAMWALL_CA_FILE=/tmp/throwaway-ca.pem \
       "$CHECKOUT/scripts/operator-handoff.sh" preflight --expected-commit "$HEAD_SHA" --work-dir "$WORK" 2>&1)"
RC=$?
expect_rc_nonzero "an exported fixture path is refused"
expect_output "the variable is named" "SCAMWALL_CA_FILE"
expect_no_output "the variable's VALUE is not echoed into the evidence log" "throwaway-ca.pem"

setup_case resolved-fixture
build_ok && {
  reset_log
  # The redirection arrives through the resolved configuration rather than the
  # environment, which assert_no_overrides cannot see.
  sed 's#/etc/scamwall/certs/pihole-ca.crt","target#/tmp/fixture-ca.crt","target#' \
    "$FAKE_DIR/compose-config.json" > "$FAKE_DIR/c.json" && mv "$FAKE_DIR/c.json" "$FAKE_DIR/compose-config.json"
  run_step probe --work-dir "$WORK"
  expect_rc_nonzero "a fixture bind source in the RESOLVED configuration is refused"
  expect_output "the refusal says the run would report on a fixture" "would report on a fixture"
  log_lacks "no container is created against a fixture configuration" '^create'
}

# --- 3. Build attribution and checked execution -------------------------------
echo
echo "-- build --"

setup_case build-ok
build_ok && {
  log_has "VERSION is passed explicitly to the build"    'build-arg VERSION='
  log_has "COMMIT is passed explicitly to the build"     "build-arg COMMIT=$HEAD_SHA"
  log_has "BUILD_DATE is passed explicitly to the build" 'build-arg BUILD_DATE='
  log_has "the build is driven with --progress=plain so its steps can be parsed" 'progress=plain'

  expect_output "the ELF assertion step is shown to have executed"  'ELF linkage assertion.*executed for this build'
  expect_output "the enforcement assertion step is shown to have executed" 'enforcement-absent assertion.*executed for this build'
  expect_output "the binary's own reported commit is checked" "the binary reports the expected commit $HEAD_SHA"
  expect_output "enforcement is confirmed absent from the artifact" 'enforcement as NOT compiled in'
  expect_output "source and image identities are recorded together" "source commit $HEAD_SHA was built into that image"
  # The verifier's own capture, not the program's stdout: the whole point of
  # capture_run is that a subordinate program's output goes to a file whose
  # path the operator is told, rather than into the middle of the verdict.
  if grep -qx "SCAMWALL_EXPECTED_IMAGE_ID=$IMAGE_A" "$WORK/verify.log" 2>/dev/null; then
    pass "the runtime verifier is pinned to the resolved image id"
  else
    fail "the runtime verifier is pinned to the resolved image id" "verify.log: $(tr '\n' '|' < "$WORK/verify.log" 2>/dev/null)"
  fi
  if grep -qx "SCAMWALL_IMAGE=$IMAGE_A" "$WORK/verify.log" 2>/dev/null; then
    pass "the runtime verifier is pointed at the resolved image id, not the tag"
  else
    fail "the runtime verifier is pointed at the resolved image id, not the tag" "verify.log: $(tr '\n' '|' < "$WORK/verify.log" 2>/dev/null)"
  fi
  expect_output "the FINDING-29 judgement is required from the verifier" 'FINDING-29'
}

setup_case build-fails-stale-tag
printf '1' > "$FAKE_DIR/rc.build"
preflight_ok && {
  run_step build --work-dir "$WORK"
  expect_rc_nonzero "a failed build fails the step"
  expect_output "the failure names the build's own exit status" 'BUILD exit=1'
  expect_output "the stale tag is called out"  'may still point at a STALE image'
  log_lacks "nothing is run against the stale image" '^create'
  log_lacks "the runtime verifier is not invoked after a failed build" 'SCAMWALL_EXPECTED_IMAGE_ID'
}

# An identical image id is legitimate. The superseded procedure REFUSED here,
# on the theory that an unchanged id meant the build had not replaced the tag —
# which makes a reproducible build a failure.
setup_case build-same-image-id
preflight_ok && {
  printf '%s' "$IMAGE_A" > "$FAKE_DIR/image-id-after-build"
  run_step build --work-dir "$WORK"
  expect_rc_zero "a build producing the SAME image id is not a failure"
  expect_output "the unchanged id is explained rather than refused" 'identical inputs produce an identical image'
  expect_no_output "no refusal is issued for an unchanged image id" 'the build did not replace it'
}

setup_case build-wrong-commit
preflight_ok && {
  printf 'scamwall  dev\ncommit    %s\nenforcement compiled in  false\n' "$OTHER_SHA" > "$FAKE_DIR/version-output"
  run_step build --work-dir "$WORK"
  expect_rc_nonzero "an image whose binary reports the wrong commit fails"
  expect_output "the expected commit is named in the failure" "the binary reports the expected commit $HEAD_SHA"
}

setup_case build-enforcement-present
preflight_ok && {
  printf 'scamwall  dev\ncommit    %s\nenforcement compiled in  true\n' "$HEAD_SHA" > "$FAKE_DIR/version-output"
  run_step build --work-dir "$WORK"
  expect_rc_nonzero "an image reporting enforcement as compiled in fails"
  expect_output "the enforcement assertion is the one that failed" 'enforcement as NOT compiled in'
}

setup_case build-cached-assertion
preflight_ok && {
  sed 's/^#11 DONE 1.4s/#11 CACHED/' "$FAKE_DIR/build-output" > "$FAKE_DIR/b" && mv "$FAKE_DIR/b" "$FAKE_DIR/build-output"
  run_step build --work-dir "$WORK"
  expect_rc_nonzero "a CACHED in-build assertion step fails the step"
  expect_output "the reason is that a cached step did not execute" 'CACHED and therefore did not execute'
}

setup_case build-log-capture-fails
preflight_ok && {
  # The build SUCCEEDS and writes nothing. Two different facts.
  : > "$FAKE_DIR/build-output"
  run_step build --work-dir "$WORK"
  expect_rc_nonzero "an unusable build log fails the step"
  expect_output "the build's own status is still reported"    'BUILD exit=0'
  expect_output "the capture failure is reported separately"  'nothing was captured'
  expect_output "the capture failure is distinguished from the exit status" 'separate from the command'
}

setup_case tag-moves
preflight_ok && {
  # The tag is resolved once for the prior id, once after the build, and once
  # at the end. The last one answers with a different image.
  printf '%s' "$IMAGE_B" > "$FAKE_DIR/image-id-moved"
  printf '3'             > "$FAKE_DIR/tag-moves-at"
  run_step build --work-dir "$WORK"
  expect_rc_nonzero "a tag that moves after the image was resolved fails the step"
  expect_output "the movement is reported with both ids" "now points at $IMAGE_B, not the image verified here"
}

setup_case verifier-fails
preflight_ok && {
  printf '1' > "$FAKE_DIR/rc.verify"
  run_step build --work-dir "$WORK"
  expect_rc_nonzero "a failing runtime verifier fails the step"
  expect_output "the verifier's own exit status is reported" 'VERIFY exit=1'
}

setup_case verifier-silent-on-finding29
preflight_ok && {
  : > "$FAKE_DIR/verify-output"
  run_step build --work-dir "$WORK"
  expect_rc_nonzero "a verifier run that never produced the FINDING-29 judgement fails"
  expect_output "the missing judgement is named" 'FINDING-29'
}

# --- 4. The credential-free probe (step B) ------------------------------------
echo
echo "-- step B: credential-free probe --"

setup_case probe-ok
build_ok && {
  reset_log
  run_step probe --work-dir "$WORK"
  expect_rc_zero "the credential-free probe passes against a healthy deployment"
  expect_output "the created container is checked against the verified image" 'runs exactly the image verified in step A'
  expect_output "no credential is mounted"  'no credential is mounted into the connectivity probe'
  expect_output "doctor reports the credential as SKIPPED" 'SKIPPED, not as passed'
  expect_output "the CA and TLS result is read" 'chain verified against the private CA'
  log_lacks "the probe never mounts the production password" "target=$CT_SECRET_PATH"
  log_lacks "no project-wide compose down is issued" 'compose .*down'
  expect_output "the container is removed" 'cleanup complete'
}

setup_case probe-secret-mounted
build_ok && {
  # The container was created with a credential mount despite the step's claim.
  : > "$FAKE_DIR/force-secret-mount"
  run_step probe --work-dir "$WORK"
  expect_rc_nonzero "a credential mounted into the credential-free probe fails the step"
  expect_output "the mounted credential is named" "$CT_SECRET_PATH IS mounted"
}

setup_case probe-secret-read
build_ok && {
  # doctor reports having READ the password — the exact contradiction the
  # superseded step B carried in its own expected-output table.
  sed 's/^SKIP  application password.*/ok    application password    readable/' \
    "$FAKE_DIR/doctor-output" > "$FAKE_DIR/d" && mv "$FAKE_DIR/d" "$FAKE_DIR/doctor-output"
  run_step probe --work-dir "$WORK"
  expect_rc_nonzero "a credential-free probe that reports reading the credential fails"
  expect_output "the missing SKIP line is reported" 'SKIPPED, not as passed'
}

setup_case probe-tls-fails
build_ok && {
  sed 's/^ok    pi-hole connectivity.*/FAIL  pi-hole connectivity    TLS verification failed/' \
    "$FAKE_DIR/doctor-output" > "$FAKE_DIR/d" && mv "$FAKE_DIR/d" "$FAKE_DIR/doctor-output"
  printf '1' > "$FAKE_DIR/rc.start"
  run_step probe --work-dir "$WORK"
  expect_rc_nonzero "a TLS failure fails the step"
  expect_output "the operator is told not to proceed to step D" 'do NOT proceed to step D'
}

# --- 5. The offline secret read (step C) --------------------------------------
echo
echo "-- step C: offline secret read --"

setup_case secret-ok
build_ok && {
  reset_log
  run_step secret --work-dir "$WORK"
  expect_rc_zero "the offline secret read passes"
  expect_output "the network is disabled at the CONTAINER level" 'no network at all \(none\)'
  expect_output "the read is attributed to the container identity" 'uid 65532 with the configured supplementary group'
  log_has "the secret is mounted for this step, and only this step" "target=$CT_SECRET_PATH"
  log_has "the container is created with no network" 'network none'
}

setup_case secret-has-network
build_ok && {
  printf 'bridge' > "$FAKE_DIR/force-network-mode"
  run_step secret --work-dir "$WORK"
  expect_rc_nonzero "a secret probe with network access fails the step"
  expect_output "the observed network mode is reported" "network mode is 'bridge', expected 'none'"
}

setup_case secret-unreadable
build_ok && {
  sed 's/^ok    application password.*/FAIL  application password    open secret: permission denied/' \
    "$FAKE_DIR/secret-output" > "$FAKE_DIR/s" && mv "$FAKE_DIR/s" "$FAKE_DIR/secret-output"
  printf '1' > "$FAKE_DIR/rc.start"
  run_step secret --work-dir "$WORK"
  expect_rc_nonzero "an unreadable secret fails the step"
  expect_output "the disagreement with step A is flagged as outranking either result" 'outranks either result'
}

setup_case secret-length-disclosed
build_ok && {
  sed 's/^ok    application password.*/ok    application password    readable, 43 bytes/' \
    "$FAKE_DIR/secret-output" > "$FAKE_DIR/s" && mv "$FAKE_DIR/s" "$FAKE_DIR/secret-output"
  run_step secret --work-dir "$WORK"
  expect_rc_nonzero "a credential length in the output fails the step"
  expect_output "the disclosure is named" 'no credential length is disclosed'
}

# --- 6. The authenticated step (step D) ---------------------------------------
echo
echo "-- step D: the authenticated operation --"

setup_case status-unauthorised
build_ok && {
  reset_log
  run_step status --work-dir "$WORK"
  expect_rc_nonzero "step D is refused without explicit authorisation"
  expect_output "the refusal names the flag" 'authorise-authenticated-read'
  log_lacks "nothing is created when step D is refused" '^create'
  log_lacks "nothing authenticates when step D is refused" '^start'
}

setup_case status-ok
build_ok && {
  run_step status --work-dir "$WORK" --authorise-authenticated-read
  expect_rc_zero "an accepted session teardown passes"
  expect_output "acceptance is reported as a fact about a REQUEST" 'fact about a REQUEST'
  expect_output "independent confirmation is stated as unavailable" 'independent confirmation is NOT available'
  expect_output "no UI menu path is promised" 'has NOT been verified for any Pi-hole version'
  expect_output "the real request bound is stated" 'not .exactly three requests'
}

setup_case status-logout-fails
build_ok && {
  sed 's/^session logout ACCEPTED by Pi-hole/session logout FAILED./' \
    "$FAKE_DIR/status-output" > "$FAKE_DIR/s" && mv "$FAKE_DIR/s" "$FAKE_DIR/status-output"
  printf '1' > "$FAKE_DIR/rc.start"
  run_step status --work-dir "$WORK" --authorise-authenticated-read
  expect_rc_nonzero "a failed session teardown fails the step"
  expect_output "the failure is stated in the appliance's terms" 'may remain valid on the appliance until it expires'
  expect_no_output "a failed teardown is never reported as accepted" 'teardown request was ACCEPTED'
}

setup_case status-silent-on-teardown
build_ok && {
  printf 'component  local\ncore       v6.0.4\n' > "$FAKE_DIR/status-output"
  run_step status --work-dir "$WORK" --authorise-authenticated-read
  expect_rc_nonzero "output that says nothing about the teardown is UNPROVEN, not a pass"
  expect_output "the silence is reported as unproven" 'makes no statement about the session teardown'
}

# --- 7. Resource ownership, cleanup and interruption --------------------------
echo
echo "-- ownership, cleanup and interruption --"

setup_case cleanup-fails
build_ok && {
  printf '1' > "$FAKE_DIR/rc.rm"
  run_step probe --work-dir "$WORK"
  expect_rc_nonzero "a cleanup failure makes the verdict nonzero"
  expect_output "cleanup is reported as incomplete" 'cleanup INCOMPLETE'
  expect_output "the remaining identifier is named" 'removal failed'
}

setup_case partial-creation
build_ok && {
  reset_log
  # The container is created and then the image identity check refuses it. The
  # partial creation must still be cleaned up.
  printf '%s' "$IMAGE_B" > "$FAKE_DIR/container-image-mismatch"
  run_step probe --work-dir "$WORK"
  expect_rc_nonzero "a container running an unexpected image fails the step"
  expect_output "the substituted image is named" "runs image $IMAGE_B, not the verified"
  log_has "the partially created container is still removed" '^rm -f cid'
}

setup_case not-ours
build_ok && {
  reset_log
  # The daemon reports a container that does NOT carry this invocation's label.
  printf 'someone-elses-invocation' > "$FAKE_DIR/own-label"
  printf 'someone-elses-project'    > "$FAKE_DIR/project-label"
  run_step probe --work-dir "$WORK"
  expect_rc_nonzero "a resource that cannot be attributed to this invocation is not deleted"
  expect_output "it is preserved rather than removed" 'PRESERVED'
  log_lacks "no removal is attempted on an unattributable resource" '^rm -f'
}

setup_case pre-existing-label
build_ok && {
  reset_log
  printf '1' > "$FAKE_DIR/rc.own-query"
  run_step probe --work-dir "$WORK"
  expect_rc_nonzero "an enumeration failure before creation is refused"
  expect_output "the refusal says enumeration failed" 'could not be enumerated'
  log_lacks "nothing is created when the pre-snapshot could not be taken" '^create'
}

setup_case interrupted
build_ok && {
  reset_log
  : > "$FAKE_DIR/interrupt"
  run_step probe --work-dir "$WORK"
  expect_rc "an interrupted run exits with the signal's status" 143
  expect_output "the interruption is announced" 'interrupted by TERM'
  log_has "the container created before the interruption is removed" '^rm -f cid'
}

# --- 8. Closeout --------------------------------------------------------------
echo
echo "-- closeout --"

setup_case closeout-enum-fails
build_ok && {
  printf '1' > "$FAKE_DIR/rc.project-query"
  run_step closeout --work-dir "$WORK"
  expect_rc_nonzero "a failed leftover enumeration is not a clean result"
  expect_output "the enumeration failure is stated" 'could not be enumerated'
  expect_output "the result is called unproven" 'leftovers are UNPROVEN'
  expect_no_output "an unaskable question is never answered 'nothing remains'" 'no container of this handoff remains'
}

setup_case closeout-leftovers
build_ok && {
  printf 'cid999999999\n' > "$FAKE_DIR/project-containers"
  run_step closeout --work-dir "$WORK"
  expect_rc_nonzero "a remaining resource fails the closeout"
  expect_output "the remaining identifier is printed" 'cid999999999'
}

# --- 9. Diagnostics never carry a credential ----------------------------------
echo
echo "-- diagnostics --"

setup_case redaction
preflight_ok && {
  printf '1' > "$FAKE_DIR/rc.build"
  {
    printf '#5 [build 3/8] RUN go build\n'
    printf 'error: request failed: {"password":"hunter2-not-a-real-password"}\n'
    printf 'X-FTL-SID: 0123456789abcdef0123456789abcdef\n'
    # The PEM marker is assembled from fragments, exactly as
    # scripts/secret-scan.sh assembles its own: a decoy written literally
    # would make this file trip the private-key rule, and whitelisting the
    # file would create the blind spot that rule exists to close.
    #
    # %s, because printf reads a leading "-----" as its own options — the PEM
    # would never reach the capture and the assertion below would pass for the
    # wrong reason. That is what the first version of this case did.
    #
    # The body line is a REAL 64-character PEM line. The sanitizer is
    # line-oriented: the BEGIN line is redacted by its own rule and each body
    # line by the long-opaque-value rule, which needs 40 characters. A PEM's
    # short FINAL line can fall under that threshold; that limit is recorded in
    # docs/VERIFICATION.md rather than papered over with a fixture chosen to
    # avoid it.
    dashes='-----'
    printf '%s\n' "${dashes}BEGIN PRIVATE KEY${dashes}" \
      'MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDPihUnT2AbcDEF' \
      "${dashes}END PRIVATE KEY${dashes}"
  } > "$FAKE_DIR/build-output"
  run_step build --work-dir "$WORK"
  expect_rc_nonzero "a failing build with credential-shaped output still fails"
  expect_no_output "a password-shaped value is not printed"    'hunter2-not-a-real-password'
  expect_no_output "a session id header value is not printed"  '0123456789abcdef0123456789abcdef'
  expect_no_output "a PEM body line is not printed"            'MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDPihUnT2AbcDEF'
  expect_output    "the diagnostic is shown, redacted"         '<redacted'
}

# --- 10. Evidence retention ---------------------------------------------------
echo
echo "-- evidence retention --"

setup_case retain-logs
preflight_ok && {
  printf '1' > "$FAKE_DIR/rc.build"
  run_step build --work-dir "$WORK"
  expect_rc_nonzero "the failing build fails"
  expect_output "the operator is told where the evidence is" "Evidence and sanitized logs remain in: $WORK"
  expect_output "the operator is told how to remove it safely" "rm -rf -- $WORK"
  if [ -f "$WORK/build.log" ]; then
    pass "a FAILING run's log is not erased before the operator can read it"
  else
    fail "a FAILING run's log is not erased before the operator can read it" "$WORK/build.log is gone"
  fi
  MODE="$(stat -c '%a' "$WORK" 2>/dev/null)"
  if [ "$MODE" = "700" ]; then pass "the work directory is mode 700"
  else fail "the work directory is mode 700" "mode is $MODE"; fi
  LOGMODE="$(stat -c '%a' "$WORK/build.log" 2>/dev/null)"
  if [ "$LOGMODE" = "600" ]; then pass "a captured log is mode 600"
  else fail "a captured log is mode 600" "mode is $LOGMODE"; fi
}

setup_case work-dir-loose
mkdir -p "$WORK" && chmod 755 "$WORK" && : > "$WORK/state.env"
run_step build --work-dir "$WORK"
expect_rc_nonzero "a work directory that is not 700 is refused"
expect_output "the observed mode is named" 'is mode 755, not 700'

setup_case no-state
mkdir -p "$WORK" && chmod 700 "$WORK"
run_step build --work-dir "$WORK"
expect_rc_nonzero "a step run before preflight is refused"
expect_output "the operator is told to run preflight" 'run the preflight step first'

# --- 11. The resolved-configuration filters, against the REAL Compose CLI -----
#
# Every case above reads a canned `compose config` fixture. This one renders the
# real definition with the real client — no daemon is involved — so a drift
# between the fixture's shape and Compose's actual output is caught rather than
# assumed away.
echo
echo "-- resolved configuration, against the real Compose CLI --"
if command -v docker >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  REAL_JSON="$ROOT/real-compose-config.json"
  if docker compose --env-file "$CHECKOUT/deploy/compose/.env" \
       -f "$CHECKOUT/deploy/compose/compose.yaml" config --format json > "$REAL_JSON" 2>/dev/null; then
    check_filter() { # label filter expected
      local got
      got="$(jq -er "$2" < "$REAL_JSON" 2>/dev/null)"
      if [ "$got" = "$3" ]; then pass "$1"; else fail "$1" "read '$got', expected '$3'"; fi
    }
    check_filter "the container user is read from the real resolved configuration" \
      '.services."scamwall".user' '65532:65532'
    check_filter "the supplementary group is read from the real resolved configuration" \
      '.services."scamwall".group_add[0] | tostring' '989'
    check_filter "the secret source is read from the real resolved configuration" \
      '.secrets.pihole_app_password.file' '/etc/scamwall/secrets/pihole_app_password'
    check_filter "the CA bind source is read from the real resolved configuration" \
      '.services."scamwall".volumes[] | select(.target == "/etc/scamwall/certs/pihole-ca.crt") | .source' \
      '/etc/scamwall/certs/pihole-ca.crt'
    # The array-vs-object rendering of extra_hosts, and the `=` separator the
    # array form uses, were both found BY THIS CASE: the canned fixture had the
    # object form and the program would have passed `pi.hole=host-gateway` to
    # --add-host. This is the filter the program actually uses.
    check_filter "the pi.hole mapping is read from the real resolved configuration" \
      '.services."scamwall".extra_hosts | if type == "object" then (to_entries | map("\(.key):\(.value)") | .[]) elif type == "array" then (.[] | sub("="; ":")) else empty end' \
      'pi.hole:host-gateway'
  else
    printf '\033[33mskip\033[0m the real Compose CLI could not resolve the definition\n'
  fi
else
  printf '\033[33mskip\033[0m docker or jq is not installed; the canned fixture is not cross-checked\n'
fi

echo
echo "=============================================="
printf ' %d tests, %d failed\n' "$TESTS" "$FAILURES"
if [ "$FAILURES" -gt 0 ]; then
  echo " RESULT: operator-handoff regression tests FAILED"
  exit 1
fi
echo " all operator-handoff regression tests passed"
exit 0
