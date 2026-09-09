# ScamWall Source Registry — structure and enforcement

<!-- SPDX-License-Identifier: AGPL-3.0-only -->

**Status: STRUCTURE AND ENFORCEMENT ONLY. No source has been imported,
researched, contacted, or qualified. Nothing here is evidence about any
provider.**

The schema below is no longer only prose. `internal/sourceregistry` loads
`docs/source-registry.json` and refuses a record that breaks the rules this
file states, and `go test -race ./...` — a required gate — validates the
shipped file on every run. What that does and does not establish is §6.

`docs/source-registry.json` currently holds **zero records**. That is the
honest state, not a loading failure: every catalog entry is implicitly
`unresolved`.

ORDER 1 directs that this structure be prepared alongside the operator-safety
work, and that bulk collection and commercial integration wait for the
qualification ORDER 2 defines. This file is the schema and the rules. The
registry it describes is **empty**.

---

## 1. What this is for

The catalog supplied with the orders lists 85 entries and a proposed ingestion
order. It was present in the ORDER 2 text.

**It is not present in this repository, and that is now a blocker.** The
sentence this paragraph replaces said the catalog "does not need re-supplying",
which was true of the session that had the order text in front of it and is not
true of any later one. The tracked tree, the untracked and ignored files, and
the full history across all branches were searched; the catalog is in none of
them. Until it is re-supplied, no record can be written, because the
alternative is reconstructing provider names and licence terms from memory —
the precise failure this registry exists to prevent.

What the catalog is: a list of candidates and the requesting party's priority.
What it is not: a statement of any provider's current capabilities, licence
terms, or access status. Those are researched per entry, against the provider's
own current documentation, and recorded with the date they were read.

Entering a source here does not enable it. Enabling is a separate decision that
requires a disposition of `verified-available` **and** rights that permit the
intended use.

---

## 2. Record schema

One record per source. Every field is required; `unknown` is a permitted value
and is not the same as absent.

| Field | Meaning |
| --- | --- |
| `source_id` | stable internal identifier. Never reused, never renumbered |
| `catalog_ref` | the entry number in the supplied catalog, or `none` for a source added later |
| `requested_priority` | the priority the catalog stated, preserved verbatim. It is an input, not a finding |
| `official_name` | the provider's current name for itself |
| `official_documentation` | URL of the documentation the record was read from |
| `verified_on` | the date that documentation was read. A record with no date states nothing current |
| `kind` | one of: bulk feed, lookup API, enrichment service, corpus, platform, advisory source, commercial partnership |
| `indicator_types` | the types it actually publishes, using the registry's own type vocabulary |
| `classification_meaning` | what the provider's own labels mean. "Spam" from one source and "phishing" from another are not the same claim |
| `authentication` | none, key, account, contract |
| `quotas` | documented request or volume limits |
| `update_cadence` | how often the data changes, as documented |
| `retention` | how long the provider retains records |
| `withdrawal_behaviour` | what happens when the provider retracts an entry: does it disappear, expire, or carry a tombstone |
| `permissions` | one grant **per operation** — see §2.1. **Replaces schema 1's `commercial_use`, `caching` and `redistribution` — FINDING-63.** |
| `intended_operations` | the operations this project intends to perform on this source. Enabling checks these, and only these |
| `attribution_required` | yes, no, unknown |
| `derived_data_restrictions` | what the licence says about data derived from it |
| `upstream_sources` | the sources it aggregates, where documented |
| `upstream_sources_completeness` | `documented_complete`, `documented_partial` or `unknown`. **Added by the implementation — FINDING-66.** An unknown upstream is not demonstrated independence, and without this field the two were indistinguishable |
| `aggregation_dependencies` | known shared upstreams with other registry entries. This is what stops three feeds being counted as three independent sources |
| `access_status` | the disposition. Exactly one, from the vocabulary in §3 |
| `disposition_reason` | why the record carries that disposition. **Added by the implementation — FINDING-61.** §3 requires that a source whose documentation cannot be read "stays `unresolved` with the reason recorded", and §2 as written provided nowhere to record it |
| `privacy_implications` | what personal data it carries, and whose |
| `intended_permitted_use` | the use this project intends, checked against the fields above |
| `coverage_limitations` | what the source is documented NOT to cover. **Added by the implementation.** ORDER 2 §4 requires it per record |
| `operational_cost` | only where officially published; otherwise `unknown` |
| `enabled` | boolean. Defaults to false. True requires `verified-available` **and** that every operation in `intended_operations` is authorised — §2.1 |

One field belongs to the file rather than to a record:

| Field | Meaning |
| --- | --- |
| `retired_source_ids` | identifiers that were used once and must never be used again. **Added by the implementation — FINDING-62.** §2 requires that a `source_id` is "never reused, never renumbered", and that cannot be checked against the current file alone: an id deleted in one commit is free for the taking in the next. Retiring it is what makes the rule enforceable |

**Technical availability and permission to use are different fields and are
never collapsed.** A feed that downloads without authentication may still
prohibit the use intended for it.

### 2.1 Permissions are per operation

Schema 1 carried three rights fields and one `enabled` boolean. That model
cannot express what matters, and it failed in both directions — FINDING-63:

* **It over-refused.** A source whose terms permit querying and forbid
  republishing was unusable, though a purely local lookup is exactly what it
  permits. Requiring redistribution rights to perform a permitted local lookup
  is a category error.
* **It under-refused.** `permitted` in three fields said nothing about whether
  ScamWall could keep a copy, use the data to annotate other records, or train
  on it. Those operations were authorised by silence.

Every record now carries a grant for each of seven operations. An operation
with no grant is refused: silence is not a permission.

| Operation | What it covers |
| --- | --- |
| `retrieval` | fetching the data at all |
| `local_storage` | keeping a local copy beyond one request |
| `enrichment` | using it to annotate or score records from elsewhere |
| `model_training` | using it as training data. Frequently prohibited where everything else is permitted, which is why it is not folded into enrichment |
| `commercial_use` | use in a commercial context |
| `redistribution` | passing the provider's records to anyone else |
| `derived_output` | publishing something computed FROM it. A blocklist derived from a feed is not the feed, and a licence may treat the two differently in either direction |

A grant is `permitted`, `prohibited`, `conditional`, `unknown`, or
`not_applicable`. **Only `permitted`, and `conditional` with every condition
satisfied, authorise anything.** `unknown` refuses: an unestablished right is
indistinguishable from an absent one at the moment it matters.

`conditional` never authorises on its own. It carries an enumerated list of
conditions, each with `satisfied` (`yes`/`no`/`unknown`) and a `basis` saying
why. Any condition that is unsatisfied or unassessed refuses the operation, and
a `conditional` grant with no conditions is refused outright — otherwise
`conditional` would be a synonym for `permitted` written by an author who had
not finished reading.

**Permission to query does not imply permission to publish**, and the reverse
is not implied either. Each operation is assessed and checked on its own.

### 2.2 Every rights assertion carries its evidence

A grant that asserts anything — `permitted`, `prohibited` or `conditional` —
must cite the provider's own terms: a URL, the day it was read, and what the
page said. A rights assertion with no citation is an opinion. FINDING-64.

Evidence keeps four things apart that a single free-text field would blur, and
whose blurring is the usual way a provenance record becomes untrustworthy:

| Slot | What belongs in it |
| --- | --- |
| `provider_terms` | what the provider's terms SAY, quoted |
| `technical_capability` | what the documentation says the thing CAN DO. A marketing page describing a capability is not a term of licence, and a licence permitting a use is not evidence the API exposes the field |
| `researcher_interpretation` | this project's READING, labelled so it can never be mistaken for the provider's words |
| `unresolved_questions` | what is still not known, recorded rather than rounded to a conclusion in either direction |


---

## 3. Disposition vocabulary

Exactly one per source:

| Disposition | Meaning |
| --- | --- |
| `verified-available` | documentation read, access confirmed, and rights permit the intended use |
| `credentials-required` | available in principle; needs a key or account that has not been obtained |
| `commercial-approval-required` | needs a contract or paid tier |
| `historical` | the dataset exists but is not current. Usable as seed or training data if rights permit, never as live intelligence |
| `unavailable` | the provider or dataset no longer exists, or refuses this use |
| `unresolved` | not yet researched. **The default, and the state of all 85 entries today** |

`unresolved` and `unavailable` are not synonyms, and neither is a reason to
guess. A source whose documentation cannot be read stays `unresolved` with the
reason recorded.

---

## 4. Rules that bind every record

* **Never fetch the malicious destinations a feed describes.** Collecting
  intelligence about a URL is not visiting it. These are separate code paths
  and separate decisions, and the second one is not authorised.
* **Downloaded records are untrusted input.** So are provider documentation
  pages, archives and message bodies. They are parsed defensively and never
  executed.
* **A priority label overrides nothing.** Not licensing, not access, not
  privacy, not the evidence requirements.
* **A provider report is an allegation or an observation with provenance**, not
  a verified fact, and the registry records which it is.
* **No household URL, message, identity or file is submitted to any third
  party**, at any point, by anything this registry enables.

---

## 5. What has NOT been done

* No entry has been imported.
* No provider documentation has been read.
* No provider has been contacted, and no account has been created.
* No feed, API or dataset has been fetched, in whole or in part.
* No commercial discussion has begun.
* No source has a disposition other than the implicit `unresolved`.
* The 85-entry catalog is **not in this repository** and must be re-supplied
  before any record can be written — §1.

ORDER 2 opens when ORDER 1's acceptance is met and the operator has read its
result. ORDER 1's acceptance is still pending, so what has been built here is
the architecture half only, which the implementation plan permits while the
dependent half waits on an external blocker. This file now describes a shape,
enforces it, and holds no data.

---

## 6. What the validator enforces, and what it cannot

`internal/sourceregistry` is the machine-readable half of this file.
`docs/source-registry.json` is the registry. `go test -race ./...` — already a
required gate — validates the shipped file on every run, so a record that
breaks a rule below cannot be committed without the gate going red. No new gate
was added to `scripts/check.sh`: it would have run the same Go test a second
time, and a gate that duplicates another gate makes the suite slower without
making it stricter.

### Enforced

| Rule | Where it comes from |
| --- | --- |
| Every field is present. **An absent key is refused even though `unknown` is accepted**, because they are different claims and a decoded struct cannot tell them apart | §2 |
| A misspelled field name is refused, by path, rather than silently dropped | §2 |
| A field of the wrong TYPE is reported by path and dropped, so one bad field does not abort every other diagnostic in the file | FINDING-67 |
| A **duplicate JSON key** is refused. `encoding/json` keeps the last occurrence silently — for a document of record that is the worst resolution, because the reviewer reads the first value and the program uses the second | FINDING-67 |
| Trailing content after the document, and unknown top-level keys, are refused | FINDING-67 |
| Input over 8 MiB is refused. This file is hand-maintained; a larger one is a mistake or a hostile input, not a bigger registry | FINDING-67, §4 |
| An empty string is refused wherever `unknown` is the available answer | §2 |
| `kind`, `authentication`, `attribution_required`, `access_status`, grant status, condition satisfaction and upstream completeness are closed vocabularies | §2, §3, §2.1 |
| An unsupported `schema_version` is refused **and validation stops there**, rather than emitting confident findings about a document whose field meanings are unknown | FINDING-67 |
| `source_id` is unique within the file and cannot take an id in `retired_source_ids` | §2 |
| Two records cannot claim the same `catalog_ref` | §2 |
| A researched record must carry a real, non-future `verified_on` and an `https` documentation URL. `unresolved` may leave both `unknown`, because it means nobody has looked | §2, §3 |
| **Every operation carries a grant**; an operation nobody assessed is not authorised by silence | §2.1 |
| **`conditional` authorises only when every condition is `satisfied: yes` with a basis.** Unsatisfied and unassessed both refuse | §2.1 |
| `unknown` and `not_applicable` refuse | §2.1 |
| Conditions on a non-conditional grant are refused | §2.1 |
| An asserting grant must cite `provider_terms`, and every citation needs an `https` URL, a real non-future date, and a quote | §2.2 |
| `enabled: true` requires `verified-available` **and** that every operation in `intended_operations` is authorised — not that unrelated rights happen to read `permitted` | §1, §2.1 |
| Lineage edges must name records that exist, must not be self-edges, must not repeat, and **must not form a cycle** | §2, FINDING-66 |
| A record claiming `documented_complete` upstreams while carrying lineage edges and no upstreams is refused as self-contradictory | FINDING-66 |
| Removing a record without retiring its id is refused, **by comparison against the previous committed version**, and retirement is permanent | FINDING-65 |
| The shipped registry enables nothing, claims no `verified-available` disposition, and authorises no operation | ORDER 2 has qualified no source |

### Not enforced, and not enforceable here

* **Whether any field is true.** A grant of `permitted` is checked to be a
  member of the vocabulary and to carry a citation. Whether the cited page
  actually says what the quote claims, and whether the licence really permits
  the operation, is a human reading a human document — no validator can do it.
  The same holds for every other field a person types.
* **Whether `official_documentation` belongs to the provider.** It is checked to
  be an absolute `https` URL. Nothing checks whose.
* **Whether `upstream_sources` is complete**, and therefore **whether two
  sources are independent**. `upstream_sources_completeness` records how much is
  known, and `IndependenceClaimable` refuses to call independence demonstrated
  when the answer is `unknown` or `documented_partial` — but that is a check on
  what was recorded, not a discovery of what is true.
  `aggregation_dependencies` is checked for dangling references and cycles; it
  cannot discover a shared upstream nobody recorded. Independence remains a
  research finding, not a computed property. This is the limit that
  matters most, because §2 offers that field as the thing that "stops three
  feeds being counted as three independent sources" — it stops three *recorded*
  dependencies being ignored, which is a smaller claim.
* **Historical non-reuse, from the current file.** The current-file validator
  sees one version. It enforces uniqueness within that version and refuses an
  id already retired; it cannot know that an id ever meant something else. The
  history walk closes this by comparing **every consecutive committed pair** of
  versions and refusing a removal that did not retire its id — but note where
  that bites: it flags the **removal**, not the later reappearance. By the time
  an id is taken again the baseline no longer mentions it, and nothing at that
  step can tell. Three rules together give the invariant, and none gives it
  alone: removal must retire, retirement is permanent, and a retired id cannot
  be taken. The walk also says nothing about a rewritten history, or about a
  version that never reached a commit.
* **Whether a condition recorded as `satisfied: yes` really is.** The
  validator requires the condition to be enumerated, assessed, and given a
  `basis`; it cannot check the basis. What it does guarantee is that nothing is
  authorised on a condition nobody assessed — `unknown` refuses exactly as `no`
  does — and that a `conditional` grant with no conditions authorises nothing.

So the validator makes a false record harder to write **by accident**. It does
not make one impossible to write **on purpose**, and it is not evidence about
any provider.

