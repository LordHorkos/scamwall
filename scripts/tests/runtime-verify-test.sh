#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
#
# runtime-verify-test.sh — regression tests for container-runtime-verify.sh.
#
# Every defect these tests cover was a FALSE PASS: the verifier reported a
# security property as satisfied when it had not actually been observed. A test
# here therefore asserts that a broken world produces a NONZERO exit, not merely
# that it prints something.
#
# The tests need no Docker daemon and no network. `docker` is replaced by a
# scripted fake whose responses are files on disk, and which MODELS RESOURCE
# LIFETIME: resources appear when a create command runs, disappear when a remove
# command succeeds, and label queries only ever return what a real daemon would
# return for that label. That is what makes ownership, collision and cleanup
# behaviour testable without a daemon.
#
# Where a fix changed an expression rather than a control flow, the test carries
# a PRE-FIX CONTROL: the superseded expression is applied to the same fixture and
# asserted to exhibit the defect. Without it, a passing test proves only that
# the current code agrees with itself.
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
RESOURCE_LIB="$REPO/scripts/lib/docker-resources.sh"
[ -f "$RESOURCE_LIB" ] || { printf 'fatal: resource library not found: %s\n' "$RESOURCE_LIB" >&2; exit 2; }

ROOT="$(mktemp -d)" || exit 2
trap 'rm -rf "$ROOT"' EXIT

# The .env gid and the RESOLVED gid differ deliberately. Expected settings must
# come from `docker compose config`, which performs Compose's own interpolation;
# the superseded implementation grepped .env directly and stripped quotes by
# hand, so it would derive ENV_GID and disagree with the container.
ENV_GID="4242"
# The resolved gid is the running account's own primary group. The verifier
# now checks that the supplementary group actually owns the password file, so
# a fixture gid this account cannot chgrp to would make every case fail on an
# unrelated assertion. The ENV_GID above stays different, which is what keeps
# the "expected settings come from compose config, not from .env" property
# under test.
CONFIG_GID="$(id -g)"
IMAGE_ID="sha256:1111111111111111111111111111111111111111111111111111111111111111"
OTHER_ID="sha256:2222222222222222222222222222222222222222222222222222222222222222"
MANIFEST_ID="sha256:3333333333333333333333333333333333333333333333333333333333333333"
FS_CID="fbc111111111"
DEP_CID="dec222222222"
NET_ID="ce7333333333"

# --- Synthetic checkout -------------------------------------------------------
CHECKOUT="$ROOT/checkout"
mkdir -p "$CHECKOUT/scripts" "$CHECKOUT/container" "$CHECKOUT/deploy/compose"
cp "$VERIFIER" "$CHECKOUT/scripts/container-runtime-verify.sh"
chmod +x "$CHECKOUT/scripts/container-runtime-verify.sh"
# The verifier sanitizes any captured Compose error through this before printing
# it, and prints nothing at all if it is absent. Copying it in means the cases
# below exercise the path an operator and CI actually take, rather than the
# fail-closed branch.
cp "$REPO/scripts/gate-diagnostics.sh" "$CHECKOUT/scripts/gate-diagnostics.sh"
# The resource attribution and cleanup implementation is shared with
# scripts/operator-handoff.sh and lives in scripts/lib. The verifier refuses to
# run without it — creating Docker resources with no cleanup implementation is
# the one failure it must not have — so the synthetic checkout carries it too.
mkdir -p "$CHECKOUT/scripts/lib"
cp "$REPO/scripts/lib/docker-resources.sh" "$CHECKOUT/scripts/lib/docker-resources.sh"
cp "$REPO/container/Dockerfile" "$CHECKOUT/container/Dockerfile"
cp "$REPO/deploy/compose/compose.yaml" "$CHECKOUT/deploy/compose/compose.yaml"
printf 'SCAMWALL_SECRET_GID=%s\nPIHOLE_HOST_IP=host-gateway\n' "$ENV_GID" > "$CHECKOUT/deploy/compose/.env"

# --- Fake docker --------------------------------------------------------------
#
# It models resource lifetime rather than replaying canned output:
#   live-containers-project   containers Compose created for this project
#   live-containers-own       containers created with the ownership label
#   live-networks/live-volumes  ditto
#   removed                   ids a successful remove has retired
# A listing never returns a removed id, and inspecting one fails as it would on
# a real daemon — which is what makes "cleanup is idempotent" a real assertion.
BIN="$ROOT/bin"
mkdir -p "$BIN"
cat > "$BIN/docker" <<'FAKE_EOF'
#!/usr/bin/env bash
D="$FAKE_DIR"
printf '%s\n' "$*" >> "$D/log"

rc_for() { if [ -f "$D/rc.$1" ]; then cat "$D/rc.$1"; else echo 0; fi; }
signal_if() { if [ -f "$D/term-on-$1" ]; then rm -f "$D/term-on-$1"; kill -TERM "$PPID" 2>/dev/null; fi; return 0; }
is_removed() { [ -f "$D/removed" ] && grep -Fxq "$1" "$D/removed"; }
live_add() { [ -n "${2:-}" ] && printf '%s\n' "$2" >> "$D/$1"; return 0; }
live_list() {
  [ -f "$D/$1" ] || return 0
  local id
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    is_removed "$id" && continue
    printf '%s\n' "$id"
  done < "$D/$1"
  return 0
}
retire() { printf '%s\n' "$1" >> "$D/removed"; }
inject_labels() { # file
  local tok proj
  tok="$(cat "$D/token" 2>/dev/null)"; proj="$(cat "$D/project" 2>/dev/null)"
  if [ -f "$D/no-owner-label" ]; then cat "$1"; return 0; fi
  jq --arg t "${tok:-}" --arg p "${proj:-}" \
     '.[0].Config.Labels = ((.[0].Config.Labels // {}) + {"scamwall.verify.invocation": $t, "com.docker.compose.project": $p})' \
     < "$1" 2>/dev/null || cat "$1"
}
label_kind() { # selector -> which live file it addresses
  case "$1" in
    label=com.docker.compose.project=*) printf 'project' ;;
    label=scamwall.verify.invocation=*) printf 'own' ;;
    *) printf 'other' ;;
  esac
}

if [ "${1:-}" = "compose" ]; then
  shift
  op=""; project=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -p|--project-name) project="${2:-}"; shift 2 ;;
      -f|--file|--env-file|--project-directory) shift 2 ;;
      -*) shift ;;
      *) op="$1"; shift; break ;;
    esac
  done
  if [ -n "$project" ]; then
    printf '%s' "$project" > "$D/project"
    printf '%s' "${project#scamwall-verify-}" > "$D/token"
  fi
  case "$op" in
    version) exit "$(rc_for compose-version)" ;;
    config)
      r="$(rc_for compose-config)"
      if [ "$r" -ne 0 ]; then printf 'services.scamwall: unresolvable interpolation (fake)\n' >&2; exit "$r"; fi
      if [ -f "$D/config-garbage" ]; then printf 'not json at all\n'; exit 0; fi
      tok="$(cat "$D/token" 2>/dev/null)"
      if [ -f "$D/drop-label" ]; then tok="somebody-elses-invocation"; fi
      proj="$(cat "$D/project" 2>/dev/null)"
      # Real Compose renders every network and volume name as <project>_<key>.
      # The fixture is written project-independently, so the project-relative
      # names are applied here, exactly as the daemon-facing tool would.
      mut='.'
      [ -f "$D/config-mutate" ] && mut="$(cat "$D/config-mutate")"
      jq --arg p "$proj" --arg t "$tok" \
         '.name = $p
          | (if has("networks") then .networks |= with_entries(.value.name = ($p + "_" + .key)) else . end)
          | (if has("volumes")  then .volumes  |= with_entries(.value.name = ($p + "_" + .key)) else . end)
          | .services.scamwall.labels = {"scamwall.verify.invocation": $t}' \
         < "$D/compose-config.json" \
        | jq --arg p "$proj" "$mut"
      exit 0 ;;
    create)
      [ -f "$D/no-create-container" ] || live_add live-containers-project "$(cat "$D/ps-aq" 2>/dev/null)"
      [ -f "$D/no-create-network" ]   || live_add live-networks "$(cat "$D/net-id" 2>/dev/null)"
      r="$(rc_for compose-create)"
      if [ "$r" -ne 0 ]; then printf 'Error response from daemon: create refused (fake)\n' >&2; fi
      signal_if compose-create
      exit "$r" ;;
    ps)
      r="$(rc_for compose-ps)"; [ "$r" -ne 0 ] && exit "$r"
      live_list live-containers-project; exit 0 ;;
    *) exit 0 ;;
  esac
fi

case "${1:-}" in
  info)
    r="$(rc_for info)"; [ "$r" -ne 0 ] && exit "$r"
    # `docker info --format` is how the verifier asks the daemon whether it
    # remaps user namespaces. A case that wants a particular answer writes it
    # to info-security; the default is silence, which the verifier treats as
    # "could not be asked" rather than as "no remapping".
    [ -f "$D/info-security" ] && cat "$D/info-security"
    exit 0 ;;
  image)
    shift; [ "${1:-}" = "inspect" ] && shift
    ref=""
    while [ $# -gt 0 ]; do
      case "$1" in -*) shift 2 ;; *) ref="$1"; shift ;; esac
    done
    r="$(rc_for image-inspect)"; [ "$r" -ne 0 ] && exit "$r"
    san="$(printf '%s' "$ref" | tr -c 'a-zA-Z0-9' '_')"
    f="$D/image-inspect.$san.json"
    [ -f "$f" ] || f="$D/image-inspect.json"
    [ -f "$f" ] || exit 1
    cat "$f"; exit 0 ;;
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
    live_add live-containers-own "$(cat "$D/create-id" 2>/dev/null)"
    cat "$D/create-id"; exit 0 ;;
  export)
    r="$(rc_for export)"; [ "$r" -ne 0 ] && exit "$r"
    signal_if export
    cat "$D/export.tar"; exit 0 ;;
  inspect)
    shift
    id=""
    while [ $# -gt 0 ]; do
      case "$1" in -*) shift 2 ;; *) id="$1"; shift ;; esac
    done
    r="$(rc_for inspect)"; [ "$r" -ne 0 ] && exit "$r"
    is_removed "$id" && { printf 'Error: No such object: %s\n' "$id" >&2; exit 1; }
    f="$D/inspect.$id.json"; [ -f "$f" ] || f="$D/container.json"
    signal_if inspect
    inject_labels "$f"; exit 0 ;;
  ps)
    shift
    sel=""
    while [ $# -gt 0 ]; do
      case "$1" in --filter) sel="${2:-}"; shift 2 ;; *) shift ;; esac
    done
    r="$(rc_for ps)"; [ "$r" -ne 0 ] && exit "$r"
    case "$sel" in
      id=*)
        id="${sel#id=}"
        # Captured first: `producer | grep -q` is the SIGPIPE race this
        # repository bans (scripts/tests/pipefail-sigpipe-test.sh).
        known="$( { live_list live-containers-project; live_list live-containers-own; } )"
        if ! is_removed "$id" && grep -Fxq "$id" <<< "$known"; then printf '%s\n' "$id"; fi ;;
      *) case "$(label_kind "$sel")" in
           project) live_list live-containers-project ;;
           own)     live_list live-containers-own ;;
           *) printf 'UNFILTERED-PS\n' >> "$D/log" ;;
         esac ;;
    esac
    exit 0 ;;
  network|volume)
    kind="$1"; shift
    sub="${1:-}"; shift || true
    case "$sub" in
      ls)
        sel=""
        while [ $# -gt 0 ]; do
          case "$1" in --filter) sel="${2:-}"; shift 2 ;; *) shift ;; esac
        done
        r="$(rc_for "$kind-ls")"; [ "$r" -ne 0 ] && exit "$r"
        case "$sel" in
          id=*|name=*)
            id="${sel#*=}"
            known="$(live_list "live-${kind}s")"
            if ! is_removed "$id" && grep -Fxq "$id" <<< "$known"; then printf '%s\n' "$id"; fi ;;
          *) case "$(label_kind "$sel")" in
               project|own) live_list "live-${kind}s" ;;
               *) printf 'UNFILTERED-%s-LS\n' "$kind" >> "$D/log" ;;
             esac ;;
        esac
        exit 0 ;;
      inspect)
        id=""
        while [ $# -gt 0 ]; do
          case "$1" in -*) shift 2 ;; *) id="$1"; shift ;; esac
        done
        is_removed "$id" && exit 1
        if [ -f "$D/no-owner-label" ]; then printf '[{"Labels":{}}]\n'; else
          printf '[{"Labels":{"com.docker.compose.project":"%s"}}]\n' "$(cat "$D/project" 2>/dev/null)"
        fi
        exit 0 ;;
      rm)
        id=""
        while [ $# -gt 0 ]; do
          case "$1" in -*) shift ;; *) id="$1"; shift ;; esac
        done
        r="$(rc_for "$kind-rm")"; [ "$r" -ne 0 ] && exit "$r"
        retire "$id"; exit 0 ;;
      *) exit 0 ;;
    esac ;;
  rm)
    shift
    id=""
    while [ $# -gt 0 ]; do
      case "$1" in -*) shift ;; *) id="$1"; shift ;; esac
    done
    r="$(rc_for rm)"; [ "$r" -ne 0 ] && exit "$r"
    retire "$id"; exit 0 ;;
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

# A sort that can be made to fail for a specific invocation shape. The verifier
# combines resource lists with `sort -u` and prepares the mount comparison with
# `sort -o`; both used to discard the status, so a sort that could not run
# produced an empty list or an unsorted operand and the gate reported clean.
REAL_SORT="$(command -v sort)" || { printf 'fatal: no sort on PATH\n' >&2; exit 2; }
cat > "$BIN/sort" <<SORT_EOF
#!/usr/bin/env bash
if [ -n "\${FAKE_DIR:-}" ]; then
  for a in "\$@"; do
    case "\$a" in
      -u) [ -f "\$FAKE_DIR/break-sort-u" ] && { printf 'sort: cannot write (fake)\n' >&2; exit 2; } ;;
      -o) [ -f "\$FAKE_DIR/break-sort-o" ] && { printf 'sort: cannot write (fake)\n' >&2; exit 2; } ;;
    esac
  done
fi
exec $REAL_SORT "\$@"
SORT_EOF
chmod +x "$BIN/sort"

# --- Fixtures -----------------------------------------------------------------
FS_SRC="$ROOT/fs"
mkdir -p "$FS_SRC/usr/local/bin"
: > "$FS_SRC/usr/local/bin/scamwall"

# The mount sources below are the RESOLVED paths the fake configuration
# declares. The container fixture must agree with it exactly: that agreement is
# the property under test.
#
# They are REAL files under the test root, not the notional `/srv/...` paths
# they used to be. The verifier now checks that every approved mount resolves to
# an existing regular file on the host — because Docker's default is to invent
# an empty DIRECTORY at a missing bind source and mount that, which satisfies
# every destination and read-only assertion while leaving the container with no
# CA and no credential. A fixture that does not exist could not exercise that.
SRV="$ROOT/srv"
mkdir -p "$SRV/secrets"
CA_SRC="$SRV/pihole-ca.crt"
CONF_SRC="$SRV/config.json"
FEED_SRC="$SRV/feed.json"
SECRET_SRC="$SRV/secrets/pihole_app_password"
printf 'test-only placeholder, not a certificate\n' > "$CA_SRC"
printf '{}\n' > "$CONF_SRC"
printf '{}\n' > "$FEED_SRC"
printf 'test-only-password\n' > "$SECRET_SRC"
chmod 700 "$SRV/secrets"
# 0640, not 0600: the container joins CONFIG_GID as a supplementary group and
# reads the file through the group class, so a fixture with no group-read bit
# would model a deployment whose credential the container cannot open.
chmod 640 "$SECRET_SRC"

container_json() { # $1 = jq mutation (or "." for none)
  jq "$1" <<JSON
[{
  "Image": "$IMAGE_ID",
  "State": { "Status": "created", "Running": false, "Pid": 0, "StartedAt": "0001-01-01T00:00:00Z" },
  "RestartCount": 0,
  "Config": {
    "User": "65532:65532",
    "Image": "scamwall:local",
    "Labels": {}
  },
  "HostConfig": {
    "GroupAdd": ["$CONFIG_GID"],
    "CapDrop": ["ALL"],
    "CapAdd": null,
    "Privileged": false,
    "SecurityOpt": ["no-new-privileges:true"],
    "Init": true,
    "ReadonlyRootfs": true,
    "Tmpfs": { "/tmp": "rw,noexec,nosuid,nodev,size=16m" },
    "NetworkMode": "scamwall-verify_default",
    "ExtraHosts": ["pi.hole:host-gateway"],
    "PortBindings": {},
    "Binds": [],
    "LogConfig": { "Type": "json-file", "Config": { "max-size": "5m", "max-file": "3" } },
    "Memory": 134217728,
    "MemorySwap": 134217728,
    "PidsLimit": 64,
    "NanoCpus": 500000000,
    "RestartPolicy": { "Name": "no", "MaximumRetryCount": 0 }
  },
  "NetworkSettings": { "Ports": {} },
  "Mounts": [
    { "Type": "bind", "Source": "$CONF_SRC",   "Destination": "/etc/scamwall/config.json", "RW": false },
    { "Type": "bind", "Source": "$FEED_SRC",   "Destination": "/etc/scamwall/feed.json", "RW": false },
    { "Type": "bind", "Source": "$CA_SRC",     "Destination": "/etc/scamwall/certs/pihole-ca.crt", "RW": false },
    { "Type": "bind", "Source": "$SECRET_SRC", "Destination": "/run/secrets/pihole_app_password", "RW": false },
    { "Type": "tmpfs", "Destination": "/tmp", "RW": true }
  ]
}]
JSON
}

image_json() { # $1 = id
  cat <<JSON
[{
  "Id": "${1:-$IMAGE_ID}",
  "RepoTags": ["scamwall:local"],
  "RepoDigests": [],
  "Config": { "User": "65532:65532", "Healthcheck": null, "ExposedPorts": {} }
}]
JSON
}

compose_config_json() { # $1 = jq mutation
  jq "${1:-.}" <<JSON
{
  "name": "placeholder",
  "networks": { "default": { "name": "placeholder_default" } },
  "secrets": { "pihole_app_password": { "file": "$SECRET_SRC" } },
  "services": {
    "scamwall": {
      "image": "scamwall:local",
      "cap_drop": ["ALL"],
      "cpus": 0.5,
      "extra_hosts": ["pi.hole=host-gateway"],
      "group_add": ["$CONFIG_GID"],
      "init": true,
      "logging": { "driver": "json-file", "options": { "max-file": "3", "max-size": "5m" } },
      "mem_limit": "134217728",
      "memswap_limit": "134217728",
      "pids_limit": 64,
      "read_only": true,
      "restart": "no",
      "secrets": [ { "source": "pihole_app_password", "target": "/run/secrets/pihole_app_password" } ],
      "security_opt": ["no-new-privileges:true"],
      "tmpfs": ["/tmp:rw,noexec,nosuid,nodev,size=16m"],
      "user": "65532:65532",
      "volumes": [
        { "type": "bind", "source": "$CA_SRC",   "target": "/etc/scamwall/certs/pihole-ca.crt", "read_only": true },
        { "type": "bind", "source": "$CONF_SRC", "target": "/etc/scamwall/config.json", "read_only": true },
        { "type": "bind", "source": "$FEED_SRC", "target": "/etc/scamwall/feed.json", "read_only": true }
      ]
    }
  }
}
JSON
}

# setup_case <name> — build a clean, all-good fake world; caller then mutates.
setup_case() {
  FAKE_DIR="$ROOT/case-$1"
  export FAKE_DIR
  rm -rf "$FAKE_DIR"; mkdir -p "$FAKE_DIR"
  : > "$FAKE_DIR/log"
  : > "$FAKE_DIR/git-log"
  : > "$FAKE_DIR/removed"
  image_json "$IMAGE_ID"   > "$FAKE_DIR/image-inspect.json"
  container_json '.'       > "$FAKE_DIR/container.json"
  compose_config_json '.'  > "$FAKE_DIR/compose-config.json"
  printf '[{"Config":{"Labels":{}}}]\n' > "$FAKE_DIR/inspect.$FS_CID.json"
  printf 'COPY /out/scamwall /usr/local/bin/scamwall\nFROM scratch\n' > "$FAKE_DIR/history.txt"
  printf '%s\n' "$FS_CID"  > "$FAKE_DIR/create-id"
  printf '%s\n' "$DEP_CID" > "$FAKE_DIR/ps-aq"
  printf '%s\n' "$NET_ID"  > "$FAKE_DIR/net-id"
  tar -cf "$FAKE_DIR/export.tar" -C "$FS_SRC" . 2>/dev/null
}

# fs_from <dir> — replace the exported image filesystem with the given tree.
# fs_from <dir> — export the tree with `tar -C dir .`, which writes members
# WITH a leading "./" (docker export archives look like this on some hosts).
fs_from() { tar -cf "$FAKE_DIR/export.tar" -C "$1" . ; }

# fs_from_paths <dir> <member...> — export named members, which tar writes
# WITHOUT a leading "./". This is the shape the superseded expressions missed
# entirely: `^\./?bin/sh$` requires the dot, so "bin/sh" matched nothing and
# every absence assertion passed without examining anything.
fs_from_paths() { local dir="$1"; shift; tar -cf "$FAKE_DIR/export.tar" -C "$dir" "$@"; }

# make_fs <name> <relative paths...> — build a filesystem tree containing the
# scamwall binary (the trust anchor) plus the given paths.
make_fs() {
  local name="$1"; shift
  local dir="$ROOT/fs-$name" p
  rm -rf "$dir"; mkdir -p "$dir/usr/local/bin"; : > "$dir/usr/local/bin/scamwall"
  for p in "$@"; do
    mkdir -p "$dir/$(dirname "$p")"
    : > "$dir/$p"
  done
  printf '%s' "$dir"
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
  if [ "$RC" -eq 0 ]; then pass "$1"; else fail "$1" "expected exit 0, got $RC. Output: $(tail -8 <<<"$OUT" | tr '\n' '|')"; fi
}
expect_output() { # label pattern
  matches "$2"
  case $? in
    0) pass "$1" ;;
    1) fail "$1" "output did not match /$2/. Tail: $(tail -8 <<<"$OUT" | tr '\n' '|')" ;;
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
# log_has / log_lacks — assertions over the fake daemon's command log.
log_has() { # label extended-regex
  if grep -qE "$2" "$FAKE_DIR/log"; then pass "$1"
  else fail "$1" "log did not contain /$2/: $(tr '\n' '|' < "$FAKE_DIR/log")"; fi
}
log_lacks() { # label extended-regex
  if grep -qE "$2" "$FAKE_DIR/log"; then
    fail "$1" "log unexpectedly contained /$2/: $(tr '\n' '|' < "$FAKE_DIR/log")"
  else pass "$1"; fi
}
log_count() { # extended-regex -> prints count
  local n
  n="$(grep -cE "$1" "$FAKE_DIR/log")" || n=0
  printf '%s' "$n"
}

# The helper definitions are lifted out of the verifier and exercised directly,
# because the "search could not be performed" branch is not reachable through a
# fake daemon: the file grep reads is written by the verifier itself.
eval "$(sed -n '/^search_file()/,/^}$/p' "$VERIFIER")"
eval "$(sed -n '/^count_matches()/,/^}$/p' "$VERIFIER")"
eval "$(sed -n '/^SIZE_MAX_BYTES=/p' "$VERIFIER")"
eval "$(sed -n '/^to_decimal()/,/^}$/p' "$VERIFIER")"
eval "$(sed -n '/^size_to_bytes()/,/^}$/p' "$VERIFIER")"
eval "$(sed -n '/^is_uint()/,/^}$/p' "$VERIFIER")"
# in_list and combine_ids moved to the shared resource library when
# scripts/operator-handoff.sh began using the same attribution and cleanup
# implementation. They are extracted from where they now live; extracting from
# the verifier silently yielded NOTHING, and an undefined in_list made every
# approved mount look unapproved.
eval "$(sed -n '/^in_list()/,/^}$/p' "$RESOURCE_LIB")"
eval "$(sed -n '/^combine_ids()/,/^}$/p' "$RESOURCE_LIB")"
eval "$(sed -n '/^APPROVED_MOUNT_DESTS=/,/pihole_app_password.$/p' "$VERIFIER")"
eval "$(sed -n '/^APPROVED_MOUNT_COUNT=/p' "$VERIFIER")"
eval "$(sed -n '/^approved_mount_problems()/,/^}$/p' "$VERIFIER")"

# Every lift is checked, not just the two that moved.
#
# `eval "$(sed ...)"` that matched nothing evaluates the empty string and
# succeeds, so a helper that MOVED and a helper that is still there are the
# same outcome until something calls it. That is how in_list disappearing from
# the verifier turned into "every approved mount is unapproved and unmounted"
# rather than into an error naming the missing helper.
for extracted in search_file count_matches to_decimal size_to_bytes is_uint \
                 in_list combine_ids approved_mount_problems; do
  declare -F "$extracted" >/dev/null ||
    { printf 'fatal: %s could not be extracted\n' "$extracted" >&2; exit 2; }
done
[ -n "${SIZE_MAX_BYTES:-}" ] ||
  { printf 'fatal: SIZE_MAX_BYTES could not be extracted\n' >&2; exit 2; }
[ "${#APPROVED_MOUNT_DESTS[@]}" -gt 0 ] ||
  { printf 'fatal: APPROVED_MOUNT_DESTS could not be extracted\n' >&2; exit 2; }
[ -n "${APPROVED_MOUNT_COUNT:-}" ] ||
  { printf 'fatal: APPROVED_MOUNT_COUNT could not be extracted\n' >&2; exit 2; }

echo "== container-runtime-verify.sh regression tests =="
echo

# --- 1. Baseline: a wholly good world passes ----------------------------------
echo "-- baseline --"
setup_case happy; run_verifier
expect_rc_zero  "a fully compliant world passes"
expect_output   "the resolved configuration supplies the supplementary group" 'supplementary group \('"$CONFIG_GID"'\)'
expect_output   "the image ID is resolved and reported" "$IMAGE_ID"
expect_output   "cleanup reports completion" 'cleanup complete'

# The pre-fix implementation derived the expected gid by grepping .env. It would
# have expected ENV_GID and disagreed with the container, which carries the
# gid Compose actually resolved.
expect_no_output "the .env value is NOT used as the expected group" 'supplementary group \('"$ENV_GID"'\)'

# Cleanup must be part of the verdict, so it has to happen BEFORE the verdict is
# printed. Previously the success line came first and cleanup errors were lost.
CLEANUP_LINE="$(grep -n '== cleanup ==' <<<"$OUT" | head -1 | cut -d: -f1)"
RESULT_LINE="$(grep -n '^RESULT:' <<<"$OUT" | head -1 | cut -d: -f1)"
if [ -n "$CLEANUP_LINE" ] && [ -n "$RESULT_LINE" ] && [ "$CLEANUP_LINE" -lt "$RESULT_LINE" ]; then
  pass "cleanup completes before the verdict is reported"
else
  fail "cleanup completes before the verdict is reported" "cleanup at line ${CLEANUP_LINE:-none}, verdict at line ${RESULT_LINE:-none}"
fi

# The invocation identifier must be unpredictable, and different every run.
PROJ_A="$(grep -oE 'scamwall-verify-[0-9a-f]+' <<<"$OUT" | head -1)"
setup_case happy2; run_verifier
PROJ_B="$(grep -oE 'scamwall-verify-[0-9a-f]+' <<<"$OUT" | head -1)"
if [ -n "$PROJ_A" ] && [ "${#PROJ_A}" -ge 32 ] && [ "$PROJ_A" != "$PROJ_B" ]; then
  pass "the project name is long and differs between invocations (not a PID)"
else
  fail "the project name is long and differs between invocations (not a PID)" "A=$PROJ_A B=$PROJ_B"
fi
if [[ "$PROJ_A" =~ ^scamwall-verify-[0-9]+$ ]]; then
  fail "the project name is not derived from a PID" "purely numeric suffix: $PROJ_A"
else
  pass "the project name is not derived from a PID"
fi

# --- 2. Filesystem path matching ---------------------------------------------
echo
echo "-- filesystem path matching (with and without a leading ./) --"

# tar writes archive members either as "./bin/sh" or as "bin/sh" depending on
# how the archive was produced. The superseded expressions began with `^\./?`,
# which REQUIRES the dot, so an unprefixed member matched nothing and every
# absence assertion passed vacuously.
PREFIX_RE_OLD='^\./?(usr/)?s?bin/(sh|bash|dash|ash|zsh|ksh)$'
PREFIX_RE_NEW='^(usr/)?(local/)?s?bin/(sh|bash|dash|ash|zsh|ksh)$'
PROBE="$ROOT/path-probe.txt"
printf 'bin/sh\nusr/bin/bash\netc/shadow\n' > "$PROBE"
if grep -qE "$PREFIX_RE_OLD" "$PROBE"; then
  fail "PRE-FIX CONTROL: the superseded expression missed unprefixed paths" "it matched, so this control proves nothing"
else
  pass "PRE-FIX CONTROL: the superseded expression missed unprefixed paths (the defect)"
fi
if grep -qE "$PREFIX_RE_NEW" "$PROBE"; then
  pass "the corrected expression matches an unprefixed path"
else
  fail "the corrected expression matches an unprefixed path" "no match against $PREFIX_RE_NEW"
fi

# End to end, for both archive shapes and for each checked path.
for probe in "bin/sh|an unprefixed shell" \
             "usr/bin/bash|an unprefixed bash" \
             "etc/shadow|an unprefixed /etc/shadow" \
             "etc/passwd|an unprefixed /etc/passwd" \
             "usr/sbin/apt-get|an unprefixed package manager" \
             "bin/busybox|an unprefixed busybox" ; do
  path="${probe%%|*}"; label="${probe##*|}"
  setup_case "fs-$(printf '%s' "$path" | tr '/' '-')"
  fs_from_paths "$(make_fs "probe" "$path")" usr/local/bin/scamwall "$path"
  run_verifier
  expect_rc_nonzero "detected: $label ($path)"
done

# The prefixed shape must be detected too. tar -C . writes "./bin/sh"; the
# verifier normalises the prefix away before matching, so both shapes are
# covered by the same expression.
setup_case fs-prefixed
PDIR="$(make_fs "prefixed" "bin/sh")"
tar -cf "$FAKE_DIR/export.tar" -C "$PDIR" ./bin/sh ./usr/local/bin/scamwall
run_verifier
expect_rc_nonzero "detected: a shell written with a leading ./ in the archive"
expect_output     "the shell finding is reported" 'no shell at checked paths'

# Controls: paths that merely resemble the forbidden ones must NOT match.
setup_case fs-controls
fs_from "$(make_fs "controls" \
  "usr/local/bin/scamwall-helper" \
  "opt/sh" \
  "etc/passwd.bak" \
  "etc/shadow.example" \
  "usr/share/doc/bash/README" \
  "home/someone/bin/sh.txt" \
  "var/lib/apt-cache")"
run_verifier
expect_rc_zero   "unrelated paths do not trigger a finding"
expect_output    "absence is still asserted for the checked paths" 'PASS.*no shell at checked paths'
expect_output    "the limitation is stated in the output" 'ENUMERATED PATHS ONLY'

setup_case anchor-missing
BARE="$ROOT/fs-bare"; rm -rf "$BARE"; mkdir -p "$BARE/etc"; : > "$BARE/etc/hosts"
fs_from "$BARE"
run_verifier
expect_rc_nonzero "a listing without the scamwall binary is not trusted"
expect_output     "the untrustworthy listing is reported" 'untrustworthy|UNPROVEN'

setup_case empty-tar; : > "$FAKE_DIR/export.tar"; run_verifier
expect_rc_nonzero "an empty export is not treated as an empty filesystem"

# --- 3. Cleanup is part of the verdict ---------------------------------------
echo
echo "-- cleanup as a verdict --"
setup_case cleanup-ok; run_verifier
log_has  "the container created for filesystem enumeration is removed" "^rm -f $FS_CID\$"
log_has  "the container created by Compose is removed"                 "^rm -f $DEP_CID\$"
log_has  "the network created by Compose is removed"                   "^network rm $NET_ID\$"
if [ "$(log_count "^rm -f $FS_CID\$")" = "1" ] && [ "$(log_count "^rm -f $DEP_CID\$")" = "1" ]; then
  pass "each container is removed exactly once (cleanup is idempotent)"
else
  fail "each container is removed exactly once (cleanup is idempotent)" "counts: fs=$(log_count "^rm -f $FS_CID\$") dep=$(log_count "^rm -f $DEP_CID\$")"
fi
log_lacks "no project-wide compose down is issued" '^compose .*down'

# The cleanup implementation is now a separate file. If it is absent the
# verifier must refuse to start — creating Docker resources with no way to
# attribute or remove them is the one condition it must never proceed under.
setup_case cleanup-lib-missing
mv "$CHECKOUT/scripts/lib/docker-resources.sh" "$ROOT/docker-resources.sh.away"
run_verifier
expect_rc_nonzero "an absent resource-tracking library refuses to run"
expect_output "the refusal names the missing library" "resource-tracking library not found"
log_lacks "nothing is created when the cleanup implementation is missing" '^(create|compose create|run)'
mv "$ROOT/docker-resources.sh.away" "$CHECKOUT/scripts/lib/docker-resources.sh"

setup_case cleanup-fails
echo 1 > "$FAKE_DIR/rc.rm"
run_verifier
expect_rc_nonzero "a failed removal makes the run fail even though every check passed"
expect_output     "the cleanup failure is reported"        'cleanup INCOMPLETE|REQUIRED CLEANUP FAILED'
expect_output     "the remaining container is named"       "$FS_CID|$DEP_CID"
expect_no_output  "success is not claimed"                 'RESULT: all required runtime checks passed'

setup_case cleanup-network-fails
echo 1 > "$FAKE_DIR/rc.network-rm"
run_verifier
expect_rc_nonzero "a failed network removal makes the run fail"
expect_output     "the remaining network is named" "$NET_ID"

setup_case cleanup-interrupt-term
: > "$FAKE_DIR/term-on-inspect"
run_verifier
expect_rc_nonzero "an interrupted run exits nonzero"
expect_output     "the interruption is reported" 'interrupted by TERM'
log_has           "the interrupted run still removes what it created" "^rm -f $FS_CID\$"
if [ "$(log_count "^rm -f $FS_CID\$")" = "1" ]; then
  pass "interruption does not duplicate destructive operations"
else
  fail "interruption does not duplicate destructive operations" "removals of $FS_CID: $(log_count "^rm -f $FS_CID\$")"
fi

# A mid-run failure must still clean up what was created before it. The failure
# injected here is a failed `compose ps`, chosen because it leaves ownership
# verifiable: an injected `inspect` failure would ALSO prevent cleanup from
# establishing ownership, and the correct behaviour then is to preserve the
# resource, which the next case asserts.
setup_case cleanup-midrun-failure
echo 1 > "$FAKE_DIR/rc.compose-ps"; run_verifier
expect_rc_nonzero "a mid-run failure still fails"
log_has "cleanup runs even when verification fails part-way" "^rm -f $FS_CID\$"
log_has "and removes the container Compose had already created"  "^rm -f $DEP_CID\$"

setup_case cleanup-inspect-unavailable
echo 1 > "$FAKE_DIR/rc.inspect"; run_verifier
expect_rc_nonzero "a run whose inspections fail cannot establish ownership"
expect_output     "the preserved resources are reported" 'ownership could not be established|PRESERVED'
log_lacks         "nothing is deleted while ownership is unknown" '^rm -f '

# An unattributable container is preserved rather than removed.
setup_case cleanup-unattributable
: > "$FAKE_DIR/no-owner-label"
run_verifier
expect_rc_nonzero "a container whose ownership cannot be established is not removed"
expect_output     "the ambiguity is reported" 'ownership label|ownership could not be established|PRESERVED'
log_lacks         "no unattributable container is deleted" "^rm -f $DEP_CID\$"

# --- 4. Resource ownership ----------------------------------------------------
echo
echo "-- resource ownership --"

# A resource that already carries this invocation's project label cannot be
# ours: the identifier was chosen moments ago and is unpredictable. Compose
# would ADOPT such a container instead of creating one, so nothing is created
# and nothing is deleted.
setup_case collision-container
printf 'aaaa99999999\n' > "$FAKE_DIR/live-containers-project"
run_verifier
expect_rc_nonzero "a container already carrying this invocation's label blocks the run"
expect_output     "the collision is reported"    'collision|already carry'
log_lacks         "nothing is created after a collision" '^compose .*create'
log_lacks         "the colliding container is never removed" 'rm -f aaaa99999999'

setup_case collision-network
printf 'cccc77777777\n' > "$FAKE_DIR/live-networks"
run_verifier
expect_rc_nonzero "a network already carrying this invocation's label blocks the run"
log_lacks         "the colliding network is never removed" 'network rm cccc77777777'

# The real deployment's resources carry a DIFFERENT project label, so a
# label-filtered query never returns them. The test asserts the queries are
# always filtered — an unfiltered listing is what would put them at risk.
setup_case unrelated-preserved
printf 'dddd66666666\n' > "$FAKE_DIR/live-containers-other"
run_verifier
expect_rc_zero "a coexisting deployment does not affect the run"
log_lacks "no unfiltered container listing is performed" 'UNFILTERED-PS'
log_lacks "no unfiltered network listing is performed"   'UNFILTERED-network-LS'
log_lacks "no unfiltered volume listing is performed"    'UNFILTERED-volume-LS'
log_lacks "the deployment project is never targeted"     'compose .*-p scamwall(\s|$)|compose down|--all|prune'
log_lacks "no deployment container is removed"           'dddd66666666'

# Partial creation: Compose created the network, then failed before the
# container existed. The network is still this invocation's to remove.
setup_case partial-create
echo 1 > "$FAKE_DIR/rc.compose-create"
: > "$FAKE_DIR/no-create-container"
run_verifier
expect_rc_nonzero "a failed compose create fails the run"
expect_output     "the create failure is reported" 'compose create failed'
log_has           "the network created by the partial run is removed" "^network rm $NET_ID\$"
log_lacks         "no container assertion is claimed"   'PASS.*container user'
expect_no_output  "no container property is claimed"    'PASS.*rootfs read-only'

# A pre-existing container must never be adopted in place of one that was
# never created.
setup_case create-fail-existing
echo 1 > "$FAKE_DIR/rc.compose-create"
: > "$FAKE_DIR/no-create-container"
printf 'bbbb88888888\n' > "$FAKE_DIR/live-containers-other"
run_verifier
expect_rc_nonzero "failed create fails even though another container exists"
log_lacks "the pre-existing container is never adopted or removed" 'bbbb88888888'

# --- 5. One consistent Compose configuration ---------------------------------
echo
echo "-- consistent Compose configuration --"
setup_case env-consistency; run_verifier
expect_rc_zero "the baseline still passes"
ENV_PATH="$CHECKOUT/deploy/compose/.env"
COMPOSE_CALLS="$(grep -cE '^compose ' "$FAKE_DIR/log")" || COMPOSE_CALLS=0
COMPOSE_WITH_ENV="$(grep -cE "^compose .*--env-file $ENV_PATH" "$FAKE_DIR/log")" || COMPOSE_WITH_ENV=0
# `compose version` takes no project or env file; every other call must carry
# the same arguments.
COMPOSE_OPS="$(grep -cE '^compose .*(config|create|ps)( |$)' "$FAKE_DIR/log")" || COMPOSE_OPS=0
if [ "$COMPOSE_OPS" -ge 3 ] && [ "$COMPOSE_WITH_ENV" -eq "$COMPOSE_OPS" ]; then
  pass "every Compose operation uses the same explicit --env-file"
else
  fail "every Compose operation uses the same explicit --env-file" "ops=$COMPOSE_OPS with-env=$COMPOSE_WITH_ENV of $COMPOSE_CALLS calls"
fi
PROJECT_CALLS="$(grep -cE '^compose .*-p scamwall-verify-' "$FAKE_DIR/log")" || PROJECT_CALLS=0
if [ "$PROJECT_CALLS" -eq "$COMPOSE_OPS" ]; then
  pass "every Compose operation uses the same private project name"
else
  fail "every Compose operation uses the same private project name" "$PROJECT_CALLS of $COMPOSE_OPS"
fi
expect_output "the resolved configuration is not printed" 'never printed'
expect_no_output "no secret path content is dumped" 'BEGIN [A-Z ]*PRIVATE KEY'

setup_case config-fails; echo 1 > "$FAKE_DIR/rc.compose-config"; run_verifier
expect_rc_nonzero "a configuration that cannot be resolved blocks the run"
expect_output     "the resolution failure is reported" 'could not be resolved'
log_lacks         "nothing is created when the configuration is unresolved" '^compose .*create'

setup_case config-garbage; : > "$FAKE_DIR/config-garbage"; run_verifier
expect_rc_nonzero "unparseable configuration output blocks the run"
expect_output     "the parse failure is reported" 'not a JSON object'

setup_case config-container-name
compose_config_json '.services.scamwall.container_name = "scamwall"' > "$FAKE_DIR/compose-config.json"
run_verifier
expect_rc_nonzero "an explicit container_name blocks the run"
expect_output     "the isolation escape is named" 'container_name'
log_lacks         "nothing is created when isolation could be escaped" '^compose .*create'

setup_case config-external
compose_config_json '.networks.default.external = true' > "$FAKE_DIR/compose-config.json"
run_verifier
expect_rc_nonzero "an externally named resource blocks the run"
expect_output     "the external resource is named" 'externally named'

setup_case config-extra-service
compose_config_json '.services.sidecar = {"image":"busybox"}' > "$FAKE_DIR/compose-config.json"
run_verifier
expect_rc_nonzero "an unexpected additional service blocks the run"
expect_output     "the unexpected service is named" 'unexpected service set'

setup_case config-label-lost; : > "$FAKE_DIR/drop-label"; run_verifier
expect_rc_nonzero "a lost ownership label blocks creation"
expect_output     "the attribution failure is reported" 'ownership label did not survive'
log_lacks         "nothing unattributable is created" '^compose .*create'

# --- 6. Mounts ----------------------------------------------------------------
echo
echo "-- mounts --"

# PRE-FIX CONTROL: with .Mounts empty, the superseded assertions produced an
# empty list and therefore PASSED, while the required mounts were all absent.
EMPTY_MOUNTS='[{"Mounts":[]}]'
OLD_RO="$(jq -r '[ .[0].Mounts[]? | select(.RW != false) | (.Destination // "?") ] | join(", ")' <<<"$EMPTY_MOUNTS")"
OLD_PROHIBITED="$(jq -r '[ .[0].Mounts[]? | select((.Source // "") | test("docker\\.sock")) | .Source ] | join("; ")' <<<"$EMPTY_MOUNTS")"
if [ -z "$OLD_RO" ] && [ -z "$OLD_PROHIBITED" ]; then
  pass "PRE-FIX CONTROL: empty .Mounts satisfied the superseded assertions (the defect)"
else
  fail "PRE-FIX CONTROL: empty .Mounts satisfied the superseded assertions" "unexpected: '$OLD_RO' '$OLD_PROHIBITED'"
fi

setup_case mounts-empty
container_json '.[0].Mounts = []' > "$FAKE_DIR/container.json"
run_verifier
expect_rc_nonzero "an empty mount list fails"
expect_output     "the absence is reported as unproven, not as clean" 'no mounts at all|UNPROVEN'

setup_case mounts-absent
container_json 'del(.[0].Mounts)' > "$FAKE_DIR/container.json"
run_verifier
expect_rc_nonzero "missing mount information fails"
expect_output     "the missing field is reported" 'mount information is absent'

setup_case mounts-missing-one
container_json '.[0].Mounts |= map(select(.Destination != "/etc/scamwall/feed.json"))' > "$FAKE_DIR/container.json"
run_verifier
expect_rc_nonzero "a missing required mount fails"
expect_output     "the missing mount is named" 'required mount\(s\) missing.*feed\.json'

setup_case mounts-missing-secret
container_json '.[0].Mounts |= map(select(.Destination != "/run/secrets/pihole_app_password"))' > "$FAKE_DIR/container.json"
run_verifier
expect_rc_nonzero "a missing password mount fails"
expect_output     "the missing password mount is named" 'pihole_app_password'

setup_case mounts-extra
container_json '.[0].Mounts += [{"Type":"bind","Source":"/srv/extra","Destination":"/etc/scamwall/extra","RW":false}]' > "$FAKE_DIR/container.json"
run_verifier
expect_rc_nonzero "an unexpected mount fails"
expect_output     "the unexpected mount is named" 'unexpected mount'

setup_case mounts-duplicate
container_json '.[0].Mounts += [{"Type":"bind","Source":"/srv/other.json","Destination":"/etc/scamwall/config.json","RW":false}]' > "$FAKE_DIR/container.json"
run_verifier
expect_rc_nonzero "a duplicated mount destination fails"
expect_output     "the duplicate is reported" 'duplicate mount destinations'

setup_case mounts-writable
container_json '(.[0].Mounts[] | select(.Destination == "/etc/scamwall/config.json") | .RW) = true' > "$FAKE_DIR/container.json"
run_verifier
expect_rc_nonzero "a writable mount fails"
expect_output     "the writable mount is named" "every mount except the /tmp scratch tmpfs is read-only"

setup_case mounts-wrong-source
container_json '(.[0].Mounts[] | select(.Destination == "/etc/scamwall/feed.json") | .Source) = "/tmp/attacker/feed.json"' > "$FAKE_DIR/container.json"
run_verifier
expect_rc_nonzero "a mount whose source is not the resolved one fails"

setup_case mounts-wrong-type
container_json '(.[0].Mounts[] | select(.Destination == "/etc/scamwall/config.json") | .Type) = "volume"' > "$FAKE_DIR/container.json"
run_verifier
expect_rc_nonzero "a mount of the wrong type fails"

setup_case mounts-docker-sock
container_json '.[0].Mounts += [{"Type":"bind","Source":"/var/run/docker.sock","Destination":"/var/run/docker.sock","RW":false}]' > "$FAKE_DIR/container.json"
run_verifier
expect_rc_nonzero "a docker.sock mount invisible in .Binds is detected"
expect_output     "the prohibited mount is named" 'prohibited mount|docker\.sock'

setup_case mounts-pihole
container_json '.[0].Mounts += [{"Type":"bind","Source":"/etc/pihole","Destination":"/etc/pihole","RW":false}]' > "$FAKE_DIR/container.json"
run_verifier
expect_rc_nonzero "an /etc/pihole mount is detected"

setup_case mounts-tmpfs-elsewhere
container_json '.[0].Mounts += [{"Type":"tmpfs","Destination":"/var/scratch","RW":true}]' > "$FAKE_DIR/container.json"
run_verifier
expect_rc_nonzero "a tmpfs anywhere other than /tmp is unexpected"

setup_case mounts-claim
setup_case mounts-claim; run_verifier
expect_output "readability of the password is explicitly NOT claimed" 'does NOT prove'

# --- 6b. Mount SOURCES on the host --------------------------------------------
#
# Everything in section 6 asks whether the CONTAINER's mounts match the resolved
# configuration. These ask whether the configuration's sources are usable at
# all. The distinction matters because Docker's default for a missing bind
# source is to create an empty DIRECTORY and mount that: the container then has
# a bind mount, at the right destination, read-only, with the right source path
# — and no CA and no credential behind it. Every assertion in section 6 passes.
#
# This is also the class of failure a hosted runner hits first, since the
# operator's `/etc/scamwall/...` paths do not exist there. CI answers it by
# materialising throwaway fixtures, never by exempting itself from the check.
echo
echo "-- mount sources on the host --"

setup_case source-missing
compose_config_json '.services.scamwall.volumes |= map(if .target == "/etc/scamwall/certs/pihole-ca.crt" then .source = "'"$ROOT/srv/absent-ca.crt"'" else . end)' > "$FAKE_DIR/compose-config.json"
run_verifier
expect_rc_nonzero "a mount source that does not exist fails"
expect_output     "the missing source is named"        "absent-ca\.crt' does not exist"
expect_output     "the destination it would serve is named" '/etc/scamwall/certs/pihole-ca\.crt'
log_lacks         "nothing is created once a source is known to be missing" '^compose .*create'

setup_case source-directory
mkdir -p "$ROOT/srv/ca-as-directory"
compose_config_json '.services.scamwall.volumes |= map(if .target == "/etc/scamwall/certs/pihole-ca.crt" then .source = "'"$ROOT/srv/ca-as-directory"'" else . end)' > "$FAKE_DIR/compose-config.json"
run_verifier
expect_rc_nonzero "a mount source that is a directory fails"
expect_output     "the directory is reported as such" 'is a directory, not a file'
log_lacks         "nothing is created for a directory source" '^compose .*create'

setup_case secret-source-missing
compose_config_json '.secrets.pihole_app_password.file = "'"$ROOT/srv/secrets/absent"'"' > "$FAKE_DIR/compose-config.json"
run_verifier
expect_rc_nonzero "a missing password file fails"
expect_output     "the missing password file is named" "absent' does not exist"

# A world-reachable secret. The fixture must live OUTSIDE the 0700 test root,
# because reachability is a property of the whole path, not of the file's mode.
WORLD_DIR="${TMPDIR:-/tmp}/scamwall-rvtest-world.$$"
mkdir -p "$WORLD_DIR" && chmod 755 "$WORLD_DIR"
WORLD_SECRET_FILE="$WORLD_DIR/pihole_app_password"
printf 'test-only-password\n' > "$WORLD_SECRET_FILE" && chmod 644 "$WORLD_SECRET_FILE"
# shellcheck disable=SC2064  # $WORLD_DIR must expand now, not at trap time
trap "rm -rf -- '$ROOT' '$WORLD_DIR'" EXIT

setup_case secret-world-readable
compose_config_json '.secrets.pihole_app_password.file = "'"$WORLD_SECRET_FILE"'"' > "$FAKE_DIR/compose-config.json"
run_verifier
expect_rc_nonzero "a world-readable password file fails"
expect_output     "the exposure is reported" 'readable by every account'
expect_no_output  "the password itself is never printed" 'test-only-password'

setup_case secret-not-world-readable
# 0640, not 0600: the verifier now also judges whether the container identity
# could read the file, and a file with no group-read bit fails that for a
# reason unrelated to world-reachability, which is what this case is about.
chmod 640 "$WORLD_SECRET_FILE"
compose_config_json '.secrets.pihole_app_password.file = "'"$WORLD_SECRET_FILE"'"' > "$FAKE_DIR/compose-config.json"
# The container fixture is moved with it. A source the configuration resolves
# and a source the container actually has must agree, and that agreement is
# asserted elsewhere; leaving it out here would fail this case for a reason
# that has nothing to do with file permissions.
container_json '(.[0].Mounts[] | select(.Destination == "/run/secrets/pihole_app_password") | .Source) = "'"$WORLD_SECRET_FILE"'"' > "$FAKE_DIR/container.json"
run_verifier
expect_rc_zero   "a password file that is not world-readable passes"
expect_output    "the check states what it does NOT establish" 'never starts the container'
chmod 644 "$WORLD_SECRET_FILE"

# --- The supplementary group and the file it is supposed to open --------------
#
# Carried forward from Phase 1 as work-order item 9: the verifier asserted the
# supplementary group's VALUE and never related it to the password file's
# ownership. A deployment could therefore satisfy every assertion while the
# container identity had no permission to read its own credential.
#
# Each case below is a world in which the superseded checks are satisfied. The
# PRE-FIX CONTROL states that explicitly rather than leaving it implied: it
# asserts that the two assertions the verifier used to make — the group is a
# valid non-root gid, and the file is not world-readable — both still report
# PASS in the very world the new assertion rejects.
NOGROUP_SRC="$SRV/secrets/no-group-read"
printf 'test-only-password\n' > "$NOGROUP_SRC"
chmod 600 "$NOGROUP_SRC"

setup_case secret-group-not-owner
# A gid that is valid, non-root, and is NOT the gid that owns the file.
compose_config_json '.services.scamwall.group_add = ["4242"]' > "$FAKE_DIR/compose-config.json"
run_verifier
expect_rc_nonzero "a supplementary group that does not own the password file fails"
expect_output     "the mismatch is reported as a readability failure" 'would NOT be readable by the container identity'
expect_output     "the observed ownership is reported as metadata" 'gid=[0-9]+ mode=[0-7]{4}'
expect_no_output  "the password itself is never printed" 'test-only-password'
expect_output     "PRE-FIX CONTROL: the group is still a valid non-root gid (the superseded assertion)" \
                  'supplementary group resolves to a single valid non-root gid \(4242\)'
expect_output     "PRE-FIX CONTROL: the file is still not world-readable (the superseded assertion)" \
                  'not world-readable through its path'
log_lacks         "nothing is created when the credential is unreadable" '^compose .*create'

setup_case secret-no-group-read
# The right group owns it, and the group-read bit is unset. This is the case a
# gid-equality check alone would pass.
compose_config_json '.secrets.pihole_app_password.file = "'"$NOGROUP_SRC"'"' > "$FAKE_DIR/compose-config.json"
container_json '(.[0].Mounts[] | select(.Destination == "/run/secrets/pihole_app_password") | .Source) = "'"$NOGROUP_SRC"'"' > "$FAKE_DIR/container.json"
run_verifier
expect_rc_nonzero "a password file with no group-read bit fails"
expect_output     "the unset group-read bit is reported" 'group-read bit is unset'

setup_case secret-owner-read
# The other way a read can legitimately be granted: the file's OWNER is the
# container's uid. The configuration is mutated so that the container identity
# is this account, which owns the fixture.
compose_config_json '.services.scamwall.user = "'"$(id -u)"':'"$(id -g)"'" | .secrets.pihole_app_password.file = "'"$NOGROUP_SRC"'"' > "$FAKE_DIR/compose-config.json"
container_json '(.[0].Mounts[] | select(.Destination == "/run/secrets/pihole_app_password") | .Source) = "'"$NOGROUP_SRC"'"' > "$FAKE_DIR/container.json"
run_verifier
expect_rc_zero   "a password file owned by the container uid passes on the owner class"
expect_output    "the granting permission class is named" "the file's owner uid"

setup_case secret-user-not-numeric
compose_config_json '.services.scamwall.user = "scamwall"' > "$FAKE_DIR/compose-config.json"
run_verifier
expect_rc_nonzero "a non-numeric container identity blocks the run"
expect_output     "the unusable identity is reported" 'not a single numeric uid:gid'

setup_case secret-userns-remap
# A daemon that remaps user namespaces makes the host metadata describe
# different ids than the container sees, so the judgement above cannot stand.
printf '[name=seccomp,profile=builtin name=userns]\n' > "$FAKE_DIR/info-security"
run_verifier
expect_rc_nonzero "a user-namespace-remapping daemon invalidates the readability judgement"
expect_output     "the remapping is reported" 'user-namespace remapping'

setup_case secret-rootless
printf '[name=rootless name=seccomp,profile=builtin]\n' > "$FAKE_DIR/info-security"
run_verifier
expect_rc_nonzero "a rootless daemon invalidates the readability judgement"
expect_output     "the rootless daemon is reported" 'rootless'

setup_case secret-userns-absent
printf '[name=seccomp,profile=builtin name=cgroupns]\n' > "$FAKE_DIR/info-security"
run_verifier
expect_rc_zero   "a daemon that reports no remapping is accepted"
expect_output    "the absence of remapping is recorded" 'no user-namespace remapping'

setup_case secret-source-prohibited
compose_config_json '.secrets.pihole_app_password.file = "/etc/pihole/setupVars.conf"' > "$FAKE_DIR/compose-config.json"
run_verifier
expect_rc_nonzero "a password file taken from a prohibited path fails"
expect_output     "the prohibited source is named" 'prohibited path.*(/etc/pihole|pihole_app_password)'

# PRE-FIX CONTROL: the superseded prohibited-path expression inspected
# `.services.<svc>.volumes` only. A secret file pointed at /etc/pihole is
# declared under `.secrets`, so it was not examined at all — and
# SCAMWALL_SECRET_FILE is an environment override, which makes it the easiest
# source in the whole definition to redirect.
PROHIBITED_FIXTURE="$(compose_config_json '.secrets.pihole_app_password.file = "/etc/pihole/setupVars.conf"')"
OLD_PROHIBITED="$(jq -r '
  [ (.services."scamwall".volumes // [])[]
      | select(((.source // "") | test("docker\\.sock|^/etc/pihole|^/proc|^/sys")))
      | (.source // "?") ] | join("; ")' <<<"$PROHIBITED_FIXTURE")"
NEW_PROHIBITED="$(jq -r '
  [ ((.services."scamwall".volumes // [])[] | { source: (.source // "") }),
    ((.secrets // {}) | to_entries[] | { source: (.value.file // "") })
      | select((.source | test("docker\\.sock|^/etc/pihole|^/proc|^/sys")))
      | .source ] | join("; ")' <<<"$PROHIBITED_FIXTURE")"
if [ -z "$OLD_PROHIBITED" ] && [ -n "$NEW_PROHIBITED" ]; then
  pass "PRE-FIX CONTROL: the superseded expression exempted the secret source (the defect)"
else
  fail "PRE-FIX CONTROL: the superseded expression exempted the secret source" \
       "old='$OLD_PROHIBITED' new='$NEW_PROHIBITED'"
fi

# --- 7. Inspection output that is structurally valid but incomplete ----------
echo
echo "-- incomplete and malformed inspection data --"
setup_case bad-json; printf 'this is not json\n' > "$FAKE_DIR/container.json"; run_verifier
expect_rc_nonzero "unparseable container JSON fails"
expect_output     "the parse failure is reported" 'not a single-element JSON array'

setup_case empty-json; printf '[]\n' > "$FAKE_DIR/container.json"; run_verifier
expect_rc_nonzero "an empty inspection array fails"

setup_case bad-image-json; printf '{"broken":\n' > "$FAKE_DIR/image-inspect.json"; run_verifier
expect_rc_nonzero "unparseable image JSON blocks verification"

setup_case image-json-not-array; printf '{"Id":"sha256:abc"}\n' > "$FAKE_DIR/image-inspect.json"; run_verifier
expect_rc_nonzero "image inspection that is not a single-element array blocks verification"

setup_case image-id-not-digest
printf '[{"Id":"scamwall:local","Config":{"User":"65532:65532"}}]\n' > "$FAKE_DIR/image-inspect.json"
run_verifier
expect_rc_nonzero "an image identifier that is not a digest blocks verification"
expect_output     "the identifier is reported" 'not a sha256 digest'

# Structurally valid JSON with required fields missing must FAIL, not be
# defaulted into a pass.
for probe in \
  'del(.[0].HostConfig.LogConfig)|missing log configuration' \
  'del(.[0].HostConfig.LogConfig.Config)|missing log options' \
  'del(.[0].HostConfig.ExtraHosts)|missing hostname pinning' \
  'del(.[0].HostConfig.Tmpfs)|missing tmpfs configuration' \
  'del(.[0].HostConfig.GroupAdd)|missing supplementary group' \
  'del(.[0].HostConfig.Memory)|missing memory limit' \
  'del(.[0].HostConfig.PidsLimit)|missing pids limit' \
  'del(.[0].HostConfig.NanoCpus)|missing cpu limit' \
  'del(.[0].HostConfig.RestartPolicy)|missing restart policy' \
  'del(.[0].State)|missing state' \
  'del(.[0].Config.User)|missing user' \
  '.[0].HostConfig = {}|empty HostConfig' \
; do
  mutation="${probe%%|*}"; label="${probe##*|}"
  setup_case "incomplete"
  container_json "$mutation" > "$FAKE_DIR/container.json"
  run_verifier
  expect_rc_nonzero "detected: $label"
done

# --- 8. Image identity --------------------------------------------------------
echo
echo "-- image identity --"
setup_case image-mismatch
container_json ".[0].Image = \"$OTHER_ID\"" > "$FAKE_DIR/container.json"
image_json "$OTHER_ID" > "$FAKE_DIR/image-inspect.$(printf '%s' "$OTHER_ID" | tr -c 'a-zA-Z0-9' '_').json"
run_verifier
expect_rc_nonzero "a container running a different image fails"
expect_output     "the mismatch is reported" 'container image mismatch'

# Tag movement: the tag resolved to IMAGE_ID, but by the time Compose created
# the container the tag pointed at OTHER_ID. Compose creates from the tag, so
# this is exactly what a mid-run repoint looks like.
setup_case tag-moved
container_json ".[0].Image = \"$OTHER_ID\"" > "$FAKE_DIR/container.json"
image_json "$OTHER_ID" > "$FAKE_DIR/image-inspect.$(printf '%s' "$OTHER_ID" | tr -c 'a-zA-Z0-9' '_').json"
run_verifier
expect_rc_nonzero "a tag moved between resolution and creation is detected"
expect_output     "the possibility is named in the report" 'tag moved'

# Not every difference is a mismatch: an image store may record a different
# identifier for the SAME image. The identifiers are resolved and compared,
# and equivalence is accepted with both values reported.
setup_case image-equivalent-id
container_json ".[0].Image = \"$MANIFEST_ID\"" > "$FAKE_DIR/container.json"
image_json "$IMAGE_ID" > "$FAKE_DIR/image-inspect.$(printf '%s' "$MANIFEST_ID" | tr -c 'a-zA-Z0-9' '_').json"
run_verifier
expect_rc_zero "an equivalent identifier that resolves to the same image passes"
expect_output  "both identifiers are reported" "$MANIFEST_ID"

setup_case pinned-id-mismatch
OUT="$(PATH="$BIN:$PATH" SCAMWALL_IMAGE=scamwall:local \
      SCAMWALL_EXPECTED_IMAGE_ID="$OTHER_ID" \
      "$CHECKOUT/scripts/container-runtime-verify.sh" 2>&1)"; RC=$?
expect_rc_nonzero "a resolved image ID differing from the pinned one fails"
expect_output     "the pin mismatch is reported" 'SCAMWALL_EXPECTED_IMAGE_ID'

setup_case pinned-id-malformed
OUT="$(PATH="$BIN:$PATH" SCAMWALL_IMAGE=scamwall:local \
      SCAMWALL_EXPECTED_IMAGE_ID="not-a-digest" \
      "$CHECKOUT/scripts/container-runtime-verify.sh" 2>&1)"; RC=$?
expect_rc_nonzero "a malformed pin is rejected rather than ignored"

# Every image-level operation must use the resolved ID, never the tag.
setup_case image-id-used; run_verifier
log_has  "image history is read by immutable ID" "^history --no-trunc --format \{\{\.CreatedBy\}\} $IMAGE_ID\$"
log_has  "the filesystem container is created from the immutable ID" "^create --label scamwall\.verify\.invocation=[0-9a-f]+ $IMAGE_ID\$"
log_lacks "no image operation uses the mutable tag" '^(history|create) .*scamwall:local'

# --- 9. Searches distinguish absence from failure ----------------------------
echo
echo "-- absence versus search failure --"
setup_case history-fail; echo 1 > "$FAKE_DIR/rc.history"; run_verifier
expect_rc_nonzero "failed docker history fails"
expect_output     "the history failure is reported" 'image history could not be read'
expect_no_output  "error text is not accepted as a clean history" 'PASS.*no credential pattern'

setup_case history-credential
printf 'RUN echo password=hunter2 > /etc/config\n' > "$FAKE_DIR/history.txt"
run_verifier
expect_rc_nonzero "a credential pattern in build instructions fails"
expect_output     "the match is reported" 'credential pattern matched'

setup_case history-scope; run_verifier
expect_output "the history check states its limits" 'NOT proof'

# The helper contract, exercised directly: matched / did not match / could not
# search must be three distinct answers.
PROBE_OK="$ROOT/search-ok.txt"; printf 'alpha\nbeta\n' > "$PROBE_OK"
search_file 'alpha' "$PROBE_OK"; rc_match=$?
search_file 'gamma' "$PROBE_OK"; rc_nomatch=$?
search_file 'alpha' "$ROOT/does-not-exist.txt"; rc_missing=$?
search_file 'alpha' "$ROOT"; rc_dir=$?
if [ "$rc_match" -eq 0 ] && [ "$rc_nomatch" -eq 1 ] && [ "$rc_missing" -eq 2 ] && [ "$rc_dir" -eq 2 ]; then
  pass "search_file reports match, no-match and could-not-search distinctly"
else
  fail "search_file reports match, no-match and could-not-search distinctly" \
       "match=$rc_match nomatch=$rc_nomatch missing=$rc_missing dir=$rc_dir"
fi

# PRE-FIX CONTROL: the superseded shape collapsed the third outcome into the
# second, so a search that never ran was reported as a clean result.
if grep -qE 'alpha' "$ROOT/does-not-exist.txt" 2>/dev/null; then
  fail "PRE-FIX CONTROL: an unperformed search looked like a clean result" "grep matched, so this control proves nothing"
else
  pass "PRE-FIX CONTROL: an unperformed search looked like a clean result (the defect)"
fi

if ! count_matches 'x' "$ROOT/does-not-exist.txt" >/dev/null 2>&1; then
  pass "count_matches reports a failed search rather than a zero count"
else
  fail "count_matches reports a failed search rather than a zero count" "it returned success"
fi
if ZERO="$(count_matches 'gamma' "$PROBE_OK")" && [ "$ZERO" = "0" ]; then
  pass "count_matches reports a genuine zero count as zero"
else
  fail "count_matches reports a genuine zero count as zero" "got '${ZERO:-<none>}'"
fi

setup_case export-fail; echo 1 > "$FAKE_DIR/rc.export"; run_verifier
expect_rc_nonzero "failed docker export fails"
expect_output     "enumeration failure is reported as unproven" 'docker export failed.*UNPROVEN'
expect_no_output  "no path absence is claimed" 'PASS.*no shell at checked paths'

setup_case create-fail; echo 1 > "$FAKE_DIR/rc.create"; run_verifier
expect_rc_nonzero "a failed docker create fails"
expect_output     "the failure is reported as unproven" 'docker create failed.*UNPROVEN'

setup_case inspect-fail; echo 1 > "$FAKE_DIR/rc.inspect"; run_verifier
expect_rc_nonzero "failed container inspect fails"
expect_output     "the inspect failure is reported" 'container inspection failed'

setup_case image-inspect-fail; echo 1 > "$FAKE_DIR/rc.image-inspect"; run_verifier
expect_rc_nonzero "failed image inspect blocks verification"
expect_output     "the image inspect failure is reported" 'could not be inspected'

setup_case compose-ps-fail; echo 1 > "$FAKE_DIR/rc.compose-ps"; run_verifier
expect_rc_nonzero "a failed compose ps fails"

setup_case ps-query-fail; echo 1 > "$FAKE_DIR/rc.ps"; run_verifier
expect_rc_nonzero "a failed container listing fails rather than reporting none"

# --- 10. tmpfs bounds ---------------------------------------------------------
echo
echo "-- tmpfs bounds --"
# Finding the substring `size=` proves nothing about the value. Each of these
# contains it and must still fail.
for probe in \
  'rw,noexec,nosuid,nodev,size=0|a zero-byte tmpfs' \
  'rw,noexec,nosuid,nodev,size=999g|an oversized tmpfs' \
  'rw,noexec,nosuid,nodev,size=|an empty size value' \
  'rw,noexec,nosuid,nodev,size=abc|a non-numeric size' \
  'rw,noexec,nosuid,nodev|no size at all' \
  'rw,nosuid,nodev,size=16m|missing noexec' \
  'rw,noexec,nodev,size=16m|missing nosuid' \
  'rw,noexec,nosuid,size=16m|missing nodev' \
  'rw,noexec,nosuid,nodev,exec,size=16m|exec re-enabled' \
  'rw,noexec,nosuid,nodev,size=16m,whatever|an unrecognised option' \
; do
  opts="${probe%%|*}"; label="${probe##*|}"
  setup_case "tmpfs"
  container_json ".[0].HostConfig.Tmpfs = {\"/tmp\": \"$opts\"}" > "$FAKE_DIR/container.json"
  compose_config_json ".services.scamwall.tmpfs = [\"/tmp:$opts\"]" > "$FAKE_DIR/compose-config.json"
  run_verifier
  expect_rc_nonzero "detected: $label"
done

setup_case tmpfs-disagree
container_json '.[0].HostConfig.Tmpfs = {"/tmp": "rw,noexec,nosuid,nodev,size=8m"}' > "$FAKE_DIR/container.json"
run_verifier
expect_rc_nonzero "container tmpfs options differing from the configuration fail"
# The size parser itself.
if [ "$(size_to_bytes 16m)" = "16777216" ]; then
  pass "size_to_bytes converts 16m"
else
  fail "size_to_bytes converts 16m" "got $(size_to_bytes 16m)"
fi
if size_to_bytes "16mb" >/dev/null 2>&1; then
  fail "size_to_bytes rejects a malformed size" "16mb was accepted"
else
  pass "size_to_bytes rejects a malformed size"
fi

# --- 11. Logging bounds -------------------------------------------------------
echo
echo "-- logging bounds --"
for probe in \
  'del(.services.scamwall.logging)|no logging configuration' \
  '.services.scamwall.logging.driver = "syslog"|an unbounded remote driver' \
  'del(.services.scamwall.logging.options["max-size"])|no max-size' \
  'del(.services.scamwall.logging.options["max-file"])|no max-file' \
  '.services.scamwall.logging.options["max-size"] = "0"|a zero max-size' \
  '.services.scamwall.logging.options["max-size"] = "500m"|an oversized max-size' \
  '.services.scamwall.logging.options["max-file"] = "0"|a zero max-file' \
  '.services.scamwall.logging.options["max-file"] = "many"|a non-numeric max-file' \
  '.services.scamwall.logging.options["max-file"] = "99"|an excessive file count' \
; do
  mutation="${probe%%|*}"; label="${probe##*|}"
  setup_case "logging"
  compose_config_json "$mutation" > "$FAKE_DIR/compose-config.json"
  run_verifier
  expect_rc_nonzero "detected: $label"
done

setup_case logging-container-disagrees
container_json '.[0].HostConfig.LogConfig.Config["max-size"] = "500m"' > "$FAKE_DIR/container.json"
run_verifier
expect_rc_nonzero "a container whose log bound differs from the configuration fails"

setup_case logging-driver-disagrees
container_json '.[0].HostConfig.LogConfig.Type = "syslog"' > "$FAKE_DIR/container.json"
run_verifier
expect_rc_nonzero "a container using a different log driver fails"

# --- 12. Hostname pinning -----------------------------------------------------
echo
echo "-- API hostname pinning --"
setup_case pin-missing
container_json '.[0].HostConfig.ExtraHosts = []' > "$FAKE_DIR/container.json"
run_verifier
expect_rc_nonzero "a container with no hostname pin fails"
expect_output     "the pin is named" 'API hostname pinned'

setup_case pin-wrong
container_json '.[0].HostConfig.ExtraHosts = ["pi.hole:203.0.113.9"]' > "$FAKE_DIR/container.json"
run_verifier
expect_rc_nonzero "a pin to an address other than the configured one fails"

setup_case pin-extra
container_json '.[0].HostConfig.ExtraHosts += ["pi.hole:203.0.113.9"]' > "$FAKE_DIR/container.json"
run_verifier
expect_rc_nonzero "a second, conflicting pin fails"

setup_case pin-config-missing
compose_config_json 'del(.services.scamwall.extra_hosts)' > "$FAKE_DIR/compose-config.json"
run_verifier
expect_rc_nonzero "a configuration with no hostname pin blocks the run"

setup_case pin-config-wrong-name
compose_config_json '.services.scamwall.extra_hosts = ["evil.example=203.0.113.9"]' > "$FAKE_DIR/compose-config.json"
run_verifier
expect_rc_nonzero "a pin for a different hostname blocks the run"

setup_case pin-ipv6
compose_config_json '.services.scamwall.extra_hosts = ["pi.hole=2001:db8::1"]' > "$FAKE_DIR/compose-config.json"
container_json '.[0].HostConfig.ExtraHosts = ["pi.hole:2001:db8::1"]' > "$FAKE_DIR/container.json"
run_verifier
expect_rc_zero "an IPv6 pin is accepted and compared exactly"

# --- 13. Supplementary group --------------------------------------------------
echo
echo "-- supplementary group --"
setup_case gid-zero
compose_config_json '.services.scamwall.group_add = ["0"]' > "$FAKE_DIR/compose-config.json"
container_json '.[0].HostConfig.GroupAdd = ["0"]' > "$FAKE_DIR/container.json"
run_verifier
expect_rc_nonzero "the root group is not accepted as a supplementary group"

setup_case gid-nonnumeric
compose_config_json '.services.scamwall.group_add = ["pihole"]' > "$FAKE_DIR/compose-config.json"
run_verifier
expect_rc_nonzero "a non-numeric supplementary group is rejected"

setup_case gid-multiple
compose_config_json '.services.scamwall.group_add = ["989","0"]' > "$FAKE_DIR/compose-config.json"
run_verifier
expect_rc_nonzero "more than one supplementary group is rejected"

setup_case gid-container-disagrees
container_json '.[0].HostConfig.GroupAdd = ["0"]' > "$FAKE_DIR/container.json"
run_verifier
expect_rc_nonzero "a container whose group differs from the configuration fails"

# --- 14. Hardening regressions ------------------------------------------------
echo
echo "-- hardening regressions --"
for probe in \
  '.[0].HostConfig.ReadonlyRootfs = false|writable rootfs' \
  '.[0].HostConfig.Privileged = true|privileged container' \
  '.[0].HostConfig.CapAdd = ["NET_ADMIN"]|added capability' \
  '.[0].HostConfig.CapDrop = []|capabilities not dropped' \
  '.[0].HostConfig.SecurityOpt = ["seccomp:unconfined"]|unconfined seccomp' \
  '.[0].HostConfig.SecurityOpt = []|no-new-privileges absent' \
  '.[0].HostConfig.Init = false|no init process' \
  '.[0].HostConfig.NetworkMode = "host"|host networking' \
  '.[0].HostConfig.NetworkMode = "container:other"|shared network namespace' \
  '.[0].HostConfig.PortBindings = {"53/tcp":[{"HostPort":"53"}]}|published port' \
  '.[0].NetworkSettings.Ports = {"53/tcp":null}|exposed container port' \
  '.[0].HostConfig.PidsLimit = 0|no pids limit' \
  '.[0].HostConfig.Memory = 0|no memory limit' \
  '.[0].HostConfig.MemorySwap = 268435456|swap above the memory limit' \
  '.[0].HostConfig.NanoCpus = 0|no cpu limit' \
  '.[0].HostConfig.RestartPolicy.Name = "always"|a restarting one-shot task' \
  '.[0].Config.User = "0:0"|root user' \
; do
  mutation="${probe%%|*}"; label="${probe##*|}"
  setup_case "probe"
  container_json "$mutation" > "$FAKE_DIR/container.json"
  run_verifier
  expect_rc_nonzero "detected: $label"
done

for probe in \
  '.[0].Config.Healthcheck = {"Test":["CMD","true"]}|an image healthcheck' \
  '.[0].Config.ExposedPorts = {"53/tcp":{}}|an image exposing a port' \
  '.[0].Config.User = "root"|an image running as root' \
; do
  mutation="${probe%%|*}"; label="${probe##*|}"
  setup_case "image-probe"
  image_json "$IMAGE_ID" | jq "$mutation" > "$FAKE_DIR/image-inspect.json"
  run_verifier
  expect_rc_nonzero "detected: $label"
done

# --- 15. No application execution during inspection ---------------------------
echo
echo "-- no application execution --"
setup_case no-exec; run_verifier
log_lacks "the container is never started"        '^(start|compose .*(up|start|run))'
log_lacks "no command is executed in a container" '^(exec|run) '
expect_output "the created-not-running state is asserted" 'PASS.*container is created, not running'

for probe in \
  '.[0].State.Status = "running"|a running container' \
  '.[0].State.Running = true|a container reported as running' \
  '.[0].State.Pid = 4242|a container with a process id' \
  '.[0].State.StartedAt = "2026-01-01T00:00:00Z"|a container that has been started' \
  '.[0].RestartCount = 2|a container that has already restarted' \
; do
  mutation="${probe%%|*}"; label="${probe##*|}"
  setup_case "exec-probe"
  container_json "$mutation" > "$FAKE_DIR/container.json"
  run_verifier
  expect_rc_nonzero "detected: $label"
done

VERIFIER_SRC="$(sed 's/#.*$//' "$VERIFIER")"
# Only a COMMAND POSITION counts: `docker` at the start of a line or after a
# shell operator. Matching the bare word anywhere would flag the prose in
# "docker compose plugin unavailable — ... cannot run", which is a message, not
# an invocation.
CMD_POS='(^|[;|&(]|then |else |do |! )[[:space:]]*'
if grep -qE "${CMD_POS}docker[[:space:]]+(start|run|exec)([[:space:]]|$)|${CMD_POS}docker[[:space:]]+compose[[:space:]][^\"]*[[:space:]](up|start|run)([[:space:]]|$)" <<<"$VERIFIER_SRC"; then
  fail "the verifier contains no container-start operation" "a start/run/exec command appears outside comments"
else
  pass "the verifier contains no container-start operation"
fi

# --- 16. Daemon availability --------------------------------------------------
echo
echo "-- daemon availability --"
setup_case no-daemon; echo 1 > "$FAKE_DIR/rc.info"; run_verifier
expect_rc_nonzero "an unreachable daemon blocks verification"
expect_output     "the block is reported, not skipped" 'BLOCKED.*docker daemon not reachable'
expect_output     "the result is stated as incomplete" 'INCOMPLETE'
expect_no_output  "no container property is claimed" 'PASS.*rootfs read-only'

setup_case no-compose; echo 1 > "$FAKE_DIR/rc.compose-version"; run_verifier
expect_rc_nonzero "a missing compose plugin blocks verification"

# --- 17. The operator path works without git ----------------------------------
echo
echo "-- no git dependency --"
setup_case no-git; run_verifier
expect_rc_zero "verification succeeds with a git that refuses every call"
if [ -s "$FAKE_DIR/git-log" ]; then
  fail "git is never invoked by the Docker verification path" "git was called: $(tr '\n' '|' < "$FAKE_DIR/git-log")"
else
  pass "git is never invoked by the Docker verification path"
fi
if grep -qE '(^|[^a-z-])git (rev-parse|status|config|ls-files)' <<<"$VERIFIER_SRC"; then
  fail "the verifier contains no git invocation" "a git command appears outside comments"
else
  pass "the verifier contains no git invocation"
fi

# --- 18. Static linkage is proven by ELF inspection ---------------------------
echo
echo "-- static linkage assertion --"
DOCKERFILE_NC="$(sed 's/#.*$//' "$REPO/container/Dockerfile")"
if grep -qE '^RUN .*ldd ' <<<"$DOCKERFILE_NC"; then
  fail "the ldd-based linkage assertion is gone" "an ldd assertion is still present"
else
  pass "the ldd-based linkage assertion is gone"
fi
if grep -qE '^RUN .*elfcheck' <<<"$DOCKERFILE_NC"; then
  pass "linkage is asserted by checked ELF inspection"
else
  fail "linkage is asserted by checked ELF inspection" "no elfcheck invocation in the Dockerfile"
fi
if [ -f "$REPO/internal/buildcheck/elfcheck/main_test.go" ]; then
  pass "the ELF checker has positive and negative controls (internal/buildcheck/elfcheck)"
else
  fail "the ELF checker has positive and negative controls" "main_test.go not found"
fi
if grep -qE 'grep -q' <<<"$DOCKERFILE_NC"; then
  if grep -qE '\| *grep -q' <<<"$DOCKERFILE_NC"; then
    fail "no producer-to-grep -q pipeline in the Dockerfile" "a piped grep -q remains"
  else
    pass "no producer-to-grep -q pipeline in the Dockerfile"
  fi
else
  pass "no producer-to-grep -q pipeline in the Dockerfile"
fi

# --- 19. Resource-list processing failures ------------------------------------
#
# The lists that decide what is preserved and what is deleted were combined by
# `printf | grep -v | sort -u` and the result was returned unconditionally. A
# combination that could not run produced an empty string, which the
# pre-snapshot read as "no collision" and cleanup read as "nothing to sweep".
echo
echo "-- resource list processing --"

pre_fix_combine() { # the superseded form, kept as a control
  printf '%s\n%s\n' "$1" "$2" | grep -v '^$' | sort -u
  return 0
}

# with_fake_bin <command...> — run a command with the scripted daemon and the
# controllable sort ahead of the real ones. The body is a subshell, so the PATH
# change is deliberately local: a variable assignment prefixed to a shell
# function persists in the calling shell afterwards, and leaking the fake bin
# onto PATH would silently arm the scripted daemon for every later case.
# shellcheck disable=SC2030,SC2031  # the subshell-local PATH is the point
with_fake_bin() ( PATH="$BIN:$PATH"; "$@" )

setup_case combine-broken-sort
: > "$FAKE_DIR/break-sort-u"
if OUT_C="$(with_fake_bin pre_fix_combine 'aaa111111111' 'bbb222222222' 2>/dev/null)"; then
  if [ -z "$OUT_C" ]; then
    pass "PRE-FIX CONTROL: the superseded combination reported success with an empty result (the defect)"
  else
    fail "PRE-FIX CONTROL: the superseded combination reported success with an empty result" "it produced '$OUT_C'"
  fi
else
  fail "PRE-FIX CONTROL: the superseded combination reported success with an empty result" "it returned nonzero, so this control proves nothing"
fi
if with_fake_bin combine_ids 'aaa111111111' 'bbb222222222' >/dev/null 2>&1; then
  fail "combine_ids reports a failed combination" "it returned 0 while sort could not run"
else
  pass "combine_ids reports a failed combination"
fi

setup_case combine-empty
if OUT_C="$(with_fake_bin combine_ids '' '')"; then
  if [ -z "$OUT_C" ]; then
    pass "combine_ids distinguishes an obtained empty list from a failure"
  else
    fail "combine_ids distinguishes an obtained empty list from a failure" "expected no output, got '$OUT_C'"
  fi
else
  fail "combine_ids distinguishes an obtained empty list from a failure" "an empty pair of lists was reported as a failure"
fi
if OUT_C="$(with_fake_bin combine_ids 'bbb222222222' 'aaa111111111')" \
   && [ "$OUT_C" = "$(printf 'aaa111111111\nbbb222222222')" ]; then
  pass "combine_ids returns the sorted union of two lists"
else
  fail "combine_ids returns the sorted union of two lists" "got '$OUT_C'"
fi

# End to end: the network sweep is the one combination that runs over a
# non-empty list, so a sort that cannot run must make the run fail rather than
# silently sweep nothing.
setup_case sweep-processing-fails
: > "$FAKE_DIR/break-sort-u"
run_verifier
expect_rc_nonzero "a resource list that could not be processed fails the run"
expect_output     "the processing failure is named" 'could not be combined'
expect_no_output  "cleanup is not reported as complete" 'cleanup complete'

# --- 20. Named resources cannot escape the invocation's namespace -------------
#
# `external: true` is not the only escape. A non-external network or volume
# with an explicit `name:` is created OR ADOPTED by that exact name, which may
# be a resource the real deployment owns.
echo
echo "-- named-resource isolation --"

OLD_EXTERNAL_ONLY="$(jq -r '[ (.networks // {}), (.volumes // {}), (.secrets // {}) | to_entries[]
                              | select(.value.external == true) | .key ] | join(",")' \
                     <<<'{"networks":{"default":{"name":"pihole_shared_net"}}}')"
if [ -z "$OLD_EXTERNAL_ONLY" ]; then
  pass "PRE-FIX CONTROL: the superseded check saw nothing wrong with a fixed, non-external network name (the defect)"
else
  fail "PRE-FIX CONTROL: the superseded check saw nothing wrong with a fixed, non-external network name" "it reported '$OLD_EXTERNAL_ONLY'"
fi

setup_case named-network-outside
printf '%s' '.networks.default.name = "pihole_shared_net"' > "$FAKE_DIR/config-mutate"
run_verifier
expect_rc_nonzero "a network named outside the invocation's namespace blocks the run"
expect_output     "the escaping name is reported" "escape project isolation.*pihole_shared_net"
log_lacks         "nothing is created, so no pre-existing network can be adopted" '^compose .*create'
log_lacks         "no network is removed"                                        '^network rm'
log_lacks         "no volume is removed"                                         '^volume rm'


setup_case named-volume-outside
printf '%s' '.volumes = {"data": {"name": "scamwall_shared_data", "external": false}}' > "$FAKE_DIR/config-mutate"
run_verifier
expect_rc_nonzero "a volume named outside the invocation's namespace blocks the run"
expect_output     "the escaping volume name is reported" "escape project isolation.*scamwall_shared_data"
log_lacks         "nothing is created for an escaping volume name" '^compose .*create'
log_lacks         "no volume is removed for an escaping volume name" '^volume rm'

# A resource that already exists under the name the configuration fixes must be
# left exactly as it was: not adopted, not reconfigured, not deleted.
setup_case named-network-preexisting
printf '%s' '.networks.default.name = "pihole_shared_net"' > "$FAKE_DIR/config-mutate"
printf 'pihole_shared_net\n' > "$FAKE_DIR/live-networks"
run_verifier
expect_rc_nonzero "a run that would adopt a pre-existing named network fails"
log_lacks "the pre-existing network is never removed" 'network rm'
if [ -s "$FAKE_DIR/removed" ]; then
  fail "no resource at all is removed when a name would escape isolation" "removed: $(tr '\n' ' ' < "$FAKE_DIR/removed")"
else
  pass "no resource at all is removed when a name would escape isolation"
fi

setup_case named-volume-inside
# $p is a jq variable bound by the fake's `--arg p`, not a shell variable.
# shellcheck disable=SC2016
printf '%s' '.volumes = {"data": {"name": ($p + "_data")}}' > "$FAKE_DIR/config-mutate"
run_verifier
expect_rc_zero "a volume named inside the invocation's namespace is accepted"
expect_output  "the namespaced name is confirmed" 'volumes name.*inside this invocation'

# --- 21. Mount comparison errors are not suppressed ---------------------------
echo
echo "-- mount comparison failures --"

setup_case mount-sort-control
: > "$FAKE_DIR/break-sort-o"
printf 'b\na\n' > "$FAKE_DIR/probe.txt"
if with_fake_bin env LC_ALL=C sort -o "$FAKE_DIR/probe.txt" "$FAKE_DIR/probe.txt" 2>/dev/null; then
  fail "PRE-FIX CONTROL: 'sort ... || true' reported success while the sort failed" "the sort succeeded, so this control proves nothing"
elif { with_fake_bin env LC_ALL=C sort -o "$FAKE_DIR/probe.txt" "$FAKE_DIR/probe.txt" 2>/dev/null || true; }; then
  pass "PRE-FIX CONTROL: 'sort ... || true' reported success while the sort failed (the defect)"
else
  fail "PRE-FIX CONTROL: 'sort ... || true' reported success while the sort failed" "it returned nonzero, so this control proves nothing"
fi

setup_case mount-sort-fails
: > "$FAKE_DIR/break-sort-o"
run_verifier
expect_rc_nonzero "a mount comparison that could not be prepared fails the gate"
expect_output     "the comparison is reported as unproven, not clean" 'mount set could not be sorted'
expect_no_output  "no clean mount verdict is printed" 'no unexpected mounts'

# --- 22. The approved mount set is enforced independently of configuration ----
#
# Deriving the expectation from `docker compose config` and comparing it with
# `docker inspect` proves only that the two AGREE. A mount added to BOTH is
# invisible to that comparison.
echo
echo "-- the approved mount set --"

BOTH_SIDES='bind|/srv/config.json|/etc/scamwall/config.json|ro
bind|/srv/feed.json|/etc/scamwall/feed.json|ro
bind|/srv/pihole-ca.crt|/etc/scamwall/certs/pihole-ca.crt|ro
bind|/srv/secrets/pihole_app_password|/run/secrets/pihole_app_password|ro
bind|/srv/extra.json|/etc/scamwall/extra.json|ro'
printf '%s\n' "$BOTH_SIDES" > "$ROOT/both-expected.txt"
printf '%s\n' "$BOTH_SIDES" > "$ROOT/both-observed.txt"
OLD_MISSING="$(LC_ALL=C comm -23 "$ROOT/both-expected.txt" "$ROOT/both-observed.txt" | tr -d '\n')"
OLD_EXTRA="$(LC_ALL=C comm -13 "$ROOT/both-expected.txt" "$ROOT/both-observed.txt" | tr -d '\n')"
if [ -z "$OLD_MISSING" ] && [ -z "$OLD_EXTRA" ]; then
  pass "PRE-FIX CONTROL: a fifth mount present on both sides satisfied the derived comparison (the defect)"
else
  fail "PRE-FIX CONTROL: a fifth mount present on both sides satisfied the derived comparison" "missing='$OLD_MISSING' extra='$OLD_EXTRA'"
fi

if [ -z "$(approved_mount_problems "$ROOT/both-observed.txt")" ]; then
  fail "the approved-set check rejects a fifth mount" "it reported no problem"
else
  pass "the approved-set check rejects a fifth mount"
fi
printf 'bind|/srv/config.json|/etc/scamwall/config.json|ro\nbind|/srv/feed.json|/etc/scamwall/feed.json|ro\nbind|/srv/pihole-ca.crt|/etc/scamwall/certs/pihole-ca.crt|ro\nbind|/srv/secrets/pihole_app_password|/run/secrets/pihole_app_password|ro\n' > "$ROOT/approved-exact.txt"
if [ -z "$(approved_mount_problems "$ROOT/approved-exact.txt")" ]; then
  pass "the approved-set check accepts exactly the four approved mounts"
else
  fail "the approved-set check accepts exactly the four approved mounts" "$(approved_mount_problems "$ROOT/approved-exact.txt")"
fi
if approved_mount_problems "$ROOT/definitely-not-here.txt" >/dev/null 2>&1; then
  fail "an unreadable mount listing is a failure, not an absence of problems" "it returned 0"
else
  pass "an unreadable mount listing is a failure, not an absence of problems"
fi

setup_case mounts-extra-both-sides
compose_config_json '.services.scamwall.volumes += [{"type":"bind","source":"/srv/extra.json","target":"/etc/scamwall/extra.json","read_only":true}]' > "$FAKE_DIR/compose-config.json"
container_json '.[0].Mounts += [{"Type":"bind","Source":"/srv/extra.json","Destination":"/etc/scamwall/extra.json","RW":false}]' > "$FAKE_DIR/container.json"
run_verifier
expect_rc_nonzero "a mount present in BOTH the configuration and the inspection still fails"
expect_output     "the unapproved destination is named" 'extra\.json.* is not an approved mount destination'

setup_case mounts-type-both-sides
compose_config_json '(.services.scamwall.volumes[] | select(.target == "/etc/scamwall/feed.json") | .type) = "volume"' > "$FAKE_DIR/compose-config.json"
container_json '(.[0].Mounts[] | select(.Destination == "/etc/scamwall/feed.json") | .Type) = "volume"' > "$FAKE_DIR/container.json"
run_verifier
expect_rc_nonzero "an approved destination mounted with the wrong type fails on both sides"
expect_output     "the wrong mount type is named" "is a 'volume' mount, not a bind"

setup_case mounts-unresolved-source-both-sides
compose_config_json '(.services.scamwall.volumes[] | select(.target == "/etc/scamwall/config.json") | .source) = ""' > "$FAKE_DIR/compose-config.json"
container_json '(.[0].Mounts[] | select(.Destination == "/etc/scamwall/config.json") | .Source) = ""' > "$FAKE_DIR/container.json"
run_verifier
expect_rc_nonzero "an approved destination without a resolved source fails on both sides"
expect_output     "the unresolved source is named" 'no resolved absolute source'

# --- 23. Numeric parsing is explicit, bounded and overflow-safe ---------------
echo
echo "-- numeric parsing --"

if [ "$((010 * 1024))" -eq 8192 ]; then
  pass "PRE-FIX CONTROL: bash arithmetic reads a leading zero as octal (the defect)"
else
  fail "PRE-FIX CONTROL: bash arithmetic reads a leading zero as octal" "010 * 1024 was $((010 * 1024))"
fi
if [ "$((18014398509483008 * 1024))" -eq 1048576 ]; then
  pass "PRE-FIX CONTROL: the superseded multiplication wrapped a huge size into a permitted one (the defect)"
else
  fail "PRE-FIX CONTROL: the superseded multiplication wrapped a huge size into a permitted one" "product was $((18014398509483008 * 1024))"
fi

check_size() { # label input expected-or-REJECT
  local got
  if got="$(size_to_bytes "$2" 2>/dev/null)"; then
    if [ "$3" = "REJECT" ]; then fail "$1" "'$2' was accepted as $got"
    elif [ "$got" = "$3" ]; then pass "$1"
    else fail "$1" "'$2' became '$got', expected '$3'"; fi
  else
    if [ "$3" = "REJECT" ]; then pass "$1"
    else fail "$1" "'$2' was rejected, expected '$3'"; fi
  fi
}
check_size "a leading zero is read as decimal, not octal"   010k                   10240
check_size "a leading zero is normalised away"              010                    10
check_size "a size that would wrap the multiplication is rejected" 18014398509483008k REJECT
check_size "an excessively long value is rejected"          99999999999999999999   REJECT
check_size "a large but representable size is rejected by the ceiling" 4096g        REJECT
check_size "an ordinary size still converts"                4g                     4294967296
check_size "an ordinary mebibyte size still converts"       16m                     16777216

if to_decimal '' >/dev/null 2>&1; then fail "to_decimal rejects an empty value" "accepted"; else pass "to_decimal rejects an empty value"; fi
if to_decimal '1x' >/dev/null 2>&1; then fail "to_decimal rejects a non-numeric value" "accepted"; else pass "to_decimal rejects a non-numeric value"; fi
if to_decimal '-1' >/dev/null 2>&1; then fail "to_decimal rejects a negative value" "accepted"; else pass "to_decimal rejects a negative value"; fi
if [ "$(to_decimal '0009')" = "9" ]; then pass "to_decimal reads leading zeros in base 10"; else fail "to_decimal reads leading zeros in base 10" "got $(to_decimal '0009')"; fi
if to_decimal '11' 10 >/dev/null 2>&1; then fail "to_decimal enforces its maximum" "11 was accepted with max 10"; else pass "to_decimal enforces its maximum"; fi
if is_uint '010' 1 10; then pass "is_uint reads a leading zero in base 10"; else fail "is_uint reads a leading zero in base 10" "010 was rejected within 1..10"; fi

setup_case tmpfs-wrapping-size
WRAP_OPTS='rw,noexec,nosuid,nodev,size=18014398509483008k'
container_json ".[0].HostConfig.Tmpfs = {\"/tmp\": \"$WRAP_OPTS\"}" > "$FAKE_DIR/container.json"
compose_config_json ".services.scamwall.tmpfs = [\"/tmp:$WRAP_OPTS\"]" > "$FAKE_DIR/compose-config.json"
run_verifier
expect_rc_nonzero "a tmpfs size that only fits by wrapping the arithmetic fails"
expect_output     "the unparseable size is named" 'not a parseable size'

# `max-file: "09"` is a valid Compose value meaning nine files, and an INVALID
# octal literal. The superseded code fed it straight to `$(( ))` inside the
# condition of an `elif`. Bash reports the arithmetic error on stderr and the
# condition takes NEITHER branch — so no verdict about the logging bound was
# printed at all, and the run continued to report success having never
# evaluated the bound it claims to check.
BRANCH_TAKEN="$( { set -uo pipefail; A=5242880; B=09
  if [ "$A" -le 0 ]; then printf 'first'
  elif [ $((A * B)) -gt 536870912 ]; then printf 'over'
  else printf 'within'; fi; } 2>/dev/null )"
if [ -z "$BRANCH_TAKEN" ]; then
  pass "PRE-FIX CONTROL: an octal-invalid value in an elif condition takes no branch, so nothing is reported (the defect)"
else
  fail "PRE-FIX CONTROL: an octal-invalid value in an elif condition takes no branch" "the '$BRANCH_TAKEN' branch ran, so this control proves nothing"
fi
setup_case log-maxfile-leading-zero
container_json '.[0].HostConfig.LogConfig.Config["max-file"] = "09"' > "$FAKE_DIR/container.json"
compose_config_json '.services.scamwall.logging.options["max-file"] = "09"' > "$FAKE_DIR/compose-config.json"
run_verifier
expect_output  "a max-file with a leading zero is read as decimal and the bound is actually evaluated" 'log size is bounded .*max-file=09'
expect_rc_zero "nine log files of five mebibytes is within the permitted total"

setup_case log-maxfile-too-many
container_json '.[0].HostConfig.LogConfig.Config["max-file"] = "0011"' > "$FAKE_DIR/container.json"
compose_config_json '.services.scamwall.logging.options["max-file"] = "0011"' > "$FAKE_DIR/compose-config.json"
run_verifier
expect_rc_nonzero "a max-file above the permitted maximum still fails once leading zeros are stripped"
expect_output     "the out-of-range max-file is named" "max-file '0011' is missing or not an integer"

# --- 24. Required inspection fields ------------------------------------------
#
# `// 0` and `// ""` made assertions total AND vacuous: the default was
# indistinguishable from the value the requirement demands.
echo
echo "-- required inspection fields --"

MISSING_STATE='[{"State":{},"HostConfig":{},"NetworkSettings":{}}]'
OLD_PID="$(jq -r '(.[0].State.Pid // 0) | tostring' <<<"$MISSING_STATE")"
OLD_NETMODE="$(jq -r '((.[0].HostConfig.NetworkMode // "") != "host") | tostring' <<<"$MISSING_STATE")"
OLD_PORTS="$(jq -r '(.[0].NetworkSettings.Ports // {}) | length | tostring' <<<"$MISSING_STATE")"
if [ "$OLD_PID" = "0" ] && [ "$OLD_NETMODE" = "true" ] && [ "$OLD_PORTS" = "0" ]; then
  pass "PRE-FIX CONTROL: absent State.Pid, NetworkMode and Ports satisfied the superseded assertions (the defect)"
else
  fail "PRE-FIX CONTROL: absent fields satisfied the superseded assertions" "pid='$OLD_PID' netmode='$OLD_NETMODE' ports='$OLD_PORTS'"
fi

require_field_case() { # label jq-mutation expected-message
  setup_case "field-$3"
  container_json "$2" > "$FAKE_DIR/container.json"
  run_verifier
  expect_rc_nonzero "$1"
  expect_output     "$1 is reported as a missing or mistyped field" 'required inspection field is absent or of the wrong type'
}
require_field_case "an absent State.Pid fails"            'del(.[0].State.Pid)'                  pid
require_field_case "an absent State.StartedAt fails"      'del(.[0].State.StartedAt)'            started
require_field_case "an absent RestartCount fails"         'del(.[0].RestartCount)'               restartcount
require_field_case "an absent NetworkMode fails"          'del(.[0].HostConfig.NetworkMode)'     netmode
require_field_case "an absent PortBindings fails"         'del(.[0].HostConfig.PortBindings)'    portbindings
require_field_case "an absent NetworkSettings.Ports fails" 'del(.[0].NetworkSettings.Ports)'     ports
require_field_case "an absent PidsLimit fails"            'del(.[0].HostConfig.PidsLimit)'       pidslimit
require_field_case "an absent SecurityOpt fails"          'del(.[0].HostConfig.SecurityOpt)'     securityopt
require_field_case "a State.Pid of the wrong type fails"  '.[0].State.Pid = "0"'                 pidtype
require_field_case "a GroupAdd of the wrong type fails"   '.[0].HostConfig.GroupAdd = "5150"'    groupaddtype

setup_case field-image-user
printf '[{"Id":"%s","RepoTags":[],"RepoDigests":[],"Config":{"Healthcheck":null,"ExposedPorts":{}}}]\n' "$IMAGE_ID" > "$FAKE_DIR/image-inspect.json"
run_verifier
expect_rc_nonzero "an absent image Config.User fails"
expect_output     "the absent image field is reported" 'image inspection field .*Config\.User'

# The optional fields Docker genuinely renders as null must still be accepted.
setup_case field-capadd-null
container_json '.[0].HostConfig.CapAdd = null' > "$FAKE_DIR/container.json"
run_verifier
expect_rc_zero "a null CapAdd — Docker's representation of 'no capability added' — is accepted"

echo
echo "=============================================="
printf '%d tests, %d failed\n' "$TESTS" "$FAILURES"
[ "$FAILURES" -eq 0 ] || exit 1
echo "all runtime-verify regression tests passed"
