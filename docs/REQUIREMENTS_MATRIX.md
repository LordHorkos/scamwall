# ScamWall Requirements Matrix

<!-- SPDX-License-Identifier: AGPL-3.0-only -->

This is the single source of truth for **what ScamWall must do** and **whether
that has been proven**. `docs/IMPLEMENTATION_PLAN.md` says how and in what
order; `docs/VERIFICATION.md` records the evidence each row points at.

Where an earlier document already states a fact in detail — the API contract,
the threat model, the security boundaries — this matrix links to it rather than
restating it. Restating creates two truths that drift.

---

## 1. How to read this document

### 1.1 Requirement IDs

`SW-P<phase>-<nn>`. IDs are **stable**: once assigned they are never reused,
renumbered, or recycled. A requirement that is dropped is marked `WITHDRAWN`
and kept, so that evidence referencing it stays resolvable.

### 1.2 Status vocabulary

Exactly one of:

| Status | Meaning |
| --- | --- |
| `VERIFIED` | Implemented **and** the required evidence has been produced and recorded in `docs/VERIFICATION.md`, tied to a specific commit. |
| `IMPLEMENTED-UNVERIFIED` | The code exists and is believed correct, but the required evidence has not been produced, or was produced against a superseded commit. |
| `MISSING` | Not implemented. |
| `BLOCKED` | Cannot be verified from this account or in this environment. The blocker and the exact operator command are recorded. |
| `WITHDRAWN` | Deliberately dropped. Retained for ID stability. |

`IMPLEMENTED-UNVERIFIED` is not a soft `VERIFIED`. A requirement whose evidence
predates a change to the code, dependencies, configuration, or artifacts it
covers is **demoted back** to `IMPLEMENTED-UNVERIFIED` until the evidence is
renewed. See §5.

### 1.3 What "evidence" means here

Evidence is a reproducible observation tied to an identity:

* the **source commit** the observation was made against;
* the **tool versions** that made it;
* where a container is involved, the **image ID** (not the tag);
* where configuration is involved, the **configuration identity**.

A conversational claim that something worked is *history*, not evidence. Rows
that rest on such claims are marked `IMPLEMENTED-UNVERIFIED` and say so.

---

## 2. Baseline

| Item | Value |
| --- | --- |
| Branch | `feat/phase-1-core` |
| Baseline commit | `2edb95a` — *fix(verify): rebuild runtime verification around checked operations* |
| Baseline tree | `546ad23` |
| Licence | AGPL-3.0-only |
| Current phase | Phase 1 |
| Enforcement | Not compiled in (`policy.EnforcementCompiledIn == false`; no `enforce` build-tag file exists) |

Full baseline detail, including tool versions and the gate transcript, is in
`docs/VERIFICATION.md` §2.

---

## 3. Phase 1 — Trustworthy verification

**Objective.** Establish checks that cannot lie, and an auditable baseline.

The governing rule for this phase: *a check that could not run has proven
nothing.* Every requirement below is written so that the absence of evidence is
visible rather than silently absent.

| ID | Requirement | Status |
| --- | --- | --- |
| SW-P1-01 | Container runtime verification is built from checked operations | VERIFIED |
| SW-P1-02 | Repository verification and operator Docker verification are separate programs | VERIFIED |
| SW-P1-03 | Every command and parse failure is checked explicitly | VERIFIED |
| SW-P1-04 | Assertions read only successfully captured structured output | VERIFIED |
| SW-P1-05 | Exact image identity and deployment settings are verified | BLOCKED |
| SW-P1-06 | Inspection resources are isolated; only this invocation's resources are removed | VERIFIED |
| SW-P1-07 | Regression tests cover the enumerated false-pass classes | VERIFIED |
| SW-P1-08 | Shell scripts pass ShellCheck as a required gate | VERIFIED |
| SW-P1-09 | An independent secret detector runs alongside the project-specific scanner | VERIFIED |
| SW-P1-10 | Critical Go paths are reviewed and the review is recorded | VERIFIED |
| SW-P1-11 | govulncheck results are handled by content, not by exit status alone | VERIFIED |
| SW-P1-12 | CI is reproducible, least-privilege, and records tool versions | VERIFIED as written, never executed |
| SW-P1-13 | Pre-existing functional, security, race, and offline-plan tests are preserved and rerun | VERIFIED |
| SW-P1-14 | The gate suite is deterministic: no gate passes or fails at random | VERIFIED |
| SW-P1-15 | The CLI's read-only guarantee is covered by a test | VERIFIED |

**Phase 1 is not complete.** Fourteen of fifteen requirements are verified;
SW-P1-05 is BLOCKED on Docker daemon access, and a blocked required gate means
the phase does not close. Operator commands: `docs/VERIFICATION.md` §6.1.

### SW-P1-01 — Runtime verification is built from checked operations

**Intended behavior.** `scripts/container-runtime-verify.sh` treats every
Docker operation as fallible. A failed operation produces `FAIL` or `BLOCKED`
and a nonzero exit; it is never indistinguishable from a satisfied assertion.

**Source.** `scripts/container-runtime-verify.sh`
**Tests.** `scripts/tests/runtime-verify-test.sh` §3, §4, §10
**Evidence required.** The regression suite passes, and each deliberate failure
injection yields a nonzero verifier exit.
**Dependencies.** None.
**Acceptance.** Every failure injection in the suite produces nonzero exit and
a report naming the failed operation.
**Status.** VERIFIED — `docs/VERIFICATION.md` §3.1.

### SW-P1-02 — Repository and operator verification are separate

**Intended behavior.** Repository-content checks use git and run as the
unprivileged service account. Docker checks talk to the daemon, are executed by
the operator, and **never invoke git** — so the operator needs no
`safe.directory` exception in a `scamwall`-owned tree, and the service account
needs no Docker group membership.

**Source.** `scripts/container-security-check.sh` (repository, uses git);
`scripts/container-runtime-verify.sh` (daemon, derives the repository root from
`BASH_SOURCE` and confirms it by required files)
**Tests.** `scripts/tests/runtime-verify-test.sh` §11 — the verifier is run with
a `git` on `PATH` that refuses every invocation, and must still succeed; a
static check asserts no git command appears outside comments.
**Evidence required.** Both assertions pass.
**Dependencies.** None.
**Acceptance.** Verification succeeds with a hostile `git`; `git` is never
executed.
**Status.** VERIFIED — `docs/VERIFICATION.md` §3.1.

### SW-P1-03 — Command and parse failures are checked explicitly

**Intended behavior.** `docker inspect`, `docker history`, `docker export`,
`docker create`, `docker compose create`, `docker compose ps`, and every `jq`
parse are checked. A `jq` failure is reported as a parse failure, never as
"the property is absent". Error text on a stream can never satisfy a pattern,
because assertions run over captured JSON rather than over command output.

**Source.** `scripts/container-runtime-verify.sh` — `assert_eq`, `assert_true`,
`assert_empty_list`, and the guarded capture sites.
**Tests.** `scripts/tests/runtime-verify-test.sh` §3 (failed operations), §4
(unparseable and empty JSON).
**Evidence required.** Each injected failure yields nonzero exit and a report
that names the operation, and no assertion is claimed as passed.
**Dependencies.** SW-P1-01.
**Acceptance.** As above, for inspect, history, export, create, and both
malformed and empty JSON.
**Status.** VERIFIED — `docs/VERIFICATION.md` §3.1.

### SW-P1-04 — Only captured structured output is evaluated

**Intended behavior.** Inspection output is captured to a file and its exit
status verified *before* any assertion reads it. Container inspection must be a
single-element JSON array before any field is read.

**Source.** `scripts/container-runtime-verify.sh` — `CJSON`/`IMAGE_JSON`
capture and the `jq -e 'type == "array" and length == 1'` gate.
**Tests.** `scripts/tests/runtime-verify-test.sh` §4.
**Evidence required.** `[]` and non-JSON both produce nonzero exit.
**Dependencies.** SW-P1-03.
**Acceptance.** As above.
**Status.** VERIFIED — `docs/VERIFICATION.md` §3.1.

### SW-P1-05 — Exact image identity and deployment settings

**Intended behavior.** The requested image is resolved to its immutable image
ID; the inspected container's `.Image` must equal that ID; and when
`SCAMWALL_EXPECTED_IMAGE_ID` is set the resolved ID must equal it. Deployment
settings — user, groups, capabilities, `no-new-privileges`, seccomp/AppArmor,
init, read-only rootfs, mount read-only-ness, prohibited mounts, tmpfs flags,
network mode, port bindings, and resource limits — are asserted against that
container.

**Source.** `scripts/container-runtime-verify.sh` — "image identity" and
"deployment container" sections.
**Tests.** `scripts/tests/runtime-verify-test.sh` §5 (identity), §6 (prohibited
mounts through `.Mounts`), §7 (thirteen hardening regressions).
**Evidence required.** Two distinct artifacts:
1. the regression suite against the scripted fake — *available now*; and
2. **a real run against a real built image, recording the image ID** — this is
   what makes the assertions statements about a deployable artifact rather than
   about a fixture.
**Dependencies.** Docker daemon access.
**Acceptance.** (1) and (2) both pass, and (2) records the image ID it ran
against.
**Status.** **BLOCKED** on (2). The service account cannot reach the Docker
daemon and, by operator decision, will not be granted it. Operator commands:
`docs/VERIFICATION.md` §6.1. (1) is VERIFIED.

### SW-P1-06 — Isolated inspection resources and scoped cleanup

**Intended behavior.** The verifier creates its inspection container under a
Compose project name private to the invocation, and removes only resources that
invocation created — including on failure and on interruption. A pre-existing
deployment container is never stopped, removed, adopted, or inspected in place
of the verifier's own.

**Source.** `scripts/container-runtime-verify.sh` — `VERIFY_PROJECT`,
`CREATED_CONTAINERS`, `cleanup`, `trap ... EXIT INT TERM`.
**Tests.** `scripts/tests/runtime-verify-test.sh` §2 (a failed create is not
masked by an existing container, and that container is neither adopted nor
removed) and §9 (cleanup scope, including mid-run failure).
**Evidence required.** The fake-Docker command log shows removal of exactly the
containers this run created, every `compose down` scoped to the private
project, and no reference to the pre-existing container.
**Dependencies.** SW-P1-01.
**Acceptance.** As above.
**Status.** VERIFIED — `docs/VERIFICATION.md` §3.1.

### SW-P1-07 — Regression tests for the false-pass classes

**Intended behavior.** Each historical false pass is reproduced deliberately
and asserted to produce a nonzero result. Required classes: failed create with
an existing container; failed inspect; failed history; failed export; failed
parsing; image mismatch; forbidden mounts; daemon unavailability; cleanup
safety.

**Source / Tests.** `scripts/tests/runtime-verify-test.sh`; wired into
`scripts/check.sh` as a required gate that needs no daemon.
**Evidence required.** All cases present and passing; the suite is a required
gate.
**Dependencies.** SW-P1-01 … SW-P1-06.
**Acceptance.** Every listed class has at least one case, and the suite runs on
every gate run as the service account.
**Status.** VERIFIED — `docs/VERIFICATION.md` §3.1. Coverage map in
`docs/VERIFICATION.md` §3.2.

### SW-P1-08 — ShellCheck as a required gate

**Intended behavior.** Every shell script in the repository is analysed by
ShellCheck. Findings are either fixed or suppressed inline with a written
justification. ShellCheck's absence is `BLOCKED`, never a silent skip.

**Source.** `scripts/check.sh` (gate), `scripts/*.sh`, `scripts/tests/*.sh`
**Tests.** The gate is its own test.
**Evidence required.** A clean ShellCheck run at a recorded severity and
version, and a demonstration that the gate fails when a script is broken.
**Dependencies.** None.
**Acceptance.** Gate present, passing, and failing on a deliberately broken
script.
**Status.** VERIFIED — `docs/VERIFICATION.md` §3.1. Clean over all 10 tracked
scripts at `--severity=style`. Two informational findings were false positives
(a function reached only through `trap`; a deliberately single-quoted regex) and
carry inline `disable=` directives with a written reason on the line above.

### SW-P1-09 — An independent secret detector

**Intended behavior.** A third-party secret scanner runs *alongside*
`scripts/secret-scan.sh`, not instead of it. The project scanner encodes
ScamWall-specific rules (forbidden paths, the Pi-hole password, private CA
material); the independent detector covers the generic credential shapes a
hand-written scanner will miss. Both are required gates.

The independent detector must cover **what would be published**: the commit
history, and the tracked/staged tree — not the operator's untracked local
material, which is governed by `.gitignore` and by the project scanner's path
denial.

**Source.** New: `scripts/independent-secret-scan.sh`, `.gitleaks.toml`
**Tests.** A positive-control case: a planted synthetic credential must be
detected.
**Evidence required.** A clean run over history and the publishable tree, with
tool version recorded; every allowlist entry justified in-file; and the
positive control detected.
**Dependencies.** None.
**Acceptance.** As above.
**Status.** VERIFIED — `docs/VERIFICATION.md` §4.2. gitleaks 8.30.0 over full
history and the `git archive` tree: clean. Positive control fires. Both
exploratory hits are dispositioned, one by a narrowly scoped and justified
allowlist entry.

### SW-P1-10 — Critical Go path review

**Intended behavior.** The following are reviewed, and the review is recorded
with a finding-by-finding disposition: credential handling; TLS configuration
and trust; destination pinning; redirect policy; proxy behavior; deadlines and
cancellation; response size limits; domain normalization; feed verification.

**Source.** `internal/config/secret.go`, `internal/config/config.go`,
`internal/adapters/pihole/client.go`, `internal/adapters/pihole/transport.go`,
`internal/domain/domain.go`, `internal/feed/feed.go`, `internal/audit/audit.go`
**Tests.** `internal/**/**_test.go` (109 test functions at the baseline);
notably `internal/adapters/pihole/guard_test.go` for the structural guards.
**Evidence required.** A written review in `docs/VERIFICATION.md` §5 naming
each area, what was checked, and the outcome — including areas found adequate.
**Dependencies.** None.
**Acceptance.** Every listed area has a recorded disposition; anything found
deficient has either a fix or an explicitly accepted finding.
**Status.** VERIFIED — the consolidated review is `docs/VERIFICATION.md` §5,
covering all nine areas with a stated disposition for each, including two
limitations carried forward to Phase 3.

### SW-P1-11 — govulncheck result handling

**Intended behavior.** The vulnerability gate decides from **result content**,
not from exit status alone. This matters because `govulncheck`'s JSON and SARIF
output modes exit `0` whether or not findings exist; a gate that trusts the
exit status in those modes reports a vulnerable dependency set as clean.

**Source.** `scripts/check.sh`
**Tests.** A case that feeds the gate a known-findings result and asserts the
gate fails.
**Evidence required.** The gate's decision procedure is documented, and the
"findings present but exit status 0" case is demonstrated to fail the gate.
**Dependencies.** None.
**Acceptance.** As above.
**Status.** VERIFIED — `docs/VERIFICATION.md` §4.3. `scripts/govulncheck-gate.sh`
decides from `finding` records, distinguishes them from the `osv` database
entries a clean scan also emits, and treats an unparseable stream as UNPROVEN.
Measured on this host: a module with 58 findings exits 3 in text mode and **0**
in JSON mode; the gate fails it either way.

### SW-P1-12 — Reproducible CI with constrained permissions

**Intended behavior.** CI runs the same gates as the local suite, with:
pinned action versions; an explicitly minimal `permissions:` block; recorded
tool versions in the run log; and **no secret exposure to untrusted
contributions** — meaning fork pull requests get no repository secrets and no
elevated token.

**Source.** New: `.github/workflows/*.yml`
**Tests.** The workflow is its own artifact; correctness is reviewed, not
executed here.
**Evidence required.** Workflow file present with the properties above, each
verifiable by reading it; and the local gate suite and CI gate list agree.
**Dependencies.** SW-P1-08, SW-P1-09, SW-P1-11.
**Acceptance.** As above. Actual CI execution is out of this environment's
reach and is recorded as such.
**Status.** VERIFIED as written, never executed — `.github/workflows/gates.yml`,
reviewed property by property in `docs/VERIFICATION.md` §3.4. No run has
occurred; pushing is outside the authorisation for this work.

### SW-P1-13 — Pre-existing tests preserved and rerun

**Intended behavior.** The functional, security, race, and offline-plan tests
that existed before this work continue to exist and to pass. Any intentional
behavior change is explained.

**Source / Tests.** All `internal/**/*_test.go`; `go test -race ./...`
**Evidence required.** A full `go test -race -count=1 ./...` transcript at the
current commit, plus `go vet`, `gofmt`, and `staticcheck`.
**Dependencies.** None.
**Acceptance.** All pass; no test deleted or weakened without an explanation.
**Status.** VERIFIED — `docs/VERIFICATION.md` §3.1.

### SW-P1-14 — The gate suite is deterministic

**Intended behavior.** A gate reports the same result for the same inputs. A
gate that fails at random is not a weaker gate — it is an untrustworthy one,
because the same nondeterminism that produces a spurious failure can produce a
spurious pass, and because a team that learns to re-run a red gate has stopped
reading it.

**Source.** `scripts/check.sh`, `scripts/tests/runtime-verify-test.sh`
**Tests.** Repeated execution of the full suite.
**Evidence required.** A recorded run count with zero unexplained variation,
and a root-cause record for any nondeterminism found and removed.
**Dependencies.** SW-P1-07.
**Acceptance.** No unexplained variation over a recorded number of runs.
**Status.** VERIFIED — root cause found, fixed, and guarded.
`docs/VERIFICATION.md` §4.1 records the whole chain: a `pipefail` +
short-circuiting `grep -q` race that inverted matches. It was a false FAIL here
and a false PASS elsewhere, including a 100%% false-clean in the secret scanner
for files above the pipe buffer.
`scripts/tests/pipefail-sigpipe-test.sh` now fails the build if the construction
returns. Determinism re-measured in `docs/VERIFICATION.md` §3.3.

### SW-P1-15 — The CLI read-only guarantee is tested

**Intended behavior.** The Phase 1 boundary is enforced at the command surface:
`sync --dry-run=false` is refused, `plan` performs no network access, and no
subcommand can mutate Pi-hole. At the baseline `cmd/scamwall` had no test file
at all, so this boundary rested on inspection alone.

**Source.** `cmd/scamwall/main.go`
**Tests.** New: `cmd/scamwall/main_test.go`
**Evidence required.** Tests covering the `--dry-run=false` refusal, the exit
codes, and the absence of an enforcement path.
**Dependencies.** None.
**Acceptance.** Tests present and passing.
**Status.** VERIFIED — `cmd/scamwall/main_test.go`, 15 test functions, all
passing. Detail in `docs/VERIFICATION.md` §4.4.

---

## 4. Phases 2–6 — forward requirements

These are registered now so that Phase 1 evidence can be linked forward, and so
that the scope of later phases is fixed before implementation begins. All are
`MISSING` until their phase opens. Each will be expanded to the same level of
detail as §3 when its phase is entered; the acceptance criteria below are
binding on that expansion.

### 4.1 Phase 2 — Verified read-only Pi-hole integration

*Entry:* Phase 1 verification accepted for the relevant source and artifacts.

| ID | Requirement | Status |
| --- | --- | --- |
| SW-P2-01 | The permitted API method/path set is defined and enforced, including authentication and session cleanup | IMPLEMENTED-UNVERIFIED |
| SW-P2-02 | TLS verification, destination pinning, redirect restriction, deadlines, bounded responses, and controlled proxy behavior are enforced | IMPLEMENTED-UNVERIFIED |
| SW-P2-03 | Bounded retries, cancellation, rate-limit handling, and credential-safe diagnostics | IMPLEMENTED-UNVERIFIED |
| SW-P2-04 | Secret permissions and access are verified **under the actual container identity** | BLOCKED |
| SW-P2-05 | A disposable Pi-hole integration environment exists, with a documented compatibility scope | MISSING |
| SW-P2-06 | Failure-path tests: correct and rejected credentials, invalid CA, wrong hostname, unavailable server, malformed responses, rate limits, interrupted execution | IMPLEMENTED-UNVERIFIED |
| SW-P2-07 | Operator commands for one controlled live read-only test, not started automatically | IMPLEMENTED-UNVERIFIED |

*Acceptance.* Read-only integration succeeds against the test environment;
approved live evidence is captured **without credentials or session tokens**;
no blocking-state mutation occurs; failure paths terminate within defined
limits; session cleanup is verified including its failure cases; permission and
compatibility assumptions are documented.

*Notes.* SW-P2-01 through SW-P2-03 and SW-P2-06 are largely implemented at the
baseline (`internal/adapters/pihole/`) and tested against a fake HTTPS server;
what is missing is evidence against anything real. SW-P2-04 is blocked for the
same reason as SW-P1-05.

### 4.2 Phase 3 — Trusted feeds, policy, and durable state

*Entry:* Earlier applicable gates pass.

| ID | Requirement | Status |
| --- | --- | --- |
| SW-P3-01 | Strict, versioned configuration and feed schemas | IMPLEMENTED-UNVERIFIED |
| SW-P3-02 | Key provisioning, rotation, revocation, sequence/freshness, expiry, and replay protection | MISSING |
| SW-P3-03 | An established signed-update design (e.g. TUF) is evaluated before any custom lifecycle protocol; the decision and its scope are recorded | MISSING |
| SW-P3-04 | Publisher provenance, review, withdrawal, and signing-key separation | MISSING |
| SW-P3-05 | Domain **validity** is separated from **maliciousness** classification; mixed scripts or Unicode alone never establish maliciousness | MISSING |
| SW-P3-06 | Exact-domain/subdomain semantics, duplicates, source conflicts, confidence rules, expiry, user exceptions, reason codes | MISSING |
| SW-P3-07 | Defined behavior for unavailable, stale, revoked, or invalid feeds, including effect on existing state | MISSING |
| SW-P3-08 | Bounded input processing; fuzzing of critical parsers and normalization | MISSING |
| SW-P3-09 | Atomic state updates, locking, corruption handling, schema migration, storage limits | MISSING |
| SW-P3-10 | Plans are versioned and deterministic, bound to feed, policy/configuration identity, destination identity, creation/expiry, actions, exclusions, and application preconditions | IMPLEMENTED-UNVERIFIED |
| SW-P3-11 | Tests for clock anomalies, interrupted writes, concurrent runs, oversized input, and recovery | MISSING |

*Acceptance.* Tampered, stale, replayed, malformed, and oversized inputs have
tested outcomes; trust changes and withdrawals have tested procedures; policy
precedence is explicit and deterministic; state survives tested interruption
without silently accepting corruption; documentation states that signing
establishes **authenticity only** and never implies detection accuracy.

*Known gap carried into this phase.* `internal/domain/domain.go` currently
rejects mixed-script labels inside `Normalize`, and a rejected record makes the
whole feed fail to load. That conflates "this name is not a valid domain" with
"this name is suspicious", which SW-P3-05 forbids. The homograph signal must
become a classification input with its own reason code, not a validity verdict.

*Plan binding gap.* `policy.Plan` at the baseline binds format version, feed
ID, manifest version, entries, and exclusions. SW-P3-10 additionally requires
binding to policy/configuration identity, destination identity, and creation
and expiry times, and requires application preconditions. Those fields do not
exist yet.

### 4.3 Phase 4 — Independent effectiveness evaluation

*Entry:* Feed and policy behavior stable enough for meaningful evaluation.

| ID | Requirement | Status |
| --- | --- | --- |
| SW-P4-01 | A versioned evaluation runner | MISSING |
| SW-P4-02 | Lawful data sourcing and redistribution constraints, documented | MISSING |
| SW-P4-03 | Evaluation labels independent of the feed under evaluation | MISSING |
| SW-P4-04 | Development data separated from held-out data; leakage controls and time boundaries documented | MISSING |
| SW-P4-05 | Dataset includes malicious, legitimate, uncertain, and internationalized domains | MISSING |
| SW-P4-06 | Precision, recall on the dataset, false-positive rate, feed delay, withdrawal delay, resource use | MISSING |
| SW-P4-07 | Sample sizes, uncertainty, label limitations, category-level results reported | MISSING |
| SW-P4-08 | Numerical acceptance thresholds proposed **and recorded** before the acceptance run and before final held-out results are inspected | MISSING |
| SW-P4-09 | Uncertain labels treated explicitly, never folded into a favorable category | MISSING |

*Acceptance.* Reproducible from recorded inputs; predeclared thresholds
assessed honestly; failures lead to remediation and a **fresh** evaluation
procedure; synthetic fixtures are never presented as real-world accuracy
evidence.

*Standing constraint.* `testdata/feed.json` is a synthetic fixture. It is
evidence about parsing and signature verification. It is not, and must never be
cited as, evidence about detection accuracy.

### 4.4 Phase 5 — Operational read-only pilot

*Entry:* Earlier gates pass and evaluation supports proceeding.

| ID | Requirement | Status |
| --- | --- | --- |
| SW-P5-01 | Pilot scope, observation period, stop conditions, and operator responsibilities defined **before** launch | MISSING |
| SW-P5-02 | Scheduling with overlap prevention, bounded retries, and cancellation | MISSING |
| SW-P5-03 | Healthy, stale, degraded, authentication-failed, and disabled states are distinguished | MISSING |
| SW-P5-04 | Bounded logs and storage; sensitive fields redacted; retention documented | IMPLEMENTED-UNVERIFIED |
| SW-P5-05 | DNS query history is not collected by default | MISSING |
| SW-P5-06 | Tests for restart, power interruption, clock issues, feed outages, credential rotation, and application upgrades | MISSING |
| SW-P5-07 | Dependency/licence inventory and a release-evidence process tied to source and image | MISSING |
| SW-P5-08 | Safe installation, update, diagnostics, and recovery instructions | MISSING |

*Acceptance.* The agreed observation period and review volume are completed;
failures and incorrect proposals are measured and either resolved or explicitly
accepted; no Pi-hole blocking-state changes occur; operational resource and
privacy requirements hold.

### 4.5 Phase 6 — Controlled enforcement

*Entry:* Phases 1–5 pass. **Household enforcement remains disabled pending a
separate review of concrete results.**

| ID | Requirement | Status |
| --- | --- | --- |
| SW-P6-01 | Enforcement is implemented and tested first against disposable Pi-hole instances | MISSING |
| SW-P6-02 | ScamWall-owned entries are tracked without assuming exclusive ownership of pre-existing user entries | MISSING |
| SW-P6-03 | Plan expiry, target identity, policy/feed identity, and observed-state preconditions are rechecked immediately before applying | MISSING |
| SW-P6-04 | Absolute and proportional change limits are enforced | MISSING |
| SW-P6-05 | Operations are journaled and partial success is reconciled | MISSING |
| SW-P6-06 | Repeated application is idempotent | MISSING |
| SW-P6-07 | Concurrent user changes are detected | MISSING |
| SW-P6-08 | Conditional rollback preserves later user changes and reports conflicts | MISSING |
| SW-P6-09 | Interruption between every meaningful mutation step is tested | MISSING |
| SW-P6-10 | Disable, uninstall, and recovery remove **only** attributable changes | MISSING |
| SW-P6-11 | Stale-feed behavior for previously applied entries is defined | MISSING |
| SW-P6-12 | A limited deployment proposal with exact changes, limits, monitoring, and rollback commands | MISSING |
| SW-P6-13 | The structural guards are widened to cover every package that can reach the network | MISSING |

*Acceptance.* Mutation and recovery tests pass in isolated environments; no
user-managed change is overwritten or removed improperly; partial failures
leave understandable, recoverable state; all earlier applicable gates pass
against the enforcement candidate; the operator reviews the concrete deployment
proposal before any live enforcement.

*Structural note.* The Phase 1 design deliberately makes enforcement
*absent* rather than *disabled*: there is no `enforce`-tagged file, so
`go build -tags enforce` fails rather than producing an enforcing binary.
Phase 6 must introduce that file, and doing so is itself a change that demotes
every Phase 1 and Phase 2 row to `IMPLEMENTED-UNVERIFIED` until re-run.

*Guard-scope note (SW-P6-13).* `TestNoMutatingEndpoints` scans only
`internal/adapters/pihole/`, which is correct today because that package is the
only one able to make an HTTP request. Phase 6 changes that. The guard must be
widened in the same change that grants any other package network access — not
afterwards. See `docs/VERIFICATION.md` §5.11.

---

## 5. Evidence renewal rule

An earlier phase's evidence is **not** permanent. A row returns to
`IMPLEMENTED-UNVERIFIED` when any of the following changes in a way that
touches it:

| Change | Rows demoted |
| --- | --- |
| Go source under `internal/` or `cmd/` | Every row whose Source lists that file, plus SW-P1-13 |
| `go.mod` / `go.sum` / toolchain | SW-P1-10, SW-P1-11, SW-P1-13, SW-P5-07 |
| `container/Dockerfile` or `deploy/compose/compose.yaml` | SW-P1-05, SW-P1-06, and every container row |
| Any `scripts/*.sh` | SW-P1-01 … SW-P1-04, SW-P1-06 … SW-P1-09, SW-P1-11, SW-P1-14 |
| A rebuilt image (new image ID) | SW-P1-05, SW-P2-04 |
| Feed schema or trust key | SW-P3-01 … SW-P3-04, SW-P3-07 |
| Detection behavior | Every Phase 4 row |

Renewal means re-running the gate and recording a **new** entry in
`docs/VERIFICATION.md` against the new commit or image ID. Editing the old
entry's commit hash is not renewal.

The converse also needs saying, or the rule becomes unusable: **evidence is
tied to the last commit that changed a gate input.** A documentation-only
commit changes none, so the record carries forward rather than requiring a
re-run — otherwise writing down the evidence would itself invalidate it.

---

## 6. Requirements deliberately not held here

Two things belong elsewhere and are linked rather than duplicated:

* **API behavior and divergence** — `docs/PIHOLE_API_CONTRACT.md`. That
  document is the contract; this matrix only records whether the client obeys
  it.
* **Threats and residual risk** — `docs/THREAT_MODEL.md` and
  `docs/SECURITY_BOUNDARIES.md`. A threat is not a requirement; the control
  answering it is.
