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
| Session baseline | `2edb95a` — *fix(verify): rebuild runtime verification around checked operations* (tree `546ad23`) |
| Evidence commit | `b6b1769151501d89d7f8550d2c8f3378d0e73c3d` — *fix(verify): check list processing, name scope, mounts, numbers and fields* |
| **Verified image** | source `b6b1769151501d89d7f8550d2c8f3378d0e73c3d`, image `sha256:b95cc07ca564b115f8bf2d49d642efafc99ae8ff4ae7746caaa7d2ff5e00516b`, build exit 0 with both in-build assertions executed, verifier 90 passed / 0 failed / 0 blocked / 0 cleanup problems, `VERIFY exit=0`. Evidence: `docs/VERIFICATION.md` §3.7 |
| Superseded evidence commit | `0b083cb` — *fix(verify): attribute resources and complete the runtime assertions*. `b6b1769` changed `scripts/*.sh`, which demotes the rows §5 names; those were re-run and renewed |
| Superseded candidate image | source `b469c592ca756b82bc2eb18ee4cdcb42b9458a0c`, image `sha256:d3c4ed2c91250448044e1f1eb4e8d0d04591ba10237b3c56e5effc55f7e2251f`, build exit 0. **No verifier was ever run against this image**, and it predates all seventeen findings in `docs/VERIFICATION.md` §4.7 and §4.8. Retained as an identity on record for ID stability; it is not evidence and must not be deployed |
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
| SW-P1-03 | Every command, search and parse failure is checked explicitly | VERIFIED |
| SW-P1-04 | Assertions read only successfully captured structured output | VERIFIED |
| SW-P1-05 | Exact image identity and deployment settings are verified against a real image | VERIFIED |
| SW-P1-06 | Inspection resources are isolated; only this invocation's resources are removed | VERIFIED |
| SW-P1-07 | Regression tests cover the enumerated false-pass classes | VERIFIED |
| SW-P1-08 | Shell scripts pass ShellCheck as a required gate | VERIFIED |
| SW-P1-09 | An independent secret detector runs alongside the project-specific scanner | VERIFIED |
| SW-P1-10 | Critical Go paths are reviewed and the review is recorded | VERIFIED |
| SW-P1-11 | govulncheck results are handled by content, not by exit status alone | VERIFIED |
| SW-P1-12 | CI is reproducible, least-privilege, and records tool versions | BLOCKED |
| SW-P1-13 | Pre-existing functional, security, race, and offline-plan tests are preserved and rerun | VERIFIED |
| SW-P1-14 | The gate suite is deterministic: no gate passes or fails at random | VERIFIED |
| SW-P1-15 | The CLI's read-only guarantee is covered by a test | VERIFIED |
| SW-P1-16 | Cleanup is part of the verdict: it completes first, it is idempotent, and its failure is nonzero | VERIFIED |
| SW-P1-17 | Every resource is attributed to this invocation before it is deleted; pre-existing resources are preserved | VERIFIED |
| SW-P1-18 | One resolved Compose configuration drives creation, listing and expectation | VERIFIED |
| SW-P1-19 | The deployment's mounts are asserted exactly: presence, type, source, mode, no extras | VERIFIED |
| SW-P1-20 | Static linkage is proven by checked ELF inspection of the built artifact | VERIFIED |

**Phase 1 is not complete.** Nineteen of twenty requirements are verified at
`b6b1769`. One is BLOCKED, and it needs an operator action rather than more
code:

| Blocked | Needs | Operator procedure |
| --- | --- | --- |
| SW-P1-12 | one actual hosted CI run — the workflow executed on GitHub, with a run URL and log | `docs/VERIFICATION.md` §6.3, which now carries the exact push and trigger sequence, **proposed and awaiting approval; nothing has been pushed** |

A blocked required item means the phase does not close, however many of the
others are green. Nineteen-twentieths is not nineteen-twentieths of a closed
phase; it is an open phase.

**Closed since the previous revision**, both by the operator's run at
`b6b1769` against image `sha256:b95cc07c…` (`docs/VERIFICATION.md` §3.7):

| Was blocked | Closed by | Acceptance criterion met |
| --- | --- | --- |
| SW-P1-05 | the verifier run against a real built image: 90 passed, 0 failed, 0 blocked, 0 cleanup problems, `VERIFY exit=0`, image identity confirmed against the pin, container created and never started | both artifacts required by the row — the regression suite against the fake, and a real run recording the image ID |
| SW-P1-20 | the ELF linkage assertion executing inside a `docker build` that exited 0 | both parts — the controls pass (§3.6) *and* the assertion ran in a real build |

**Reconciliation of everything else claimed for Phase 1**, so that nothing is
carried on assumption:

| Item | State |
| --- | --- |
| `check.sh` exit status, requested directly rather than inferred from the printed verdict | **Obtained** at `b6b1769`: `CHECK exit=1`, with 19 passed, 0 failed, 2 BLOCKED. The status and the printed verdict agree. `docs/VERIFICATION.md` §3.0 |
| Evidence renewal after `b6b1769` changed `scripts/*.sh` | **Done.** §5 demotes SW-P1-01 … SW-P1-04, SW-P1-06 … SW-P1-09, SW-P1-11 and SW-P1-14 on any `scripts/*.sh` change; the suite was re-run at `b6b1769` and those rows rest on the new transcript, not the `0b083cb` one |
| The six defects fixed in `b6b1769` | **Recorded** as FINDING-17 … FINDING-22, `docs/VERIFICATION.md` §4.8, with the pre-fix comparison in §3.5 — the `0b083cb` verifier fails 50 of the 319 cases |
| Determinism (SW-P1-14) at the new suite size | **Partly renewed.** 30 consecutive runs of the 319-case suite at `b6b1769`, 0 failures — against 500 runs for the 237-case suite at `0b083cb`. Shorter by design and stated as such, not merged into one figure. `docs/VERIFICATION.md` §3.3 |
| Fork-pull-request secret handling | **Not demonstrated**, and not demonstrable by the proposed push. Reviewed only. It is registered in `docs/VERIFICATION.md` §7 so it is not lost when SW-P1-12 closes |
| Runtime password access, live authentication, destination connectivity and TLS verification through the `pi.hole` pin | **Not established, and out of Phase 1 scope.** Phase 2 — SW-P2-02 and SW-P2-04. `docs/VERIFICATION.md` §6.2 |

### SW-P1-01 — Runtime verification is built from checked operations

**Intended behavior.** `scripts/container-runtime-verify.sh` treats every
Docker operation as fallible. A failed operation produces `FAIL` or `BLOCKED`
and a nonzero exit; it is never indistinguishable from a satisfied assertion.

**Source.** `scripts/container-runtime-verify.sh`
**Tests.** `scripts/tests/runtime-verify-test.sh` — the *absence versus search failure*, *incomplete and malformed inspection data* and *daemon availability* case groups
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
**Tests.** `scripts/tests/runtime-verify-test.sh` — *no git dependency*: the verifier is run with
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
**Tests.** `scripts/tests/runtime-verify-test.sh` — *absence versus search failure* (failed operations and failed searches), *incomplete and malformed inspection data*
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
**Tests.** `scripts/tests/runtime-verify-test.sh` — *incomplete and malformed inspection data*.
**Evidence required.** `[]` and non-JSON both produce nonzero exit.
**Dependencies.** SW-P1-03.
**Acceptance.** As above.
**Status.** VERIFIED — `docs/VERIFICATION.md` §3.1.

### SW-P1-05 — Exact image identity and deployment settings

**Intended behavior.** The requested image is resolved ONCE to its immutable
image ID; that ID — never the tag — is used for image history and for creating
the filesystem-enumeration container; the inspected deployment container's
`.Image` must equal it; and when `SCAMWALL_EXPECTED_IMAGE_ID` is set the
resolved ID must equal it. Deployment settings — user, supplementary group,
capabilities, `no-new-privileges`, seccomp/AppArmor, init, read-only rootfs,
the exact mount set, tmpfs options, hostname pinning, network mode, port
bindings, log bounds and resource limits — are asserted against that container,
against values derived from the resolved configuration.

Compose creates from the tag written in the compose file, so the container's
recorded image is what detects a tag repointed between resolution and creation.
A difference is not assumed to be a mismatch: Docker's image stores do not all
record the same identifier for the same image, so the container's identifier is
re-resolved through the daemon and compared. Equivalence is accepted with both
identifiers reported; anything else fails. What each field means — `.Id` the
local image identifier, `.RepoDigests` registry manifest digests, a manifest
list a different identifier entirely — is printed rather than assumed.

**Source.** `scripts/container-runtime-verify.sh` — "image identity" and
"deployment container" sections.
**Tests.** `scripts/tests/runtime-verify-test.sh` — *image identity* (mismatch,
tag movement, equivalent identifier, malformed and non-digest identifiers, and
a log assertion that no image operation uses the mutable tag), *mounts*,
*tmpfs bounds*, *logging bounds*, *API hostname pinning*, *supplementary
group*, *hardening regressions*.
**Evidence required.** Two distinct artifacts:
1. the regression suite against the scripted fake; and
2. **a real run against a real built image, recording the image ID** — this is
   what makes the assertions statements about a deployable artifact rather than
   about a fixture.
**Dependencies.** Docker daemon access.
**Acceptance.** (1) and (2) both pass, and (2) records the image ID it ran
against.
**Status.** **VERIFIED** at `b6b1769`, on both artifacts:

| Artifact | Result |
| --- | --- |
| (1) regression suite against the scripted fake | 319 cases, 0 failed. The cases discriminate: the `0b083cb` verifier fails 50 of them — `docs/VERIFICATION.md` §3.5 |
| (2) operator run against image `sha256:b95cc07ca564b115f8bf2d49d642efafc99ae8ff4ae7746caaa7d2ff5e00516b`, built from `b6b1769` | 90 passed, 0 failed, **0 blocked**, 0 cleanup problems; `VERIFY exit=0`; the inspected container's image matched the pin; the container remained created and was never started; cleanup reported completion — `docs/VERIFICATION.md` §3.7 |

`0 blocked` carries as much weight here as `0 failed`. This verifier reports
"could not run" separately from "failed", and a run with no failures but
several unrun checks would satisfy the letter of the acceptance criterion while
proving much less than it appears to.

**Scope of the closure.** This row is about the container's *configuration as
built and created*. It is not evidence that the application runs, authenticates,
or reads its mounted secret — the verifier never starts it, deliberately, which
is what makes the check safe to run on a host carrying a live deployment. Those
are SW-P2-01 and SW-P2-04, both still open.

**Renewal.** Tied to that image ID and that commit. Any rebuild produces a new,
unverified image; §5 applies. The procedure is retained at
`docs/VERIFICATION.md` §6.1.

*Note on the earlier candidate.* The operator's build of `b469c592` produced
image `sha256:d3c4ed2c…`. No verifier was ever run against it and it predates
all seventeen findings in `docs/VERIFICATION.md` §4.7 and §4.8. It remains an
identity on record, is superseded by `sha256:b95cc07c…`, and must not be
deployed or cited as evidence for this row.

### SW-P1-06 — Attributable inspection resources and scoped cleanup

**Intended behavior.** Every resource this invocation creates is attributable
to it before it is deleted, and nothing else is touched.

* The invocation identifier is UNPREDICTABLE (128 bits from `/dev/urandom`),
  not `$$`. A PID is small, reused and guessable, so a stale resource could
  carry a colliding project name.
* Created resource IDs are recorded as they are created, and a per-invocation
  ownership label is applied through a Compose override, so a resource left by
  a partially completed creation is still attributable.
* A snapshot is taken BEFORE anything is created. Any resource already carrying
  the invocation's labels is a collision: nothing is created and nothing is
  deleted, and the ambiguity is reported.
* Removal is by exact ID after re-verifying the label. There is no
  `compose down -p <project>`: project-wide deletion trusts a name.
* Configuration features that escape project isolation — `container_name`,
  externally named networks, volumes or secrets, additional services — block
  the run before anything is created.
* A resource whose ownership cannot be established is PRESERVED and reported.

**Source.** `scripts/container-runtime-verify.sh` — `INVOCATION`,
`VERIFY_PROJECT`, the ownership override, `snapshot_kind`, `label_query`,
`owned_by_this_invocation`, `remove_owned`, `sweep`, `run_cleanup`.
**Tests.** `scripts/tests/runtime-verify-test.sh` — *resource ownership*
(container and network collisions, unrelated-resource preservation, partial
creation, a pre-existing container never adopted), *consistent Compose
configuration* (isolation-escaping features), *cleanup as a verdict*.
**Evidence required.** The fake daemon's command log shows removal of exactly
the resources this run created, every listing filtered by a label unique to
this invocation, no `compose down`, and no reference to any other resource.
**Dependencies.** SW-P1-01.
**Acceptance.** As above, plus: a collision blocks creation, and an
unattributable resource is preserved rather than removed.
**Status.** VERIFIED — `docs/VERIFICATION.md` §3.1. Behaviour against a real
daemon rode on SW-P1-05, which is now closed: the operator's run at `b6b1769`
reported 0 cleanup problems and cleanup completion against a real daemon, and
left the host's existing deployment untouched — `docs/VERIFICATION.md` §3.7.

### SW-P1-07 — Regression tests for the false-pass classes

**Intended behavior.** Each historical false pass is reproduced deliberately
and asserted to produce a nonzero result. Required classes: forbidden paths
with and without a leading `./`; failed cleanup and interrupted cleanup;
resource-name collision and unrelated-resource preservation; partial Compose
creation; consistent `.env` handling and interpolation; missing, additional,
duplicated, writable and incorrect mounts; missing inspection fields and
malformed JSON; image tag movement and identity mismatch; failed history search
and other search errors; missing or incorrect hostname pinning; missing,
invalid or unbounded logging settings; invalid tmpfs bounds; static and
dynamically linked ELF controls; and the absence of any application-start
operation in the inspection workflow.

A passing suite proves only that the code agrees with itself unless the tests
DISCRIMINATE. Two mechanisms provide that:

* **Pre-fix controls in the suite.** Where a fix changed an expression, the
  superseded expression is applied to the same fixture and asserted to exhibit
  the defect — the `^\./?` path anchor missing `bin/sh`, an unperformed grep
  looking like a clean result, empty `.Mounts` satisfying the old read-only and
  prohibited-mount assertions.
* **The whole suite run against the pre-fix implementation.** Recorded in
  `docs/VERIFICATION.md` §3.5.

**Source / Tests.** `scripts/tests/runtime-verify-test.sh` (319 cases at `b6b1769`); the ELF
controls are `internal/buildcheck/elfcheck/main_test.go`. Both are wired into
`scripts/check.sh` as required gates that need no daemon.
**Evidence required.** All cases present and passing; the suite is a required
gate; and each targeted case is shown to fail against the pre-fix
implementation.
**Dependencies.** SW-P1-01 … SW-P1-06, SW-P1-16 … SW-P1-20.
**Acceptance.** Every listed class has at least one case; the suite runs on
every gate run as the service account; the pre-fix comparison is recorded.
**Status.** VERIFIED at `b6b1769` — `docs/VERIFICATION.md` §3.1. Coverage map in
`docs/VERIFICATION.md` §3.2; pre-fix comparisons in §3.5, which record both the
`b469c59` comparison (112 failures once its own baseline is unmasked) and the
`0b083cb` one (50 of 319 cases). Six classes were added at `b6b1769` for
FINDING-17 … FINDING-22; they are listed at the end of §3.2.

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

**Source.** `.github/workflows/gates.yml`
**Tests.** None can substitute for running it. Three different things are often
conflated here, and this row keeps them apart:

| Level | Meaning | State |
| --- | --- | --- |
| Implementation review | the workflow file was read property by property against the requirement | DONE — `docs/VERIFICATION.md` §3.4 |
| Local simulation | the same gate list was executed locally, as the service account | DONE — `bash scripts/check.sh`, §3.0. This exercises the GATES, not the workflow: it says nothing about `permissions:`, action pinning, runner image, or fork-PR secret handling |
| Hosted CI run | the workflow itself executed on GitHub, with a run URL and log | **NOT DONE** |

**Evidence required.** A hosted run: workflow file at a named commit, a run
URL, the recorded tool versions from that run's log, and the outcome of each
gate in it.
**Dependencies.** SW-P1-08, SW-P1-09, SW-P1-11.
**Acceptance.** The hosted run exists and passes, and its gate list matches the
local suite's.
**Status.** **BLOCKED**, and now the only blocked Phase 1 requirement. "Reviewed,
not executed" is not verified CI execution, so this row is not carried as
VERIFIED with a caveat. Running the workflow requires a push, which is outside
the authorisation for this work.

**Operator action.** `docs/VERIFICATION.md` §6.3 carries the exact push and
trigger sequence, written out in full and **proposed for approval only —
nothing has been pushed, and no merge is proposed.** In outline: the branch is
`feat/phase-1-core`, the workflow's `push` filter matches `feat/**`, so a plain
non-forced `git push origin feat/phase-1-core` starts a run by itself; no pull
request and no `workflow_dispatch` is needed for a first result.

**Two things this row will still not cover when it closes.** Both are recorded
now, because the moment a green run exists they become easy to forget:

* **Fork-pull-request secret handling.** The workflow's strongest security
  property — that a fork PR gets no repository secret and a read-only token —
  cannot be demonstrated by pushing a branch in this repository. It needs a pull
  request from a fork. Until then that property is reviewed, not observed.
* **Agreement with the runtime evidence.** The hosted runner has a Docker
  daemon, so `docker build` and the runtime verification will attempt to run
  there rather than report `BLOCKED`. If either fails on a *hardening
  assertion*, that is not a CI defect to be worked around: it is a disagreement
  with `docs/VERIFICATION.md` §3.7 about builds of the same commit, and it takes
  precedence over closing this row.

**The acceptance criterion above is not satisfiable as written, and that was
established before any push.** `deploy/compose/compose.yaml` binds
`/etc/scamwall/certs/pihole-ca.crt` — a literal absolute path with no
environment override — and a secret file defaulting to
`/etc/scamwall/secrets/pihole_app_password`. Neither can exist on a fresh hosted
runner, so `compose create` fails there, the runtime verification reports
`BLOCKED` or `FAIL`, and `check.sh` exits 1. `docker compose config` does not
catch it: tested against a nonexistent secret path, it exits 0. The analysis is
`docs/VERIFICATION.md` §6.3.

This row therefore closes only after a decision the operator has not yet been
asked to make: materialise throwaway fixtures in CI so the container gates
genuinely run there (which edits a gate input and re-opens §3.4's review), or
amend this acceptance criterion to "the workflow ran, its gate list matched the
local suite, and every gate that could run passed". Recording the requirement as
unsatisfiable and leaving it that way would be the one unacceptable outcome, so
it is written down here rather than discovered on a red run.

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
and a false PASS elsewhere, including a 100% false-clean in the secret scanner
for files above the pipe buffer.
`scripts/tests/pipefail-sigpipe-test.sh` now fails the build if the construction
returns.

**Run counts, stated separately rather than merged**, because the suite changed
size between them and a single figure would imply a measurement that was not
made — `docs/VERIFICATION.md` §3.3:

| Suite | Consecutive runs | Failures |
| --- | --- | --- |
| 237 cases, at `0b083cb` | 500 | 0 |
| 319 cases, at `b6b1769` | 30 | 0 |

The `b6b1769` measurement is shorter: each run of the larger suite takes about
75 seconds, so 500 of them is roughly ten hours. The root cause behind the
original nondeterminism is fixed and independently guarded by
`scripts/tests/pipefail-sigpipe-test.sh`, which is why a shorter repeat is
treated as sufficient to renew rather than as re-establishing the property from
nothing. The shortfall is recorded in `docs/VERIFICATION.md` §7 so it is visible
rather than rounded away.

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


### SW-P1-16 — Cleanup is part of the verdict

**Intended behavior.** Required cleanup completes BEFORE success is reported;
its failures count towards the verdict; a failed required cleanup makes the
exit status nonzero and names every remaining resource by identifier, without
printing configuration, environment or credential content; the handler runs on
EXIT, INT and TERM without repeating a destructive operation; and it is
idempotent — a resource already removed is not an error, and at most one
removal is attempted per resource however many handlers fire.

At the baseline the success summary was printed first and every cleanup error
was discarded, so a run that left containers behind reported success.

**Source.** `scripts/container-runtime-verify.sh` — `run_cleanup`, `on_exit`,
`on_signal`, `remove_owned`, `HANDLED_RESOURCES`, `summary_and_exit`.
**Tests.** `scripts/tests/runtime-verify-test.sh` — *cleanup as a verdict*:
ordering (the cleanup section precedes the verdict line), a failed container
removal, a failed network removal, a TERM delivered mid-run, a mid-run
verification failure, and a run whose inspections fail so ownership cannot be
established.
**Evidence required.** Each case produces a nonzero exit; the fake daemon's log
shows exactly one removal attempt per resource; leftovers are named.
**Dependencies.** SW-P1-17.
**Acceptance.** As above.
**Status.** VERIFIED — `docs/VERIFICATION.md` §3.1.

### SW-P1-17 — Resource ownership is established before deletion

Requirement text and evidence: see SW-P1-06, which this row makes explicit as
its own acceptance item so that a future change to the cleanup path cannot
quietly weaken it. The properties held separately here are:

* the invocation identifier is unpredictable, not derived from the PID;
* every created resource ID is recorded, and a per-invocation ownership label
  is applied;
* pre-existing resources are preserved, including any that coincidentally
  carry a matching label, and their presence blocks creation;
* deletion is by exact ID after re-verifying ownership, never project-wide;
* partial creation is cleaned up by attribution, and unattributable resources
  are preserved and reported.

**Status.** VERIFIED — `docs/VERIFICATION.md` §3.1. Behaviour against a real
daemon rode on SW-P1-05, which is now closed: the operator's run at `b6b1769`
reported 0 cleanup problems and cleanup completion against a real daemon, and
left the host's existing deployment untouched — `docs/VERIFICATION.md` §3.7.

### SW-P1-18 — One resolved Compose configuration

**Intended behavior.** A single argument set — private project name, explicit
`--env-file`, the compose file, and the ownership override — resolves the
configuration, creates the container and lists it. Configuration resolution and
parsing failures are checked explicitly and block the run. Expected
interpolated settings are derived from `docker compose config`, Compose's own
interpolation, and then validated separately against the security requirements;
they are never re-derived by grepping `.env` and stripping quotes by hand. The
rendered configuration is kept in a mode-700 temporary directory and is never
printed.

At the baseline creation passed `--env-file` and cleanup did not, so the two
commands could describe different deployments; and the expected supplementary
group came from a hand-rolled `.env` parse that reimplements — and gets wrong —
Compose's precedence rules.

**Source.** `scripts/container-runtime-verify.sh` — `COMPOSE_ARGS`,
`CONFIG_JSON`, `cfg`, the derived-settings section.
**Tests.** `scripts/tests/runtime-verify-test.sh` — *consistent Compose
configuration*: every Compose operation carries the same `--env-file` and
project name; a `.env` value deliberately DIFFERENT from the resolved value
must not be used; resolution failure and unparseable output block the run.
**Evidence required.** As above, plus the mode-700 directory assertion in the
verifier's own output.
**Dependencies.** SW-P1-03.
**Acceptance.** As above.
**Status.** VERIFIED — `docs/VERIFICATION.md` §3.1.

### SW-P1-19 — The mount set is asserted exactly

**Intended behavior.** `.Mounts` must be a non-empty array before any statement
is made about mounts. The observed set must EQUAL the set derived from the
resolved configuration — mount type, expected resolved source, destination and
read-only status — with nothing missing, nothing extra, and no duplicated
destination. The one runtime-managed exception, the scratch tmpfs at `/tmp`, is
named explicitly and validated separately from `HostConfig.Tmpfs`, where Docker
records its options. Prohibited sources and destinations are rejected.

At the baseline an absent or empty `.Mounts` satisfied both "every mount is
read-only" and "no prohibited mounts" without a single mount being examined,
and nothing checked that the configuration, feed, CA and password mounts were
present at all.

**Scope.** A read-only mount at `/run/secrets/pihole_app_password` does not
prove the container identity can READ it; that depends on the host file's
owner, group and mode. The verifier prints this, and no row here claims it.

**Source.** `scripts/container-runtime-verify.sh` — `EXPECTED_MOUNTS`,
`OBSERVED_MOUNTS`, the mount comparison and tmpfs validation.
**Tests.** `scripts/tests/runtime-verify-test.sh` — *mounts*: empty, absent,
missing configuration mount, missing password mount, extra, duplicated,
writable, wrong source, wrong type, `docker.sock`, `/etc/pihole`, a tmpfs
somewhere other than `/tmp`; plus a pre-fix control showing empty `.Mounts`
satisfied the superseded assertions.
**Evidence required.** Each case produces a nonzero exit and names the mount.
**Dependencies.** SW-P1-18.
**Acceptance.** As above.
**Status.** VERIFIED — `docs/VERIFICATION.md` §3.1. Against a real container:
SW-P1-05.

### SW-P1-20 — Static linkage proven by ELF inspection

**Intended behavior.** The build asserts the intended executable properties of
the artifact it produced by parsing its ELF structure: an executable object
type, no `PT_INTERP` and no `.interp` section, no `PT_DYNAMIC` and no
`SHT_DYNAMIC` section, and no `DT_NEEDED` shared library. A missing inspection
tool, an unreadable file, an empty file or a malformed executable is a FAILURE.

At the baseline the assertion was `! ldd BIN 2>/dev/null | grep -q "=>"`, which
passed for a static binary, a missing binary, a corrupt binary and a missing
`ldd` alike.

**Scope.** This proves the binary carries no dynamic linking apparatus. It does
not prove the binary is safe, secret-free, or built from this source.

**Source.** `internal/buildcheck/elfcheck/main.go`; invoked by
`container/Dockerfile` in the build stage.
**Tests.** `internal/buildcheck/elfcheck/main_test.go` — positive control (a
`CGO_ENABLED=0` build compiled by the test), negative controls (hand-built ELF
objects carrying `PT_INTERP` and `PT_DYNAMIC`, a dynamically linked system
binary where one is present), and malformed inputs (missing, empty, non-ELF,
truncated header, a directory). `scripts/container-security-check.sh` asserts
the Dockerfile still invokes it and that no `ldd`-based assertion returns.
**Evidence required.** The controls pass, AND the assertion is observed to run
inside a real `docker build`.
**Dependencies.** Docker daemon access for the second part.
**Acceptance.** Both.
**Status.** **VERIFIED** at `b6b1769`, on both:

| Part | Result |
| --- | --- |
| The controls | 5 test functions, positive, negative and malformed inputs, all passing — `docs/VERIFICATION.md` §3.6 |
| The assertion inside a real build | Executed during the operator's `docker build` of `b6b1769`, which exited 0 and produced image `sha256:b95cc07c…` — `docs/VERIFICATION.md` §3.7 |

The assertion is a `RUN` step, so a build exit of 0 does not merely coexist with
it having passed: the build could not have reached that status otherwise. The
same build also executed the enforcement-absent assertion — the binary must
report `enforcement compiled in false` — which is recorded alongside it and
corroborates the `Enforcement` row in §2 against the built artifact rather than
against the source alone.

Neither part closes this row alone. Passing controls prove the checker works;
a green build without them proves an assertion ran but not that it can fail.

**Renewal.** Tied to that image. A rebuild re-executes the assertion, and its
result is recorded against the new image ID; §5.

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
| SW-P2-04 | Secret permissions and access are verified **under the actual container identity** | BLOCKED — see the note below; the blocker is no longer daemon access |
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
what is missing is evidence against anything real.

*Carried into this phase from the `b6b1769` runtime verification.* The verified
run resolved the API destination through the compose default mapping,
`pi.hole:host-gateway`, with `PIHOLE_HOST_IP` unset. What that established is
narrow and worth stating exactly: the pin is applied as configured — a single
`extra_hosts` entry, agreeing between the resolved configuration and the created
container, with no second or conflicting entry. It is a fact about the
container's name resolution and about nothing beyond it.

Three consequences follow, and all three are Phase 2 work rather than Phase 1
gaps:

| Question | Requirement | State |
| --- | --- | --- |
| Is the address behind the mapping reachable, and is it a Pi-hole? | SW-P2-05, SW-P2-07 | **Not attempted.** The container was never started; nothing was sent |
| Does TLS verification succeed against it — correct CA, correct hostname, no downgrade or fallback? | SW-P2-02 | **Not attempted against anything real.** Evidenced only against a fake HTTPS server |
| Can the container identity read the mounted password at runtime, and does authentication succeed? | SW-P2-04, SW-P2-01 | **Unverified.** No process has read the file; no session has been established |

SW-P2-04 remains BLOCKED, and the reason has changed. It is no longer blocked
on Docker daemon access — that is resolved. It is blocked because the runtime
verifier deliberately never starts the application, so a passing run says
nothing whatever about credential access. Verifying it requires a *started*
container under the actual container identity, which is a Phase 2 activity,
operator-initiated and never automatic. Passing runtime verification must not be
read as partial evidence for it: it is not weak evidence, it is absent evidence.

Destination connectivity and TLS verification through the mapping are recorded
here as Phase 2 scope so that neither is mistaken for something Phase 1 closed.

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

Writing this paragraph does not fix it. SW-P3-05 stays **MISSING**, and it is
deliberately not restated as a Phase 1 item or closed by documentation: the
conflation is in `internal/domain/domain.go`, and only a code change removes
it. Recording a defect and resolving it are different acts, and this matrix
distinguishes them everywhere.

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
| A rebuilt image (new image ID) | SW-P1-05, SW-P1-20, SW-P2-04 |
| Feed schema or trust key | SW-P3-01 … SW-P3-04, SW-P3-07 |
| Detection behavior | Every Phase 4 row |

Renewal means re-running the gate and recording a **new** entry in
`docs/VERIFICATION.md` against the new commit or image ID. Editing the old
entry's commit hash is not renewal.

The converse also needs saying, or the rule becomes unusable: **evidence is
tied to the last commit that changed a gate input.** A documentation-only
commit changes none, so the record carries forward rather than requiring a
re-run — otherwise writing down the evidence would itself invalidate it.

**Image-bound rows carry a second identity.** SW-P1-05 and SW-P1-20 are tied to
image `sha256:b95cc07c…` *and* to commit `b6b1769`. Both must hold. A rebuild
from the same commit produces an image that has not been verified, however
confident one is that it is equivalent — reproducibility is a property to be
demonstrated, not assumed, and it has not been demonstrated here. Rebuild, then
re-run `docs/VERIFICATION.md` §6.1 and record the new ID.

---

## 6. Requirements deliberately not held here

Two things belong elsewhere and are linked rather than duplicated:

* **API behavior and divergence** — `docs/PIHOLE_API_CONTRACT.md`. That
  document is the contract; this matrix only records whether the client obeys
  it.
* **Threats and residual risk** — `docs/THREAT_MODEL.md` and
  `docs/SECURITY_BOUNDARIES.md`. A threat is not a requirement; the control
  answering it is.
