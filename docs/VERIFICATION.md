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
| Evidence commit | `aa49797` — *fix(ci): supply the deployment's fixtures, and check the mount sources*. The last commit that changes a gate input |
| Previous evidence commit | `b6b1769151501d89d7f8550d2c8f3378d0e73c3d` — *fix(verify): check list processing, name scope, mounts, numbers and fields*. Retained where cited; superseded for every row §5 of the matrix demotes |
| Verified image | `sha256:b95cc07ca564b115f8bf2d49d642efafc99ae8ff4ae7746caaa7d2ff5e00516b`, built by the operator from `b6b1769` — §3.7. **No image has been built from `aa49797`**, so the image-bound rows are open; §6.1 |
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
| `2a18874` | docs: record the verified image and close the Docker and ELF blockers — the commit CI ran against (§3.8) |
| `c3ae292` | docs: record the first hosted CI run, and a defect it exposed |
| `ef40156` | fix(gates): report a failing gate's verdict, not its first 25 lines — FINDING-23, §4.9 |
| `aa49797` | fix(ci): supply the deployment's fixtures, and check the mount sources — FINDING-24 … FINDING-26, §4.10 |

Results in §3 are produced against `aa49797`, the last commit that changes any
gate input, **except** §3.6 – §3.8, which are tied to the commits and image IDs
named in them and are not re-runnable from here. They are **not** valid for
earlier commits: §4.1 – §4.5 describe defects present at `2edb95a`, §4.7
describes eleven defects present at `b469c59` — including in the runtime
verifier as it stood there, which is the version an operator would have run had
it been executed — §4.8 describes six further defects present at `0b083cb`, §4.9
describes one present at `c3ae292`, and §4.10 three more present at the same
commit.

`b6b1769` changed `scripts/container-runtime-verify.sh` and its regression
suite. Under `docs/REQUIREMENTS_MATRIX.md` §5 that demotes every row resting on
a `scripts/*.sh` gate, so the `0b083cb` transcript is not carried forward for
those rows: the suite was re-run at `b6b1769`, and that run is §3.0. The
regression suite grew from 237 cases to 319 over the same commit.

`ef40156` and `aa49797` change `scripts/check.sh`,
`scripts/container-runtime-verify.sh`, `deploy/compose/compose.yaml` and
`.github/workflows/gates.yml`, and add three scripts. That demotes the same set
of rows again, so the suite was re-run at `aa49797` and that run is now §3.0.
The image-bound rows (SW-P1-05, SW-P1-20) cannot be renewed from here at all —
they need the operator, §6.1.

**Later sessions carry their own identity blocks**, because rewriting this
table each time would lose the commit each observation was actually made at.
`§3.14` covers `f94214a`…`7e11419`; `§3.15` covers the handoff-correction
session and names the commit that supersedes `7e11419` as the candidate. Both
say explicitly which earlier evidence does and does not carry forward.

The rule is worth stating rather than assuming: **evidence is tied to the last commit that changed a gate input.** A
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
| Docker Compose | v5.5.1. Recorded from FINDING-27 onward: it is the tool behind the `docker compose config` gate and behind the runtime verifier's configuration resolution, and two hosts disagreeing about a resolved field could not be explained while it went unrecorded. The runner's version differs and is printed by the workflow's `Record tool versions` step |

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
(runtime-verify with 336 cases, secret-scan controls, pipefail/SIGPIPE), and —
added at `ef40156`/`aa49797` — two more: gate-diagnostics with 62 cases and
compose-fixture with 16, plus the gate reporter's own `--self-test`. The counts
moved this session: `internal/buildcheck/elfcheck` is new (5 functions, the ELF
controls), and the runtime-verify suite grew from 47 cases to 237 at `0b083cb`,
to 319 at `b6b1769` and to 336 at `aa49797`. No fuzz targets exist yet; fuzzing
is a Phase 3 requirement (SW-P3-08).

---

## 3. Phase 1 gate results

### 3.0 Run identity

Run against commit **`aa49797`** on `feat/phase-1-core`, with the tools in
§2.2, as user `scamwall`, in the repository working tree — which `git status
--porcelain` reported as empty before the run, so the checkout is identical to
the commit. The deployment `.env` is gitignored and is the file the operator's
deployment uses; it contains a group id and nothing else, and no value from it
is reproduced here.

**This run supersedes the one recorded here against `b6b1769`.** `aa49797` and
its parent `ef40156` change `scripts/check.sh`, `scripts/container-runtime-
verify.sh`, `deploy/compose/compose.yaml` and `.github/workflows/gates.yml` —
all gate inputs under `docs/REQUIREMENTS_MATRIX.md` §5 — so the earlier
transcript no longer describes the suite that is now in the tree. The `b6b1769`
figures (19 passed, 0 failed, 2 BLOCKED) are retained in §3.5 and §3.8 where
they are compared against, and nowhere else.

The earlier transcript in this section was taken against `0b083cb` in a fresh
`--local` clone. That method is still valid and is preferable when the tree is
dirty; it is not used here because the tree is clean and the run must be tied
to `aa49797` itself.

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

-- gate reporting --
  PASS    gate diagnostics self-test
  PASS    gate diagnostics regression tests

-- compose definition --
  PASS    docker compose config
  PASS    compose definition under runner conditions

-- runtime verifier regression tests --
  PASS    runtime-verify regression tests

-- container runtime (operator-executed, needs daemon) --
  BLOCKED docker build (docker daemon not reachable by scamwall)
  BLOCKED container runtime verification (docker daemon not reachable by scamwall — run scripts/container-runtime-verify.sh as the operator)

-- working tree --
  PASS    no uncommitted generated artifacts

======================================================
 22 passed, 0 failed, 2 BLOCKED, 0 optional-skipped
 RESULT: NOT COMPLETE — required gates failed or could not run.
======================================================
CHECK exit=1
```

**Three gates are new since `b6b1769`**, which is why the count moved from 19 to
22:

| Gate | What it establishes |
| --- | --- |
| `gate diagnostics self-test` | The failure reporter shows a failure that appears below the first twenty-five lines, states any truncation, and redacts credential-shaped decoys. §4.9 |
| `gate diagnostics regression tests` | 62 cases driving `check.sh`'s own `require`: status preservation, cleanup visibility, no false pass on large output, no decoy in the log or the retained artifact. §4.9 |
| `compose definition under runner conditions` | The real deployment definition, resolved with no `.env` and no operator paths, produces exactly the approved mount set from disposable fixtures — the local reproduction of what CI faces. §3.9 |

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
| SW-P1-01 | `scripts/tests/runtime-verify-test.sh`, 336 cases, all passing | VERIFIED |
| SW-P1-02 | *no git dependency*: the verifier succeeds with a `git` on `PATH` that exits 128 on every call, the git-log fixture stays empty, and no git command appears in the comment-stripped source | VERIFIED |
| SW-P1-03 | *absence versus search failure*: failed inspect, history, export, `docker create`, `compose ps`, container listing, configuration resolution, and both malformed and empty JSON each produce a nonzero exit | VERIFIED |
| SW-P1-04 | *incomplete and malformed inspection data*: `[]`, non-JSON, a non-array image inspection, a non-digest image identifier, and twelve structurally valid documents with a required field deleted are each rejected before any conclusion is drawn | VERIFIED |
| SW-P1-05 | *image identity*, *mounts*, *mount sources on the host*, *tmpfs bounds*, *logging bounds*, *API hostname pinning*, *supplementary group*, *hardening regressions* against the scripted fake | **IMPLEMENTED-UNVERIFIED against a real image.** The operator run in §3.7 is against `sha256:b95cc07c…` built from `b6b1769`; `aa49797` changes both `compose.yaml` and the verifier, so that evidence does not carry forward. Renewal: §6.1 |
| SW-P1-06 | *resource ownership* and *cleanup as a verdict*: the command log shows removal of exactly the resources this run created, every listing filtered by a label unique to this invocation, no `compose down` at all, and no reference to any pre-existing resource | VERIFIED |
| SW-P1-07 | Coverage map in §3.2; pre-fix comparison in §3.5 | VERIFIED |
| SW-P1-08 | `shellcheck --severity=style` over all 13 tracked scripts, clean | VERIFIED |
| SW-P1-09 | §4.2 | VERIFIED |
| SW-P1-10 | §5 | VERIFIED |
| SW-P1-11 | §4.3 | VERIFIED |
| SW-P1-12 | `.github/workflows/gates.yml`, reviewed in §3.4 and re-reviewed at `aa49797`; executed three times, the third **passing** at `72bc84c` — run 34047025567, 24 passed / 0 failed / 0 BLOCKED, gate list identical to §3.0. §3.12 | VERIFIED |
| SW-P1-13 | `go test -race -count=1 ./...` passes; 129 test functions; no test removed or weakened | VERIFIED |
| SW-P1-14 | §4.1, and the repeat-run evidence in §3.3 | VERIFIED |
| SW-P1-15 | `cmd/scamwall/main_test.go`, 15 test functions, all passing | VERIFIED |
| SW-P1-16 | *cleanup as a verdict*: ordering (cleanup precedes the verdict line), failed container removal, failed network removal, TERM mid-run, mid-run verification failure, and exactly one removal attempt per resource | VERIFIED |
| SW-P1-17 | *resource ownership*: container and network collisions block creation; a coexisting deployment is never listed or touched; partial creation is cleaned up by attribution; an unattributable resource is preserved and reported | VERIFIED |
| SW-P1-18 | *consistent Compose configuration*: all three Compose operations carry the same `--env-file` and project name; a `.env` value deliberately different from the resolved value is not used; resolution and parse failures block the run | VERIFIED |
| SW-P1-19 | *mounts*: the cases covering empty, absent, missing, extra, duplicated, writable, wrong-source, wrong-type and prohibited mounts, plus the pre-fix controls; an exact four-destination approved set enforced independently of the configuration and a failed comparison treated as UNPROVEN (§4.8, FINDING-19 and FINDING-20); and — added at `aa49797` — *mount sources on the host*, covering an absent source, a directory where a file is required, an absent or world-reachable password file, and a secret source taken from a prohibited path (§4.10) | VERIFIED |
| SW-P1-20 | §3.6 — the ELF controls pass, and they are unchanged at `aa49797`; §3.7 and §3.8 — the in-build assertion executed inside two independent `docker build`s of `b6b1769`/`2a18874`. **The image-bound half is IMPLEMENTED-UNVERIFIED at `aa49797`**: no image has been built from this commit. Renewal: §6.1 |

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

**Re-reviewed at `aa49797`**, which adds three steps. The workflow is a gate
input, so this re-review is required rather than optional
(`docs/REQUIREMENTS_MATRIX.md` §5):

| New step | Property | How it is met |
| --- | --- | --- |
| Create disposable deployment fixtures | Nothing production-derived enters CI | Both files are generated on the runner. Nothing is copied from any host, no key pair is generated, no committed fixture is rewritten, and no site value appears — the compose overrides carry the operator defaults, which CI replaces with runner-local paths |
| | Fixtures cannot enter an image | They are written under `RUNNER_TEMP`, outside the checkout, and the build context is the checkout (`../..`). `scripts/tests/compose-fixture-test.sh` asserts that neither fixture path lies under the resolved build context |
| | Fixtures are not readable by other accounts | Directory 0700, files 0600, both set with an explicit `chmod` rather than `mkdir -m` (which applies only to the deepest component). The verifier independently checks that the password file is not reachable by every account on the host |
| | No authentication happens | The verifier uses `docker compose create` and `docker create` only. Nothing is started, so the password is mounted and never read |
| Upload gate diagnostics | Cannot turn a red job green | `if: always()`, and it runs after the gate step has already concluded. An upload action does not alter a prior step's conclusion |
| | Cannot publish a credential | Everything in the directory has been through `scripts/gate-diagnostics.sh`, which is self-tested against eleven credential decoys and writes nothing it could not sanitize. §4.9 |
| | Pinned | `actions/upload-artifact` by commit SHA `043fb46…` (v7.0.1), with the tag in a comment, like the other two |
| Remove disposable fixtures | Cleanup is a result, not a hope | `if: always()`, and it re-tests for the directory after removing it and fails the job if it survives. "The runner is discarded afterwards" is not a cleanup procedure |

**No secret is referenced by the workflow at any point**, before or after this
change, so the `pull_request`-not-`pull_request_target` property is unaffected:
a fork pull request still receives a read-only token and nothing to exfiltrate.
The fixtures are generated from `/dev/urandom` on the runner, so a fork PR
generating its own throwaway password reveals nothing about anything.

The YAML was parsed with `gopkg.in/yaml.v3` to confirm it is well-formed and
that `permissions` resolves to `map[contents:read]`. At `aa49797` that check
was not repeated in the same form — the pinned toolchain has no network access
to fetch that module here — so the file was instead parsed by the Compose YAML
reader, which reached interpolation without a syntax error, confirming
well-formedness but **not** re-confirming the `permissions` value by parse. The
`permissions` blocks are unchanged from the reviewed text above and are visible
in the diff; that is weaker evidence than a parse and is labelled as such.

**This is a review, and a review is not an execution.** Three things are
routinely conflated, so they are separated here:

| Level | State |
| --- | --- |
| Implementation review — the file read property by property against the requirement | DONE, above |
| Local simulation — the same GATE LIST executed locally by `scripts/check.sh` (§3.0) | DONE, and it says nothing about `permissions:`, action pinning, the runner image, or fork-PR secret handling, because none of those exist locally |
| Hosted CI run — the workflow itself executed on GitHub, with a run URL and log | **NOT DONE** |

SW-P1-12 is therefore **BLOCKED**, not "VERIFIED as written". The middle row
above has since been executed — run 34036997074, §3.8 — and the bottom row is
what is still missing: a hosted run that passes. The workflow at `aa49797` has
never been executed at all, and reviewing a change to it is not running it.
§6.3.

### 3.5 Deliberate failure injection

"The gates pass" is a much weaker statement than it looks unless the gates can
also be shown to fail. Each injection below was made in a fresh `--local` clone
of this repository, with `scripts/check.sh` run unmodified.

**These injections were run at `b6b1769` and have not been repeated at
`aa49797`**, so the counts below are that commit's (19, not 22). They are
retained rather than re-run because each one demonstrates a specific gate's
ability to fail, and none of those gates changed; the reporting *around* them
did, which is a different property and is covered by §3.10 and §4.9 — including
an injection at `aa49797` that this table does not have: a gate exiting **3**,
so that the status is distinguishable from a plain failure.

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

### 3.8 Hosted CI run (SW-P1-12)

The workflow was executed. This is the first hosted run of `gates.yml`; the
branch was pushed with operator approval, and nothing was merged.

| | |
| --- | --- |
| Run | <https://github.com/LordHorkos/scamwall/actions/runs/34036997074> |
| Commit reported by the run | `2a18874ab84de80f145e3c57cae083d5dfcba71b` |
| Trigger | `push` to `feat/phase-1-core` |
| Runner | Ubuntu 24.04.4 LTS |
| Duration | 3m01s |
| Job conclusion | **failure** |

**Tool versions, from the run's own `Record tool versions` step.** This is what
makes the result attributable, and it is reproduced in full rather than
summarised:

```
commit:      2a18874ab84de80f145e3c57cae083d5dfcba71b
runner:      Ubuntu 24.04.4 LTS
go:          go version go1.26.8 linux/amd64
staticcheck: staticcheck 2026.2.1 (0.8.1)
govulncheck: Go: go1.26.8 Scanner: govulncheck@v1.7.0 DB: https://vuln.go.dev DB updated: 2026-09-02 19:12:04 +0000 UTC
shellcheck:  0.11.0
gitleaks:    8.30.0
jq:          jq-1.7
docker:      Docker version 28.0.4, build b8034c0
```

Every version matches the set in §2.2 — the same Go toolchain, the same
analysers, the same vulnerability database timestamp. Two hosts, one toolchain:
that is the reproducibility claim SW-P1-12 exists to test, and this run is the
first evidence for it.

**Per-gate outcome.**

| Gate | Local (§3.0) | CI |
| --- | --- | --- |
| toolchain (2 gates), gofmt, build, vet, `go test -race` | PASS | PASS |
| staticcheck, shellcheck, govulncheck self-test, govulncheck by content | PASS | PASS |
| secret scan tree / controls, independent scan self-test / scan, container security, SIGPIPE | PASS | PASS |
| `docker compose config` | PASS | PASS |
| runtime-verify regression tests | PASS | PASS |
| **`docker build`** | BLOCKED (no daemon) | **PASS** |
| **container runtime verification** | BLOCKED (no daemon) | **FAIL** |
| working tree clean | PASS | PASS |
| **Summary** | 19 passed, 0 failed, 2 BLOCKED | **20 passed, 1 failed, 0 BLOCKED, 0 optional-skipped** |

The gate list is identical on both hosts, which is the second thing this row
asks for. `check.sh` is the single definition of a gate run and CI maintains no
parallel list, so the lists cannot drift — this run demonstrates that rather
than assuming it.

**`docker build` passed on the runner, and that is worth separating out.** It is
an independent second-host execution of the ELF linkage assertion and the
enforcement-absent assertion, on a different Docker version (28.0.4 against the
operator's 29.8.0), from a clean checkout, by an account unrelated to the
operator's. SW-P1-20 was already closed by §3.7; this corroborates it rather
than establishing it, and corroboration from an independent host is the thing
§3.7's "form of the evidence" note said was missing.

**The runtime verification failed, and the log does not say why.** It reached
image identity — the image resolved to `sha256:1e3c716e…`, a different build of
the same source on a different host, and `SCAMWALL_EXPECTED_IMAGE_ID` is not set
in CI, so the tag was trusted — and the output stops there. It stops because
`scripts/check.sh` truncates a failing gate's captured output to its first 25
lines (§4.9). Everything visible in the run log is a `PASS`; the failure itself
is below the cut.

So the honest reading of this row is narrower than it first appears:

| Claim | State |
| --- | --- |
| The workflow executed on GitHub, with a run URL and log | **Established** |
| The recorded tool versions match the local set | **Established** |
| CI's gate list matches the local suite's | **Established** |
| `docker build` succeeds on an independent host | **Established** |
| The run passes | **No** — it failed, as predicted in §6.3 |
| The runtime verification failed *because the deployment's host paths are absent on the runner* | **Predicted in §6.3, NOT confirmed.** The prediction anticipated `BLOCKED` or `FAIL`, and `FAIL` occurred — but a correct prediction of the outcome is not evidence of the cause, and the cause is not in the log |

That last row is the one to hold the line on. The prediction and the result
agree, the explanation is plausible, and nothing observed here tests it. It
stays a hypothesis until §4.9 is fixed and a run shows the verifier's actual
verdict.

**Recovery attempted, at `aa49797`, and the omitted output is gone.** Before
anything was changed, the run was re-examined for the missing material:

```bash
gh run view 34036997074 --json headSha,workflowName,jobs   # head SHA, job, per-step conclusions
gh run view 34036997074 --log                              # 392 lines, the complete job log
gh api repos/LordHorkos/scamwall/actions/runs/34036997074/artifacts
#   {"total_count":0,"artifacts":[]}
```

The run has **no artifacts**, and the job log contains exactly the twenty-five
lines already quoted — counted line by line against `head -25`, which they match
exactly. There is no second copy of a step's output in the Actions API. **The
cause of that failure cannot be recovered from that run, and this document will
not assert one.** What the run does still establish is listed in the table
above, and that list is unchanged.

The identity reconciliation is also worth stating, because it decides which
evidence survives: `b6b1769..2a18874` and `2a18874..c3ae292` are
**documentation-only** (`git diff --stat` lists only `docs/`), so the tested
tree at `2a18874` is byte-identical to `b6b1769` outside `docs/`. The operator
evidence in §3.7 and the CI run in §3.8 therefore describe the same source. That
equality ends at `ef40156`.

---

### 3.9 The runner's conditions, reproduced locally (SW-P1-12)

Run at `aa49797`, as `scamwall`, with **no Docker daemon**. This is what could
be tested here about the CI failure without the daemon the service account
cannot reach, and it is deliberately narrower than the claim it supports.

`scripts/tests/compose-fixture-test.sh` builds a synthetic checkout containing
only the files Compose reads, **without `deploy/compose/.env`** — that file is
gitignored, so a fresh clone never has one, and running the test from the
operator's checkout would otherwise pick the local one up and hide the very
difference under examination. It then resolves the real
`deploy/compose/compose.yaml` under three environments and inspects the result
with the verifier's own lifted `approved_mount_problems`.

```
== deployment definition under hosted-runner conditions ==

ok   the synthetic checkout has no .env, as a fresh clone has none
ok   the definition resolves with no overrides at all
ok   the CA default is unchanged for the operator
ok   the password default is unchanged for the operator
ok   compose config exits 0 even when every bind source is absent (which is why it cannot be the check)
ok   the verifier's host-side rule does detect the absent sources
ok   the definition resolves under CI conditions
ok   CI resolves exactly the 4 approved mounts, each a read-only bind
ok   every CI-resolved mount source exists and is a regular file
ok   the container sees identical mount destinations in CI and on the operator's host
ok   no bind may have its source auto-created (create_host_path is false on all of them)
ok   the fixtures lie outside the image build context (…/checkout)
ok   the CI password fixture is not readable by every account on the host
ok   an override pointing the CA at Pi-hole's own state is caught by the prohibited-path rule
ok   an override pointing the password at the Docker socket is caught
ok   the fixture directory is removable, leaving nothing behind

16 test(s), 0 failure(s)
```

**What this establishes, precisely:**

| Claim | State |
| --- | --- |
| Under runner conditions the definition names two bind sources that cannot exist on a fresh `ubuntu-24.04` | **Established, by resolution rather than by reading.** Both resolve to `/etc/scamwall/…` when nothing overrides them |
| `docker compose config` does not detect that | **Established.** It exits 0 with every bind source absent — so the CI gate that passed could not have caught it |
| The overrides do not move the operator's defaults | **Established.** Resolved with no environment at all, both sources are the operator paths |
| CI and the operator's host verify the same thing | **Established for the configuration.** The four mount destinations the container sees are identical in both; only the sources differ |
| The CI failure of §3.8 was *caused* by those absent sources | **Still not established.** This shows the precondition held on that runner. It does not show which assertion fired, because that needs a daemon, and the run that had one discarded its output |

That last row is the discipline this section exists for. A demonstrated
precondition and a matching outcome are not a demonstrated mechanism.

**A defect was demonstrated along the way, and is fixed rather than left for a
redundant red run.** Docker's default for a missing bind source is to create an
empty *directory* at it and mount that. A deployment with no CA and no password
file therefore produces a container whose mount set, destinations and read-only
flags are all exactly as required — and every assertion in `SW-P1-19` passes,
against a container that has a directory where its trust anchor should be. That
is a false pass in the class SW-P1-07 enumerates, and it does not need a hosted
run to establish. It is fixed two ways at `aa49797` (FINDING-25, §4.10).

---

### 3.10 The failure reporter, demonstrated end to end (FINDING-23)

The regression suite proves the reporter's properties in isolation. This is the
whole `check.sh` driven with a deliberately failing gate, because "the unit
tests pass" is not the same claim as "a red run is diagnosable".

A fake `staticcheck` was placed first on `PATH`. It reports progressively — 40
`PASS` lines, then a credential decoy, then the failure and the verdict — and
exits **3**, a status neither 0 nor 1:

```bash
PATH="$FAKEBIN:$PATH" GITHUB_ACTIONS=true SCAMWALL_GATE_DIAG_DIR="$DIAG" \
  bash ./scripts/check.sh; echo "INJECTED CHECK exit=$?"
```

```
  FAIL    staticcheck ./...
         --- why it failed (exit status 3) ---
         FAIL    the injected failure, at line 42, below the old 25-line cut
         RESULT: injected gate INCOMPLETE
         --- full output (43 line(s), sanitized) ---
::group::gate output: staticcheck ./...
         PASS    checked package 1
         …
         PASS    checked package 40
         password=<redacted>
         FAIL    the injected failure, at line 42, below the old 25-line cut
         RESULT: injected gate INCOMPLETE
::endgroup::
         sanitized capture retained at: …/staticcheck-.-....log
INJECTED CHECK exit=1
```

Six things are observable there at once, and each is a separate requirement:
the failure at line 42 is visible where `head -25` would have cut at line 25;
the reason and the verdict are printed **before** the full capture and outside
the collapsible group; the command's own exit status **3** is reported rather
than collapsed to "failed"; `password=…` is redacted; the CI grouping markers
are emitted; and a mode-600 artifact is retained in a mode-700 directory.

**The reporter also earned its place on a real failure during this work.** With
the decoy fixtures committed, `independent secret scan` failed, and the log said
why in full — two `generic-api-key` findings, named by rule, file and line, in
both the history scan and the publishable-tree scan. Under the superseded
reporter that gate's output would have been cut before the findings. The decoys
were then assembled at run time instead of written as literals, which is what
the other decoys in the same file already did, so no allowlist entry was added
and no hole was opened in the detector. The two commits were rebuilt rather than
patched, because a decoy in history is permanent and neither had been pushed.

---

### 3.11 Second hosted CI run (SW-P1-12)

The workflow at `07154b6` was executed. This is the first run of the workflow as
changed by `aa49797`, and the first in which the container gates actually ran.

| | |
| --- | --- |
| Run | <https://github.com/LordHorkos/scamwall/actions/runs/34045148578> |
| Commit reported by the run | `07154b649c5ef43162e70319986eefb248f059e5` |
| Trigger | `push` to `feat/phase-1-core` |
| Runner | Ubuntu 24.04.4 LTS, Docker 28.0.4 |
| Duration | 3m39s |
| Job conclusion | **failure** |
| Summary | **23 passed, 1 failed, 0 BLOCKED, 0 optional-skipped** |

**Every required step's result**, because "the job failed" is not a per-step
report:

| Step | Result |
| --- | --- |
| Set up job, checkout, Set up Go, Install ShellCheck, Install gitleaks, Install Go analysis tools, Record tool versions | success |
| **Create disposable deployment fixtures** | **success** — `-rw------- runner runner 232 pihole-ca.crt`, `-rw------- runner runner 45 pihole_app_password`, in a 0700 directory. No content echoed |
| **Run the gate suite** | **failure**, exit 1 |
| **Upload gate diagnostics** | success — artifact `gate-diagnostics-34045148578-1`, 792 bytes, expires 2026-09-13 |
| **Remove disposable fixtures** | success — `CI fixtures removed.`, and the step re-tests for the directory before saying so |
| Post checkout, Complete job | success |

**Three things this run establishes that no previous one did.**

*First, the container gates execute and pass on an independent host:*

```
-- container runtime (operator-executed, needs daemon) --
  PASS    docker build
  PASS    container runtime verification
```

That is the whole purpose of option A, and it worked. The runtime verifier ran
on a CI-built image with CI fixtures and passed every assertion — including the
three added at `aa49797`: exactly the approved mounts, every source an existing
regular file, and the password file not world-readable through its path. The
`b6b1769` run of the verifier had a real CA and a real password behind those
mounts; this one had fixtures. Both satisfied the same checks.

*Second, a red run is now diagnosable from its own log.* The failing gate
printed its reason, then its complete sanitized output inside a `::group::`,
then the artifact path — 21 lines where the previous run gave 25 lines of `PASS`
and no diagnosis:

```
  FAIL    compose definition under runner conditions
         --- why it failed (exit status 1) ---
         FAIL no bind may have its source auto-created
         --- full output (21 line(s), sanitized) ---
::group::gate output: compose definition under runner conditions
         …
         FAIL no bind may have its source auto-created
                resolved: 'unset'
         …
##[endgroup]
         sanitized capture retained at: /home/runner/work/_temp/gate-diagnostics/…
```

FINDING-23's fix is now observed on a runner, not only locally. The `::group::`
markers, the artifact upload and the retained capture all worked as designed.

*Third, the failure is a defect in this session's own work, not in the
deployment* — FINDING-27, §4.11. The one failing gate is
`compose definition under runner conditions`, added at `aa49797`. It asserted a
property of the deployment through a channel that does not carry that property
on every Compose version.

**What this run does NOT establish.**

| Claim | Why not |
| --- | --- |
| CI passes | It did not. 23 passed, 1 failed; the acceptance criterion for SW-P1-12 is unchanged and unmet |
| SW-P1-05 or SW-P1-20 are renewed | The verification passed against an image whose **ID is nowhere in the log**. `check.sh` prints nothing for a passing gate, so a green container gate does not say what it was green about. FINDING-28, §4.11 |
| Why the `2a18874` run failed | Still unrecoverable from that run. This run is a different commit with fixtures present, so it cannot speak to it |
| `bind.create_host_path: false` is honoured by the runner's Compose | Unknown, and now known to be unknown. See §4.11 |

---

### 3.12 Third hosted CI run — **PASSING** (SW-P1-12)

The workflow at `72bc84c` was executed and **passed**. This is the evidence
SW-P1-12 has been blocked on since it was written.

| | |
| --- | --- |
| Run | <https://github.com/LordHorkos/scamwall/actions/runs/34047025567> |
| Commit reported by the run | `72bc84c13f4e6914bfb015e87d46a5234e8f5234` |
| Trigger | `push` to `feat/phase-1-core` |
| Runner | Ubuntu 24.04.4 LTS |
| Duration | 3m34s |
| Job conclusion | **success** |
| Summary | **24 passed, 0 failed, 0 BLOCKED, 0 optional-skipped** |
| Verdict line | `RESULT: all required gates passed.` |

**Every step succeeded.** Setup, checkout, Go, ShellCheck, gitleaks, Go analysis
tools, tool versions, fixtures, the gate suite, the image-identity record, the
diagnostics upload, fixture removal, and both post-job steps.

**Tool versions, from the run's own step**, reproduced in full because that is
what makes the result attributable:

```
commit:      72bc84c13f4e6914bfb015e87d46a5234e8f5234
runner:      Ubuntu 24.04.4 LTS
go:          go version go1.26.8 linux/amd64
staticcheck: staticcheck 2026.2.1 (0.8.1)
govulncheck: Go: go1.26.8 Scanner: govulncheck@v1.7.0 DB: https://vuln.go.dev DB updated: 2026-09-02 19:12:04 +0000 UTC
shellcheck:  0.11.0
gitleaks:    8.30.0
jq:          jq-1.7
docker:      Docker version 28.0.4, build b8034c0
compose:     Docker Compose version v2.38.2
```

The last line is new, and it retrospectively confirms FINDING-27 (§4.11):
**v2.38.2** here against **v5.5.1** on the operator's host. The two disagree
about whether `create_host_path` appears in rendered configuration, which is
exactly what the previous run failed on and exactly what could not be diagnosed
while the version went unrecorded.

**The complete gate transcript**, as the run produced it:

```
-- toolchain --
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
-- gate reporting --
  PASS    gate diagnostics self-test
  PASS    gate diagnostics regression tests
-- compose definition --
  PASS    docker compose config
  PASS    compose definition under runner conditions
-- runtime verifier regression tests --
  PASS    runtime-verify regression tests
-- container runtime (operator-executed, needs daemon) --
  PASS    docker build
  PASS    container runtime verification
-- working tree --
  PASS    no uncommitted generated artifacts
======================================================
 24 passed, 0 failed, 0 BLOCKED, 0 optional-skipped
 RESULT: all required gates passed.
```

**Gate lists compared**, which is the second half of the acceptance criterion:

| | Local, §3.0 | CI |
| --- | --- | --- |
| Gates in the suite | 24 | 24 |
| Passed | 22 | **24** |
| BLOCKED | 2 (no daemon) | **0** |
| Failed | 0 | 0 |
| Exit status | 1 | 0 |

Identical lists, in identical order. The difference is entirely the two
container gates, which are `BLOCKED` here and `PASS` there — the intended
behaviour, and the reason `BLOCKED` was made to fail the suite rather than be
skipped.

**The image the container gates ran against**, recorded by the new step
(FINDING-28):

```
verified image: sha256:d7c44949d56d4f609b3f184464521a2d95c6b34e628f69fd5b145ad6104bba07
source commit:  72bc84c13f4e6914bfb015e87d46a5234e8f5234
```

**Fixtures and diagnostics.** The fixture directory was created 0700 with 0600
files, and `CI fixtures removed.` was printed by the step that re-tests for the
directory before reporting success. The diagnostics artifact count is **0** —
`if-no-files-found: ignore`, and a run with no failing gate produces no captures.
That is the correct behaviour and is worth recording as an observation rather
than an absence: the artifact appeared when there was a failure (§3.11, 792
bytes) and did not when there was none.

#### What this closes, and what it does not

**SW-P1-12's acceptance criterion is met.** "The hosted run exists and passes,
and its gate list matches the local suite's" — both halves, at a named commit,
with a run URL, recorded tool versions and a per-gate outcome. The row moves to
VERIFIED. The criterion was never amended; CI was made able to satisfy it.

**Independently re-verified at `b6e70f4`**, from the run itself rather than from
this document: `gh run view 34047025567` reports `conclusion: success`,
`headSha: 72bc84c13f4e6914bfb015e87d46a5234e8f5234`, `event: push`, and all
fifteen steps `success`; the downloaded run log contains the `24 passed, 0
failed, 0 BLOCKED` summary line, `RESULT: all required gates passed.`, `verified
image: sha256:d7c44949…`, `source commit: 72bc84c…`, and `CI fixtures removed.`
The workflow configures no build cache and the runner is fresh, so every `RUN`
in the build executed rather than being restored.

**It closes SW-P1-20.** That row's acceptance is "the controls pass, AND the
assertion is observed to run inside a real `docker build`". Both halves hold at
`72bc84c`: the controls pass (§3.6, re-run at `b6e70f4`), and the assertion is a
`RUN` step in a build that exited 0 on an uncached runner, producing
`sha256:d7c44949…`. **An earlier revision of this section said the CI run did not
renew SW-P1-20. That was wrong, and the error was one of over-application:** the
four CI/deployment differences tabulated below are differences in the *deployment
the container is created from*. The ELF assertion is a property of the
*executable*, asserted in the build stage, before any deployment exists. It does
not read the password, the CA, the supplementary group or the mount set, so no
difference in those can bear on it. The row is now VERIFIED, **bound to image
`sha256:d7c44949…`** — the artifact the assertion actually ran against.

**It does NOT close SW-P1-05**, and the reason is specific rather than
procedural. `container runtime verification` passed on the runner against a
named image, which looks like exactly what that row asks for. It is not, because
CI resolves a *different deployment*:

| Setting | Operator's deployment | What CI verified |
| --- | --- | --- |
| `group_add` | `989` — the gid that owns the password file | **`65532`** — the container's own gid, which grants nothing extra |
| CA source | `/etc/scamwall/certs/pihole-ca.crt`, the real private CA | a throwaway placeholder under `RUNNER_TEMP` |
| Password source | `/etc/scamwall/secrets/pihole_app_password` | 32 random bytes generated on the runner |
| Image | built on the operator's host | `sha256:d7c44949…`, built on the runner |

The supplementary group is the sharpest of these and was checked directly rather
than assumed: `deploy/compose/.env` is gitignored, so a fresh clone has none, and
`${SCAMWALL_SECRET_GID:-65532}` falls back to the default. Resolving the
definition with no `.env` yields `group_add: ["65532"]`; with the operator's,
`["989"]` — confirmed again at `b6e70f4` by rendering the definition locally
(§3.13). **CI therefore verified that a supplementary group is configured
correctly, not that the deployment's supplementary group is.**

**What CI does establish for SW-P1-05, precisely.** Against a real image on an
independent host, from a clean checkout, by an unrelated account: the mount set
and its destinations, the read-only flags, the image-identity discipline, the
hardening flags, the tmpfs and logging bounds, the resource limits, and the fact
that the verifier's assertions can all be satisfied by a correctly shaped
deployment. What remains unevaluated against the operator's configuration is
narrow and nameable — it is listed in §6.1 and in the row itself, and it is not
"everything".

**The pin was not exercised.** CI runs the verifier without
`SCAMWALL_EXPECTED_IMAGE_ID`, so the `SCAMWALL_EXPECTED_IMAGE_ID` comparison was
skipped there. It is covered by the regression suite against the fake (§3.5) and
by the operator procedure, which sets it (§6.1).

Stating it the other way, because this is the row most likely to be over-read:
**a green CI badge on this repository does not mean the deployment is
verified.**

---

### 3.13 Evidence reconciled at `b6e70f4` (this session)

Nothing here is new implementation. It is the set of observations made to
confirm that the record above still describes the repository, made before any
operator command was proposed.

| Claim under test | How it was checked | Result |
| --- | --- | --- |
| Local `HEAD` is `b6e70f4`, tree clean, branch ahead of `origin/feat/phase-1-core` by one | `git rev-parse HEAD`, `git status --porcelain`, `git branch -av` | Confirmed. Remote is `72bc84c`; `main` is `66aff2e` |
| `b6e70f4` changes documentation only | `git show --stat b6e70f4` | Confirmed: `docs/IMPLEMENTATION_PLAN.md`, `docs/REQUIREMENTS_MATRIX.md`, `docs/VERIFICATION.md`. No gate input is touched, so the CI evidence at `72bc84c` applies unchanged to this tree |
| The CI run is real and passed at the stated commit | `gh run view 34047025567 --json` | `conclusion: success`, `headSha: 72bc84c…`, `event: push`, all 15 steps `success`, 16:56:22Z → 16:59:59Z |
| The gate transcript, image record, diagnostics handling and fixture cleanup | the run log, downloaded with `gh run view --log` | `24 passed, 0 failed, 0 BLOCKED, 0 optional-skipped`; `RESULT: all required gates passed.`; `verified image: sha256:d7c44949…`; `source commit: 72bc84c…`; `CI fixtures removed.`; runner `docker 28.0.4` / `compose v2.38.2` |
| The CI build could not have restored a cached ELF assertion | the workflow declares no cache action and no buildx cache; the runner is fresh | Confirmed — so the assertion executed |
| The local gate suite still reports what §3.0 says | `bash scripts/check.sh` at `b6e70f4` | **22 passed, 0 failed, 2 BLOCKED, 0 optional-skipped; `CHECK exit=1`.** The two BLOCKED are `docker build` and `container runtime verification`, both "docker daemon not reachable by scamwall" |
| The operator's `.env` really does change what the verifier will assert | `docker compose --env-file deploy/compose/.env -f deploy/compose/compose.yaml config --format json`, run **as `scamwall`** — `compose config` needs the CLI, not the daemon | `group_add: ["989"]`. Without the `.env`, `["65532"]` |
| The bind sources the new host-side check will evaluate | the same rendering | `/etc/scamwall/certs/pihole-ca.crt`, `/home/scamwall/scamwall/deploy/compose/config.example.json`, `/home/scamwall/scamwall/testdata/feed.json`, secret `/etc/scamwall/secrets/pihole_app_password`. Compose resolves the two relative sources to absolute paths, so the check will not depend on the working directory |
| Those sources exist as regular files | `stat` as `scamwall` | CA `644 root:root`, config and feed `664 scamwall:scamwall`. The secrets directory is `0750 root:swsecret` and `scamwall` cannot list it — which is why the procedure must run as root |
| `create_host_path: false` is observable on this host's Compose | the same rendering, Compose **v5.5.1** | Rendered on all three binds. CI's v2.38.2 omits it, which is what `72bc84c` taught the fixture test to handle in both directions |
| The verifier never starts anything | every `docker` invocation in `scripts/container-runtime-verify.sh` enumerated | `create`, `inspect`, `ps`, `ls`, `history`, `export`, `rm`, `network ls/inspect/rm`, `compose config/create/ps`. No `up`, `start` or `run` |
| The image the operator would build is byte-identical in context to `b6b1769`'s | `.dockerignore` admits only `go.mod`, `go.sum`, `cmd/`, `internal/`; `git diff b6b1769..HEAD` touches none of them, nor `container/Dockerfile` | Confirmed — which is why the build-cache question in §6.1 is a real one and is now guarded |

**What this session did not do.** It did not reach the Docker daemon, build an
image, create a container, read the application password, contact a Pi-hole, or
push anything. `origin/feat/phase-1-core` is still `72bc84c`.

### 3.14 Implementation session at `f94214a` … `7e11419`

Work performed while the operator was away, under an order that permitted
implementation and local verification but not pushing, merging, contacting the
live Pi-hole, or declaring any phase complete. Nothing here closes a
requirement that needs a hosted run or a Docker daemon; where a boundary was
reached it is named rather than worked around.

**Identity.**

| Item | Value |
| --- | --- |
| Starting HEAD | `f94214aba8d56c8b133b9049a168b11ce64f3156` |
| **Candidate** | `7e1141997cc1f7484144f07c1fb05cde5d39e280` — the last commit that changes a gate input. Every gate result below is evidence about this tree |
| Ending HEAD | `80ab1866ddb3043403ea3d679afccd049f1e3e98`. The commits after the candidate are documentation only and change no gate input, so under `docs/REQUIREMENTS_MATRIX.md` §5 the transcript carries forward rather than needing a re-run — which is why the candidate is named separately rather than every reference being rewritten to the latest HEAD |
| Published commit at the start | `72bc84c13f4e6914bfb015e87d46a5234e8f5234` — unchanged; **nothing was pushed** |
| Branch | `feat/phase-1-core` — unchanged |
| Diff | 30 files, +3857 / −223 |

**Commits, and what each is for.**

| Commit | Purpose |
| --- | --- |
| `bc5ad77` | The runtime verifier now relates the supplementary group to the password file's ownership. Phase 2 work-order item 9, carried forward from Phase 1 |
| `511e1f6` | ShellCheck SC2155 in the change above |
| `66199c8` | `scripts/workflow-policy-check.sh`: the workflow's security posture becomes a gate instead of a review |
| `3cc7c5e` | The pipefail/SIGPIPE gate caught FINDING-01's shape in the new checker on its first run |
| `0d620de` | The Pi-hole API contract is enforced at run time: a permitted-operation table, redirect-target enforcement, a total operation deadline, `Retry-After`, a session-nesting refusal, and credential scrubbing of peer-supplied strings |
| `ee09fff` | SW-P3-05: domain syntax, risk signal, evidence and blocking eligibility separated |
| `2a0af8f` | End-to-end CLI tests against a local fake HTTPS Pi-hole |
| `7e11419` | Four fuzz targets, and the two real defects their first runs found |

**Local suite on the final clean committed tree.** Run directly, as `scamwall`,
not through a wrapper, `tee`, a monitor or a background task, so the status is
the script's own:

```
$ bash ./scripts/check.sh; echo "CHECK exit=$?"
 24 passed, 0 failed, 2 BLOCKED, 0 optional-skipped
 RESULT: NOT COMPLETE — required gates failed or could not run.
CHECK exit=1
```

The gate list is now **26**, not 24: `workflow policy self-test` and `workflow
policy` were added. The two BLOCKED gates are the same two as before — `docker
build` and `container runtime verification` — blocked because this account has
no Docker socket, which is the intended boundary and not a defect. `CHECK
exit=1` is therefore the correct outcome, and the exit status agrees with the
printed verdict.

Supporting suites, each run directly:

| Suite | Result |
| --- | --- |
| `go test -race -count=1 ./...` | all 8 packages ok |
| `staticcheck ./...` | clean |
| `shellcheck --severity=style` over every tracked and untracked-but-not-ignored script | clean |
| `scripts/tests/runtime-verify-test.sh` | **355** tests, 0 failed (was 336; 19 added) |
| `scripts/tests/compose-fixture-test.sh` | **20** tests, 0 failed (was 19) |
| `scripts/workflow-policy-check.sh --self-test` | 14 self-tests, 0 failed |
| `scripts/secret-scan.sh --tree` | clean, 71 files |

**Bounded fuzz campaigns.** Durations are stated because a fuzz result is
meaningless without one. Each was run with an explicit `-fuzztime` and its
executions recorded:

| Target | Duration | Executions | Result |
| --- | --- | --- | --- |
| `internal/domain.FuzzAssess` | 180s | 1,406,144 | pass, after FINDING-34 |
| `internal/config.FuzzLoad` | 90s | 539,642 | pass, after FINDING-35 |
| `internal/feed.FuzzValidate` | 90s | 1,220,575 | pass |
| `internal/adapters/pihole.FuzzAuthResponse` | 120s | 22,983 | pass. Slower by three orders of magnitude because every execution is a real TLS request through the real client |

**This does not establish that these paths are free of defects.** It
establishes that none were found in the inputs these runs reached, which is a
much smaller claim. The one discovered failing input is preserved as a seed at
`internal/domain/testdata/fuzz/FuzzAssess/d05714e1c72a5771` and runs on every
ordinary `go test` from now on.

**What this session did NOT do**, stated so that a reader of the commit log
does not infer otherwise: nothing was pushed, no pull request was opened, no
branch protection was touched, `main` was not modified, no Docker command was
run, no `sudo` was used, the live Pi-hole was not contacted, and no production
secret, certificate, `.env` or deployment resource was read or changed. Every
network test in the tree talks to a server started by the test itself and
listening on the loopback interface.

### 3.15 Operator-handoff correction session

Work performed under an order to correct the `§6.5` operator handoff as one
focused patch, without expanding application scope, and **without executing
steps A–D or contacting the live Pi-hole**. Nothing here was run against a
Docker daemon, a network beyond loopback, or an appliance.

**Identity.**

| Item | Value |
| --- | --- |
| Starting HEAD | `6a737f39ade68f94e441809b58bde9816577a0ae` |
| Previous candidate | `7e1141997cc1f7484144f07c1fb05cde5d39e280` — the last commit that changed a gate input *before* this session |
| **Candidate** | `9ebb98c590fe96628c486d83b66a3b9c87608b85` — *feat(operator): make the handoff a tested program, not a paste-in block*. The last commit of this session that changes a gate input, and therefore the commit every gate result below is evidence about. It **supersedes** `7e11419` |
| Ending HEAD | the documentation commits after the candidate change no gate input, so under `docs/REQUIREMENTS_MATRIX.md` §5 the transcript carries forward rather than needing a re-run. The candidate is named separately for the same reason §3.14 names one: a SHA the recording commit would invalidate is not a usable identity, which is FINDING-38 in miniature |
| Published commit | `72bc84c13f4e6914bfb015e87d46a5234e8f5234` — unchanged; **nothing was pushed** |
| Branch | `feat/phase-1-core` — unchanged |

**Commits, and what each is for.**

| Commit | Purpose |
| --- | --- |
| `42477f1` | `doctor --no-credential`; the credential length removed from its report; `Client.Teardown` and truthful session-teardown reporting in `status` and `sync`; the Dockerfile's `--offline` claim corrected |
| `9c413d2` | The resource attribution and cleanup implementation extracted to `scripts/lib/docker-resources.sh` and shared. Behaviour-preserving; both programs refuse to start without it |
| `9ebb98c` | `scripts/operator-handoff.sh` and its 141-case suite; the new gate in `scripts/check.sh` |
| *(documentation)* | This section, §4.13, the §6.5 rewrite, the §6.1 supersession banner, and the matrix updates |

**Evidence renewal.** This session changes application code
(`cmd/scamwall/main.go`, `internal/adapters/pihole/client.go`) and gate inputs
(`scripts/check.sh`, `scripts/container-runtime-verify.sh`, a new
`scripts/lib/docker-resources.sh`, a new `scripts/operator-handoff.sh`, and
`container/Dockerfile`). Under `docs/REQUIREMENTS_MATRIX.md` §5 that demotes
every row resting on those inputs. **The passing CI run 34047025567 at
`72bc84c` is not relabelled as covering this tree**, and neither is the local
transcript at `7e11419`; both remain evidence about the commits they name. The
local suite was re-run here, and a hosted run is still owed.

**Local suite on the final clean committed tree.** Run directly, as `scamwall`,
not through a wrapper, `tee`, a monitor or a background task, so the status is
the script's own:

```
$ bash ./scripts/check.sh; echo "CHECK exit=$?"
 25 passed, 0 failed, 2 BLOCKED, 0 optional-skipped
 RESULT: NOT COMPLETE — required gates failed or could not run.
CHECK exit=1
```

The gate list grew by one — `operator-handoff regression tests`. The two
BLOCKED gates are the same two as always, `docker build` and `container runtime
verification`, blocked because this account has no Docker socket. That is the
intended boundary, not a defect, and `CHECK exit=1` is therefore the correct
outcome with the exit status agreeing with the printed verdict.

Supporting suites, each run directly:

| Suite | Result |
| --- | --- |
| `go test -race -count=1 ./...` | all 8 packages ok |
| `staticcheck ./...` | clean |
| `gofmt -l .` | clean |
| `shellcheck --severity=style` over every tracked and untracked-but-not-ignored script | clean |
| `scripts/tests/runtime-verify-test.sh` | **358** tests, 0 failed (was 355; 3 added for the library extraction) |
| `scripts/tests/operator-handoff-test.sh` | **141** tests, 0 failed (new) |
| `scripts/tests/compose-fixture-test.sh` | 20 tests, 0 failed |
| `scripts/tests/gate-diagnostics-test.sh` | passed |
| `scripts/secret-scan.sh --tree`, `scripts/independent-secret-scan.sh` | clean |

**What the new handoff suite actually drives.** `scripts/operator-handoff.sh`
runs against a scripted fake `docker` and a scripted fake `git`. The fake
Docker models container lifetime — a container exists once `create` returns its
id and stops existing when `rm` succeeds — and echoes back the ownership labels
the `create` call actually carried, so attribution, cleanup and idempotence are
real assertions rather than replayed output. The cases cover, at minimum: an
unexpected HEAD; a dirty tree; a `rev-parse` failure and a `status` failure,
separately; an exported fixture override, with its value asserted absent from
the output; a fixture path arriving through the *resolved* configuration rather
than the environment; a failed build with a stale tag still on it; a successful
build producing the same image ID; an in-build assertion step reported
`CACHED`; a build that succeeds and writes no log; a binary reporting the wrong
commit; a binary reporting enforcement as compiled in; a tag that moves after
the image was resolved; a credential-free probe whose container has a secret
mounted; a credential-free probe whose output reports reading the credential;
an offline secret probe with network access; a credential length in the output;
step D without authorisation; a failed session teardown; output that says
nothing about the teardown; a partially created container; a cleanup removal
failure; a resource that is not this invocation's; a pre-snapshot enumeration
failure; a `SIGTERM` mid-run; a failed leftover enumeration; and credential-,
session-id- and PEM-shaped values in a failing build's diagnostics.

**Two things this suite found that review had not.**

* The canned `docker compose config` fixture used the *object* rendering of
  `extra_hosts`. The cross-check case, which renders the real definition with
  the real Compose client (no daemon involved), showed the installed Compose
  emits an **array** of `"pi.hole=host-gateway"`. The program would have passed
  `pi.hole=host-gateway` to `--add-host`. Both renderings are handled now and
  the array form's `=` is normalised.
* The redaction case initially used `printf '-----BEGIN…'`, which `printf`
  reads as its own options, so the PEM never reached the capture and the
  "not printed" assertion passed for the wrong reason. Fixed to `printf '%s\n'`
  with a real 64-character body line.

**A limit of the diagnostics filter, recorded rather than papered over.**
`scripts/gate-diagnostics.sh` is line-oriented. A PEM's `-----BEGIN…` line has
its own rule and each 64-character body line is caught by the
long-opaque-value rule, which requires 40 characters. A PEM's short **final**
body line can fall under that threshold and survive. The filter is
deny-by-pattern, so this is one instance of its general limit rather than a new
kind of gap; it is stated here so the next reader does not infer a stronger
guarantee.

**What this session did NOT do**, stated so a reader of the commit log does not
infer otherwise: nothing was pushed, no pull request was opened, `main` was not
modified, no Docker command was run, no `sudo` was used, no image was built, no
container was created, the live Pi-hole was not contacted, and no production
secret, certificate, `.env` or deployment resource was read or changed. Steps
A, B, C and D of `§6.5` remain unexecuted.

---

### 3.16 Defect-review pass on the open rows

Work performed under an order to correct FINDING-47 without stopping for
permission, to inspect the reported diagnostics-filter gap and fix it if
sensitive content could escape, and to review the ten open rows of §7
individually — separating confirmed defects from missing evidence, documented
limitations, and claims needing correction, with an explicit instruction not to
file an implementation defect as "pending operator testing".

Three of the four defects found were inside rows already classified as
something else. **Nothing was pushed, no Docker daemon was contacted, and the
live Pi-hole was not touched.** Steps A–D of §6.5 remain unexecuted.

**Identity.**

| Item | Value |
| --- | --- |
| Starting HEAD | `a1b6b507c5f5a579b705ecec322e88fdc2a4d2b8` |
| Previous candidate | `9ebb98c590fe96628c486d83b66a3b9c87608b85` — the last commit that changed a gate input *before* this session |
| **Candidate** | `5af270d8ae36b1f60832f4edf26b71df2eee4945` — *fix(gates,operator): four defects the open rows were hiding*. The only commit of this session that changes a gate input, and therefore the commit every gate result below is evidence about. It **supersedes** `9ebb98c` |
| Ending HEAD | the documentation commit after the candidate changes no gate input, so under `docs/REQUIREMENTS_MATRIX.md` §5 the transcript carries forward. The candidate is named separately for the reason §3.14 and §3.15 name one — a SHA the recording commit would invalidate is not a usable identity, which is FINDING-38 |
| Published commit | `72bc84c13f4e6914bfb015e87d46a5234e8f5234` — unchanged; **nothing was pushed** |
| Branch | `feat/phase-1-core` — unchanged |

**Evidence renewal.** This session changes gate inputs — `scripts/check.sh`,
`scripts/gate-diagnostics.sh`, `scripts/operator-handoff.sh`, the tracked file
mode of `scripts/container-runtime-verify.sh`, and two test files, plus a new
`scripts/tests/entrypoint-mode-test.sh`. Under `docs/REQUIREMENTS_MATRIX.md` §5
that demotes every row resting on those inputs. It changes **no Go source**, so
the Go-path rows established at `9ebb98c` and `7e11419` are untouched. **The
passing CI run 34047025567 at `72bc84c` is not relabelled**, and neither is the
local transcript at `9ebb98c`; both remain evidence about the commits they name.
A hosted run is still owed, and is now owed for a 26-gate suite rather than a
25-gate one.

**Local suite on the final clean committed tree.** Run directly, as `scamwall`,
not through a wrapper, `tee`, a monitor or a background task, so the status is
the script's own:

```
$ bash ./scripts/check.sh; echo "CHECK exit=$?"
 26 passed, 0 failed, 2 BLOCKED, 0 optional-skipped
 RESULT: NOT COMPLETE — required gates failed or could not run.
CHECK exit=1
```

The gate list grew by one again — `entry-point file modes`. The two BLOCKED
gates are the same two as always, `docker build` and `container runtime
verification`, blocked because this account has no Docker socket. That is the
intended boundary, and `CHECK exit=1` is the correct outcome with the exit
status agreeing with the printed verdict.

Supporting suites, each run directly:

| Suite | Result | Change |
| --- | --- | --- |
| `go test -race -count=1 ./...` | all 8 packages ok | no Go source changed |
| `staticcheck ./...` | clean | — |
| `gofmt -l .` | clean | — |
| `shellcheck --severity=style` over 18 tracked and untracked-but-not-ignored scripts | clean | +1 file |
| `scripts/tests/runtime-verify-test.sh` | **358** tests, 0 failed | unchanged |
| `scripts/tests/operator-handoff-test.sh` | **167** tests, 0 failed | was 141; +26 for FINDING-49 and FINDING-50 |
| `scripts/tests/gate-diagnostics-test.sh` | **73** tests, 0 failed | +9 for FINDING-48 |
| `scripts/tests/entrypoint-mode-test.sh` | **58** tests, 0 failed | new, for FINDING-47. It reports 56 when its own file is untracked and 58 once tracked: it discovers its subjects from the git index, so it acquires two cases about itself. The tracked figure is the operative one |
| `scripts/gate-diagnostics.sh --self-test` | all passed | +1 for FINDING-48 |
| `scripts/secret-scan.sh` (staged), `scripts/independent-secret-scan.sh --staged` | clean; gitleaks 8.30.0 found nothing in history or in the staged tree | run before the commit |

**Repeat runs, and exactly what they are worth (row 10 of §7).** The
determinism row names a standard set at `0b083cb`: 30 consecutive runs. Five
rounds of all four shell suites were run here — 20 suite executions, one writer,
one log:

```
round=1..5  runtime-verify    rc=0  358 tests, 0 failed
round=1..5  operator-handoff  rc=0  167 tests, 0 failed
round=1..5  gate-diagnostics  rc=0   73 test(s), 0 failure(s)
round=1..5  entrypoint-mode   rc=0   58 test(s), 0 failure(s)
20 runs, 20 rc=0, 0 nonzero, case counts identical across every round
```

**Five is not thirty, and this does not close the row.** At five runs a
one-in-fifty defect is missed about ninety per cent of the time. What it
establishes is narrower and still worth recording: across five rounds the case
counts did not drift, no suite flaked, and the two suites that gained cases this
session are as stable as the two that did not.

A first attempt at this measurement was **discarded rather than reported**. Two
copies of the campaign were running against the same log, each truncating it at
start, so the file interleaved two runs and its contents could not be attributed
to either. The number it would have supported was larger than the one recorded
above. It is not used.

**A count that depends on the index.** `scripts/tests/entrypoint-mode-test.sh`
reports **56** cases when its own file is untracked and **58** once it is
committed. That is not a flake: it discovers its subjects from `git ls-files`,
so once tracked it acquires two cases about itself. The candidate's commit
message records 56, measured before the file was staged; 58 is the figure that
holds for the committed tree, and both are correct about the tree they describe.

**Every fix was shown to discriminate.** Each carries a PRE-FIX CONTROL inside
its suite, and each was additionally verified by reverting the fix in the
working tree and observing the suite fail:

| Fix reverted | Failures |
| --- | --- |
| The tracked file mode | **5**, including the `exit 126` direct-invocation case |
| `state_put` / `state_get` (FINDING-49) | **6** |
| The preflight baseline (FINDING-50) | **8** |

The FINDING-48 control is inside the suite rather than by reversion: the
superseded three-rule set is applied to the same fixture and asserted to leak
the short body line.

**The new mode gate caught a live regression while this session ran.** A `cp`
used to restore a backup during the reversion experiments dropped the execute
bit on `scripts/operator-handoff.sh`; the next run of
`scripts/tests/entrypoint-mode-test.sh` failed with `exit 126 — found but not
executable`. That is the defect class it was written for, occurring
independently, hours after the file was written.

**What the FINDING-48 reproduction used.** Synthetic material only —
`AAAAsynthetic…`, `ZZZZshortTailSynthetic03==` — assembled at run time. No
production secret, key, certificate or `.env` was read at any point, and
`keys/feed-signing.ed25519.key` was not touched.

**A limit of the new mode gate, recorded rather than left to be inferred.**
`scripts/check.sh` and `scripts/make-test-feed.sh` are *not* exec'd by it.
Neither parses arguments, so one would run the entire gate suite from inside the
gate suite and the other would rewrite `testdata/feed.json`. They are covered by
the tracked-mode and working-tree assertions only, which establish that the bit
is set and not that the kernel accepted it. That is weaker, and it is stated
here rather than papered over with a live invocation that has a side effect
hidden inside it.

**What this session did NOT do:** nothing was pushed, no pull request was
opened, `main` was not modified, no Docker command was run, no `sudo` was used,
no image was built, no container was created, the live Pi-hole was not
contacted, and no production secret, certificate, `.env` or deployment resource
was read or changed. Steps A, B, C and D of `§6.5` remain unexecuted.

---
### 3.17 Order-1 session — the operator safety foundation

> **STATUS: IMPLEMENTATION COMPLETE; ACCEPTANCE PENDING.**
>
> Every code change ORDER 1 asks for is written, tested and committed, and the
> local gate suite passes on the clean committed tree. That is **not** the
> order's acceptance criterion. ORDER 1 accepts when *"the existing Phase 1
> matrix is reconciled, and the handoff's security boundaries have supporting
> code, negative tests, **and applicable real-runtime evidence**"*.
>
> The first two are done. The third is outstanding and cannot be produced from
> this account:
>
> * **Operator evidence** — `§6.5` step A has not been run. No image has been
>   built from this source on any host, so SW-P1-05 and SW-P1-20 stay
>   IMPLEMENTED-UNVERIFIED.
> * **Hosted evidence** — this tree has never had a hosted run. The published
>   commit is `72bc84c` and its run executed 24 gates; this tree has 26.
>   SW-P1-12 stays IMPLEMENTED-UNVERIFIED.
>
> Do not read "the suite passes" as "the order is accepted". The suite passing
> is what makes the order's evidence *worth collecting*; it is not the evidence.

> **SUPERSEDED IN PART BY §3.18.** "Implementation complete" above was complete
> with respect to the ORDER 1 *items*. It was not complete with respect to the
> step lifecycle those items introduced: a review of the package produced from
> this session exercised the state functions directly and found three further
> defects in that lifecycle — a terminal record published in pieces, a
> prerequisite comparison that skipped whatever was absent, and no exclusion
> between concurrent invocations. They are FINDING-57, FINDING-58 and
> FINDING-59, fixed at `04e7ea4`. Read §3.18 and §4.16 with this section; the
> candidate named below is no longer the head of this line of work.

Work performed under **ORDER 1** of the consolidated phase orders, which
directs that five defects found by a review *of* `5af270d` be addressed, that
the step lifecycle be made explicit, and that step results be bound to the
identities they were produced against.

The five items map onto six findings, because the order also states separately
that an authorisation flag must not be relied on as proof that prerequisite
tests passed, and that is a distinct defect with a distinct fix:

| Order 1 item | Finding | Subject |
| --- | --- | --- |
| 1. Failed pre-start mount or network assertions must prevent `docker start` | **FINDING-51** | `scripts/operator-handoff.sh` |
| 2. Step completion persisted only after required checks and cleanup succeed | **FINDING-52** | `scripts/operator-handoff.sh` |
| (body) Do not rely on an authorisation flag as proof that prerequisites passed | **FINDING-53** | `scripts/operator-handoff.sh` |
| 3. Raw captures separated from sanitized shareable evidence | **FINDING-54** | `scripts/operator-handoff.sh` |
| 4. Closeout must examine the resource identities from the actual previous steps | **FINDING-55** | `scripts/operator-handoff.sh` |
| 5. Privileged work-directory and state handling | **FINDING-56** | `scripts/operator-handoff.sh` |

All six were found by reading the program, all six were reproduced **without a
Docker daemon**, and none of them needed one. §4.15 describes each.

#### Commit identity

| | |
| --- | --- |
| **Candidate** | `76f3bfd3ebc647ba21dd281fc2b5a3c48435b8d7` — *fix(operator): six defects the handoff was carrying, and an explicit step lifecycle* |
| Parent | `0cdec6c9d582337fe07867a7540fbc20a8007f5a` |
| Previous candidate | `5af270d8ae36b1f60832f4edf26b71df2eee4945` — superseded |
| Branch | `feat/phase-1-core`, ahead of `origin/feat/phase-1-core`; **not pushed** |
| Published commit | `72bc84c` — unchanged |
| Files changed | `scripts/operator-handoff.sh`, `scripts/tests/operator-handoff-test.sh` |

The candidate is the only commit of this session that changes a gate input. The
documentation commit that follows it changes none, so it does not invalidate the
gate results below — and it is what names `76f3bfd`, because a SHA cannot be
recorded by the commit that creates it (FINDING-38).

**No Go source, no Dockerfile, no Compose definition and no workflow changed by
this candidate.** §5 of the requirements matrix demotes the script-bound rows
again, and the suite was re-run on the clean committed tree to renew them.

**That says nothing about the Go-bound rows, and must not be read as if it
did.** "This patch changed no Go source" is a statement about
`0cdec6c…76f3bfd`. It is not a statement about the distance between this tree
and the tree any earlier evidence was produced against. Since `72bc84c` — the
commit whose hosted run closed SW-P1-20 — five commits have changed Go source
and `container/Dockerfile` changed with them, cumulatively **+3440 / −229
across 22 files**. SW-P1-20 and SW-P1-12 have been IMPLEMENTED-UNVERIFIED
continuously since `7e11419`, they remain so, and this candidate neither
renews nor further demotes them. The full reconciliation, including what the
old evidence still covers and what the current renewal requires, is in
`docs/REQUIREMENTS_MATRIX.md` §3 under *SW-P1-20 reconciled across the complete
history since `72bc84c`*.

#### Suites at the end of this session

| Suite | Result | Change |
| --- | --- | --- |
| `go test -race -count=1 ./...` | all 8 packages ok | no Go source changed this session |
| `staticcheck ./...` | clean | — |
| `gofmt -l .` | clean | — |
| `shellcheck --severity=style` over the tracked scripts | clean | — |
| `scripts/tests/runtime-verify-test.sh` | **358**, 0 failed | unchanged |
| `scripts/tests/operator-handoff-test.sh` | **308**, 0 failed | was 167; **+141** |
| `scripts/tests/gate-diagnostics-test.sh` | **73**, 0 failed | unchanged |
| `scripts/tests/entrypoint-mode-test.sh` | **58**, 0 failed | unchanged |
| `scripts/gate-diagnostics.sh --self-test` | all passed | unchanged |

#### Determinism, repeated for a suite that nearly doubled

Five rounds of all four shell suites — 20 executions:

```
round=1..5  runtime-verify    rc=0  358 tests, 0 failed
round=1..5  operator-handoff  rc=0  308 tests, 0 failed
round=1..5  gate-diagnostics  rc=0   73 test(s), 0 failure(s)
round=1..5  entrypoint-mode   rc=0   58 test(s), 0 failure(s)
20 runs, 20 rc=0, 0 nonzero, counts identical across every round
```

**Five is not thirty, and the row stays open.** At five runs a one-in-fifty
defect is missed about nine times in ten. What this establishes is narrower:
the counts did not drift, nothing flaked, and the suite that grew from 167 to
308 cases is as stable as the three that did not change.

#### The gate suite, run directly on the clean committed tree

Not through a wrapper, `tee`, a monitor or a background task, so the status is
the script's own.

```
$ git status --porcelain          # (no output — the tree is clean)
$ bash ./scripts/check.sh; echo "CHECK exit=$?"
 26 passed, 0 failed, 2 BLOCKED, 0 optional-skipped
 RESULT: NOT COMPLETE — required gates failed or could not run.
CHECK exit=1
```

Exit 1 is correct and agrees with the printed verdict. The two BLOCKED gates
are the privilege boundary, unchanged and not a defect:

```
BLOCKED  docker build (docker daemon not reachable by scamwall)
BLOCKED  container runtime verification (docker daemon not reachable by scamwall
         — run scripts/container-runtime-verify.sh as the operator)
```

The gate list is **unchanged at 26**: this session added no gate. It changed
what one of them — `operator-handoff regression tests` — asserts, and how much.

Run on the *working* tree before committing, the suite reported 25 passed and
one failure: the uncommitted-tree gate, which is the gate that fails until the
work is committed. That figure is not used; the committed-tree run above is the
operative one.

#### Every fix was shown to discriminate

Each fix was reverted in the working tree, on its own, and the suite re-run.
The counts are what the reverted program actually produced:

| Fix reverted | Failures |
| --- | --- |
| FINDING-51 — the start gate removed from `start_probe` | **8** |
| FINDING-52 — identities written immediately instead of staged | **5** |
| FINDING-52 — cleanup problems excluded from the verdict | **2** |
| FINDING-53 — step D's B and C prerequisites removed | **7** |
| FINDING-54 — evidence published unsanitized (`cat` for the filter) | **2** |
| FINDING-55 — closeout searching its own fresh project label again | **7** |
| FINDING-56 — the symlink checks neutered | **10** |
| FINDING-56 — the work directory's ownership check removed | **1** |
| FINDING-56 — the ancestor-writability check removed | **2** |
| FINDING-56 — the state file's symlink check removed | **1** |

**What a reversion count is and is not.** It establishes that the suite
distinguishes the fixed program from the unfixed one on that specific change.
It does not establish that the fix is complete, and a count of 1 is not weaker
evidence than a count of 10 — it means one case is written against that branch,
which for `assert_state_file_trusted`'s symlink rule is the number of cases the
branch needs.

#### What this session did NOT do

Nothing was pushed. No pull request was opened. `main` was not modified. No
Docker command reached a daemon — the account has no socket, and the suites
drive a scripted fake. No `sudo` was used, no image was built, no container was
created, the live Pi-hole was not contacted, and no production secret,
certificate, `.env` or deployment resource was read or changed. **Steps A, B, C
and D of §6.5 remain unexecuted**, and the fixes below change what those steps
will do when an operator runs them.


### 3.18 ORDER-1 review response — the state machine made consistent

> **STATUS: IMPLEMENTATION COMPLETE; ACCEPTANCE PENDING.** Unchanged from
> §3.17, and for the same reasons. This session did not produce operator or
> hosted evidence and could not. What it changes is that §3.17's
> "implementation complete" was **complete with respect to the ORDER 1 items**
> and not with respect to the state machine those items introduced: a review
> of the ORDER 1 package found three further defects in it. They are fixed
> here. SW-P1-05, SW-P1-12 and SW-P1-20 are untouched by this session and stay
> IMPLEMENTED-UNVERIFIED.

The ORDER 1 review package was returned for review. The reviewer did not read
the diff and agree with it — they **exercised the state functions from the
package** and interrupted one. That found three defects `§4.15` had not, all in
the step lifecycle `§4.15` introduced, and all of the same kind: a record that
is true of one moment being read as though it were true of another.

| Review item | Finding | Subject |
| --- | --- | --- |
| A terminal outcome, its bindings and its staged results must be one atomic replacement; an incomplete `passed` record must never exist | **FINDING-57** | `scripts/operator-handoff.sh` |
| Required bindings must be explicit per step, and missing, empty, malformed or unreadable ones must refuse dependent execution — not be skipped | **FINDING-58** | `scripts/operator-handoff.sh` |
| Concurrent invocations sharing a work directory must not race state updates, and the lock must not introduce a symlink hole | **FINDING-59** | `scripts/operator-handoff.sh` |
| *(found while re-running the gates; pre-existing, unrelated, not fixed here)* | **FINDING-60** | `cmd/scamwall/e2e_test.go` |

Rebuild invalidation was also named in the review as something to **preserve**,
not to change. It is preserved, and strengthened: the invalidation is now a
single replacement rather than eight, so a rebuild interrupted partway through
it cannot leave some downstream acceptances voided and others standing beside a
stale image pin. §4.16 describes each finding, the fix, and how it is tested.

#### Commit identity

| | |
| --- | --- |
| **Candidate** | `04e7ea4e8e85c39cf60d6786021ce3cc7562e904` — *fix(operator): publish a step's terminal record atomically, bind it explicitly, and serialise the work directory* |
| Parent | `5d9d21de11f6fe194e50e48bc0276541c398425b` |
| Previous candidate | `76f3bfd3ebc647ba21dd281fc2b5a3c48435b8d7` — the ORDER 1 fixes this review is *of* |
| Branch | `feat/phase-1-core`, ahead of `origin/feat/phase-1-core`; **not pushed** |
| Published commit | `72bc84c` — unchanged |
| Files changed | `scripts/operator-handoff.sh`, `scripts/tests/operator-handoff-test.sh` |

**No Go source, no Dockerfile, no Compose definition and no workflow changed by
this candidate.** §5 of the requirements matrix demotes the script-bound rows
again, and the suite was re-run on the clean committed tree to renew them. As
in §3.17, that says nothing about the Go-bound rows: SW-P1-20 and SW-P1-12 have
been IMPLEMENTED-UNVERIFIED continuously since `7e11419` and neither is renewed
or further demoted here.

#### What the fix actually changed, in one place

| Before | After |
| --- | --- |
| `state_put` and `state_clear` each rewrote and renamed the state file; a terminal record took five or more renames | One primitive, `state_apply`, takes a whole change set and installs it with **one** `rename(2)`. `state_put` is its one-change spelling; `state_clear` is gone, its callers now expressing removal as part of the set that carries their other changes |
| `record_step_outcome` wrote the status first, the bindings after | Status, bindings and staged results are one replacement. There is no moment at which the file says `passed` and does not say what against |
| `begin_step` set `running` and left the previous run's bindings in place | `running` and the removal of that step's own bindings, in one replacement |
| `invalidate_after_rebuild` performed up to eight separate writes | One replacement |
| Bindings were whatever a step happened to establish | A stated required set per step, enforced when a pass is published **and** when one is accepted |
| `assert_prereq_identities` compared only components both sides had | Every required component is compared; absence on either side is refused, and shape is checked wherever presence is |
| Nothing serialised two invocations in one work directory | An exclusive `flock` taken before the first read of the state file and held for the whole step |

#### Suites at the end of this session

| Suite | Result | Change |
| --- | --- | --- |
| `go test -race -count=1 ./...` | **see FINDING-60** | no Go source changed this session; one test in `cmd/scamwall` fails about 8% of runs on a pre-existing coincidence |
| `staticcheck ./...` | clean | — |
| `gofmt -l .` | clean | — |
| `shellcheck --severity=style` over the 18 tracked scripts | clean | — |
| `scripts/tests/runtime-verify-test.sh` | **358**, 0 failed | unchanged |
| `scripts/tests/operator-handoff-test.sh` | **393**, 0 failed | was 308; **+85** |
| `scripts/tests/gate-diagnostics-test.sh` | **73**, 0 failed | unchanged |
| `scripts/tests/entrypoint-mode-test.sh` | **58**, 0 failed | unchanged |
| `scripts/gate-diagnostics.sh --self-test` | all passed | unchanged |

#### Every fix was shown to discriminate

Each fix was reverted in the working tree, on its own, and the suite re-run.
The counts are what the reverted program actually produced:

| Fix reverted | Failures |
| --- | --- |
| FINDING-57 — the terminal record written as status-then-bindings again | **5** |
| FINDING-58 — required bindings compared only when both sides have them | **19** |
| FINDING-59 — the work-directory lock not taken | **7** |
| All three at once (the pre-fix script in full) | **33** |

The three targeted reversions sum to 31, not 33. The difference is the two
cases that cover `begin_step` clearing a step's own previous bindings — a
sub-fix of FINDING-57 that the targeted reversion of `record_step_outcome`
leaves in place and the whole-file reversion does not. It is named here rather
than reconciled away, because the arithmetic not adding up is the sort of thing
that hides a case counted twice.

A reversion count establishes that the suite distinguishes the fixed program
from the unfixed one on that specific change. It does not establish that the
fix is complete.

#### The gate suite, run directly on the clean committed tree

Not through a wrapper, `tee`, a monitor or a background task, so the status is
the script's own.

```
$ git status --porcelain          # (no output — the tree is clean at 04e7ea4)
$ bash ./scripts/check.sh; echo "CHECK exit=$?"
 25 passed, 1 failed, 2 BLOCKED, 0 optional-skipped
 RESULT: NOT COMPLETE — required gates failed or could not run.
CHECK exit=1
```

The gate list is **unchanged**: 28 items, the same 28 §3.17 ran — where the
"26" quoted is the non-blocked count. This session added no gate. The two
BLOCKED gates are the privilege boundary, unchanged and not a defect:

```
BLOCKED  docker build (docker daemon not reachable by scamwall)
BLOCKED  container runtime verification (docker daemon not reachable by scamwall
         — run scripts/container-runtime-verify.sh as the operator)
```

**The one failure is `go test -race ./...`, and it is FINDING-60** — a
pre-existing coincidence in `cmd/scamwall/e2e_test.go` that this session did
not introduce, in a file this session did not touch, and deliberately did not
fix. It fails about 8% of runs; it passed on the working-tree run taken earlier
the same day and failed on this one. `CHECK exit=1` is the correct outcome for
this tree as it stands, and it is **not** the "26 passed, 0 failed" of §3.17.
That difference is not a regression introduced here, and it is not being
presented as a pass.

Every gate this session's changes are inputs to passes: `shellcheck` over all
18 tracked scripts, `operator-handoff regression tests` at 393/0, the secret
scans, and the uncommitted-artifacts gate.


#### No repeat determinism campaign

The review directed that none be run, and none was. The four shell suites were
each run once on the committed tree. `scripts/tests/operator-handoff-test.sh`
was additionally run during development as the fix was assembled: the final
program produced **393 tests, 0 failed** on every run of it, and the one
intermediate run that did not — 392 tests, 1 failed — is what found the
`begin_step` sub-fix described in §4.16, and was of a program that no longer
exists. That is development, not a determinism campaign, and it is not offered
as one. The determinism row (SW-P1-14) is neither advanced nor damaged by this
session, and the five-round figure recorded in §3.17 stands as the last one
taken.

#### What this session did NOT do

Nothing was pushed. No pull request was opened. `main` was not modified. No
Docker command reached a daemon — the account has no socket, and the suites
drive a scripted fake. No `sudo` was used, no image was built, no container was
created, the live Pi-hole was not contacted, and no production secret,
certificate, `.env` or deployment resource was read or changed. **Steps A, B, C
and D of §6.5 remain unexecuted.** ORDER 2 was not started.


### 3.19 FINDING-60 fixed — the required Go gate made deterministic

> **STATUS: IMPLEMENTATION COMPLETE; ACCEPTANCE PENDING.** Unchanged from
> §3.17 and §3.18, and for the same reasons. This session produced no operator
> and no hosted evidence and could not. SW-P1-05, SW-P1-12 and SW-P1-20 are
> untouched and stay IMPLEMENTED-UNVERIFIED.

§3.18 recorded a gate run of `25 passed, 1 failed, 2 BLOCKED` and named the one
failure as FINDING-60, deferred because fixing it meant changing Go source. The
reviewer instructed the fix. It is made, and the gate suite now has **no
failing gate on this tree**.

The change is confined to `cmd/scamwall/e2e_test.go`. §4.16 carries the
reasoning, the two shapes the fix could have taken and why only one of them is
honest, the mutation evidence that the check still catches a real disclosure,
and what the whole episode says about SW-P1-14.

#### Commit identity

| | |
| --- | --- |
| **Candidate** | `ff2e7349ad49005d9ec889d9ee276e2b358a7660` — *fix(test): stop the credential-length check matching the test's own temp path* |
| Parent | `222e903a042dd07ffc69bd43bd685d2d2006fab6` |
| Previous candidate | `04e7ea4e8e85c39cf60d6786021ce3cc7562e904` — FINDING-57 … FINDING-59 |
| Branch | `feat/phase-1-core`, ahead of `origin/feat/phase-1-core`; **not pushed** |
| Published commit | `72bc84c` — unchanged |
| Files changed | `cmd/scamwall/e2e_test.go` |

**This changes Go source under `cmd/`, and §5 of the requirements matrix
applies.** It is a `_test.go` file. It is not compiled into any binary, so the
executable is byte-identical to the one at `222e903` and **no image-bound row
moves**: SW-P1-20's image half is untouched by it, as is SW-P1-05's. No row's
**Source** field lists `cmd/scamwall/e2e_test.go`, so the demotion the rule
produces is SW-P1-13 alone — renewed by the run below.

SW-P1-13's acceptance clause is *"All pass; no test deleted or weakened without
an explanation."* A test **was** modified, and the explanation is §4.16: the
haystack was narrowed and the property was not, demonstrated by mutating the
program to disclose the length with and without a unit and confirming the check
fires in both cases. The version that would have weakened it — matching
`"<n> bytes"`-shaped phrases instead of a bare integer — was considered and
rejected, and the mutation that discriminates between the two is recorded.

#### The flake, before and after

| | Runs | Failures | Rate |
| --- | --- | --- | --- |
| `TestDoctorNeverReportsTheCredentialLength` at `222e903` | 25 | 2 | ~8% |
| the same test at `ff2e734` | 60 | 0 | — |

Sixty clean runs is not proof of zero. At the measured 8% rate the probability
of sixty clean runs by chance is about 0.7%, which is what makes this evidence
rather than one lucky pass. The mechanism is also understood and removed rather
than merely unobserved, and that is the stronger half of the argument: the
collision was between a two-digit constant and a ten-digit random path
component, and the path component is no longer in the text being searched.

#### The gate suite, run directly on the clean committed tree

Not through a wrapper, `tee`, a monitor or a background task, so the status is
the script's own.

```
$ git status --porcelain          # (no output — the tree is clean at ff2e734)
$ bash ./scripts/check.sh; echo "CHECK exit=$?"
 26 passed, 0 failed, 2 BLOCKED, 0 optional-skipped
 RESULT: NOT COMPLETE — required gates failed or could not run.
CHECK exit=1
```

`CHECK exit=1` with **zero failures** is the correct outcome and agrees with
the printed verdict: the two BLOCKED gates are the privilege boundary, and a
BLOCKED required gate is not a pass.

```
BLOCKED  docker build (docker daemon not reachable by scamwall)
BLOCKED  container runtime verification (docker daemon not reachable by scamwall
         — run scripts/container-runtime-verify.sh as the operator)
```

That restores the `26 passed, 0 failed` of §3.17. The gate list is unchanged at
28 items; this session added no gate.

**One run of this suite was discarded rather than reported.** It was started on
a clean tree and the documentation for this section was edited while it ran, so
its `working tree has uncommitted changes` gate failed against a tree that was
clean when the run began. Every other gate in it passed, including `go test
-race ./...`. It is named here because a run whose result was produced by the
act of recording it is exactly the kind of thing that gets quietly rounded to a
pass, and the run above was taken afterwards with nothing touched from start to
finish.


#### No repeat determinism campaign

None was run, and the review's standing instruction against one has not been
revisited. The sixty runs above are of **one test function**, are the
measurement of a specific defect's removal, and are not offered as a
determinism campaign or as renewal of SW-P1-14. What they establish is bounded
by what was measured.

#### What this session did NOT do

Nothing was pushed. No pull request was opened. `main` was not modified. No
Docker command reached a daemon. No `sudo` was used, no image was built, no
container was created, the live Pi-hole was not contacted, and no production
secret, certificate, `.env` or deployment resource was read or changed. **Steps
A, B, C and D of §6.5 remain unexecuted.** ORDER 2 was not started. The
temporary mutations of `cmd/scamwall/main.go` used to test discrimination were
reverted in the working tree and never committed; `git status` was clean before
the gate run above.

### 3.20 ORDER 2, architecture half — the registry schema made enforceable

> **STATUS: ARCHITECTURE HALF IMPLEMENTED. CATALOG HALF BLOCKED. ORDER 2 NOT
> ACCEPTED.**
>
> ORDER 2 is *"validate the source catalog and architecture"*. The architecture
> is now enforced rather than described. **No source has been imported,
> researched, contacted or qualified**, no provider documentation has been
> read, nothing has been fetched, and the registry holds zero records. ORDER 1
> also remains unaccepted, so ORDER 2's dependent acceptance has not opened;
> what proceeded here is its independent work, which §3.2 of the implementation
> plan permits while an external blocker stands.

#### The blocker, stated first because it bounds everything else

`docs/SOURCE_REGISTRY.md` said the 85-entry catalog was *"present in the order
text"* and *"does not need re-supplying"*. That was true of the session holding
the order text. It is not true of this repository.

Searched: the tracked tree, untracked files, ignored files, and the full commit
history across all branches. The catalog is in none of them.

It was not reconstructed. Producing 85 provider names, licence terms and access
states from recollection would be the precise failure this registry exists to
prevent — a guess laundered into a record — and §3 of that document forbids it
in those words. The registry therefore ships **empty**, and `docs/SOURCE_REGISTRY.md`
§1 and §5 now record the catalog's absence as a blocker rather than repeating
the claim that it is available.

#### What was built

| | |
| --- | --- |
| **Candidate** | `6bb33bfe78374d41738416af78c76db131e6151d` — *feat(registry): enforce the source-registry schema instead of describing it* |
| Parent | `0da91d4f74d13c59cc0f6c74c8618c2e85422434` |
| Branch | `feat/phase-1-core`, ahead of `origin/feat/phase-1-core`; **not pushed** |
| Files | `internal/sourceregistry/registry.go`, `internal/sourceregistry/registry_test.go`, `docs/source-registry.json`, `docs/SOURCE_REGISTRY.md` |

`internal/sourceregistry` loads `docs/source-registry.json` and refuses a record
that breaks the rules the prose states. The full list of what it enforces, and
the longer list of what it cannot, is `docs/SOURCE_REGISTRY.md` §6. The two
points worth repeating here:

* **An absent field is refused even though `unknown` is accepted.** They are
  different claims, and a decoded Go struct cannot tell them apart — a missing
  string and a string present-and-empty are the same value. The parser
  therefore decodes twice, once to see which keys the file carries and once to
  read them. A refactor that decoded once would silently delete the
  distinction, so it has its own test saying why.
* **The validator checks that a claim is well-formed, never that it is true.**
  `commercial_use: permitted` is checked for membership of a vocabulary;
  whether the licence says so is a human reading a human document. This is
  sharpest for independence: §2 offers `aggregation_dependencies` as the thing
  that "stops three feeds being counted as three independent sources", and what
  the validator actually does is refuse a dependency on a record that does not
  exist. It cannot discover a shared upstream nobody recorded. Independence
  stays a research finding, not a computed property.

Two schema gaps surfaced by implementing the prose — §4.17 — and both are
recorded in the schema table itself so the reason a field exists travels with
the field.

#### Two decisions taken, and why

**No new gate in `scripts/check.sh`.** `go test -race ./...` is already a
required gate and it validates the shipped registry on every run. A gate that
runs the same Go test a second time makes the suite slower without making it
stricter. The registry is protected; the protection is just not given its own
line in the output.

**`docs/source-registry.json`, not `data/source-registry.json`.** The first
attempt put it in `data/`, which `.gitignore` excludes as runtime state — so
the file would have been silently absent from the repository, which is the
failure the ignore rule's own header warns about for a different reason. The
options were a narrow `!` exception in a deny-by-default block that exists for
credential safety, or a path that is not runtime state. The second is correct:
the registry is a document of record and belongs beside the prose defining it.

#### Discrimination

A record with five defects was put into the shipped registry and the gate
re-run. All five were reported in one pass, by path, and the tree was restored:

```
sources[0].aggregation_dependencies[0]: names "src-0002", which is not a
    source_id in this registry
sources[0].enabled: is true while commercial_use is "unknown"; a source is not
    enabled on a right that is prohibited or unknown
sources[0].verified_on: is 2027-01-01, which is in the future — documentation
    cannot have been read on a day that has not happened
sources[0] (src-0001) is enabled; no source has been qualified
sources[0] (src-0001) claims verified-available; no provider documentation has
    been read
```

The last two come from a test that exists only to pin the current state: the
shipped registry must enable nothing and claim no `verified-available`
disposition. When the catalog arrives and a source is genuinely qualified, that
test is the one that must be deliberately changed, which is the point of
writing it.

#### Suites

| Suite | Result | Change |
| --- | --- | --- |
| `go test -race -count=1 ./...` | all **9** packages ok | was 8; `internal/sourceregistry` is new, 80 cases |
| `staticcheck ./...` | clean | — |
| `gofmt -l .` | clean | — |
| `shellcheck --severity=style` over the 18 tracked scripts | clean | no script changed |
| `scripts/tests/operator-handoff-test.sh` | **393**, 0 failed | unchanged |
| `scripts/tests/runtime-verify-test.sh` | **358**, 0 failed | unchanged |
| `scripts/tests/gate-diagnostics-test.sh` | **73**, 0 failed | unchanged |
| `scripts/tests/entrypoint-mode-test.sh` | **58**, 0 failed | unchanged |

#### The gate suite, run directly on the clean committed tree

Not through a wrapper, `tee`, a monitor or a background task, so the status is
the script's own. Nothing was edited between the run starting and finishing —
`git status` was clean at both ends, which §3.19 records as a mistake worth not
repeating.

```
$ git status --porcelain          # (no output — the tree is clean at 6bb33bf)
$ bash ./scripts/check.sh; echo "CHECK exit=$?"
 26 passed, 0 failed, 2 BLOCKED, 0 optional-skipped
 RESULT: NOT COMPLETE — required gates failed or could not run.
CHECK exit=1
```

Zero failures. `CHECK exit=1` is correct and agrees with the printed verdict:
the two BLOCKED gates are the Docker privilege boundary, and a BLOCKED required
gate is not a pass. The gate list is unchanged at 28 items — this session added
no gate, deliberately.


#### What this session did NOT do

No provider was contacted. No provider documentation was read or fetched. No
account was created, no key requested, no commercial discussion begun. No feed,
API or dataset was fetched in whole or in part, and nothing was submitted to
any third party. Nothing was pushed, no pull request opened, `main` untouched.
No Docker command reached a daemon, no `sudo` was used, the live Pi-hole was
not contacted, and **steps A, B, C and D of §6.5 remain unexecuted**.

The registry enables nothing, and a test fails if it ever does without that
being a deliberate change.

### 3.21 ORDER 2 execution — registry authorization semantics, and the catalog still missing

> **STATUS: ORDER 2 NOT ACCEPTED. ORDER 1 NOT ACCEPTED.**
>
> ORDER 2 accepts when all 85 catalog entries have a disposition. **Zero do**,
> and none can until the catalog is re-supplied. The registry's safety model is
> complete and enforced; the data it exists to hold does not exist. No provider
> was contacted, no documentation fetched, nothing downloaded.

#### Baseline, recorded rather than assumed

| | |
| --- | --- |
| HEAD at session start | `17017ad2e36f7d8973434aad12b07630c74b7f89` — matches the previous report |
| Branch | `feat/phase-1-core`, clean working tree |
| `origin/feat/phase-1-core` | `72bc84c13f4e6914bfb015e87d46a5234e8f5234` (confirmed by `git ls-remote`, read-only) |
| `origin/main` and local `main` | `66aff2e862fbbfc02c9d353c5d972ab53c3c58e6` — in sync, untouched |
| Divergence from the last hosted-tested commit | **31 commits** ahead of `72bc84c` at session start; 45 files, +14781/−716 |

That divergence is the reason SW-P1-12 stays IMPLEMENTED-UNVERIFIED: the gate
list this tree runs is not the list any hosted run has executed, and no hosted
run has seen any of these 31 commits.

#### The catalog: searched again, and absent

Searched the tracked tree, untracked files, ignored files, every commit on
every branch, the stash, and dangling git objects; and outside the repository,
this session's scratch area and the usual drop locations. The 85-entry catalog
is in none of them.

Stated once, as ORDER 2 §2 directs, and not reconstructed. §4, §5 and §6 of the
order are blocked on it: no record can be researched, no first wave selected,
and no adapter contract written for sources that have not been chosen.

#### What was done

| | |
| --- | --- |
| **Candidate** | `e8f86834de2d9f696b37e8c4a9479d751bbe9c89` — *feat(registry): authorize per operation, cite the evidence, and check lineage and input strictly* |
| Parent | `17017ad2e36f7d8973434aad12b07630c74b7f89` |
| Files | `internal/sourceregistry/{registry,authorize,lineage,baseline,strictjson}.go`, two test files, `docs/SOURCE_REGISTRY.md`, `docs/source-registry.json` |

ORDER 2 §3's five items, each a defect in the registry as first written and
each recorded in §4.18: per-operation authorization (FINDING-63), evidence for
every rights assertion (FINDING-64), identifier retirement enforced across
versions (FINDING-65), lineage cycles and the independence rule (FINDING-66),
and strict input handling (FINDING-67).

The schema moved from 1 to 2. There is no migration burden because the registry
has never held a record, and a v1 file is refused outright rather than read
under v2 meanings — a v1 record says nothing about retrieval, storage,
enrichment or training, and reading one as though it did would authorise by
silence the exact operations the new model exists to gate.

**The acceptance criterion ORDER 2 §3 sets** — *"the registry cannot authorize
an operation whose required access or usage conditions are unknown or
unmet"* — is `Source.Authorizes`, and it is exercised in both directions:
`unknown` refuses, a `conditional` grant with an unassessed condition refuses,
one with an unsatisfied condition refuses, one with no conditions at all
refuses, and one with every condition satisfied allows. Without that last case
every other would pass against a validator that simply refused everything.

#### Suites

| Suite | Result | Change |
| --- | --- | --- |
| `go test -race -count=1 ./...` | all **9** packages ok | `internal/sourceregistry` now **105** cases, was 80 |
| `staticcheck ./...`, `gofmt -l .`, `go vet ./...` | clean | — |
| `shellcheck --severity=style`, 18 tracked scripts | clean | no script changed this session |
| `scripts/tests/operator-handoff-test.sh` | **393**, 0 failed | unchanged |
| `scripts/tests/runtime-verify-test.sh` | **358**, 0 failed | unchanged |
| `scripts/tests/gate-diagnostics-test.sh` | **73**, 0 failed | unchanged |
| `scripts/tests/entrypoint-mode-test.sh` | **58**, 0 failed | unchanged |

#### The gate suite, run directly on the clean committed tree

Nothing was edited between the run starting and finishing; `git status` was
clean at both ends.

```
$ git status --porcelain          # (no output — the tree is clean at e8f8683)
$ bash ./scripts/check.sh; echo "CHECK exit=$?"
 26 passed, 0 failed, 2 BLOCKED, 0 optional-skipped
 RESULT: NOT COMPLETE — required gates failed or could not run.
CHECK exit=1
```

Zero failures. `CHECK exit=1` is correct: the two BLOCKED gates are the Docker
privilege boundary, and a BLOCKED required gate is not a pass. The gate list is
unchanged at 28 items; this session added no gate, for the reason recorded in
§3.20.

**On determinism, precisely.** This is one run of the full suite on one tree.
The four shell suites were each run once; `go test -race` once. Nothing here
supports a claim that the suite is deterministic, and the SW-P1-14 gap recorded
in §3.19 — that its repeat counts never covered the Go gate — is unchanged and
unclosed by this session.

#### An error made and reverted, recorded because it touched history

Testing the identifier-retirement walk, two throwaway commits were made on
`feat/phase-1-core` to create a synthetic history, and `git reset --hard` was
then used to remove them. The reset also discarded tracked working-tree changes
that a `git stash` was holding; they were recovered from the stash and verified
intact, and HEAD returned to `17017ad` with the branch again 31 ahead of
origin. Nothing was lost and nothing was pushed.

The right approach, taken afterwards, was to make the walk testable without
git at all: `ValidateVersionChain` takes an ordered list of registry versions,
so the loop is exercised by unit tests on synthetic sequences and the git-backed
test only supplies real versions to it.

#### Also produced

`docs/EVALUATION_PROTOCOL.md` — ORDER 2 §7. A protocol written **before** any
evaluation data exists, which is the only order in which it is worth anything.
It fixes the comparison configuration, requires labels from outside the
candidate source set, specifies temporal and lineage leakage controls, measures
both additional malicious caught and additional legitimate wrongly proposed,
treats abstentions and unlabelled destinations as first-class reported
quantities, and defines how corrections and feed delay are measured.

**It proposes no numeric thresholds.** §8 of that document states the shape of
each threshold and its rationale and leaves the values blank, because filling
them in before the household has said what a false block costs it would be
inventing a requirement and then meeting it.

#### What this session did NOT do

No provider was contacted. No provider documentation was read or fetched. No
account created, no key requested, no purchase, no commercial discussion. No
feed, API or dataset fetched in whole or in part. No malware sample, message
corpus or bulk indicator dataset downloaded. Nothing submitted to any third
party. No household data collected. Nothing pushed, no pull request opened,
`main` untouched. No Docker command reached a daemon, no `sudo` was used, the
live Pi-hole was not contacted, and **steps A, B, C and D of §6.5 remain
unexecuted**. Enforcement remains not compiled in.

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

Neither of the last two belongs to Phase 1 as a code defect; each observation
here is registered against the row or phase that owns it so it is not lost. The
Phase 1 code defects found here have their own sections — FINDING-23 (§4.9) and
FINDING-24 … FINDING-26 (§4.10) and FINDING-27 … FINDING-28 (§4.11) — and all six
are now fixed.

**The CI job cannot pass on a hosted runner as configured (SW-P1-12) —
ADDRESSED at `aa49797`.** The observation was correct as far as it went, and it
is kept in its original form below because the fix should be readable against
what prompted it. Two of its clauses have since been settled by measurement
rather than by reading (§3.9), and its premise that the CA path has "no
environment override" is what `aa49797` changed. Its final sentence — that the
choice is the operator's — was overtaken: the choice was made under an
authorisation to fix the CI diagnostics and make CI self-contained, and the
reasoning is set out in §6.3 rather than assumed. What it did NOT establish, and
what is still not established, is the cause of the §3.8 failure.

> **The CI job cannot pass on a hosted runner as configured (SW-P1-12).**
`deploy/compose/compose.yaml` binds `/etc/scamwall/certs/pihole-ca.crt`, a
literal absolute path with no environment override, and a Compose secret
defaulting to `/etc/scamwall/secrets/pihole_app_password`. Neither exists on a
fresh `ubuntu-24.04` runner, so the runtime verification cannot get past
`compose create` there — while `docker compose config`, which the suite runs
first, exits 0 even when the secret path does not exist (tested directly). The
consequence is that SW-P1-12's acceptance criterion, "the hosted run exists and
passes", is expected not to be satisfiable by pushing the branch as it stands.
This was found by reading the workflow and the compose file against each other
before proposing the push, not by watching a run go red. The run has since
happened and failed at that gate (§3.8), which is consistent with this reading
but does not establish it: FINDING-23 (§4.9) keeps the verifier's own verdict
out of the log. The options are set out in §6.3 and the choice is the
operator's.

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

### 4.9 FINDING-23 — a failing gate's output is truncated from the wrong end

**Severity: medium. Found by the CI run in §3.8. FIXED at `ef40156`.**

`scripts/check.sh` captures each gate's output and, on failure, prints it:

```bash
    bad "$label"
    sed 's/^/         /' "$out" | head -25
```

`head -25` keeps the *first* twenty-five lines. For a gate that reports
progressively — checking prerequisites, then identity, then assertions, then
cleanup, then a verdict — the first twenty-five lines are the part that
succeeded, and the failure, the cleanup result and the verdict are all below the
cut. The longer and more thorough the gate, the more completely its diagnosis is
discarded.

This is not hypothetical. In §3.8 the `container runtime verification` gate
failed, and the run log contains exactly twenty-four lines of it: seven
prerequisite `PASS`es, the image-identity explanation, and three more `PASS`es.
Nothing in the visible output indicates any problem at all. The reason the gate
failed does not appear anywhere in the log.

**Why it matters more here than in a typical suite.** `container-runtime-
verify.sh` exists to distinguish *passed*, *failed* and *could not run*, and to
name what it could not clean up (SW-P1-16, SW-P1-03). Its verdict line and its
cleanup report are the last things it prints. A truncation that keeps the head
therefore removes precisely the output that requirement was written to produce —
and on a hosted runner, where the log is the only artifact, it removes it
permanently.

It also degrades quietly. Locally, with two container gates BLOCKED rather than
FAILED, the truncation never fired, so eleven gate runs across this session gave
no sign of it. It took a host where the gate could actually fail to expose it.

**Fixed at `ef40156`.** Reporting moved into `scripts/gate-diagnostics.sh`, a
separate program with its own `--self-test`, so "what a failing gate may print"
is one reviewable thing rather than a line inside a loop. It prints the failure
reason, the verdict and the cleanup result first and outside any length limit —
those are the lines the reader needs and they are always at the end — then the
complete capture inside a collapsible CI group. Where a limit does apply, the
truncation is stated, both ends are shown, and the omitted material is preserved
in a mode-600 file inside a mode-700 directory whose path is printed.

`require` now captures the command's status into a variable before anything else
runs, and reports it. The superseded form used it only as an `if` condition, so
a gate that exited 2 because a tool could not run read identically in the log to
one that exited 1 because a check failed.

**The fix carries an opposite risk, and that is the part worth reviewing.**
Printing *more* of a gate's output is a disclosure decision: a capture can quote
a mounted file, an API header, or an environment value, and a CI log is public.
Everything is therefore sanitized before it is printed, and a capture that
cannot be sanitized is **not printed at all** — an unreadable log costs a rerun;
a leaked credential cannot be taken back. The retained artifact holds the same
sanitized text, never the raw capture, because in CI that artifact is uploaded.

Reporting is invoked *after* the verdict is recorded and its own exit status is
never consulted, so neither a broken reporter nor a missing one can turn a red
gate green. Both are tested.

| Property required | Where it is proven |
| --- | --- |
| A failure below the first 25 lines stays visible | `gate-diagnostics-test.sh` case 1, plus three PRE-FIX CONTROLS asserting `head -25` hid the failure, the verdict and the cleanup result on the same fixture |
| The original nonzero status is preserved | case 2, for statuses 1, 2, 7 and 42; and a zero-exit gate stays a pass with no diagnosis printed |
| Cleanup failures stay visible and affect the verdict | case 4, including with the cleanup report pushed past the inline cap — an artifact is not a substitute for a verdict, so the verdict is still printed inline |
| Large output does not create a false pass | case 3: 5000 lines and a nonzero exit is a FAIL, 5000 lines and a zero exit is still a PASS |
| Decoys are not exposed | case 5: eleven credential shapes, checked in the log **and** in the retained artifact |
| Reporting cannot change a verdict | case 6: a reporter that exits 9, and a reporter that does not exist. In the missing case nothing is printed rather than falling back to the raw capture |
| No temporary file is left behind | case 7 |

62 cases, all passing (§3.0). End-to-end demonstration through `check.sh`
itself, including the CI grouping markers and the retained artifact, is §3.10.

**The same truncation existed inside the verifier and went with it.** Its two
Compose failures folded stderr onto one line and cut it at 200 characters.
Compose puts the useful part of a mount or secret error at the end of a
multi-line message, so that cut discarded precisely the sentence naming the path
it could not use — and those are the two places the §3.8 failure would most
likely have spoken from. Both now print the full sanitized capture through the
same filter, or nothing.

---

### 4.10 FINDING-24 … FINDING-26 — the deployment definition at `c3ae292`

Three defects found while making CI able to run the container gates. None was
found by the hosted run; all three were found by asking what the runner would
face and then checking, and all three are fixed at `aa49797`.

#### FINDING-24 — the prohibited-path rule exempted the secret source

**Severity: medium.**

The verifier rejects a mount whose source is `docker.sock`, `/etc/pihole`,
`/proc`, `/sys`, `/`, `/etc`, `/root` and so on. The expression inspected
`.services.<svc>.volumes` only. The application password is not declared there —
it is a Compose *secret*, under `.secrets` — so it was never examined.

That is the wrong one to miss. It is the only source in the definition that was
already redirectable by an environment variable (`SCAMWALL_SECRET_FILE`), which
makes it the easiest thing in the whole deployment to point somewhere it should
not go. `SCAMWALL_SECRET_FILE=/etc/pihole/setupVars.conf` would have been
mounted read-only at `/run/secrets/pihole_app_password` with every assertion
passing.

Fixed by examining both sources under one rule. The PRE-FIX CONTROL in
`runtime-verify-test.sh` applies the superseded expression to a fixture with the
password taken from `/etc/pihole` and asserts it reports nothing, so the new
case is not merely agreeing with the new code.

#### FINDING-25 — a missing bind source is materialised as an empty directory

**Severity: medium. This is a false pass, not an inconvenience.**

Docker's default for a bind mount whose source does not exist is to create a
*directory* at that path and mount it. The consequence for this deployment:
with no CA file and no password file on the host, `compose create` still
succeeds, and the container has four bind mounts, at the four approved
destinations, all read-only, with the four expected source paths. Every mount
assertion in SW-P1-19 passes. The container has an empty directory where its
trust anchor should be, and another where its credential should be.

Fixed twice, because the two halves catch different things:

* `bind.create_host_path: false` on all three binds in `compose.yaml`. Docker
  now refuses a missing source instead of inventing one.
* A host-side check in the verifier, before anything is created, that every
  approved mount resolves to an existing **regular file**. This catches what
  `create_host_path` cannot: a source that exists and *is* a directory, which
  mounts perfectly well.

It also names the offending path in the output, which is the difference between
a diagnosable red run and another one like §3.8.

#### FINDING-26 — the password file's exposure was configured, never checked

**Severity: low.**

`compose.yaml` documents that the password is delivered through a Compose secret
and that the container joins a supplementary group to read it. Nothing checked
the file's actual exposure on the host. A `0644` password file would have
satisfied every assertion.

Fixed by computing **reachability** rather than mode: the file's own
other-read bit, AND an other-execute bit on every directory above it. Mode alone
answers the wrong question in both directions — a `0644` file inside a `0750`
directory is not world-readable, and a `0640` file under a `0777` directory
still is not. A `stat` that fails is reported as undetermined, never as either
verdict.

This deliberately does **not** claim the container can read the file. The
verifier never starts a container, so that remains exactly where §7 has always
put it: not established.

---

### 4.11 FINDING-27 and FINDING-28 — found by the second hosted run

Both were found by the run in §3.11, and both are defects in this session's own
work rather than in the deployment. Recording them that way matters: the first
hosted run found a defect in the gate suite, and it would be easy to present
this second one as "CI is nearly green" instead of "the new gate was wrong".

#### FINDING-27 — an assertion read a property through a channel that does not carry it

**Severity: low as a security matter, high as a lesson. Fixed at the commit
carrying this document.**

`scripts/tests/compose-fixture-test.sh` asserted that every bind in the resolved
configuration carries `create_host_path: false`. It passed locally and failed in
CI, on a byte-identical definition:

```
FAIL no bind may have its source auto-created
       resolved: 'unset'
```

The cause is not the definition. `compose-go` tags `CreateHostPath` with
`omitempty`, and `false` is a `bool`'s zero value, so on those versions
`docker compose config` **omits the field entirely** and a `false` is
indistinguishable in the rendered output from an absent one. Compose v5.5.1
(this host) renders it; the version shipped with Docker 28.0.4 on
`ubuntu-24.04` does not.

Note what the earlier revision of this assertion did. It read
`.bind.create_host_path // true`, which jq resolves to `true` for a `false`
value — so it reported `true` for a definition that correctly said `false`. That
was found and fixed while writing the test. The corrected form then had the
*opposite* problem in a different environment. The property is genuinely awkward
to observe, and both mistakes came from assuming the rendered configuration is a
faithful mirror of the definition. It is a projection, and projections lose
things.

**Fixed by checking whichever channel carries the property, and saying which
was used.** Where the field is rendered, the rendered value is asserted. Where
it is omitted, the definition itself is read and one `create_host_path: false`
is required *per bind* — stricter than "one somewhere". The branch that this
host does not take is exercised anyway, against a resolved configuration with
the field stripped, because an unexercised branch is how the original defect
survived every local run. A negative control confirms a definition with the key
removed is rejected.

**The load-bearing check was never this one.** FINDING-25 is defended primarily
by the verifier's host-side rule that every approved mount source is an existing
regular file — which runs in both environments, needs no Compose cooperation,
and **passed on the runner** in §3.11. `create_host_path: false` is defence in
depth, and whether the runner's Compose honours it at create time is not
established: the fixtures existed, so nothing would have been auto-created
either way. That is stated rather than assumed.

**An attribution gap it exposed, and the real reason it took a diff to explain.**
`docker compose config` is a required gate, and the runtime verifier resolves
the deployment through Compose — yet **no Compose version was recorded by either
host**. §2.2 records the Docker CLI and not the thing that actually parsed the
definition. Two runs disagreed and neither log said what had parsed it. The
workflow now records `docker compose version`, and §2.2 carries it for this
host.

#### FINDING-28 — a passing container gate does not record what it passed against

**Severity: medium for evidence, none for security. Fixed at the commit carrying
this document.**

In §3.11 `container runtime verification` **passed** on the runner. That is the
result option A was built to obtain — and it cannot be used as evidence for
SW-P1-05 or SW-P1-20, because the log does not say which image it verified.

`check.sh` prints a gate's captured output only on failure, which is right for a
log's readability and wrong for exactly one gate: the container gates *build an
artifact* and verify it, and the artifact's identity is the evidence. A green
run therefore said which gates passed but not what they passed about. §6.1 has
required the image ID from the operator since it was written; CI was not held to
the same standard.

Fixed in the workflow rather than in `check.sh`: a step after the gate suite
records `docker image inspect -f '{{.Id}}' scamwall:local` alongside the source
commit. It runs `if: always()` — the ID is as interesting after a failure — and
cannot affect the job's conclusion.

**This does not by itself renew SW-P1-05 or SW-P1-20.** Those rows require a run
against a named image, and a future CI run will record one; whether CI evidence
*may* renew an image-bound row that §6.1 assigns to the operator is a separate
question, and this document does not answer it here. What the fix removes is the
situation where the question could not even be asked.

### 4.12 FINDING-29 … FINDING-37 — the implementation session at `7e11419`

Nine findings. Five are defects in shipped code, two are gaps in what evidence
existed rather than in behaviour, and two things that looked like findings were
defects in the tests that found them — recorded here because a reader who
cannot tell those apart cannot use this document.

#### FINDING-29 — the supplementary group was never related to the file it opens

*Severity: high (deployment correctness).* Carried forward from Phase 1 as
`§6.4` work-order item 9. `scripts/container-runtime-verify.sh` asserted that
`group_add` resolved to a single valid non-root gid, and asserted that the
password file was not world-reachable. It never asked whether that gid was the
gid that **owns** the file, or whether the group-read bit was set. A deployment
could therefore satisfy every assertion in the suite — all ninety of them —
while the container identity had no permission to read its own credential.

Fixed at `bc5ad77`. The verifier derives the container identity from the
resolved configuration (`user:`, refused unless it is a numeric `uid:gid`) and
judges from host metadata whether the ordinary UNIX permission check would
grant that identity a read, through the owner class or the group class. Three
assumptions between the metadata and the outcome are checked rather than
assumed: an ACL mask that strips read from the group class, user-namespace
remapping, and rootless Docker. Each produces a failure or an UNDETERMINED
verdict; none produces a pass. Path traversal is deliberately not re-checked —
the daemon resolves the bind source as root, so ancestor modes gate the host,
not the container.

**This is metadata, and the output says so.** It states that the permission
check would grant a read. It does not state that a read was performed; no
container is started. The actual read remains `§6.4` work-order item 5.

*Discrimination.* Seven new regression cases, including a PRE-FIX CONTROL that
asserts both superseded assertions still report PASS in the very world the new
one rejects — the group is a valid non-root gid, and the file is not
world-readable, and the container still cannot read it.

#### FINDING-30 — the workflow's security posture was carried by review alone

*Severity: medium (evidence).* Not a vulnerability: every property held. The
gap was that nothing would have noticed if one stopped holding. The trigger
being `pull_request` rather than `pull_request_target`, the read-only
`permissions` blocks, the SHA-pinned actions, `persist-credentials: false`, the
absence of any secret reference — all of it rested on §3.4, a human reading the
file. Each is a one-line edit away from being lost and none would have failed a
test.

Fixed at `66199c8`: `scripts/workflow-policy-check.sh`, wired into
`scripts/check.sh` as two gates. It also checks a property review had not
covered — that no attacker-chosen context (`github.event.pull_request.*`,
`github.head_ref`) is interpolated into a `run:` block, where `${{ }}` is
expanded before the shell sees it.

**What it does not close.** It is lexical: it establishes what the workflow
*says*. That GitHub withholds secrets and issues a read-only token to a fork
pull request is a fact about GitHub, and observing it needs a run from a fork.
`§6.4` item 10 is unchanged.

#### FINDING-31 — a same-origin redirect could reach a forbidden endpoint

*Severity: high.* `CheckRedirect` refused cross-origin redirects and capped the
count. It said nothing about the target **path**. A Pi-hole answering
`GET /api/info/version` with a `302` to a configuration or DNS-control endpoint
would have been followed, within the approved origin, to an endpoint the
contract forbids — and the client would have sent its session id there.

A second defect in the same place: the redirect target's query string was not
examined. Pi-hole accepts the session id as a `sid` query parameter, and a
redirect is the only way a URL this client did not build could acquire one.
Every log that records a URL would then have held a live credential.

Fixed at `0d620de`. The permitted-operation table is enforced in
`CheckRedirect` as well as in `do`, and any redirect target carrying a query
string is refused outright.

#### FINDING-32 — `TotalTimeout` did not bound a retried operation

*Severity: medium.* `http.Client.Timeout` bounds one request. `do` gave each
attempt a fresh `RequestTimeout` context, so the real ceiling for a retried
read was `attempts × RequestTimeout` plus every backoff — growing with
`MaxRetries`, and unrelated to the number the configuration calls the total.
Fixed at `0d620de` by deriving one operation-level deadline in `do`.

#### FINDING-33 — `Retry-After` overflowed into no delay at all

*Severity: low.* Found by the overflow case in a table-driven test, before the
fuzzer reached it. `time.Duration` is an int64 of nanoseconds, so
`time.Duration(secs) * time.Second` with a large delta-seconds value overflows
to a **negative** duration, which then sails past a `> maxRetryDelay` test and
is used as the wait. A peer answering `429` with `Retry-After:
9223372036854775807` would have removed the backoff rather than extended it.
The clamp now happens before the multiplication.

#### FINDING-34 — `domain.Assess` was not idempotent

*Severity: high.* Found by `FuzzAssess` within a second of the target existing,
on the input `"0.\xd00"`. The input is not valid UTF-8; the IDNA mapper
replaces the bad byte with U+FFFD and encodes **that**, producing an ACE label
that the same profile then refuses on the way back in. The canonical form was
not canonicalisable.

That is not cosmetic. Feed deduplication, the conflicting-record check, and the
plan digest all rest on the premise that two spellings of one name converge on
one canonical form. Fixed at `7e11419` in two layers: invalid UTF-8 is rejected
before anything else looks at the bytes — a domain arriving in a JSON feed is a
UTF-8 string by definition — and the round trip is then asserted in the code
rather than assumed, so a future change in the IDNA tables cannot reintroduce
the defect silently.

#### FINDING-35 — `config.Load` returned a populated `Config` alongside an error

*Severity: medium.* Found by `FuzzLoad`. On a validation failure `Load`
returned the decoded configuration together with the error. Every caller in the
tree checks the error, so nothing was broken today — but a caller that logged
it and carried on would have been acting on settings that failed their own
checks, with the credential still on disk and the network still available.
`Load` now fails closed with the zero `Config`, which has no host and no paths
and cannot authenticate to anything.

#### FINDING-36 — `WithSession` could nest and leak a session seat

*Severity: medium.* A second `Login` overwrote the session id held in memory.
The overwritten session stayed valid on the server for the remainder of its
lifetime, occupying one of a finite number of seats, with no way left to
destroy it. Refused at `0d620de` with `ErrSessionAlreadyActive`.

#### FINDING-37 — a peer echoing a credential back would put it into an error

*Severity: medium.* The peer already knows the password; we sent it. The risk
is the peer putting it into a message ScamWall then writes to a log or a
diagnostic capture, without any code here having printed it. `APIError.Message`
carried Pi-hole's own words verbatim, sanitised for control characters and
length but not for content.

Fixed at `0d620de` with `config.Secret.Scrub`, applied to the live session id on
every endpoint and to the password on the authentication error specifically. It
is deliberately not `Reveal`: `Reveal`'s call sites are counted by a test and
are the moment a credential goes on the wire; scrubbing is the opposite
operation and must not compete for that budget.

#### Two things that were NOT findings

Both were reported by a test as a defect in the code and were defects in the
test. They are written down because the alternative is a reader who sees them
in a transcript and cannot tell.

* **"status 120 was interpreted as a successful authorisation."** It was not.
  `net/http`'s *server* treats a 1xx passed to `WriteHeader` as an
  informational block and then sends its own `200` as the final status, so the
  client correctly saw a `200` while the test believed it had sent a `120`.
  `FuzzAuthResponse` now fuzzes final statuses only, and says why.
* **"fuzzing process hung or terminated unexpectedly"** at roughly 17,000
  executions. The target was constructing a fresh client, and hence a fresh
  never-closed `http.Transport`, on every iteration, and exhausted the
  process's file descriptors. One client for the campaign.

---

### 4.13 FINDING-38 … FINDING-46 — the operator handoff at `6a737f3`

Nine defects in the `§6.5` procedure, and in the code two of its steps depend
on. Every one of them was in a block an operator was expected to paste into a
root shell and run against the household Pi-hole. None would have been caught
by any gate, because nothing executed the block.

#### FINDING-38 — the procedure refused the checkout it documented

Step 0 hardcoded `CANDIDATE=7e1141997cc1f7484144f07c1fb05cde5d39e280` and
refused unless `HEAD` equalled it. The commits that wrote and revised that
block are themselves in the tree the SHA names, so recording the value changed
the object it claimed to be. At `6a737f3` — the commit the handoff was written
for — the preamble would have printed `REFUSING: HEAD is 6a737f3…, expected
7e11419…` and stopped.

The near-miss fix is worse than the defect: reading the expected commit from
`HEAD` makes the check tautological, and `git reset`ting to satisfy it destroys
the operator's work. **Fixed** by taking the expected commit as an argument
(`--expected-commit`), validating its form, requiring `HEAD` to equal it,
refusing otherwise, and never moving the tree. Four identities — expected
checkout, actual checkout, the commit embedded in the artifact, and the commits
earlier evidence covers — are now named separately, because collapsing them is
what produced this.

#### FINDING-39 — the build passed no metadata, so the image named no source

The build command was `docker build --no-cache --pull -f … -t scamwall:local .`
with no `--build-arg`. The Dockerfile defaults `VERSION`, `COMMIT` and
`BUILD_DATE` to `dev`/`unknown`/`unknown` and stamps them into the binary with
`-ldflags -X`. The image produced by the SW-P1-05 renewal would therefore have
reported `commit unknown`, and could not have been tied to a source at all —
in a procedure whose stated purpose is binding results to exact identities.

**Fixed:** all three are passed explicitly, `COMMIT` is the validated expected
checkout, and the built binary is then **run** and required to report that
commit back. The builder's account of the build and the artifact's own account
are now both required to agree.

#### FINDING-40 — two false claims about the build cache, and one false assertion about image identity

The procedure asserted `[ "$IMAGE_ID" != "$PRIOR_IMAGE" ]`, refusing with "the
build did not replace it" when the two matched. An image ID is the digest of
the image's content: identical inputs produce an identical ID, and this turned
reproducibility into a failure.

Its comment also claimed "a layer cached from an earlier candidate would
produce an image that is not this source". The build cache is keyed on the
build context, so cache reuse means the inputs *were* identical.

**Fixed:** the differ-from-prior assertion is removed and an unchanged ID is
explained rather than refused. `--no-cache` is retained for the reason that is
actually true — the two in-build assertions are `RUN` steps, and a cached `RUN`
step does not execute, so it produces no evidence for this collection — and the
text now says that it is not a substitute for source identity or for a
successful build, both of which are checked separately.

#### FINDING-41 — the build's exit status was read through `tee`, and the capture was never checked

`docker build … | tee "$WORK/build.log"` with `BUILD_RC="${PIPESTATUS[0]}"`
recovers the status, but the same procedure's own preamble table said "A status
read through `tee`, a pipeline or a monitor is the wrapper's, not the
command's. FINDING-23 began as exactly this kind of substitution." It had
reintroduced the shape it warned against. Nothing checked that anything reached
the log, so a build that succeeded with an unwritable capture and a build that
succeeded normally were indistinguishable.

The in-build assertion parser also depended on BuildKit's plain step output
while the build ran with the default progress renderer, which rewrites lines in
place.

**Fixed:** the command's status is read from the command, the capture's
usability is a separate reported result, and `--progress=plain` is passed
because the output is parsed.

#### FINDING-42 — step B claimed to read no password, and its own expected output showed it reading one

Step B stated "**No password is read and none is transmitted**", then listed in
its expected-output table `ok application password readable, N bytes`. Both
could not be true. `cmdDoctor` called `config.LoadSecretFile` unconditionally,
before any connectivity check, so there was no way to run `doctor` without
opening `/run/secrets/pihole_app_password`.

The step also used `docker compose run`, which mounts the Compose secret, so
the container had the credential available regardless of what the command did
with it.

**Fixed** in three places: `doctor --no-credential` skips the read and reports
the check as `SKIP` rather than as a pass; step B creates its container with no
secret mount at all and asserts the absence of `/run/secrets/pihole_app_password`
on the created container *before starting it*; and step C became a separate
operation instead of a `grep` over step B's log.
`TestDoctorNoCredentialDoesNotOpenTheSecret` carries a control that fails the
same configuration without the flag, and `TestDoctorOfflineStillReadsTheSecret`
records that `--offline` is not the credential-free flag the Dockerfile comment
claimed it was.

#### FINDING-43 — `--offline` was treated as an isolation boundary

Step C's justification was "`--offline` skips every connectivity check, so this
reads the credential and touches no network." That is a claim about what the
program chooses to do, offered as a guarantee about what the container *can*
do. A defect, a different code path, or a future flag change all defeat it.

**Fixed:** step C runs with `--network none` and asserts the created
container's network mode before starting it. `--offline` is still passed; it is
no longer what the isolation rests on.

#### FINDING-44 — steps B, C and D ran whatever `scamwall:local` pointed at

Step A resolved the tag to an immutable image ID and then verified *that*. B, C
and D used `docker compose run`, and `compose.yaml` names the mutable tag. Any
rebuild, retag or concurrent build between A and D would have been executed
without notice, and the evidence would still have cited A's image ID.

**Fixed:** the resolved image ID is recorded in the work directory and every
later container is created from it explicitly; the created container's
`.Image` is compared to it before the container starts; the tag is re-resolved
at the end of step A and a movement fails the step; and the runtime verifier is
invoked with `SCAMWALL_EXPECTED_IMAGE_ID` so it refuses a substitution too.

#### FINDING-45 — cleanup was `compose down --remove-orphans` on a project name

Steps B, C and D each ended with `docker compose -p "$PROBE_PROJECT" … down
--remove-orphans`, then printed `probe project removed: $PROBE_PROJECT`
unconditionally — whether or not the command had succeeded. `down` deletes by
project **name**; `--remove-orphans` widens that to anything Compose considers
stray under the name. This is the same class of defect the runtime verifier had
already been corrected for, and the corrected implementation was sitting in the
next file.

The leftover check that followed it also treated an unaskable question as an
answered one: `docker ps -a --filter name=…` printing nothing means either "no
leftovers" or "the query failed".

**Fixed** by reusing the reviewed implementation rather than writing a second
one. `scripts/lib/docker-resources.sh` is now shared between the verifier and
the handoff: unpredictable invocation identifiers, per-invocation ownership
labels, a pre-existing-resource snapshot that treats a label collision as a
refusal, deletion only by exact ID after re-verifying ownership, preservation
of anything not attributable, idempotent cleanup installed *before* any
resource is created and reached on EXIT/INT/TERM, cleanup failure counted in
the verdict, and enumeration failure distinguished from an empty result
everywhere. The verifier's own 358-case suite was re-run over the extraction.

#### FINDING-46 — `status` printed "session closed" on a path where the logout had failed

`WithSession` performs the logout in a deferred call and deliberately does not
let a logout failure mask the caller's error. So a run whose `DELETE /api/auth`
failed still returned `nil` from `WithSession`, and `cmdStatus` printed
`session closed` and exited 0. The failure existed only as a
`pihole.logout_incomplete` warning in the audit stream.

The procedure then compounded it: it instructed the operator to treat
`status.log` ending with `session closed` as confirmation of cleanup, and to
confirm independently in the Pi-hole web interface under *Settings → All
settings → Web interface / API* by looking for a session attributed to the
ScamWall user agent — a menu path and an attribution behaviour this repository
has never verified for any Pi-hole version, and cannot verify without
contacting an appliance.

It also described `status` as "exactly three requests". `GET /api/info/version`
is in the permitted set as **retryable**, so with the shipped `max_retries: 2`
and up to two same-origin redirects per request the real worst case is fifteen
HTTP requests. The bound that is true is the permitted set, not a count.

**Fixed:** `Client` records a `Teardown` outcome — not attempted, accepted,
already absent, or failed — and `status` and `sync` report which of them they
observed, exiting nonzero on a failed teardown.
`TestAFailedLogoutIsNotReportedAsSuccess` and
`TestALogoutAnswered404IsTheDesiredEndState` cover the outcomes, and
`TestStatusIsNotLimitedToThreeRequests` pins the retry behaviour by making the
fake answer 503 twice. `ACCEPTED` is printed with the qualification that it is
a fact about a request; the UI instruction is replaced by a statement that
independent confirmation is unavailable from here, has not been verified
elsewhere, and must be recorded as *"request accepted, not independently
confirmed"* if the appliance's version offers no supported method.

#### Three smaller corrections made in the same pass

* The preamble hashed the production password with `sha256sum` in **every**
  case, to compare it at the end. Hashing a credential is not needed to show
  that some other step was credential-free. It is now opt-in
  (`--verify-secret-integrity`), states that it reads the credential, checks
  `sha256sum`'s status before parsing its output, validates the digest length,
  never prints the digest, and is nonzero on any read or comparison failure.
  The default compares owner, group, mode, size and mtime, and says explicitly
  that this does not prove the content is unchanged.
* Step Z ended with `rm -rf -- "$WORK"`, destroying a failing run's diagnosis
  before the operator could return it. Logs are now retained, and the path and
  the removal command are printed.
* Step B cited "§4 of `docs/PIHOLE_API_CONTRACT.md`" for `GET /api/auth`
  requiring no credential. It is §3.4; §4 is the read-only endpoint set.
  `doctor`'s `application password` line also reported a byte count, which
  diagnosed nothing — `LoadSecretFile` already refuses an empty credential —
  and is removed.

---

### 4.14 FINDING-47 … FINDING-50 — the defect-review pass at `a1b6b50`

Four defects, found by reviewing the ten open rows of §7 one at a time instead
of carrying them forward as a block. Three of them were sitting *inside* rows
this record had already classified as "pending operator execution" or "a
documented limitation". They were neither. A defect that a test can reach
without a daemon is a defect, and filing it under work that needs an appliance
is how it stops being looked at.

All four are fixed here, each with a regression case and each with a PRE-FIX
CONTROL that reproduces the defect and asserts the superseded code exhibits it.

#### FINDING-47 — the runtime verifier lost its executable bit, and no gate could see it

`9c413d2` changed `scripts/container-runtime-verify.sh` from tracked mode
`100755` to `100644` while extracting the resource-tracking block out of it.
Three commits passed before anyone looked.

Nothing caught it because **every tested path invokes these scripts as an
argument to `bash`** — `bash ./scripts/container-runtime-verify.sh` in
`scripts/check.sh`, `bash "$VERIFIER"` in `scripts/operator-handoff.sh` — and
`bash` does not consult the execute bit of a file it is told to read. The
documented invocations are the direct form, and the kernel refuses those with
`EACCES`:

```
$ ./scripts/container-runtime-verify.sh
/bin/bash: ./scripts/container-runtime-verify.sh: Permission denied
```

Three documented invocations were broken: `CONTRIBUTING.md` line 155, the
verifier's own usage header at line 53, and the command
`scripts/container-security-check.sh` prints when it redirects the operator to
it. The gate suite stayed green throughout, and **the first person to find out
would have been the operator, at §6.5 step A** — the machine where a failure
costs the most, which is the precise outcome the handoff rewrite exists to
prevent.

**Fixed:** the mode is restored in the index, not only in the working tree
(`git update-index --chmod=+x`), because a local `chmod` leaves every fresh
clone broken while making this checkout look correct.
`scripts/lib/docker-resources.sh` stays `100644`: it is sourced, and marking it
executable would invite it being run.

**Regression:** `scripts/tests/entrypoint-mode-test.sh`, 56 cases, wired into
`scripts/check.sh` as `entry-point file modes`. It asserts the **tracked** mode
of every shell program under `scripts/`, that the working tree agrees with the
index, that everything under `scripts/lib/` is non-executable, that every
`./scripts/…` or `sudo scripts/…` form appearing in the documentation names a
tracked-executable file — reading the invocation *form*, because the form is the
whole defect — and it then **execs** each entry point that has a
side-effect-free help path, asserting against exit 126 specifically. Docker,
Compose and `go` are shimmed to record and fail during those invocations, so
"no daemon was contacted" is asserted rather than assumed. `check.sh` and
`make-test-feed.sh` are deliberately not exec'd: neither parses arguments, so
one would run the entire gate suite from inside itself and the other would
rewrite `testdata/feed.json`. They keep the mode assertions, which is weaker,
and this says so rather than hiding a side effect inside a mode test.

The suite discriminates: reverting the mode produces **5 failures**, including
the `exit 126` case. It also caught a real regression during this session — a
`cp` used to restore a backup dropped the bit again, and the suite failed on the
next run.

#### FINDING-48 — a PEM's short final body line was printed in full

§7 recorded this as a *limitation*: "the filter is line-oriented, and a PEM's
short final body line can fall under the 40-character threshold the
long-opaque-value rule uses." That description was accurate and the
classification was wrong. It is a **leak**, and it was reachable through the
real reporting path.

`scripts/gate-diagnostics.sh` gave the `-----BEGIN` and `-----END` markers a
rule each and left the body between them to the long-opaque-value rule, which
requires 40 characters. A PEM body wraps at 64, so every line but the last is
caught — and the last is the remainder, routinely shorter than 40. Reproduced
against `--report`, with synthetic material only:

```
$ gate-diagnostics.sh --report 'pem repro' 1 pem-repro.log
         --- full output (8 line(s), sanitized) ---
         PASS    check 1
         <redacted: PEM block>
         <redacted: long opaque value>
         <redacted: long opaque value>
         ZZZZshortTailSynthetic03==          <-- 26 characters, printed in full
```

**Fixed** with the filter's one stateful rule: between a BEGIN marker and its
END marker, any line that is nothing but base64 is redacted whatever its length.
The markers contain `-`, so they never match the body pattern and their own
rules still apply. Two consequences are deliberate and are documented at the
rule: an unterminated block — a capture cut off mid-key — leaves the range open
to end of input, which is the fail-closed direction; and it costs nothing that
matters, because every line the digest must always show (`FAIL`, `BLOCKED`,
`RESULT:`, the counts) contains spaces or punctuation and cannot match a
pure-base64 line. That is asserted, not assumed.

**Regression:** four cases in `scripts/tests/gate-diagnostics-test.sh` plus one
in the reporter's own `--self-test`. The existing decoy carried a single
64-character body line, so it had been passing while saying nothing about the
last line; it now carries a short tail. The PRE-FIX CONTROL applies the
superseded three-rule set to the same fixture and asserts it leaks.

**What this does not establish.** The filter is still deny-by-pattern. It
establishes what its patterns catch, and a credential of an unanticipated shape
would pass through it. That is the residual limitation, and it is a real one —
but it is no longer a stand-in for a known leak.

#### FINDING-49 — a re-run of step A left every later step pinned to the previous build

Filed under "the handoff behaves correctly against a real Docker daemon", which
is a row about missing runtime evidence. This needed no daemon.

`state_put` **appended** to the work directory's state file and `state_get`
returned the **first** match. A second `build` into the same work directory —
after a failed first attempt, or a corrected one, which is the ordinary way a
procedure gets re-run — appended a new `IMAGE_ID` that nothing ever read. Steps
B, C and D went on creating their containers from the **previous** build's
image while step A's report named the new one.

Worse, each of those steps still passed its own `.Image` comparison, because it
compared against the same stale value it had been created from. The pin
introduced by FINDING-44 was intact and pointing at the wrong artifact. It is
FINDING-44's defect — a result bound to one identity while the operation was
performed on another — arriving by a different route.

Reproduced with the two implementations in isolation:

```
IMAGE_ID=sha256:AAAAfirstbuild
IMAGE_ID=sha256:BBBBsecondbuild
state_require IMAGE_ID -> sha256:AAAAfirstbuild
```

**Fixed:** `state_put` now replaces any existing record of the key — rewriting
through a temporary file in the mode-700 work directory and renaming it into
place — and announces a replacement whose value differs, so a re-run says so in
its own output. `state_get` takes the **last** record, which matters only for a
state file written by an older revision of this program: there the last record
is the current value and the first is the one the defect returned. Key matching
is a literal prefix comparison at position 1, not a regex, so no metacharacter
in a key can widen it.

**Regression:** a `rebuild-repins` case builds twice with different image IDs
into one work directory and asserts the state file holds exactly one `IMAGE_ID`,
that it is the second build's, that the replacement is announced, and — read
from the fake daemon's recorded `create` argument lists rather than from the
program's own output — that the probe container is created from the second
image and not the first. Reverting the two functions produces **6 failures**.

#### FINDING-50 — step Z compared the secret against a baseline it had just written itself

Also filed under the "real Docker daemon" row. Also needed no daemon.

§6.5 step Z says the deployment secret's "owner, group, mode, size and
modification time are compared against the values recorded earlier in the same
work directory". **Nothing recorded them earlier.** `SECRET_META` was written
only by `step_closeout`, which took its own baseline when it found none, printed
`no earlier metadata was recorded; this run records it as the baseline`, and
reported:

```
ok    secret metadata recorded (uid:gid mode size mtime)
```

On a single pass — 0, A, B, C, D, Z, which is the entire procedure — that was
**every run**. The comparison never happened, and with no other failure the step
reported `RESULT: every check in this step ran and passed`. A check that could
not have run was reading as one that passed, which is the exact shape this
repository has spent five sessions removing.

**Fixed** in both halves. The preflight step records the baseline, before any
step has run — metadata only; no credential is opened, there or in step Z's
default path. Where preflight cannot read it, that is recorded as
`SECRET_META_UNAVAILABLE` and step Z reports the comparison as **UNPROVEN**
rather than inventing a baseline at the moment it is supposed to be checking
one. Preflight itself does **not** fail on an unreadable secret: it requires
neither Docker nor the deployment, and failing there would make it unusable on
any host where the deployment is absent. The failure belongs to the step that
makes the claim, and that is step Z.

**Regression:** eleven cases, including the two that matter most — a closeout
whose metadata read *succeeds* while no baseline exists (the branch the defect
lived in, reached with a scoped `stat` shim that answers for the secret path and
delegates everything else), and the positive and negative comparisons against a
preflight-recorded baseline. Reverting the fix produces **8 failures**.

#### The ten open rows, reviewed one at a time

The review that produced the four findings above. Every row of §7's "still not
established" table was taken separately and sorted into one of four kinds, and
the sorting is recorded because three rows were in the wrong one.

| # | Row | Kind | Disposition |
| --- | --- | --- | --- |
| 1 | The gate suite passes on a hosted runner at the candidate | **Missing hosted evidence** | Needs an approved push. Not authorised here; nothing was pushed |
| 2 | An image built from the candidate satisfies the hardening assertions | **Missing runtime evidence** | Needs §6.5 step A, with a daemon. Unexecuted |
| 3 | The handoff behaves correctly against a real Docker daemon | **Was: pending operator testing. Contained two confirmed defects** | FINDING-49 and FINDING-50, both fixed here. The **residual** is genuine runtime evidence: that a real daemon accepts the arguments the program builds, and that the deployment's paths are mountable |
| 4 | The container identity can read the mounted secret | **Missing runtime evidence** | Needs a started container: step C. Unexecuted |
| 5 | A session is confirmed absent from the appliance afterwards | **Documented limitation** | ScamWall cannot ask — the session-listing endpoint is outside the permitted set, and widening it for a diagnostic is the wrong trade. Unchanged |
| 6 | `docker --add-host` accepts what the resolved configuration yields | **Missing runtime evidence** | The rendering is handled and cross-checked against the real Compose CLI. Whether the daemon maps the name is step B |
| 7 | The diagnostics filter catches every credential shape | **Was: documented limitation. Contained a confirmed defect** | FINDING-48, fixed here. The **residual** is a real limitation: deny-by-pattern establishes what its patterns catch |
| 8 | A fork pull request receives no secret and a read-only token | **Missing hosted evidence** | `workflow-policy-check.sh` establishes what the workflow says. What GitHub does needs a pull request from a fork |
| 9 | Why the first CI runtime verification failed | **Documented limitation** | The run has no artifacts and its log holds twenty-five lines. Not recoverable, and the row stays open rather than being closed by a plausible mechanism |
| 10 | The suite is deterministic to the standard set at `0b083cb` | **Missing evidence — partially supplied, and the row stays open** | §3.16: five rounds of all four suites, 20 runs, 0 failures, counts identical. Five is not the 30 the standard names. A first attempt was discarded rather than reported, because two copies of the campaign were truncating one log |

Three rows also carried **claims requiring correction**, independent of the
defects:

* §7's diagnostics-filter row described a leak as a limitation. Corrected: it
  was FINDING-48, it is fixed, and the residual is the deny-by-pattern nature.
* §6.5 step Z's "compared against the values recorded earlier in the same work
  directory" was **not true of the code**. It is now, by FINDING-50's fix.
* §3.15's "the gate list grew by one" and its `25 passed` are superseded: the
  list has grown again and the counts are restated in §3.16 rather than edited
  in place, because §3.15 is evidence about `9ebb98c`.

---

### 4.15 FINDING-51 … FINDING-56 — the operator handoff at `0cdec6c`, fixed at `76f3bfd`

Six defects in `scripts/operator-handoff.sh`, found by reading the program
under ORDER 1. Every one was reproduced against the scripted fake Docker, with
no daemon. Four of them cause the program to **do the thing it has just
reported must not be done**; two cause it to report a pass for a check that did
not happen.

#### FINDING-51 — a failed isolation assertion did not prevent the start

Steps B and C establish their isolation on the **created** container, before it
runs: step B asserts that the credential-free probe has no credential mounted,
step C asserts that the offline probe has no network. Both assertions were
written correctly and both returned a status. **Every call site discarded it:**

```bash
assert_no_mount "no credential is mounted into the connectivity probe" "$CT_SECRET_PATH"
assert_network_mode "the probe has network access, as this step requires" "bridge"
capture_run "$WORK/doctor.log" docker start -a "$PROBE_CID"
```

So a container whose isolation assertion FAILED was started anyway. The step
printed an accurate failure and then performed the action the failure said not
to perform:

* step B would have started a container with the real application password
  mounted, while its own output said no credential was mounted, in the one step
  whose entire purpose is to be credential-free;
* step C would have started a container with network access, while its own
  output said it had none, in the step that opens the credential and relies on
  `--network none` to guarantee that what it reads cannot leave the host.

The verdict was still nonzero, which is why this survived: the *step* failed,
so nothing looked wrong in the summary. What failed was the thing that happened
before the summary.

**Fixed.** `PROBE_BLOCKED` is raised by any pre-start assertion that fails **or
that cannot be evaluated** — an unreadable mount list is not permission to
start, it is the absence of the evidence starting requires — and `start_probe`
is now the only place a probe is started. It refuses while `PROBE_BLOCKED` is
nonzero, and the container is removed by cleanup rather than run.

**Regression.** Four cases assert the forbidden action does not occur, reading
the **fake daemon's own command log** rather than the program's output:
`log_lacks "the container is NEVER started" '^start'`. Reverting the gate
produces 8 failures.

#### FINDING-52 — a step published its results before it had a verdict

Step A ended:

```bash
state_put IMAGE_ID "$image"
state_put BUILD_COMMIT "$expected"
state_put BUILD_DATE "$build_date"
summary_and_exit
```

Those writes were unconditional. `summary_and_exit` then computed a verdict
that could be FAILED, and ran cleanup that could fail — after the identities
were already in the state file. A step A whose runtime verification failed, or
whose in-build assertion was reported CACHED, or whose cleanup could not remove
the container it created, still published the image id that steps B, C and D
went on to create their containers from.

There was no step state at all. A step that FAILED and a step that was NEVER
RUN were indistinguishable to every later step, which could only ask whether
`IMAGE_ID` happened to be present.

**Fixed.** Two changes, and both are needed:

* Results are **staged** where they become known and written by
  `record_step_outcome` only when the outcome is `passed`. A step that does not
  pass names the identities it is withholding and says why.
* A **step state machine** — `not_started`, `running`, `passed`, `failed`,
  `interrupted`, `indeterminate` — recorded in the state file. `passed` is
  written in exactly one place, after `run_cleanup` has returned **and** its
  problems have been counted into the verdict, so a step whose checks passed
  and whose cleanup failed is recorded as `failed`.

`indeterminate` is deliberately not a synonym for `failed`. A step that began
and ended without recording a verdict — a refusal after it started, or a death —
established something unknown, and a later step refuses it in those words.

**Regression.** Five cases: a failed build, a failed verifier, a failed
cleanup, an interruption and a post-start refusal, each asserting both the
recorded state and that the next step will not run off it. Reverting the
staging produces 5 failures; reverting the cleanup term produces 2.

#### FINDING-53 — the authorisation flag was accepted as proof of the prerequisites

Step D authenticates to the live appliance. Its refusal read:

> step D authenticates to the live Pi-hole. It runs only with
> `--authorise-authenticated-read`, **and only after steps A, B and C have
> passed and been read.**

It checked the flag. Nothing else. An operator who ran step B, watched it fail,
and then passed the flag got an authenticated request to the household Pi-hole
and a program that had told them in writing it would not do that.

**Fixed.** Two independent gates, and neither substitutes for the other. The
flag is the operator's **intent**; `require_step_passed` on preflight, build,
probe and secret is the **evidence**. The program now says which is which in
its own output.

**Regression.** Five cases, each asserting that the fake daemon's log contains
no `start` — no authentication is attempted — when a prerequisite is missing,
failed, or stale. Reverting the two prerequisite lines produces 7 failures.

#### FINDING-54 — the work directory's "sanitized logs" were the raw captures

`capture_run` wrote each command's **unmodified** output into the work
directory. `print_diagnostic` sanitized only what it printed to the terminal.
The closing summary then told the operator:

```
Evidence and sanitized logs remain in: <work dir> (mode 700)
```

Nothing in that directory had been sanitized. An operator following that
sentence — and it is the sentence the procedure gives them — would return a
build log, a doctor log and a runtime-verifier log exactly as the commands
emitted them. The mode-700 directory was the only thing standing between a
credential-shaped value in a build log and an evidence package.

**Fixed.** Two directories with different meanings:

| | |
| --- | --- |
| `<work>/raw/` | what the command actually wrote. Unsanitized. Carries its own `README-DO-NOT-SHARE.txt` |
| `<work>/evidence/` | the same output through `scripts/gate-diagnostics.sh --sanitize`. This is what leaves the host |

Sanitizing happens inside `capture_run`, not at its call sites, so a future
capture cannot forget it, and callers pass a **basename** rather than a path so
a raw capture cannot be written into the shareable directory by mistake. A
sanitizer that is absent or that fails produces **no** evidence file: an
unreadable evidence set costs a rerun, a file wrongly labelled sanitized cannot
be taken back. The resolved deployment configuration stays in `raw/` — it holds
the deployment's real host paths and is never published.

**Residual limitation, unchanged and stated in the evidence directory itself:**
the filter is deny-by-pattern. It establishes what its patterns catch. This
change does not make the filter complete; it stops the **unfiltered** file from
being labelled as the filtered one.

**Regression.** A build is made to emit a credential-shaped value; the raw
capture is asserted to **contain** it — that is what makes it raw — and the
evidence copy to not. Reverting the sanitize call produces 2 failures.

#### FINDING-55 — step Z's leftover check was a tautology, and passed every time

Step Z called `begin_invocation`, which generates a **new** unpredictable
identifier and then **refuses if anything already carries it**. It then
enumerated resources carrying that same brand-new label:

```bash
found="$(label_query "$kind" "$PROJECT_LABEL=$VERIFY_PROJECT")"
```

The query was guaranteed by construction to return nothing. Step Z printed

```
PASS    no container of this handoff remains
PASS    no network of this handoff remains
PASS    no volume of this handoff remains
```

for **every closeout that has ever run**, whatever steps A to D had left on the
host. The trailing note described the defect accurately without recognising it:
*"this step can only speak for its own"* — it was speaking for an invocation
that had created nothing.

This is the false-clean case the rest of the suite exists to prevent, in the
step whose only job is to establish that nothing remains.

**Fixed.** Every step that can create a resource records its invocation and
project identities into the state file **at `begin_invocation`, before it can
create anything**, in an accumulating register. That register is never cleared
by a failure, an interruption or an invalidation — a step that died halfway is
exactly the one whose leftovers matter. Step Z enumerates by **those**
identities, by both the ownership and the project label, per step and by name.
It does not enter itself into the register it is about to search.

An **empty register is not a pass.** No step in this work directory recorded an
invocation, so either none ran or they ran elsewhere; either way step Z has
nothing to search for and reports `leftovers are UNPROVEN`.

**Regression.** Four cases: a real leftover (a container whose removal was made
to fail) must produce a FAILING closeout that names the step that created it;
an empty register must be UNPROVEN and must make no clean-host claim; a genuine
clean result must name the steps searched; an enumeration that could not run
must be UNPROVEN. Reverting to the self-label query produces 7 failures.

#### FINDING-56 — the privileged work directory and state file were not validated

This program runs under `sudo`. Every path below is opened by uid 0, and the
work directory is named by the operator on the command line.

| What it did | Why that is a defect |
| --- | --- |
| `mkdir -p -- "$requested"` then `chmod 700` on it | `mkdir -p` on an existing **symlink** succeeds silently, and the `chmod` that follows applies to the link's **target**. A symlink at the named path pointed root's `chmod` at any directory on the host |
| Checked the mode, never the **owner** | A directory belonging to another account, mode 700, passed unchanged — root can enter it. The run then wrote its evidence where that account could read it, and read its identities back out of a file that account could write |
| Reached the state file with `[ -f "$STATE" ]` | `-f` follows symlinks. A `state.env` symlinked at any root-readable file made this program parse that file, and the values taken out of it became `EXPECTED_COMMIT`, `REPO_ROOT` and `IMAGE_ID` — the identities every other check is performed against |
| Never considered the **ancestors** | A work directory inside a directory another account can write is a directory that account can replace between two of this program's own syscalls |
| `: > "$log"` for each capture | Follows a symlink. In a work directory an attacker could prepare, that is a root-owned truncate-and-overwrite of a file of their choosing |

**Fixed.** The symlink check happens **before** `mkdir`, not after. The
directory must be owned by the account running the step, be mode 700, and have
no ancestor that another account can write without the sticky bit — `/tmp` at
`1777` is fine, which is what keeps `mktemp -d` acceptable, and a plain `0777`
parent is not. The state file must be a regular non-symlinked file, mode 600,
owned by us, **with exactly one hard link** — a second name for it means its
content is not solely this run's. `raw/` and `evidence/` are created by `mkdir`
**with** their mode, so there is no window in which they exist wider, and every
capture path is symlink-checked before it is written.

**STATED LIMIT.** These are checks, not locks. Between a check and the use that
follows it a sufficiently privileged account could still substitute a
component. The ancestor rule is what closes the practical version — an
unprivileged attacker needs a writable ancestor to perform the swap — and it is
not claimed to be more than that.

**A limit of the regression, stated rather than hidden.** The **ownership**
comparison cannot be exercised by an unprivileged account against a directory
owned by someone else, because such a directory cannot be created here. It is
exercised against a shimmed `id` reporting a different uid, which drives the
other side of the same comparison. That is weaker than the real condition and
the case says so.

**Regression.** Nine cases: a symlinked work directory at creation and at open,
a symlinked state file, a hard-linked state file, a state file of the wrong
mode, a world-writable ancestor, a sticky ancestor that must still be accepted,
a foreign owner, a symlinked capture file, and a symlinked `raw/`. The symlink
case also asserts that the link's **target** was neither chmod-ed nor written
into. Reverting the symlink checks produces 10 failures.

#### What these six do not establish

They are defects in a program that has **still never met a real Docker
daemon**. `scripts/tests/operator-handoff-test.sh` is now 308 cases against a
scripted fake, which establishes control flow, refusals, attribution, cleanup,
state handling, evidence separation and the order in which steps may run. It
does not establish that a real daemon accepts the arguments the program builds,
that `docker create` produces the container those arguments describe, or that
the deployment's paths exist and are mountable. Only steps A to D can establish
those, and they remain pending operator execution.


### 4.16 FINDING-57 … FINDING-60 — the ORDER 1 review, at `5d9d21d`; 57–59 fixed at `04e7ea4`, 60 at `ff2e734`

The ORDER 1 package was reviewed, and the reviewer did what §4.15 had not: they
**called the state functions themselves** and interrupted one. Three defects
came out of that, and all three are the same kind of defect — a record that is
true of one moment being read as though it were true of another. A fourth,
unrelated and pre-existing, surfaced in the Go suite while the gates were being
re-run; it is recorded here because it was found here, not because this session
caused it.

Every one of the first three was reproduced **without a Docker daemon**, from
outside the program, by the cases in `scripts/tests/operator-handoff-test.sh`.

#### FINDING-57 — a step's terminal record was published in pieces

`record_step_outcome` was the only writer of a terminal step state, which is
what §4.15 established and is still true. What it was not was a single write.
It wrote

```
state_put "$(step_key STEP_STATUS "$STEP_NAME")" "$outcome"      # rename 1
[ -n "$BIND_COMMIT" ] && state_put STEP_COMMIT_<step> ...        # rename 2
[ -n "$BIND_IMAGE" ]  && state_put STEP_IMAGE_<step>  ...        # rename 3
[ -n "$BIND_CONFIG" ] && state_put STEP_CONFIG_<step> ...        # rename 4
commit_staged_results                                            # renames 5..n
```

and each `state_put` was a complete rewrite-and-rename of the state file. The
status went in **first**. Between rename 1 and rename 2 the file said

```
STEP_STATUS_PROBE=passed
```

and said nothing whatever about the image or the resolved deployment
configuration that step had passed against. A step that died in that window —
the reviewer injected the interruption; a `kill`, an OOM, a power loss or a
`^C` at the wrong instant would do it — persisted exactly that: **a pass
carrying nothing**.

That record is worse than no record. `require_step_passed` accepted it, because
it read a status. `assert_prereq_identities` accepted it too, for the separate
reason that is FINDING-58. So the next step ran, and created its container from
an image the state file could not name.

**The fix.** Every write to the state file now goes through one primitive,
`state_apply`, which takes an arbitrary set of `+KEY=VALUE` and `-KEY` changes,
builds the complete new version in one temporary file, and installs it with a
single `rename(2)`. Whatever moment a reader looks, it sees the whole set of
changes or none of it. `record_step_outcome` emits the status, the three
bindings and every staged result as one such set.

Two neighbouring sites were made single writes for the same reason:

* `begin_step` sets `running` **and removes that step's own previous
  bindings** in one replacement. A step that has begun has not yet passed
  against anything, so the identities a previous run of the same step recorded
  must not outlive the moment this one starts. This was found by the new tests
  rather than by the reviewer: after an interrupted rebuild the state file
  still held `STEP_COMMIT_BUILD` and `STEP_IMAGE_BUILD` from the previous,
  successful build, beside `STEP_STATUS_BUILD=running`. Nothing could reach
  them — `require_step_passed` refuses a `running` step — but a binding sitting
  beside a status that does not entitle anything to read it is the precise
  shape of the defect being fixed, and it is not left standing on the argument
  that today's callers happen not to follow it.
* `invalidate_after_rebuild` voids every downstream acceptance and the previous
  image pin in one replacement rather than in eight. A rebuild interrupted
  partway through the invalidation cannot leave some acceptances voided and
  others standing beside a stale `IMAGE_ID`.

**STATED LIMIT.** `rename(2)` is atomic against concurrent readers and against
this process dying at any point. It is **not** a durability barrier: a host
that loses power between the rename and the filesystem's own flush can come
back holding the older version. That is tolerable here, because the older
version never claims more than the newer one does, and it is not claimed to be
more than that.

**How it is tested.** Not by asserting about the source. `mv` is shadowed in
the test harness and acts only on renames whose destination is a `state.env`,
so the one moment the recorded state changes can be observed and interrupted
from outside the program:

* every version of the state file installed during a real run of steps 0, A and
  B is copied out, and the suite asserts that **no version ever recorded
  `STEP_STATUS_<step>=passed` without every key that step is required to be
  bound to** — plus a non-vacuity check that passes for all three steps were in
  fact observed being published;
* the handoff is `SIGKILL`ed *at* the publishing rename: nothing of that step
  survives, and step B then refuses on `recorded as RUNNING` without creating
  or starting a container;
* the handoff is `SIGKILL`ed *immediately after* it: the **complete** record
  survives — status, both bindings and the staged `IMAGE_ID` — and step B
  proceeds on it, which is the other half of "whole, or not at all";
* the rename is made to **fail**: the previous version stands, the failure is
  reported, the exit status is nonzero, and no temporary state file is left
  behind.

`SIGKILL` rather than `SIGTERM` deliberately. A signal the program can handle
would let it tidy up, and what is being established is what survives when it
cannot.

#### FINDING-58 — a recorded pass was accepted without the identities it was bound to

`assert_prereq_identities` compared a component only when **both** the recorded
value and the current one were non-empty, and blocked only when *nothing at all*
could be compared:

```
rec="$(state_get "$(step_key STEP_COMMIT "$step")")" || rec=""
if [ -n "$rec" ] && [ -n "$BIND_COMMIT" ]; then ... compared="source commit"; fi
...
if [ -z "$compared" ]; then blocked ...; return 1; fi
ok "step $step passed against exactly these identities ($compared)"
```

So a matching commit, on its own, was enough. With `STEP_IMAGE_BUILD` absent —
which FINDING-57 makes an ordinary occurrence rather than a hypothetical — the
function returned **0**, and printed

```
PASS    step build passed against exactly these identities (source commit)
```

which is a true sentence and a useless one. The acceptance was carried forward
to a container created from an image nothing had compared. The sentence even
says "exactly these identities", and the operator reading it has no way to know
that the set is short.

**The fix.** Each step now has a **stated, required binding set**, and it is
enforced at both ends rather than inferred from what happens to be present:

| Step | Required bindings |
| --- | --- |
| `preflight` | source commit |
| `build` | source commit, image id |
| `probe` | source commit, image id, configuration digest |
| `secret` | source commit, image id, configuration digest |
| `status` | source commit, image id, configuration digest |
| `closeout` | none — it creates nothing and no step depends on it |

* `record_step_outcome` will not publish `passed` unless every required binding
  is established and well-formed; `summary_and_exit` checks the same thing
  *before* it computes the verdict, so the exit status and the printed result
  agree with what is recorded rather than diverging from it.
* `require_step_passed` refuses a recorded pass whose required bindings are
  **missing, empty, unreadable or malformed** — in those words, calling the
  record INCOMPLETE or CORRUPT rather than treating the gap as "not
  applicable". This is checked before the step requires Docker, creates a
  container, or offers a credential to one.
* `assert_prereq_identities` compares every required component. Absence on
  either side is refused, not skipped. Components neither side is required to
  carry are still compared when both have them, which costs nothing and catches
  a drift the table does not model.

Shape is checked wherever presence is: a commit is 40 lowercase hex, a
configuration digest is 64, an image id is `sha256:` and 64. A truncated or
non-hex value is refused as corrupt rather than compared and reported as
staleness — and a merely non-empty value can no longer satisfy a presence check
while establishing nothing.

The historical case is the same case. A state file written by an earlier
revision of this program, or left by an interruption, can hold
`STEP_STATUS_BUILD=passed` and nothing else; that record is now refused rather
than carried into a comparison that silently skips what is missing.

**How it is tested.** Six cases edit a *legitimately produced* state file the
way an interruption or an older revision would have left it — drop
`STEP_IMAGE_BUILD`, record it empty, record it malformed, abbreviate
`STEP_COMMIT_BUILD`, drop `STEP_CONFIG_PROBE`, drop `STEP_IMAGE_SECRET` — and
assert the consequence rather than the wording: the step exits nonzero **and**
the fake daemon's log contains no `create` and no `start`. The first of them is
the reviewer's case exactly: the commit still matches, and the image binding is
gone.

#### FINDING-59 — nothing serialised two invocations sharing a work directory

Each step is a separate invocation, and the state file is how they speak to one
another. Nothing stopped two of them running in the same work directory at the
same time. `rename(2)` makes each individual write atomic; it does **not** make
a read-decide-write **sequence** atomic, and a prerequisite check is exactly
that: read the earlier step's record, decide it is usable, act on it. Three
concrete races followed:

* step B could read `STEP_STATUS_BUILD=passed` and its bindings while a
  concurrent `build` was midway through invalidating exactly those records;
* two steps could each read-modify-write the invocation register
  (`state_append_word`) and one of the two registrations would be lost —
  leaving containers behind that step Z would never know to look for, while
  step Z reported no leftovers;
* `preflight` removes and recreates the state file, which another step could be
  reading through at that moment.

**The fix.** Each step takes an exclusive `flock` on `<work>/.handoff.lock`
before the first read of the state file — inside `open_work_dir` and
`create_work_dir`, after the directory's trust checks and before `STATE` is
even set — and holds it for the whole step. It is released explicitly in the
`EXIT` trap after the terminal state has been recorded, so the next invocation
cannot begin reading until this one's verdict is on disk; and it is released by
the kernel with the descriptor if the process is killed.

It is **nonblocking**. Two steps in one work directory at once is an operator
error, not a queue, and reporting it is more useful than silently serialising
two runs the operator believes are independent. `flock` being absent is a
refusal, not a warning: the alternative is racing the state file while claiming
not to.

**The lock must not become the hole it closes.** A naive `: > "$WORK/lock"`
would reintroduce, for the lock, exactly the symlink defect FINDING-56 closed
for the state file. So: the path is refused if it is a symlink, before and
after creation; and after the descriptor is opened, `stat` of
`/proc/self/fd/9` is compared against `stat` of the path, so a component
substituted between the check and the open is caught rather than followed. The
type is read separately and both of `stat %F`'s spellings for a regular file
are accepted — it says `regular empty file` for a zero-length one — and the
type is deliberately **not** part of the identity comparison, because a file's
length can change between the two calls without the file having been
substituted.

**STATED LIMIT.** The descriptor is inherited by the commands this program
runs. Every one of them is short-lived and waited for, so none outlives the
step and none can hold the lock past this program's exit; a future call site
that spawned something detached would have to close it.

**How it is tested.** Three cases, all deterministic:

* another process holds the lock — the step refuses, names what would race, and
  the fake daemon's log shows **no `build` and no `create`**; the same step then
  succeeds once the lock is released;
* the lock is held *through* a step rather than merely taken at its start: the
  fake `docker build` is made to block, a first invocation is left inside it, a
  second invocation is refused while it is there, and the first then completes
  normally with a complete record;
* the lock path is a symlink — refused, and the target is not created.

#### FINDING-60 — a Go end-to-end test fails about 8% of the time, on a coincidence

Not this session's defect, not in this session's changed files, and not caused
by anything in them. It surfaced because the gate suite was re-run.

`cmd/scamwall/e2e_test.go:635`, in
`TestDoctorNeverReportsTheCredentialLength`:

```go
if strings.Contains(stdout, strconv.Itoa(len(e.password))) {
    t.Errorf("stdout contains the credential's length:\n%s", stdout)
}
```

The e2e password is `"scamwall-e2e-password-"` plus 32 hex characters — **54**
characters, always. The assertion therefore searches stdout for the two-digit
string `54`. `stdout` legitimately contains `t.TempDir()` paths, and Go's
`t.TempDir()` embeds a 10-digit random component:

```
ok  certificate authority  loaded and parsed:
    /tmp/TestDoctorNeverReportsTheCredentialLength3547291038/001/pihole-ca.crt
                                                   ^^
```

`3547291038` contains `54`, so the test failed. The probability that a random
10-digit decimal string contains a given two-digit needle is about 8.6%, and
measured over 25 runs of that test alone on this tree it failed **2 times**.

**What it means for the evidence.** The check the test is *for* — that the
credential's length is never disclosed — is worth having; the way it is written
also matches unrelated digits anywhere in the output. It is a false positive,
not a real disclosure: no credential and no length was printed in the failing
run, and the assertion above it (`strings.Contains(stdout, "bytes")`) passed.
Earlier sessions recorded `go test -race -count=1 ./...` as passing; those runs
were correct **and lucky**, and the row they support is not invalidated by this
— but it is now known to be renewed by a test that fails about one run in
twelve for a reason unrelated to the property.

**Deferred at `04e7ea4`, fixed at `ff2e734` on the reviewer's instruction.** It
was deferred because the fix is a **Go source change**, which demotes rows
under `docs/REQUIREMENTS_MATRIX.md` §5, and ORDER 1's review had directed a
state-consistency fix and said not to change code merely to assemble a package.
Changing Go source to turn a gate green is exactly that, and it was not a call
to make unilaterally. The reviewer then instructed the fix, and it was made.

**The fix narrows the haystack, not the property.** Two shapes were available
and only one of them is honest:

* Replace the bare-integer search with `"<n> bytes"`-shaped pattern matching.
  This removes the false positive **and the property** — a length emitted with
  no unit at all would stop being caught, and that is the disclosure shape the
  bare-integer check exists for.
* Remove the one source of unrelated random digits and keep the bare-integer
  search over everything the program itself composed. The masked text is the
  directory this test created, whose value the test knows verbatim.

The second was taken. Two guards keep the narrowing from rotting into a
blindfold: an empty `e.dir` is fatal rather than masking the whole of stdout,
and a password shorter than 10 characters is fatal, because a one- or two-digit
length would collide with the counts in the `N checks, N failed, N skipped`
summary and reintroduce the identical class of false positive one layer down.

**Shown to still discriminate.** `cmd/scamwall/main.go` was mutated in the
working tree to disclose the length, and reverted:

| Mutation | Result |
| --- | --- |
| `readable (%d bytes)` | both the `"bytes"` check and the bare-integer check fire |
| `readable, %d` | the bare-integer check fires; the `"bytes"` check does **not** |

The second row is the whole argument for keeping a bare-integer search. A
pattern-matching rewrite would have passed that mutation.

**Shown to be fixed.** Before: 2 failures in 25 runs of that test. After: **0
in 60**. At the measured rate the probability of 60 clean runs by chance is
about 0.7%, so this is evidence rather than one lucky pass — which is the
distinction the first version of this row got wrong.

**What it says about SW-P1-14.** That row is *"the gate suite is
deterministic"*, and it is VERIFIED on repeat counts of 500 and 30 runs. Those
counts are of the **shell** suites. `go test -race ./...` is a required gate in
the same suite and was never in any of them, and it carried an 8%
nondeterminism from the moment this assertion was written until `ff2e734`. The
row's evidence is narrower than the row's claim, and the gap is not closed by
this fix — it is only made visible by it. The status is left as it stands
rather than being quietly adjusted; see the note added to SW-P1-14 in
`docs/REQUIREMENTS_MATRIX.md`, and §7.

#### What these four do not establish

The first three are defects in a program that has **still never met a real
Docker daemon**. `scripts/tests/operator-handoff-test.sh` is now 393 cases
against a scripted fake. It establishes control flow, refusals, attribution,
cleanup, state handling, evidence separation, the order in which steps may run,
and now the atomicity of the recorded state, the completeness of its bindings
and the exclusion of concurrent invocations. It does not establish that a real
daemon accepts the arguments the program builds, that `docker create` produces
the container those arguments describe, or that the deployment's paths exist
and are mountable. Only steps A to D can establish those, and they remain
pending operator execution.

### 4.17 FINDING-61 and FINDING-62 — the source-registry schema, found by implementing it

Two gaps in `docs/SOURCE_REGISTRY.md`, both surfaced by writing the validator
that enforces it. Neither is a defect in code that existed; both are places
where the prose asked for something the schema had no room to hold, which is
the failure mode a schema written without an implementation tends to have.

#### FINDING-61 — §3 required a reason, and §2 provided nowhere to record it

§3 closes with:

> A source whose documentation cannot be read stays `unresolved` with the
> reason recorded.

The 26-field record schema in §2 has no field for a reason. Every field it does
have is about the provider — its name, its documentation, its licence, its
cadence — and none of them is about *this registry's own state of knowledge*.
So the rule as written could not be complied with: the only places to put "the
provider's documentation site returned 403" were fields that mean something
else, and putting it in one of those would have made a false statement about
the provider in order to record a true one about the research.

**Fixed** by adding `disposition_reason`, required on every record like all the
others, and validated as non-empty. It carries why the record holds the
disposition it holds — including, for the common case, "not yet researched".

The gap matters more than it looks. `unresolved` is the default and the state
of all 85 catalog entries; a registry that cannot distinguish *nobody has
looked* from *somebody looked and was refused* loses the difference between
work not started and work that hit a wall.

#### FINDING-62 — "never reused" cannot be checked against the current file

§2 says of `source_id`:

> stable internal identifier. Never reused, never renumbered

A validator that sees only the current registry can enforce uniqueness *within
that file*, and that is all. An id deleted in one commit is free for the taking
in the next, and the rule would be silently violated by the ordinary act of
removing a record and adding another — which is exactly when it matters, because
anything that referenced the old id now points at a different source.

**Fixed** by adding a file-level `retired_source_ids` array. Retiring an id is
what turns the rule from an instruction into something enforceable: the
validator refuses a record whose `source_id` appears there.

**Stated limit.** This makes the rule checkable, not automatic. Nothing forces
an author who deletes a record to retire its id, and the validator cannot know
about an id that was removed without being retired — it never saw it. What the
mechanism provides is a place to record the decision and a check that honours
it; the discipline of using it remains a human one, and is now at least
possible to follow.

#### Why both are recorded rather than quietly patched

Each is a change to a schema that another document, and eventually 85 records,
depend on. A field added to `docs/SOURCE_REGISTRY.md` §2 without a note reads,
to the next person, as though it had always been there and had always been
thought about. Both entries in the schema table now carry the finding number,
so the reason the field exists travels with the field.

### 4.18 FINDING-63 … FINDING-67 — the source-registry safety model, at `6bb33bf`, fixed at `e8f8683`

Five defects in `internal/sourceregistry` as first written, found by reviewing
it against the full source-qualification requirements rather than against the
prose it was implementing. The registry was empty throughout, so none of them
had produced a wrong answer about a real provider — which is the only reason
they are cheap to fix now.

#### FINDING-63 — three rights fields and a boolean cannot express authorization

Schema 1 carried `commercial_use`, `caching` and `redistribution`, each
`permitted`/`prohibited`/`conditional`/`unknown`, and one `enabled` flag gated
on all three being `permitted` or `conditional`. That model fails in **both**
directions, which is what makes it worth recording rather than merely
replacing.

**It over-refuses.** A source whose terms permit querying and forbid
republishing could never be enabled, though a purely local lookup is exactly
what those terms permit. Requiring redistribution rights to perform a permitted
local lookup is a category error, and it would have quietly disqualified a
whole class of otherwise usable sources.

**It under-refuses, which is worse.** `permitted` in those three fields said
nothing about whether ScamWall could fetch the data at all, keep a local copy,
use it to annotate other records, or train on it. Those operations were
authorised by silence. Model training in particular is frequently prohibited by
terms that permit everything else, and the old model had nowhere to record that
and no way to act on it.

**And `conditional` was effectively a permission.** It was accepted as
sufficient to enable a source, on the reasoning that "the condition may well be
met". Nothing recorded what the condition was, whether anyone had checked, or
what they concluded.

**Fixed** by making authorization per operation. Seven operations — retrieval,
local storage, enrichment, model training, commercial use, redistribution,
derived output — each carry a grant. An operation with no grant is refused:
silence is not a permission. `conditional` authorises only when every
enumerated condition is recorded satisfied **with a basis**; unsatisfied and
unassessed both refuse, because an unmet condition and an unchecked one are the
same thing at the moment the operation would happen. `enabled` is checked
against `intended_operations` alone, so permission to query never becomes
permission to publish and a local lookup never needs redistribution rights.

#### FINDING-64 — rights assertions carried no evidence

A record could say `commercial_use: permitted` and cite nothing. The registry's
claim to be evidence rests entirely on assertions being traceable to a document
and a date, and the schema provided neither.

Worse, it provided no way to keep apart four things whose blurring is the usual
route to an untrustworthy provenance record: what the provider's terms **say**,
what the documentation says the product **can do**, this project's **reading**
of either, and what remains **unknown**. A single free-text field would have
let a marketing page describing a capability stand in as a term of licence,
which ORDER 2 §4 names explicitly as a mistake not to make.

**Fixed.** Every asserting grant cites `provider_terms` — an https URL, the day
it was read, and the quote — and evidence has four separate slots, validated
independently. `unknown` and `not_applicable` assert nothing and need no
citation, which is the distinction that keeps the requirement honest rather
than a box to fill.

#### FINDING-65 — deleting a record without retiring its id bypassed "never reused"

`retired_source_ids` was added in FINDING-62 to make "never reused" checkable.
It did not make it enforced. Nothing required a **removal** to retire the id it
freed, so the ordinary sequence

```
commit N     src-0007 = "Provider A"
commit N+1   the record is deleted; src-0007 is not retired
commit N+2   src-0007 = "Provider B"
```

produced three files that each validate, while anything referencing `src-0007`
silently changed meaning.

**Fixed** by comparing versions. `ValidateAgainstBaseline` refuses a removal
that did not retire, refuses an id dropped from the retired list, and catches a
same-commit swap directly. A test walks **every consecutive committed pair** of
the file's history.

**Where it bites, stated because it is easy to overclaim.** The walk flags the
**removal**, not the later reappearance — by the time an id is taken again the
baseline no longer mentions it and nothing at that step can tell. A test
asserts the reappearance step is silent, so the mechanism cannot later be
mistaken for more than it is. Three rules together give the invariant and none
gives it alone: removal must retire, retirement is permanent, a retired id
cannot be taken. And the walk sees only the history git can show it: nothing
about a rewritten history, nothing about a version that never reached a commit.

#### FINDING-66 — lineage had no cycle detection, and unknown upstreams read as independence

Self-edges, duplicates and dangling edges were refused. **Cycles were not
detected at all**, so `A -> B -> C -> A` validated cleanly. Lineage is
directional — a source cannot be derived from something derived from it — so a
cycle is a contradiction, and any future deduplication or independence
reasoning walking that graph would not terminate or would terminate wrongly.

Separately, and more consequentially: a record with **no** documented upstreams
was indistinguishable from a record whose upstreams **nobody had established**.
The first is a primary observer; the second is an unknown. Treating them alike
is precisely how three feeds sharing one upstream get counted as three
independent sources — the thing `aggregation_dependencies` is advertised as
preventing.

**Fixed.** Cycle detection is a three-colour DFS reporting each cycle once,
canonicalised so one cycle is not reported from several entry points.
`upstream_sources_completeness` records how much is known, and
`IndependenceClaimable` refuses to call independence demonstrated when the
answer is `unknown` or `documented_partial`. A record claiming
`documented_complete` while carrying lineage edges and listing no upstreams is
refused as self-contradictory.

It remains a check on what was **recorded**. It cannot discover a shared
upstream nobody wrote down.

#### FINDING-67 — input handling was whatever the decoder happened to do

Four behaviours, none of them chosen:

* **Duplicate JSON keys were accepted**, with `encoding/json` keeping the last
  occurrence silently. For a document of record that is the worst available
  resolution: a reviewer reading the file sees the first value, the program
  uses the second, and both are reading the same bytes. A record carrying
  `"commercial_use": "prohibited"` followed by `"commercial_use": "permitted"`
  decoded to `permitted` with no diagnostic anywhere.
* **A single wrongly typed field aborted the whole document**, discarding every
  other diagnostic. One typo made the file unreadable rather than making one
  field wrong.
* **There was no size cap.** "Parse whatever arrives" is how a parser becomes a
  denial-of-service surface, and `docs/SOURCE_REGISTRY.md` §4 is explicit that
  downloaded records are untrusted input — the registry is no more trusted than
  the things it describes.
* **Trailing content after the document was accepted**, so `{...}{...}` read
  the first object and discarded the second in silence.

**Fixed**, each with defined behaviour and a test: duplicates refused by a token
walk before any value exists; wrong types reported by path and the field
dropped so validation of everything else continues; an 8 MiB cap; trailing
content and unknown top-level keys refused. An unsupported `schema_version` now
refuses **and stops**, rather than going on to emit confident findings about a
document whose field meanings it does not know.

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

`doctor` no longer reports the credential's byte count. `LoadSecretFile`
already refuses an empty credential, so the length diagnosed nothing that the
pass/fail result did not, and a length is still a fact about a credential
written into an operator's evidence log.
`TestDoctorNeverReportsTheCredentialLength` keeps it out.

**What this set does not amount to.** It is a set of reviewed protections with
tests, not a proof that no code can disclose a credential. The call-site count
is a lexical property of this tree at this commit and constrains this code, not
a future edit and not a dependency. The formatting overrides bind
`config.Secret`; a plaintext copied out into a plain `string` is outside all of
them. `§6.5` step C states the same limits where an operator will read them,
because the superseded text there asserted the stronger claim.

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

### 6.1 Runtime verification against a real image (SW-P1-05) — **SUPERSEDED BY §6.5 STEP A**

> **Do not run the command block in this section.** It is retained because the
> reasoning below — what is missing for SW-P1-05 and why CI does not cover it —
> is still current and is what step A exists to satisfy. Its *commands* are the
> ancestor of the procedure §4.13 documents nine defects in: they pass no build
> metadata, assert that the new image ID must differ from the old, read the
> build status through `tee`, and hash the production password unconditionally.
> `scripts/operator-handoff.sh build` replaces them and is tested.

**Status.** Executed by the operator at commit `b6b1769` against image
`sha256:b95cc07c…`: build exit 0 with both in-build assertions run, verifier
90 passed / 0 failed / 0 blocked / 0 cleanup problems, `VERIFY exit=0`. The
result is §3.7. That evidence remains valid **for `b6b1769` and for that image**
and is not withdrawn; it no longer covers the current candidate.

**SW-P1-20 is no longer waiting on this procedure.** Its acceptance is about the
ELF assertion executing in a real build, and the passing CI run at `72bc84c` did
that on an uncached runner — §3.12. This procedure still re-executes the
assertion, and its result is recorded against the operator-built image, but that
is an extension of the row to a second artifact rather than the evidence the row
was blocked on.

**What is actually missing for SW-P1-05, at `b6e70f4`.** Not "the whole row".
Four assertions have never been evaluated against the operator's resolved
configuration and an operator-built image:

| Assertion | Why CI does not cover it |
| --- | --- |
| `no prohibited path appears in the configured mounts or in the secret source` | added at `aa49797`; CI evaluated it against fixture paths under `RUNNER_TEMP` |
| `every approved mount resolves to an existing regular file on this host` | added at `aa49797`; "this host" was the runner |
| `the application password file is not world-readable through its path` | added at `aa49797`; the runner's file was a 0600 fixture in a fresh directory, not `/etc/scamwall/secrets` |
| the supplementary group is the gid that owns the password file | CI resolved `65532` from the default, not `989` from the operator's `.env` — §3.12 |

Everything else the row asserts was exercised in CI against a real image
(§3.12). The renewal is expected to pass: the CA at
`/etc/scamwall/certs/pihole-ca.crt` is a regular file, `/etc/scamwall/secrets`
is `0750 root:swsecret`, and rendering the definition with the operator's `.env`
yields `group_add: ["989"]` (§3.13). "Expected to pass" is not a result. If any
of them FAILS, that is a finding about the deployment and takes precedence over
closing anything.

**The access constraint is unchanged, and is not a defect.** The service
account is not in the `docker` group and has no passwordless sudo. By operator
decision this stays that way: `docker` group membership is root-equivalent on
this host, since it permits mounting the host filesystem into a container.
Docker operations remain operator-executed, so a `scamwall` run of
`scripts/check.sh` will continue to report these two gates as `BLOCKED` and
exit 1 (§3.0). That is the correct local result and does not contradict §3.7.

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

#### Four defects in the previous form of this procedure, and their fixes

The commands printed here before `b6e70f4` would have run, and three of the four
faults below could have produced a *wrong result* rather than a failed run. They
were found by reviewing the procedure against the current verifier and
Dockerfile, not by running it.

1. **A failed build was survivable, and the stale tag would have been verified
   in its place.** The block set no `-e` and tested nothing: after a failing
   `docker build`, `docker image inspect -f '{{.Id}}' scamwall:local` returns
   whatever already held that tag — on this host, `b6b1769`'s
   `sha256:b95cc07c…`. The verifier would then have passed, pinned to an image
   built from a different commit, and the transcript would have been filed
   against `b6e70f4`. **Fixed:** the tag's pre-build identity is recorded first,
   a nonzero build status aborts, and both identities are printed.
2. **The evidence the procedure asked for could not appear in the output it
   collected.** Step 2 said "the last ~40 lines of build output … contain the
   ELF assertion's report". Under BuildKit's default progress renderer they
   contain a collapsed step summary; `elfcheck`'s report is not in them.
   **Fixed:** `--progress=plain`, the build log captured, and the two assertion
   steps extracted by step number.
3. **A cached layer would have been read as an assertion that ran.** Both
   in-build assertions are `RUN` steps. The build context is byte-identical to
   `b6b1769`'s — `.dockerignore` admits only `go.mod`, `go.sum`, `cmd/` and
   `internal/`, none of which changed — so only the differing `--build-arg`
   values invalidate the cache. **Fixed:** `CACHED` on either assertion step
   aborts with the instruction to rebuild with `--no-cache`, and the count of
   cached steps is printed either way.
4. **`tee /tmp/scamwall-verify.log`, run as root, reintroduced the exact defect
   `scripts/check.sh` documents and avoids** — a predictable name in a
   world-writable directory, which any local account can pre-create as a symlink
   and so redirect a root-owned write. **Fixed:** `mktemp`, `chmod 600`.

Two additions of the same kind: the CI fixture variables are refused if they are
still exported in the operator's shell, so a leftover `SCAMWALL_CA_FILE` cannot
silently redirect a bind source to a placeholder; and the real secret's mode,
owner, size and content digest are compared before and after, so "the procedure
did not touch the credential" is an observation rather than an assurance. The
digest is compared, never printed.

**Run the whole block as root.** The password-permission assertion needs
traverse permission on the `0750 root:swsecret` secrets directory. An identity
without it makes the verifier report the exposure as UNDETERMINED and FAIL —
which is the correct behaviour, but it is a fact about the identity, not about
the deployment. The preflight settles this before anything is built.

**Two inputs.** `SCAMWALL_REPO` is the checkout path, deliberately not recorded
in this document. `SCAMWALL_EXPECT_COMMIT` is the candidate's full SHA, taken
from the handoff — it is a parameter rather than a literal because this file is
part of the tree it names, so a SHA written inside it would be invalidated by
the very commit that recorded it. The run aborts if `HEAD` is anything else.

```bash
# ScamWall — operator runtime verification.
# The candidate commit is supplied by the handoff, not hardcoded: this file is
# part of the tree it names, so any revision of it would invalidate a SHA
# written inside it.
set -uo pipefail

REPO="${SCAMWALL_REPO:?set this to the ScamWall checkout path}"
EXPECT_COMMIT="${SCAMWALL_EXPECT_COMMIT:?set this to the candidate commit named in the handoff}"
SECRET=/etc/scamwall/secrets/pihole_app_password

die() { printf '\nABORT: %s\n' "$1" >&2; exit 1; }

# ---- 0. Preflight ------------------------------------------------------------
# CI passes throwaway fixture paths through these variables. If one is still
# exported in this shell it silently redirects a bind SOURCE, and the run would
# verify a fixture while reporting the deployment.
for v in SCAMWALL_CA_FILE SCAMWALL_SECRET_FILE SCAMWALL_CONFIG SCAMWALL_FEED \
         SCAMWALL_IMAGE SCAMWALL_EXPECTED_IMAGE_ID; do
  [ -z "${!v:-}" ] || die "$v is set in this shell ('${!v}') — unset it; the deployment's own values must apply"
done

printf 'RUN AS=%s (uid %s)\n' "$(id -un)" "$(id -u)"
printf 'DOCKER=%s\n' "$(docker --version 2>&1)"
printf 'COMPOSE=%s\n' "$(docker compose version 2>&1)"
docker info >/dev/null 2>&1 || die "this account cannot reach the Docker daemon"

# The password-permission assertion needs traverse permission on the 0750
# secrets directory. Without it the verifier reports the exposure UNDETERMINED
# and fails — a fact about the identity, not about the deployment. Settle it now.
stat -c '%a' -- "$SECRET" >/dev/null 2>&1 ||
  die "cannot stat $SECRET as $(id -un) — run this whole procedure as root"

ENV_FILE="$REPO/deploy/compose/.env"
[ -f "$ENV_FILE" ] || die "$ENV_FILE is absent — the deployment's overrides would not apply"
printf 'ENV FILE=%s\nENV KEYS=%s\n' "$ENV_FILE" \
  "$(sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' "$ENV_FILE" | tr '\n' ' ')"

# Identity of the real secret, recorded before anything runs. The digest is
# compared, never printed.
printf 'SECRET BEFORE=%s\n' "$(stat -c 'mode=%a owner=%U:%G size=%s mtime=%Y' -- "$SECRET")"
SECRET_SUM_BEFORE="$(sha256sum -- "$SECRET" | cut -d' ' -f1)" || die "could not read $SECRET"

# ---- 1. Source identity, read AS scamwall ------------------------------------
COMMIT="$(sudo -u scamwall git -C "$REPO" rev-parse HEAD)" || die "could not read HEAD as scamwall"
DESCRIBE="$(sudo -u scamwall git -C "$REPO" describe --tags --always --dirty)" || die "could not describe HEAD"
DIRTY="$(sudo -u scamwall git -C "$REPO" status --porcelain | wc -l | tr -d ' ')" || die "could not read the working-tree state"
printf 'SOURCE COMMIT=%s\nDESCRIBE=%s\nUNCOMMITTED FILES=%s\n' "$COMMIT" "$DESCRIBE" "$DIRTY"
[ "$DIRTY" = 0 ] || die "$DIRTY uncommitted file(s) — the image could not be tied to a commit"
[ "$COMMIT" = "$EXPECT_COMMIT" ] || die "HEAD is $COMMIT, expected $EXPECT_COMMIT"

# ---- 2. What holds the tag now, before the build replaces it -----------------
PRE_IMAGE_ID="$(docker image inspect -f '{{.Id}}' scamwall:local 2>/dev/null)" || PRE_IMAGE_ID=none
printf 'PRE-BUILD scamwall:local=%s\n' "$PRE_IMAGE_ID"

# ---- 3. Build, through the operator's Docker access --------------------------
BUILD_LOG="$(mktemp)" || die "could not create a build log"
chmod 600 "$BUILD_LOG"
docker build \
  --progress=plain \
  -f "$REPO/container/Dockerfile" \
  -t scamwall:local \
  --build-arg VERSION="$DESCRIBE" \
  --build-arg COMMIT="$COMMIT" \
  --build-arg BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "$REPO" 2>&1 | tee "$BUILD_LOG"
BUILD_RC="${PIPESTATUS[0]}"
printf 'BUILD exit=%s\n' "$BUILD_RC"
[ "$BUILD_RC" -eq 0 ] ||
  die "the build failed; scamwall:local still refers to $PRE_IMAGE_ID, which must NOT be verified as this candidate"

# ---- 4. The two in-build assertions, from the build's own output -------------
show_step() { # <substring of the RUN command>
  local n
  n="$(sed -n "s|^#\([0-9][0-9]*\) \[[^]]*\] RUN .*$1.*|\1|p" "$BUILD_LOG" | head -1)"
  [ -n "$n" ] || { printf '  (no build step matched "%s" — read %s in full)\n' "$1" "$BUILD_LOG"; return 0; }
  grep -E "^#${n}( |\$)" "$BUILD_LOG"
}
printf 'CACHED STEPS=%s (a cached step did not execute for this build)\n' "$(grep -cE '^#[0-9]+ CACHED' "$BUILD_LOG")"
echo "---- ELF linkage assertion (SW-P1-20) ----"
ELF_STEP="$(show_step 'elfcheck')"
printf '%s\n' "$ELF_STEP"
case "$ELF_STEP" in
  *CACHED*) die "the ELF assertion step was CACHED — it did not execute for this build. Re-run step 3 with --no-cache" ;;
esac
echo "---- enforcement-absent assertion ----"
ENF_STEP="$(show_step '/out/scamwall version')"
printf '%s\n' "$ENF_STEP"
case "$ENF_STEP" in
  *CACHED*) die "the enforcement assertion step was CACHED — it did not execute for this build. Re-run step 3 with --no-cache" ;;
esac

# ---- 5. Image identity -------------------------------------------------------
IMAGE_ID="$(docker image inspect -f '{{.Id}}' scamwall:local)" || die "could not resolve the built image"
printf 'IMAGE ID=%s\nPREVIOUS TAG HELD=%s\n' "$IMAGE_ID" "$PRE_IMAGE_ID"

# ---- 6. Verify, pinned to exactly that image ---------------------------------
# The verifier uses `docker compose create` and `docker create` only. It starts
# nothing, so no credential is used and no authenticated command runs.
VERIFY_LOG="$(mktemp)" || die "could not create a verifier log"
chmod 600 "$VERIFY_LOG"
SCAMWALL_EXPECTED_IMAGE_ID="$IMAGE_ID" \
  bash "$REPO/scripts/container-runtime-verify.sh" 2>&1 | tee "$VERIFY_LOG"
VERIFY_RC="${PIPESTATUS[0]}"
printf 'VERIFY exit=%s\n' "$VERIFY_RC"

# ---- 7. The deployment's secret is exactly as it was -------------------------
printf 'SECRET AFTER=%s\n' "$(stat -c 'mode=%a owner=%U:%G size=%s mtime=%Y' -- "$SECRET")"
if [ "$(sha256sum -- "$SECRET" | cut -d' ' -f1)" = "$SECRET_SUM_BEFORE" ]; then
  echo "SECRET CONTENTS=unchanged"
else
  echo "SECRET CONTENTS=CHANGED — stop and investigate before anything else"
fi

# ---- 8. Nothing of this invocation is left behind ----------------------------
echo "---- residue (both lists must be empty) ----"
docker ps -a --filter 'name=scamwall-verify-' --format '{{.ID}} {{.Names}} {{.Status}}'
docker network ls --filter 'name=scamwall-verify-' --format '{{.ID}} {{.Name}}'

printf '\nRETURN: every line above, plus the full contents of:\n  %s\n  %s\n' "$BUILD_LOG" "$VERIFY_LOG"
```

`VERIFY_RC` is the exit status of the verifier itself, not of `tee` — that is
what `PIPESTATUS[0]` is for. Reading `$?` after a pipeline would report `tee`'s
status, which is 0 almost always, and would turn a failed verification into a
green result.

**What the verifier does to the host.** It creates two containers and one
network under a Compose project named `scamwall-verify-<128 random bits>`,
starts neither, and removes exactly what it created. Its only Docker verbs are
`create`, `inspect`, `ps`, `ls`, `history`, `export` and `rm`: there is no `up`,
no `start` and no `run`, so the application never executes and no credential is
read. It refuses to create anything if a resource already carries that project
name, it never issues a project-wide `compose down`, every resource query is
filtered by a label unique to the invocation, and any resource it cannot
attribute to itself is left in place and reported. **A running deployment is not
stopped, removed, inspected, or adopted.** If the run is interrupted, cleanup
still completes; if cleanup fails, the exit status is nonzero and the remaining
identifiers are printed.

**Interpreting the result.**

| Exit | Meaning |
| --- | --- |
| 0 | every required check ran and passed, AND cleanup completed |
| 1 | at least one check failed, could not run, or required cleanup failed — the output distinguishes `FAIL`, `BLOCKED` and `CLEANUP` |
| 2 | the script was invoked wrongly, or the directory is not a ScamWall checkout |

**What to return.** Every line the block prints, plus the full contents of the
two logs it names. Partial output is weaker: the verifier's value is that it
distinguishes "passed", "failed" and "could not run", and a truncated log loses
exactly that distinction — which is why the counts for all three categories are
recorded in §3.7 and not just the passes. FINDING-23 was that same mistake made
mechanically, by the gate suite, to this verifier's output.

The lines that are the reason this renewal exists rather than a formality — the
three assertions added at `aa49797`, and the two that carry the supplementary
group:

```
PASS    no prohibited path appears in the configured mounts or in the secret source
PASS    every approved mount resolves to an existing regular file on this host
PASS    the application password file is not world-readable through its path
PASS    supplementary group resolves to a single valid non-root gid (989)
PASS    supplementary group
```

The gid in the fourth line is the evidence that the operator's `.env` was in
force: a run with no `.env` reports `65532` there and still passes, which is
what CI did. The total will exceed 90 because checks were added, not because
anything was relaxed. A `FAIL` on the third line means
`/etc/scamwall/secrets/pihole_app_password` is reachable by every account on the
host, which would be a finding about the deployment rather than about the
verifier, and it takes precedence over closing either row.

**A limitation to record rather than fix here.** The verifier asserts that the
supplementary group is a single valid non-root gid and that the container
carries exactly the gid the resolved configuration specifies. It does **not**
stat the password file to confirm that this gid is the file's owning group —
that `989` is `swsecret` is established by the deployment's `.env` and by §3.13,
not by an assertion. Closing that gap means changing
`scripts/container-runtime-verify.sh`, which is a gate input for eleven rows and
would invalidate the CI evidence at `72bc84c`. It is registered as a Phase 2
item (§6.4) rather than smuggled into a renewal run, and no acceptance criterion
in Phase 1 requires it.

**Redaction.** The verifier's output names the deployment's resolved paths, its
supplementary group id and its pinned address. It contains no credential — it
never reads one — but none of those values belong in this document: §3.7 records
that the assertions held, not what they held against. Redact before pasting, or
return only the verdict lines and the identities.

**Do not** substitute CI's fixture paths for the deployment's, and do not change
a deployment setting to make an assertion pass. A failing assertion is a result.

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

### 6.3 CI execution (SW-P1-12) — **CLOSED at `72bc84c`**

**Status.** Three runs, by the procedure below, each with operator approval for
its specific push. The third passed.

| Run | Commit | Result |
| --- | --- | --- |
| <https://github.com/LordHorkos/scamwall/actions/runs/34036997074> | `2a18874` | failure — 20 passed, 1 failed. The log did not say why (FINDING-23). §3.8 |
| <https://github.com/LordHorkos/scamwall/actions/runs/34045148578> | `07154b6` | failure — 23 passed, 1 failed, 0 BLOCKED. The container gates PASSED; the log said exactly why the one gate failed (FINDING-27). §3.11 |
| <https://github.com/LordHorkos/scamwall/actions/runs/34047025567> | `72bc84c` | **success — 24 passed, 0 failed, 0 BLOCKED.** §3.12 |

SW-P1-12's acceptance criterion is met and was never amended. This section is
retained as the renewal procedure: the workflow is a gate input, so any change
to it demotes the row and the run is repeated.

The original narrative follows, unedited, because a record of how a row closed
is more useful than a record that it did.

A local `scripts/check.sh` run does not substitute — §3.0 is not evidence for
this row. It exercises the gate list, not the workflow, and says nothing about
`permissions:`, action pinning, the runner image, or fork-pull-request secret
handling.

**What now stands between this row and closure**, in the order the work has to
happen:

1. ~~**FINDING-23 (§4.9)**~~ — **DONE at `ef40156`.** A failing gate now reports
   its reason, its verdict and its cleanup result before any length limit, and
   the workflow uploads the complete sanitized capture as an artifact. §3.10
   demonstrates it end to end through `check.sh` itself.
2. ~~**The fixture decision**~~ — **DONE at `aa49797`: option A.** The reasoning
   is below, and it is not the reasoning originally anticipated — see "why A,
   and why not after step 1's evidence".
3. **A passing run** of the workflow at `aa49797`, recorded against its own
   commit. Not yet done, and nothing here substitutes for it.

#### Why A, and why the choice did not wait for the failure's cause

The plan in the previous revision was to fix step 1, re-run, read the verdict,
then choose. That is still the better order in general, and it was not followed
here for a reason that should be stated rather than glossed:

* **The old run's output is unrecoverable** (§3.8). Re-running to obtain it
  means pushing again, and a push is the one thing this work must ask for rather
  than take.
* **A local reproduction settled the part that actually decides between A and
  B** (§3.9). Under runner conditions the definition resolves two bind sources
  that cannot exist on a fresh runner, and `docker compose config` exits 0
  anyway. That is the fact option A exists to address, and it is now established
  by resolution rather than inferred from an outcome.
* **A independently fixes a false pass** (FINDING-25, §4.10) that has nothing to
  do with CI: a missing bind source becomes an empty directory and every mount
  assertion passes against it. That defect needed fixing whether or not CI ever
  ran, so the work was not contingent on the choice.
* **B was rejected on its merits, not for convenience.** Amending the acceptance
  criterion to "every gate that could run passed" would permanently exempt the
  container gates from the only independent host available, and SW-P1-12 exists
  precisely to check that two hosts agree. Option A costs a re-review of the
  workflow (done, §3.4); option B costs the requirement.

**What A does not do.** It does not make the CI run equivalent to §3.7. CI
builds its own image and mounts throwaway fixtures; the operator's run mounts
the real CA and the real password file. The two runs check the same properties
against different material, and the CI run is corroboration, not a substitute.

**What is still not confirmed, and is not being quietly closed:** *why* the run
at `2a18874` failed. The next run will say. If it says something other than the
absent bind sources, that is the answer and this section will record it.

#### The procedure, as approved and executed

Run once against `2a18874`. Recorded here because a procedure that was followed
is more useful than one that was proposed, and re-running it is how this row is
eventually closed.

**What the push triggers.** `.github/workflows/gates.yml` fires on
`push` to `main` or `feat/**`, on `pull_request`, and on `workflow_dispatch`.
The branch is `feat/phase-1-core`, so **the push alone starts a run** — no
second action is needed, and a pull request is not required to obtain the
evidence.

**Pre-push checks**, in order. Each one exists because of a specific way this
push could produce a misleading result. All four passed before the push:

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
#   66aff2e..2a18874  feat/phase-1-core -> feat/phase-1-core
#   PUSH exit=0
```

`--force` and `--force-with-lease` are deliberately absent. `main` was not
pushed, nothing was merged, and no tag was created.

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

#### The prediction, and how it actually turned out

Written before the push, so that it could be checked against the result rather
than constructed afterwards to fit it. **Outcome: the direction was right and
the cause is still unconfirmed.** The job failed and the runtime verification
reported `FAIL` rather than `BLOCKED` — but §4.9 means the log does not say why,
so the specific cause below remains a hypothesis. Recording it as "confirmed"
would be exactly the error this document is written to avoid: a prediction that
matches an outcome is not thereby shown to have matched the mechanism.

The prediction as written:

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

**This collided with SW-P1-12's acceptance criterion**, which reads "the hosted
run exists and **passes**". At `2a18874` it could not pass, so the push alone
did not close the row — and §3.8 bears that out. The options as they were
written before the push are retained verbatim, because the one that was taken
should be readable against the alternatives that were on the table rather than
presented alone:

| Option | What it costs | What it buys |
| --- | --- | --- |
| **A — materialise the fixtures in CI.** Add a workflow step before `check.sh` that writes a throwaway CA certificate and password file to those paths, and exports `SCAMWALL_SECRET_FILE` | Edits `.github/workflows/gates.yml`, which is a gate input: it demotes SW-P1-12's review evidence (§3.4) and needs the file re-reviewed | The strongest result — the container gates genuinely execute on a second, independent host, from a clean checkout. It also makes CI reproduce §3.7 rather than merely coexist with it |
| **B — let the container gates report `BLOCKED` in CI and amend the acceptance criterion** so SW-P1-12 closes on "the workflow ran, its gate list matched the local suite, and every gate that could run passed" | Requires amending a requirement to match an observation, which needs saying out loud rather than doing quietly | Closes the row honestly without touching a gate input. The container evidence stays where it already is — §3.7 |
| **C — push as-is first, and decide afterwards** | One red run on the record | Produces the run URL and tool-version output, and tests the prediction before anything is changed |

**C was done first** (§3.8), and it earned its place: it produced the run URL,
the tool versions, the demonstration that both hosts run an identical gate list,
an independent `docker build`, and FINDING-23 — which would otherwise have been
found much later, by someone trying to diagnose a red CI run and finding nothing
in the log. It did *not* confirm the cause above.

**A has since been done, at `aa49797`**, and the reasoning for choosing it
without the cause in hand is set out above under "Why A, and why the choice did
not wait for the failure's cause". Its cost was paid: `.github/workflows/gates.yml`
is re-reviewed property by property in §3.4, including the three new steps.

The prediction table below is retained unchanged, as written before the first
push. Its `SCAMWALL_CA_FILE` row is now out of date by construction — that
override exists as of `aa49797`, which is what option A added — and it is left
as it was rather than edited, because a prediction rewritten after the fact is
not a prediction.

**Reading the result — retained for the next run, once §4.9 makes the verdict
visible:**

| Outcome | Meaning |
| --- | --- |
| The runtime verification fails or blocks on missing host paths | The hypothesis above, then confirmed. An environment gap, not a defect, and no reflection on §3.7 |
| Every gate passes | The hypothesis was wrong and the runner supplied something unanticipated. Establish what before recording anything |
| It fails on a **hardening assertion** — a mount set, a bound, a pin | Do not treat this as a CI problem. It is a disagreement with §3.7 about builds of the same commit, and it takes precedence over closing this row |
| A non-container gate fails | The gate list disagrees between the two hosts. That is a reproducibility defect, which is what this requirement exists to detect. It did not happen in §3.8: all eighteen non-container gates passed on both |

**Reading the *next* run, at `aa49797`.** The table above was written for a
runner with no fixtures. The workflow now creates them, so the outcomes to
expect are different, and they are written down before the run for the same
reason as last time:

| Outcome | Meaning |
| --- | --- |
| Every gate passes | SW-P1-12's acceptance criterion is met. The container gates ran against a CI-built image with CI fixtures; that corroborates §3.7 from an independent host and does not replace it |
| `container runtime verification` fails, and the log now says why | The reason is what matters, and the log will carry it. If it names a missing or non-file mount source, the §3.8 hypothesis is confirmed at last — but for *this* run, not retroactively for that one |
| It fails on a **hardening assertion** — a mount set, a bound, a pin, the exact approved set | Still not a CI problem. A CI-built image and an operator-built image of the same source disagreeing about hardening is a finding that outranks closing this row |
| It fails on `the application password file is readable by every account on this host` | The fixture step's permissions are wrong, or `RUNNER_TEMP` is world-traversable in a way not anticipated. A CI defect, fixed in the workflow — never by relaxing the assertion |
| `compose definition under runner conditions` fails in CI but passes locally | The two Docker CLI versions resolve the definition differently. That is exactly the reproducibility question SW-P1-12 exists to ask, and the answer goes in this document before anything is changed |
| `gate diagnostics self-test` or its regression tests fail | The reporter behaves differently under the runner's `sed`, `grep` or locale. Until it is fixed, treat every other failure in the same run as possibly mis-reported |
| The `gate-diagnostics-*` artifact contains anything credential-shaped | Stop. That is a disclosure defect in the sanitizer and takes precedence over every other row here |

**Fork pull requests are not exercised by this push**, and the workflow's most
security-relevant property — that a fork PR receives no secret and a read-only
token — therefore remains reviewed rather than demonstrated. Closing that
properly needs a pull request from a fork, which is a separate, later step; it
is recorded here so the gap is not lost when SW-P1-12 goes green.

**Not authorised by this section:** pushing `main`, merging, opening or merging
a pull request, tagging, creating a release, publishing an image, or changing
any repository setting.

### 6.4 Phase 2 work order — **DRAFT, opens when SW-P1-05 closes**

Registered now so that Phase 1 evidence links forward and so that the scope is
fixed before implementation. Nothing here is authorised to run yet. Two
standing constraints apply to every item: **no household blocking state is
changed**, and **no live authenticated command runs until its own operator
procedure has been reviewed and recorded here**, on the model of §6.1.

| # | Work | Acceptance it must produce |
| --- | --- | --- |
| 1 | **Disposable Pi-hole integration tests.** A throwaway Pi-hole instance, created and destroyed by the test, never the household one. Procedure prepared at §6.6 — version pinning, isolation, cleanup and the assumptions it must confirm first — and **not executed** | A transcript naming the instance's identity and its teardown, and a control proving the test fails when the instance is absent rather than skipping |
| 2 | **Approved API methods and paths.** The allowlist in `docs/PIHOLE_API_CONTRACT.md` asserted against the client, not merely documented | A test that fails on any request outside the allowlist, including one issued through a redirect |
| 3 | **Session lifecycle and bounded retries.** Acquire, reuse, expiry, re-authentication, and a hard bound on attempts | Controls for each transition, and a demonstration that a failing endpoint cannot produce unbounded authentication attempts |
| 4 | **Credential-safe diagnostics.** Extends `scripts/gate-diagnostics.sh` to whatever Phase 2 logs | Decoy tests for the new shapes — session identifiers, cookies, `Authorization` headers — added to the existing eleven |
| 5 | **Runtime password readability.** The one thing §3.7 and §6.1 deliberately do not establish: that the container identity can *read* the mounted secret | A started container, in a disposable deployment, reporting a successful read without echoing the value. Not on the household deployment |
| 6 | **Destination and TLS verification through the configured pin.** That the address behind `pi.hole` is reachable, is a Pi-hole, and chains to the private CA | A recorded handshake through the real mapping, plus a negative control with the wrong CA |
| 7 | **Failure scenarios and compatibility scope.** Unreachable host, wrong password, expired session, malformed response, oversized response, slow-loris, and the Pi-hole versions claimed to be supported | One case per scenario, each asserting a named error rather than a generic one, and an explicit statement of the version range tested |
| 8 | **Revalidation of Phase 1 guarantees.** Phase 2 adds authenticated paths; the Phase 1 boundary must still hold | `enforcement compiled in false` re-asserted in the build, the read-only mount set unchanged, and `docs/REQUIREMENTS_MATRIX.md` §5 re-applied to every row whose gate inputs Phase 2 touches |
| 9 | **Carried forward from Phase 1.** The verifier asserts the supplementary group's *value*, not that the gid owns the password file (§6.1) | A host-side check that the secret's owning group is the configured gid, added with its own PRE-FIX CONTROL, and the affected rows renewed |
| 10 | **Carried forward from Phase 1.** A fork pull request receives no secret and a read-only token (§6.3) | A run triggered from a fork, showing the token's permissions and the absent secret |

Item 5 and item 6 are the two that require a live Pi-hole. Both stay pending a
reviewed operator procedure; neither is started by this session or by the
Phase 1 closure.

### 6.5 Operator handoff — **PENDING REVIEW AND EXECUTION**

Four steps, A to D, in order, plus a preflight and a close-out. **A is the
renewal SW-P1-05 has been waiting for.** B, C and D are Phase 2 evidence and
are *pending operator review and execution*: reading them is not authorisation
to run them, and none may be run until the operator has read what each does and
decided to. D additionally refuses to run without an explicit flag.

#### The procedure is a program, and the program is tested

The previous form of this section was about two hundred lines of shell for an
operator to paste into an interactive root shell. Nothing executed it before an
operator would have, so its defects were only discoverable against the
household Pi-hole — the most expensive place to find one. Eight of them were
found by reading it (§4.13), and they were not subtle.

It is now `scripts/operator-handoff.sh`, driven by
`scripts/tests/operator-handoff-test.sh` against a scripted fake Docker and a
scripted fake git: **308 cases, 0 failed**, no daemon, no network, no
appliance. Every refusal the procedure must make is reproduced there
deliberately, and where the defect is that the program *performs an action* the
case asserts against the fake daemon's own command log rather than against the
program's output. This section describes what each step does and how to read
its result; it does not restate the commands, because a second copy is a second
thing to get wrong.

#### Steps are ordered, and the order is enforced from recorded state

Each step records exactly one of six states in the work directory:

| State | Meaning |
| --- | --- |
| `not_started` | no record exists |
| `running` | the step began and has not recorded a verdict |
| `passed` | every required check ran **and** passed **and** cleanup completed |
| `failed` | a required check failed, could not run, or cleanup failed |
| `interrupted` | a signal arrived while the step was running |
| `indeterminate` | the step began and ended without recording a verdict — a refusal after it started, or a death. What it established is unknown, which is not the same as failed, and it is refused in those words |

A later step accepts **only** `passed`, and only when the identities the
earlier step recorded — source commit, image id, resolved-configuration
digest — match the ones this step is using. A prerequisite that passed against
a different image or a different resolved deployment configuration is reported
as **STALE** and refused.

A **rebuild invalidates every downstream acceptance before it runs**, together
with the previously recorded image id. That ordering is what makes a *failed*
rebuild safe: were it done on success only, a build that failed halfway would
leave the previous build's image id in place with the previous B/C/D passes
standing beside it, and the next step would create containers from an image no
step in this work directory had verified.

`--authorise-authenticated-read` is checked **in addition to** these
prerequisites and never instead of them. See FINDING-53.

A step's terminal record — its state, the identities it passed against, and the
values it publishes for later steps — is written by **one** replacement of
`state.env`. Whatever moment you look at that file, it is complete: there is no
window in which it says `passed` and does not yet say what against, and a step
killed at that instant leaves either the whole record or none of it. Each step
also has a **required** binding set; a recorded pass whose bindings are
missing, empty, unreadable or malformed is refused as an INCOMPLETE or CORRUPT
record rather than compared on whatever happens to be present. FINDING-57,
FINDING-58.

#### One step at a time, per work directory

A step takes an exclusive lock on `<work>/.handoff.lock` before it reads the
state file, and holds it until it exits. Running two steps in the same work
directory at once is refused, immediately, in these words:

```
REFUSING another invocation of this program is running in <work> and holds its
lock. Two steps sharing one work directory would read and write the same state
file with no ordering between them; wait for that step to finish, or give this
one its own work directory
```

That is not a queue. Wait for the running step to finish, or use a separate
work directory — and note that a separate work directory means a separate
`preflight`, because the state a later step reads is per-directory. The lock is
released when the process exits, including when it is killed; there is nothing
to clean up by hand. If you see this refusal and believe nothing else is
running, check for a step still executing in another terminal or under a
different `sudo` session before doing anything else. FINDING-59.

#### The work directory

| Path | What it is |
| --- | --- |
| `<work>/state.env` | identities and step states. Mode 600, owned by the running account, not a symlink, exactly one hard link |
| `<work>/.handoff.lock` | the exclusive lock that keeps two invocations out of one work directory. Created by the step, refused if it is a symlink, and released by the kernel if the step is killed. Nothing to return and nothing to remove by hand |
| `<work>/raw/` | **unsanitized** command output, exactly as the commands wrote it. It may contain credential material. **Do not share it.** Carries its own `README-DO-NOT-SHARE.txt` |
| `<work>/evidence/` | the same output through `scripts/gate-diagnostics.sh --sanitize`. **This is what to return.** The filter is deny-by-pattern: it establishes what its patterns catch, and nothing wider |

The directory itself is validated on every step, not merely created: see the
work-directory row of the table below, and FINDING-56.

The resource attribution and cleanup implementation is not a second one either.
It was extracted from `scripts/container-runtime-verify.sh` into
`scripts/lib/docker-resources.sh` and is **shared**, so the reviewed
behaviour — unpredictable invocation identifiers, per-invocation ownership
labels, deletion only by exact ID after re-verifying ownership, preservation of
anything not attributable, idempotent cleanup that runs on EXIT/INT/TERM and
counts toward the verdict — applies to both programs. The verifier's own suite
was re-run over the extraction: **358 cases, 0 failed**.

#### The expected checkout

The step-0 command takes `--expected-commit <40-hex-sha>`. **The value is
supplied with the handoff and is deliberately not written into this file.** A
SHA written here names a commit that does not yet exist at the moment of
writing: the commit that adds the line changes the file, so the object name it
claims is invalidated by its own recording. That is precisely what happened to
the previous form, which hardcoded `CANDIDATE=7e11419…` and would therefore
have refused the checkout it was written to describe.

Four identities are kept apart, because conflating them is what produced that
defect:

| Identity | What it is | Where it comes from |
| --- | --- | --- |
| **Expected checkout** | the commit the operator intends to verify | `--expected-commit`, supplied by the handoff |
| **Actual checked-out commit** | what `HEAD` is right now | `git rev-parse HEAD`, read as the tree's owner |
| **Embedded commit** | what the built artifact says it is | `--build-arg COMMIT=…`, read back out of the image by running `scamwall version` |
| **Historically covered commits** | commits an earlier evidence run described | §2.1, §3.12, §3.14 — never inferred from the current HEAD |

The program **refuses** when the actual commit is not the expected one, names
both, and does not move the tree. It re-checks source identity at the start of
**every** step: passing step 0 does not freeze the tree, and a step run against
a commit that moved would name the wrong source in its own evidence.

#### Common properties, and why each is there

| Property | Reason |
| --- | --- |
| Repository metadata is read **as the tree's owner** | `git` refuses to operate on another account's tree without a `safe.directory` exception, and adding one is a permanent widening for a momentary convenience. The owner is read from the directory, not assumed |
| Docker is used **only** through the operator | The service account has no socket access, deliberately. Nothing here asks for any |
| Every step stops on a failed precondition | A verification that continues past one is reporting on something other than what it names |
| No `docker compose up`, and no `docker compose run` for B–D | `up` starts the whole definition in one opaque step. `run` cannot pin the image, cannot remove the secret mount for a credential-free probe, and creates project resources whose attribution has to be reconstructed afterwards |
| Direct exit statuses are captured | A status read through `tee`, a pipeline or a monitor is the wrapper's, not the command's. FINDING-23 began as exactly this substitution, and the superseded procedure had reintroduced it |
| Log capture is a **separate** result from the command's status | "The build succeeded" and "the build log was written" are two facts. Conflating them lets an unusable capture read as a clean run |
| Temporary storage is `mktemp -d`, mode 0700 **set and read back** | A predictable path under `/tmp` created by root is a symlink target for any local account. `chmod` can fail, and an unchecked `chmod` is an assumption |
| The work directory is **validated**, not merely created | This runs under `sudo`. It must not be a symlink, must be owned by the account running the step, must be mode 700, and must have no ancestor another account can write without the sticky bit. The state file must additionally be a regular file, mode 600, with exactly one hard link. FINDING-56 |
| Raw captures and shareable evidence are **different directories** | The sanitizer's output is what may leave the host; the command's own output is not. Labelling the second as the first is FINDING-54 |
| A failed pre-start isolation assertion **prevents the start** | An assertion whose result is discarded is a report, not a control. FINDING-51 |
| A step's results are written **only if the step passed** | Which includes cleanup. An identity published by a step that failed is an identity no step verified. FINDING-52 |
| Prerequisites are read from **recorded step state**, never from a flag | `--authorise-authenticated-read` is the operator's intent. It is not evidence that steps A, B and C passed. FINDING-53 |
| Logs are **kept**, not erased | The work directory holds the evidence the operator has to return. The path and the removal command are printed instead |
| Existing deployment resources and secrets are preserved | Nothing here removes, rewrites, or reads the content of the real CA or the real password |
| Results are bound to exact source **and** image identities | An unbound result is a claim about no particular artifact |

**Do not repeat a step whose requirement has not changed.** If A passes and
nothing in the tree changes afterwards, B, C and D do not re-run A.

---

#### Step 0 — preflight

```
sudo scripts/operator-handoff.sh preflight --expected-commit <expected-checkout-sha>
```

It refuses unless: the expected commit is a full 40-character lowercase object
name; `HEAD` equals it; the tree is clean; git could actually answer both
questions; and none of `SCAMWALL_CA_FILE`, `SCAMWALL_SECRET_FILE`,
`SCAMWALL_CONFIG`, `SCAMWALL_FEED`, `SCAMWALL_IMAGE`,
`SCAMWALL_EXPECTED_IMAGE_ID`, `SCAMWALL_VERSION`, `SCAMWALL_COMMIT`,
`SCAMWALL_BUILD_DATE`, `PIHOLE_HOST_IP` or `SCAMWALL_SECRET_GID` is set in the
environment. Compose gives the shell environment precedence over `--env-file`,
so one of those still exported would silently redirect a bind **source** and
every step below would verify a fixture while reporting the deployment. The
variable is named; its **value is never echoed**, because a path in an evidence
log is an unnecessary disclosure and naming the variable is enough to fix it.

A git failure and a dirty tree are distinguished. "git could not tell us" is
reported as `source identity is UNKNOWN`, never as a mismatch and never as a
clean tree.

It also records the deployment secret's **baseline metadata** — owner, group,
mode, size, mtime — which is what step Z compares against at the end. No
credential is opened: this is `stat`, not a read. Where the secret cannot be
read from here, that is recorded rather than failed, because preflight requires
neither Docker nor the deployment; step Z then reports its comparison as
UNPROVEN instead of inventing a baseline. See FINDING-50.

**Record:** the work-directory path it prints. Every later step takes
`--work-dir <that path>`.

---

#### A — complete the pending Phase 1 deployment verification (SW-P1-05)

```
sudo scripts/operator-handoff.sh build --work-dir <work>
```

**What it does, in order.**

1. Re-checks source identity, then takes an unpredictable, length-checked
   invocation identifier and refuses if anything already carries its label.
2. Records what holds `scamwall:local` now — **for the record only**.
3. Builds with `--no-cache --pull --progress=plain` and explicit
   `--build-arg VERSION`, `--build-arg COMMIT=<expected checkout>`,
   `--build-arg BUILD_DATE`. The superseded procedure passed none of these, so
   the image it produced carried `commit=unknown` and could not be tied to a
   source at all.
4. Reports `BUILD exit=` from Docker itself, and reports the usability of the
   capture separately.
5. Checks the two in-build assertions **per build step**: it finds the step
   number from its header line, then examines that step's own lines. A build
   log that merely *contains* the text of an assertion proves nothing — the
   text is in the Dockerfile, so it appears whether the step ran or was reused.
   `CACHED` fails the step; so does a step that never reported `DONE`.
6. Resolves `scamwall:local` to an immutable image ID and validates its shape.
7. **Asks the artifact rather than the builder.** It creates a container from
   that exact image ID with no network, no mounts and no credential, verifies
   the created container's image identity *before starting it*, runs
   `scamwall version`, and requires the binary to report the expected commit
   and `enforcement compiled in false`.
8. Re-resolves the tag and fails if it moved during the step.
9. Runs `scripts/container-runtime-verify.sh` with **both** `SCAMWALL_IMAGE`
   and `SCAMWALL_EXPECTED_IMAGE_ID` set to that ID, so a tag moving between the
   two programs is a refusal rather than a silent substitution.
10. Requires the verifier's output to contain the line beginning `the
    application password would be readable by the container identity`. That
    line is the FINDING-29 evidence, it has never been produced against this
    deployment, and a verifier run that never emitted it has not produced it.

**What was removed, and why.**

* *"The new image ID must differ from the previous one."* Wrong. An image ID is
  the digest of the image's content, so a build producing identical output
  legitimately keeps the same ID — and reproducibility is a goal here, not a
  fault. The program notes an unchanged ID and does not refuse.
* *"A layer cached from an earlier candidate would produce an image that is not
  this source."* Wrong. The build cache is keyed on the build context, so cache
  reuse means the inputs were identical. `--no-cache` is used for a different
  and real reason: **the two in-build assertions are `RUN` steps, and a cached
  `RUN` step does not execute**, so it produces no evidence for this
  collection. `--pull` re-resolves the digest-pinned base image. Neither flag
  is a substitute for source identity or for a successful build, both of which
  are checked separately.

**If it fails:** the tag may still point at a stale image from an earlier
build. The program says so, and runs nothing against it.

**Record:** `BUILD exit`, `IMAGE_ID`, the binary's own reported commit,
`VERIFY exit`, the verifier's passed/failed/blocked counts, and the
FINDING-29 line, which prints `uid=`, `gid=` and `mode=` and no content.

**Do not proceed to B, C or D if this step's verdict is not `RESULT: every
check in this step ran and passed`.**

---

#### B — unauthenticated destination and TLS checks, with no credential

```
sudo scripts/operator-handoff.sh probe --work-dir <work>
```

**PENDING REVIEW.** What it establishes: that the address behind the `pi.hole`
pin is reachable from inside the container's mapping, that it presents a
certificate chaining to the mounted private CA, and that the certificate is
valid for the name `pi.hole`. What it sends: one `GET /api/auth`, which
`docs/PIHOLE_API_CONTRACT.md` **§3.4** documents as requiring no credential.
It does not authenticate.

**The contradiction this replaces.** The superseded step B stated "No password
is read and none is transmitted" and then listed, in its own expected-output
table, the line `ok application password readable, N bytes` — which is doctor
reporting that it had opened the password. It was not a wording slip: `doctor`
read `/run/secrets/pihole_app_password` unconditionally, before any network
check, so there was no way to run it credential-free at all.

Both halves are fixed:

* **The command cannot read it.** `doctor --no-credential` skips the read and
  reports the check as `SKIP`, not as a pass — a deliberately-not-performed
  check reported as `ok` would be read as evidence that the credential is
  fine, which is the opposite of what the flag establishes.
  `TestDoctorNoCredentialDoesNotOpenTheSecret` proves it, with a control that
  fails the same configuration *without* the flag.
* **The container has nothing to read.** The probe is created from the pinned
  image ID with the CA, config and feed binds and **no secret mount at all**,
  and the absence of `/run/secrets/pihole_app_password` is asserted on the
  created container *before it starts*. A claim that no password is read is
  worth much less than a container that has no password to read.

Nothing is hashed. Hashing the production secret is not needed to prove a step
is credential-free, and the superseded preamble did it in every case.

**Deliberate differences from the deployment**, both stated rather than
discovered: the probe attaches to the default bridge rather than a Compose
project network, and it mounts no secret. Everything else — the `65532:65532`
identity, the supplementary group, `read_only`, `cap_drop: ALL`,
`no-new-privileges`, the pids/memory/cpu bounds, the tmpfs, the three read-only
binds and the `pi.hole` address mapping — is **derived from `docker compose
config`**, which performs Compose's own interpolation, rather than re-derived
by reading `.env`.

The resolved bind sources are then checked against the deployment's real paths.
`assert_no_overrides` catches a redirection arriving through the environment;
this catches the same redirection arriving any other way, by checking the
result rather than the mechanism.

**Read the result like this:**

| Line in `doctor.log` | Meaning |
| --- | --- |
| `SKIP application password  NOT READ (--no-credential)` | This run opened no credential and makes no claim about one. Required; its absence fails the step |
| `ok certificate authority  loaded and parsed` | The mounted CA is a real, parseable certificate. Distinct from A, which only checked that the mount exists and is a regular file |
| `ok pi-hole connectivity  reachable over TLS; authentication required` | The destination answered, the chain verified against the private CA, and `pi.hole` matched the certificate. This is the `§6.4` item 6 evidence |
| `FAIL pi-hole connectivity … TLS verification failed` | The chain or the hostname did not verify. **Do not proceed to D.** The message is the diagnosis and carries no credential |
| `FAIL pi-hole connectivity … transport error` | Nothing answered at the pinned address, or the pin is wrong |

The negative control for the CA — that a *wrong* CA is refused — is exercised
by `TestTLSFailureWithWrongCA` and `TestHostnameMismatchIsRefused`, and is
deliberately **not** repeated against the live appliance: it would mean editing
the deployment, which this handoff does not do.

---

#### C — the container identity can open the mounted secret

```
sudo scripts/operator-handoff.sh secret --work-dir <work>
```

**PENDING REVIEW.** This is `§6.4` work-order item 5: the one thing A
deliberately does not establish. A judged the *metadata*; this performs the
*read*, under the real container identity, against the real mount.

It is a separate operation from B, not a line extracted from B's output. B is
about the network and must open no credential; C is about the credential and
must touch no network. The superseded section made C a `grep` over B's log,
which is why B could not be credential-free in the first place.

* **The network is disabled at the container level**, with `--network none`,
  and the created container's network mode is asserted before it starts.
  `doctor --offline` is a CLI flag that makes the program skip its connectivity
  checks; it is not an isolation boundary, and the superseded text treated it
  as one.
* It runs under the intended `65532:65532` identity with the configured
  supplementary group, both read from the resolved configuration.
* It opens the secret and prints **no content and no length**. The byte count
  the previous output carried has been removed from `doctor` entirely:
  `LoadSecretFile` already refuses an empty credential, so the length diagnosed
  nothing the pass/fail result did not, and a length is still a fact about a
  credential in an operator's log. `TestDoctorNeverReportsTheCredentialLength`
  keeps it out.

**What the two outcomes mean:**

* `ok application password readable` — the container identity can read the
  mounted secret. `§6.4` item 5 is satisfied, and FINDING-29's metadata
  judgement is corroborated by an actual read.
* `FAIL application password  open secret: … permission denied` — it cannot.
  If A passed its readability judgement and this fails, the two disagree, and
  that disagreement outranks either result. The likely causes are the ones A
  names as assumptions: an ACL, a user-namespace remap, or a rootless daemon.

**What protects the credential, stated accurately.** The superseded text said
"Nothing in ScamWall can print the value: `config.Secret` overrides every
formatting path, and a test counts the two places the plaintext is reachable at
all." That overstates what those controls do. What is actually reviewed and
tested:

* `config.Secret` overrides `String`, `GoString`, `Format`, `MarshalJSON`,
  `MarshalText` and `Redacted`, so the realistic leak — a struct containing a
  secret reaching `%v`, or being marshalled into a debug dump — yields a
  placeholder. `Format` covers `%x`, which would otherwise print the bytes.
* `Reveal` is the single escape hatch, and a test asserts it appears at exactly
  two call sites: building the authentication body, and setting the
  `X-FTL-SID` header. Both are the moment a credential goes on the wire.
* `Secret.Scrub` removes a value a peer echoed back, at the one call site that
  holds the password.
* `TestCredentialsNeverReachAnyStream` runs every command and asserts neither
  the password nor the session id appears on stdout, stderr or the audit
  stream, with both values generated per run so a match cannot be coincidence.

**Its limits.** A call-site count is a lexical property of this tree at this
commit; it constrains this code, not a future edit, and not a third-party
dependency. `Reveal` necessarily materialises an immutable Go string that
`Destroy` cannot wipe. `Scrub` compares against the plaintext and so
materialises a copy for the duration. The formatting overrides bind
`config.Secret`; a credential copied out into a plain `string` is outside all
of it. Taken together these are **reviewed protections with tests**, not a
proof that no code can disclose a credential.

---

#### D — one reviewed authenticated read-only operation

```
sudo scripts/operator-handoff.sh status --work-dir <work> --authorise-authenticated-read
```

**PENDING ITS OWN OPERATOR REVIEW, and the most consequential step here.** It
is the first time ScamWall authenticates to the household Pi-hole. The program
**refuses without the flag**, and the flag exists so that reading this section
cannot be mistaken for authorising the step. Do not run it until A, B and C
have passed and been read.

**What it may send, stated as it actually is.** The bound is the permitted
**set**, enforced in `do()` before the URL is built and again on every
redirect — not a request count. The superseded text said "exactly three
requests", which is true only when nothing is retried:

| Logical operation | Attempts | Notes |
| --- | --- | --- |
| `POST /api/auth` | 1 | Not retryable: Pi-hole rate-limits login and has finite session seats |
| `GET /api/info/version` | up to `1 + max_retries` (**3** by default) | Retryable on 429/500/502/503/504 and on transport failures |
| `DELETE /api/auth` | 1 | Not retryable; a 404 is already the desired end state |

Each of those may additionally follow **up to two** same-origin redirects,
whose method and path are re-checked against the same table and which are
refused outright if they carry a query string. With the shipped defaults the
worst case is therefore **15 HTTP requests**, every one to the pinned origin
and within the four permitted operations. If `Login` fails there is no session
and no logout, so that path is one logical operation.

**Session teardown, and the three claims that are not the same claim.**

`status` used to print `session closed` unconditionally whenever it returned
successfully. That was untrue on a real path: `WithSession` performs the logout
in a deferred call and deliberately does not let a logout failure mask the
caller's error, so a run whose `DELETE /api/auth` had **failed** still returned
`nil`, printed the success line, and exited 0. The failure was visible only as
a `pihole.logout_incomplete` warning in the audit stream.

`Client` now records the outcome it observed, and the command reports it:

| Observed | Printed | Exit |
| --- | --- | --- |
| DELETE accepted | `session logout ACCEPTED by Pi-hole`, with the qualification below | 0 |
| DELETE answered 404 | `session ALREADY ABSENT on Pi-hole` | 0 |
| DELETE failed | `WARNING: session logout FAILED` — the id is discarded locally so nothing can retry it, and a session may remain valid until it expires | **1** |

`TestAFailedLogoutIsNotReportedAsSuccess` covers the middle of those, including
that the successfully-read version data is still reported: the failure is about
cleanup, and saying which part failed is the point.

`ACCEPTED` is a fact about a **request**. It is not confirmation that the
appliance's session table no longer holds the session, and the printed line
says so.

**Independent confirmation is not available from here, and this is not a
promise that it is available elsewhere.** The superseded text instructed the
operator to look under *Settings → All settings → Web interface / API* for a
session attributed to the ScamWall user agent. **This repository has not
verified that menu path, or that Pi-hole attributes sessions by user agent, for
any Pi-hole version**, and has no way to: doing so means contacting an
appliance. ScamWall itself cannot ask — the endpoint that lists sessions is
outside the permitted set, and adding it to check up on ourselves would widen
this client's reach for a diagnostic.

The supported method proposed instead: D prints the Core, Web and FTL versions
it read. Take those, consult **that version's** own documentation for how
active API sessions are listed, and confirm there. If no supported method
exists for that version, record the outcome as *"teardown request accepted, not
independently confirmed"* — which is a smaller claim, and a true one.

**Do not** run `sync` in this step, even with `--dry-run`. It performs the same
authenticated operations *and* reads and reports the feed; keeping D to the
smallest authenticated operation means a failure has one candidate cause.

---

#### Step Z — close out

```
sudo scripts/operator-handoff.sh closeout --work-dir <work>
```

* **The deployment's secret.** Owner, group, mode, size and modification time
  are compared against the baseline **the preflight step recorded**, before any
  step of the handoff ran. That is what can be established without reading a
  credential, and it is reported as exactly that: it does **not** prove the
  content is unchanged, and a same-length rewrite with a restored mtime would
  pass it. A read that fails is a failure and does not end the step — the
  leftover enumeration below is the other half of closing out.

  Until `5af270d` this sentence was **not true of the code**. Nothing recorded
  the metadata earlier: step Z took its own baseline when it found none, printed
  "no earlier metadata was recorded", and reported `ok` — so on a single pass,
  which is the whole procedure, the comparison never happened and the step
  reported a pass for it anyway. That is FINDING-50. Where preflight could not
  read the secret, step Z now reports the comparison as **UNPROVEN** and fails,
  rather than establishing a baseline at the moment it is supposed to be
  checking one.
* **Optional content integrity**, with `--verify-secret-integrity`, off by
  default. **It reads the credential**, which is why it is opt-in and why it is
  not used merely to show that some other step was credential-free.
  `sha256sum`'s own exit status is checked *before* anything parses its output
  (a `cut` of a failed command's empty output is an empty string, and comparing
  two empty strings passes), the digest length is validated, the digest is
  compared and **never printed**, and any read or comparison failure is
  nonzero.
* **Leftovers of the steps that actually ran**, enumerated by the invocation
  and project identities **those steps recorded** — by both labels, per step,
  and named per step in the output. An enumeration that could not run is
  reported as `UNPROVEN` and fails the step; it is never answered "nothing
  remains". An **empty register is not a pass** either: if no step recorded an
  invocation in this work directory, step Z has nothing to search for and says
  so.

  Until this session this check was a **tautology that passed every time**.
  Step Z generated a new invocation identifier — refusing if anything already
  carried it — and then enumerated resources carrying that same brand-new
  label, so the query could not return anything. It printed `PASS  no container
  of this handoff remains` for every closeout that has ever run, whatever steps
  A to D had left behind, and the note beside it described the defect without
  recognising it: *"this step can only speak for its own"*. That is FINDING-55.
* **The logs are not deleted, and raw output is not labelled as evidence.** The
  work directory's path and the exact `rm -rf` command are printed. Erasing a
  failing run's diagnosis before the operator has read it is a defect, not
  tidiness — and so is telling the operator that unsanitized command output is
  a sanitized log, which is what the closing summary did until this session
  (FINDING-54). See *The work directory* above.

---

#### What this handoff does **not** authorise

Pushing, merging, opening or merging a pull request, tagging, releasing,
publishing an image, changing any repository setting, editing the deployment,
running `sync` against the live appliance, or enabling enforcement. Enforcement
is not compiled into this build, so the last of those is not merely
unauthorised — there is no binary that can do it.

### 6.6 Disposable Pi-hole integration procedure — **PREPARED, NOT EXECUTED**

`§6.4` work-order item 1. Everything in this repository that exercises the API
talks to a fake written from `docs/PIHOLE_API_CONTRACT.md`. If the appliance
diverges from that document, every test passes and the deployment fails. This
is the procedure that would close that gap, against a **throwaway instance**,
never the household one.

It has not been run. It is written now so that its scope is fixed before
anyone is tempted to improvise it at the moment they want the answer.

#### What it must not touch

The household Pi-hole, its configuration, its blocking state, its password, its
certificate, and port 53 on the host. A disposable instance that answered DNS
on the LAN would be worse than no test: it would silently become part of the
household's resolution path.

#### Unverified assumptions, to be confirmed before running

These are stated as assumptions rather than steps because they were not
verified from this account — there is no Docker daemon here and no access to a
registry — and a procedure that presents an unchecked belief as an instruction
is how a verification run produces a wrong answer confidently.

| Assumption | How to confirm |
| --- | --- |
| Pi-hole v6 (FTL) serves the API over HTTPS using a certificate read from `/etc/pihole/tls.pem`, as a combined key-and-certificate PEM | The chosen release's own documentation, before the instance is created. If the path or format differs, fix this document first |
| A `pihole/pihole` tag exists whose Core version matches the household's | Step D of `§6.5` reports the household's `core`, `web` and `ftl` versions. Choose the tag that matches `core`, and record it |
| The application password can be set at creation through an environment variable | The chosen release's documentation. Whatever the mechanism, the value must be generated by `head -c 32 /dev/urandom \| base64` and must never be the household password |

#### Version pinning

A test against "latest" answers a question about whatever was published that
morning. Pin twice:

```bash
# 1. Choose the tag matching the household's Core version, recorded by §6.5 D.
PIHOLE_TAG="pihole/pihole:<core-version-from-step-D>"

# 2. Resolve it to a digest and use the DIGEST from then on. A tag is mutable;
#    a digest is the artifact.
sudo docker pull "$PIHOLE_TAG"
PIHOLE_REF="$(sudo docker image inspect --format '{{index .RepoDigests 0}}' "$PIHOLE_TAG")"
echo "PIHOLE_REF=$PIHOLE_REF"
```

`PIHOLE_REF` is recorded with the result. A result that names only a tag is a
result about an unknown artifact, and `docs/REQUIREMENTS_MATRIX.md` §5 already
treats image identity that way for ScamWall's own image.

#### Isolation

| Resource | How it is isolated |
| --- | --- |
| Compose project | A dedicated project name, `scamwall-itest-<random>`, so every resource carries a label naming this invocation. Never the `scamwall` project |
| Network | A network created by that project and removed with it. The ScamWall container and the disposable Pi-hole join it and nothing else does |
| Ports | **None published.** ScamWall reaches the instance by its service name on the private network, so no port needs to leave it. In particular port 53 is not published, on any interface |
| DNS | The instance will answer DNS on its own network only. Nothing on the LAN can reach it |
| Trust material | A CA and a leaf for the name the test uses, generated into a `mktemp -d` at mode 0700 and destroyed with it. Not the household CA |
| Credential | Generated from `/dev/urandom` at creation, held only in the temporary directory at 0600, destroyed with it. Not the household password |
| Persistent state | None. No named volume and no bind mount of a host path for `/etc/pihole` or `/etc/dnsmasq.d`; the instance is created, used and discarded, so nothing survives to be picked up later |
| Host filesystem | Nothing outside the temporary directory is written |

#### What the run must establish

Each item is a comparison against the fake, not merely a success:

| Claim | Passing evidence |
| --- | --- |
| ScamWall authenticates to a real Pi-hole | `status` exits 0 against the instance, and the request sequence observed by the instance is exactly `POST /api/auth`, `GET /api/info/version`, `DELETE /api/auth` |
| The session is destroyed | The instance's own session list is empty afterwards |
| The response schema matches the contract | The version numbers ScamWall prints equal the ones the instance reports through an independent client |
| The failure modes are the documented ones | Wrong password, expired session, unreachable host, wrong CA, and a hostname mismatch each produce the named error, not a generic one |
| **The test fails when the instance is absent** | The control that matters. Run the same command with the instance removed and confirm it FAILS rather than skipping. A test that silently skips when its fixture is missing is indistinguishable from one that passes |

That last row is the acceptance criterion `§6.4` item 1 already states, and it
is the one most easily lost: an integration test that degrades to a skip is a
green result about nothing.

#### Cleanup, verified rather than assumed

```bash
sudo docker compose -p "$ITEST_PROJECT" -f <itest-compose-file> down --volumes --remove-orphans
# Each of these must print nothing.
sudo docker ps -a     --filter "label=com.docker.compose.project=$ITEST_PROJECT" --format '{{.Names}}'
sudo docker network ls --filter "label=com.docker.compose.project=$ITEST_PROJECT" --format '{{.Name}}'
sudo docker volume ls  --filter "label=com.docker.compose.project=$ITEST_PROJECT" --format '{{.Name}}'
rm -rf -- "$ITEST_WORK"; [ -e "$ITEST_WORK" ] && echo "ALERT: temporary material remains"
```

The image itself is left in place — it is not this invocation's resource, and
removing an image another deployment may reference is not cleanup.

#### What this procedure will still not establish

That the household Pi-hole behaves like the disposable one. They are different
installations with different configuration, and a divergence assessment against
a fresh instance is evidence about fresh instances. `§6.5` steps B, C and D
remain the only evidence about the appliance that is actually deployed.

---

## 7. Evidence status, item by item

Stated plainly so that nothing here is read as more than it is. Newly
established claims are listed alongside the outstanding ones, because a table
of only the gaps invites the reader to assume everything absent from it is
settled.

**Established at `b6b1769`, and what survives at `b6e70f4`.** `ef40156` and
`aa49797` change four gate inputs, so the image-bound rows below lapsed under
`docs/REQUIREMENTS_MATRIX.md` §5. `72bc84c` then restored two of them by running
the whole suite, including a build, on a hosted runner; `b6e70f4` changes
documentation only and restores nothing, because it invalidates nothing. Rows
are kept with the commit they were established at, because deleting them would
make the record look thinner than it is — but a row tied to `b6b1769` is
evidence about `b6b1769`.

| Claim | Basis | Carries to `b6e70f4`? |
| --- | --- | --- |
| The `b6b1769` image satisfies its runtime hardening assertions | §3.7 | **No.** The verifier and `compose.yaml` both changed; renew per §6.1 |
| The shipped binary carries no dynamic linking apparatus | §3.6 + §3.7 + §3.8 + §3.12 | **Both halves do, at `72bc84c`.** The controls are untouched and were re-run at `b6e70f4`; the image-bound half is re-established by the passing CI build, which executed the assertion on an uncached runner and produced `sha256:d7c44949…`. §3.12. No *operator-built* image exists from these commits — that is a second artifact for the same claim, not an unmet criterion |
| The gate suite's exit status matches its printed verdict | `CHECK exit=1` at `b6e70f4`, 22 passed / 0 failed / 2 BLOCKED. §3.0, re-run in §3.13 | **Yes, re-established directly on this tree** |
| The regression cases discriminate rather than agreeing with the code | §3.5, plus five new PRE-FIX CONTROLS at `ef40156`/`aa49797` (§4.9, §4.10) | **Yes** |
| The workflow runs on GitHub and runs the same gate list as the local suite | Runs 34036997074 (`2a18874`) and **34047025567 (`72bc84c`, passing)**. §3.8, §3.12 | **Yes.** The workflow file as it now stands ran and passed; `b6e70f4` does not touch it |
| The image builds, and its in-build assertions pass, on an unrelated host | CI `docker build` at `2a18874` (§3.8) and at **`72bc84c`** (§3.12), the latter in a run that passed end to end | **Yes, at `72bc84c`.** `b6e70f4` changes no build input, so it applies to this tree |

**Established at `7e11419`, by local evidence only.** Every claim in this block
rests on tests and gates run on this host, as `scamwall`, with no daemon and no
network beyond loopback. None of it has been through a hosted run, and the
published commit is still `72bc84c`.

| Claim | Basis |
| --- | --- |
| The client cannot issue a request outside the permitted set, and cannot be redirected to one | `PermittedOperations` enforced in `do` before the URL is built, and again in `CheckRedirect`. Nine forbidden (method, path) pairs refused against an origin nothing is listening on, so a refusal that came from the network rather than from the table would show as a dial error. §3.14, `internal/adapters/pihole/allowlist_internal_test.go` |
| A same-origin redirect to a forbidden path, or to a URL carrying a query string, is refused | Two tests against the local fake, each asserting the forbidden request was never recorded by the server. FINDING-31 |
| One deadline bounds a retried operation, retries and backoff included | `TestTotalTimeoutBoundsTheWholeOperationIncludingRetries`. FINDING-32 |
| A server's `Retry-After` is honoured and capped | `TestRateLimitRespectsRetryAfter`, plus an eleven-case table over both RFC 9110 forms including the overflow that was FINDING-33 |
| A rejected credential produces exactly one authentication attempt | Asserted at the adapter and again end to end through the CLI |
| No credential or session id reaches stdout, stderr or the audit log, for any of the six commands | `TestCredentialsNeverReachAnyStream`, with both values generated per run so a match cannot be a coincidence |
| A peer echoing a credential back cannot get it into an error | `TestAServerEchoingTheCredentialDoesNotLeakItIntoAnError` and its session-id counterpart. FINDING-37 |
| The approved read-only workflow performs three network operations, in order, **when nothing is retried** | `TestStatusPerformsExactlyTheApprovedSequence`, comparing an ordered list — a set comparison would accept a logout that happened first. **Corrected at the handoff session:** `GET /api/info/version` is retryable, so the real worst case with the shipped defaults is 15 HTTP requests, all within the permitted set. `TestStatusIsNotLimitedToThreeRequests` pins it. The bound that holds is the permitted set, not a count |
| An invalid configuration, or a missing credential, fails with ZERO network calls | Four configuration cases plus a missing-secret case, each asserting the fake server recorded nothing |
| Enforcement is refused with a server reachable | `TestEnforcementIsRefusedEvenWithAReachableServer`, so the refusal does not depend on the network being down |
| A syntactically valid mixed-script domain no longer destroys a signed feed, and does not thereby become eligible for blocking | `TestOneSuspiciousEntryNoLongerDestroysTheFeed` and `TestReviewEntriesAreWithheldWithoutBeingHidden`. SW-P3-05 |
| Unicode, a non-Latin script, and punycode alone change no blocking disposition | `TestUnicodeAloneIsNeverEvidence` |
| Domain normalisation is idempotent, deterministic, and bounded | Eight invariants over 1,406,144 fuzz executions, after FINDING-34 |
| The workflow declares the posture SW-P1-12 describes | `scripts/workflow-policy-check.sh`, thirteen negative cases and one positive. **Lexical only** — see the row below |

**Established at `b6b1769`:**

| Claim | Basis |
| --- | --- |
| The ScamWall container image satisfies its runtime hardening assertions | Image `sha256:b95cc07c…`, built from `b6b1769`: 90 passed, 0 failed, 0 blocked, 0 cleanup problems, `VERIFY exit=0`. §3.7 |
| The shipped binary carries no dynamic linking apparatus | The ELF checker and its controls pass (§3.6) **and** the assertion executed inside the `docker build` that produced that image (§3.7). Neither half suffices alone |
| Enforcement is not compiled into the shipped binary | The build's own assertion, executed in the same build. §3.7 |
| The gate suite's exit status matches its printed verdict | `CHECK exit=1` observed directly at `b6b1769`, with two gates BLOCKED on this host. §3.0 |
| The `b6b1769` regression cases discriminate rather than merely agreeing with the code | The `0b083cb` verifier fails 50 of the 319 cases. §3.5 |
| The workflow runs on GitHub, records its tool versions, and runs the same gate list as the local suite | Run 34036997074 at `2a18874`: versions identical to §2.2, gate list identical to §3.0. §3.8 |
| The image builds, and its in-build assertions pass, on a host unrelated to the operator's | `docker build` PASSED in CI on Ubuntu 24.04.4 with Docker 28.0.4, at `2a18874` (§3.8) and again at `07154b6` (§3.11). Corroborates §3.7 from a second host |
| The container hardening assertions hold on a second, independent host | `container runtime verification` PASSED in runs 34045148578 and 34047025567, against CI-built images with CI fixtures, including the three assertions added at `aa49797`. The passing run names the image: `sha256:d7c44949…`. §3.11, §3.12. **It does not renew SW-P1-05** — CI resolves a different deployment, with `group_add: 65532` rather than the operator's `989`, throwaway fixtures rather than the real CA and password, and an image built on the runner. It *does* close SW-P1-20, whose assertion is about the executable and reads none of those. §3.12 |

**Established at `9ebb98c`, by local evidence only.** Same
conditions as the block above: this host, as `scamwall`, no daemon, no network
beyond loopback. §3.15.

| Claim | Basis |
| --- | --- |
| `doctor` can perform a connectivity and TLS check without opening the application password | `doctor --no-credential` skips the read and reports `SKIP`, never `ok`. `TestDoctorNoCredentialDoesNotOpenTheSecret`, with a control asserting the same configuration FAILS without the flag — without that control the test would pass for a doctor that read the credential anyway |
| `doctor --offline` is not a credential-free command | `TestDoctorOfflineStillReadsTheSecret`. Recorded because the `§6.5` step C rationale and a Dockerfile comment both asserted the opposite |
| No command reports the credential's length | `TestDoctorNeverReportsTheCredentialLength`, which also asserts the literal length value is absent |
| A failed session teardown is never reported as success | `Client` records a `Teardown` outcome and `status`/`sync` report which they observed. `TestAFailedLogoutIsNotReportedAsSuccess` asserts a nonzero exit, the absence of any "accepted" claim, that the successfully-read version data is still reported, and that the DELETE was in fact attempted. `TestALogoutAnswered404IsTheDesiredEndState` covers the third outcome |
| `status` is not bounded to three requests | `TestStatusIsNotLimitedToThreeRequests`: the fake answers 503 twice and the observed sequence is five requests, all within the permitted set |
| The operator procedure refuses an unexpected HEAD, a dirty tree, an unreadable tree, and a fixture redirection arriving by either route | `scripts/tests/operator-handoff-test.sh`, 141 cases against a scripted fake `docker` and a scripted fake `git`. §3.15 lists the covered failure modes. **Superseded at `5af270d`:** the suite is now 167 cases, and two of the additions cover defects this row did not — FINDING-49 and FINDING-50, §4.14. **Superseded again by the Order-1 session:** the suite is 308 cases, and this row covers only the refusals it names. The six defects of §4.15 were outside it |
| A step whose isolation assertion failed does not start its container | Four cases in §4.15, asserting `^start` is absent from the **fake daemon's own command log** rather than that the program complained. Reverting the gate produces 8 failures. FINDING-51 |
| A step that did not pass publishes no identity, and no later step runs off one | Five cases covering a failed build, a failed verifier, a failed cleanup, an interruption and a post-start refusal — each asserting both the recorded step state and the next step's refusal. FINDING-52 |
| Step D does not authenticate on the strength of its authorisation flag | Five cases: a missing, failed, interrupted, indeterminate and stale prerequisite, each asserting no `start` reaches the fake daemon. FINDING-53 |
| The shareable evidence directory retains no credential-shaped value the sanitizer catches | The raw capture is asserted to **contain** the synthetic value and the evidence copy to not. This is bounded by the filter being deny-by-pattern, which the evidence directory's own README states. FINDING-54 |
| Step Z reports leftovers of the steps that actually ran | Four cases, including a container whose removal was made to fail and which step Z must then find and attribute by step name. Before this the check could not return anything and passed every time. FINDING-55 |
| The privileged work directory and state file are validated | Nine cases: symlinked work directory at creation and at open, symlinked state file, hard-linked state file, wrong state-file mode, world-writable ancestor, sticky ancestor still accepted, foreign owner, symlinked capture file, symlinked `raw/`. **The ownership case uses a shimmed `id`**, because an unprivileged account cannot create a directory owned by someone else; that is weaker than the real condition and the case says so. FINDING-56 |
| Cleanup is installed before creation, is idempotent, preserves what it cannot attribute, distinguishes a failed enumeration from an empty one, and counts toward the verdict | The reviewed implementation, now shared as `scripts/lib/docker-resources.sh`. Its behaviour is unchanged over the extraction: the verifier's suite re-ran at **358** cases, 0 failed, including a new case asserting the verifier REFUSES to start if the library is absent |
| A `SIGTERM` mid-run removes what was created and exits 143 | An interruption case in the handoff suite, delivered at the one moment a container exists |
| A failing step's diagnostics carry no password-, session-id- or PEM-shaped value, and the logs survive for the operator to return | Four assertions in the redaction case, plus retention assertions on the work directory (mode 700) and the captured log (mode 600) |

**Established at `5af270d`, by local evidence only.** Same conditions: this
host, as `scamwall`, no daemon, no network beyond loopback. §3.16.

| Claim | Basis |
| --- | --- |
| Every shell program under `scripts/` is tracked executable, the working tree agrees with the index, and everything under `scripts/lib/` is non-executable | `scripts/tests/entrypoint-mode-test.sh`, 56 cases, run as a gate. The **tracked** mode is what is asserted: a local `chmod` leaves every clone broken while making the checkout look correct |
| Every direct invocation the documentation names can actually be exec'd | The same suite execs each entry point with a side-effect-free help path and asserts against `exit 126` specifically, with Docker, Compose and `go` shimmed to record and fail so that "no daemon was contacted" is asserted rather than assumed. `check.sh` and `make-test-feed.sh` are excluded, for stated reasons, and keep the mode assertions only |
| A PEM's body does not reach a gate log, at any line length | The stateful range rule in `scripts/gate-diagnostics.sh`, with four cases in `scripts/tests/gate-diagnostics-test.sh` and one in the reporter's own `--self-test`, all driven through the real `--report` path. A PRE-FIX CONTROL applies the superseded three-rule set to the same fixture and asserts it leaks |
| An unterminated PEM block does not swallow the diagnosis | Asserted directly: the failure line, the verdict and the pass/fail counts all survive a range left open to end of input, because none of them is a pure-base64 line |
| A re-run of step A repins every later step to the new image | `rebuild-repins`: two builds of different images into one work directory, then the probe container's image read from the **fake daemon's recorded `create` arguments** rather than from the program's own output. Reverting `state_put`/`state_get` produces 6 failures |
| Step Z compares the secret against a baseline recorded before the handoff, and reports UNPROVEN when there is none | Eleven cases, including the branch the defect lived in — a metadata read that *succeeds* with no baseline recorded — reached with a `stat` shim scoped to the secret path. Reverting the preflight change produces 8 failures |
| A step that could not perform its check does not report a pass for it | The FINDING-50 fix, asserted by `expect_no_output` on both superseded success lines and by a state-file assertion that step Z writes no baseline of its own |

**Still not established:**

| Claim | Status |
| --- | --- |
| The image built by the operator from `b469c59` is verified | **Not established, and superseded.** `sha256:d3c4ed2c…` is an identity on record. No verifier ran against it, and it predates all seventeen findings in §4.7 and §4.8. Do not deploy or cite it |
| CI passes | **ESTABLISHED.** Run 34047025567 at `72bc84c`: **24 passed, 0 failed, 0 BLOCKED**, `RESULT: all required gates passed`, gate list identical to the local suite's. §3.12. Two earlier runs failed and are retained: 34036997074 (§3.8) and 34045148578 (§3.11) |
| `bind.create_host_path: false` is honoured by the runner's Compose | **Not established, and known to be unknown.** The runner has Compose v2.38.2, which omits the field from rendered output, so it cannot be observed there; the CI fixtures existed, so nothing would have been auto-created either way. The load-bearing defence against FINDING-25 is the verifier's host-side regular-file check, which does not depend on Compose and passed on the runner. §4.11 |
| Why the CI runtime verification failed | **Not established, and not recoverable from that run.** The run has no artifacts and its log holds exactly the twenty-five lines `head -25` kept (§3.8). The precondition for the predicted cause IS now established — under runner conditions the definition resolves two bind sources that cannot exist there, and `docker compose config` exits 0 anyway (§3.9) — but a demonstrated precondition is not a demonstrated mechanism, and this row stays open until a run says so itself |
| A red CI run can be diagnosed from its own log | **Established, and observed on a runner.** FINDING-23 is fixed at `ef40156`; run 34045148578 printed the failing gate's reason, its complete sanitized output inside a `::group::`, and the path of a retained artifact that uploaded successfully. §3.11. The failure it reported — FINDING-27 — was diagnosed and fixed from that log alone, and the next run passed |
| A fork pull request receives no secret and a read-only token | **Not established.** Reviewed in §3.4, and now also asserted *lexically* by `scripts/workflow-policy-check.sh` (FINDING-30) — which establishes what the workflow SAYS, not what GitHub DOES. Demonstrating the latter needs a pull request from a fork. §6.3, §6.4 item 10 |
| The gate suite passes on a hosted runner at `5af270d` | **Not established.** The published commit is `72bc84c`; run 34047025567 covers that tree and 24 gates. This tree has **26** gates, changed Go source, a changed Dockerfile comment, a shared script library, and three new scripts. It needs its own run after an approved push, and **the earlier run must not be relabelled as covering it.** §3.15, §3.16 |
| An image built from `9ebb98c` satisfies the runtime hardening assertions | **Not established.** No image has been built from this source on any host. SW-P1-05 and SW-P1-20 are both demoted; §6.5 step A is the renewal, and it has not been run |
| The container identity can read the mounted secret | **Not established, and now closer.** The verifier judges from host metadata whether the permission check WOULD grant the read, and states three assumptions it cannot check from metadata alone (FINDING-29). An actual read still needs a started container: §6.5 step C, which is written, tested against a fake daemon, and **unexecuted** |
| The operator handoff behaves correctly against a REAL Docker daemon | **Not established — and this row has now carried EIGHT defects that had nothing to do with a daemon.** FINDING-49 and FINDING-50 were fixed at `5af270d` (§4.14). FINDING-51 to FINDING-56 were found and fixed in the Order-1 session (§4.15): a failed isolation assertion did not prevent the start, a step published its identities before it had a verdict, the authorisation flag was accepted as proof of the prerequisites, the "sanitized logs" were the raw captures, step Z's leftover check was a tautology that passed every time, and the privileged work directory and state file were not validated. All eight were found by reading the program and reproduced without a daemon. **The pattern is the finding:** "pending operator testing against a real daemon" was standing in for defects that never needed one, and it should not be read as a queue of things only a daemon can settle. The **residual** is genuine runtime evidence: 308 cases against a scripted fake establish control flow, refusals, attribution, cleanup, state handling, evidence separation and step ordering. They do not establish that the arguments the program constructs are accepted by a real daemon, that `docker create` produces the container those arguments describe, or that the deployment's paths exist and are mountable. Only steps A–D can establish those, and they are pending operator execution |
| `docker --add-host` accepts what the resolved configuration yields | **Established for the shape, not for the daemon.** The installed Compose renders `extra_hosts` as `["pi.hole=host-gateway"]`; the program normalises the `=` to the `:` form and a case cross-checks the filter against the real Compose CLI. Whether the daemon then maps the name as intended is observable only in step B |
| A session created by ScamWall is confirmed absent from the appliance afterwards | **Not established, and no method for it is claimed.** ScamWall cannot ask: the endpoint that lists sessions is outside the permitted set. The superseded procedure named a Pi-hole UI path and a user-agent attribution that **this repository has never verified for any version**. §6.5 step D now states the limitation and proposes consulting the appliance version's own documentation, recording *"request accepted, not independently confirmed"* where no supported method exists |
| The diagnostics filter catches every credential shape | **Not established, and the previous wording of this row was wrong.** It described a PEM's short final body line surviving the 40-character threshold as a *limitation*. It was a **leak**, reachable through the real `--report` path, and it is FINDING-48 — fixed at `5af270d` by a stateful rule that redacts a PEM's body between its markers whatever the line length, with a PRE-FIX CONTROL asserting the superseded rules leaked it. §4.14. What remains is the true limitation: the filter is deny-by-pattern, so it establishes what its patterns catch, and a credential of an unanticipated shape would pass through it. That is no longer standing in for a known leak |
| The domain policy separation is accepted | **Not claimed.** SW-P3-05 is implemented and locally tested at `7e11419`; its acceptance belongs to Phase 3, which has not begun |
| The four fuzz targets show these paths are free of defects | **Not established, and not claimed.** Four bounded campaigns found two real defects and then stopped finding things. That is evidence about the inputs those runs reached and about nothing else. Durations and execution counts are recorded in §3.14 precisely so the claim cannot be inflated later |
| The CI fixtures never enter an image or a log | **Established by construction and by test, and the step has now run.** `scripts/tests/compose-fixture-test.sh` asserts the fixture paths lie outside the resolved build context and that the password fixture is not world-reachable; run 34045148578 created them 0600 in a 0700 directory, echoed only `ls -l` metadata, and removed them in a step that re-tests before reporting success. §3.11 |
| The uploaded gate diagnostics contain nothing credential-shaped | **Established for eleven decoy shapes, on the retained artifact as well as the log** (§4.9), and one artifact has now actually been produced and uploaded (792 bytes, §3.11). That is a deny-by-pattern filter, so it establishes what those patterns catch and nothing wider. A credential of an unanticipated shape would pass through it |
| The container identity can read the mounted secret | **Not established, and `aa49797` does not change it.** The verifier now checks that the password file is not readable by every account on the HOST (FINDING-26) — the opposite question. A read-only mount at `/run/secrets/pihole_app_password` is a mount, not a successful read, and no container has been started |
| ScamWall can authenticate to a real Pi-hole | **Not established.** Only a fake HTTPS server has been exercised |
| The destination behind the `pi.hole` pin is reachable, is a Pi-hole, and passes TLS verification | **Not established.** §3.7 proves the pin is configured and applied exactly; nothing was sent through it. Phase 2 — §6.2 |
| The shell suites are deterministic to the standard set at `0b083cb` | **Partly established, and the row stays open.** §3.3 recorded 30 consecutive runs of the 319-case suite, 0 failures, against 500 runs for the 237-case suite. At `5af270d` the four shell suites were run five rounds each — 20 executions, 20 `rc=0`, counts identical (§3.16). **Repeated at the Order-1 session, for a handoff suite that grew from 167 to 308 cases:** five rounds again — 20 executions, 20 `rc=0`, `358 / 308 / 73 / 58` identical in every round. **Five is not thirty:** at five runs a one-in-fifty defect is missed about nine times in ten. What it establishes is that the counts did not drift and that the suite which nearly doubled this session is as stable as the three that did not change. The gap remains one of duration, not of method. A first attempt at the `5af270d` measurement was **discarded rather than reported** — two copies of the campaign were truncating one log — and the larger number it would have supported is not used |
| ScamWall detects scam domains accurately | **Not established, and not claimed.** `testdata/feed.json` is a synthetic fixture. It is evidence about signature verification and parsing, and about nothing else. Detection accuracy is Phase 4 and has not begun |

The last row is the one most easily misread, so it is stated twice: a signed
feed proves who wrote it. It says nothing whatever about whether the contents
are correct.

The row above it is the second most easily misread. §3.7 reports `0 failed`
against a real image, and it would be an easy step from there to "the
deployment works". It does not say that. The verifier never starts the
application: it establishes what the container *is*, not what it can *do*.
