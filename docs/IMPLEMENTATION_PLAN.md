# ScamWall Implementation Plan

<!-- SPDX-License-Identifier: AGPL-3.0-only -->

This document describes **how** ScamWall is built and **in what order**.
`docs/REQUIREMENTS_MATRIX.md` holds the numbered requirements and their status;
`docs/VERIFICATION.md` holds the evidence. Where those documents already say
something, this one links instead of repeating.

---

## 1. The rule that shapes everything below

> **Writing the code does not complete a phase. Producing its evidence does.**

Two consequences follow, and they are the reason this plan is structured the
way it is.

**A check that could not run has proven nothing.** It is reported as `BLOCKED`
and it fails the gate. It is never a skip, never an "N/A", never a green tick
with a footnote. The failure mode this prevents is specific and common: a
suite that reports green while quietly omitting the half of itself that needed
a daemon, a network, or a credential.

**Evidence expires.** Every phase revalidates the applicable guarantees of
every earlier phase before it can pass. A Phase 1 gate result recorded against
commit `A` says nothing about commit `B`. The demotion rules are in
`docs/REQUIREMENTS_MATRIX.md` §5, and they are mechanical: if the source moved,
the evidence is stale, regardless of how confident anyone is that the change was
harmless.

---

## 2. Sequencing

```
Phase 1  Trustworthy verification          <- current
   |     establish gates that cannot lie
   v
Phase 2  Verified read-only integration
   |     prove the Pi-hole client against something real
   v
Phase 3  Trusted feeds, policy, durable state
   |     make the inputs and the stored state defensible
   v
Phase 4  Independent effectiveness evaluation
   |     find out whether it actually works
   v
Phase 5  Operational read-only pilot
   |     run it for real, changing nothing
   v
Phase 6  Controlled enforcement            <- household enforcement stays
         (separate operator review)           disabled pending its own review
```

The order is not arbitrary. Verification comes first because every later claim
is expressed through it: if the gates can produce a false pass, no subsequent
result means anything. Effectiveness evaluation comes *before* the pilot and
well before enforcement, because the cost of being wrong rises steeply along
that axis — a false positive in Phase 4 is a number in a report, and the same
false positive in Phase 6 blocks a household's bank.

### 2.1 Working while blocked

Some evidence needs the Docker daemon, and the service account does not have
it (`docs/SECURITY_BOUNDARIES.md` §5.2). That is a deliberate choice, not an
oversight: `docker` group membership is root-equivalent on this host.

Work therefore proceeds on independent tasks while a gate is blocked. What does
**not** proceed is the completion decision: a phase with a blocked required
gate is not complete, and dependent phases do not open. Blocked items carry the
exact operator command needed to unblock them, in `docs/VERIFICATION.md` §6.

---

## 3. Phase 1 — Trustworthy verification

**Objective.** Establish checks that cannot lie, and an auditable baseline.

**Status at the baseline commit `2edb95a`.** Eight of fifteen requirements were
verified. The container verifier had already been rebuilt around checked
operations and was covered by 61 regression cases. Missing was the tooling layer
around it — ShellCheck, an independent secret detector, content-based
vulnerability handling, CI — plus the findings this session's own inspection
raised.

**Status now, at `aa49797`.** Seventeen of twenty verified — the requirement set
grew from fifteen to twenty as the work exposed classes that had no requirement
covering them. `docs/REQUIREMENTS_MATRIX.md` §3 is authoritative; this paragraph
is a summary and defers to it wherever the two differ.

**SW-P1-05 and SW-P1-20 were closed and have been re-opened**, not by a failure
but by the renewal rule. They closed on the operator's run at `b6b1769` against
image `sha256:b95cc07c…`: build exit 0 with the ELF and enforcement-absent
assertions executed inside it, verifier 90 passed / 0 failed / 0 blocked / 0
cleanup problems, `VERIFY exit=0` (`docs/VERIFICATION.md` §3.7). `ef40156` and
`aa49797` then changed the verifier and the compose definition, which
`docs/REQUIREMENTS_MATRIX.md` §5 demotes both rows on, and no image has been
built from `aa49797`. Renewal is an operator action — `docs/VERIFICATION.md`
§6.1 — and is expected to pass; expected is not observed.

**SW-P1-12 is the one BLOCKED requirement, so the phase does not close.**
The workflow was executed with operator approval — run 34036997074 at
`2a18874` — and it failed: 20 passed, 1 failed, 0 BLOCKED
(`docs/VERIFICATION.md` §3.8). The run established that CI works, records its
tool versions, runs the same gate list as the local suite, and builds the image
on an independent host; it did not produce a passing run, and it did not say why
it failed. Both named prerequisites are now discharged — FINDING-23 is fixed at
`ef40156`, and the fixture question is decided as option A at `aa49797` — so the
row is blocked on running the workflow, and on nothing else.

Twenty-six findings were raised and resolved along the way. The most serious
were a `pipefail`/SIGPIPE race that made the secret scanner report a planted
private key as clean 200 times out of 200 in a 1 MB file
(`docs/VERIFICATION.md` §4.1), and seventeen false-pass defects in the runtime
verifier itself, found in two review rounds and none by execution (§4.7, §4.8).

### 3.1 Work items

| # | Work | Requirement |
| --- | --- | --- |
| 1 | Container checker corrections | SW-P1-01 |
| 2 | Separate repository verification from operator Docker verification | SW-P1-02 |
| 3 | Check command and parsing failures explicitly | SW-P1-03 |
| 4 | Evaluate only successfully captured structured results | SW-P1-04 |
| 5 | Verify exact image identity and deployment settings | SW-P1-05 |
| 6 | Isolate inspection resources; clean up only what this run created | SW-P1-06 |
| 7 | Regression tests for the false-pass classes | SW-P1-07 |
| 8 | ShellCheck review of shell scripts | SW-P1-08 |
| 9 | Independent secret detector alongside project controls | SW-P1-09 |
| 10 | Review critical Go paths | SW-P1-10 |
| 11 | govulncheck result handling by content | SW-P1-11 |
| 12 | Reproducible CI, constrained permissions, recorded tool versions | SW-P1-12 |
| 13 | Preserve and rerun pre-existing tests | SW-P1-13 |
| 14 | Remove gate nondeterminism | SW-P1-14 |
| 15 | Test the CLI read-only guarantee | SW-P1-15 |

Items 1–7 and 13 were completed in commits `36ed21b` … `2edb95a`. Items 8–12
and 14–15 are this session's work.

### 3.2 Approach for the outstanding items

**ShellCheck (SW-P1-08).** Run over every tracked shell script at
`--severity=style`. Findings are fixed rather than suppressed wherever fixing
is honest; the two informational findings that are false positives — a function
invoked only through `trap`, and a deliberately single-quoted regex — get inline
`# shellcheck disable=` directives *with a reason on the line above*. A bare
disable directive is a silenced check, which is the thing this phase exists to
prevent.

**Independent secret detector (SW-P1-09).** `scripts/secret-scan.sh` encodes
ScamWall-specific knowledge: which paths must never be tracked, that the
Pi-hole password lives at a fixed location, that a certificate body means the
private CA leaked. A generic scanner knows none of that, and conversely knows
hundreds of credential formats the project scanner does not. They are
complementary, so both run and both are required.

The independent detector must scan **what would be published** — the commit
history and the tracked/staged tree — rather than the working directory as it
happens to sit on disk. Scanning the raw directory reports the operator's
correctly-ignored local key material as a finding, which trains people to
ignore the tool. The publishable tree is materialised with `git archive`, so
the scanner sees exactly the bytes a clone would.

Allowlisting is the risk here. Every allowlist entry is a hole, so each one
carries a written justification in `.gitleaks.toml`, and a positive control
proves the detector still fires.

**govulncheck (SW-P1-11).** The gate must decide from result *content*.
`govulncheck`'s default text mode exits nonzero on findings, so the current
gate is not wrong — but its correctness is accidental, resting on a property of
one output mode. In `-format json` and `-format sarif` the exit status is `0`
whether or not findings exist. A gate written against those modes without
parsing the output reports a vulnerable dependency set as clean. The gate is
therefore rewritten to capture JSON, count findings by osv/finding records, and
fail on a nonzero count — and to fail if the output cannot be parsed at all,
because an unparseable result is an unrun check.

**CI (SW-P1-12).** GitHub Actions, with: actions pinned by commit SHA rather
than by tag; a top-level `permissions: contents: read`; `pull_request` rather
than `pull_request_target`, so fork contributions run without repository
secrets and without a writable token; every tool version echoed into the run
log; and the same gate list as `scripts/check.sh`.

The last clause of that paragraph used to read "Docker-dependent gates are
reported as blocked in CI exactly as they are locally", and that was wrong about
the hosted runner: it **has** a daemon, so those gates attempt to run rather than
block. The first hosted run proved it by building the image successfully and
then failing the runtime verification. As of `aa49797` the workflow supplies the
two host files the deployment binds — generated on the runner, outside the image
build context, removed by a step that fails the job if the removal did not take
— so the container gates **execute** in CI against a CI-built image.

The rule that decision was made under: **a CI-specific fixture is acceptable; a
CI-specific bypass of a required assertion is not.** The runtime checker
enforces the same mount destinations, the same read-only binds, the same
exact-set rule and the same permission check in both environments; only the bind
*sources* differ, and every destination remains fixed in the compose file with no
override. Where a gate genuinely cannot run — a runner with no daemon — it still
reports BLOCKED and BLOCKED still fails the suite.

**Gate diagnosability.** Added to this phase's scope by the first hosted run
rather than planned into it, and worth recording as a lesson about the plan
rather than only as a fix. Every gate here was designed to distinguish *passed*,
*failed* and *could not run*; none of that survives if the harness prints the
wrong end of the output, and locally the defect was invisible because the two
container gates blocked rather than failed, so the truncation never fired.
Failure reporting is now a separate, self-testing program that prints the
reason, the verdict and the cleanup result before any length limit, sanitizes
everything it prints, and preserves anything it had to omit in an artifact the
workflow uploads. `docs/VERIFICATION.md` §4.9.

**Gate determinism (SW-P1-14).** A nondeterministic failure was observed in
`scripts/tests/runtime-verify-test.sh` and root-caused before being fixed —
patching a flake without understanding it risks converting a random failure into
a random pass, which is strictly worse. The cause turned out not to be confined
to the test at all: a `pipefail` script whose condition ends in a
short-circuiting `grep -q` reads a match as a non-match whenever the producer is
still writing. The same construction appeared throughout `secret-scan.sh`, where
it produced a 100%% false-clean on files above the pipe buffer.
`docs/VERIFICATION.md` §4.1 has the measurements. A static gate now fails the
build if the construction returns.

**CLI test (SW-P1-15).** `cmd/scamwall` had no test file, so the Phase 1 boundary
at the command surface rested on reading the code — the one place where a
regression would be both easy to introduce and invisible to the existing suite.
`cmd/scamwall/main_test.go` now covers it, including that the
`--dry-run=false` refusal happens before configuration is consulted, so a valid
configuration cannot mean the credential was already read from disk.

### 3.3 Acceptance

Phase 1 is complete when, at one commit:

* every required gate that can run, ran and passed;
* every deliberate failure injection produces a nonzero gate result;
* no required gate is silently omitted;
* **a failing gate says why** — its reason, its verdict and its cleanup result
  appear in the log, and anything omitted for length is preserved and pointed
  at. Added after the first hosted run showed a red gate whose diagnosis had
  been discarded (`docs/VERIFICATION.md` §4.9);
* operator verification runs without root git access;
* runtime assertions are tied to the exact inspected image ID;
* existing deployment resources survive checker execution;
* remaining evidence gaps are explicitly `BLOCKED`, with operator commands.

Three of these are outstanding at `aa49797`, and none of them is satisfiable
from the service account:

| Outstanding | Why | Who |
| --- | --- | --- |
| A hosted run that passes | SW-P1-12's acceptance criterion, unchanged | Needs an approved push; the run follows automatically from the branch filter |
| Runtime assertions tied to an image ID | The `b6b1769` image is superseded by `aa49797`'s changes to the verifier and the compose definition | Operator — `docs/VERIFICATION.md` §6.1 |
| Deployment resources survive checker execution | Demonstrated against the scripted fake at `aa49797` (336 cases) but not re-demonstrated against a real daemon since `b6b1769` | Same operator run |

### 3.4 Previous-state validation

There is no earlier phase, so this reduces to: the functional, security, race,
and offline-plan tests that already existed must still exist and still pass,
and any intentional behavior change must be explained. Tracked in SW-P1-13.

---

## 4. Phase 2 — Verified read-only Pi-hole integration

**Entry.** Phase 1 verification accepted for the relevant source and artifacts.

**Objective.** Move the Pi-hole client from "tested against a fake" to "proven
against something real", without ever writing to Pi-hole.

### 4.1 Work items

1. Define the permitted method/path set, including authentication and session
   cleanup. The set is already a constant pair in
   `internal/adapters/pihole/client.go` (`/api/auth`, `/api/info/version`) and
   is asserted structurally by `guard_test.go`; Phase 2 makes that definition
   authoritative and links it to `docs/PIHOLE_API_CONTRACT.md`.
2. Enforce TLS verification, intended destination handling, redirect
   restriction, deadlines, bounded responses, controlled proxy behavior.
3. Bounded retries, cancellation, rate-limit handling, credential-safe
   diagnostics.
4. Verify secret permissions and access **under the actual container
   identity** — not under the service account, and not by reading the file mode
   and reasoning about it. The distinction matters: the current record
   establishes configured permissions, and explicitly not proven access
   (`docs/SECURITY_BOUNDARIES.md` §5.1).
5. Stand up a disposable Pi-hole instance and document the compatibility scope
   — which Pi-hole versions this contract was observed against, and what
   happens outside that range.
6. Test correct credentials, rejected credentials, invalid CA, wrong hostname,
   unavailable server, malformed responses, rate limits, interrupted execution.
7. Provide operator commands for **one** controlled live read-only test, after
   the permitted operations have been reviewed. It is not started
   automatically.

### 4.2 Acceptance

Read-only integration succeeds against the disposable environment; approved
live evidence is captured with no credential or session token in it; no
blocking-state mutation occurs; failure paths terminate within their defined
limits; session cleanup is verified **including its failure cases**; permission
and compatibility assumptions are written down.

### 4.3 Previous-phase validation

Rerun the Phase 1 gates against the resulting source and image. Any new failure
class discovered here gets a regression test before the phase closes.

---

## 5. Phase 3 — Trusted feeds, policy, and durable state

**Entry.** Earlier applicable gates pass.

**Objective.** Make the inputs and the persisted state defensible against a
publisher that is wrong, compromised, or replaying.

### 5.1 Work items

1. Strict, versioned configuration and feed schemas.
2. Key provisioning, rotation, revocation, sequence and freshness checks,
   expiry, replay protection.
3. **Evaluate TUF, or an equivalent established signed-update design, before
   writing a custom lifecycle protocol.** Record the decision and its scope.
   The baseline uses a single Ed25519 key with no rotation or revocation path,
   which is adequate for a fixture and inadequate for a distributed feed.
   Rolling a bespoke key-lifecycle protocol is a well-known way to reinvent
   known vulnerabilities, so the default is to adopt rather than invent, and
   the burden of argument sits on inventing.
4. Publisher provenance, review, withdrawal, signing-key separation.
5. **Separate domain validity from maliciousness classification.** A mixed-script
   label or the mere presence of non-ASCII must not, on its own, establish that
   a domain is malicious. Today `domain.Normalize` rejects mixed-script labels
   as *invalid*, and one rejected record fails the whole feed. That conflates
   two different judgements and produces a bad outcome in both directions: a
   legitimate internationalized domain is unusable, and a homograph is recorded
   as a parse error rather than as the signal it actually is. The homograph
   check becomes a classification input with its own reason code.
6. Exact-domain and subdomain semantics, duplicate handling, source conflicts,
   confidence rules, expiry, user exceptions, reason codes.
7. Behavior for unavailable, stale, revoked, or invalid feeds — including what
   happens to state that already exists.
8. Bounded input processing; fuzz the parsers and the normalizer. `Normalize`
   is the single highest-value fuzz target in the tree: it is the only place
   attacker-influenced text drives a complex third-party state machine, and it
   is exactly where the two reachable `govulncheck` findings landed
   (`docs/SECURITY_BOUNDARIES.md` §5.3).
9. Atomic state updates, locking, corruption handling, schema migration,
   storage limits.
10. Versioned, deterministic plans bound to feed identity, policy and
    configuration identity, destination identity, creation and expiry,
    actions, exclusions, and application preconditions. The baseline plan
    digest covers format version, feed ID, manifest version, and entries; the
    remaining bindings do not exist yet.
11. Test clock anomalies, interrupted writes, concurrent runs, oversized input,
    recovery.

### 5.2 Acceptance

Tampered, stale, replayed, malformed, and oversized inputs all have tested
outcomes. Trust changes and withdrawals have tested procedures. Policy
precedence is explicit and deterministic. State survives tested interruption
without silently accepting corruption. Documentation states plainly that
**signing establishes authenticity, not accuracy** — a correctly signed feed
can still be entirely wrong.

### 5.3 Previous-phase validation

Rerun Phase 1–2 gates. Confirm that no feed or state change broadens the
Pi-hole permission surface.

---

## 6. Phase 4 — Independent effectiveness evaluation

**Entry.** Feed and policy behavior stable enough for meaningful evaluation.

**Objective.** Find out whether ScamWall actually works, in a way that cannot
flatter itself.

### 6.1 Work items

1. A versioned evaluation runner.
2. Lawful data sourcing and redistribution constraints, documented.
3. **Labels independent of the feed under evaluation.** Scoring a feed against
   itself measures nothing.
4. Development data separated from held-out data, with documented leakage
   controls and time boundaries.
5. Malicious, legitimate, uncertain, and internationalized domains in the set.
   Internationalized names are not decoration here — they are where the
   validity/maliciousness conflation of Phase 3 does its damage.
6. Precision, recall on the dataset, false-positive rate, feed delay,
   withdrawal delay, resource use.
7. Sample sizes, uncertainty, label limitations, category-level results.
8. **Numerical thresholds proposed and recorded before the acceptance run**,
   and before anyone looks at final held-out results. A threshold chosen after
   seeing the number is not a threshold.
9. Uncertain labels handled explicitly. They are not quietly counted as
   whichever category improves the headline.

### 6.2 Acceptance

Reproducible from recorded inputs. Predeclared thresholds assessed honestly.
Failures lead to remediation **and a fresh evaluation**, not to a re-reading of
the same run. Synthetic fixtures are never presented as real-world accuracy
evidence — `testdata/feed.json` is evidence about signature verification and
nothing else.

### 6.3 Previous-phase validation

Rerun earlier gates after any policy or dependency change. Recheck held-out
data integrity before each acceptance evaluation.

---

## 7. Phase 5 — Operational read-only pilot

**Entry.** Earlier gates pass and evaluation supports proceeding.

**Objective.** Run ScamWall against the real household network for a defined
period, changing nothing.

### 7.1 Work items

1. Scope, observation period, stop conditions, and operator responsibilities —
   agreed **before** launch, because a stop condition invented after a problem
   appears is a negotiation, not a control.
2. Scheduling with overlap prevention, bounded retries, cancellation.
3. Distinguish healthy, stale, degraded, authentication-failed, and disabled.
   Collapsing these into up/down is what makes an outage invisible: a feed that
   has been stale for a week reports "healthy" under a naive check.
4. Bounded logs and storage; redacted sensitive fields; documented retention.
5. **No DNS query history collected by default.** This is a household network.
   The query log is the most sensitive data in reach and ScamWall has no need
   for it in this phase.
6. Test restart, power interruption, clock issues, feed outages, credential
   rotation, application upgrades.
7. Dependency and licence inventory; release evidence tied to source and image.
8. Safe installation, update, diagnostics, and recovery instructions.

### 7.2 Acceptance

The agreed observation period and review volume are completed. Failures and
incorrect proposals are measured, and each is resolved or explicitly accepted.
No Pi-hole blocking-state change occurs. Resource and privacy requirements
hold.

### 7.3 Previous-phase validation

Run applicable earlier gates before pilot start and after every pilot software
or configuration change. Re-evaluate accuracy whenever detection behavior
changes.

---

## 8. Phase 6 — Controlled enforcement

**Entry.** Phases 1–5 pass.

**Household enforcement remains disabled pending a separate review of concrete
results.** Reaching this phase authorises building and testing enforcement in
isolated environments. It does not authorise turning it on.

### 8.1 Work items

1. Implement and test against disposable Pi-hole instances first.
2. Track ScamWall-owned entries **without assuming exclusive ownership** of
   entries the user already had. Pi-hole's blocklists are a shared namespace;
   an entry ScamWall did not create is not ScamWall's to remove.
3. Recheck plan expiry, target identity, policy/feed identity, and
   observed-state preconditions immediately before applying — not at plan time.
4. Absolute and proportional change limits. A plan that wants to add ten
   thousand entries, or to triple the blocklist, stops and asks.
5. Journal operations; reconcile partial success.
6. Idempotent repeated application.
7. Detect concurrent user changes.
8. Conditional rollback that preserves later user changes and reports
   conflicts rather than resolving them silently.
9. Test interruption between **every** meaningful mutation step.
10. Verify disable, uninstall, and recovery remove only attributable changes.
11. Define stale-feed behavior for entries already applied.
12. A limited deployment proposal: exact changes, limits, monitoring, rollback
    commands.
13. Widen the structural guards. `TestNoMutatingEndpoints` scans only
    `internal/adapters/pihole/`, which is correct while that is the only
    package able to make an HTTP request. The moment enforcement gains network
    access the guard stops covering the thing it exists to cover, so it is
    widened in the same change — not afterwards.

### 8.2 Acceptance

Mutation and recovery tests pass in isolated environments. No user-managed
change is overwritten or removed improperly. Partial failures leave
understandable, recoverable state. All earlier applicable gates pass against
the enforcement candidate. The operator reviews the concrete deployment
proposal before any live enforcement.

### 8.3 A structural note

Phase 1 made enforcement *absent* rather than *disabled*: there is no
`enforce`-tagged source file, so `go build -tags enforce` fails to compile
rather than producing an enforcing binary. Phase 6 necessarily introduces that
file. That single change demotes every Phase 1 and Phase 2 container and
command-surface row to `IMPLEMENTED-UNVERIFIED` until the gates are re-run
against the enforcement candidate — by design.

---

## 9. Standing constraints

These hold in every phase.

* **Do not push, merge, publish, or enable live enforcement.**
* **Docker operations are operator-executed.** No Docker socket access, no
  repository ownership change, no `safe.directory` exception.
* **Secrets, network topology, and household data stay out of public commits
  and diagnostic output.** Staged content is reviewed and secret checks are run
  before every commit.
* **Do not rewrite working components without a demonstrated requirement.**
* **Never convert a failed prerequisite or an unavailable required check into a
  pass.**
