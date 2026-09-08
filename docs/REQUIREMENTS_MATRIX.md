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
| Evidence commit | `aa49797` — *fix(ci): supply the deployment's fixtures, and check the mount sources*. The last commit that changes a gate input |
| **Verified image** | source `b6b1769151501d89d7f8550d2c8f3378d0e73c3d`, image `sha256:b95cc07ca564b115f8bf2d49d642efafc99ae8ff4ae7746caaa7d2ff5e00516b`, build exit 0 with both in-build assertions executed, verifier 90 passed / 0 failed / 0 blocked / 0 cleanup problems, `VERIFY exit=0`. Evidence: `docs/VERIFICATION.md` §3.7. **Lapsed at `aa49797`**, which changes the verifier and `compose.yaml`; no image has been built from `aa49797` or later on the operator's host. Renewal: `docs/VERIFICATION.md` §6.1 |
| **CI-built image** | source `72bc84c13f4e6914bfb015e87d46a5234e8f5234`, image `sha256:d7c44949d56d4f609b3f184464521a2d95c6b34e628f69fd5b145ad6104bba07`, built on the runner in the passing run 34047025567: build exit 0 with both in-build assertions executed, and `container runtime verification` PASSED against CI's own fixtures. Evidence: `docs/VERIFICATION.md` §3.12. It carries **SW-P1-20**, which is about the executable. It does **not** carry SW-P1-05, which is about this deployment's settings. Not a deployable artifact for this household: it was built from a clean checkout with no `.env` |
| Previous evidence commit | `b6b1769` — *fix(verify): check list processing, name scope, mounts, numbers and fields*. `ef40156`/`aa49797` changed `scripts/*.sh`, `compose.yaml` and the workflow, which demotes the rows §5 names; the script-bound rows were re-run and renewed at `aa49797`, the image-bound ones were not and cannot be from the service account |
| Superseded evidence commit | `0b083cb` — *fix(verify): attribute resources and complete the runtime assertions*. `b6b1769` changed `scripts/*.sh`, which demotes the rows §5 names; those were re-run and renewed |
| Superseded candidate image | source `b469c592ca756b82bc2eb18ee4cdcb42b9458a0c`, image `sha256:d3c4ed2c91250448044e1f1eb4e8d0d04591ba10237b3c56e5effc55f7e2251f`, build exit 0. **No verifier was ever run against this image**, and it predates all seventeen findings in `docs/VERIFICATION.md` §4.7 and §4.8. Retained as an identity on record for ID stability; it is not evidence and must not be deployed |
| Previous working candidate | `7e1141997cc1f7484144f07c1fb05cde5d39e280`. Implementation and local verification only: not pushed, not built, not deployed. It changes Go source, `scripts/*.sh` and `.github/workflows/gates.yml`, so §5 demotes the rows named in §3 below. `docs/VERIFICATION.md` §3.14 |
| Previous working candidate | `9ebb98c590fe96628c486d83b66a3b9c87608b85`. Correction and local verification only: not pushed, not built, not deployed. It changes Go source (`cmd/scamwall/main.go`, `internal/adapters/pihole/client.go`), `scripts/check.sh`, `scripts/container-runtime-verify.sh`, a new `scripts/lib/docker-resources.sh`, a new `scripts/operator-handoff.sh` and a comment in `container/Dockerfile`. `docs/VERIFICATION.md` §3.15 |
| Previous working candidate | `5af270d8ae36b1f60832f4edf26b71df2eee4945`. Defect correction and local verification only: not pushed, not built, not deployed. It changes `scripts/check.sh`, `scripts/gate-diagnostics.sh`, `scripts/operator-handoff.sh`, the **tracked file mode** of `scripts/container-runtime-verify.sh`, two test files, and adds `scripts/tests/entrypoint-mode-test.sh`, so §5 demotes the script-bound rows again. It changes **no Go source**, so the Go-path rows established at `9ebb98c` and `7e11419` stand. It does **not** change `.github/workflows/gates.yml`. `docs/VERIFICATION.md` §3.16, §4.14 |
| Previous working candidate | `76f3bfd3ebc647ba21dd281fc2b5a3c48435b8d7`. ORDER 1: defect correction and local verification only — not pushed, not built, not deployed. It changes `scripts/operator-handoff.sh` and `scripts/tests/operator-handoff-test.sh` and nothing else, so §5 demotes the script-bound rows again; the suite was re-run on the clean committed tree to renew them. It changes **no Go source**, no Dockerfile, no Compose definition and no workflow, so the Go-path rows established at `9ebb98c` and `7e11419` stand. `docs/VERIFICATION.md` §3.17, §4.15 |
| **Working candidate** | `04e7ea4e8e85c39cf60d6786021ce3cc7562e904`. ORDER 1 review response: defect correction and local verification only — not pushed, not built, not deployed. It changes `scripts/operator-handoff.sh` and `scripts/tests/operator-handoff-test.sh` and nothing else, so §5 demotes the script-bound rows again; the suite was re-run on the clean committed tree to renew them. It changes **no Go source**, no Dockerfile, no Compose definition and no workflow, so the Go-path rows established at `9ebb98c` and `7e11419` stand. One gate does **not** pass on this tree: `go test -race ./...` fails about 8% of runs on a pre-existing coincidence in `cmd/scamwall/e2e_test.go` that this session did not introduce and deliberately did not fix — FINDING-60. `docs/VERIFICATION.md` §3.18, §4.16 |
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
| SW-P1-05 | Exact image identity and deployment settings are verified against a real image | IMPLEMENTED-UNVERIFIED |
| SW-P1-06 | Inspection resources are isolated; only this invocation's resources are removed | VERIFIED |
| SW-P1-07 | Regression tests cover the enumerated false-pass classes | VERIFIED |
| SW-P1-08 | Shell scripts pass ShellCheck as a required gate | VERIFIED |
| SW-P1-09 | An independent secret detector runs alongside the project-specific scanner | VERIFIED |
| SW-P1-10 | Critical Go paths are reviewed and the review is recorded | VERIFIED |
| SW-P1-11 | govulncheck results are handled by content, not by exit status alone | VERIFIED |
| SW-P1-12 | CI is reproducible, least-privilege, and records tool versions | IMPLEMENTED-UNVERIFIED |
| SW-P1-13 | Pre-existing functional, security, race, and offline-plan tests are preserved and rerun | VERIFIED |
| SW-P1-14 | The gate suite is deterministic: no gate passes or fails at random | VERIFIED |
| SW-P1-15 | The CLI's read-only guarantee is covered by a test | VERIFIED |
| SW-P1-16 | Cleanup is part of the verdict: it completes first, it is idempotent, and its failure is nonzero | VERIFIED |
| SW-P1-17 | Every resource is attributed to this invocation before it is deleted; pre-existing resources are preserved | VERIFIED |
| SW-P1-18 | One resolved Compose configuration drives creation, listing and expectation | VERIFIED |
| SW-P1-19 | The deployment's mounts are asserted exactly: presence, type, source, mode, no extras | VERIFIED |
| SW-P1-20 | Static linkage is proven by checked ELF inspection of the built artifact | IMPLEMENTED-UNVERIFIED |

**Phase 1 is not complete, and at `7e11419` it is further from complete than it
was at `72bc84c`.** That is the renewal rule working, not a regression. Nineteen
of twenty requirements were verified at `72bc84c`; the working candidate changes
Go source, `scripts/*.sh` and the workflow, so §5 demotes three rows rather than
one. Restoring them needs an operator build and a hosted run — in that order,
and neither can be performed from this account.

| Row | State at `7e11419` | Next step |
| --- | --- | --- |
| SW-P1-12 | **IMPLEMENTED-UNVERIFIED** | Demoted by §5: `.github/workflows/gates.yml` changed at `bc5ad77` (fixture ownership) and `scripts/check.sh` at `66199c8`/`3cc7c5e`. The gate list is now **26**, not the 24 run 34047025567 executed, so that run cannot be read as covering this tree. It also needs the property-by-property re-review §5 requires for a workflow change — begun, and partly mechanised: `scripts/workflow-policy-check.sh` now asserts seven of the properties on every run (`docs/VERIFICATION.md` FINDING-30). Renewal: an approved push, then a hosted run |
| SW-P1-20 | **IMPLEMENTED-UNVERIFIED** | Demoted by §5 on both halves. The commit half lapsed because the Go source changed, so the executable this row is about is not the one image `sha256:d7c44949…` contains; the image half lapses with it. The controls (§3.6) are untouched and pass. Renewal: the assertion must be observed inside a real `docker build` of this source — `docs/VERIFICATION.md` §6.5 step A produces exactly that, or a hosted run does |
| SW-P1-05 | IMPLEMENTED-UNVERIFIED | Still open, and its renewal now has **wider scope**: `bc5ad77` adds assertions relating the supplementary group to the password file's ownership, the container identity's ability to read it, and the daemon's user-namespace posture. None has ever been evaluated against this deployment. Renewal is an operator action: `docs/VERIFICATION.md` §6.5 step A |

**Do not relabel run 34047025567 as covering `7e11419`.** It covers `72bc84c`:
24 gates, a different workflow file, and different Go source. The new candidate
needs its own hosted run after a subsequently approved push, and until then the
honest statement is that these three rows are implemented and unverified.

**And do not relabel it as covering `9ebb98c` either.**
That session changes Go source and three scripts and adds two more, so §5
demotes the same rows a second time. Its local suite was re-run on the final
clean committed tree and those rows rest on *that* transcript
(`docs/VERIFICATION.md` §3.15); nothing about it was renewed by any earlier run.

| Row | State at `9ebb98c` | Next step |
| --- | --- | --- |
| SW-P1-12 | **IMPLEMENTED-UNVERIFIED** | Still demoted. `.github/workflows/gates.yml` is unchanged by this session, so the property-by-property workflow re-review is not re-triggered — but `scripts/check.sh` gained a gate, so the gate list this tree runs is again not the list any hosted run has executed. Renewal: an approved push, then a hosted run |
| SW-P1-20 | **IMPLEMENTED-UNVERIFIED** | Still demoted on both halves: the Go source changed again, so the executable this row is about is not the one in image `sha256:d7c44949…`. The controls (§3.6) are untouched and pass. Renewal: the assertion observed inside a real `docker build` of this source — `docs/VERIFICATION.md` §6.5 step A, or a hosted run |
| SW-P1-05 | IMPLEMENTED-UNVERIFIED | Still open. Its renewal procedure was **rewritten and tested** this session — `§6.5` step A now passes explicit build metadata, checks the in-build assertions per step, runs the built binary to confirm the commit it embeds, and pins the runtime verifier to the resolved image ID. That is a better renewal, not a renewal. It has not been executed |
| SW-P1-15 | **IMPLEMENTED-UNVERIFIED** | Demoted by §5 on the Go change, and renewed on the local transcript: `go test -race -count=1 ./...` passes with six new CLI cases covering the credential-free doctor mode, the credential-length removal, and the three session-teardown outcomes. `docs/VERIFICATION.md` §3.15 |

**Where the rows stood at `72bc84c`, retained because a row that was closed and
then demoted is a different thing from one that was never closed.** Nineteen of
twenty requirements were verified at
`72bc84c`. No requirement is BLOCKED any more — SW-P1-12 closed on a passing
hosted run, and SW-P1-20 closed on the build inside it — and one remains
demoted, awaiting an operator action this account cannot perform:

| Row | State | Next step |
| --- | --- | --- |
| SW-P1-12 | **VERIFIED** | Closed at `72bc84c` by run 34047025567: 24 passed, 0 failed, 0 BLOCKED, gate list identical to the local suite's. It took three runs — the first could not be diagnosed at all (FINDING-23), the second diagnosed itself and found FINDING-27 — and the acceptance criterion was never relaxed. `docs/VERIFICATION.md` §3.12 |
| SW-P1-20 | **VERIFIED** | Closed at `72bc84c`, bound to image `sha256:d7c44949…`. Its acceptance is "the controls pass, AND the assertion is observed to run inside a real `docker build`"; the controls are untouched and were re-run at `b6e70f4`, and the assertion is a `RUN` step in a build that exited 0 on an uncached runner. An earlier revision held this row open because CI's *deployment* differs from the operator's — an over-application, since the ELF assertion reads no deployment. `docs/VERIFICATION.md` §3.12 |
| SW-P1-05 | IMPLEMENTED-UNVERIFIED | Demoted by §5: `aa49797` changes `deploy/compose/compose.yaml` **and** `scripts/container-runtime-verify.sh`, and the verifier now makes assertions the `b6b1769` run never evaluated. The CI run at `72bc84c` passed the same verifier against image `sha256:d7c44949…` and **does not close this**: it resolved a different deployment, so four assertions remain unevaluated against the operator's configuration. Renewal is an operator action: `docs/VERIFICATION.md` §6.1 |


#### SW-P1-20 reconciled across the complete history since `72bc84c`

This row has been closed once and demoted twice, and the two facts are easy to
collapse into a wrong one. They are kept apart here.

| | |
| --- | --- |
| **Old evidence, and what it still covers** | Run 34047025567 at source `72bc84c13f4e6914bfb015e87d46a5234e8f5234`, image `sha256:d7c44949d56d4f609b3f184464521a2d95c6b34e628f69fd5b145ad6104bba07`. The ELF linkage assertion executed as a `RUN` step inside an uncached `docker build` that exited 0. **That evidence is not withdrawn and is not weakened.** It remains valid for the artifact it names, and `docs/VERIFICATION.md` §3.12 keeps it |
| **What it does not cover** | Any other source tree, and any other image. It is bound to an image ID, which is the digest of that image's content |
| **Drift since** | Five commits changed Go source — `0d620de`, `ee09fff`, `2a0af8f`, `7e11419`, `42477f1` — and `container/Dockerfile` changed with them. Cumulatively **+3440 / −229 across 22 files** (`git diff --stat 72bc84c..HEAD -- '*.go' go.mod go.sum container/Dockerfile`). The executable this tree produces is not the executable inside `sha256:d7c44949…` |
| **Current status** | **IMPLEMENTED-UNVERIFIED**, and has been continuously since `7e11419` |
| **Current renewal requirement** | The ELF linkage assertion must be observed executing inside a real `docker build` **of this source**, not of any earlier one. Two paths produce it: `docs/VERIFICATION.md` §6.5 **step A**, run by the operator; or a hosted run after an approved push. Either is sufficient on its own for this row. The static controls (`docs/VERIFICATION.md` §3.6) are untouched and pass, and they are the *other* half of the acceptance — they are not a substitute for the build half |

**The error this table exists to prevent.** "This patch changed no Go source"
is a statement about one patch. It is not a statement about the distance
between the current tree and the tree some earlier evidence was produced
against, and it must never be read as one. The renewal rule in §5 is
cumulative: evidence lapses when the source it describes moves, and it does not
un-lapse because a later commit happened to leave that source alone.

The same reading applies to **SW-P1-12**, for the same reason and by a
different route: the gate list this tree runs is **26**, and run 34047025567
executed **24**. That row is also IMPLEMENTED-UNVERIFIED and also needs its own
hosted run.

Demoting rows that were green is the rule working, not a regression. The
alternative — leaving them VERIFIED because the change "should not affect them"
— is precisely the assumption §5 exists to forbid. Restoring one of them on
evidence that genuinely covers it is the same rule working in the other
direction, and is not a relaxation: SW-P1-20's criterion was met, not amended.

An unverified required item means the phase does not close, however many of the
others are green — and "the CI badge is green" is the most tempting reason to
forget that. Nineteen-twentieths is not nineteen-twentieths of a closed phase;
it is an open phase. The one open row is the one that ties the work to a real
image *and a real deployment*, which is precisely the half a passing CI run
cannot supply: CI verified a container built on the runner, mounting throwaway
fixtures, with `group_add: 65532` rather than the deployment's `989`
(`docs/VERIFICATION.md` §3.12).

**What is missing for SW-P1-05, precisely** — four assertions, not the row as a
whole. `docs/VERIFICATION.md` §6.1 lists them: the prohibited-path rule over the
secret source, the host-side regular-file check on every approved mount, the
password file's world-reachability, and the supplementary group resolving to the
deployment's `989` rather than the default `65532`. Everything else the row
asserts ran against a real image in CI.

**The history of these two rows**, retained rather than rewritten, because a
row that was closed, demoted and closed again on different evidence is a
different thing from one that was never in doubt. Both were first closed by the
operator's run at `b6b1769` against image `sha256:b95cc07c…`
(`docs/VERIFICATION.md` §3.7):

| Was blocked | Closed by | Acceptance criterion met | State now |
| --- | --- | --- | --- |
| SW-P1-05 | the verifier run against a real built image: 90 passed, 0 failed, 0 blocked, 0 cleanup problems, `VERIFY exit=0`, image identity confirmed against the pin, container created and never started | both artifacts required by the row — the regression suite against the fake, and a real run recording the image ID | **Demoted** at `aa49797`. Artifact (1) renewed; artifact (2) awaits §6.1 |
| SW-P1-20 | the ELF linkage assertion executing inside a `docker build` that exited 0 | both parts — the controls pass (§3.6) *and* the assertion ran in a real build | **VERIFIED again** at `72bc84c`, on the CI build. Bound to `sha256:d7c44949…` rather than to `sha256:b95cc07c…` |

**Reconciliation of everything else claimed for Phase 1**, so that nothing is
carried on assumption:

| Item | State |
| --- | --- |
| `check.sh` exit status, requested directly rather than inferred from the printed verdict | **Obtained** at `aa49797` and again at `b6e70f4`: `CHECK exit=1`, with 22 passed, 0 failed, 2 BLOCKED. Run directly, not through a wrapper, a monitor, `tee` or a background task, so the status is the script's own. The status and the printed verdict agree. `docs/VERIFICATION.md` §3.0, §3.13 |
| Evidence renewal after `ef40156`/`aa49797` changed `scripts/*.sh`, `compose.yaml` and the workflow | **Done, except for one row.** §5 demotes SW-P1-01 … SW-P1-04, SW-P1-06 … SW-P1-09, SW-P1-11 and SW-P1-14 on any `scripts/*.sh` change; the suite was re-run at `aa49797`, and again at `b6e70f4`, and those rows rest on that transcript. SW-P1-20 was renewed by the CI build at `72bc84c`. SW-P1-05 needs an image built on the operator's host against the operator's deployment and cannot be renewed from the service account; it is demoted rather than carried, `docs/VERIFICATION.md` §6.1 |
| The six defects fixed in `b6b1769` | **Recorded** as FINDING-17 … FINDING-22, `docs/VERIFICATION.md` §4.8, with the pre-fix comparison in §3.5 — the `0b083cb` verifier fails 50 of the 319 cases |
| Determinism (SW-P1-14) at the new suite size | **Partly renewed.** 30 consecutive runs of the 319-case suite at `b6b1769`, 0 failures — against 500 runs for the 237-case suite at `0b083cb`. Shorter by design and stated as such, not merged into one figure. `docs/VERIFICATION.md` §3.3 |
| Hosted CI execution | **Done, and it failed.** Run 34036997074 at `2a18874`. What it established: the workflow runs, its recorded tool versions match §2.2 exactly, its gate list matches the local suite's, and `docker build` passes on an independent host. What it did not: a passing run. `docs/VERIFICATION.md` §3.8 |
| Diagnosability of a failed CI gate | **Fixed at `ef40156`, and demonstrated locally.** A failing gate now reports its reason, verdict and cleanup result before any length limit, states any truncation, and preserves the omitted material in a sanitized artifact CI uploads. 62 regression cases, three PRE-FIX CONTROLS, and an end-to-end demonstration through `check.sh` with an injected failing gate — `docs/VERIFICATION.md` §4.9 and §3.10. **Not yet observed on a runner**: the `::group::` markers and the artifact upload have never been exercised by GitHub |
| Why the `2a18874` CI run failed | **Not established, and unrecoverable from that run.** It has no artifacts and its log holds exactly the twenty-five lines the old `head -25` kept. The *precondition* for the predicted cause is now established by resolving the real definition under runner conditions (`docs/VERIFICATION.md` §3.9), but a precondition is not a mechanism |
| CI's ability to run the container gates at all | **Addressed at `aa49797`, unobserved.** The workflow now creates disposable fixtures under `RUNNER_TEMP`, outside the build context, 0700/0600, and removes them in a step that fails the job if the removal did not take. No CI-specific assertion was weakened or skipped. `docs/VERIFICATION.md` §3.4 and §6.3 |
| Fork-pull-request secret handling | **Not demonstrated**, and not demonstrable by a branch push. Reviewed in `docs/VERIFICATION.md` §3.4, and since `66199c8` also asserted *lexically* on every gate run by `scripts/workflow-policy-check.sh` — which establishes what the workflow says, not what GitHub does. Registered in `docs/VERIFICATION.md` §6.4 item 10 so it is not lost when SW-P1-12 closes again |
| Evidence renewal at `7e11419` | **Local half done; hosted and image halves outstanding.** §5 demotes SW-P1-01 … SW-P1-04, SW-P1-06 … SW-P1-09, SW-P1-11, SW-P1-14 and SW-P1-19 on any `scripts/*.sh` change, and every Go-source row plus SW-P1-13 on a Go change. The whole local suite was re-run on the final clean committed tree — 24 passed, 0 failed, 2 BLOCKED, `CHECK exit=1` — and those rows rest on that transcript (`docs/VERIFICATION.md` §3.14). SW-P1-12 and SW-P1-20 cannot be renewed from this account and are demoted rather than carried |
| The API contract, enforced rather than described | **New at `0d620de`, locally evidenced.** A permitted-operation table is checked before any network activity and again on every redirect; the total deadline, `Retry-After` handling, session nesting and credential scrubbing are covered by tests against a local fake. `docs/PIHOLE_API_CONTRACT.md` §7 states the permitted set and, in its own subsection, that none of this is evidence about a real Pi-hole |
| Runtime password access, live authentication, destination connectivity and TLS verification through the `pi.hole` pin | **Not established, and out of Phase 1 scope.** Phase 2 — SW-P2-02 and SW-P2-04. `docs/VERIFICATION.md` §6.2 |
| The operator procedure that renews SW-P1-05 | **Rewritten and tested; still unexecuted.** It was a documentation code block that nothing ran, and it carried nine defects — including a hardcoded HEAD that refused its own documented checkout, a build passing no source metadata, a step claiming to read no password beside output showing it reading one, and steps B–D executing whatever the mutable tag pointed at. It is now `scripts/operator-handoff.sh` with 141 regression cases against a scripted fake Docker and git. `docs/VERIFICATION.md` §4.13 and §6.5. **Testing the procedure is not performing it**: SW-P1-05 closes when the operator runs step A and returns its result |
| Evidence renewal at `76f3bfd` (ORDER 1) | **Local half done; hosted and image halves outstanding, as before.** §5 demotes SW-P1-01 … SW-P1-04, SW-P1-06 … SW-P1-09, SW-P1-11, SW-P1-14 and SW-P1-19 on the `scripts/*.sh` change. The whole local suite was re-run on the final clean committed tree and those rows rest on that transcript (`docs/VERIFICATION.md` §3.17). SW-P1-12, SW-P1-20 and SW-P1-05 cannot be renewed from this account and are demoted rather than carried. **This patch changing no Go source does not renew any Go-bound row** — see the row below |
| SW-P1-20 reconciled across the whole history since `72bc84c` | **IMPLEMENTED-UNVERIFIED, and this patch does not change that in either direction.** A correction is recorded here rather than left implied: "no Go source changed in this patch" says something about `0cdec6c…76f3bfd` and **nothing** about whether the current Go source matches the tree CI built at `72bc84c`. It does not. Five commits since have changed Go source — `0d620de`, `ee09fff`, `2a0af8f`, `7e11419`, `42477f1` — together with `container/Dockerfile`, for a cumulative **+3440 / −229 across 22 files**. The image the old evidence is bound to therefore contains a **different executable** from the one this tree builds. See §5 and the reconciliation table below |
| The operator procedure's own defects, second pass | **Six found and fixed at `76f3bfd`; the procedure is still unexecuted.** FINDING-51 to FINDING-56: a failed isolation assertion did not prevent `docker start`, a step published its identities before it had a verdict, `--authorise-authenticated-read` was accepted as proof that steps A, B and C had passed, the work directory's advertised "sanitized logs" were the raw captures, step Z's leftover check could not return anything and therefore passed every time, and the privileged work directory and state file were not validated for symlinks, ownership, mode or ancestor writability. `docs/VERIFICATION.md` §4.15. The suite is 308 cases. **Testing the procedure is still not performing it**: SW-P1-05 closes when the operator runs step A and returns its result |
| The "pending operator testing" row, examined as a category | **Reclassified.** Across two review passes that row has now been found to contain **eight** defects that needed no Docker daemon — FINDING-49 and FINDING-50 at `5af270d`, FINDING-51 … FINDING-56 at `76f3bfd`. It must not be read as a queue of questions only a daemon can settle. What genuinely remains behind it is narrow, and `docs/VERIFICATION.md` §7 states it as such |
| Evidence renewal at `9ebb98c` | **Local half done; hosted and image halves outstanding, as before.** §5 demotes SW-P1-01 … SW-P1-04, SW-P1-06 … SW-P1-09, SW-P1-11, SW-P1-14 and SW-P1-19 on the `scripts/*.sh` change, and every Go-source row plus SW-P1-13 and SW-P1-15 on the Go change. The whole local suite was re-run on the final clean committed tree and those rows rest on that transcript (`docs/VERIFICATION.md` §3.15). SW-P1-12, SW-P1-20 and SW-P1-05 cannot be renewed from this account and are demoted rather than carried |

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
**Status.** **IMPLEMENTED-UNVERIFIED** at `b6e70f4`. It was VERIFIED at
`b6b1769` on both artifacts; artifact (2) lapsed and is partly, not wholly,
restored by CI:

| Artifact | Result | At `b6e70f4` |
| --- | --- | --- |
| (1) regression suite against the scripted fake | 336 cases, 0 failed. The cases discriminate: the `0b083cb` verifier fails 50 of the 319 it shares — `docs/VERIFICATION.md` §3.5 | **Renewed**, at `aa49797` and re-run at `b6e70f4`. Seventeen cases were added for the host-side mount-source and password-permission assertions, with a PRE-FIX CONTROL for the exempted secret source |
| (2) operator run against image `sha256:b95cc07ca564b115f8bf2d49d642efafc99ae8ff4ae7746caaa7d2ff5e00516b`, built from `b6b1769` | 90 passed, 0 failed, **0 blocked**, 0 cleanup problems; `VERIFY exit=0`; the inspected container's image matched the pin; the container remained created and was never started; cleanup reported completion — `docs/VERIFICATION.md` §3.7 | **Lapsed, and only partly replaced.** `aa49797` changes `compose.yaml` and the verifier; §5 demotes this row on either. The CI run at `72bc84c` ran the current verifier against a real image (`sha256:d7c44949…`) and so restores most of what artifact (2) asserts — the mount set, destinations, read-only flags, image-identity discipline, hardening flags, bounds and limits, on an independent host. It does **not** restore the four assertions that depend on the operator's own configuration |

**The four assertions still unevaluated against this deployment**, which is the
whole of what is missing:

1. `no prohibited path appears in the configured mounts or in the secret source`
   — added at `aa49797`; CI evaluated it against fixture paths under `RUNNER_TEMP`.
2. `every approved mount resolves to an existing regular file on this host`
   — added at `aa49797`; "this host" was the runner.
3. `the application password file is not world-readable through its path`
   — added at `aa49797`; the runner's was a 0600 fixture in a fresh directory,
   not `/etc/scamwall/secrets/pihole_app_password`.
4. the supplementary group — CI resolved `65532` from the default, because
   `deploy/compose/.env` is gitignored and a fresh clone has none. The
   deployment resolves `989`.

Nothing observed suggests the renewal will fail: the operator host already has a
regular file at the CA path and a `0750 root:swsecret` secrets directory, and
rendering the definition with the deployment's `.env` yields `group_add:
["989"]` (`docs/VERIFICATION.md` §3.13). But "expected to pass" is not a result,
which is the entire point of §5. `docs/VERIFICATION.md` §6.1 lists the exact
commands and the lines to look for.

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

**Classes added at `76f3bfd` for the operator handoff (ORDER 1).** These belong
to `scripts/tests/operator-handoff-test.sh` rather than to the verifier's suite,
and each is a false-pass or a forbidden-action class the earlier list did not
name:

* an isolation assertion that failed, or that could not be evaluated, must
  prevent the container from being started at all — asserted against the fake
  daemon's own command log, not against the program's output;
* a step that did not pass must publish no identity, and a later step must
  refuse rather than run off one;
* a cleanup failure must make the step's recorded state `failed`, not `passed`;
* an authorisation flag must not stand in for a prerequisite's recorded result;
* a prerequisite that passed against a different image or a different resolved
  configuration must be refused as STALE;
* a rebuild must invalidate downstream acceptance **before** it runs, so a
  failed rebuild leaves nothing usable;
* the shareable evidence copy must retain no credential-shaped value the
  sanitizer catches, while the raw capture must retain it;
* a close-out check that cannot return anything is not a pass, and an empty
  invocation register is UNPROVEN;
* a privileged program must not follow a symlink, adopt a state file it does
  not own, or write into a directory an unprivileged account could substitute.

The discrimination mechanism for these is the **reversion experiment** recorded
in `docs/VERIFICATION.md` §3.17: each fix was reverted on its own and the suite
re-run. In-suite pre-fix controls were not used here because five of the six
defects are the *absence* of a control-flow gate rather than a changed
expression, and a reverted gate is the faithful reproduction of that.

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
| Implementation review | the workflow file was read property by property against the requirement | DONE — `docs/VERIFICATION.md` §3.4, re-done at `aa49797` for the three new steps |
| Local simulation | the same gate list was executed locally, as the service account | DONE — `bash scripts/check.sh`, §3.0. This exercises the GATES, not the workflow: it says nothing about `permissions:`, action pinning, runner image, or fork-PR secret handling. `scripts/tests/compose-fixture-test.sh` narrows the gap slightly by resolving the deployment under the runner's conditions (§3.9), and narrows it only slightly: it still runs here |
| Hosted CI run | the workflow itself executed on GitHub, with a run URL and log | **DONE, AND PASSING** — 34047025567 at `72bc84c`, 24 passed / 0 failed / 0 BLOCKED (§3.12). Two earlier runs failed and are retained: 34036997074 (§3.8) and 34045148578 (§3.11) |

**Evidence required.** A hosted run: workflow file at a named commit, a run
URL, the recorded tool versions from that run's log, and the outcome of each
gate in it.
**Dependencies.** SW-P1-08, SW-P1-09, SW-P1-11.
**Acceptance.** The hosted run exists and passes, and its gate list matches the
local suite's. **This criterion is unchanged**, and was deliberately not
amended: option B in `docs/VERIFICATION.md` §6.3 proposed relaxing it to "every
gate that could run passed", which would have permanently exempted the container
gates from the only independent host available. Making CI able to satisfy the
criterion was chosen over making the criterion able to accept CI.
**Status at `7e11419`.** **IMPLEMENTED-UNVERIFIED.** Demoted by §5: the
workflow file and `scripts/check.sh` both changed, and the gate list is now 26
rather than the 24 run 34047025567 executed. Renewal is a hosted run of *this*
tree after an approved push. `docs/VERIFICATION.md` §3.14.

**A mismatch inside this row, recorded rather than resolved by moving the
requirement.** Its *Intended behavior* says "no secret exposure to untrusted
contributions — meaning fork pull requests get no repository secrets and no
elevated token". Its *Acceptance* says only that a hosted run exists, passes,
and matches the local gate list. Those are not the same thing, and the second
does not entail the first: run 34047025567 satisfied the acceptance criterion
in full while demonstrating nothing whatever about fork pull requests.

The disposition, stated explicitly because the tempting move is the wrong one:

* The acceptance criterion **is not reopened**. It was met on its own terms at
  `72bc84c`, and it was met without being relaxed — `docs/VERIFICATION.md` §6.3
  records that a proposal to weaken it was rejected. Reopening a criterion that
  was satisfied would make the record less trustworthy, not more.
* The fork-PR property **stays assigned to Phase 2** (`docs/VERIFICATION.md`
  §6.4 item 10), where it was assigned before this session. It is not being
  moved to a later phase in order to close Phase 1: it was already there, and
  it cannot be demonstrated without a pull request from a fork — which is not
  an artefact of scheduling but of what GitHub will and will not do for a
  branch push.
* What *was* closable was closed now. `scripts/workflow-policy-check.sh`
  (`docs/VERIFICATION.md` FINDING-30) turns seven properties from "reviewed"
  into "asserted on every gate run", including one review had not covered:
  that no attacker-chosen context reaches a `run:` block. That removes the risk
  of the declaration being silently changed. It does not, and cannot, establish
  what GitHub does at run time.

**Superseded status, retained.**
 **VERIFIED** at `72bc84c` — run 34047025567, 24 passed / 0 failed /
0 BLOCKED, `RESULT: all required gates passed`, gate list identical to the local
suite's in content and order. `docs/VERIFICATION.md` §3.12.

| Acceptance component | State |
| --- | --- |
| A hosted run exists, with a run URL and log | **Met.** <https://github.com/LordHorkos/scamwall/actions/runs/34047025567>, commit `72bc84c` |
| The run records its tool versions | **Met.** Reproduced in full at `docs/VERIFICATION.md` §3.12; every version matches the local set except Compose, which differs and is now recorded on both sides — that difference is FINDING-27 |
| Its gate list matches the local suite's | **Met.** 24 gates, identical and in identical order; `check.sh` is the single definition and CI keeps no second list. The only difference in outcome is the two container gates, BLOCKED locally and PASS in CI |
| The run passes | **Met.** 24 passed, 0 failed, 0 BLOCKED, `RESULT: all required gates passed` |

**A by-product worth recording separately:** `docker build` PASSED on the
runner, executing the ELF linkage and enforcement-absent assertions on Ubuntu
24.04.4 with Docker 28.0.4. SW-P1-20 was already closed by §3.7 against the
operator's host; this is independent corroboration from a second one.

**The blocking sequence**, which is now more specific than "run CI":

1. ~~**Fix FINDING-23**~~ — **DONE at `ef40156`.** A failing gate now reports its
   reason, verdict and cleanup result before any length limit, states any
   truncation, and preserves the omitted material in a sanitized artifact the
   workflow uploads. 62 regression cases plus an end-to-end demonstration
   through `check.sh` itself — `docs/VERIFICATION.md` §4.9 and §3.10.
2. ~~**Then decide the fixture question**~~ — **DONE at `aa49797`: option A.**
   The workflow generates disposable fixtures on the runner rather than
   exempting CI from the container gates. The reasoning for deciding it without
   the old run's cause in hand — including why option B was rejected on its
   merits — is `docs/VERIFICATION.md` §6.3.
3. ~~**Then a passing run**~~ — **DONE at `72bc84c`.** Run 34047025567: 24
   passed, 0 failed, 0 BLOCKED. §3.12. The sequence took three runs and each
   one earned its place: the first produced the run URL and FINDING-23, the
   second produced FINDING-27 and FINDING-28 by diagnosing itself, and the
   third passed.

**All three steps have been observed on a runner.** The `::group::` markers, the
artifact upload, the fixture step (0600 files in a 0700 directory) and its
cleanup behaved as designed, and the container gates executed and passed. The
caveat that stood here — that all of it was a hypothesis about GitHub's
behaviour until a run exercised it — was well placed: run 34045148578 found
FINDING-27, an assertion added by this session that read a Compose field not
every Compose version renders. It was fixed rather than accommodated, and run
34047025567 then passed.

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

**Why the acceptance criterion is probably not satisfiable as written.** This was
set out before the push and the run is consistent with it, but it is a
hypothesis and is labelled as one. `deploy/compose/compose.yaml` binds
`/etc/scamwall/certs/pihole-ca.crt` — a literal absolute path with no
environment override — and a secret file defaulting to
`/etc/scamwall/secrets/pihole_app_password`. Neither can exist on a fresh hosted
runner, so `compose create` should fail there. `docker compose config` does not
catch it: tested against a nonexistent secret path, it exits 0.

**The run neither confirmed nor refuted this.** It failed at the right gate, and
FINDING-23 means the log does not say why. A prediction that matches an outcome
has not thereby been shown to match the mechanism, and this row will not record
that it has until a log shows the verifier's own verdict. `docs/VERIFICATION.md`
§3.8 and §6.3.

Recording the requirement as unsatisfiable and leaving it that way would be the
one unacceptable outcome, so it is written down here rather than left to be
rediscovered on each red run.

**Resolved, and the resolution is narrower than "the problem is fixed".** The
acceptance criterion turned out to be satisfiable after all — run 34047025567
passed at `72bc84c` — and the reasoning below is retained because it is why.
 Two of the three statements above have since been tested rather than
reasoned about, by resolving the real definition under runner conditions with no
`.env` and no operator paths (`docs/VERIFICATION.md` §3.9):

| Statement | Now |
| --- | --- |
| The CA source is a literal absolute path with **no** environment override | **No longer true.** `${SCAMWALL_CA_FILE}` was added at `aa49797`, defaulting to the operator path. Adding it is what makes the row satisfiable without amending it |
| Neither source can exist on a fresh runner | **Established by resolution**, not merely read off the file: with nothing set, both resolve under `/etc/scamwall/` |
| `docker compose config` does not catch it | **Established.** Exits 0 with every bind source absent |
| Therefore the `2a18874` run failed for this reason | **Still not established**, and unrecoverable from that run — it kept no artifact and its log holds only the twenty-five lines `head -25` allowed |

The acceptance criterion **is** satisfiable, and has been satisfied: CI creates
the two fixtures it needs, the verifier makes the same assertions in both
environments, and run 34047025567 passed all 24 gates. The heading of this
paragraph — "probably not satisfiable as written" — was wrong, and is left
standing rather than rewritten, because a prediction edited after the outcome is
not a prediction. What made it wrong was adding one environment override and a
fixture step, neither of which existed when it was written.

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
satisfied the superseded assertions. And — added at `aa49797` — *mount sources
on the host*: a source that does not exist, a source that is a directory where a
file is required, an absent password file, a world-reachable password file, a
secret source taken from a prohibited path, and a pre-fix control showing the
superseded prohibited-path expression exempted the secret source entirely.
`scripts/tests/compose-fixture-test.sh` additionally resolves the real
definition under hosted-runner conditions and checks the result against this
row's own approved mount set.
**Evidence required.** Each case produces a nonzero exit and names the mount.
**Dependencies.** SW-P1-18.
**Acceptance.** As above.
**Status.** VERIFIED — `docs/VERIFICATION.md` §3.1. Against a real container:
SW-P1-05, which is IMPLEMENTED-UNVERIFIED at `aa49797` pending a rebuild.

**What `aa49797` added, and why it belongs in this row rather than a new one.**
Every assertion here was about the container's mount TABLE. Docker's default for
a bind whose source does not exist is to create an empty directory and mount
that — so a deployment with no CA and no password file produces a mount table
that satisfies every assertion above, over nothing. That is a false pass in this
row's own subject matter, and it is closed two ways: `bind.create_host_path:
false` in the definition, and a host-side check that each approved source is an
existing regular file. `docs/VERIFICATION.md` §4.10, FINDING-25.

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
**Status.** **VERIFIED** at `72bc84c`, bound to image
`sha256:d7c44949d56d4f609b3f184464521a2d95c6b34e628f69fd5b145ad6104bba07`.
It was VERIFIED at `b6b1769`, demoted at `aa49797` when the image it was bound
to no longer matched the candidate, and re-established by the passing CI run:

| Part | Result | At `b6e70f4` |
| --- | --- | --- |
| The controls | 5 test functions, positive, negative and malformed inputs, all passing — `docs/VERIFICATION.md` §3.6 | **Valid.** `internal/buildcheck/elfcheck` and `container/Dockerfile` are untouched by `ef40156`, `aa49797`, `72bc84c` and `b6e70f4`, and the tests were re-run at `b6e70f4` (`docs/VERIFICATION.md` §3.13) |
| The assertion inside a real build | Executed during the operator's `docker build` of `b6b1769` (§3.7); in CI at `2a18874` (§3.8); and in the **passing** run 34047025567 at `72bc84c`, which produced `sha256:d7c44949…` (§3.12) | **Valid at `72bc84c`.** The runner is fresh and the workflow declares no build cache, so the `RUN` step executed rather than being restored |

**Why the CI run closes this row when it does not close SW-P1-05.** The two
rows were demoted together and are easily assumed to renew together. They do
not. SW-P1-05 asserts *deployment settings* — the supplementary group, the CA
and password sources, the mount set — and CI resolves a different deployment,
so its run does not speak to the operator's. This row asserts a property of the
*executable*, established in the build stage before any deployment exists: the
assertion opens the binary, parses its ELF structure and exits. It reads no
password, no CA, no mount and no group. A difference in those cannot bear on
it, and treating it as though it could was an over-application of the renewal
rule rather than an application of it — `docs/VERIFICATION.md` §3.12.

The assertion is a `RUN` step, so a build exit of 0 does not merely coexist with
it having passed: the build could not have reached that status otherwise. The
same build also executed the enforcement-absent assertion — the binary must
report `enforcement compiled in false` — which is recorded alongside it and
corroborates the `Enforcement` row in §2 against the built artifact rather than
against the source alone.

Neither part closes this row alone. Passing controls prove the checker works;
a green build without them proves an assertion ran but not that it can fail.

**Scope of the closure.** This row is closed for the artifact the assertion ran
against. It is not a claim about any other image, and specifically not about an
image the operator has yet to build: `docs/VERIFICATION.md` §6.1 re-executes the
assertion during the operator's build and records the result against that image
ID, extending this row to a second artifact. That extension is not a
precondition for closing it — a requirement is met by the evidence its
acceptance names, and this one names a real build, not a particular host.

**Renewal.** Tied to an image. A rebuild re-executes the assertion, and its
result is recorded against the new image ID; §5. A `CACHED` build step is not a
re-execution, which is why §6.1 refuses one.

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

*Implementation advanced at `7e11419`, without acceptance.* `0d620de` closes
four gaps these rows depend on and that no test previously covered: the
permitted set of API operations is enforced in code before any network activity
and again on every redirect target (FINDING-31); one deadline bounds a retried
operation rather than each attempt separately (FINDING-32); `Retry-After` is
honoured and capped (FINDING-33); and a session cannot be nested, which
previously leaked a seat on the appliance (FINDING-36). `2a0af8f` adds
end-to-end coverage of the CLI against a local fake, asserting the exact ordered
network sequence, that an invalid configuration fails with zero network calls,
and that no credential reaches any stream.

**None of that is acceptance.** Phase 2 opens when SW-P1-05 closes, and every
row here still needs evidence against something real. `docs/VERIFICATION.md`
§6.5 steps B, C and D are the procedures that would produce it, and they are
pending operator review.

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
| SW-P3-05 | Domain **validity** is separated from **maliciousness** classification; mixed scripts or Unicode alone never establish maliciousness | IMPLEMENTED-UNVERIFIED |
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

*Known gap, and its resolution at `7e11419`.* Until that commit,
`internal/domain/domain.go` rejected mixed-script labels inside `Normalize`,
and a rejected record made the whole feed fail to load. That conflated "this
name is not a valid domain" with "this name is suspicious", which SW-P3-05
forbids — and the blast radius was the sharper half of the defect: one
suspicious-looking entry destroyed every unrelated indicator in a signed feed.

The conflation is removed, in both directions:

| Question | Where it is answered now |
| --- | --- |
| Is this a syntactically valid domain, and what is its canonical form? | `domain.Normalize`. Its errors are about syntax only; `ErrMixedScript` no longer exists |
| Is there anything notable about the name? | `domain.Assess` returns observations — `non_ascii`, `punycode_input`, `single_non_latin_script`, `mixed_script` — carrying no judgement |
| Is the domain malicious? | Nothing in the domain package answers this, and its package comment says so |
| Is it eligible for a proposed block? | `policy.Decide`, from the feed's own claims first and the name's signals second |

The disposition is three-valued, not two. A mixed-script name the feed asserts
with high confidence is **neither proposed nor excluded**: it is held for
review, visible, with the signals that put it there and a stable reason code.
Excluding on a signal would silently withdraw protection from entries the
publisher was confident about; proposing it would treat a signal as evidence.
Unicode, a non-Latin script and punycode alone change no disposition, and a
test asserts each of them individually.

Plan format `scamwall-plan-v1` becomes `v2`: the review section is inside the
digest, because a plan that withheld an entry and one that never saw it are
different plans and an operator approving the first must not thereby authorise
the second. Every digest changes, deliberately. **No signing fixture was
regenerated** — none needed to be, and none may be regenerated to make a test
pass.

**SW-P3-05 is `IMPLEMENTED-UNVERIFIED`, not VERIFIED.** The code exists and is
covered by regressions for Cyrillic and Greek lookalikes in four positions,
legitimate Japanese Han+kana combinations, ordinary IDNs in five scripts,
invalid encodings and disallowed input, duplicate and conflicting canonical
forms through the feed validator, stable signal and reason codes, and
determinism over repeated runs. Its **acceptance** is a Phase 3 activity and
Phase 3 has not begun; implementing a requirement early does not accelerate the
phase that accepts it. `docs/VERIFICATION.md` §3.14.

*Bounded parsing and fuzzing (SW-P3-08).* Four native fuzz targets now exist —
domain normalisation, configuration decoding, feed decoding, and the
authentication response — and their first runs found two real defects
(`docs/VERIFICATION.md` FINDING-34, FINDING-35). The row stays **MISSING**: it
requires fuzzing of *critical parsers and normalisation* as an accepted,
sustained practice with recorded corpora and durations, and four bounded
campaigns on one afternoon is a start, not that.

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
| `container/Dockerfile` or `deploy/compose/compose.yaml` | SW-P1-05, SW-P1-06, SW-P1-18, SW-P1-19, and every container row |
| Any `scripts/*.sh` — including `scripts/tests/*.sh` and any script added later | SW-P1-01 … SW-P1-04, SW-P1-06 … SW-P1-09, SW-P1-11, SW-P1-14, SW-P1-19 |
| `.github/workflows/*.yml` | SW-P1-12, and its implementation-review evidence specifically: the file must be re-reviewed property by property, not merely re-run |
| A rebuilt image (new image ID) | SW-P1-05, SW-P1-20, SW-P2-04 |
| Feed schema or trust key | SW-P3-01 … SW-P3-04, SW-P3-07 |
| Detection behavior | Every Phase 4 row |

Applied to `7e11419`, that table demotes SW-P1-12 (workflow and `check.sh`
changed), SW-P1-20 (Go source changed, so the executable the row is about is
not the one the verified image contains), and every Go-source row plus
SW-P1-13 — the last of which the local re-run then renews. SW-P1-05 was already
demoted and its renewal scope has widened. §3 above states each one and its
next step.

The `scripts/*.sh` row is written to include test scripts and future ones on
purpose. `ef40156` added `scripts/gate-diagnostics.sh` and
`scripts/tests/gate-diagnostics-test.sh`; `aa49797` added
`scripts/tests/compose-fixture-test.sh`. A rule that enumerated the scripts that
existed when it was written would have silently exempted all three, and
`shellcheck (all scripts)` already had exactly that defect once — it read only
the git index, so an unstaged script was "clean" by never having been staged
(`docs/VERIFICATION.md` §4.5).

Renewal means re-running the gate and recording a **new** entry in
`docs/VERIFICATION.md` against the new commit or image ID. Editing the old
entry's commit hash is not renewal.

The converse also needs saying, or the rule becomes unusable: **evidence is
tied to the last commit that changed a gate input.** A documentation-only
commit changes none, so the record carries forward rather than requiring a
re-run — otherwise writing down the evidence would itself invalidate it.

**Image-bound rows carry a second identity.** SW-P1-05 and SW-P1-20 are tied to
an image ID *and* to a commit. Both must hold. At `b6e70f4`:

| Row | Bound to | Holds? |
| --- | --- | --- |
| SW-P1-20 | image `sha256:d7c44949…`, commit `72bc84c` | **Yes.** `b6e70f4` changes documentation only, so the commit half is intact; the image half is the artifact the assertion ran against |
| SW-P1-05 | image `sha256:b95cc07c…`, commit `b6b1769` | **No.** The commit half lapsed at `aa49797`, which changed the verifier and `compose.yaml` — so the row is `IMPLEMENTED-UNVERIFIED` in §3 rather than carried forward on the image alone |

At `7e11419` neither holds. SW-P1-20's commit half lapsed when the Go source
changed, and no image has been built from this source on any host, so both
identities are absent rather than merely stale. A rebuild is the only route,
and `docs/VERIFICATION.md` §6.5 step A is that rebuild.

A rebuild from the same commit produces an image that has not been verified,
however confident one is that it is equivalent — reproducibility is a property
to be demonstrated, not assumed, and it has not been demonstrated here.
Rebuild, then re-run `docs/VERIFICATION.md` §6.1 and record the new ID.

**A row bound to a CI-built image is not thereby a weaker row.** What matters is
whether the artifact the evidence names is the artifact the requirement is
about. SW-P1-20 is about an executable's linkage, and CI built a real one.
SW-P1-05 is about a deployment's settings, and CI resolved a different
deployment. The distinction is the requirement's, not the runner's.

---

## 6. Requirements deliberately not held here

Two things belong elsewhere and are linked rather than duplicated:

* **API behavior and divergence** — `docs/PIHOLE_API_CONTRACT.md`. That
  document is the contract; this matrix only records whether the client obeys
  it.
* **Threats and residual risk** — `docs/THREAT_MODEL.md` and
  `docs/SECURITY_BOUNDARIES.md`. A threat is not a requirement; the control
  answering it is.
