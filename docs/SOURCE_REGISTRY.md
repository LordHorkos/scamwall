# ScamWall Source Registry — structure

<!-- SPDX-License-Identifier: AGPL-3.0-only -->

**Status: STRUCTURE ONLY. No source has been imported, researched, contacted,
or qualified. Nothing here is evidence about any provider.**

ORDER 1 directs that this structure be prepared alongside the operator-safety
work, and that bulk collection and commercial integration wait for the
qualification ORDER 2 defines. This file is the schema and the rules. The
registry it describes is **empty**.

---

## 1. What this is for

The catalog supplied with the orders lists 85 entries and a proposed ingestion
order. **The complete catalog is present in the order text**, entries 1–85 plus
the two recommended waves, so ORDER 2 does not need it re-supplied.

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
| `access_status` | see §3 |
| `privacy_implications` | what personal data it carries, and whose |
| `intended_permitted_use` | the use this project intends, checked against the fields above |
| `operational_cost` | only where officially published; otherwise `unknown` |
| `enabled` | boolean. Defaults to false and stays false until qualification completes |

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

ORDER 2 opens when ORDER 1's acceptance is met and the operator has read its
result. Until then this file describes a shape and holds no data.
