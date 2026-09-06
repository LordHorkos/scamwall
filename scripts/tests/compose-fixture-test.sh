#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
#
# compose-fixture-test.sh — resolve the REAL deployment definition under the
# conditions a hosted runner presents, without a Docker daemon.
#
# WHY
#
# The first hosted CI run failed inside the runtime verification and the log did
# not say why (FINDING-23). The predicted cause was that
# deploy/compose/compose.yaml binds host paths which exist on the operator's
# host and cannot exist on a runner: a private CA at a literal absolute path,
# and an application password. That prediction could not be tested locally,
# because the local host HAS those paths and HAS a deploy/compose/.env.
#
# This reproduces the runner's environment for the parts that need no daemon:
#   * no deploy/compose/.env — it is gitignored, so a fresh checkout has none;
#   * the operator's /etc/scamwall paths not used;
#   * the CI overrides pointing at throwaway fixtures.
#
# `docker compose config` is entirely client-side, so all of that is checkable
# here. What it cannot reach is `compose create`, which is where the container
# is actually built — so this file establishes that the CONFIGURATION a runner
# resolves is the one the verifier requires, and claims nothing about the
# container. That distinction is the point of the file.
#
# Exit status: 0 when every case passes.

set -uo pipefail

TESTS=0; FAILURES=0
pass() { printf '\033[32mok\033[0m   %s\n' "$1"; TESTS=$((TESTS + 1)); }
fail() { printf '\033[31mFAIL\033[0m %s\n' "$1"; printf '       %s\n' "$2"; TESTS=$((TESTS + 1)); FAILURES=$((FAILURES + 1)); }

SRC_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)" || exit 2
REPO="$(cd -- "$SRC_DIR/../.." >/dev/null 2>&1 && pwd -P)" || exit 2
VERIFIER="$REPO/scripts/container-runtime-verify.sh"
COMPOSE_SRC="$REPO/deploy/compose/compose.yaml"
for f in "$VERIFIER" "$COMPOSE_SRC"; do
  [ -f "$f" ] || { printf 'fatal: not found: %s\n' "$f" >&2; exit 2; }
done
for tool in docker jq; do
  command -v "$tool" >/dev/null 2>&1 || { printf 'fatal: %s is required\n' "$tool" >&2; exit 2; }
done

ROOT="$(mktemp -d)" || exit 2
trap 'rm -rf -- "$ROOT"' EXIT

# --- A checkout shaped like a fresh clone -------------------------------------
#
# Only the files Compose reads. Critically it has NO deploy/compose/.env: that
# file is gitignored, so a runner never sees one, and a test run from the
# operator's checkout would otherwise silently pick the local one up — which is
# precisely the difference that made the CI failure unreproducible.
CO="$ROOT/checkout"
mkdir -p "$CO/deploy/compose" "$CO/testdata" "$CO/container"
cp "$COMPOSE_SRC" "$CO/deploy/compose/compose.yaml"
cp "$REPO/deploy/compose/config.example.json" "$CO/deploy/compose/config.example.json"
cp "$REPO/testdata/feed.json" "$CO/testdata/feed.json"
cp "$REPO/container/Dockerfile" "$CO/container/Dockerfile"
echo "== deployment definition under hosted-runner conditions =="
echo

if [ -e "$CO/deploy/compose/.env" ]; then
  fail "the synthetic checkout has no .env" "one was copied in"
else
  pass "the synthetic checkout has no .env, as a fresh clone has none"
fi

# --- Throwaway fixtures, created the way the workflow creates them ------------
FIX="$ROOT/fixtures"
# The mode is set after creation, not with `mkdir -m`: with -p that mode
# applies to the deepest component only, and any parent would take the
# ambient umask.
mkdir -p "$FIX" && chmod 700 "$FIX"
printf 'ScamWall test fixture. Not a certificate and not a key.\n' > "$FIX/pihole-ca.crt"
printf 'throwaway-not-a-real-password\n' > "$FIX/pihole_app_password"
chmod 600 "$FIX/pihole-ca.crt" "$FIX/pihole_app_password"

# --- The verifier's own expectations, lifted rather than restated -------------
#
# Restating "the approved mount set" here would create a second copy that can
# drift from the one the verifier enforces, and a test that agrees with a stale
# copy proves nothing.
eval "$(sed -n '/^in_list()/,/^}$/p' "$VERIFIER")"
eval "$(sed -n '/^APPROVED_MOUNT_DESTS=/,/pihole_app_password.$/p' "$VERIFIER")"
eval "$(sed -n '/^APPROVED_MOUNT_COUNT=/p' "$VERIFIER")"
eval "$(sed -n '/^approved_mount_problems()/,/^}$/p' "$VERIFIER")"
eval "$(sed -n '/^secret_world_reachable()/,/^}$/p' "$VERIFIER")"
[ -n "${APPROVED_MOUNT_DESTS:-}" ] || { printf 'fatal: could not lift the approved mount set from the verifier\n' >&2; exit 2; }
declare -F approved_mount_problems >/dev/null || { printf 'fatal: could not lift approved_mount_problems\n' >&2; exit 2; }
declare -F secret_world_reachable  >/dev/null || { printf 'fatal: could not lift secret_world_reachable\n' >&2; exit 2; }

SERVICE="scamwall"

# resolve <config-json-out> <err-out> — run `compose config` exactly as the
# verifier does: from the compose file's directory, with no --env-file, in an
# environment carrying only what CI sets.
resolve() {
  ( cd "$CO/deploy/compose" && \
    env -i PATH="$PATH" HOME="$HOME" \
      ${SCAMWALL_CA_FILE:+SCAMWALL_CA_FILE="$SCAMWALL_CA_FILE"} \
      ${SCAMWALL_SECRET_FILE:+SCAMWALL_SECRET_FILE="$SCAMWALL_SECRET_FILE"} \
      docker compose -f compose.yaml config --format json > "$1" 2> "$2" )
}

# expected_mounts <config-json> — the same derivation the verifier performs.
expected_mounts() {
  jq -r "
    [ (.services.\"$SERVICE\".volumes // [])[]
        | (.type // \"?\") + \"|\" + (.source // \"?\") + \"|\" + (.target // \"?\") + \"|\"
          + (if .read_only == true then \"ro\" else \"rw\" end) ]
    + [ (.services.\"$SERVICE\".secrets // [])[] as \$s
        | \"bind|\" + ((.secrets[\$s.source].file) // \"?\") + \"|\"
          + (\$s.target // (\"/run/secrets/\" + \$s.source)) + \"|ro\" ]
    | sort | .[]" < "$1"
}

# --- 1. The operator's defaults are preserved ---------------------------------
#
# The overrides exist for a test environment. If adding them moved the default
# out from under the operator, the fix would have broken the deployment it is
# meant to leave alone.
unset SCAMWALL_CA_FILE SCAMWALL_SECRET_FILE
if resolve "$ROOT/default.json" "$ROOT/default.err"; then
  pass "the definition resolves with no overrides at all"
  DEF_CA="$(jq -r '.services.scamwall.volumes[] | select(.target == "/etc/scamwall/certs/pihole-ca.crt") | .source' < "$ROOT/default.json")"
  DEF_SECRET_FILE="$(jq -r '.secrets.pihole_app_password.file' < "$ROOT/default.json")"
  if [ "$DEF_CA" = "/etc/scamwall/certs/pihole-ca.crt" ]; then
    pass "the CA default is unchanged for the operator"
  else
    fail "the CA default is unchanged for the operator" "resolved to '$DEF_CA'"
  fi
  if [ "$DEF_SECRET_FILE" = "/etc/scamwall/secrets/pihole_app_password" ]; then
    pass "the password default is unchanged for the operator"
  else
    fail "the password default is unchanged for the operator" "resolved to '$DEF_SECRET_FILE'"
  fi
else
  fail "the definition resolves with no overrides at all" "$(tr '\n' '|' < "$ROOT/default.err")"
fi

# --- 2. `compose config` does not detect an absent bind source ----------------
#
# Recorded as a positive assertion because it is the reason a separate check is
# needed at all: the gate that passed in the failing CI run was this one.
export SCAMWALL_CA_FILE="$ROOT/does-not-exist/pihole-ca.crt"
export SCAMWALL_SECRET_FILE="$ROOT/does-not-exist/pihole_app_password"
if resolve "$ROOT/absent.json" "$ROOT/absent.err"; then
  pass "compose config exits 0 even when every bind source is absent (which is why it cannot be the check)"
else
  fail "compose config exits 0 even when every bind source is absent" "it failed: $(tr '\n' '|' < "$ROOT/absent.err")"
fi
# ... and the verifier's host-side rule does detect it.
ABSENT_PROBLEM=""
while IFS='|' read -r _t s d _m; do
  [ -n "${d:-}" ] || continue
  [ -e "$s" ] || ABSENT_PROBLEM="${ABSENT_PROBLEM}${ABSENT_PROBLEM:+; }$d <- $s"
done < <(expected_mounts "$ROOT/absent.json")
if [ -n "$ABSENT_PROBLEM" ]; then
  pass "the verifier's host-side rule does detect the absent sources"
else
  fail "the verifier's host-side rule does detect the absent sources" "nothing was reported missing"
fi

# --- 3. With the CI fixtures, the resolved definition is exactly right --------
export SCAMWALL_CA_FILE="$FIX/pihole-ca.crt"
export SCAMWALL_SECRET_FILE="$FIX/pihole_app_password"
if ! resolve "$ROOT/ci.json" "$ROOT/ci.err"; then
  fail "the definition resolves under CI conditions" "$(tr '\n' '|' < "$ROOT/ci.err")"
else
  pass "the definition resolves under CI conditions"

  expected_mounts "$ROOT/ci.json" > "$ROOT/ci-mounts.txt"
  if PROBLEMS="$(approved_mount_problems "$ROOT/ci-mounts.txt")"; then
    if [ -z "$PROBLEMS" ]; then
      pass "CI resolves exactly the $APPROVED_MOUNT_COUNT approved mounts, each a read-only bind"
    else
      fail "CI resolves exactly the $APPROVED_MOUNT_COUNT approved mounts, each a read-only bind" "$PROBLEMS"
    fi
  else
    fail "the resolved mount set could be examined" "approved_mount_problems could not read the listing"
  fi

  # Every source must exist on this host and be a regular file — the assertion
  # the verifier makes, applied to what CI actually produces.
  STATE=""
  while IFS='|' read -r _t s d _m; do
    [ -n "${d:-}" ] || continue
    if [ ! -e "$s" ]; then STATE="${STATE}${STATE:+; }$d missing"
    elif [ -d "$s" ]; then STATE="${STATE}${STATE:+; }$d is a directory"
    elif [ ! -f "$s" ]; then STATE="${STATE}${STATE:+; }$d is not a regular file"; fi
  done < "$ROOT/ci-mounts.txt"
  if [ -z "$STATE" ]; then
    pass "every CI-resolved mount source exists and is a regular file"
  else
    fail "every CI-resolved mount source exists and is a regular file" "$STATE"
  fi

  # The destinations are what the container sees, and they must be identical to
  # the operator's. If an override could move one of these, the two
  # environments would not be verifying the same thing.
  DESTS="$(jq -r '[ (.services.scamwall.volumes[].target),
                    (.services.scamwall.secrets[] | (.target // ("/run/secrets/" + .source))) ] | sort | join(",")' < "$ROOT/ci.json")"
  DEF_DESTS="$(jq -r '[ (.services.scamwall.volumes[].target),
                        (.services.scamwall.secrets[] | (.target // ("/run/secrets/" + .source))) ] | sort | join(",")' < "$ROOT/default.json")"
  if [ "$DESTS" = "$DEF_DESTS" ]; then
    pass "the container sees identical mount destinations in CI and on the operator's host"
  else
    fail "the container sees identical mount destinations in CI and on the operator's host" "ci='$DESTS' operator='$DEF_DESTS'"
  fi

  # `create_host_path: false` must be set on every bind. Without it, Docker
  # invents an empty directory at a missing source and the container starts
  # with no CA behind a perfectly correct-looking mount.
  #
  # `.bind.create_host_path // true` is WRONG here and was written that way
  # first: jq's alternative operator treats `false` as absent, so the one value
  # this assertion exists to detect would be replaced by the default and the
  # check would report "true" for a definition that correctly says false.
  # Presence is therefore tested explicitly.
  #
  # THE RENDERED CONFIGURATION DOES NOT ALWAYS CARRY THIS FIELD. compose-go
  # tags `CreateHostPath` with `omitempty`, and `false` is a bool's zero value,
  # so on those versions `config` output omits the key entirely and a `false`
  # is indistinguishable from an absent one. Compose v5.5.1 renders it; the
  # version on `ubuntu-24.04` at the time of writing does not, which is how this
  # was found — the assertion failed in CI and passed locally against the same
  # definition (docs/VERIFICATION.md §4.11).
  #
  # So the property is checked through whichever channel actually carries it,
  # and the channel used is REPORTED rather than hidden. The fallback is not a
  # weakening: it reads the definition itself, which is where the key has to be,
  # and requires one occurrence per bind rather than merely one anywhere.
  BIND_COUNT="$(jq -r '[ .services.scamwall.volumes[] | select(.type == "bind") ] | length' < "$ROOT/ci.json")"
  CREATE_PATHS="$(jq -r "[ .services.scamwall.volumes[] | select(.type == \"bind\")
      | (if (has(\"bind\") and (.bind | has(\"create_host_path\"))) then (.bind.create_host_path | tostring) else \"unset\" end) ]
    | unique | join(\",\")" < "$ROOT/ci.json")"
  case "$CREATE_PATHS" in
    false)
      pass "no bind may have its source auto-created (create_host_path=false on all $BIND_COUNT, observed in the resolved configuration)"
      ;;
    unset)
      # This Compose omits the field when it is false. Fall back to the source.
      DECLARED="$(grep -cE '^[[:space:]]*create_host_path:[[:space:]]*false[[:space:]]*$' "$CO/deploy/compose/compose.yaml")" || DECLARED=0
      if [ "$DECLARED" -eq "$BIND_COUNT" ] && [ "$BIND_COUNT" -gt 0 ]; then
        pass "no bind may have its source auto-created (create_host_path=false declared on all $BIND_COUNT binds; this Compose omits the field from rendered output, so the definition was read instead)"
      else
        fail "no bind may have its source auto-created" \
             "$DECLARED declaration(s) of create_host_path=false for $BIND_COUNT bind mount(s), and this Compose does not render the field"
      fi
      ;;
    *)
      fail "no bind may have its source auto-created" "resolved: '$CREATE_PATHS'"
      ;;
  esac

  # Both branches must be exercised wherever this runs. Whichever channel this
  # host happens to use, the other one is unexercised and could rot unnoticed
  # until the next environment change — which is exactly how the original
  # assertion survived local runs and failed in CI. The unused branch is
  # therefore driven against a resolved configuration with the field stripped,
  # simulating the Compose versions that omit it.
  SIMULATED="$ROOT/ci-without-bind-field.json"
  jq '.services.scamwall.volumes |= map(del(.bind))' < "$ROOT/ci.json" > "$SIMULATED"
  SIM_RENDERED="$(jq -r '[ .services.scamwall.volumes[] | select(.type == "bind")
      | (if (has("bind") and (.bind | has("create_host_path"))) then (.bind.create_host_path | tostring) else "unset" end) ]
    | unique | join(",")' < "$SIMULATED")"
  if [ "$SIM_RENDERED" = "unset" ]; then
    pass "a Compose that omits create_host_path is detected as 'unset', not silently as 'true'"
  else
    fail "a Compose that omits create_host_path is detected as 'unset', not silently as 'true'" "got '$SIM_RENDERED'"
  fi
  SIM_DECLARED="$(grep -cE '^[[:space:]]*create_host_path:[[:space:]]*false[[:space:]]*$' "$CO/deploy/compose/compose.yaml")" || SIM_DECLARED=0
  if [ "$SIM_DECLARED" -eq "$BIND_COUNT" ]; then
    pass "the source-definition fallback accepts this definition, so the CI branch is exercised here too"
  else
    fail "the source-definition fallback accepts this definition" "$SIM_DECLARED declaration(s) for $BIND_COUNT bind(s)"
  fi

  # A negative control for the fallback, so that "the definition declares it"
  # cannot pass by matching nothing. A definition with the key removed must be
  # rejected by the same expression.
  STRIPPED="$ROOT/compose-without-create-host-path.yaml"
  grep -vE '^[[:space:]]*create_host_path:[[:space:]]*false[[:space:]]*$' "$CO/deploy/compose/compose.yaml" > "$STRIPPED"
  STRIPPED_COUNT="$(grep -cE '^[[:space:]]*create_host_path:[[:space:]]*false[[:space:]]*$' "$STRIPPED")" || STRIPPED_COUNT=0
  if [ "$STRIPPED_COUNT" -eq 0 ]; then
    pass "NEGATIVE CONTROL: a definition with create_host_path removed is not accepted by the fallback"
  else
    fail "NEGATIVE CONTROL: a definition with create_host_path removed is not accepted by the fallback" \
         "the stripped definition still matched $STRIPPED_COUNT time(s)"
  fi

  # Fixtures must not sit inside the image build context, or `docker build`
  # would ship a password into a layer.
  CONTEXT="$(jq -r '.services.scamwall.build.context // ""' < "$ROOT/ci.json")"
  if [ -z "$CONTEXT" ]; then
    fail "the fixtures lie outside the image build context" "the build context could not be read"
  else
    INSIDE=0
    for p in "$FIX/pihole-ca.crt" "$FIX/pihole_app_password"; do
      case "$p" in "$CONTEXT"/*) INSIDE=1 ;; esac
    done
    if [ "$INSIDE" -eq 0 ]; then
      pass "the fixtures lie outside the image build context ($CONTEXT)"
    else
      fail "the fixtures lie outside the image build context" "a fixture is under $CONTEXT"
    fi
  fi

  # The permission property the verifier enforces, checked against the fixtures
  # the workflow actually creates.
  secret_world_reachable "$FIX/pihole_app_password"
  case $? in
    1) pass "the CI password fixture is not readable by every account on the host" ;;
    0) fail "the CI password fixture is not readable by every account on the host" "it is world-reachable" ;;
    *) fail "the CI password fixture is not readable by every account on the host" "its permissions could not be determined" ;;
  esac
fi

# --- 4. A wrong override is rejected, not accommodated ------------------------
#
# The overrides exist for fixtures. They must not become a way to point the
# deployment at Pi-hole's own state or at the Docker socket.
export SCAMWALL_CA_FILE="/etc/pihole/setupVars.conf"
export SCAMWALL_SECRET_FILE="$FIX/pihole_app_password"
if resolve "$ROOT/bad.json" "$ROOT/bad.err"; then
  BAD="$(jq -r "
    [ ((.services.\"$SERVICE\".volumes // [])[] | { source: (.source // \"\"), target: (.target // \"\") }),
      ((.secrets // {}) | to_entries[] | { source: (.value.file // \"\"), target: (\"secret \" + .key) })
        | select((.source | test(\"docker\\\\.sock|^/etc/pihole|^/var/lib/docker|^/var/run/docker|^/proc|^/sys|^/dev(/|\$)|^/\$|^/etc\$|^/root|^/home\$\"))
                 or (.target | test(\"docker\\\\.sock|^/etc/pihole\")))
        | .source ] | join(\"; \")" < "$ROOT/bad.json")"
  if [ -n "$BAD" ]; then
    pass "an override pointing the CA at Pi-hole's own state is caught by the prohibited-path rule"
  else
    fail "an override pointing the CA at Pi-hole's own state is caught by the prohibited-path rule" "nothing was flagged"
  fi
else
  fail "the definition resolves with a prohibited override (so that the rule can reject it)" "$(tr '\n' '|' < "$ROOT/bad.err")"
fi

export SCAMWALL_CA_FILE="$FIX/pihole-ca.crt"
export SCAMWALL_SECRET_FILE="/var/run/docker.sock"
if resolve "$ROOT/bad2.json" "$ROOT/bad2.err"; then
  BAD2="$(jq -r '[ (.secrets // {}) | to_entries[] | (.value.file // "") | select(test("docker\\.sock")) ] | join("; ")' < "$ROOT/bad2.json")"
  if [ -n "$BAD2" ]; then
    pass "an override pointing the password at the Docker socket is caught"
  else
    fail "an override pointing the password at the Docker socket is caught" "nothing was flagged"
  fi
else
  fail "the definition resolves with a socket override (so that the rule can reject it)" "$(tr '\n' '|' < "$ROOT/bad2.err")"
fi

# --- 5. Fixture cleanup --------------------------------------------------------
#
# The workflow removes the fixture directory unconditionally and fails the job
# if it survives. The same removal is exercised here, because "rm -rf in a step
# that always runs" is a claim like any other.
rm -rf -- "$FIX"
if [ ! -e "$FIX" ]; then
  pass "the fixture directory is removable, leaving nothing behind"
else
  fail "the fixture directory is removable, leaving nothing behind" "$FIX still exists"
fi

echo
printf '%d test(s), %d failure(s)\n' "$TESTS" "$FAILURES"
[ "$FAILURES" -eq 0 ] || exit 1
