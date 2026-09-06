# ScamWall Verification Record

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
| 6 | Operator procedures, and what remains blocked |
| 7 | Evidence status, item by item |

---

## 2. Baseline and environment

### 2.1 Source

| | |
| --- | --- |
| Branch | `feat/phase-1-core` |
| Session start | `2edb95a07567f4ebf9d6bc1bcb6c1ff01f5decc8` (tree `546ad23`) |
| Evidence commit | `b6b1769151501d89d7f8550d2c8f3378d0e73c3d` — *fix(verify): check list processing, name scope, mounts, numbers and fields* |
| Verified image | `sha256:b95cc07ca564b115f8bf2d49d642efafc99ae8ff4ae7746caaa7d2ff5e00516b`, built by the operator from that commit — §3.7 |
| Superseded evidence commit | `0b083cb` — *fix(verify): attribute resources and complete the runtime assertions*. Retained where cited; **not** carried forward for the rows §5 of the matrix demotes |

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
| `b469c59` | docs: add the phased plan, requirements matrix, and verification record |
| `204fd4d` | build: prove static linkage by checked ELF inspection |
| `0b083cb` | fix(verify): attribute resources and complete the runtime assertions |
| `7c639c2` | docs: record the eleven verifier findings and correct the evidence status |
| `b6b1769` | fix(verify): check list processing, name scope, mounts, numbers and fields |

All results in §3 were produced against `b6b1769`, the last commit that changes
any gate input. They are **not** valid for earlier commits: §4.1 – §4.5
describe defects present at `2edb95a`, §4.7 describes eleven defects present at
`b469c59` — including in the runtime verifier as it stood there, which is the
version an operator would have run had it been executed — and §4.8 describes
six further defects present at `0b083cb`.

`b6b1769` changed `scripts/container-runtime-verify.sh` and its regression
suite. Under `docs/REQUIREMENTS_MATRIX.md` §5 that demotes every row resting on
a `scripts/*.sh` gate, so the `0b083cb` transcript is not carried forward for
those rows: the suite was re-run at `b6b1769`, and that run is §3.0. The
regression suite grew from 237 cases to 319 over the same commit.

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

129 Go test functions across eight packages, plus three shell test suites
(runtime-verify with 319 cases, secret-scan controls, pipefail/SIGPIPE). The
counts moved this session: `internal/buildcheck/elfcheck` is new (5 functions,
the ELF controls), and the runtime-verify suite grew from 47 cases to 237 at
`0b083cb` and to 319 at `b6b1769`. No fuzz targets exist yet; fuzzing is a
Phase 3 requirement (SW-P3-08).

---

## 3. Phase 1 gate results

### 3.0 Run identity

Run against commit **`b6b1769`** on `feat/phase-1-core`, with the tools in
§2.2, as user `scamwall`, in the repository working tree — which `git status
--porcelain` reported as empty before the run, so the checkout is identical to
the commit. The deployment `.env` is gitignored and is the file the operator's
deployment uses; it contains a group id and nothing else, and no value from it
is reproduced here.

The earlier transcript in this section was taken against `0b083cb` in a fresh
`--local` clone. That method is still valid and is preferable when the tree is
dirty; it is not used here because the tree is clean and the run must be tied
to `b6b1769` itself.

Command, capturing the exit status directly rather than inferring it from the
printed verdict:

```bash
bash scripts/check.sh; echo "CHECK exit=$?"
```

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
CHECK exit=1
```

**`CHECK exit=1` is the observation, not the summary line.** It was requested
separately, and the distinction is the point: a script can print anything it
likes, and a caller — CI, a pre-commit hook, an operator's `&&` chain — acts on
the status alone. The two agree here, which is what had to be shown; the
printed verdict on its own would not have shown it.

**The suite's overall verdict is NOT COMPLETE, and that is the correct
result on this host.** Two required gates could not run as `scamwall`: the
Docker daemon is unreachable from the service account by operator decision
(§6.1). They are not skipped, not marked N/A, and not quietly excluded from the
count — they are `BLOCKED`, and `BLOCKED` exits 1.

Both of those gates have since been executed by the operator, against this same
commit and against a real image — §3.7. That does not turn this run green and
must not be read as doing so: a `scamwall` run of `check.sh` on this host will
continue to exit 1, because the account still cannot reach the daemon. The
runtime evidence lives in §3.7 and is tied to an image ID, not to this
transcript.

### 3.1 Detail by requirement

Case groups in `scripts/tests/runtime-verify-test.sh` are named, not numbered;
they are referred to below by the title printed when the suite runs.

| Requirement | Evidence | Verdict |
| --- | --- | --- |
| SW-P1-01 | `scripts/tests/runtime-verify-test.sh`, 319 cases, all passing | VERIFIED |
| SW-P1-02 | *no git dependency*: the verifier succeeds with a `git` on `PATH` that exits 128 on every call, the git-log fixture stays empty, and no git command appears in the comment-stripped source | VERIFIED |
| SW-P1-03 | *absence versus search failure*: failed inspect, history, export, `docker create`, `compose ps`, container listing, configuration resolution, and both malformed and empty JSON each produce a nonzero exit | VERIFIED |
| SW-P1-04 | *incomplete and malformed inspection data*: `[]`, non-JSON, a non-array image inspection, a non-digest image identifier, and twelve structurally valid documents with a required field deleted are each rejected before any conclusion is drawn | VERIFIED |
| SW-P1-05 | *image identity*, *mounts*, *tmpfs bounds*, *logging bounds*, *API hostname pinning*, *supplementary group*, *hardening regressions* against the scripted fake; **and** an operator run against image `sha256:b95cc07c…` built from this commit, §3.7 | VERIFIED |
| SW-P1-06 | *resource ownership* and *cleanup as a verdict*: the command log shows removal of exactly the resources this run created, every listing filtered by a label unique to this invocation, no `compose down` at all, and no reference to any pre-existing resource | VERIFIED |
| SW-P1-07 | Coverage map in §3.2; pre-fix comparison in §3.5 | VERIFIED |
| SW-P1-08 | `shellcheck --severity=style` over all 10 tracked scripts, clean | VERIFIED |
| SW-P1-09 | §4.2 | VERIFIED |
| SW-P1-10 | §5 | VERIFIED |
| SW-P1-11 | §4.3 | VERIFIED |
| SW-P1-12 | `.github/workflows/gates.yml`, reviewed in §3.4. Review is not execution | **BLOCKED** on §6.3 |
| SW-P1-13 | `go test -race -count=1 ./...` passes; 129 test functions; no test removed or weakened | VERIFIED |
| SW-P1-14 | §4.1, and the repeat-run evidence in §3.3 | VERIFIED |
| SW-P1-15 | `cmd/scamwall/main_test.go`, 15 test functions, all passing | VERIFIED |
| SW-P1-16 | *cleanup as a verdict*: ordering (cleanup precedes the verdict line), failed container removal, failed network removal, TERM mid-run, mid-run verification failure, and exactly one removal attempt per resource | VERIFIED |
| SW-P1-17 | *resource ownership*: container and network collisions block creation; a coexisting deployment is never listed or touched; partial creation is cleaned up by attribution; an unattributable resource is preserved and reported | VERIFIED |
| SW-P1-18 | *consistent Compose configuration*: all three Compose operations carry the same `--env-file` and project name; a `.env` value deliberately different from the resolved value is not used; resolution and parse failures block the run | VERIFIED |
| SW-P1-19 | *mounts*: the cases covering empty, absent, missing, extra, duplicated, writable, wrong-source, wrong-type and prohibited mounts, plus the pre-fix controls, and — added at `b6b1769` — an exact four-destination approved set enforced independently of the configuration and a failed comparison treated as UNPROVEN (§4.8, FINDING-19 and FINDING-20) | VERIFIED |
| SW-P1-20 | §3.6 — the ELF controls pass; and §3.7 — the in-build assertion executed inside the operator's `docker build` of this commit | VERIFIED |

### 3.2 SW-P1-07 coverage map

Each required false-pass class, and the case that reproduces it. "Case group"
is the heading the suite prints.

| Required class | Case |
| --- | --- |
| Forbidden paths without a leading `./` | *filesystem path matching* — six archives whose members are written unprefixed (`bin/sh`, `usr/bin/bash`, `etc/shadow`, `etc/passwd`, `usr/sbin/apt-get`, `bin/busybox`); each is detected |
| Forbidden paths with a leading `./` | Same group — an archive written as `./bin/sh` |
| Look-alike paths must not match | Same group — `usr/local/bin/scamwall-helper`, `opt/sh`, `etc/passwd.bak`, `etc/shadow.example`, `usr/share/doc/bash/README`, `home/someone/bin/sh.txt`, `var/lib/apt-cache`: the run passes and absence is still asserted |
| Failed cleanup | *cleanup as a verdict* — `docker rm` and `docker network rm` each made to fail; the run exits nonzero and names what remains |
| Interruption cleanup | Same group — the fake daemon delivers SIGTERM mid-inspection; cleanup runs once and the exit is nonzero |
| Idempotent cleanup | Same group — exactly one removal attempt per resource across EXIT and TERM |
| Resource-name collision | *resource ownership* — a container, and separately a network, already carrying this invocation's project label: nothing is created, nothing is deleted |
| Unrelated resource preservation | Same group — a coexisting deployment resource; no unfiltered listing is ever performed, and the deployment project is never named |
| Partial Compose creation | Same group — `compose create` fails after the network exists; the network is removed by attribution, no container assertion is claimed |
| Failed create with an existing container | Same group — a pre-existing container is neither adopted nor removed |
| Consistent `.env` handling | *consistent Compose configuration* — every Compose operation carries the same `--env-file` and project |
| Interpolation from structured configuration | Same group — the `.env` gid (4242) differs from the resolved gid (5150); the resolved value must be used |
| Isolation-escaping configuration | Same group — `container_name`, an external network, an extra service, and a lost ownership label each block creation |
| Missing / additional / duplicated / writable / incorrect mounts | *mounts* — thirteen cases, plus a pre-fix control showing empty `.Mounts` satisfied the superseded assertions |
| Missing inspection fields | *incomplete and malformed inspection data* — twelve required fields deleted one at a time |
| Malformed JSON | Same group — non-JSON, `[]`, a non-array image inspection |
| Image tag movement | *image identity* — the container records a different image than the tag resolved to |
| Image identity mismatch | Same group — mismatch, malformed pin, non-digest identifier; and an equivalent identifier that resolves to the same image is accepted with both values reported |
| Immutable identity used throughout | Same group — the log shows `history` and `docker create` addressed by image ID, and no image operation using the tag |
| Failed history search | *absence versus search failure* — `docker history` exits 1 **and writes benign text to stdout**, so a verifier reading output rather than status would have passed |
| Other search errors | Same group — `search_file` returns three distinct outcomes, and `count_matches` reports a failed search rather than a zero count; both with pre-fix controls |
| Missing / incorrect hostname pinning | *API hostname pinning* — absent, wrong address, a second conflicting entry, absent in configuration, a different hostname; an IPv6 pin is accepted |
| Missing, invalid or unbounded logging | *logging bounds* — nine configuration cases and two container-disagreement cases |
| Invalid tmpfs bounds | *tmpfs bounds* — ten cases, including three that contain the literal `size=` and are still rejected |
| Static and dynamic ELF controls | `internal/buildcheck/elfcheck/main_test.go`; §3.6 |
| No application execution | *no application execution* — the log contains no start, up, run or exec; five state mutations are each detected; the comment-stripped verifier contains no start operation |
| Daemon unavailability | *daemon availability* — `docker info` fails, and a missing compose plugin |

Classes added at `b6b1769`, each with a pre-fix control (§3.5):

| Required class | Case |
| --- | --- |
| A resource list that could not be enumerated or combined | *resource ownership* — `combine_ids` distinguishes an obtained empty list from a failed one; the pre-snapshot BLOCKS and cleanup reports the leftovers it could not sweep, rather than either reading the failure as "nothing there" |
| A resolved name escaping the invocation's namespace | *consistent Compose configuration* — a non-external network, and separately a volume, carrying a fixed `name:`; each blocks creation before `compose create` runs, so nothing can be adopted |
| A mount comparison that could not be prepared | *mounts* — a failed sort or comparison reports the requirement UNPROVEN rather than clean |
| A mount approved by neither side's requirement but present in both | *mounts* — a fifth mount in the configuration AND the inspection; wrong type and unresolved source on both sides; the approved set is exactly four destinations, not a floor of four |
| Octal, overflowing and over-long numeric values | *tmpfs bounds* and *logging bounds* — `size=010k`, a size that only fits by wrapping the multiplication, an excessively long value, and `max-file: "09"`, which previously matched neither branch and left the bound unevaluated |
| A required inspection field absent or mistyped | *incomplete and malformed inspection data* — `State.Pid`, `State.StartedAt`, `RestartCount`, `NetworkMode`, `PortBindings`, `NetworkSettings.Ports`, `PidsLimit`, `SecurityOpt`, `GroupAdd` and the image field, each absent or of the wrong type, and each reported as missing rather than defaulted into a pass. `CapAdd` and `Config.Labels` are the deliberate exceptions, where Docker's `null` IS the requirement |

### 3.3 Determinism (SW-P1-14)

Two measurements, kept separate because the suite changed size between them.
Merging them into one figure would imply a measurement that was never made.

| Suite | Consecutive runs | Failures |
| --- | --- | --- |
| 237 cases, at `0b083cb`, after the §4.1 fix | **500** | **0** |
| 319 cases, at `b6b1769` | **30** | **0** |

Before the §4.1 fix the 237-case suite failed intermittently — roughly 1 run in
50 under a plain loop, and 8 failures in the first ~50 runs of an instrumented
loop. The failure rate was low enough that the first three re-runs after the
original observation all passed, which is exactly what makes this class of
defect dangerous: the natural response to a flake is to re-run it, and
re-running it confirms the wrong conclusion.

**Why the second measurement is shorter, stated rather than glossed.** Each run
of the 319-case suite takes about 75 seconds, so 500 runs is roughly ten hours;
30 runs is 37 minutes. At 30 runs a defect reproducing at the pre-fix rate of
1-in-50 would be missed about 55% of the time, so this is not equivalent
evidence and is not offered as such.

What makes 30 sufficient to *renew* rather than to re-establish the property
from nothing is that the root cause is known, fixed, and independently guarded:
`scripts/tests/pipefail-sigpipe-test.sh` fails the build if the
`pipefail`-plus-short-circuiting-`grep` construction returns anywhere in the
tree, and that guard runs on every gate invocation (§3.0, `no SIGPIPE-decided
conditions`). The repeat run tests for a *new* source of nondeterminism
introduced by `b6b1769`; the old one cannot return silently.

The shortfall against the 500-run standard is carried in §7 rather than being
absorbed into a single number here.

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

**This is a review, and a review is not an execution.** Three things are
routinely conflated, so they are separated here:

| Level | State |
| --- | --- |
| Implementation review — the file read property by property against the requirement | DONE, above |
| Local simulation — the same GATE LIST executed locally by `scripts/check.sh` (§3.0) | DONE, and it says nothing about `permissions:`, action pinning, the runner image, or fork-PR secret handling, because none of those exist locally |
| Hosted CI run — the workflow itself executed on GitHub, with a run URL and log | **NOT DONE** |

SW-P1-12 is therefore **BLOCKED**, not "VERIFIED as written". No run has
occurred; pushing is outside the authorisation for this work. §6.3.

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

**The runtime-verify suite run against the PRE-FIX implementation.** A suite
that passes proves only that the code agrees with itself. This comparison was
made twice, once per round of fixes; the `b469c59` round is below and the
`0b083cb` round follows it.

**Round one — against `b469c59`.** To show that the 237 cases as they stood at
`0b083cb` actually discriminate, the corrected suite was run against the
verifier as it stood at `b469c59` — the version an operator would have executed
had the first candidate image been verified.

Method: a tree containing `b469c59`'s `scripts/container-runtime-verify.sh`,
`container/Dockerfile` and `deploy/compose/compose.yaml`, with the corrected
`scripts/tests/runtime-verify-test.sh` and the same `.env`.

| Run | Result |
| --- | --- |
| `0b083cb` verifier, `0b083cb` suite | **237 cases, 0 failed** |
| `b469c59` verifier, `0b083cb` suite, fixtures unchanged | **237 cases, 61 failed** |
| `b469c59` verifier, `0b083cb` suite, fixtures neutralised so its own baseline is clean | **236 cases, 112 failed** |

The second row understates the picture: with the `.env`/resolved-configuration
divergence in place the pre-fix verifier fails every run for that one reason,
which masks its other defects behind an unrelated failure. The third row
removes that mask — the `.env` gid is made to agree, and the runtime-managed
`/tmp` entry (which the pre-fix verifier had no concept of) is removed from the
container fixture — so the pre-fix baseline passes and each remaining failure
is a defect of its own. Those 112 include, as **false passes** that the pre-fix
implementation did not detect at all:

* all six unprefixed forbidden paths — `bin/sh`, `usr/bin/bash`, `etc/shadow`,
  `etc/passwd`, `usr/sbin/apt-get`, `bin/busybox`;
* an empty `.Mounts`, a missing configuration mount, a missing password mount,
  an extra mount, a duplicated destination, a wrong source, a wrong type;
* every tmpfs bound case, including `size=0`, `size=999g`, `size=`, `size=abc`
  and an `exec` option re-enabling execution;
* every logging case — no logging configuration, an unbounded remote driver, a
  missing, zero, oversized or non-numeric bound, and a container disagreeing
  with the configuration;
* every hostname-pinning case — absent, wrong, duplicated, or absent from the
  configuration;
* a non-numeric and a multiple supplementary group;
* a container reported as running, with a pid, with a start time, or with a
  restart count;
* a project-label collision, an isolation-escaping `container_name`, an
  external resource, an extra service, and a lost ownership label;
* a failed cleanup, an interrupted cleanup, and cleanup ordering;
* a failed container listing reported as "no containers".

The full transcript of both runs is reproducible with the method above; the
recorded outcome is the three rows in the table.

**Round two — against `0b083cb`.** The six defects in §4.8 were reviewed out of
the verifier as it stood at `0b083cb`, so the same question applies again: do
the new cases actually discriminate, or do they only agree with the code that
was written alongside them?

Method: `git archive b6b1769` into a scratch tree, then the single file
`scripts/container-runtime-verify.sh` replaced by `git show
0b083cb:scripts/container-runtime-verify.sh` — verified by SHA-256 against the
committed blob — and the `b6b1769` suite run against it unchanged. One file
differs; everything else, fixtures included, is identical.

| Run | Result |
| --- | --- |
| `b6b1769` verifier, `b6b1769` suite | **319 cases, 0 failed** |
| `0b083cb` verifier, `b6b1769` suite | **319 cases, 50 failed** |

No masking correction was needed this time — the `0b083cb` verifier's own
baseline is clean against these fixtures, so all 50 failures are defects rather
than consequences of one broken precondition. They partition cleanly across the
six findings:

| Finding | Failing cases | What the `0b083cb` verifier did |
| --- | --- | --- |
| FINDING-17 | 5 | An unprocessable resource list read as an empty one: no collision before creation, nothing to sweep during cleanup, and cleanup still reported complete |
| FINDING-18 | 8 | A network and a volume named outside the invocation's namespace were both allowed to be created — and so could be adopted from the real deployment |
| FINDING-19 | 3 | A mount comparison that could not be prepared printed a clean verdict |
| FINDING-20 | 7 | A fifth mount present in BOTH the configuration and the inspection passed; wrong type and unresolved source passed on both sides |
| FINDING-21 | 9 | `010k` read as octal, a size that only fits by wrapping the arithmetic accepted, an over-long value accepted, and a `max-file` bound never evaluated at all |
| FINDING-22 | 18 | Absent `State.Pid`, `State.StartedAt`, `RestartCount`, `NetworkMode`, `PortBindings`, `NetworkSettings.Ports`, `PidsLimit`, `SecurityOpt` and a mistyped `State.Pid`, `GroupAdd` and image field each satisfied the assertion that was supposed to examine them |

The FINDING-22 group is the one to read twice. Eighteen cases where a field
being *missing from the inspection output* was accepted as the field *having
the required value* — "no process id is recorded" satisfied by no `State.Pid`
being there at all.

### 3.6 ELF linkage controls (SW-P1-20)

`go test ./internal/buildcheck/elfcheck/` — 5 test functions, 5 subtests, all
passing, run as part of `go test -race ./...` in §3.0.

| Control | Input | Expected | Observed |
| --- | --- | --- | --- |
| positive | a `CGO_ENABLED=0` Go build, compiled by the test | accepted | accepted |
| negative | a hand-built ELF64 executable carrying `PT_INTERP` | rejected, naming the interpreter property | as expected |
| negative | a hand-built ELF64 executable carrying `PT_DYNAMIC` | rejected, naming the dynamic-segment property | as expected |
| negative | a dynamically linked system binary, when the host has one | rejected | as expected (`/bin/ls`) |
| malformed | missing file, empty file, non-ELF bytes, truncated ELF header, a directory | each rejected | as expected |

Observed directly against real artifacts, outside the test:

```
$ go run ./internal/buildcheck/elfcheck <CGO_ENABLED=0 build of ./cmd/scamwall>
  ok   object type is executable    observed: ET_EXEC
  ok   no PT_INTERP segment         observed: none
  ok   no .interp section           observed: none
  ok   no PT_DYNAMIC segment        observed: none
  ok   no SHT_DYNAMIC section       observed: none
  ok   no DT_NEEDED entries         observed: none
  ok   no imported libraries        observed: none
exit 0

$ go run ./internal/buildcheck/elfcheck /bin/ls
  FAIL no PT_INTERP segment         observed: PT_INTERP present
  FAIL no DT_NEEDED entries         observed: [libselinux.so.1 libcap.so.2 libc.so.6]
exit 1
```

**Scope.** This proves the inspected file carries no dynamic interpreter and no
dynamic linking apparatus. It does not prove the binary is safe, contains no
embedded secret, or was built from this source.

**The remaining step, now taken.** These controls prove the checker works; they
do not prove the shipped build ran it. That required a `docker build`, which
cannot be executed from this account. The operator executed one at `b6b1769`:
the assertion ran inside the build and the build exited 0 — §3.7. SW-P1-20 is
closed on the two together, and neither half closes it alone.


### 3.7 Operator runtime verification against a real image (SW-P1-05, SW-P1-20)

This is the evidence §6.1 was written to obtain. It was produced by the
operator, on the operator's account, because the service account cannot reach
the Docker daemon and — by standing decision — will not be given access to it.

**Identity.** Without these four values the run below would be an anecdote.

| | |
| --- | --- |
| Source commit | `b6b1769151501d89d7f8550d2c8f3378d0e73c3d` |
| Image ID | `sha256:b95cc07ca564b115f8bf2d49d642efafc99ae8ff4ae7746caaa7d2ff5e00516b` |
| Verifier | `scripts/container-runtime-verify.sh` at that commit |
| Pin | `SCAMWALL_EXPECTED_IMAGE_ID` set to the image ID above, so the verifier's own identity assertion had to agree with the build's output |

**Build.**

| Observation | Result |
| --- | --- |
| `docker build` | exit 0 |
| ELF linkage assertion (`go run ./internal/buildcheck/elfcheck /out/scamwall`), executed inside the build | completed successfully |
| Enforcement-absent assertion (`/out/scamwall version` must report `enforcement compiled in false`), executed inside the build | completed successfully |

Both assertions are `RUN` steps: a failure fails the build, so `exit 0` is not
merely consistent with them having passed, it requires it. This is what
SW-P1-20 was missing — the checker and its controls were already proven (§3.6),
but the assertion had never been executed by a build.

**Verification.**

| Observation | Result |
| --- | --- |
| Verdict | **90 passed, 0 failed, 0 blocked, 0 cleanup problems** |
| `VERIFY exit` | **0** |
| Application execution | the container remained *created* and was never started |
| Image identity | the inspected container's image matched the expected image |
| Cleanup | reported completion |
| Effective hostname mapping under test | `pi.hole:host-gateway` — the compose default, `PIHOLE_HOST_IP` unset |

`0 blocked` is the load-bearing number alongside `0 failed`. The verifier
distinguishes *failed* from *could not run*, and a run reporting no failures but
several blocked checks would establish very little. Neither category occurred.

That the container was created and never started is a property of the method,
and it is why this evidence could be gathered at all: no credential is read and
no request is made to any Pi-hole, so the run is safe to perform against a host
carrying a live deployment.

**One reported value was corroborated independently**, as `scamwall`, without
Docker daemon access:

```
$ docker compose --env-file deploy/compose/.env \
    -f deploy/compose/compose.yaml config | grep -A1 extra_hosts
    extra_hosts:
      - pi.hole=host-gateway
```

`deploy/compose/.env` defines exactly one key, and it is not `PIHOLE_HOST_IP`,
so `${PIHOLE_HOST_IP:-host-gateway}` takes its default. The mapping the operator
reported is therefore the one this configuration necessarily resolves to. This
is a small check, and it is recorded because it is the kind that is available
and skipped: `docker compose config` needs no daemon, so a claim about the
resolved configuration can always be tested from this account even when nothing
about the running container can be.

**What this does and does not establish.**

| | |
| --- | --- |
| Established | The image built from `b6b1769` satisfies the runtime hardening assertions the verifier makes — image identity, the exact mount set, tmpfs and logging bounds, hostname pinning, supplementary group, capabilities and privilege settings, and created-not-running — and the verifier cleaned up after itself |
| Established | The shipped binary carries no dynamic linking apparatus, asserted by the build that produced it, and enforcement is not compiled into it |
| **Not** established | That the container identity can *read* the mounted password. The container was never started, so no process read it. SW-P2-04 stays BLOCKED |
| **Not** established | That the destination reachable through `pi.hole:host-gateway` is a Pi-hole, that TLS verification succeeds against it, or that authentication works. Nothing was sent. §6.2 |
| **Not** established | Anything about detection accuracy, which is Phase 4 and has not begun |

**Form of the evidence, stated plainly.** What is recorded here is the
operator's report of the run — the identities, the exit statuses and the
verdict counts — not an archived transcript. This record's own rule is that a
conversational report is history rather than evidence, and the rule is not
waived: it is met differently. The reported values are each an *identity or a
status*, both reproducible on demand by re-running §6.1 against the same commit,
and the image ID ties them to a specific artifact that still exists. A summary
that could not be checked against anything would not qualify; this one can be.
The stronger form remains the verbatim `/tmp/scamwall-verify.log`, and attaching
it — or its hash — to this section would remove the last step of trust.

**Site-specific values are deliberately absent.** No address, no supplementary
group id, no deployment path and no host identity appears here. The verifier
asserts these against values resolved from the operator's own configuration;
this record states that the assertions held, not what they held against.

**Renewal.** Both rows are tied to *this image ID and this commit*. Any change
to Go source, the Dockerfile, the compose definition, or the scripts invalidates
them, and any rebuild produces a new image ID that has not been verified.
`docs/REQUIREMENTS_MATRIX.md` §5; the procedure is retained at §6.1.

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

None belongs to Phase 1 as a code defect; each is registered against the row or
phase that owns it so it is not lost.

**The CI job cannot pass on a hosted runner as configured (SW-P1-12).**
`deploy/compose/compose.yaml` binds `/etc/scamwall/certs/pihole-ca.crt`, a
literal absolute path with no environment override, and a Compose secret
defaulting to `/etc/scamwall/secrets/pihole_app_password`. Neither exists on a
fresh `ubuntu-24.04` runner, so the runtime verification cannot get past
`compose create` there — while `docker compose config`, which the suite runs
first, exits 0 even when the secret path does not exist (tested directly). The
consequence is that SW-P1-12's acceptance criterion, "the hosted run exists and
passes", is not satisfiable by pushing the branch as it stands. This was found
by reading the workflow and the compose file against each other before
proposing the push, not by watching a run go red; the options are set out in
§6.3 and the choice is the operator's.

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

### 4.7 FINDING-06 … FINDING-16 — the runtime verifier at `b469c59`

Eleven defects found by review of the verifier as it stood at `b469c59`, before
it had ever been executed against a real image. Every one of the first ten is a
FALSE PASS: the program could report a security property as satisfied without
having observed it. Each was reproduced as a regression case first; §3.5 records
the pre-fix comparison.

**FINDING-06 — the filesystem absence expressions could not match an ordinary
archive entry.** *Severity: high.* Every absence pattern began with `^\./?`,
which REQUIRES a leading dot. `docker export | tar -t` writes members either as
`./bin/sh` or as `bin/sh` depending on how the archive was produced, and for the
unprefixed shape the patterns matched nothing at all: "no shell at checked
paths", "no busybox", "no package manager", "no libc", "no /etc/passwd" and "no
/etc/shadow" all passed while the files were present. The trust anchor did not
help — it used the same permissive alternation and matched either shape.
*Fixed:* the listing is normalised once (leading `./` or `/` removed) and
matched against unprefixed patterns. Six unprefixed cases, one prefixed case, a
seven-path look-alike control set, and a pre-fix control that asserts the
superseded expression misses `bin/sh`.

**FINDING-07 — cleanup was not part of the verdict.** *Severity: high.* The
success summary was printed BEFORE cleanup ran, and every cleanup error was
discarded (`docker rm -f ... >/dev/null 2>&1`, `return 0`). A run that left
containers and a network behind reported "all required runtime checks passed"
and exited 0. *Fixed:* cleanup completes first, its failures count towards the
verdict and force a nonzero exit, remaining resources are named by identifier
only, and at most one destructive attempt is made per resource across
EXIT/INT/TERM.

**FINDING-08 — resources were deleted on the strength of a PID.** *Severity:
high.* `scamwall-verify-$$` is not proof of ownership: PIDs are small, reused
and guessable, so a stale or unrelated resource could carry this run's project
name and be destroyed by `compose down -p`. Worse, `compose create` ADOPTS a
container that already carries the project label rather than creating one, so a
colliding container could have been inspected in place of the verifier's own.
*Fixed:* 128 bits from `/dev/urandom`, recorded resource IDs, a per-invocation
ownership label applied through a Compose override, a pre-creation snapshot that
turns any collision into a refusal to create or delete anything, removal by
exact ID after re-verifying the label, and no project-wide deletion at all.

**FINDING-09 — configuration features that escape project isolation were never
examined.** *Severity: medium.* A private project name isolates only what
Compose names after the project. `container_name`, `external: true` networks,
volumes or secrets, and additional services do not follow that rule. The
verifier neither checked for them nor would have attributed the resources they
produce. *Fixed:* the resolved configuration is inspected for all of them, and
any occurrence blocks the run before anything is created.

**FINDING-10 — creation and cleanup used different Compose arguments.**
*Severity: medium.* Creation passed `--env-file`; cleanup did not. The two
commands could therefore be describing different deployments — and the one that
DELETES was the one running with less information. *Fixed:* one argument set
resolves, creates and lists, and cleanup no longer uses Compose at all.

**FINDING-11 — expected settings were re-derived by grepping `.env`.**
*Severity: medium.* The expected supplementary group was extracted with `grep`,
`${line#*=}` and hand-rolled quote stripping. That reimplements Compose's
interpolation — shell environment over `.env`, `${VAR:-default}` forms,
quoting, precedence — and gets it wrong in exactly the cases that matter,
silently producing an expectation the deployment never had. *Fixed:* every
expected value is read from `docker compose config` and then validated
separately against the security requirement. The regression suite sets the
`.env` value (4242) DIFFERENT from the resolved value (5150) so a return to the
old method fails immediately.

**FINDING-12 — an absent or empty `.Mounts` satisfied every mount
assertion.** *Severity: high.* "Every mount is read-only" and "no prohibited
mounts" were both computed as "the filtered list is empty", so a container with
no `.Mounts` at all passed both without a single mount being examined — and
nothing checked that the configuration, feed, CA and password mounts were
present. *Fixed:* `.Mounts` must be a non-empty array, and the observed set must
equal the set derived from the resolved configuration — type, resolved source,
destination, read-only status — with no missing, extra or duplicated
destination. The runtime-managed `/tmp` tmpfs is the one named exception and is
validated separately from `HostConfig.Tmpfs`.

**FINDING-13 — image operations used the mutable tag after resolving the
immutable ID.** *Severity: medium.* The ID was resolved and then `docker
history` and `docker create` were both given the TAG again, so a tag repointed
between operations would have had a different image scanned and enumerated
while the report named the first. *Fixed:* the resolved ID is validated as a
sha256 digest and used for every later operation; the container's `.Image` is
compared against it; a difference is re-resolved through the daemon before
being called a mismatch, because image stores do not all record the same
identifier for the same image; and what each identifier means is printed.

**FINDING-14 — a search that could not run was reported as a clean result.**
*Severity: high.* `grep -qiE ... "$HISTORY_OUT"` treated exit 2 — grep itself
failing — identically to exit 1, so an unperformed credential scan produced
"PASS no credential pattern in image build instructions". The same shape
appeared in the filesystem trust anchor. *Fixed:* every search distinguishes
matched / did not match / could not search, and the third is a failure. The
helper is exercised directly, with a pre-fix control showing the superseded
shape collapsing the third outcome into the second.

**FINDING-15 — several required deployment properties were unasserted, and
others were asserted by substring.** *Severity: medium.* The API hostname pin
was never checked against the container at all. The log driver and its bounds
were never checked. `test("size=")` proved only that three letters were present:
`size=0`, `size=999g`, `size=` and `size=abc` all passed. The supplementary
group was compared but never validated, so `0` — root's group — would have been
accepted from a malformed `.env`. Nothing asserted positively that no
application had run. *Fixed:* pinning is asserted exactly against the resolved
address, tmpfs and log options are parsed and bounded, the group must be a
single non-root numeric gid, and created-not-running is asserted through five
independent fields. Missing required fields fail rather than being defaulted.

**FINDING-16 — the verification record's own file was corrupted.** *Severity:
low, but it is a record of evidence.* `docs/VERIFICATION.md` as committed at
`b469c59` began with eleven stray lines — fragments of the §2.1 commit table and
the §3.1 heading, duplicated — and its title line had been concatenated onto a
`| Requirement |` fragment. The document rendered as a broken table before its
own heading. *Fixed:* the stray prefix is removed and the title restored; no
other content was lost, since every fragment was a duplicate of text that
appears correctly later in the file.

### 4.8 FINDING-17 … FINDING-22 — the runtime verifier at `0b083cb`

Six further defects, found by review of the verifier *after* the §4.7 fixes and
fixed in `b6b1769`. Every one is the same class as §4.7: the program could
report a security property as satisfied without having observed it. They are
recorded separately rather than folded into §4.7 because they were present in a
version this record had already described as corrected — which is the useful
lesson. A round of fixes that resolves eleven findings does not establish that
none remain, and treating "reviewed and fixed" as "now correct" is how the
second round gets skipped.

Each carries a regression test that fails against the `0b083cb` verifier and
passes against `b6b1769`, plus pre-fix controls showing the superseded
expression exhibiting the defect. §3.5 records the run of the corrected suite
against the pre-fix verifier.

**FINDING-17 — resource-list processing failures were discarded.** *Severity:
high.* `snapshot_kind` returned success unconditionally after its pipeline, and
`sweep` never tested the status of its combination. A `grep` or `sort` that
could not run therefore yielded an empty string, which was read as *no
collision* before creation and as *nothing to sweep* during cleanup — the two
places where an empty list is the most dangerous thing to assume. *Fixed:*
`combine_ids` distinguishes an obtained empty list from a failed enumeration or
a failed combination, and both callers act on the difference: the pre-creation
snapshot BLOCKS, and cleanup records the leftovers it could not sweep.

**FINDING-18 — named resources could escape project isolation.** *Severity:
high.* The configuration check inspected only `external: true`. A
non-external network or volume carrying a fixed `name:` passed it — and Compose
*creates or adopts* a resource by that exact name, which may be one the real
deployment owns. §4.7's FINDING-09 closed the `external` route and left this
one open. *Fixed:* every resolved network and volume name must equal
`<project>_<key>` for this invocation's unpredictable project, checked **before**
`compose create` runs. Nothing is created when a name would escape, so a
pre-existing resource cannot be adopted, reconfigured or deleted.

**FINDING-19 — mount-comparison errors were suppressed.** *Severity: medium.*
`sort ... || true` discarded the status of the step the comparison depends on,
and `comm` on an unsorted operand reports arbitrary differences — or none.
*Fixed:* a failed sort or comparison is a failed gate that reports the
requirement as UNPROVEN, which is the honest verdict: the comparison did not
happen, so it neither passed nor failed.

**FINDING-20 — the approved mount set was verified only for self-consistency.**
*Severity: high.* The expectation was derived from `docker compose config` and
compared against `docker inspect`, which proves the two AGREE and nothing more:
a fifth mount present in both was invisible to the comparison, and the count
check was a floor of four rather than an exact set. A comparison between a
configuration and the container that configuration produced cannot detect a
mount that the configuration itself asks for. *Fixed:* exactly the four
approved destinations — configuration, feed, CA, password — are required on
BOTH sides, each a read-only bind with a resolved absolute source. The scratch
tmpfs at `/tmp` stays outside that set and keeps its separate validation.

**FINDING-21 — numeric parsing was octal, unbounded, and could overflow.**
*Severity: high.* `$(( ))` reads a leading zero as OCTAL, so `size=010k` was
8 KiB rather than 10; and `max-file: "09"` is not a valid octal literal at all,
so its `elif` condition took NEITHER branch — the logging bound was never
evaluated and the run still reported success. Separately, the multiplication
happened before any bound was applied, so `size=18014398509483008k` wrapped to
one mebibyte and passed the tmpfs bound. *Fixed:* `to_decimal` reads every value
in base 10, rejects malformed and excessively long input, and bounds the
multiplicand before multiplying.

**FINDING-22 — inspection fields were defaulted, making assertions vacuous.**
*Severity: high.* `// 0` and `// ""` made assertions total AND empty: an absent
`State.Pid` satisfied "no process id is recorded", and an absent `NetworkMode`
satisfied both "not on host network" and "not sharing a container netns". This
is §4.7's FINDING-12 in a different place — an absent field read as a
satisfied requirement. *Fixed:* every required container and image field is
asserted present with the expected type before it is evaluated, and the
defaults are gone except where Docker's own representation uses `null` for
"none" and that `null` IS the requirement (`CapAdd`, `Config.Labels`).

**What the two rounds together say about the method.** Seventeen false-pass
defects were found in one program by review, in two passes, and none by
execution — because until §3.7 it had never been executed against a real image.
The regression suite grew from 47 cases to 319 across the same work. The pattern
in almost every finding is identical: an operation whose failure was
indistinguishable from a clean result. That is the class worth looking for
first in anything else that reports on security properties.

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

## 6. Operator procedures, and what remains blocked

### 6.1 Runtime verification against a real image (SW-P1-05, SW-P1-20) — **CLOSED at `b6b1769`**

**Status.** Executed by the operator at commit `b6b1769` against image
`sha256:b95cc07c…`: build exit 0 with both in-build assertions run, verifier
90 passed / 0 failed / 0 blocked / 0 cleanup problems, `VERIFY exit=0`. The
result is §3.7. SW-P1-05 and SW-P1-20 are VERIFIED on it.

**The access constraint is unchanged, and is not a defect.** The service
account is not in the `docker` group and has no passwordless sudo. By operator
decision this stays that way: `docker` group membership is root-equivalent on
this host, since it permits mounting the host filesystem into a container.
Docker operations remain operator-executed, so a `scamwall` run of
`scripts/check.sh` will continue to report these two gates as `BLOCKED` and
exit 1 (§3.0). That is the correct local result and does not contradict §3.7.

**This section is retained as the renewal procedure.** The evidence is tied to
one image ID and one commit. Rebuild or change a gate input and it lapses —
`docs/REQUIREMENTS_MATRIX.md` §5 — at which point the commands below are run
again, not edited.

**Earlier candidate images.** `sha256:d3c4ed2c…`, built from `b469c592`, was
recorded before any verifier had run. It is superseded and was never verified;
it predates all seventeen findings in §4.7 and §4.8. It is retained in
`docs/REQUIREMENTS_MATRIX.md` §2 as an identity on record and must not be
deployed or cited as evidence.

**Two accounts, deliberately.** Git metadata is read as `scamwall`, because the
repository is owned by `scamwall` and git refuses to operate in another user's
tree; Docker is used by the operator, because only the operator can reach the
daemon. Neither side is given the other's access: **do not** add a
`safe.directory` exception, change repository ownership, or put `scamwall` in
the `docker` group.

```bash
# Run as the operator (the account with Docker access), from anywhere.
set -u
# The ScamWall checkout, owned by the service account. Set for this host; the
# path is deliberately not recorded in this document.
REPO="${SCAMWALL_REPO:?set this to the checkout path}"

# ---- 1. Source identity, read AS scamwall -------------------------------
# git is run under the owning account so no ownership exception is needed.
COMMIT="$(sudo -u scamwall git -C "$REPO" rev-parse HEAD)"
DESCRIBE="$(sudo -u scamwall git -C "$REPO" describe --tags --always --dirty)"
DIRTY="$(sudo -u scamwall git -C "$REPO" status --porcelain | wc -l)"
printf 'SOURCE COMMIT=%s\nDESCRIBE=%s\nUNCOMMITTED FILES=%s\n' \
  "$COMMIT" "$DESCRIBE" "$DIRTY"
# UNCOMMITTED FILES must be 0. A dirty tree means the image cannot be tied
# to a commit, and the evidence would be untraceable.

# ---- 2. Build, through the operator's Docker access ----------------------
docker build \
  -f "$REPO/container/Dockerfile" \
  -t scamwall:local \
  --build-arg VERSION="$DESCRIBE" \
  --build-arg COMMIT="$COMMIT" \
  --build-arg BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "$REPO"
printf 'BUILD exit=%s\n' "$?"
# This build EXECUTES the ELF linkage assertion (SW-P1-20). A dynamically
# linked binary fails the build here rather than at run time.

# ---- 3. Image identity --------------------------------------------------
IMAGE_ID="$(docker image inspect -f '{{.Id}}' scamwall:local)"
printf 'IMAGE ID=%s\n' "$IMAGE_ID"
# Evidence is tied to this, not to the tag.

# ---- 4. Verify, pinned to that image ------------------------------------
# The pin means a tag that moves between these two commands cannot substitute
# another image. The verifier creates a container but never starts one: it
# uses `docker compose create` and `docker create` only, so the authenticated
# application does not run and no credential is used.
SCAMWALL_EXPECTED_IMAGE_ID="$IMAGE_ID" \
  bash "$REPO/scripts/container-runtime-verify.sh" 2>&1 | tee /tmp/scamwall-verify.log
VERIFY_RC="${PIPESTATUS[0]}"
printf 'VERIFY exit=%s\n' "$VERIFY_RC"
```

`VERIFY_RC` is the exit status of the verifier itself, not of `tee` — that is
what `PIPESTATUS[0]` is for. Reading `$?` after a pipeline would report `tee`'s
status, which is 0 almost always, and would turn a failed verification into a
green result.

**What the verifier does to the host.** It creates two containers and one
network under a Compose project named `scamwall-verify-<128 random bits>`,
starts neither, and removes exactly what it created. It refuses to create
anything if a resource already carries that project name, it never issues a
project-wide `compose down`, every resource query is filtered by a label unique
to the invocation, and any resource it cannot attribute to itself is left in
place and reported. **A running deployment is not stopped, removed, inspected,
or adopted.** If the run is interrupted, cleanup still completes; if cleanup
fails, the exit status is nonzero and the remaining identifiers are printed.

**Interpreting the result.**

| Exit | Meaning |
| --- | --- |
| 0 | every required check ran and passed, AND cleanup completed |
| 1 | at least one check failed, could not run, or required cleanup failed — the output distinguishes `FAIL`, `BLOCKED` and `CLEANUP` |
| 2 | the script was invoked wrongly, or the directory is not a ScamWall checkout |

**What to return on a renewal run:**

1. the `SOURCE COMMIT`, `DESCRIBE` and `UNCOMMITTED FILES` lines from step 1;
2. the `BUILD exit` line, and the last ~40 lines of build output — they contain
   the ELF assertion's report, which is SW-P1-20's evidence;
3. the `IMAGE ID` line from step 3;
4. the complete contents of `/tmp/scamwall-verify.log`, and the `VERIFY exit`
   line.

All four are recorded against that image ID. Partial output is weaker: the
verifier's value is that it distinguishes "passed", "failed" and "could not
run", and a truncated log loses exactly that distinction — which is why the
counts for all three categories are recorded in §3.7 and not just the passes.

**Redaction.** The log may name the deployment's resolved paths, its
supplementary group id and its pinned address. None of those belong in this
document; §3.7 records that the assertions held, not the values they held
against. Redact before pasting, or return only the verdict lines and the
identities.

### 6.2 Live Pi-hole read (SW-P2-04, and Phase 2 generally)

Not attempted. Phase 2 has not been entered, and no live read-only test is
started automatically. The current record establishes **configured
permissions**, explicitly not proven access — see `docs/SECURITY_BOUNDARIES.md`
§5.1.

**The hostname mapping, and what §3.7 did and did not settle.** The verified
run resolved the API destination through `pi.hole:host-gateway` — the compose
default, with `PIHOLE_HOST_IP` unset. §3.7 establishes that this mapping is
*pinned exactly as the configuration specifies*: a single `extra_hosts` entry,
present in both the resolved configuration and the created container, with no
second or conflicting entry. That is a statement about the container's name
resolution and nothing else.

Three separate things are settled by nothing so far, and each is Phase 2 work:

| Question | Owner | State |
| --- | --- | --- |
| Does the address behind `host-gateway` actually answer, and is it a Pi-hole? | SW-P2-05 / SW-P2-07 | Not attempted. The container was never started, so nothing was sent |
| Does TLS verification succeed against it — correct CA, correct hostname, no fallback? | SW-P2-02 | Not attempted against anything real. Evidenced only against a fake HTTPS server |
| Can the container identity read the mounted password, and does authentication succeed? | SW-P2-04 / SW-P2-01 | **Unverified.** A read-only mount is a mount; no process has read the file, and no session has been established |

The last row is the one to resist rounding up. `0 failed` in §3.7 covers the
checks the verifier makes, and the verifier deliberately never starts the
application — so a passing runtime verification is not weak evidence of
credential access, it is *no* evidence of it. Both remain unverified until a
Phase 2 run under the actual container identity says otherwise, and that run is
operator-initiated, never automatic.

### 6.3 CI execution (SW-P1-12) — **STILL BLOCKED**

The workflow is reviewed (§3.4) but has never been executed. Running it requires
a push, which is outside the authorisation for this work. This is the one Phase 1
blocker that §3.7 does not touch, and it is the reason Phase 1 does not close.

A local `scripts/check.sh` run does not substitute — §3.0 is not evidence for
this row. It exercises the gate list, not the workflow, and says nothing about
`permissions:`, action pinning, the runner image, or fork-pull-request secret
handling.

#### Proposed procedure — awaiting approval, not executed

Nothing below has been run. It is written out in full so the operator is
approving an exact sequence rather than a description of one.

**What the push triggers.** `.github/workflows/gates.yml` fires on
`push` to `main` or `feat/**`, on `pull_request`, and on `workflow_dispatch`.
The branch is `feat/phase-1-core`, so **the push alone starts a run** — no
second action is needed, and a pull request is not required to obtain the
evidence.

**Pre-push checks**, in order. Each one exists because of a specific way this
push could produce a misleading result:

```bash
cd "$SCAMWALL_REPO"   # the checkout; path not recorded here

# 1. The tree must be clean: a run must be attributable to a commit.
git status --porcelain            # expect: no output

# 2. Confirm what would be pushed, and to where.
git rev-parse HEAD                # expect: b6b1769... (or the doc commit on top)
git log --oneline origin/feat/phase-1-core..HEAD
git remote -v                     # confirm the intended remote

# 3. Confirm the branch is exactly what the workflow's push filter matches.
git rev-parse --abbrev-ref HEAD   # expect: feat/phase-1-core

# 4. Confirm no force is needed. The remote branch must be an ancestor.
git merge-base --is-ancestor origin/feat/phase-1-core HEAD && echo "fast-forward: yes"
```

**The push.** A plain, non-forced push of one branch:

```bash
git push origin feat/phase-1-core
```

`--force` and `--force-with-lease` are deliberately absent. `main` is not
pushed, nothing is merged, and no tag is created.

**If a run must be re-triggered** without a new commit — for example after a
transient runner failure — use the workflow's `workflow_dispatch` entry rather
than an empty commit:

```bash
gh workflow run gates.yml --ref feat/phase-1-core
```

**What to return, to close SW-P1-12:**

1. the run URL, and the commit SHA the run reports;
2. the complete output of the **Record tool versions** step — this is what ties
   the result to a toolchain, and without it the run is not evidence for a
   reproducibility requirement;
3. the per-gate outcome from the **Run the gate suite** step — the full
   `check.sh` transcript, including its summary line;
4. the job's conclusion and its exit status.

#### This run will not be green, and the reason is not a defect

Predicted before the fact, so that the prediction can be checked against the
result rather than constructed afterwards to fit it.

The hosted runner has a Docker daemon, so `docker build` and the container
runtime verification will *attempt* to run rather than report `BLOCKED` for a
missing daemon — which is what the workflow's own comment anticipates. But the
deployment the verifier creates binds two host paths that exist on the operator's
host and cannot exist on a fresh `ubuntu-24.04` runner:

| Mount source | On a hosted runner |
| --- | --- |
| `/etc/scamwall/certs/pihole-ca.crt` | absent. The source is a literal absolute path in `deploy/compose/compose.yaml` with **no** environment override, so it cannot be redirected — only created |
| `${SCAMWALL_SECRET_FILE:-/etc/scamwall/secrets/pihole_app_password}` | absent, though this one *is* overridable |
| `${SCAMWALL_CONFIG:-./config.example.json}` | present — resolves inside the checkout |
| `${SCAMWALL_FEED:-../../testdata/feed.json}` | present — resolves inside the checkout |

`docker compose config` does not detect this: it was tested here with
`SCAMWALL_SECRET_FILE` pointed at a nonexistent path and exited 0. The failure
surfaces later, at `compose create`, and the verifier reports it as `BLOCKED` or
`FAIL` — either of which makes `check.sh` exit 1 and the job red.

**This collides with SW-P1-12's acceptance criterion**, which reads "the hosted
run exists and **passes**". As things stand it cannot pass, so the push alone
does not close the row. Three ways forward; the choice belongs to the operator
and is not made here:

| Option | What it costs | What it buys |
| --- | --- | --- |
| **A — materialise the fixtures in CI.** Add a workflow step before `check.sh` that writes a throwaway CA certificate and password file to those paths, and exports `SCAMWALL_SECRET_FILE` | Edits `.github/workflows/gates.yml`, which is a gate input: it demotes SW-P1-12's review evidence (§3.4) and needs the file re-reviewed | The strongest result — the container gates genuinely execute on a second, independent host, from a clean checkout. It also makes CI reproduce §3.7 rather than merely coexist with it |
| **B — let the container gates report `BLOCKED` in CI and amend the acceptance criterion** so SW-P1-12 closes on "the workflow ran, its gate list matched the local suite, and every gate that could run passed" | Requires amending a requirement to match an observation, which needs saying out loud rather than doing quietly | Closes the row honestly without touching a gate input. The container evidence stays where it already is — §3.7 |
| **C — push as-is first, and decide afterwards** | One red run on the record | Confirms the prediction above against a real log before anything is changed, and produces the run URL and tool-version output that requirements 1 and 2 below ask for |

C then A is the sequence that assumes least. Nothing is changed until the
prediction has been tested.

**Reading the result, once there is one:**

| Outcome | Meaning |
| --- | --- |
| The container gates report `BLOCKED` or `FAIL` on missing host paths | As predicted above. An environment gap, not a defect, and no reflection on §3.7 |
| Every gate passes | The prediction was wrong and the runner supplied something unanticipated. Establish what before recording anything |
| A container gate fails on a **hardening assertion** — a mount set, a bound, a pin | Do not treat this as a CI problem. It is a disagreement with §3.7 about builds of the same commit, and it takes precedence over closing this row |
| A non-container gate fails | The gate list disagrees between the two hosts. That is a reproducibility defect, which is what this requirement exists to detect |

**Fork pull requests are not exercised by this push**, and the workflow's most
security-relevant property — that a fork PR receives no secret and a read-only
token — therefore remains reviewed rather than demonstrated. Closing that
properly needs a pull request from a fork, which is a separate, later step; it
is recorded here so the gap is not lost when SW-P1-12 goes green.

**Not authorised by this section:** pushing `main`, merging, opening or merging
a pull request, tagging, creating a release, publishing an image, or changing
any repository setting.

---

## 7. Evidence status, item by item

Stated plainly so that nothing here is read as more than it is. Newly
established claims are listed alongside the outstanding ones, because a table
of only the gaps invites the reader to assume everything absent from it is
settled.

**Established at `b6b1769`:**

| Claim | Basis |
| --- | --- |
| The ScamWall container image satisfies its runtime hardening assertions | Image `sha256:b95cc07c…`, built from `b6b1769`: 90 passed, 0 failed, 0 blocked, 0 cleanup problems, `VERIFY exit=0`. §3.7 |
| The shipped binary carries no dynamic linking apparatus | The ELF checker and its controls pass (§3.6) **and** the assertion executed inside the `docker build` that produced that image (§3.7). Neither half suffices alone |
| Enforcement is not compiled into the shipped binary | The build's own assertion, executed in the same build. §3.7 |
| The gate suite's exit status matches its printed verdict | `CHECK exit=1` observed directly at `b6b1769`, with two gates BLOCKED on this host. §3.0 |
| The `b6b1769` regression cases discriminate rather than merely agreeing with the code | The `0b083cb` verifier fails 50 of the 319 cases. §3.5 |

**Still not established:**

| Claim | Status |
| --- | --- |
| The image built by the operator from `b469c59` is verified | **Not established, and superseded.** `sha256:d3c4ed2c…` is an identity on record. No verifier ran against it, and it predates all seventeen findings in §4.7 and §4.8. Do not deploy or cite it |
| CI passes | **Not established, and not achievable by the proposed push.** The workflow has never been executed, and as configured it cannot go green on a hosted runner: two of the deployment's bind sources cannot exist there. §4.6 and §6.3. This is the only Phase 1 blocker remaining |
| A fork pull request receives no secret and a read-only token | **Not established.** Reviewed in §3.4; demonstrating it needs a fork PR, which even a successful branch run does not provide. §6.3 |
| The container identity can read the mounted secret | **Not established.** File modes are configured; no process has been observed reading it. A read-only mount at `/run/secrets/pihole_app_password` is a mount, not a successful read — and §3.7 does not weaken this, because the container was never started |
| ScamWall can authenticate to a real Pi-hole | **Not established.** Only a fake HTTPS server has been exercised |
| The destination behind the `pi.hole` pin is reachable, is a Pi-hole, and passes TLS verification | **Not established.** §3.7 proves the pin is configured and applied exactly; nothing was sent through it. Phase 2 — §6.2 |
| The 319-case suite is deterministic to the standard set at `0b083cb` | **Partly established.** §3.3: 30 consecutive runs, 0 failures, against 500 runs for the 237-case suite. At 30 runs a 1-in-50 defect would be missed more often than not. The gap is one of duration, not of method |
| ScamWall detects scam domains accurately | **Not established, and not claimed.** `testdata/feed.json` is a synthetic fixture. It is evidence about signature verification and parsing, and about nothing else. Detection accuracy is Phase 4 and has not begun |

The last row is the one most easily misread, so it is stated twice: a signed
feed proves who wrote it. It says nothing whatever about whether the contents
are correct.

The row above it is the second most easily misread. §3.7 reports `0 failed`
against a real image, and it would be an easy step from there to "the
deployment works". It does not say that. The verifier never starts the
application: it establishes what the container *is*, not what it can *do*.
