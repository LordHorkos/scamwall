#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
#
# entrypoint-mode-test.sh — regression tests for FINDING-47.
#
# THE DEFECT
#
# `9c413d2` extracted the resource-tracking block out of
# scripts/container-runtime-verify.sh into scripts/lib/docker-resources.sh. In
# the same commit the verifier's tracked file mode changed from 100755 to
# 100644, and nothing noticed for three commits.
#
# Nothing noticed because every path the suite exercises invokes these scripts
# as an ARGUMENT TO BASH — `bash ./scripts/container-runtime-verify.sh` in
# check.sh, `bash "$VERIFIER"` in operator-handoff.sh — and bash does not
# consult the execute bit of a file it is told to read. The documentation tells
# a human to run `./scripts/container-runtime-verify.sh`, which the kernel
# refuses with EACCES. So 358 passing verifier cases and a green gate suite said
# nothing whatever about it, and the first person to find out would have been
# the operator, at step A, on the machine where a failure costs the most.
#
# WHAT IS CHECKED, AND WHY EACH IS SEPARATE
#
#   1. The TRACKED mode in the index, not the working tree's. A local `chmod +x`
#      makes the checkout work while every fresh clone stays broken, which is
#      the same false pass in a different place.
#   2. The working tree agrees with the index, so this checkout and a clone
#      behave alike.
#   3. Sourced libraries are NOT executable. scripts/lib/docker-resources.sh is
#      sourced and must never be run as a program; marking it executable would
#      invite exactly that.
#   4. Documentation is cross-checked against the modes. A `./scripts/x.sh` in
#      CONTRIBUTING.md is a promise that the file is executable; `bash
#      scripts/x.sh` is not. The distinction is the whole defect, so the test
#      reads the invocation FORM rather than just the path.
#   5. The documented direct invocation is actually PERFORMED, through the
#      kernel, for every entry point that has a side-effect-free help path.
#      Exit 126 is the status a shell reports for "found, but not executable",
#      so it is asserted against explicitly.
#
# NO DOCKER, NO APPLICATION EXECUTION. The live invocations run with a PATH
# whose `docker`, `git` and `go` are shims that record being called and fail.
# Any invocation that reached for one is a failure of this test, so "it did not
# contact the daemon" is asserted rather than assumed.
#
# Exit status: 0 when every case passes.

set -uo pipefail

TESTS=0; FAILURES=0
pass() { printf '\033[32mok\033[0m   %s\n' "$1"; TESTS=$((TESTS + 1)); }
fail() { printf '\033[31mFAIL\033[0m %s\n' "$1"; printf '       %s\n' "$2"; TESTS=$((TESTS + 1)); FAILURES=$((FAILURES + 1)); }

SRC_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)" || exit 2
REPO_ROOT="$(cd -- "$SRC_DIR/../.." >/dev/null 2>&1 && pwd -P)" || exit 2
cd "$REPO_ROOT" || exit 2

command -v git >/dev/null 2>&1 || { printf 'fatal: git is required to read tracked file modes\n' >&2; exit 2; }
git rev-parse --git-dir >/dev/null 2>&1 || { printf 'fatal: not a git repository: %s\n' "$REPO_ROOT" >&2; exit 2; }

ROOT="$(mktemp -d)" || exit 2
trap 'rm -rf -- "$ROOT"' EXIT

# --- The tracked mode index ---------------------------------------------------
#
# Read ONCE, from the index, and its own failure is fatal rather than an empty
# result. An empty listing would otherwise pass every loop below by iterating
# zero times — the shape scripts/lib/docker-resources.sh calls out for resource
# enumeration, and it applies just as much to a test's input.
MODES="$ROOT/modes"
git ls-files -s -- scripts > "$MODES" 2>/dev/null || {
  printf 'fatal: could not read tracked modes from the index\n' >&2; exit 2; }
[ -s "$MODES" ] || { printf 'fatal: the index lists no files under scripts/\n' >&2; exit 2; }

tracked_mode() { # <path> -> prints the 6-digit mode, or nothing
  awk -v p="$1" '$4 == p { print $1 }' "$MODES"
}

# Every tracked path under scripts/, and the subset that is a shell program.
mapfile -t TRACKED < <(awk '{ print $4 }' "$MODES" | LC_ALL=C sort)
[ "${#TRACKED[@]}" -gt 0 ] || { printf 'fatal: no tracked paths parsed\n' >&2; exit 2; }

# --- 1. Sourced libraries are not executable ----------------------------------
#
# Checked first, and by location: anything under scripts/lib/ is sourced. If a
# genuinely executable program is ever added there, this case is the right place
# to fail, because the directory's meaning would have changed.
LIB_COUNT=0
for p in "${TRACKED[@]}"; do
  case "$p" in
    scripts/lib/*) ;;
    *) continue ;;
  esac
  LIB_COUNT=$((LIB_COUNT + 1))
  m="$(tracked_mode "$p")"
  if [ "$m" = "100644" ]; then
    pass "sourced library is tracked non-executable: $p"
  else
    fail "sourced library is tracked non-executable: $p" "tracked mode is ${m:-<unreadable>}, expected 100644"
  fi
  if [ -x "$p" ]; then
    fail "sourced library is not executable in the tree: $p" "the working tree has the execute bit set"
  else
    pass "sourced library is not executable in the tree: $p"
  fi
  # A sourced file must not be given a shebang either: a shebang plus an execute
  # bit is how a library becomes a program by accident.
  if [ -n "$(sed -n '1{/^#!/p}' "$p")" ] && [ -x "$p" ]; then
    fail "sourced library is not a program: $p" "it has both a shebang and the execute bit"
  fi
done
if [ "$LIB_COUNT" -eq 0 ]; then
  fail "the sourced-library directory was found" "nothing tracked under scripts/lib/ — this test would pass vacuously"
else
  pass "the sourced-library directory was found ($LIB_COUNT file(s))"
fi

# --- 2. Every shell program is tracked executable -----------------------------
#
# A "shell program" is a tracked file under scripts/, outside scripts/lib/, that
# begins with a shebang. That definition comes from the file's own content, so a
# newly added script is covered the moment it lands, without an allowlist that
# somebody has to remember to update.
PROG_COUNT=0
for p in "${TRACKED[@]}"; do
  case "$p" in
    scripts/lib/*) continue ;;
  esac
  [ -f "$p" ] || continue
  [ -n "$(sed -n '1{/^#!/p}' "$p")" ] || continue
  PROG_COUNT=$((PROG_COUNT + 1))
  m="$(tracked_mode "$p")"
  if [ "$m" = "100755" ]; then
    pass "tracked executable: $p"
  else
    fail "tracked executable: $p" "tracked mode is ${m:-<unreadable>}, expected 100755 — a clone of this commit cannot run it directly"
  fi
  # The working tree must agree with the index. They diverge exactly when
  # somebody fixes a mode with `chmod` and forgets `git update-index`.
  if [ -x "$p" ]; then
    if [ "$m" = "100755" ]; then
      pass "the working tree agrees with the index: $p"
    else
      fail "the working tree agrees with the index: $p" "executable here, but tracked $m — a clone would differ from this checkout"
    fi
  else
    fail "the working tree agrees with the index: $p" "not executable in the working tree"
  fi
done
if [ "$PROG_COUNT" -lt 10 ]; then
  fail "the shell programs were discovered" "only $PROG_COUNT found; the discovery is probably broken"
else
  pass "the shell programs were discovered ($PROG_COUNT file(s))"
fi

# --- 3. PRE-FIX CONTROL -------------------------------------------------------
#
# The mode assertions above must be able to FAIL. A copy of the verifier is
# staged into a scratch index at 100644 — the exact state 9c413d2 left — and the
# same predicate is applied to it. Without this the loop proves only that the
# current tree agrees with itself.
CTL="$ROOT/ctl"
mkdir -p "$CTL/scripts/lib" || exit 2
cp -- scripts/container-runtime-verify.sh "$CTL/scripts/" 2>/dev/null || exit 2
cp -- scripts/lib/docker-resources.sh "$CTL/scripts/lib/" 2>/dev/null || exit 2
(
  cd "$CTL" || exit 2
  git init -q . >/dev/null 2>&1 || exit 2
  chmod 644 scripts/container-runtime-verify.sh
  git add -A >/dev/null 2>&1 || exit 2
) || { fail "PRE-FIX CONTROL: a 100644 program is detected" "the scratch repository could not be prepared"; }

CTL_MODE="$(cd "$CTL" && git ls-files -s -- scripts/container-runtime-verify.sh 2>/dev/null | awk '{print $1}')"
if [ "$CTL_MODE" = "100644" ]; then
  pass "PRE-FIX CONTROL: the 9c413d2 state is reproduced (tracked 100644) and would fail the assertion above"
else
  fail "PRE-FIX CONTROL: the 9c413d2 state is reproduced" "the scratch index recorded ${CTL_MODE:-<nothing>}, not 100644 — this test cannot show it discriminates"
fi
if [ -x "$CTL/scripts/container-runtime-verify.sh" ]; then
  fail "PRE-FIX CONTROL: the control copy is not executable" "it kept the execute bit"
else
  pass "PRE-FIX CONTROL: the control copy is not executable, and the kernel would refuse it"
fi

# --- 4. Documentation names only invocations the modes support ----------------
#
# `./scripts/x.sh` and `sudo scripts/x.sh` are direct invocations and require
# the execute bit. `bash scripts/x.sh` does not. The defect was invisible
# precisely because the tested paths use the second form and the documented
# paths use the first, so the FORM is what this reads.
DOC_FILES=(README.md CONTRIBUTING.md SECURITY.md)
while IFS= read -r f; do DOC_FILES+=("$f"); done < <(find docs -maxdepth 1 -name '*.md' 2>/dev/null | LC_ALL=C sort)

DIRECT="$ROOT/direct-refs"
: > "$DIRECT"
for f in "${DOC_FILES[@]}"; do
  [ -f "$f" ] || continue
  # Direct invocation forms only. The leading context is captured so that a
  # `bash scripts/...` line is excluded rather than matched on its tail.
  LC_ALL=C grep -oE '(^|[^-[:alnum:]_/])(\./scripts/|sudo +scripts/)[A-Za-z0-9_-]+\.sh' "$f" 2>/dev/null |
    LC_ALL=C grep -oE 'scripts/[A-Za-z0-9_-]+\.sh' >> "$DIRECT"
done
LC_ALL=C sort -u -o "$DIRECT" "$DIRECT" 2>/dev/null || true

if [ -s "$DIRECT" ]; then
  pass "the documentation names at least one direct invocation"
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    if [ ! -f "$ref" ]; then
      fail "documented direct invocation names an existing file: $ref" "no such file"
      continue
    fi
    m="$(tracked_mode "$ref")"
    if [ "$m" = "100755" ]; then
      pass "documented direct invocation is executable: $ref"
    else
      fail "documented direct invocation is executable: $ref" "tracked mode ${m:-<unreadable>} — the documentation tells the reader to run something the kernel refuses"
    fi
  done < "$DIRECT"
else
  fail "the documentation names at least one direct invocation" "none found; the cross-check would pass vacuously"
fi

# --- 5. The direct invocation is actually performed ---------------------------
#
# Through the kernel, with the shebang, as a human would. Docker, git and go are
# shimmed to record and fail, so a script that reached for one is caught rather
# than quietly succeeding against the real thing.
SHIM="$ROOT/shim"
mkdir -p "$SHIM" || exit 2
CALLED="$ROOT/called"
: > "$CALLED"
for tool in docker docker-compose go; do
  cat > "$SHIM/$tool" <<SHIM_EOF
#!/usr/bin/env bash
printf '%s\n' "$tool" >> "$CALLED"
printf 'shimmed %s must not be called by a --help path\n' "$tool" >&2
exit 97
SHIM_EOF
  chmod +x "$SHIM/$tool"
done

# Entry points with a side-effect-free help path. Two are deliberately absent:
#
#   * check.sh parses no arguments and would run the entire gate suite, from
#     inside the gate suite;
#   * make-test-feed.sh parses no arguments and rewrites testdata/feed.json.
#
# Both are still covered by the tracked-mode and working-tree cases above. That
# is weaker than an exec, and saying so is better than a live invocation with a
# side effect hiding inside a mode test.
HELP_ENTRYPOINTS=(
  scripts/container-runtime-verify.sh
  scripts/container-security-check.sh
  scripts/gate-diagnostics.sh
  scripts/govulncheck-gate.sh
  scripts/independent-secret-scan.sh
  scripts/operator-handoff.sh
  scripts/secret-scan.sh
  scripts/workflow-policy-check.sh
)

for ep in "${HELP_ENTRYPOINTS[@]}"; do
  if [ ! -f "$ep" ]; then
    fail "direct invocation runs: $ep" "no such file"
    continue
  fi
  out="$(PATH="$SHIM:$PATH" timeout 20 "./$ep" --help 2>&1)"; rc=$?
  case "$rc" in
    126)
      fail "direct invocation runs: $ep" "exit 126 — found but not executable; this is FINDING-47" ;;
    127)
      fail "direct invocation runs: $ep" "exit 127 — not found or the interpreter is missing" ;;
    124)
      fail "direct invocation runs: $ep" "timed out; --help is not a side-effect-free path here" ;;
    *)
      if LC_ALL=C grep -qi 'permission denied' <<<"$out"; then
        fail "direct invocation runs: $ep" "the shell reported permission denied"
      elif [ -z "$out" ]; then
        fail "direct invocation runs: $ep" "exited $rc with no output; a help path should say something"
      else
        pass "direct invocation runs: $ep (exit $rc)"
      fi ;;
  esac
done

if [ -s "$CALLED" ]; then
  fail "no help path contacted Docker or the toolchain" "called: $(LC_ALL=C sort -u "$CALLED" | tr '\n' ' ')"
else
  pass "no help path contacted Docker or the toolchain"
fi

# The verifier is the file the defect was in, so its direct invocation is
# asserted specifically rather than only as one row of the loop above.
out="$(PATH="$SHIM:$PATH" timeout 20 ./scripts/container-runtime-verify.sh --help 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && LC_ALL=C grep -q 'OPERATOR-EXECUTED runtime verification' <<<"$out"; then
  pass "the verifier's own documented invocation prints its usage and exits 0"
else
  fail "the verifier's own documented invocation prints its usage and exits 0" "exit $rc"
fi

echo
printf '%d test(s), %d failure(s)\n' "$TESTS" "$FAILURES"
[ "$FAILURES" -eq 0 ] || exit 1
