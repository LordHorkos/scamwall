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
| `commercial_use` | permitted, prohibited, conditional, unknown |
| `caching` | permitted, prohibited, conditional, unknown |
| `redistribution` | permitted, prohibited, conditional, unknown |
| `attribution_required` | yes, no, unknown |
| `derived_data_restrictions` | what the licence says about data derived from it |
| `upstream_sources` | the sources it aggregates, where documented |
| `aggregation_dependencies` | known shared upstreams with other registry entries. This is what stops three feeds being counted as three independent sources |
| `access_status` | the disposition. Exactly one, from the vocabulary in §3 |
| `disposition_reason` | why the record carries that disposition. **Added by the implementation — FINDING-61.** §3 requires that a source whose documentation cannot be read "stays `unresolved` with the reason recorded", and §2 as written provided nowhere to record it |
| `privacy_implications` | what personal data it carries, and whose |
| `intended_permitted_use` | the use this project intends, checked against the fields above |
| `operational_cost` | only where officially published; otherwise `unknown` |
| `enabled` | boolean. Defaults to false and stays false until qualification completes |

One field belongs to the file rather than to a record:

| Field | Meaning |
| --- | --- |
| `retired_source_ids` | identifiers that were used once and must never be used again. **Added by the implementation — FINDING-62.** §2 requires that a `source_id` is "never reused, never renumbered", and that cannot be checked against the current file alone: an id deleted in one commit is free for the taking in the next. Retiring it is what makes the rule enforceable |

**Technical availability and permission to use are different fields and are
never collapsed.** A feed that downloads without authentication may still
prohibit the use intended for it.

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
| An empty string is refused wherever `unknown` is the available answer, so that not knowing is stated rather than implied | §2 |
| `kind`, `authentication`, the three rights fields, `attribution_required` and `access_status` are closed vocabularies | §2, §3 |
| `source_id` is unique within the file, and cannot take an identifier listed in `retired_source_ids` | §2 |
| Two records cannot claim the same `catalog_ref` | §2 |
| A record whose disposition is anything but `unresolved` must carry a real, non-future `verified_on` and an `https` documentation URL | §2 — *"a record with no date states nothing current"* |
| `unresolved` may leave both `unknown`, because it means nobody has looked | §3 |
| `enabled: true` requires `access_status: verified-available` **and** `commercial_use`, `caching` and `redistribution` each `permitted` or `conditional` — never `prohibited`, never `unknown` | §1 |
| `aggregation_dependencies` must name records that exist, and not the record's own id | §2 |
| The shipped registry enables nothing and claims no `verified-available` disposition | ORDER 2 has qualified no source |

### Not enforced, and not enforceable here

* **Whether any field is true.** `commercial_use: permitted` is checked to be a
  member of the vocabulary. Whether the provider's licence actually permits
  commercial use is a human reading a human document, and no validator can do
  it. The same holds for every other field a person types.
* **Whether `official_documentation` belongs to the provider.** It is checked to
  be an absolute `https` URL. Nothing checks whose.
* **Whether `upstream_sources` is complete**, and therefore **whether two
  sources are independent**. `aggregation_dependencies` is checked for dangling
  references; it cannot discover a shared upstream nobody recorded. Independence
  remains a research finding, not a computed property. This is the limit that
  matters most, because §2 offers that field as the thing that "stops three
  feeds being counted as three independent sources" — it stops three *recorded*
  dependencies being ignored, which is a smaller claim.
* **Whether a `conditional` right's condition is met.** `conditional` is
  accepted for an enabled source deliberately: the condition may well be
  satisfied, and where that judgement lives is `derived_data_restrictions` and
  `intended_permitted_use`. The validator checks that the judgement was made
  against a *stated* right, not that it was made correctly.

So the validator makes a false record harder to write **by accident**. It does
not make one impossible to write **on purpose**, and it is not evidence about
any provider.

