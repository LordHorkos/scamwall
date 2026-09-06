| `8d49971` | fix(gates): test govulncheck output for validity, not truthiness |
| `cff75be` | fix(gates): require the gitleaks finding count to be a number |
| `cff75be` | fix(gates): require the gitleaks finding count to be a number |
### 3.1 Detail by requirement

Section numbers written as "suite §N" below refer to the numbered case groups
inside `scripts/tests/runtime-verify-test.sh`, not to sections of this document.

Section numbers written as "suite §N" below refer to the numbered case groups
inside `scripts/tests/runtime-verify-test.sh`, not to sections of this document.

| Requirement |# ScamWall Verification Record

<!-- SPDX-License-Identifier: AGPL-3.0-only -->

Evidence for the requirements in `docs/REQUIREMENTS_MATRIX.md`. This document
records **observations**, not intentions: what was run, against what, with which
tools, and what came out.

Three rules govern what may appear here.

1. **Evidence is tied to an identity** — a source commit, a tool version, an
   image ID, a configuration. An observation with no identity attached cannot be
   renewed or refuted, so it is not evidence.
2. **A conversational report is history, not evidence.** Where a claim rests on
   something reported earlier rather than reproduced here, it is labelled as
   such and its requirement stays `IMPLEMENTED-UNVERIFIED`.
3. **A check that could not run has proven nothing.** It is recorded as
   `BLOCKED`, with the exact command an operator needs.

---

## 1. Contents

| § | |
| --- | --- |
| 2 | Baseline and environment |
| 3 | Phase 1 gate results |
| 4 | Findings raised by this session |
| 5 | Critical Go path review |
| 6 | Blocked items and operator commands |
| 7 | Evidence not yet obtained |

---

## 2. Baseline and environment

### 2.1 Source

| | |
| --- | --- |
| Branch | `feat/phase-1-core` |
| Session start | `2edb95a07567f4ebf9d6bc1bcb6c1ff01f5decc8` (tree `546ad23`) |
| Evidence commit | `54b56abfbdb876cfe7296e559dd65031cf2c71f9` |

Commits between the two:

| Commit | |
| --- | --- |
| `dab3d37` | fix(gates): remove the pipefail/SIGPIPE race that inverted grep matches |
| `90b19b0` | feat(gates): add ShellCheck, an independent secret detector, and content-based govulncheck |
| `124fb73` | test(cli): cover the Phase 1 read-only boundary at the command surface |
| `cec2d9b` | ci: add a reproducible, least-privilege gate workflow |
| `4a013d8` | fix(gates): stop the shell gates from silently narrowing their own scope |
| `8d49971` | fix(gates): test govulncheck output for validity, not truthiness |
| `cff75be` | fix(gates): require the gitleaks finding count to be a number |
| `54b56ab` | fix(gates): broaden the SIGPIPE guard, and stop it exempting itself |

All results in §3 were produced against `54b56ab`, the last commit that changes
any gate input. They are **not** valid for `2edb95a`; §4.1, §4.2, §4.3 and §4.5
describe defects present at that commit.

The commit carrying this document changes documentation only. That does not
invalidate the results above, and the rule is worth stating rather than
assuming: **evidence is tied to the last commit that changed a gate input.** A
documentation-only commit changes none, so the record carries forward. Any
commit touching source, scripts, dependencies, the container definition, or CI
does change one, and demotes the affected rows per
`docs/REQUIREMENTS_MATRIX.md` §5.

### 2.2 Host and tools

Recorded because a gate result is a statement about a toolchain as much as
about the code.

| Component | Version |
| --- | --- |
| OS | Debian GNU/Linux 13 (trixie), kernel 6.12.107+deb13-amd64 |
| bash | 5.2.37(1)-release |
| git | 2.47.3 |
| Go | go1.26.8 linux/amd64 |
| staticcheck | 2026.2.1 (0.8.1) |
| govulncheck | v1.7.0, DB vuln.go.dev updated 2026-09-02 |
| ShellCheck | 0.11.0 |
| gitleaks | 8.30.0 |
| jq | 1.7 |
| Docker CLI | 29.8.0 (build 88096ef) — **daemon not reachable by this account** |

`go.mod` pins `toolchain go1.26.8`; the installed toolchain matches, and
go.dev reports it as a currently supported release.

ShellCheck and gitleaks were installed into `$(go env GOPATH)/bin` for this
work. They were not present on the host before, which is why no ShellCheck or
independent-scanner evidence exists for earlier commits.

| Tool | Source | SHA-256 of the installed binary |
| --- | --- | --- |
| shellcheck 0.11.0 | `koalaman/shellcheck` release `v0.11.0`, `linux.x86_64` | `4da528ddb3a4d1b7b24a59d4e16eb2f5fd960f4bd9a3708a15baddbdf1d5a55b` |
| gitleaks 8.30.0 | `gitleaks/gitleaks` release `v8.30.0`, `linux_x64` | tarball `79a3ab579b53f71efd634f3aaf7e04a0fa0cf206b7ed434638d1547a2470a66e` |

### 2.3 Test inventory

124 Go test functions across all seven packages, plus three shell test suites
(runtime-verify, secret-scan controls, pipefail/SIGPIPE). No fuzz targets exist
yet; fuzzing is a Phase 3 requirement (SW-P3-08).

---

## 3. Phase 1 gate results

### 3.0 Run identity

Run against a fresh `--local` clone of commit **`54b56ab`** on
`feat/phase-1-core`, with the tools in §2.2, as user `scamwall`. A clone is used
so the working-tree gate is evaluated against a genuinely clean checkout rather
than against a tree holding this document.

Command: `bash scripts/check.sh`

```
======================================================
 ScamWall quality gates
======================================================

-- toolchain --
         go binary: go1.26.8 | go.mod toolchain: go1.26.8
  PASS    toolchain matches go.mod
  PASS    toolchain go1.26.8 is a currently supported release

-- go --
  PASS    gofmt clean
  PASS    go build ./...
  PASS    go vet ./...
  PASS    go test -race ./...

-- static analysis --
  PASS    staticcheck ./...
  PASS    shellcheck (all scripts)
  PASS    govulncheck self-test
  PASS    govulncheck (by content)

-- repository hygiene --
  PASS    secret scan (tree)
  PASS    secret scan controls
  PASS    independent secret scan self-test
  PASS    independent secret scan
  PASS    container security (static)
  PASS    no SIGPIPE-decided conditions

-- compose definition --
  PASS    docker compose config

-- runtime verifier regression tests --
  PASS    runtime-verify regression tests

-- container runtime (operator-executed, needs daemon) --
  BLOCKED docker build (docker daemon not reachable by scamwall)
  BLOCKED container runtime verification (docker daemon not reachable by scamwall — run scripts/container-runtime-verify.sh as the operator)

-- working tree --
  PASS    no uncommitted generated artifacts

======================================================
 19 passed, 0 failed, 2 BLOCKED, 0 optional-skipped
 RESULT: NOT COMPLETE — required gates failed or could not run.
======================================================
```

**The suite's overall verdict is NOT COMPLETE, and that is the correct
result.** Two required gates could not run on this host. They are not skipped,
not marked N/A, and not quietly excluded from the count — they fail the suite.
See §6.

### 3.1 Detail by requirement

Section numbers written as "suite §N" below refer to the numbered case groups
inside `scripts/tests/runtime-verify-test.sh`, not to sections of this document.

| Requirement | Evidence | Verdict |
| --- | --- | --- |
| SW-P1-01 | `scripts/tests/runtime-verify-test.sh`, 61 cases, all passing | VERIFIED |
| SW-P1-02 | Same suite §11: the verifier succeeds with a `git` on `PATH` that exits 128 on every call, and the git-log fixture stays empty | VERIFIED |
| SW-P1-03 | Same suite §3–§4: failed inspect, history, export, create, and both malformed and empty JSON each produce a nonzero verifier exit | VERIFIED |
| SW-P1-04 | Same suite §4: `[]` and non-JSON are rejected before any field is read | VERIFIED |
| SW-P1-05 | Same suite §5–§7 against the scripted fake — **but no run against a real image** | Partly VERIFIED, BLOCKED on §6.1 |
| SW-P1-06 | Same suite §2, §9: the command log shows removal of exactly the two containers this run created, every `compose down` scoped to `scamwall-verify-<pid>`, and no reference to the pre-existing container | VERIFIED |
| SW-P1-07 | Coverage map in §3.2 | VERIFIED |
| SW-P1-08 | `shellcheck --severity=style` over all 10 tracked scripts, clean | VERIFIED |
| SW-P1-09 | §4.2 | VERIFIED |
| SW-P1-10 | §5 | VERIFIED |
| SW-P1-11 | §4.3 | VERIFIED |
| SW-P1-12 | `.github/workflows/gates.yml`, reviewed in §3.4 | VERIFIED as written; never executed |
| SW-P1-13 | `go test -race -count=1 ./...` passes; 124 test functions; no test removed or weakened | VERIFIED |
| SW-P1-14 | §4.1 | VERIFIED |
| SW-P1-15 | `cmd/scamwall/main_test.go`, 15 test functions, all passing | VERIFIED |

### 3.2 SW-P1-07 coverage map

Each required false-pass class, and the case that reproduces it:

| Required class | Case |
| --- | --- |
| Failed create with existing containers | §2 — `compose create` fails while `ps -aq` would return a container; nonzero exit, no container assertion claimed, the existing container neither adopted nor removed |
| Failed inspect | §3 — `docker inspect` exits 1 |
| Failed history | §3 — `docker history` exits 1 **and writes benign text to stdout**, so a verifier reading output rather than status would have passed |
| Failed export | §3 — `docker export` exits 1; reported as path absence UNPROVEN |
| Failed parsing | §4 — unparseable container JSON, empty array, unparseable image JSON |
| Image mismatch | §5 — container `.Image` differs from the resolved ID; and resolved ID differs from `SCAMWALL_EXPECTED_IMAGE_ID` |
| Forbidden mounts | §6 — `docker.sock` and `/etc/pihole` visible only through `.Mounts` and **not** through `.HostConfig.Binds`, which is the representation the earlier Binds-only check missed; plus a writable mount |
| Daemon unavailability | §10 — `docker info` fails, and a missing compose plugin |
| Cleanup safety | §9 — containers created by the run are removed, `compose down` is always project-scoped, the deployment project is never targeted, and cleanup still runs when verification fails part-way |

Plus 13 hardening regressions (§7) and three filesystem-enumeration cases (§8).

### 3.3 Determinism (SW-P1-14)

`scripts/tests/runtime-verify-test.sh` executed **500 consecutive times** after
the §4.1 fix: **0 failures**.

Before the fix the same suite failed intermittently — roughly 1 run in 50 under
a plain loop, and 8 failures in the first ~50 runs of an instrumented loop. The
failure rate was low enough that the first three re-runs after the original
observation all passed, which is exactly what makes this class of defect
dangerous: the natural response to a flake is to re-run it, and re-running it
confirms the wrong conclusion.

### 3.4 CI review (SW-P1-12)

`.github/workflows/gates.yml` is reviewed here rather than executed; this
environment cannot run GitHub Actions.

| Property | How it is met |
| --- | --- |
| Reproducible | Go, staticcheck, govulncheck, ShellCheck, and gitleaks versions are pinned in `env:` and echoed into the run log by a dedicated step |
| Actions pinned | `actions/checkout` and `actions/setup-go` are referenced by commit SHA (`fbc6f39…`, `924ae3a…`), with the tag they correspond to in a comment. A tag is mutable; a SHA is not |
| Least privilege | `permissions: contents: read` at the top level and repeated on the job; never widened |
| No secret exposure to untrusted contributions | Trigger is `pull_request`, not `pull_request_target`. `pull_request_target` would run with a writable token and repository secrets while checking out fork code. The workflow also references no secret at all |
| No credential persistence | `persist-credentials: false` on checkout, so no token is left in `.git/config` for later steps |
| Same gates as local | The job runs `scripts/check.sh` rather than maintaining a second list that could drift |
| Full history | `fetch-depth: 0`, because the independent secret scan inspects every commit; a shallow clone would silently narrow it |

The YAML was parsed with `gopkg.in/yaml.v3` to confirm it is well-formed and
that `permissions` resolves to `map[contents:read]`.

**Not evidence of a passing CI run.** No run has occurred. Pushing is outside
the authorisation for this work.

### 3.5 Deliberate failure injection

"The gates pass" is a much weaker statement than it looks unless the gates can
also be shown to fail. Each injection below was made in a fresh `--local` clone
of this repository, with `scripts/check.sh` run unmodified.

| Injection | Result |
| --- | --- |
| none (clean clone) | exit 1 — **19 passed, 0 failed, 2 BLOCKED** |
| unformatted Go file | exit 1 — `gofmt` fails |
| a CLI test inverted so it asserts the wrong thing | exit 1 — `go test -race` fails |
| a script with `cd $1` and no `\|\| exit`, **untracked** | exit 1 — `shellcheck (all scripts)` fails |
| a script using `printf ... \| grep -q` as a condition | exit 1 — `no SIGPIPE-decided conditions` fails, and `shellcheck` too |
| a synthetic AWS access key id, committed | exit 1 — **both** `secret scan (tree)` and `independent secret scan` fail, the latter on history *and* on the publishable tree |

The clean clone still exits 1. That is the correct result and the most important
row in the table: two required gates could not run, they are counted as
`BLOCKED`, and `BLOCKED` fails the suite. There is no configuration in which a
missing daemon produces a green run.

**Scanner scope, verified explicitly**, because the two secret gates have
deliberately different reach:

| Secret state | `secret-scan.sh --tree` | `secret-scan.sh --staged` | `independent` (HEAD) | `independent --staged` |
| --- | --- | --- | --- | --- |
| committed | detects | — | detects | detects |
| staged, not committed | detects | detects | correctly silent | detects |

`independent-secret-scan.sh` in its default mode scans `git archive HEAD`, so a
staged-but-uncommitted secret is genuinely outside its scope — which is why
`--staged` exists and why `CONTRIBUTING.md` names it in the pre-commit step. In
a `check.sh` run the gap is closed from the other side: a staged file makes the
working-tree gate fail.

**Two injections initially appeared to prove the gates were broken and did
not.** `echo $foo` after `foo=1` is not a ShellCheck finding, because ShellCheck
can prove the expansion safe; and a planted credential written through an
eval-mangled `printf '%%s'` format put no credential in the file at all. Both
were faults in the injection, not in the gate. They are recorded because "the
gate did not fire" is exactly the observation one is most tempted to accept
without checking the input — and doing so here would have meant weakening a
working control to satisfy a broken test.

---

## 4. Findings raised by this session

### 4.1 FINDING-01 — `pipefail` + a short-circuiting `grep -q` silently inverts a match

**Severity: high.** It produced a 100% false-clean in the repository's primary
secret control, and a silent false PASS in a security regression test.

**Discovery.** `scripts/check.sh` reported `runtime-verify regression tests` as
FAILED on one run and PASSED on the next three, with no change in between. The
failing case asserted that a message the verifier demonstrably prints was
present in its output.

**Root cause.** Under `set -o pipefail`:

```bash
if producer | grep -q PATTERN; then ...
```

is a race. `grep -q` exits at the first match. If the producer has not finished
writing, it takes SIGPIPE and dies with 141, and `pipefail` makes 141 the status
of the whole pipeline — so the `if` reads false for input that **did** match.

Instrumenting the harness captured it directly:

```
label=the pin mismatch is reported
pattern=SCAMWALL_EXPECTED_IMAGE_ID
pipeline_rc=141          <- 128 + SIGPIPE
bytes=3264
retry_grep_on_file=1     <- the pattern WAS present
herestring_rc=0          <- and the herestring form finds it
```

Five distinct assertions were caught this way, all of them ones whose pattern
appears early in the output — which is exactly when `grep -q` exits with the
most left to write.

**Why the first attempt to reproduce it failed.** A microbenchmark of
`printf | grep -q` over 2 MB returned `PIPESTATUS=0 0` fifty times running,
which looked like an acquittal. It was not: whether the producer finishes before
the consumer exits is a scheduling question, and a tight loop on an idle machine
resolves it one way almost every time. Only the instrumented capture of a real
failure settled it.

**Impact, measured.** The same construction was used throughout
`scripts/secret-scan.sh`. With a private-key marker at the head of a 1 MB
string:

```
pipe form   (printf | grep -q) missed the key: 200 / 200
herestring  (grep -q <<<)      missed the key:   0 / 200
```

So at commit `2edb95a` the secret scanner **would not have reported a private
key in any file large enough to exceed the pipe buffer**. Every tracked file in
this repository is far below that threshold, so no real secret was missed and
the historical clean results stand — but the control was unsound, and it was
unsound in the direction that does damage.

The mirror-image case is worse. `expect_no_output` in the regression suite read:

```bash
if printf '%s' "$OUT" | grep -qE "$2"; then fail ...; else pass ...; fi
```

Here a match causes `grep -q` to exit early, the producer takes SIGPIPE, the
pipeline reports nonzero, and the test records **pass** — a violation reported
as compliance, in a test whose entire purpose is to catch false passes.

**Resolution.** Every condition of this shape was rewritten to read from a
herestring, a direct file argument, or a pre-captured variable:

| File | Sites |
| --- | --- |
| `scripts/secret-scan.sh` | 6 — path denial, private key, certificate, token patterns, placeholder, struct-tag exclusion |
| `scripts/check.sh` | 2 — both go.dev toolchain-support matches, over a response of hundreds of KB |
| `scripts/container-security-check.sh` | 5 — `cap_drop`, three tmpfs flags, `apt-get` in the final stage |
| `scripts/tests/runtime-verify-test.sh` | 4 — `expect_output`, `expect_no_output`, `compose down` scoping, the git-invocation guard |

`matches()` in the test harness now also distinguishes grep's exit status 2 (an
execution error) from 1 (no match), and reports the former as UNPROVEN rather
than as either verdict.

**Regression protection.**

* `scripts/tests/pipefail-sigpipe-test.sh` — a static gate over every tracked
  and untracked-not-ignored shell script. Two rules, chosen to match intent
  rather than syntax position:
  * **any** pipeline into `grep -q`, because the only reason to pass `-q` is to
    consume the exit status, so such a pipeline is always status-driven; and
  * a pipeline into `head` **only in a condition**, since `head` is normally a
    diagnostic whose status is discarded.

  Matching on intent is what makes `while`, `until`, a leading `!`, and
  backslash-continued pipelines fall out for free rather than needing to be
  enumerated — all four were verified to slip past the first, position-based
  rule. It carries a positive control, assembled from fragments so the script
  is not its own first violation; exempting the path would have blinded the
  checker to the one script most able to disable it.
* `scripts/tests/secret-scan-test.sh` — includes the 1 MB private-key case.
  Run against the pre-fix scanner it fails; against the fixed one it passes.
* 500 consecutive runs of the regression suite,
  0 failures (§3.3).

**Collateral fix.** `check.sh`'s `require` wrote gate output to `/tmp/gate.$$`.
A PID-derived name in a world-writable directory is predictable, so a local user
could pre-create it as a symlink and redirect the write. It now uses `mktemp`.

### 4.2 FINDING-02 — no independent secret detector (SW-P1-09)

At `2edb95a` the only secret control was `scripts/secret-scan.sh`. It is a good
scanner for ScamWall specifically — it knows the forbidden paths, the Pi-hole
password's fixed location, and that a certificate body means the private CA
leaked — and it knows nothing about the hundreds of vendor credential formats a
generic detector carries. Neither tool is a superset of the other, so both are
now required gates.

`scripts/independent-secret-scan.sh` runs gitleaks over the two things that
matter for a public repository:

* **every commit reachable from HEAD**, because anything ever committed is
  public forever once pushed; and
* **the publishable tree**, materialised with `git archive` rather than scanned
  in place.

The `git archive` detail is deliberate. A raw `gitleaks dir .` reports the
operator's correctly-gitignored local signing key as a finding — a file that
cannot be published, flagged on every run. A detector that cries wolf about
impossible leaks is one people learn to ignore. `git archive` produces exactly
the bytes a clone would receive.

**Exploratory findings and their disposition.**

| Finding | Disposition |
| --- | --- |
| `generic-api-key` at `internal/audit/audit_test.go:65`, secret `abcdef0123456789` | Allowlisted. The test asserts that the audit logger *redacts* sensitive values, so it must first log something credential-shaped. The value is invented and corresponds to no account or session. Scoped by rule **and** path **and** the exact literal, with `matchCondition = "AND"` |
| `private-key` at `keys/feed-signing.ed25519.key` | Not a finding in the gate. The file is untracked, gitignored, mode 0600, and refused by `secret-scan.sh`'s path denial; it is absent from the `git archive` the gate scans. A path allowlist exists only for anyone running `gitleaks dir .` by hand |

Every allowlist entry in `.gitleaks.toml` carries a written justification. An
entry whose reason cannot be written down does not go in.

A ScamWall-specific rule was added for the Pi-hole application password. It has
no distinctive prefix or checksum, so no generic rule catches it by shape; what
is catchable is its assignment to one of the names ScamWall uses.

**Positive control.** `--self-test` plants a synthetic AWS access key id in a
throwaway directory and requires a hit. The value is assembled from fragments at
runtime so the script's own source contains no matchable literal — whitelisting
the scanner's source would create precisely the blind spot the scanner exists to
close. The control deliberately avoids AWS's published documentation keys,
which gitleaks allowlists by design; a control built from one would appear to
fail while the detector worked, and might then be "fixed" by weakening the
config.

**The two scanners caught each other.** The first draft of the self-test named
one of those documentation keys in a comment. gitleaks ignored it; the project
scanner flagged it and refused the commit. That is the complementarity working
as intended, on its first outing.

### 4.3 FINDING-03 — govulncheck result handling (SW-P1-11)

At `2edb95a` the gate was `govulncheck ./...`, trusting the exit status. In
default text mode that is correct — but only accidentally, because it depends
on a property of one output mode.

**Measured on this host, govulncheck v1.7.0**, against a module pinned to
`golang.org/x/text v0.3.0`:

| Mode | Findings | Exit status |
| --- | --- | --- |
| default text | 58 | **3** |
| `-format json` | 58 | **0** |

A gate written against the machine-readable format — which is what CI and
tooling generally want — and trusting the exit status therefore reports a
vulnerable dependency set as clean.

`scripts/govulncheck-gate.sh` decides from content. Two subtleties are
load-bearing:

* **`osv` records are not findings.** They are vulnerability *database* entries
  consulted during the scan. A clean ScamWall scan emits 202 of them and zero
  findings; a gate that counted `osv` would fail every run. Only `finding`
  records count.
* **Unparseable is not clean.** Output that does not parse, or that carries no
  `config` record, means the scan did not demonstrably run. That is reported as
  UNPROVEN with exit 2, never as a pass.

Findings are classified by the deepest populated element of `.trace[0]` —
`called`, `imported`, or `required`. All three fail the gate; `called` is
reported separately because it is what an operator triages first.

**Verification.**

```
self-test:  clean stream        -> clean
            findings present    -> FAIL despite a zero exit status
            unparseable         -> UNPROVEN, not clean
            empty               -> UNPROVEN, not clean
            missing config      -> UNPROVEN, not clean

real capture (x/text v0.3.0, JSON, exit 0):
  FAIL  58 finding record(s)
        reachable (called): 2 | imported: 5 | required only: 51
          GO-2021-0113  golang.org/x/text  ParseAcceptLanguage
          GO-2022-1059  golang.org/x/text  ParseAcceptLanguage
```

**Current result for ScamWall:** 0 findings, 202 database entries consulted.

### 4.4 FINDING-04 — the CLI had no tests (SW-P1-15)

`cmd/scamwall` had no test file at `2edb95a`, so the Phase 1 boundary at the
command surface rested entirely on reading the code. `cmd/scamwall/main_test.go`
now covers it with 15 test functions, including:

* `sync --dry-run=false` is refused with a usage exit, and the refusal is
  checked not to contain wording that reads like an action was taken;
* the refusal happens **before** configuration is consulted — so a valid
  configuration cannot mean the credential was already read from disk;
* `plan` and `validate-feed` work with `ca_path` and `secret_path` pointing at
  files that do not exist, proving they need neither;
* the plan digest is byte-identical across runs, which is what makes operator
  review meaningful;
* `doctor` exits nonzero when a check fails, rather than printing failures and
  exiting 0;
* an unknown flag is a usage error on every subcommand, so a mistyped
  security-relevant flag cannot look honoured;
* structurally, `cmdPlan`, `cmdValidateFeed`, and `printPlan` contain no
  reference to the Pi-hole adapter;
* no `enforce`-tagged file and no `EnforcementCompiledIn = true` exists anywhere
  in `internal/policy`.

### 4.5 FINDING-05 — the shell gates silently narrowed their own scope

**Severity: medium.** A clean result was reported over a smaller file set than
the output implied, and it concealed a real violation.

`scripts/check.sh`'s ShellCheck gate and
`scripts/tests/pipefail-sigpipe-test.sh` both selected their input with
`git ls-files '*.sh'`. That lists the index and nothing else, so a script
present in the working tree but not yet staged was invisible to them.

Both gates reported PASS while `scripts/govulncheck-gate.sh` and
`scripts/independent-secret-scan.sh` were untracked — and the first of those was
in violation:

```
[ -s "$ERR" ] && sed 's/^/          /' "$ERR" | head -15
```

The violation only surfaced once the files were committed, in a clone built for
the injection testing in §3.5. Had that testing not been done, the gate would
have gone green on a tree it had not fully examined.

This is the same failure class as §4.1 arriving from a different direction: not
a check that reports the wrong answer, but a check that answers a narrower
question than the one it appears to answer.

**Resolution.** Both gates now read tracked *and* untracked-but-not-ignored
scripts. Verified by placing an unstaged script containing the bad construction
into `scripts/` and confirming the guard fails on it (§3.5, row 4).

The flagged line was restructured rather than annotated. A pipeline after `&&`
is an action, not a condition, so it was not in fact a bug — but it reads like
one, and a line-based checker cannot tell the difference. The ambiguity is the
part worth removing; an inline suppression would have kept it.

### 4.6 Observations carried forward, not fixed here

Neither belongs to Phase 1; both are registered against the phase that owns
them so they are not lost.

**Domain validity is conflated with maliciousness (SW-P3-05).**
`domain.Normalize` rejects mixed-script labels as *invalid*, and one rejected
record makes the entire feed fail to load. That is wrong in both directions: a
legitimate internationalized domain is unusable, and a homograph — a genuine
signal — is recorded as a parse error rather than as a classification input with
a reason code. The package's own comment is candid that this is a partial UTS #39
profile and does not detect whole-script confusables. Phase 3 work.

**The plan binds less than Phase 3 requires (SW-P3-10).** `policy.Plan`'s digest
covers format version, feed ID, manifest version, and entries. SW-P3-10 also
requires binding to policy and configuration identity, destination identity,
creation and expiry times, and application preconditions. Those fields do not
exist yet. Deliberately excluding per-run timestamps from the digest is correct
and should survive: a digest that changed without the plan changing would be
useless for review.

---

## 5. Critical Go path review (SW-P1-10)

Review of the areas SW-P1-10 names. Each entry states what was checked and what
was concluded, including where the conclusion is "adequate".

### 5.1 Credential handling

`internal/config/secret.go`, `internal/adapters/pihole/client.go`

`Secret` overrides `String`, `GoString`, `Format`, `MarshalJSON`, and
`MarshalText`. That set matters: the realistic leak is not a deliberate print
but a struct containing a secret passed to `%v`, or marshalled into a debug
dump. Redacting only `String()` would leave both open. `Format` covers `%x`,
which would otherwise print the underlying bytes.

`Reveal()` is the single escape hatch and appears at exactly two call sites, both
the moment a credential goes on the wire: the auth request body, and the
`X-FTL-SID` header. `guard_test.go:TestRevealCallSitesAreBounded` enforces the
count.

`LoadSecretFile` bounds the read, requires a regular file, and **refuses** a
world-readable credential rather than warning. Refusing is right: the failure is
loud and fixable, while proceeding leaves an exposure nobody notices.

`Destroy()` zeroes the backing bytes. The code is honest that this is a
reduction and not a guarantee — Go may have copied during a heap move, and
`Reveal` necessarily produces an immutable string. **Adequate, with the residual
risk correctly documented rather than overstated.**

### 5.2 TLS configuration and trust

`buildTLSConfig` builds a pool containing **only** the configured private CA;
the system trust store is not consulted. That is the right call: Pi-hole's
certificate is privately issued, so accepting any publicly-trusted issuer would
widen the set of parties able to impersonate it to every CA on the internet.

`ServerName` is pinned to the configured host, `MinVersion` is TLS 1.2, and
`InsecureSkipVerify` is left at its zero value with no configuration path able
to set it. `guard_test.go:TestNoTLSVerificationBypass` asserts the identifier
does not appear in the package at all. The CA read is bounded, and a PEM that
yields no usable certificate is a hard error rather than an empty pool — an
empty pool would fail closed anyway, but with a far worse diagnostic.

### 5.3 Destination pinning

`config.Validate` rejects an IP address for `pihole.host`, because the
certificate is issued for a name and using an address would either fail
verification or invite someone to relax it. `address_override` is the exact
analogue of `curl --resolve`: it changes which address is dialled, never which
identity is required.

The transport's `DialContext` refuses any address other than the configured
origin. Combined with the redirect policy, no response can steer the client at
another host. **This is the load-bearing control**, and it is enforced at the
dialler rather than by inspecting URLs, which is the right layer.

### 5.4 Redirects

`CheckRedirect` caps the chain at 3 and refuses any change of scheme or host
against `via[0]`. Comparing against the *original* request rather than the
immediately preceding one is correct: a chain of same-origin-looking hops could
otherwise walk away from the origin one step at a time.

### 5.5 Proxy behavior

`Transport.Proxy` is explicitly `nil`, so `HTTP_PROXY` and friends are ignored.
Correct for a service that is by definition on the local network: a proxy would
terminate or observe the connection, and honouring an environment variable would
make the trust boundary depend on the shell that happened to launch the process.

### 5.6 Deadlines and cancellation

Four separate bounds — connect, request, total, logout — each validated
positive, with `request_timeout <= total_timeout` enforced. `TLSHandshakeTimeout`
and `ResponseHeaderTimeout` are set on the transport, so a peer that accepts a
connection and then stalls cannot hold the client open.

`Logout` runs under `context.WithoutCancel(ctx)` plus its own timeout. This is
the subtle one and it is right: an interrupted or failed operation still gets a
real chance to destroy its session, rather than inheriting an already-expired
context. A leaked session stays valid for its remaining lifetime and occupies
one of a finite number of seats.

Signals are translated into context cancellation in `main`, so an interrupted
run unwinds through the deferred logout instead of dying with a live session.

### 5.7 Response limits

`MaxResponseBytes` (1 MiB default) is applied with `io.LimitReader(limit+1)` and
an explicit over-limit check, so truncation cannot masquerade as a short body.
The content type must parse as `application/json` before the body is read. The
CA read, the config read, and the feed read use the same read-one-past-the-limit
pattern; the feed and config additionally check `Stat()` size first so an
oversized file is rejected before any of it is buffered.

Bodies are drained to a bounded 4 KiB before close, so connection reuse does not
become a way to make the client read an unbounded amount.

### 5.8 Error and log hygiene

`APIError` carries status, endpoint, and Pi-hole's error key — never a body, a
header, or a credential. `sanitizeMessage` strips control characters and caps
peer-supplied strings at 200 bytes before they reach an error or a log.
`redactTransportError` rewrites transport errors so only class and endpoint
survive, while deliberately preserving the specific TLS verification failure —
which is exactly what an operator needs and contains no credential.

The audit logger recognises secrets **structurally**, through a `Redactor`
interface, rather than by a key denylist. That is the right shape: the realistic
leak is a secret logged under an innocuous key, and a denylist never catches
that. `guard_test.go` covers both the log and error paths.

Retries are bounded, jittered, and never applied to authentication — Pi-hole
rate-limits login and returns 429 when its session table is full, so a retry
storm could lock out a legitimate operator during an incident.

### 5.9 Domain normalization

Structural rejections (wildcards, IP literals, URL syntax, control characters)
run **before** IDNA conversion, which is the correct order: feeding such input to
a normaliser produces confusing errors and, at worst, converts "successfully"
into something unintended. The IDNA profile is strict — `StrictDomainName`,
`ValidateLabels`, `VerifyDNSLength`, `BidiRule`. Public suffixes are refused
outright, so a feed cannot ask for `co.uk` to be blocked.

See §4.6: the mixed-script check is sound as a *signal* but is currently applied
as a *validity verdict*, which Phase 3 must separate.

### 5.10 Feed verification

The strongest part of the tree.

The signature is verified over the **raw payload bytes**, captured as
`json.RawMessage`, not over a re-serialisation. This defeats a parser
differential: two decoders that disagree about the same bytes would otherwise
let a signature validate over content nobody signed. Nothing is interpreted
before the signature verifies.

`strictUnmarshal` rejects unknown fields — a field ScamWall does not understand
may carry meaning the publisher expects honoured, and silently ignoring it means
acting on a different feed than the one signed — and rejects trailing data, so a
second document appended after the signed one cannot ride along.

Key ID is compared before signature verification, so a feed signed by the wrong
key fails with a clear reason. Algorithm and both version fields are pinned.
Timestamps are checked for internal consistency, for not-yet-valid with a 5
minute skew tolerance, and for expiry. Record count is bounded; duplicates and
contradictory actions are distinguished.

The package comment states the essential point plainly: *a signed feed is still
an untrusted feed*. Signing establishes authenticity, not accuracy.

**Limitations, carried to Phase 3:** a single trust key with no rotation,
revocation, sequence-number, or freshness mechanism beyond manifest expiry. That
is SW-P3-02 and SW-P3-03, and SW-P3-03 requires evaluating TUF before any
bespoke lifecycle protocol is written.

### 5.11 Scope notes on the structural guards

The guard tests are strong, and it is worth being precise about what they
bound, so that a later change does not quietly step outside them.

* `TestNoTLSVerificationBypass` matches an **assignment** to
  `InsecureSkipVerify`, not a mention, so the explanatory comment in
  `client.go` does not trip it. It walks every non-test `.go` file in the
  module, so the scope is the whole tree.
* `TestRevealCallSitesAreBounded` pins the count per file and fails on growth
  in **either** direction — a call site appearing somewhere new, or an expected
  one disappearing. The second half matters more than it looks: a silently
  removed call site would mean the credential path had moved somewhere the
  guard is not watching.
* `TestNoMutatingEndpoints` scans only `internal/adapters/pihole/`. That is the
  correct scope today, because the adapter is the only package that can make an
  HTTP request at all — `internal/policy` deliberately does not import it, and
  `cmd/scamwall/main_test.go` now asserts that the offline commands do not
  either. It stops being sufficient the moment any other package gains network
  access, which Phase 6 will do. The guard must be widened at that point, and
  this note exists so that requirement is not discovered afterwards.

---

## 6. Blocked items and operator commands

### 6.1 Runtime verification against a real image (SW-P1-05)

**Blocker.** The service account is not in the `docker` group and has no
passwordless sudo. By operator decision this stays that way: `docker` group
membership is root-equivalent on this host, since it permits mounting the host
filesystem into a container. Docker operations are operator-executed.

**Consequence.** Every runtime assertion is currently evidenced against a
scripted fake Docker. That proves the *verifier* behaves correctly. It does not
prove anything about a built ScamWall image.

**Operator commands.** Run from the repository root. The verifier needs no git,
so root can run it in this `scamwall`-owned tree without a `safe.directory`
exception — do not add one.

```bash
cd /home/scamwall/scamwall

# 1. Build.
docker build \
  -f container/Dockerfile \
  -t scamwall:local \
  --build-arg VERSION="$(git describe --tags --always --dirty)" \
  --build-arg COMMIT="$(git rev-parse --short HEAD)" \
  --build-arg BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  .

# 2. Record the image ID. Evidence is tied to this, not to the tag.
docker image inspect -f '{{.Id}}' scamwall:local

# 3. Verify, pinning the expected ID so a stale local tag cannot stand in.
SCAMWALL_EXPECTED_IMAGE_ID="$(docker image inspect -f '{{.Id}}' scamwall:local)" \
  bash scripts/container-runtime-verify.sh
echo "VERIFY exit=$?"
```

Exit 0 means every required check ran and passed. Any nonzero exit means at
least one check failed **or could not run**; the output distinguishes the two.
The verifier creates its inspection container under a Compose project private to
the invocation and removes only what it created, so a running deployment is not
disturbed.

Please return: the image ID from step 2, and the complete output plus exit
status from step 3. Both will be recorded here against that image ID.

### 6.2 Live Pi-hole read (SW-P2-04, and Phase 2 generally)

Not attempted. Phase 2 has not been entered, and no live read-only test is
started automatically. The current record establishes **configured
permissions**, explicitly not proven access — see `docs/SECURITY_BOUNDARIES.md`
§5.1.

### 6.3 CI execution (SW-P1-12)

The workflow is reviewed but never executed. Running it requires a push, which
is outside the authorisation for this work.

---

## 7. Evidence not yet obtained

Stated plainly so that nothing here is read as more than it is.

| Claim | Status |
| --- | --- |
| The ScamWall container image satisfies its runtime hardening assertions | **Not established.** Verifier behaviour is proven; the image is not. §6.1 |
| ScamWall can authenticate to a real Pi-hole | **Not established.** Only a fake HTTPS server has been exercised |
| The container identity can read the mounted secret | **Not established.** File modes are configured; no process has been observed reading it |
| CI passes | **Not established.** Never run |
| ScamWall detects scam domains accurately | **Not established, and not claimed.** `testdata/feed.json` is a synthetic fixture. It is evidence about signature verification and parsing, and about nothing else. Detection accuracy is Phase 4 and has not begun |

The last row is the one most easily misread, so it is stated twice: a signed
feed proves who wrote it. It says nothing whatever about whether the contents
are correct.
