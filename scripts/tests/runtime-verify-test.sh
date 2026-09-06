#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
#
# runtime-verify-test.sh — regression tests for container-runtime-verify.sh.
#
# Every defect these tests cover was a FALSE PASS: the verifier reported a
# security property as satisfied when it had not actually been observed. A
# test here therefore asserts that a broken world produces a NONZERO exit, not
# merely that it prints something.
#
# The tests need no Docker daemon and no network. `docker` is replaced by a
# scripted fake whose responses are files on disk, so each failure mode —
# a failed create, a failed inspect, unparseable JSON, a mismatched image —
# can be reproduced exactly and cheaply.
#
# The verifier under test is copied into a synthetic checkout so the .env it
# reads is controlled by the test rather than by the operator's real one. That
# also exercises the "derive the repository root from the script's location"
# path that lets the operator run it without git.
#
# Exit status: 0 when every case passes.

set -uo pipefail

TESTS=0; FAILURES=0
pass() { printf '\033[32mok\033[0m   %s\n' "$1"; TESTS=$((TESTS + 1)); }
fail() { printf '\033[31mFAIL\033[0m %s\n' "$1"; printf '       %s\n' "$2"; TESTS=$((TESTS + 1)); FAILURES=$((FAILURES + 1)); }

SRC_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)" || exit 2
REPO="$(cd -- "$SRC_DIR/../.." >/dev/null 2>&1 && pwd -P)" || exit 2
VERIFIER="$REPO/scripts/container-runtime-verify.sh"
[ -f "$VERIFIER" ] || { printf 'fatal: verifier not found: %s\n' "$VERIFIER" >&2; exit 2; }

ROOT="$(mktemp -d)" || exit 2
trap 'rm -rf "$ROOT"' EXIT

TEST_GID="4242"
IMAGE_ID="sha256:1111111111111111111111111111111111111111111111111111111111111111"
OTHER_ID="sha256:2222222222222222222222222222222222222222222222222222222222222222"

# --- Synthetic checkout -------------------------------------------------------
CHECKOUT="$ROOT/checkout"
mkdir -p "$CHECKOUT/scripts" "$CHECKOUT/container" "$CHECKOUT/deploy/compose"
cp "$VERIFIER" "$CHECKOUT/scripts/container-runtime-verify.sh"
chmod +x "$CHECKOUT/scripts/container-runtime-verify.sh"
cp "$REPO/container/Dockerfile" "$CHECKOUT/container/Dockerfile"
cp "$REPO/deploy/compose/compose.yaml" "$CHECKOUT/deploy/compose/compose.yaml"
printf 'SCAMWALL_SECRET_GID=%s\nPIHOLE_HOST_IP=host-gateway\n' "$TEST_GID" > "$CHECKOUT/deploy/compose/.env"

# --- Fake docker --------------------------------------------------------------
BIN="$ROOT/bin"
mkdir -p "$BIN"
cat > "$BIN/docker" <<'FAKE_EOF'
#!/usr/bin/env bash
D="$FAKE_DIR"
printf '%s\n' "$*" >> "$D/log"
rc_for() { if [ -f "$D/rc.$1" ]; then cat "$D/rc.$1"; else echo 0; fi; }

if [ "${1:-}" = "compose" ]; then
  op=""
  for a in "$@"; do
    case "$a" in create|ps|down|version) op="$a"; break ;; esac
  done
  case "$op" in
    version) exit "$(rc_for compose-version)" ;;
    create)
      r="$(rc_for compose-create)"
      [ "$r" -ne 0 ] && printf 'Error response from daemon: create refused (fake)\n' >&2
      exit "$r" ;;
    ps)
      r="$(rc_for compose-ps)"; [ "$r" -ne 0 ] && exit "$r"
      cat "$D/ps-aq" 2>/dev/null; exit 0 ;;
    down) exit 0 ;;
    *) exit 0 ;;
  esac
fi

case "${1:-}" in
  info) exit "$(rc_for info)" ;;
  image)
    r="$(rc_for image-inspect)"; [ "$r" -ne 0 ] && exit "$r"
    cat "$D/image-inspect.json"; exit 0 ;;
  history)
    r="$(rc_for history)"
    if [ "$r" -ne 0 ]; then
      # Benign, non-credential error text on STDOUT. A verifier that ignored the
      # exit status would see non-empty output, match no pattern, and PASS.
      printf 'Error response from daemon: no such image\n'
      exit "$r"
    fi
    cat "$D/history.txt"; exit 0 ;;
  create)
    r="$(rc_for create)"; [ "$r" -ne 0 ] && exit "$r"
    cat "$D/create-id"; exit 0 ;;
  export)
    r="$(rc_for export)"; [ "$r" -ne 0 ] && exit "$r"
    cat "$D/export.tar"; exit 0 ;;
  inspect)
    r="$(rc_for inspect)"; [ "$r" -ne 0 ] && exit "$r"
    cat "$D/container.json"; exit 0 ;;
  rm) exit 0 ;;
  *) exit 0 ;;
esac
FAKE_EOF
chmod +x "$BIN/docker"

# A git that always refuses, as it would for root in a scamwall-owned tree.
# Any invocation is recorded; the operator path must never call it.
cat > "$BIN/git" <<'GIT_EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_DIR/git-log"
printf 'fatal: detected dubious ownership in repository\n' >&2
exit 128
GIT_EOF
chmod +x "$BIN/git"

# --- Fixtures -----------------------------------------------------------------
FS_SRC="$ROOT/fs"
mkdir -p "$FS_SRC/usr/local/bin"
: > "$FS_SRC/usr/local/bin/scamwall"

container_json() { # $1 = jq mutation (or "." for none)
  jq "$1" <<JSON
[{
  "Image": "$IMAGE_ID",
  "State": { "Status": "created" },
  "Config": { "User": "65532:65532" },
  "HostConfig": {
    "GroupAdd": ["$TEST_GID"],
    "CapDrop": ["ALL"],
    "CapAdd": null,
    "Privileged": false,
    "SecurityOpt": ["no-new-privileges:true"],
    "Init": true,
    "ReadonlyRootfs": true,
    "Tmpfs": { "/tmp": "rw,noexec,nosuid,nodev,size=16m" },
    "NetworkMode": "scamwall-verify_default",
    "PortBindings": {},
    "Binds": [],
    "Memory": 134217728,
    "MemorySwap": 134217728,
    "PidsLimit": 64,
    "NanoCpus": 500000000,
    "RestartPolicy": { "Name": "no", "MaximumRetryCount": 0 }
  },
  "NetworkSettings": { "Ports": {} },
  "Mounts": [
    { "Type": "bind", "Source": "/srv/config.json", "Destination": "/etc/scamwall/config.json", "RW": false },
    { "Type": "bind", "Source": "/srv/feed.json", "Destination": "/etc/scamwall/feed.json", "RW": false },
    { "Type": "bind", "Source": "/srv/pihole-ca.crt", "Destination": "/etc/scamwall/certs/pihole-ca.crt", "RW": false }
  ]
}]
JSON
}

image_json() {
  cat <<JSON
[{
  "Id": "$IMAGE_ID",
  "Config": { "User": "65532:65532", "Healthcheck": null, "ExposedPorts": {} }
}]
JSON
}

# setup_case <name> — build a clean, all-good fake world; caller then mutates.
setup_case() {
  FAKE_DIR="$ROOT/case-$1"
  export FAKE_DIR
  rm -rf "$FAKE_DIR"; mkdir -p "$FAKE_DIR"
  : > "$FAKE_DIR/log"
  : > "$FAKE_DIR/git-log"
  image_json          > "$FAKE_DIR/image-inspect.json"
  container_json '.'  > "$FAKE_DIR/container.json"
  printf 'COPY /out/scamwall /usr/local/bin/scamwall\nFROM scratch\n' > "$FAKE_DIR/history.txt"
  printf 'fsc1111111111\n' > "$FAKE_DIR/create-id"
  printf 'depc222222222\n' > "$FAKE_DIR/ps-aq"
  tar -cf "$FAKE_DIR/export.tar" -C "$FS_SRC" . 2>/dev/null
}

run_verifier() {
  OUT="$(PATH="$BIN:$PATH" SCAMWALL_IMAGE=scamwall:local \
        "$CHECKOUT/scripts/container-runtime-verify.sh" 2>&1)"
  RC=$?
  return 0
}

# matches: does $OUT contain the extended regex $1?
#
# The match reads from a HERESTRING, never from `printf ... | grep -q`. Under
# `set -o pipefail` that pipeline is a race: `grep -q` exits at the first match,
# printf takes SIGPIPE, and the pipeline reports 141 — so a pattern that IS
# present is read as absent. Observed here as intermittent false FAILs in
# expect_output, and, far worse, as a silent false PASS in expect_no_output,
# where a pattern that appeared early would be reported as absent. See
# docs/VERIFICATION.md 4.1.
#
# grep's own exit status is also distinguished from an execution error: 0 is a
# match, 1 is no match, anything else means grep itself failed and the test
# result is UNPROVEN rather than either verdict.
matches() { # pattern -> 0 match, 1 no match, 2 grep failed
  local rc
  grep -qE "$1" <<<"$OUT"
  rc=$?
  case "$rc" in
    0|1) return "$rc" ;;
    *)   return 2 ;;
  esac
}

expect_rc_nonzero() { # label
  if [ "$RC" -ne 0 ]; then pass "$1"; else fail "$1" "expected nonzero exit, got 0"; fi
}
expect_rc_zero() { # label
  if [ "$RC" -eq 0 ]; then pass "$1"; else fail "$1" "expected exit 0, got $RC. Output: $(tail -5 <<<"$OUT" | tr '\n' '|')"; fi
}
expect_output() { # label pattern
  matches "$2"
  case $? in
    0) pass "$1" ;;
    1) fail "$1" "output did not match /$2/. Tail: $(tail -5 <<<"$OUT" | tr '\n' '|')" ;;
    *) fail "$1" "grep failed while testing /$2/ — result UNPROVEN" ;;
  esac
}
expect_no_output() { # label pattern
  matches "$2"
  case $? in
    0) fail "$1" "output unexpectedly matched /$2/" ;;
    1) pass "$1" ;;
    *) fail "$1" "grep failed while testing /$2/ — result UNPROVEN" ;;
  esac
}

echo "== container-runtime-verify.sh regression tests =="
echo

# --- 1. Baseline: a wholly good world passes ----------------------------------
echo "-- baseline --"
setup_case happy; run_verifier
expect_rc_zero  "a fully compliant world passes"
expect_output   "the deployment .env is read for the supplementary group" 'supplementary group \('"$TEST_GID"'\)'
expect_output   "the image ID is resolved and reported" "$IMAGE_ID"

# --- 2. Failed create with a pre-existing container cannot pass ---------------
echo
echo "-- failed create must not be masked by an existing container --"
setup_case create-fail
echo 1 > "$FAKE_DIR/rc.compose-create"
printf 'preexisting9999\n' > "$FAKE_DIR/ps-aq"   # a container IS present
run_verifier
expect_rc_nonzero "failed create fails even though a container exists"
expect_output     "the create failure is reported" 'compose create failed'
expect_no_output  "no container assertion is claimed as passed" 'PASS.*container user'
if grep -q 'ps -aq' "$FAKE_DIR/log"; then
  fail "the pre-existing container is never adopted" "verifier listed containers after create failed"
else
  pass "the pre-existing container is never adopted"
fi
if grep -q 'preexisting9999' "$FAKE_DIR/log"; then
  fail "the pre-existing container is never removed" "verifier referenced preexisting9999"
else
  pass "the pre-existing container is never removed"
fi

# --- 3. Failed inspect cannot pass -------------------------------------------
echo
echo "-- failed Docker operations must not pass --"
setup_case inspect-fail; echo 1 > "$FAKE_DIR/rc.inspect"; run_verifier
expect_rc_nonzero "failed container inspect fails"
expect_output     "the inspect failure is reported" 'container inspection failed'

setup_case history-fail; echo 1 > "$FAKE_DIR/rc.history"; run_verifier
expect_rc_nonzero "failed docker history fails"
expect_output     "the history failure is reported" 'image history could not be read'
expect_no_output  "error text is not accepted as a clean history" 'PASS.*no credential pattern'

setup_case export-fail; echo 1 > "$FAKE_DIR/rc.export"; run_verifier
expect_rc_nonzero "failed docker export fails"
expect_output     "enumeration failure is reported as unproven" 'docker export failed.*UNPROVEN'
expect_no_output  "no path absence is claimed" 'PASS.*no shell at checked paths'

setup_case image-inspect-fail; echo 1 > "$FAKE_DIR/rc.image-inspect"; run_verifier
expect_rc_nonzero "failed image inspect blocks verification"
expect_output     "the image inspect failure is reported" 'could not be inspected'

# --- 4. Unparseable JSON cannot pass -----------------------------------------
echo
echo "-- JSON parsing failures must not pass --"
setup_case bad-json; printf 'this is not json\n' > "$FAKE_DIR/container.json"; run_verifier
expect_rc_nonzero "unparseable container JSON fails"
expect_output     "the parse failure is reported" 'not a single-element JSON array'

setup_case empty-json; printf '[]\n' > "$FAKE_DIR/container.json"; run_verifier
expect_rc_nonzero "an empty inspection array fails"

setup_case bad-image-json; printf '{"broken":\n' > "$FAKE_DIR/image-inspect.json"; run_verifier
expect_rc_nonzero "unparseable image JSON blocks verification"

# --- 5. Image mismatch fails --------------------------------------------------
echo
echo "-- image identity --"
setup_case image-mismatch
container_json ".[0].Image = \"$OTHER_ID\"" > "$FAKE_DIR/container.json"
run_verifier
expect_rc_nonzero "a container running a different image fails"
expect_output     "the mismatch is reported" 'container image matches resolved image ID'

setup_case pinned-id-mismatch
OUT="$(PATH="$BIN:$PATH" SCAMWALL_IMAGE=scamwall:local \
      SCAMWALL_EXPECTED_IMAGE_ID="$OTHER_ID" \
      "$CHECKOUT/scripts/container-runtime-verify.sh" 2>&1)"; RC=$?
expect_rc_nonzero "a resolved image ID differing from the pinned one fails"
expect_output     "the pin mismatch is reported" 'SCAMWALL_EXPECTED_IMAGE_ID'

# --- 6. Prohibited mounts detected through .Mounts ---------------------------
echo
echo "-- prohibited mounts via .Mounts --"
setup_case docker-sock
# .HostConfig.Binds stays EMPTY: this mount is only visible through .Mounts,
# which is exactly the representation the old Binds-only check missed.
container_json '.[0].Mounts += [{"Type":"bind","Source":"/var/run/docker.sock","Destination":"/var/run/docker.sock","RW":false}]' \
  > "$FAKE_DIR/container.json"
run_verifier
expect_rc_nonzero "a docker.sock mount invisible in .Binds is detected"
expect_output     "the prohibited mount is named" 'prohibited mounts.*docker\.sock|docker\.sock.*->'

setup_case pihole-mount
container_json '.[0].Mounts += [{"Type":"bind","Source":"/etc/pihole","Destination":"/etc/pihole","RW":false}]' \
  > "$FAKE_DIR/container.json"
run_verifier
expect_rc_nonzero "an /etc/pihole mount is detected"

setup_case writable-mount
container_json '.[0].Mounts[0].RW = true' > "$FAKE_DIR/container.json"
run_verifier
expect_rc_nonzero "a writable mount is detected"
expect_output     "the writable mount is named" 'every mount is read-only'

# --- 7. Hardening regressions -------------------------------------------------
echo
echo "-- hardening regressions --"
for probe in \
  '.[0].HostConfig.ReadonlyRootfs = false|writable rootfs' \
  '.[0].HostConfig.Privileged = true|privileged container' \
  '.[0].HostConfig.CapAdd = ["NET_ADMIN"]|added capability' \
  '.[0].HostConfig.CapDrop = []|capabilities not dropped' \
  '.[0].HostConfig.SecurityOpt = ["seccomp:unconfined"]|unconfined seccomp' \
  '.[0].HostConfig.NetworkMode = "host"|host networking' \
  '.[0].HostConfig.PortBindings = {"53/tcp":[{"HostPort":"53"}]}|published port' \
  '.[0].HostConfig.Tmpfs = {"/tmp":"rw,size=16m"}|tmpfs without noexec' \
  '.[0].HostConfig.PidsLimit = 0|no pids limit' \
  '.[0].HostConfig.Memory = 0|no memory limit' \
  '.[0].Config.User = "0:0"|root user' \
  '.[0].HostConfig.GroupAdd = ["0"]|wrong supplementary group' \
  '.[0].State.Status = "running"|container already started' \
; do
  mutation="${probe%%|*}"; label="${probe##*|}"
  setup_case "probe"
  container_json "$mutation" > "$FAKE_DIR/container.json"
  run_verifier
  expect_rc_nonzero "detected: $label"
done

# --- 8. Filesystem enumeration ------------------------------------------------
echo
echo "-- filesystem enumeration --"
setup_case shell-present
SHELL_FS="$ROOT/fs-shell"; rm -rf "$SHELL_FS"
mkdir -p "$SHELL_FS/usr/local/bin" "$SHELL_FS/bin"
: > "$SHELL_FS/usr/local/bin/scamwall"; : > "$SHELL_FS/bin/sh"
tar -cf "$FAKE_DIR/export.tar" -C "$SHELL_FS" .
run_verifier
expect_rc_nonzero "a shell present in the image is detected"
expect_output     "the shell finding is reported" 'no shell at checked paths'

setup_case anchor-missing
BARE_FS="$ROOT/fs-bare"; rm -rf "$BARE_FS"; mkdir -p "$BARE_FS/etc"; : > "$BARE_FS/etc/hosts"
tar -cf "$FAKE_DIR/export.tar" -C "$BARE_FS" .
run_verifier
expect_rc_nonzero "a listing without the scamwall binary is not trusted"
expect_output     "the untrustworthy listing is reported" 'untrustworthy|UNPROVEN'

setup_case empty-tar; : > "$FAKE_DIR/export.tar"; run_verifier
expect_rc_nonzero "an empty export is not treated as an empty filesystem"

# --- 9. Cleanup preserves pre-existing containers -----------------------------
echo
echo "-- cleanup scope --"
setup_case cleanup; run_verifier
if grep -qE '^rm -f fsc1111111111$' "$FAKE_DIR/log" && grep -qE '^rm -f depc222222222$' "$FAKE_DIR/log"; then
  pass "containers created by this run are removed"
else
  fail "containers created by this run are removed" "log: $(tr '\n' '|' < "$FAKE_DIR/log")"
fi
# Both intermediate results are captured into variables first. `producer |
# grep -q...` would race: the short-circuiting grep exits at the first match and
# the producer takes SIGPIPE, which pipefail turns into a nonzero pipeline
# status. Here the consumer is `grep -qv`, which short-circuits on the first
# NON-matching line — so the race would have turned an unscoped `compose down`
# into a silent PASS.
DOWN_CMDS="$(grep -E '^compose .*down' "$FAKE_DIR/log" || true)"
if [ -n "$DOWN_CMDS" ] && grep -qvE '\-p scamwall-verify-[0-9]+' <<<"$DOWN_CMDS"; then
  fail "compose down is always scoped to the private project" "an unscoped down was issued"
else
  pass "compose down is always scoped to the private project"
fi
if grep -qE 'compose .*(-p scamwall |^compose down|--all)' "$FAKE_DIR/log"; then
  fail "the deployment project is never targeted" "log referenced the deployment project"
else
  pass "the deployment project is never targeted"
fi

setup_case cleanup-interrupt
# A mid-run failure must still clean up what was created before it.
echo 1 > "$FAKE_DIR/rc.inspect"; run_verifier
if grep -qE '^rm -f fsc1111111111$' "$FAKE_DIR/log"; then
  pass "cleanup runs even when verification fails part-way"
else
  fail "cleanup runs even when verification fails part-way" "log: $(tr '\n' '|' < "$FAKE_DIR/log")"
fi

# --- 10. Missing daemon access blocks verification ----------------------------
echo
echo "-- daemon availability --"
setup_case no-daemon; echo 1 > "$FAKE_DIR/rc.info"; run_verifier
expect_rc_nonzero "an unreachable daemon blocks verification"
expect_output     "the block is reported, not skipped" 'BLOCKED.*docker daemon not reachable'
expect_output     "the result is stated as incomplete" 'INCOMPLETE'
expect_no_output  "no container property is claimed" 'PASS.*rootfs read-only'

setup_case no-compose; echo 1 > "$FAKE_DIR/rc.compose-version"; run_verifier
expect_rc_nonzero "a missing compose plugin blocks verification"

# --- 11. The operator path works without git ----------------------------------
echo
echo "-- no git dependency --"
setup_case no-git; run_verifier
expect_rc_zero "verification succeeds with a git that refuses every call"
if [ -s "$FAKE_DIR/git-log" ]; then
  fail "git is never invoked by the Docker verification path" "git was called: $(tr '\n' '|' < "$FAKE_DIR/git-log")"
else
  pass "git is never invoked by the Docker verification path"
fi
GIT_LINES="$(grep -rn 'git ' "$VERIFIER" | grep -vE '^\s*[0-9]+:\s*#' || true)"
if [ -n "$GIT_LINES" ] && grep -qE '(^|[^a-z-])git (rev-parse|status|config|ls-files)' <<<"$GIT_LINES"; then
  fail "the verifier contains no git invocation" "a git command appears outside comments"
else
  pass "the verifier contains no git invocation"
fi

echo
echo "=============================================="
printf '%d tests, %d failed\n' "$TESTS" "$FAILURES"
[ "$FAILURES" -eq 0 ] || exit 1
echo "all runtime-verify regression tests passed"
