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
    # A case can hold the build OPEN, or interrupt it. The first proves the
    # work-directory lock is held for the duration of a step rather than only
    # taken at its start; the second proves a rebuild that dies partway leaves
    # nothing downstream usable.
    if [ -f "$D/build-blocks" ]; then
      : > "$D/build-entered"
      i=0
      while [ ! -f "$D/build-release" ] && [ "$i" -lt 400 ]; do sleep 0.05; i=$((i + 1)); done
    fi
    if [ -f "$D/build-interrupt" ]; then
      : > "$D/build-entered"
      kill -TERM "$PPID" 2>/dev/null
      sleep 5
      exit 0
    fi
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

# --- Fake mv, standing at the one moment the state file changes ---------------
#
# The handoff builds every state update in a temporary file beside state.env
# and installs it with ONE rename. That is the property under test, and from
# outside the program the rename is the only place it can be observed or
# interrupted — so `mv` is shadowed here.
#
# It acts ONLY on renames whose destination is a state.env, and only when the
# case has asked it to; everything else is delegated to the real mv unchanged,
# including the fake daemon's own bookkeeping.
#
#   record            copy each version that is about to be installed into
#                     $FAKE_DIR/state-versions/, then install it. This is what
#                     makes "no version of this file ever said `passed` without
#                     saying what against" a checkable statement rather than a
#                     claim about the source.
#   fail-on-pass      refuse the rename that would publish the pass.
#   kill-before-pass  SIGKILL the handoff instead of performing that rename.
#   kill-after-pass   perform it, then SIGKILL the handoff immediately.
#
# SIGKILL rather than SIGTERM deliberately: a signal the program can handle
# would let it tidy up, and what is being established here is what survives
# when it CANNOT.
cat > "$BIN/mv" <<'MV_EOF'
#!/usr/bin/env bash
REAL=""
for c in /bin/mv /usr/bin/mv; do [ -x "$c" ] && REAL="$c" && break; done
[ -n "$REAL" ] || { printf 'no real mv found\n' >&2; exit 127; }

D="${FAKE_DIR:-}"
mode=""
[ -n "$D" ] && [ -f "$D/mv-mode" ] && mode="$(cat "$D/mv-mode" 2>/dev/null)"
[ -n "$mode" ] || exec "$REAL" "$@"

dst="${*: -1}"
case "$dst" in
  */state.env) ;;
  *) exec "$REAL" "$@" ;;
esac

src=""
[ "$#" -ge 2 ] && src="${@:$(($# - 1)):1}"
key="STEP_STATUS_BUILD=passed"
[ -f "$D/mv-key" ] && key="$(cat "$D/mv-key" 2>/dev/null)"
publishes_pass=0
grep -qxF "$key" "$src" 2>/dev/null && publishes_pass=1

case "$mode" in
  record)
    n="$(cat "$D/mv-count" 2>/dev/null || echo 0)"
    n=$((n + 1)); printf '%s' "$n" > "$D/mv-count"
    mkdir -p "$D/state-versions"
    cp -- "$src" "$D/state-versions/$(printf '%03d' "$n")" 2>/dev/null
    exec "$REAL" "$@"
    ;;
  fail-on-pass)
    if [ "$publishes_pass" -eq 1 ]; then
      printf 'simulated: the state file could not be installed\n' >&2
      exit 1
    fi
    exec "$REAL" "$@"
    ;;
  kill-before-pass)
    if [ "$publishes_pass" -eq 1 ]; then
      : > "$D/killed-before-publication"
      kill -KILL "$PPID" 2>/dev/null
      sleep 5
      exit 1
    fi
    exec "$REAL" "$@"
    ;;
  kill-after-pass)
    "$REAL" "$@" || exit 1
    if [ "$publishes_pass" -eq 1 ]; then
      : > "$D/killed-after-publication"
      kill -KILL "$PPID" 2>/dev/null
      sleep 5
    fi
    exit 0
    ;;
  *) exec "$REAL" "$@" ;;
esac
MV_EOF
chmod +x "$BIN/mv"

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
# secret_ok — 0, A, B and C, which is what step D now REQUIRES before it will
# authenticate. Before this, step D ran off a passing step A and a flag; the
# cases that exercise step D therefore had to be changed to get there
# legitimately, and that change is itself part of the fix.
probe_ok() {
  build_ok || return 1
  run_step probe --work-dir "$WORK"
  [ "$RC" -eq 0 ] || { fail "setup: probe should have passed" "rc=$RC: $(tail -8 <<<"$OUT" | tr '\n' '|')"; return 1; }
  return 0
}
secret_ok() {
  probe_ok || return 1
  run_step secret --work-dir "$WORK"
  [ "$RC" -eq 0 ] || { fail "setup: secret should have passed" "rc=$RC: $(tail -8 <<<"$OUT" | tr '\n' '|')"; return 1; }
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
  if grep -qx "SCAMWALL_EXPECTED_IMAGE_ID=$IMAGE_A" "$WORK/raw/verify.log" 2>/dev/null; then
    pass "the runtime verifier is pinned to the resolved image id"
  else
    fail "the runtime verifier is pinned to the resolved image id" "verify.log: $(tr '\n' '|' < "$WORK/raw/verify.log" 2>/dev/null)"
  fi
  if grep -qx "SCAMWALL_IMAGE=$IMAGE_A" "$WORK/raw/verify.log" 2>/dev/null; then
    pass "the runtime verifier is pointed at the resolved image id, not the tag"
  else
    fail "the runtime verifier is pointed at the resolved image id, not the tag" "verify.log: $(tr '\n' '|' < "$WORK/raw/verify.log" 2>/dev/null)"
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
secret_ok && {
  run_step status --work-dir "$WORK" --authorise-authenticated-read
  expect_rc_zero "an accepted session teardown passes"
  expect_output "acceptance is reported as a fact about a REQUEST" 'fact about a REQUEST'
  expect_output "independent confirmation is stated as unavailable" 'independent confirmation is NOT available'
  expect_output "no UI menu path is promised" 'has NOT been verified for any Pi-hole version'
  expect_output "the real request bound is stated" 'not .exactly three requests'
}

setup_case status-logout-fails
secret_ok && {
  sed 's/^session logout ACCEPTED by Pi-hole/session logout FAILED./' \
    "$FAKE_DIR/status-output" > "$FAKE_DIR/s" && mv "$FAKE_DIR/s" "$FAKE_DIR/status-output"
  printf '1' > "$FAKE_DIR/rc.start"
  run_step status --work-dir "$WORK" --authorise-authenticated-read
  expect_rc_nonzero "a failed session teardown fails the step"
  expect_output "the failure is stated in the appliance's terms" 'may remain valid on the appliance until it expires'
  expect_no_output "a failed teardown is never reported as accepted" 'teardown request was ACCEPTED'
}

setup_case status-silent-on-teardown
secret_ok && {
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

# --- 8b. FINDING-49: a re-run of step A must not leave a stale image pin -------
#
# The state file carries identities from one step to the next. state_put
# APPENDED and state_get returned the FIRST match, so a second `build` into the
# same work directory recorded a new IMAGE_ID that nothing ever read: steps B, C
# and D went on creating their containers from the PREVIOUS build's image while
# step A's report named the new one. Each still passed its own `.Image`
# comparison — because it compared against the same stale value it had been
# created from. That is FINDING-44 arriving by a different route.
echo
echo "-- state file identity --"

setup_case rebuild-repins
preflight_ok && {
  run_step build --work-dir "$WORK"
  expect_rc_zero "the first build passes"

  # A second build, of a DIFFERENT image, into the same work directory.
  printf '%s' "$IMAGE_B" > "$FAKE_DIR/image-id"
  run_step build --work-dir "$WORK"
  expect_rc_zero "a second build into the same work directory passes"
  # The message changed with the fix and says something stronger. The previous
  # one announced a REPLACEMENT after the fact; this one announces that the
  # previous identity was INVALIDATED before the rebuild started, which is what
  # makes a failed rebuild safe as well as a successful one.
  expect_output "the invalidation of the recorded image id is announced" \
    'previously recorded IMAGE_ID is INVALIDATED'

  N_IDS="$(grep -c '^IMAGE_ID=' "$WORK/state.env" 2>/dev/null)" || N_IDS="?"
  if [ "$N_IDS" = "1" ]; then
    pass "the state file holds exactly one IMAGE_ID record"
  else
    fail "the state file holds exactly one IMAGE_ID record" "found $N_IDS"
  fi

  RECORDED="$(grep '^IMAGE_ID=' "$WORK/state.env" 2>/dev/null | head -1)"
  if [ "$RECORDED" = "IMAGE_ID=$IMAGE_B" ]; then
    pass "the recorded image id is the second build's"
  else
    fail "the recorded image id is the second build's" "state holds '$RECORDED', expected 'IMAGE_ID=$IMAGE_B'"
  fi

  # The pin is only worth anything if the NEXT step uses it. The fake records
  # every `create` argument list, so this is read from what the container was
  # actually created from rather than from what the program said.
  #
  # The recorded argument lists are cleared as well as the log. The FIRST build
  # legitimately created a version probe from IMAGE_A — that is step A asking
  # the artifact its own commit — so without this the stale-image assertion
  # below would match that container and fail for the wrong reason.
  reset_log
  rm -f "$FAKE_DIR"/container-*.args
  run_step probe --work-dir "$WORK"
  expect_rc_zero "the probe passes after the rebuild"
  if grep -qF -- "$IMAGE_B" "$FAKE_DIR"/container-*.args 2>/dev/null; then
    pass "the probe container is created from the SECOND build's image"
  else
    fail "the probe container is created from the SECOND build's image" \
         "no create carried $IMAGE_B"
  fi
  if grep -qF -- "$IMAGE_A" "$FAKE_DIR"/container-*.args 2>/dev/null; then
    fail "the probe container is not created from the stale image" \
         "a create carried the first build's $IMAGE_A"
  else
    pass "the probe container is not created from the stale image"
  fi
}

# PRE-FIX CONTROL. The superseded pair — append, and read the first match — is
# reproduced here over the same two writes and asserted to return the STALE
# value. Without it the cases above prove only that the new implementation
# agrees with itself.
CTL_STATE="$ROOT/ctl-state.env"
: > "$CTL_STATE"
printf 'IMAGE_ID=%s\n' "$IMAGE_A" >> "$CTL_STATE"
printf 'IMAGE_ID=%s\n' "$IMAGE_B" >> "$CTL_STATE"
CTL_FIRST="$(grep -m1 -E '^IMAGE_ID=' "$CTL_STATE" 2>/dev/null)"
CTL_FIRST="${CTL_FIRST#*=}"
if [ "$CTL_FIRST" = "$IMAGE_A" ]; then
  pass "PRE-FIX CONTROL: append-and-read-first returns the stale image id, the replacement does not"
else
  fail "PRE-FIX CONTROL: append-and-read-first returns the stale image id" \
       "the superseded shape returned '$CTL_FIRST'; this fixture does not reproduce FINDING-49"
fi

# The current reader must take the LAST record, so a state file written by an
# older revision of this program — which really can hold duplicates — resolves
# to the current value rather than the stale one.
CTL_LAST="$(awk -v key=IMAGE_ID '
  index($0, key "=") == 1 { v = substr($0, length(key) + 2) }
  END { print v }' "$CTL_STATE")"
if [ "$CTL_LAST" = "$IMAGE_B" ]; then
  pass "a duplicated state file from an older revision resolves to the current value"
else
  fail "a duplicated state file from an older revision resolves to the current value" "got '$CTL_LAST'"
fi

# --- 8c. FINDING-50: the secret baseline is taken before the handoff, not after
#
# step Z compared the deployment secret's metadata against "the values recorded
# earlier in the same work directory". Nothing recorded them earlier: step Z
# took its own baseline when it found none, printed "no earlier metadata was
# recorded", and reported `ok`. On a single pass — 0, A, B, C, D, Z, which is
# the whole procedure — that was EVERY run. The comparison never happened and
# the step reported a pass for it anyway.
#
# The baseline is now taken by the preflight step. Where preflight could not
# read it, that is recorded, and step Z reports UNPROVEN instead of inventing a
# baseline at the moment it is supposed to be checking one.
echo
echo "-- secret metadata baseline --"

setup_case secret-baseline
run_step preflight --expected-commit "$HEAD_SHA" --work-dir "$WORK"
expect_rc_zero "preflight passes on a host with no deployment secret"
expect_output "the unreadable baseline is stated, not hidden" \
  'metadata could not be read at /etc/scamwall/secrets/pihole_app_password'
expect_output "preflight says it is recording rather than failing" 'recorded, not failed'
expect_output "preflight says step Z will report UNPROVEN" 'UNPROVEN'
if grep -q '^SECRET_META_UNAVAILABLE=1$' "$WORK/state.env" 2>/dev/null; then
  pass "the unavailability is recorded in the state file"
else
  fail "the unavailability is recorded in the state file" "$(tr '\n' '|' < "$WORK/state.env" 2>/dev/null)"
fi
if grep -q '^SECRET_META=' "$WORK/state.env" 2>/dev/null; then
  fail "no baseline is fabricated when the secret cannot be read" "SECRET_META was recorded anyway"
else
  pass "no baseline is fabricated when the secret cannot be read"
fi

# The case that actually discriminates.
#
# On a host with no deployment, step Z's metadata read fails and it reports that
# — which the superseded code did too, so a test run only in that condition
# would pass against the defect. The branch the defect lived in is the one where
# the read SUCCEEDS and no baseline exists, and reaching it needs a readable
# secret path.
#
# `stat` is therefore shimmed for these two cases only: it answers for the
# deployment's secret path and delegates everything else — the work directory's
# mode, the repository's owner — to the real one. The shim is removed
# immediately afterwards so no later case inherits it.
STAT_MTIME_FILE="$ROOT/stat-mtime"
stat_shim() { # <mtime> — answer for the secret path, delegate everything else
  printf '%s' "$1" > "$STAT_MTIME_FILE"
  cat > "$BIN/stat" <<STAT_EOF
#!/usr/bin/env bash
for a in "\$@"; do
  if [ "\$a" = "/etc/scamwall/secrets/pihole_app_password" ]; then
    printf '0:989 640 64 %s\n' "\$(cat '$STAT_MTIME_FILE')"
    exit 0
  fi
done
exec /usr/bin/stat "\$@"
STAT_EOF
  chmod +x "$BIN/stat"
}

setup_case closeout-no-baseline
# Preflight and build run with NO shim, so no baseline is recorded — the exact
# state the superseded code invented one in. The shim is installed only for the
# closeout, so its metadata read SUCCEEDS and the branch under test is reached.
build_ok && {
  stat_shim 1750000000
  run_step closeout --work-dir "$WORK"
  expect_rc_nonzero "a readable secret with no recorded baseline is not a clean result"
  expect_output "the missing baseline is reported as not comparable" \
    'no baseline was recorded by the preflight step'
  expect_no_output "step Z never takes its own baseline and calls it a pass" \
    'this run records it as the baseline'
  expect_no_output "step Z never reports the metadata check as passed" \
    'secret metadata recorded'
  if grep -q '^SECRET_META=' "$WORK/state.env" 2>/dev/null; then
    fail "step Z does not write a baseline at the moment it should be checking one" \
         "closeout recorded SECRET_META itself"
  else
    pass "step Z does not write a baseline at the moment it should be checking one"
  fi
}

# And the positive: with a baseline recorded by preflight, the comparison is
# real and it passes.
setup_case closeout-baseline-matches
stat_shim 1750000000
preflight_ok && {
  if grep -q "^SECRET_META=0:989 640 64 1750000000$" "$WORK/state.env" 2>/dev/null; then
    pass "preflight records the deployment secret's baseline when it can read it"
  else
    fail "preflight records the deployment secret's baseline when it can read it" \
         "$(tr '\n' '|' < "$WORK/state.env" 2>/dev/null)"
  fi
  run_step build --work-dir "$WORK"
  run_step closeout --work-dir "$WORK"
  expect_output "an unchanged secret compares equal against the preflight baseline" \
    "the secret's metadata is unchanged"
  expect_output "the comparison states what it does NOT prove" \
    'does NOT prove the content is unchanged'
}

# And the negative: a secret that changed during the handoff is caught.
setup_case closeout-baseline-changed
stat_shim 1750000000
preflight_ok && {
  run_step build --work-dir "$WORK"
  # The secret's mtime moves between the baseline and the closeout.
  stat_shim 1799999999
  run_step closeout --work-dir "$WORK"
  expect_rc_nonzero "a secret that changed during the handoff fails the closeout"
  expect_output "the change is stated" 'metadata CHANGED during this handoff'
}

rm -f "$BIN/stat"

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
  expect_output "the operator is told where this step's files are" "This step's files are in: $WORK"
  expect_output "the raw directory is named as unsanitized"        "$WORK/raw"
  expect_output "the raw directory is labelled DO NOT SHARE"       'DO NOT SHARE IT'
  expect_output "the evidence directory is named as the shareable one" "$WORK/evidence"
  expect_output "the deny-by-pattern limit is stated where the evidence is offered" \
    'establishes what its patterns catch'
  expect_output "the operator is told how to remove it safely" "rm -rf -- $WORK"
  if [ -f "$WORK/raw/build.log" ]; then
    pass "a FAILING run's log is not erased before the operator can read it"
  else
    fail "a FAILING run's log is not erased before the operator can read it" "$WORK/raw/build.log is gone"
  fi
  MODE="$(stat -c '%a' "$WORK" 2>/dev/null)"
  if [ "$MODE" = "700" ]; then pass "the work directory is mode 700"
  else fail "the work directory is mode 700" "mode is $MODE"; fi
  for D in raw evidence; do
    DMODE="$(stat -c '%a' "$WORK/$D" 2>/dev/null)"
    if [ "$DMODE" = "700" ]; then pass "the $D directory is mode 700"
    else fail "the $D directory is mode 700" "mode is $DMODE"; fi
  done
  LOGMODE="$(stat -c '%a' "$WORK/raw/build.log" 2>/dev/null)"
  if [ "$LOGMODE" = "600" ]; then pass "a captured log is mode 600"
  else fail "a captured log is mode 600" "mode is $LOGMODE"; fi
  EMODE="$(stat -c '%a' "$WORK/evidence/build.log" 2>/dev/null)"
  if [ "$EMODE" = "600" ]; then pass "a published evidence file is mode 600"
  else fail "a published evidence file is mode 600" "mode is $EMODE"; fi
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
    # WHY THE EXPECTATIONS BELOW ARE COMPUTED RATHER THAN WRITTEN OUT —
    # FINDING-71.
    #
    # Three of these cases used to assert the operator's own deployment values
    # as string literals: gid 989, and the two /etc/scamwall/... bind sources.
    # That made them pass on exactly one machine. The first hosted run to
    # execute this suite failed all three, because CI points the same
    # definition at throwaway fixtures under RUNNER_TEMP with the runner's own
    # gid — which is the environment behaving exactly as designed.
    #
    # The case was never about the VALUES. Its subject, stated in the header
    # above, is whether the jq FILTERS pick the right fields out of what the
    # real Compose CLI emits, so that a drift between the canned fixture's
    # shape and Compose's actual rendering is caught. Pinning the values tested
    # the machine instead of the filter.
    #
    # So the expectation is resolved independently, by the shell, from the same
    # inputs Compose uses and in the same precedence order. That is not
    # circular: the program under test reaches the value through Compose's
    # renderer and a jq filter, and this reaches it by reading the environment
    # and the env-file directly. A filter that named the wrong field, or an
    # env-file that stopped being consulted, still fails the case.
    #
    # `user` keeps its literal. It is fixed in compose.yaml, is not
    # site-specific, and is the one value here a deployment must NOT be able to
    # move — so a literal is the correct assertion for it, and it passed in CI.
    resolve_site_var() { # <variable name> <compose.yaml default>
      # Reproduces `${NAME:-default}` precedence without asking the program
      # under test: an exported variable wins, then the --env-file's value,
      # then the default written into compose.yaml. Empty counts as unset,
      # exactly as `:-` treats it.
      local name="$1" default="$2" from_file=""
      if [ -n "${!name-}" ]; then printf '%s\n' "${!name}"; return 0; fi
      if [ -f "$CHECKOUT/deploy/compose/.env" ]; then
        from_file="$(sed -n "s/^[[:space:]]*${name}=//p" \
          "$CHECKOUT/deploy/compose/.env" | tail -n 1)"
      fi
      if [ -n "$from_file" ]; then printf '%s\n' "$from_file"; return 0; fi
      printf '%s\n' "$default"
    }

    EXPECT_GID="$(resolve_site_var SCAMWALL_SECRET_GID 65532)"
    EXPECT_CREDENTIAL_SOURCE="$(resolve_site_var SCAMWALL_SECRET_FILE /etc/scamwall/secrets/pihole_app_password)"
    EXPECT_CA_SOURCE="$(resolve_site_var SCAMWALL_CA_FILE /etc/scamwall/certs/pihole-ca.crt)"

    check_filter "the container user is read from the real resolved configuration" \
      '.services."scamwall".user' '65532:65532'
    check_filter "the supplementary group is read from the real resolved configuration" \
      '.services."scamwall".group_add[0] | tostring' "$EXPECT_GID"
    check_filter "the secret source is read from the real resolved configuration" \
      '.secrets.pihole_app_password.file' "$EXPECT_CREDENTIAL_SOURCE"
    check_filter "the CA bind source is read from the real resolved configuration" \
      '.services."scamwall".volumes[] | select(.target == "/etc/scamwall/certs/pihole-ca.crt") | .source' \
      "$EXPECT_CA_SOURCE"

    # The site variables must actually REACH the rendering. Without this, the
    # three cases above could pass while Compose ignored the environment
    # entirely and fell back to compose.yaml's defaults — the resolver would
    # fall back to the same defaults, and two wrongs would agree.
    #
    # So the definition is rendered a SECOND time with values chosen here, and
    # the render must show them. The values are deliberately unlike anything a
    # deployment would use, and no file has to exist: `compose config` renders,
    # it does not open bind sources. This runs identically on every host, so
    # the case count does not depend on what the environment happens to set —
    # a suite whose total moves with the machine is hard to hold to account.
    OVERRIDE_JSON="$ROOT/real-compose-config-overridden.json"
    if env SCAMWALL_SECRET_GID=4242 \
           SCAMWALL_SECRET_FILE=/nonexistent/test-only/secret \
           SCAMWALL_CA_FILE=/nonexistent/test-only/ca.crt \
           docker compose --env-file "$CHECKOUT/deploy/compose/.env" \
             -f "$CHECKOUT/deploy/compose/compose.yaml" config --format json \
             > "$OVERRIDE_JSON" 2>/dev/null; then
      check_override() { # <label> <filter> <expected>
        local got
        got="$(jq -er "$2" < "$OVERRIDE_JSON" 2>/dev/null)"
        if [ "$got" = "$3" ]; then pass "$1"; else fail "$1" "read '$got', expected '$3'"; fi
      }
      check_override "SCAMWALL_SECRET_GID reaches the rendered definition" \
        '.services."scamwall".group_add[0] | tostring' '4242'
      check_override "SCAMWALL_SECRET_FILE reaches the rendered definition" \
        '.secrets.pihole_app_password.file' '/nonexistent/test-only/secret'
      check_override "SCAMWALL_CA_FILE reaches the rendered definition" \
        '.services."scamwall".volumes[] | select(.target == "/etc/scamwall/certs/pihole-ca.crt") | .source' \
        '/nonexistent/test-only/ca.crt'
    else
      fail "the overridden definition renders" \
        "the real Compose CLI resolved the definition unmodified but not with overrides set"
    fi
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


# ==============================================================================
# 12. The five defects of the second review pass — FINDING-51 … FINDING-55
# ==============================================================================
#
# Each block asserts that the FORBIDDEN ACTION does not occur, not merely that
# the program printed a complaint about it. The distinction is the whole of
# FINDING-51: the superseded program printed an accurate complaint and then
# performed the action anyway.

state_has() { # <label> <extended regex over the state file>
  if grep -qE "$2" "$WORK/state.env" 2>/dev/null; then pass "$1"
  else fail "$1" "state.env did not match /$2/: $(tr '\n' '|' < "$WORK/state.env" 2>/dev/null)"; fi
}
state_lacks() { # <label> <extended regex over the state file>
  if grep -qE "$2" "$WORK/state.env" 2>/dev/null; then
    fail "$1" "state.env unexpectedly matched /$2/: $(tr '\n' '|' < "$WORK/state.env" 2>/dev/null)"
  else pass "$1"; fi
}

# --- FINDING-51: a failed pre-start assertion must PREVENT the start ----------
echo
echo "-- FINDING-51: no start after a failed isolation assertion --"

# Step B mounts no credential. The fake is told to report one mounted anyway,
# which is what an operator would see if the argument construction were wrong
# or the daemon did something unexpected.
setup_case iso-secret-mounted
build_ok && {
  reset_log
  : > "$FAKE_DIR/force-secret-mount"
  run_step probe --work-dir "$WORK"
  expect_rc_nonzero "step B fails when the credential-free probe has a credential mounted"
  expect_output "the mounted credential is reported"  'IS mounted'
  expect_output "the start is refused, in those words" 'was NOT started'
  expect_output "the refusal counts the failed assertions" 'pre-start isolation assertion'
  # THE assertion. Before the fix the program printed the two lines above and
  # then started the container regardless.
  log_lacks "the container is NEVER started"          '^start'
  log_has   "the container it refused to start is removed" '^rm -f cid'
  state_has "step B is recorded as failed"            '^STEP_STATUS_PROBE=failed$'
}

# Step C runs with --network none. The fake is told the created container has
# bridge networking, so the offline claim is false.
setup_case iso-network-wrong
build_ok && {
  reset_log
  printf 'bridge' > "$FAKE_DIR/force-network-mode"
  run_step secret --work-dir "$WORK"
  expect_rc_nonzero "step C fails when the offline probe turns out to have a network"
  expect_output "the observed network mode is named" "network mode is 'bridge', expected 'none'"
  expect_output "the start is refused"               'was NOT started'
  log_lacks "the container that would have opened the credential is NEVER started" '^start'
  log_has   "it is removed instead"                  '^rm -f cid'
}

# An assertion that cannot be EVALUATED is not permission to start either. The
# fake's inspect fails for a container it does not consider live.
setup_case iso-unprovable
build_ok && {
  reset_log
  : > "$FAKE_DIR/force-secret-mount"
  run_step probe --work-dir "$WORK"
  expect_rc_nonzero "an isolation assertion that fails blocks the start"
  log_lacks "nothing is started while isolation is unestablished" '^start'
}

# The version probe in step A is gated by the same rule.
setup_case iso-version-probe
preflight_ok && {
  reset_log
  : > "$FAKE_DIR/force-secret-mount"
  run_step build --work-dir "$WORK"
  expect_rc_nonzero "step A fails when its version probe has a credential mounted"
  expect_output "the version probe's start is refused" 'was NOT started'
  log_lacks "the version probe is never started"       '^start'
  state_lacks "a step A that refused to start its probe records no image id" '^IMAGE_ID='
}

# --- FINDING-52: completion is persisted only after checks AND cleanup --------
echo
echo "-- FINDING-52: a step that did not pass publishes nothing --"

setup_case persist-build-failed
preflight_ok && {
  printf '1' > "$FAKE_DIR/rc.build"
  run_step build --work-dir "$WORK"
  expect_rc_nonzero "a failing build fails"
  state_lacks "a failed step A records NO image id"   '^IMAGE_ID='
  state_has   "step A is recorded as failed"          '^STEP_STATUS_BUILD=failed$'
  # And the next step will not run off it.
  reset_log
  run_step probe --work-dir "$WORK"
  expect_rc_nonzero "step B refuses after a failed step A"
  expect_output "the refusal names step A's recorded status" 'step build is recorded as FAILED'
  log_lacks "nothing is created after a failed step A" '^create'
}

# A step whose checks all passed and whose CLEANUP failed is not a passed step.
setup_case persist-cleanup-failed
preflight_ok && {
  printf '1' > "$FAKE_DIR/rc.rm"
  run_step build --work-dir "$WORK"
  expect_rc_nonzero "a build whose cleanup failed does not pass"
  expect_output "the reason is stated as cleanup" 'REQUIRED CLEANUP FAILED'
  expect_output "the step status is explained"    'completion requires cleanup as well as checks'
  state_has   "step A is recorded as failed"      '^STEP_STATUS_BUILD=failed$'
  state_lacks "its image id is NOT published"     '^IMAGE_ID='
  run_step probe --work-dir "$WORK"
  expect_rc_nonzero "step B refuses after a step A whose cleanup failed"
}

# The runtime verifier failing is a check failure like any other, and it used to
# be the clearest case: IMAGE_ID was written three lines above the verdict.
setup_case persist-verifier-failed
preflight_ok && {
  printf '1' > "$FAKE_DIR/rc.verify"
  run_step build --work-dir "$WORK"
  expect_rc_nonzero "a build whose runtime verification failed does not pass"
  # The image RESOLVED — the id is known and was printed — and is then withheld
  # because the step did not pass. The operator is told so by name.
  expect_output "the image id is reported as resolved"   'IMAGE_ID=sha256:'
  expect_output "the withheld identities are named"      'IMAGE_ID — NOT RECORDED'
  expect_output "the reason is stated"                   'a later step must not run'
  state_lacks "the unverified image id is NOT published" '^IMAGE_ID='
  run_step probe --work-dir "$WORK"
  expect_rc_nonzero "step B refuses to run against an image step A did not verify"
}

setup_case persist-interrupted
build_ok && {
  reset_log
  : > "$FAKE_DIR/interrupt"
  run_step probe --work-dir "$WORK"
  expect_rc "an interrupted step exits with the signal's status" 143
  state_has "the interrupted step is recorded as interrupted, not failed" '^STEP_STATUS_PROBE=interrupted$'
  rm -f "$FAKE_DIR/interrupt"
  run_step status --work-dir "$WORK" --authorise-authenticated-read
  expect_rc_nonzero "a later step refuses after an interrupted prerequisite"
  expect_output "the refusal says INTERRUPTED, not FAILED" 'step probe was INTERRUPTED'
}

# A refusal AFTER the step began is neither passed nor failed: what it
# established is unknown, and it is refused in those words.
setup_case persist-indeterminate
build_ok && {
  printf '%s' "$OTHER_SHA" > "$FAKE_DIR/head-sha"
  run_step probe --work-dir "$WORK"
  expect_rc_nonzero "a step that refuses after beginning exits nonzero"
  expect_output "it is recorded as indeterminate" 'recorded as INDETERMINATE'
  state_has "the state file says indeterminate" '^STEP_STATUS_PROBE=indeterminate$'
  printf '%s' "$HEAD_SHA" > "$FAKE_DIR/head-sha"
  run_step status --work-dir "$WORK" --authorise-authenticated-read
  expect_rc_nonzero "a later step refuses an indeterminate prerequisite"
  expect_output "the refusal distinguishes it from a failure" 'recorded as INDETERMINATE'
}

# --- A failed rebuild must not leave an earlier success usable ---------------
echo
echo "-- a failed rebuild invalidates what the previous one established --"

setup_case rebuild-failed-invalidates
build_ok && {
  run_step probe --work-dir "$WORK"
  expect_rc_zero "step B passes against the first build"
  state_has "step B is recorded as passed" '^STEP_STATUS_PROBE=passed$'

  # The rebuild fails.
  printf '1' > "$FAKE_DIR/rc.build"
  reset_log
  run_step build --work-dir "$WORK"
  expect_rc_nonzero "the rebuild fails"
  expect_output "step B's acceptance is announced as invalidated" 'step probe was recorded as passed; that acceptance is INVALIDATED'
  state_lacks "the previous build's image id is gone"  '^IMAGE_ID='
  state_has   "step B is back to not_started"          '^STEP_STATUS_PROBE=not_started$'

  # And nothing downstream will run.
  reset_log
  run_step probe --work-dir "$WORK"
  expect_rc_nonzero "step B refuses after a failed rebuild"
  log_lacks "no container is created from the previous build's image" '^create'
  run_step status --work-dir "$WORK" --authorise-authenticated-read
  expect_rc_nonzero "step D refuses after a failed rebuild"
}

# --- FINDING-53: the authorisation flag is intent, never evidence -------------
echo
echo "-- FINDING-53: --authorise-authenticated-read is not proof of anything --"

setup_case authz-no-prereqs
build_ok && {
  reset_log
  run_step status --work-dir "$WORK" --authorise-authenticated-read
  expect_rc_nonzero "step D refuses with the flag when steps B and C have not run"
  expect_output "the refusal names the missing prerequisite" 'step probe has not been run'
  expect_output "the flag is explicitly rejected as evidence" 'an authorisation flag is not evidence'
  log_lacks "nothing is created"      '^create'
  log_lacks "nothing authenticates"   '^start'
}

setup_case authz-failed-prereq
build_ok && {
  : > "$FAKE_DIR/force-secret-mount"
  run_step probe --work-dir "$WORK"
  expect_rc_nonzero "step B fails"
  rm -f "$FAKE_DIR/force-secret-mount"
  reset_log
  run_step status --work-dir "$WORK" --authorise-authenticated-read
  expect_rc_nonzero "step D refuses with the flag after a FAILED step B"
  expect_output "the refusal names step B's status" 'step probe is recorded as FAILED'
  log_lacks "nothing authenticates after a failed prerequisite" '^start'
}

setup_case authz-secret-missing
probe_ok && {
  reset_log
  run_step status --work-dir "$WORK" --authorise-authenticated-read
  expect_rc_nonzero "step D refuses when step C has not run"
  expect_output "the refusal names step C" 'step secret has not been run'
  log_lacks "nothing authenticates" '^start'
}

# A prerequisite that passed against a DIFFERENT resolved deployment
# configuration is stale, and step D says so rather than inheriting it.
setup_case authz-stale-config
secret_ok && {
  reset_log
  # The deployment's resolved configuration changes between step C and step D.
  # Nothing about the change matters except that it is a change.
  sed 's/"pids_limit": 64/"pids_limit": 32/' "$FAKE_DIR/compose-config.json" > "$FAKE_DIR/c" \
    && mv "$FAKE_DIR/c" "$FAKE_DIR/compose-config.json"
  run_step status --work-dir "$WORK" --authorise-authenticated-read
  expect_rc_nonzero "step D refuses when the deployment configuration changed after step B and C"
  expect_output "the staleness is named"        'its acceptance is STALE'
  expect_output "the changed identity is named" 'different resolved deployment configuration'
  log_lacks "nothing authenticates against a deployment the prerequisites did not cover" '^start'
}

# The happy path still works, so the gate is not simply refusing everything.
setup_case authz-full-chain
secret_ok && {
  run_step status --work-dir "$WORK" --authorise-authenticated-read
  expect_rc_zero "step D runs when the flag AND all three prerequisites are satisfied"
  expect_output "the prerequisites are reported individually" 'prerequisite: step secret is recorded as passed'
  expect_output "the flag is reported as intent, not evidence" 'that flag is intent, not evidence'
  state_has "step D is recorded as passed" '^STEP_STATUS_STATUS=passed$'
}

# --- FINDING-54: raw captures are separated from shareable evidence -----------
echo
echo "-- FINDING-54: what may be shared is not the file the command wrote --"

setup_case evidence-separation
preflight_ok && {
  SECRET_TOKEN='hunter2-not-a-real-password'
  printf '1' > "$FAKE_DIR/rc.build"
  {
    printf '#5 [build 1/2] RUN something\n'
    printf 'PIHOLE_PASSWORD=%s\n' "$SECRET_TOKEN"
    printf '#5 ERROR: process did not complete successfully\n'
  } > "$FAKE_DIR/build-output"
  run_step build --work-dir "$WORK"
  expect_rc_nonzero "the failing build fails"

  if [ -f "$WORK/raw/build.log" ]; then pass "the raw capture exists"
  else fail "the raw capture exists" "$WORK/raw/build.log is missing"; fi
  if [ -f "$WORK/evidence/build.log" ]; then pass "a sanitized copy exists beside it"
  else fail "a sanitized copy exists beside it" "$WORK/evidence/build.log is missing"; fi

  # The raw file is the command's own output — that is what makes it raw, and
  # what makes it unsafe to return.
  if grep -qF "$SECRET_TOKEN" "$WORK/raw/build.log" 2>/dev/null; then
    pass "the RAW capture is unmodified, and holds the credential-shaped value"
  else
    fail "the RAW capture is unmodified, and holds the credential-shaped value" "the token is absent from the raw log"
  fi
  # The shareable copy does not.
  if grep -qF "$SECRET_TOKEN" "$WORK/evidence/build.log" 2>/dev/null; then
    fail "the SHAREABLE copy retains no credential material" "the token survived into $WORK/evidence/build.log"
  else
    pass "the SHAREABLE copy retains no credential material"
  fi
  if grep -q '<redacted' "$WORK/evidence/build.log" 2>/dev/null; then
    pass "the shareable copy records that something was redacted"
  else
    fail "the shareable copy records that something was redacted" "no redaction marker in the evidence copy"
  fi
  # The two directories say what they are, in the directories themselves,
  # because an operator collecting evidence reads the directory and not this
  # program's terminal output from an hour ago.
  if grep -q 'DO NOT SHARE' "$WORK/raw/README-DO-NOT-SHARE.txt" 2>/dev/null; then
    pass "the raw directory carries its own DO-NOT-SHARE marker"
  else
    fail "the raw directory carries its own DO-NOT-SHARE marker" "marker missing or empty"
  fi
  if grep -q 'deny-by-pattern' "$WORK/evidence/README.txt" 2>/dev/null; then
    pass "the evidence directory states the filter's deny-by-pattern limit"
  else
    fail "the evidence directory states the filter's deny-by-pattern limit" "limit not stated"
  fi
  # The resolved deployment configuration holds the deployment's real paths and
  # belongs in raw/, not in the directory the operator is told to return.
  if [ -f "$WORK/evidence/compose-config.json" ]; then
    fail "the resolved configuration is not published as evidence" "it is in evidence/"
  else
    pass "the resolved configuration is not published as evidence"
  fi
}

# --- FINDING-55: closeout examines the identities of the steps that ran -------
echo
echo "-- FINDING-55: step Z looks for the EARLIER steps' resources --"

setup_case closeout-finds-leftovers
build_ok && {
  # Step B leaks a container: its removal fails, so it really is still there.
  printf '1' > "$FAKE_DIR/rc.rm"
  run_step probe --work-dir "$WORK"
  expect_rc_nonzero "step B reports its own cleanup failure"
  LEFTOVER="$(grep -m1 . "$FAKE_DIR/live" 2>/dev/null)"
  if [ -n "$LEFTOVER" ]; then pass "a container really does remain on the fake daemon"
  else fail "a container really does remain on the fake daemon" "the fake's live list is empty"; fi

  # The register tells step Z which project to look under; the fake answers
  # that query with the leftover.
  rm -f "$FAKE_DIR/rc.rm"
  printf '%s\n' "$LEFTOVER" > "$FAKE_DIR/project-containers"
  run_step closeout --work-dir "$WORK"
  expect_rc_nonzero "step Z FAILS when an earlier step's container remains"
  expect_output "the leftover is attributed to the step that created it" 'containers of step probe REMAIN'
  expect_output "the leftover identifier is printed"                     "$LEFTOVER"
  expect_no_output "step Z does not report a clean host"                 'no container of step probe remains'
}

# The tautology in its own right: with nothing recorded, step Z must not
# report a clean result. Before the fix this printed PASS three times.
setup_case closeout-no-register
preflight_ok && {
  run_step closeout --work-dir "$WORK"
  expect_rc_nonzero "step Z is not a pass when no step recorded an invocation"
  expect_output "the result is stated as unproven" 'leftovers are UNPROVEN'
  expect_no_output "no clean-host claim is made"   'no container of'
}

setup_case closeout-clean
build_ok && {
  run_step probe --work-dir "$WORK"
  expect_rc_zero "step B passes"
  : > "$FAKE_DIR/project-containers"
  run_step closeout --work-dir "$WORK"
  expect_output "step Z names the steps it searched for"  'searching for resources of step build'
  expect_output "step Z searches for step B as well"      'searching for resources of step probe'
  expect_output "a genuinely clean result names the step" 'no container of step probe remains'
  expect_no_output "step Z does not search for itself"    'searching for resources of step closeout'
}

# An enumeration that could not run is not an empty result.
setup_case closeout-enumeration-fails
build_ok && {
  printf '1' > "$FAKE_DIR/rc.project-query"
  run_step closeout --work-dir "$WORK"
  expect_rc_nonzero "step Z fails when it cannot enumerate"
  expect_output "the failure is reported as unproven" 'leftovers are UNPROVEN'
  expect_no_output "no clean-host claim is made"      'no container of step build remains'
}

# --- FINDING-56: the privileged work directory and state file ----------------
echo
echo "-- FINDING-56: the work directory and state file are validated --"

setup_case wd-symlink
mkdir -p "$ROOT/real-target-$$"
# Whatever the mode is here, it must be the mode afterwards. `mkdir -p` on an
# existing symlink succeeds, and the chmod 700 that used to follow it landed on
# THIS directory — a privileged chmod of a path the operator never named.
MODE_BEFORE="$(stat -c '%a' "$ROOT/real-target-$$" 2>/dev/null)"
ln -sfn "$ROOT/real-target-$$" "$WORK"
run_step preflight --expected-commit "$HEAD_SHA" --work-dir "$WORK"
expect_rc_nonzero "a work directory that is a symlink is refused at creation"
expect_output "the refusal names the symlink" 'is a symbolic link'
MODE_AFTER="$(stat -c '%a' "$ROOT/real-target-$$" 2>/dev/null)"
if [ "$MODE_AFTER" = "$MODE_BEFORE" ]; then
  pass "the symlink's TARGET was not chmod-ed"
else
  fail "the symlink's TARGET was not chmod-ed" "mode went from $MODE_BEFORE to $MODE_AFTER"
fi
if [ -e "$ROOT/real-target-$$/state.env" ]; then
  fail "nothing was written into the symlink's target" "state.env was created there"
else
  pass "nothing was written into the symlink's target"
fi
rm -f "$WORK"

setup_case wd-symlink-open
mkdir -p "$ROOT/opened-target-$$" && chmod 700 "$ROOT/opened-target-$$"
: > "$ROOT/opened-target-$$/state.env" && chmod 600 "$ROOT/opened-target-$$/state.env"
ln -sfn "$ROOT/opened-target-$$" "$WORK"
run_step build --work-dir "$WORK"
expect_rc_nonzero "a later step refuses a work directory reached through a symlink"
expect_output "the refusal names the symlink" 'is a symbolic link'
rm -f "$WORK"

setup_case wd-state-symlink
preflight_ok && {
  printf 'EXPECTED_COMMIT=%s\n' "$OTHER_SHA" > "$ROOT/planted-state-$$"
  chmod 600 "$ROOT/planted-state-$$"
  rm -f "$WORK/state.env"
  ln -sfn "$ROOT/planted-state-$$" "$WORK/state.env"
  run_step build --work-dir "$WORK"
  expect_rc_nonzero "a state file that is a symlink is refused"
  expect_output "the refusal names the state file" 'the state file is a symbolic link'
  expect_no_output "the planted identity is never adopted" "$OTHER_SHA"
}

setup_case wd-state-hardlinked
preflight_ok && {
  ln "$WORK/state.env" "$ROOT/second-name-$$" 2>/dev/null && {
    run_step build --work-dir "$WORK"
    expect_rc_nonzero "a state file with a second name is refused"
    expect_output "the refusal says why a second name matters" 'its content is not solely this run'
  }
  rm -f "$ROOT/second-name-$$"
}

setup_case wd-state-mode
preflight_ok && {
  chmod 644 "$WORK/state.env"
  run_step build --work-dir "$WORK"
  expect_rc_nonzero "a state file that is not 600 is refused"
  expect_output "the observed mode is named" 'the state file is mode 644, not 600'
}

setup_case wd-writable-ancestor
PARENT="$ROOT/loose-parent-$$"
mkdir -p "$PARENT" && chmod 777 "$PARENT"
mkdir -p "$PARENT/w" && chmod 700 "$PARENT/w"
run_step preflight --expected-commit "$HEAD_SHA" --work-dir "$PARENT/w"
expect_rc_nonzero "a work directory inside a world-writable directory is refused"
expect_output "the ancestor is named"        "$PARENT"
expect_output "the reason is substitution"   'could be replaced underneath this run'
chmod 755 "$PARENT"

setup_case wd-sticky-ancestor-allowed
# /tmp is 1777. The sticky bit is why mktemp -d is acceptable and a plain 0777
# directory is not, so the rule must not reject the ordinary case.
run_step preflight --expected-commit "$HEAD_SHA"
expect_rc_zero "a work directory under a sticky world-writable directory (mktemp) is accepted"
expect_output "the directory is reported as validated" 'no ancestor another account can write'

# The ownership comparison cannot be exercised as an unprivileged account
# against a directory owned by someone else, because such a directory cannot be
# created here. It is exercised against a shimmed `id`, which is the other side
# of the same comparison: the directory is ours and the running uid is not.
setup_case wd-foreign-owner
mkdir -p "$WORK" && chmod 700 "$WORK" && : > "$WORK/state.env" && chmod 600 "$WORK/state.env"
cat > "$BIN/id" <<'ID_EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "-u" ]; then printf '4242\n'; exit 0; fi
exec /usr/bin/id "$@"
ID_EOF
chmod +x "$BIN/id"
run_step build --work-dir "$WORK"
expect_rc_nonzero "a work directory not owned by the account running the step is refused"
expect_output "both uids are named" 'not by uid 4242 which is running this step'
rm -f "$BIN/id"

setup_case wd-capture-symlink
preflight_ok && {
  ln -sfn "$ROOT/capture-target-$$" "$WORK/raw/build.log"
  run_step build --work-dir "$WORK"
  expect_rc_nonzero "a capture file that is a symlink is refused"
  expect_output "the refusal names the capture file" 'the capture file is a symbolic link'
  if [ -e "$ROOT/capture-target-$$" ]; then
    fail "the symlink's target was not created or truncated" "$ROOT/capture-target-$$ exists"
  else
    pass "the symlink's target was not created or truncated"
  fi
}

setup_case wd-raw-symlink
preflight_ok && {
  rm -rf "$WORK/raw"
  ln -sfn "$ROOT/raw-target-$$" "$WORK/raw"
  run_step build --work-dir "$WORK"
  expect_rc_nonzero "a raw-capture directory that is a symlink is refused"
  expect_output "the refusal names it" 'the raw-capture directory is a symbolic link'
}

# --- The state machine is visible in the state file --------------------------
echo
echo "-- the recorded step states --"

setup_case states-recorded
preflight_ok && {
  state_has "preflight records itself as passed" '^STEP_STATUS_PREFLIGHT=passed$'
  state_has "preflight records the commit it passed against" "^STEP_COMMIT_PREFLIGHT=$HEAD_SHA\$"
  run_step build --work-dir "$WORK"
  expect_rc_zero "step A passes"
  state_has "step A records itself as passed"   '^STEP_STATUS_BUILD=passed$'
  state_has "step A records the image it built" "^STEP_IMAGE_BUILD=$IMAGE_A\$"
  state_has "step A publishes the image id"     "^IMAGE_ID=$IMAGE_A\$"
  run_step probe --work-dir "$WORK"
  expect_rc_zero "step B passes"
  state_has "step B records the configuration digest it passed against" '^STEP_CONFIG_PROBE=[0-9a-f]{64}$'
  state_has "the invocation register accumulates across steps" '^HANDOFF_INVOCATIONS=build:[0-9a-f]{32}:[^ ]+ probe:[0-9a-f]{32}:'
}

# =============================================================================
# FINDING-57 … FINDING-59 — the terminal record, its bindings, and concurrency
# =============================================================================
#
# The reviewer exercised the functions themselves rather than the program, and
# found three things:
#
#   * record_step_outcome wrote STEP_STATUS=passed BEFORE the identity bindings
#     and the staged results, each through its own rename. An interruption in
#     that window persisted a pass carrying nothing.
#   * assert_prereq_identities returned 0 when the commit matched and the image
#     and configuration bindings were absent, because it compared only the
#     components both sides happened to have.
#   * nothing serialised two invocations sharing one work directory.
#
# The cases below reproduce all three from OUTSIDE the program — no daemon, no
# sourcing of its internals — and assert the consequences, not the wording: no
# dependent container is created, none is started, and nothing authenticates.

# --- helpers for these cases --------------------------------------------------

# state_drop / state_set — edit a recorded state file the way an interruption
# or an older revision of the program would have left it. Mode and link count
# are preserved, because the handoff checks both.
state_drop() { # <key>
  grep -v "^$1=" "$WORK/state.env" > "$WORK/state.env.edit" 2>/dev/null
  cat "$WORK/state.env.edit" > "$WORK/state.env"
  rm -f "$WORK/state.env.edit"
  chmod 600 "$WORK/state.env"
}
state_set() { # <key> <value>
  state_drop "$1"
  printf '%s=%s\n' "$1" "$2" >> "$WORK/state.env"
  chmod 600 "$WORK/state.env"
}

BG_PID=0
run_step_bg() { # <outfile> <args...> — sets BG_PID
  local out="$1"; shift
  env -u SCAMWALL_CA_FILE -u SCAMWALL_SECRET_FILE -u SCAMWALL_CONFIG \
      -u SCAMWALL_FEED -u SCAMWALL_IMAGE -u SCAMWALL_EXPECTED_IMAGE_ID \
      -u SCAMWALL_VERSION -u SCAMWALL_COMMIT -u SCAMWALL_BUILD_DATE \
      -u PIHOLE_HOST_IP -u SCAMWALL_SECRET_GID \
      PATH="$BIN:$PATH" FAKE_DIR="$FAKE_DIR" \
      "$CHECKOUT/scripts/operator-handoff.sh" "$@" > "$out" 2>&1 &
  BG_PID=$!
}

wait_for_file() { # <path> — bounded, so a broken case fails instead of hanging
  local i=0
  while [ ! -f "$1" ] && [ "$i" -lt 300 ]; do sleep 0.05; i=$((i + 1)); done
  [ -f "$1" ]
}

echo
echo "-- FINDING-57: a terminal record is published whole, or not at all --"

# The invariant, stated directly and checked against EVERY version of the state
# file that ever existed during a real run of steps 0, A and B.
#
# Under the previous code the very first of those versions to carry
# STEP_STATUS_BUILD=passed carried nothing else, because the status and the
# bindings were separate renames. That is the defect, and this is the assertion
# that names it.
setup_case atomic-publication
printf 'record' > "$FAKE_DIR/mv-mode"
preflight_ok && {
  run_step build --work-dir "$WORK"
  expect_rc_zero "step A passes with the state file under observation"
  run_step probe --work-dir "$WORK"
  expect_rc_zero "step B passes with the state file under observation"

  VERSIONS="$FAKE_DIR/state-versions"
  NVER="$(find "$VERSIONS" -type f 2>/dev/null | wc -l)"
  if [ "${NVER:-0}" -ge 3 ]; then
    pass "every state-file version installed during the run was captured ($NVER)"
  else
    fail "every state-file version installed during the run was captured" "only ${NVER:-0} captured"
  fi

  # For each step, the keys a `passed` record of that step must carry.
  INCOMPLETE=""
  SAW_PASS=""
  for v in "$VERSIONS"/*; do
    [ -f "$v" ] || continue
    for spec in "PREFLIGHT:STEP_COMMIT_PREFLIGHT" \
                "BUILD:STEP_COMMIT_BUILD STEP_IMAGE_BUILD IMAGE_ID BUILD_COMMIT" \
                "PROBE:STEP_COMMIT_PROBE STEP_IMAGE_PROBE STEP_CONFIG_PROBE"; do
      s="${spec%%:*}"
      grep -qx "STEP_STATUS_${s}=passed" "$v" || continue
      SAW_PASS="$SAW_PASS $s"
      for k in ${spec#*:}; do
        grep -q "^${k}=." "$v" || INCOMPLETE="$INCOMPLETE $(basename "$v"):${s}:${k}"
      done
    done
  done
  if [ -z "$INCOMPLETE" ]; then
    pass "no version of the state file ever recorded a pass without every identity it was bound to"
  else
    fail "no version of the state file ever recorded a pass without every identity it was bound to" \
         "incomplete versions:$INCOMPLETE"
  fi
  # Without this the assertion above would also hold for a run that never
  # recorded a pass at all.
  case "$SAW_PASS" in
    *PREFLIGHT*) case "$SAW_PASS" in
                   *BUILD*) case "$SAW_PASS" in
                              *PROBE*) pass "the assertion is not vacuous: passes for steps 0, A and B were observed being published" ;;
                              *) fail "the assertion is not vacuous" "no PROBE pass was ever installed:$SAW_PASS" ;;
                            esac ;;
                   *) fail "the assertion is not vacuous" "no BUILD pass was ever installed:$SAW_PASS" ;;
                 esac ;;
    *) fail "the assertion is not vacuous" "no PREFLIGHT pass was ever installed:$SAW_PASS" ;;
  esac
}

# Killed at the rename that would have published the pass. Nothing of that step
# survives — not the status, and not the identities it staged.
setup_case interrupted-before-publication
preflight_ok && {
  printf 'kill-before-pass' > "$FAKE_DIR/mv-mode"
  printf 'STEP_STATUS_BUILD=passed' > "$FAKE_DIR/mv-key"
  run_step build --work-dir "$WORK"
  expect_rc_nonzero "a build killed at the moment of publication does not report success"
  if [ -f "$FAKE_DIR/killed-before-publication" ]; then
    pass "the interruption was delivered at the publishing rename"
  else
    fail "the interruption was delivered at the publishing rename" "the publishing rename was never reached"
  fi
  rm -f "$FAKE_DIR/mv-mode"
  state_lacks "no pass was persisted"                    '^STEP_STATUS_BUILD=passed$'
  state_lacks "no image binding was persisted"           '^STEP_IMAGE_BUILD='
  state_lacks "no commit binding was persisted"          '^STEP_COMMIT_BUILD='
  state_lacks "no image id was published"                '^IMAGE_ID='
  state_has   "the step is still recorded as running"    '^STEP_STATUS_BUILD=running$'
  reset_log
  run_step probe --work-dir "$WORK"
  expect_rc_nonzero "step B refuses to run on the interrupted step A"
  expect_output "the refusal says the step never recorded a verdict" 'recorded as RUNNING'
  log_lacks "no container was created for step B"  '^create'
  log_lacks "no container was started for step B"  '^start'
}

# Killed immediately AFTER that rename. The single rename is the whole
# publication, so what survives is the COMPLETE record — status, bindings and
# staged results together — and step B may legitimately proceed on it.
setup_case interrupted-after-publication
preflight_ok && {
  printf 'kill-after-pass' > "$FAKE_DIR/mv-mode"
  printf 'STEP_STATUS_BUILD=passed' > "$FAKE_DIR/mv-key"
  run_step build --work-dir "$WORK"
  if [ -f "$FAKE_DIR/killed-after-publication" ]; then
    pass "the interruption was delivered immediately after the publishing rename"
  else
    fail "the interruption was delivered immediately after the publishing rename" "it was never reached"
  fi
  rm -f "$FAKE_DIR/mv-mode"
  state_has "the pass survived"              '^STEP_STATUS_BUILD=passed$'
  state_has "so did the commit binding"      "^STEP_COMMIT_BUILD=$HEAD_SHA\$"
  state_has "so did the image binding"       "^STEP_IMAGE_BUILD=$IMAGE_A\$"
  state_has "so did the staged image id"     "^IMAGE_ID=$IMAGE_A\$"
  run_step probe --work-dir "$WORK"
  expect_rc_zero "step B proceeds on a record that was published whole"
}

# A rename that FAILS leaves the previous version in place, is reported, and
# exits nonzero — it does not leave a half-written file or a stray temporary.
setup_case failed-state-write
preflight_ok && {
  printf 'fail-on-pass' > "$FAKE_DIR/mv-mode"
  printf 'STEP_STATUS_BUILD=passed' > "$FAKE_DIR/mv-key"
  run_step build --work-dir "$WORK"
  expect_rc_nonzero "a build whose state write fails does not report success"
  expect_output "the failure is named" 'could not be installed'
  rm -f "$FAKE_DIR/mv-mode"
  state_lacks "no pass was persisted by a failed write"  '^STEP_STATUS_BUILD=passed$'
  state_lacks "no image id leaked through the failure"   '^IMAGE_ID='
  LEFTOVER="$(find "$WORK" -maxdepth 1 -name 'state.env.*' 2>/dev/null | wc -l)"
  if [ "${LEFTOVER:-1}" -eq 0 ]; then
    pass "the failed write left no temporary state file behind"
  else
    fail "the failed write left no temporary state file behind" "$LEFTOVER remain"
  fi
}

echo
echo "-- FINDING-58: a pass is usable only WITH the identities it was bound to --"

# The reviewer's case exactly: the commit still matches, and the image binding
# is gone. The old rule compared the commit, found it equal, reported "step
# build passed against exactly these identities (source commit)" and returned 0.
setup_case passed-record-missing-image
build_ok && {
  state_drop STEP_IMAGE_BUILD
  reset_log
  run_step probe --work-dir "$WORK"
  expect_rc_nonzero "a pass whose image binding is missing is refused"
  expect_output "the record is called incomplete" 'INCOMPLETE pass record'
  expect_output "the missing binding is named"    'STEP_IMAGE_BUILD'
  log_lacks "no container was created from an unbound acceptance" '^create'
  log_lacks "no container was started from an unbound acceptance" '^start'
}

setup_case passed-record-empty-image
build_ok && {
  state_set STEP_IMAGE_BUILD ""
  reset_log
  run_step probe --work-dir "$WORK"
  expect_rc_nonzero "a pass whose image binding is recorded EMPTY is refused"
  expect_output "empty is refused in the same words as absent" 'missing, empty or unreadable'
  log_lacks "no container was created" '^create'
  log_lacks "no container was started" '^start'
}

setup_case passed-record-malformed-image
build_ok && {
  state_set STEP_IMAGE_BUILD "sha256:not-a-digest"
  reset_log
  run_step probe --work-dir "$WORK"
  expect_rc_nonzero "a pass whose image binding is malformed is refused"
  expect_output "the record is called corrupt" 'CORRUPT pass record'
  log_lacks "no container was created" '^create'
  log_lacks "no container was started" '^start'
}

setup_case passed-record-truncated-commit
build_ok && {
  state_set STEP_COMMIT_BUILD "1111111"
  reset_log
  run_step probe --work-dir "$WORK"
  expect_rc_nonzero "an abbreviated commit binding is refused, not compared"
  expect_output "the record is called corrupt" 'CORRUPT pass record'
  log_lacks "no container was created" '^create'
  log_lacks "no container was started" '^start'
}

# Step D is the one that authenticates, and step B's configuration binding is
# one of the three it must be able to compare. Its absence must stop the
# authenticated operation before anything is sent.
setup_case probe-config-binding-missing
secret_ok && {
  state_drop STEP_CONFIG_PROBE
  reset_log
  run_step status --work-dir "$WORK" --authorise-authenticated-read
  expect_rc_nonzero "step D refuses when step B's configuration binding is absent"
  expect_output "the record is called incomplete" 'INCOMPLETE pass record'
  expect_output "the missing binding is named"    'STEP_CONFIG_PROBE'
  log_lacks "no container was created, so nothing authenticated" '^create'
  log_lacks "no container was started, so nothing authenticated" '^start'
}

setup_case secret-image-binding-missing
secret_ok && {
  state_drop STEP_IMAGE_SECRET
  reset_log
  run_step status --work-dir "$WORK" --authorise-authenticated-read
  expect_rc_nonzero "step D refuses when step C's image binding is absent"
  log_lacks "no container was created, so nothing authenticated" '^create'
  log_lacks "no container was started, so nothing authenticated" '^start'
}

echo
echo "-- FINDING-58: a rebuild that does not finish leaves nothing usable --"

setup_case rebuild-interrupted-invalidates
secret_ok && {
  reset_log
  : > "$FAKE_DIR/build-interrupt"
  run_step build --work-dir "$WORK"
  expect_rc_nonzero "an interrupted rebuild does not pass"
  rm -f "$FAKE_DIR/build-interrupt"
  state_lacks "no image id survives an interrupted rebuild"        '^IMAGE_ID='
  state_has   "step B's acceptance was voided before the rebuild"  '^STEP_STATUS_PROBE=not_started$'
  state_has   "step C's acceptance was voided before the rebuild"  '^STEP_STATUS_SECRET=not_started$'
  state_lacks "step B's image binding went with it"                '^STEP_IMAGE_PROBE='
  state_lacks "step C's image binding went with it"                '^STEP_IMAGE_SECRET='
  state_lacks "step B's configuration binding went with it"        '^STEP_CONFIG_PROBE='
  reset_log
  run_step status --work-dir "$WORK" --authorise-authenticated-read
  expect_rc_nonzero "step D refuses after an interrupted rebuild"
  log_lacks "no container was created after an interrupted rebuild" '^create'
  log_lacks "no container was started after an interrupted rebuild" '^start'
}

# The same, with the rebuild killed at the publishing rename rather than
# signalled inside the build: the invalidation is already on disk, and the
# rebuild's own pass never reaches it.
setup_case rebuild-killed-at-publication
secret_ok && {
  printf 'kill-before-pass' > "$FAKE_DIR/mv-mode"
  printf 'STEP_STATUS_BUILD=passed' > "$FAKE_DIR/mv-key"
  reset_log
  run_step build --work-dir "$WORK"
  expect_rc_nonzero "a rebuild killed at publication does not pass"
  rm -f "$FAKE_DIR/mv-mode"
  state_lacks "no image id survives it"                     '^IMAGE_ID='
  state_lacks "no image binding survives it"                '^STEP_IMAGE_BUILD='
  state_lacks "no commit binding survives it"               '^STEP_COMMIT_BUILD='
  state_has   "step B's acceptance is still voided"         '^STEP_STATUS_PROBE=not_started$'
  state_has   "step C's acceptance is still voided"         '^STEP_STATUS_SECRET=not_started$'
  reset_log
  run_step status --work-dir "$WORK" --authorise-authenticated-read
  expect_rc_nonzero "step D refuses after a rebuild killed at publication"
  log_lacks "no container was created" '^create'
  log_lacks "no container was started" '^start'
}

echo
echo "-- FINDING-59: one invocation at a time, per work directory --"

setup_case lock-external-holder
preflight_ok && {
  ( flock -w 10 200 || exit 1
    : > "$FAKE_DIR/holder-ready"
    i=0
    while [ ! -f "$FAKE_DIR/holder-release" ] && [ "$i" -lt 300 ]; do sleep 0.05; i=$((i + 1)); done
  ) 200>>"$WORK/.handoff.lock" &
  HOLDER=$!
  if wait_for_file "$FAKE_DIR/holder-ready"; then
    pass "another process holds the work directory's lock"
    reset_log
    run_step build --work-dir "$WORK"
    expect_rc_nonzero "a step refuses to run while another invocation holds the lock"
    expect_output "the refusal explains what would race" 'holds its lock'
    log_lacks "no build was started while the lock was held" '^build'
    log_lacks "no container was created while the lock was held" '^create'
  else
    fail "another process holds the work directory's lock" "the holder never acquired it"
  fi
  : > "$FAKE_DIR/holder-release"
  wait "$HOLDER" 2>/dev/null
  reset_log
  run_step build --work-dir "$WORK"
  expect_rc_zero "the step runs once the lock is released"
}

# Held for the DURATION of the step, not merely taken at its start: the
# concurrent invocation is refused while the first is midway through its build.
setup_case lock-held-through-step
preflight_ok && {
  : > "$FAKE_DIR/build-blocks"
  BGOUT="$FAKE_DIR/bg-build.out"
  run_step_bg "$BGOUT" build --work-dir "$WORK"
  BGPID="$BG_PID"
  if wait_for_file "$FAKE_DIR/build-entered"; then
    pass "the first invocation is inside its build, holding the lock"
    run_step probe --work-dir "$WORK"
    expect_rc_nonzero "a second invocation is refused mid-step"
    expect_output "the refusal names the running invocation" 'holds its lock'
  else
    fail "the first invocation is inside its build, holding the lock" "it never entered the fake build"
  fi
  : > "$FAKE_DIR/build-release"
  wait "$BGPID"; BGRC=$?
  if [ "$BGRC" -eq 0 ]; then
    pass "the invocation that held the lock completed normally"
  else
    fail "the invocation that held the lock completed normally" "rc=$BGRC: $(tail -6 "$BGOUT" | tr '\n' '|')"
  fi
  state_has "and its record is complete" "^STEP_IMAGE_BUILD=$IMAGE_A\$"
}

# A lock is a file this program creates in a directory it has already
# established only this account can write. It must still refuse to open one
# through a symlink, or the check would be exactly the hole FINDING-56 closed
# for the state file.
setup_case lock-symlink
preflight_ok && {
  rm -f "$WORK/.handoff.lock"
  ln -sfn "$ROOT/lock-target-$$" "$WORK/.handoff.lock"
  run_step build --work-dir "$WORK"
  expect_rc_nonzero "a lock file that is a symlink is refused"
  expect_output "the refusal names it" 'work-directory lock file is a symbolic link'
  if [ -e "$ROOT/lock-target-$$" ]; then
    fail "nothing was created through the symlink" "the target exists"
  else
    pass "nothing was created through the symlink"
  fi
}
echo
echo "=============================================="
printf ' %d tests, %d failed\n' "$TESTS" "$FAILURES"
if [ "$FAILURES" -gt 0 ]; then
  echo " RESULT: operator-handoff regression tests FAILED"
  exit 1
fi
echo " all operator-handoff regression tests passed"
exit 0
