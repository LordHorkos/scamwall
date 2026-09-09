# ScamWall Effectiveness Evaluation Protocol

<!-- SPDX-License-Identifier: AGPL-3.0-only -->

**Status: PROTOCOL ONLY. Nothing here has been run. No evaluation data has been
acquired, no labels obtained, no measurement taken, and no threshold agreed.**

This document is written **before** any evaluation data exists, which is the
only order in which it is worth anything. A protocol written after the numbers
are in is a description of the numbers.

It prepares ORDER 9. It is not permission to run live blocking, and it does not
open Phase 4.

---

## 1. The question, stated so it can fail

> Does adding ScamWall's proposed decisions to an existing Pi-hole
> configuration block additional malicious destinations, and at what cost in
> additional legitimate destinations wrongly proposed?

Two quantities, measured together and reported together. A protocol that
measures only the first is a protocol for producing a favourable number.

**No accuracy target is proposed here, and no improvement is claimed.** §8
proposes thresholds for review; they are proposals with reasons, to be agreed
*before* the held-out run, and they are not predictions.

---

## 2. The comparison

Evaluation compares two configurations over the same traffic, in the same
window.

| | Configuration |
| --- | --- |
| **Baseline** | The household Pi-hole as it is actually configured: its current blocklists, at their versions on the evaluation start date, with its current allowlist and local overrides |
| **Candidate** | Baseline **plus** the decisions ScamWall proposes from its first-wave sources |

Three properties this comparison must have, each of which is easy to lose:

* **The baseline is the real one.** Comparing against a bare Pi-hole with no
  lists would measure "does a blocklist help", which is not the question and
  has a known answer. The value ScamWall must demonstrate is value *on top of
  what the household already runs*.
* **The baseline lists are pinned by version and date.** A baseline that
  updates during the window is a moving comparison, and any difference is then
  partly the other project's work.
* **Neither configuration blocks anything during the evaluation.** Both are
  evaluated as *proposals* against observed traffic. Enforcement is ORDER 10
  and is separately gated.

**Recorded before the run:** every baseline list, its version or fetch digest,
its fetch date, and the allowlist and local overrides in force.

---

## 3. Labels must come from somewhere other than the thing being tested

The central failure of feed evaluation is grading a feed against feeds. If a
destination is labelled malicious because a source says so, and ScamWall
proposed it because that same source said so, the measurement is a tautology
with error bars.

**Requirements for a label to count:**

| Requirement | Why |
| --- | --- |
| The labeller is not in the candidate's source set, and does not share a documented upstream with any of them | Otherwise agreement measures shared lineage, not truth. `upstream_sources_completeness` in the registry is what makes this checkable, and `unknown` upstreams do not satisfy it |
| The label is dated, and the date is comparable to the observation | A destination malicious in March and benign in September is two different labels |
| The labelling basis is recorded | "Reported as spam" and "observed serving a credential-harvesting page" are different claims and must not be pooled |
| Abstention is available | A labeller that must answer produces answers it does not have. **`unknown` is a first-class outcome and is reported, never redistributed into the other two** |

**Where labels may come from**, in descending order of strength: direct
observation with evidence retained; an independent provider whose registry
record permits this use; manual adjudication by a human with the basis
recorded. Manual adjudication is the fallback and its sample size is reported
separately, because it is small and its cost is what bounds the study.

**Rights prerequisite.** A source may be used for labelling only where its
registry record authorises the operations this requires — at minimum
`retrieval`, `local_storage`, and `enrichment`. A label set whose terms forbid
that use cannot be used, however convenient it is. See §7.

---

## 4. Leakage controls

Two kinds, both of which silently inflate results.

### 4.1 Temporal

* **Held-out window.** Thresholds, source selection and any tuning are fixed on
  a development window, and the reported result comes from a later window that
  was not consulted while tuning. The held-out window is declared, by date,
  before it is opened.
* **Point-in-time source state.** A decision is evaluated against what the
  source said **at the time of the observation**, not against the feed as it
  stands when the analysis runs. Evaluating today's feed against last month's
  traffic credits ScamWall with knowledge it did not have — this is the single
  most common way a retrospective feed evaluation produces an impressive and
  meaningless number.
* **Label-after-observation.** A label acquired after the observation is
  acceptable and is the normal case; a label acquired after *the decision was
  scored* is not, and the acquisition timestamp is recorded so the difference
  is auditable.

### 4.2 Source lineage

* Candidate sources that share a documented upstream are **not** counted as
  independent corroboration. The registry's `aggregation_dependencies` and
  `IndependenceClaimable` are the inputs to this.
* A labeller sharing an upstream with a candidate source disqualifies that
  labeller **for that decision**, not necessarily for the whole study.
* **An unknown upstream is not demonstrated independence.** Where lineage is
  undocumented, the decision is reported in a separate stratum rather than
  assumed clean.

---

## 5. What is measured

Per decision, over the held-out window:

| Quantity | Definition |
| --- | --- |
| **Additional malicious caught** | Destinations independently labelled malicious that the candidate proposes and the baseline does not block |
| **Additional legitimate wrongly proposed** | Destinations independently labelled legitimate that the candidate proposes and the baseline does not block |
| **Unchanged** | Destinations both configurations treat identically |
| **Abstentions** | Decisions ScamWall declines to propose. Counted, never silently dropped |
| **Unlabelled** | Destinations no qualifying labeller would adjudicate. Reported as its own number |

**Denominators are stated with every rate**, and rates are never reported
alone. "Caught 40% more" over eleven observations is not a finding.

**Uncertainty.** Every rate carries an interval appropriate to its
denominator — Wilson intervals for proportions, and the interval is reported
even when it is embarrassingly wide, because a wide interval is the honest
description of a small sample. A point estimate with no interval is not
reportable under this protocol.

**Stratification.** Results are reported per source and per indicator type as
well as pooled. A pooled number can hide one source contributing all the value
and another contributing all the false proposals, and the decision the study
exists to inform is which sources to keep.

---

## 6. Corrections and delay

Both are properties of a feed that a single-snapshot study cannot see, and both
change the operational picture more than accuracy usually does.

* **Feed delay.** For each destination independently labelled malicious with a
  known first-observation time, record when each candidate source first
  published it. Report the distribution, not a mean: a source that is usually
  fast and occasionally a week late has a different operational character from
  one that is uniformly a day behind.
* **Correction behaviour.** For each destination a source later withdraws or
  downgrades, record the withdrawal time and whether the mechanism is a
  disappearance, an expiry or a tombstone. **A source that silently drops
  entries cannot be distinguished from one that never had them**, which is why
  `withdrawal_behaviour` is a required registry field and why measuring this
  needs point-in-time snapshots retained from the start of the window.
* **Correction latency for our own errors.** Time from a legitimate destination
  being wrongly proposed to it being withdrawn. This is the number a household
  actually feels.

---

## 7. Data access and rights prerequisites

Before any evaluation data is acquired:

1. Every source used for **candidate decisions** has a registry record
   authorising `retrieval` and `local_storage`, and the evaluation's use of it
   falls inside `intended_operations`.
2. Every source used for **labelling** authorises the same, plus `enrichment`.
3. If any result is to be published outside the household, `derived_output` is
   authorised for every source contributing to it. **Permission to query is not
   permission to publish** — this is checked per source, not assumed from the
   study's purpose.
4. Retention of point-in-time snapshots is checked against each source's
   `retention` and `local_storage` terms. A protocol that requires keeping
   snapshots a licence forbids keeping is not runnable, and finding that out
   after collection starts is too late.
5. **No household traffic leaves the household.** Destinations observed locally
   are not submitted to third-party services for labelling. Where a label
   requires a third-party lookup, that is a lookup ScamWall must be able to
   perform without disclosing that *this* household saw *this* destination —
   and where it cannot, the destination goes to manual adjudication or stays
   unlabelled. This constraint is not negotiable for a convenience gain and it
   materially limits §3.

---

## 8. Thresholds proposed for review

**Proposals with reasons, for agreement before the held-out window opens. Not
targets, not predictions, and not claims about what the system achieves.**

| Proposed threshold | Rationale |
| --- | --- |
| Additional legitimate destinations wrongly proposed: **upper bound of the interval** below a rate the household agrees in advance | A false block is felt immediately and erodes trust in the whole system; the *upper* bound is used because a point estimate under a small denominator is not a bound |
| Additional malicious caught: a **lower** bound above zero | The system must demonstrate it adds something, and "the interval includes zero" means it has not |
| Unlabelled fraction below an agreed ceiling | Above it, the study is measuring the labeller's coverage rather than ScamWall's decisions |
| Per-source stratum reported regardless of pooled outcome | So a source that only adds noise is visible even when the pooled number is acceptable |

The numeric values are deliberately left blank. Filling them in here, before
the household has said what a false block costs it, would be inventing a
requirement and then meeting it.

---

## 9. What this protocol will still not establish

* **Anything about enforcement.** It measures proposals against observed
  traffic. Whether blocking those destinations is net-beneficial in daily use
  is ORDER 10's question and needs a pilot.
* **Generalisation beyond this household.** One household's traffic over one
  window. Nothing here supports a claim about anyone else's.
* **Anything about sources not in the candidate set**, including sources that
  were excluded because their rights did not permit this use. Their absence is
  a fact about the study, not about them.
* **A causal claim.** The comparison is observational. It shows a difference
  between two configurations over the same traffic; it does not isolate why.
