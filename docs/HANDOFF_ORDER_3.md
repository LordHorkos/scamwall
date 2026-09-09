# ScamWall — ORDER 3 handoff

<!-- SPDX-License-Identifier: AGPL-3.0-only -->

**Nothing was pushed. No Docker image was built. No container was started. No
request reached the household Pi-hole. No credential was opened. No provider was
contacted, registered with, or paid. No feed, dataset or indicator was
fetched.**

This is the record of one autonomous session. It is a summary with pointers;
the evidence lives in `docs/VERIFICATION.md`, the requirement states in
`docs/REQUIREMENTS_MATRIX.md`, and the source records in
`docs/source-registry.json`.

---

## 1. Commits

| | |
| --- | --- |
| Starting HEAD | `c35b1e601f2543cb666d34888c61b08406446106` |
| Ending HEAD | `d38a072` … plus this handoff commit — see the last row of §7 |
| Branch | `feat/phase-1-core`, **33 commits ahead** of `origin/feat/phase-1-core` at session start, 0 behind |
| Pushed | **No.** Pushing is not authorised by the order this session ran under |

| Commit | Purpose |
| --- | --- |
| `9bbf284` | **feat(registry): put the catalog in the repository, and qualify all 85 entries.** Adds `docs/SOURCE_CATALOG.md`; takes `docs/source-registry.json` from 0 records to 85; fixes FINDING-69 in `internal/sourceregistry`; replaces the shipped-registry authorisation test |
| `d38a072` | **docs: reconcile the operator evidence, correct the renewal rule, make the plan actionable.** Adds VERIFICATION §3.23 and FINDING-70; corrects the matrix's renewal table; adds the first-wave proposal and adapter specification; amends the evaluation protocol |
| *(this commit)* | **docs: record the ORDER 3 gate run and the handoff.** VERIFICATION §3.24 and this file |

### Files changed

| File | Change |
| --- | --- |
| `docs/SOURCE_CATALOG.md` | **New.** All 85 catalog entries, transcribed |
| `docs/source-registry.json` | 0 → **85 records** |
| `docs/SOURCE_REGISTRY.md` | Status, coverage table, §3.1 on the disposition strain, §4.1 on the rules the research turned into findings, §6 on the replaced test |
| `internal/sourceregistry/registry.go` | FINDING-69: `unknown` added to the `kind` and `authentication` vocabularies |
| `internal/sourceregistry/registry_test.go` | Three FINDING-69 cases; the shipped-registry authorisation test split and replaced |
| `docs/VERIFICATION.md` | §3.23 (evidence grades and the access blocker), §3.24 (this gate run), FINDING-69, FINDING-70 |
| `docs/REQUIREMENTS_MATRIX.md` | Renewal-rule correction; working-candidate row; five reconciliation rows |
| `docs/IMPLEMENTATION_PLAN.md` | §5.4 first-wave proposal, §5.5 adapter specification, §5.6 roadmap dependencies |
| `docs/EVALUATION_PROTOCOL.md` | §2.1, §4.3, §5.1, §5.2, §6.1, §6.2, §7.1, §8.1, §9.1 |

---

## 2. Operator evidence reconciliation

**This account inspected no file.** `/tmp/tmp.4mtoNEjwv3/` is `root:root` mode
`0700`; `ls` and `head` on the directory and on each of `evidence/verify.log`,
`evidence/version.log` and `evidence/build.log` returned `Permission denied`.
`sudo`, any permission or ownership change, and any read of `raw/` were
forbidden by the order and were not attempted.

`docs/VERIFICATION.md` §3.22 said the returned evidence was "counts rather than
a per-assertion listing". That was wrong: sanitized transcripts exist, and their
contents were relayed in the order text. §3.23 records the correction, grades
the evidence — **(A)** direct inspection, none; **(B)** operator-supplied
transcript evidence, relayed; **(C)** operator-reported terminal results — and
sets out what each grade establishes.

| Requirement | Status | Bound to |
| --- | --- | --- |
| **SW-P1-05** | **VERIFIED**, unchanged by this session | commit `c35b1e6`, image `sha256:0efff150…` |
| **SW-P1-20** | **VERIFIED**, unchanged by this session | the same commit and image |
| **SW-P1-13** | VERIFIED — demoted by `9bbf284`'s Go-source change and renewed by the §3.24 run | `d38a072` |
| **SW-P1-12** | **IMPLEMENTED-UNVERIFIED.** The one open Phase 1 row | needs an approved push and a hosted run |
| Every other Phase 1 row | VERIFIED, unmoved | as recorded |
| **SW-P2-04** and all of Phase 2 | **BLOCKED**, untouched | no container was started |

The relayed transcript evidence adds, without changing any status: the verifier
ran against the pinned image identity; all four approved mount sources existed
as regular files; the permission judgement used `uid=0, gid=989, mode=0640` with
no extended ACL; the configured supplementary group was `989`; the daemon
reported no user-namespace remapping; the inspection container was created and
never started; build steps #13 and #14 executed uncached.

**Kept pending, as the order requires:** hosted CI / SW-P1-12; an actual
credential read inside the deployment container; live destination and TLS
checks; authentication and session teardown on Pi-hole; secret-content
comparison.

**FINDING-68** stays recorded and unfixed — stale explanatory output in the
verifier, `docs/VERIFICATION.md` §4.19. The tested verifier was not edited.

---

## 3. Catalog coverage

| | |
| --- | --- |
| Catalog entries | **85** |
| Records in `docs/source-registry.json` | **85** — one per entry, none omitted, none substituted |
| Researched against primary provider documentation | **74** |
| Documentation unreadable, blocker named per record | **11** — catalog 34, 35, 42, 47, 50, 58, 64, 65, 71, 75, 84 |
| Partially blocked, disposition deliberately not inferred | 2 — catalog 74, 77 |

| Disposition | Count |
| --- | --- |
| `commercial-approval-required` | 21 |
| `credentials-required` | 14 |
| `historical` | 6 |
| `unavailable` | 3 |
| `unresolved` | 41 |
| **`verified-available`** | **0** |
| **Enabled** | **0** |
| Records declaring an intended operation | **0** |
| Records whose terms authorise any operation | 2 — catalog 37 and 80, both CC0 |

**Why `verified-available` is zero.** §3 requires access to be *confirmed*, and
this order forbids fetching the data. So access is documented everywhere and
confirmed nowhere. **The 41 `unresolved` records are not 41 unexamined ones**:
11 are unreadable, 7 are read but state no terms, and the rest are fully
researched with only access confirmation outstanding.
`docs/SOURCE_REGISTRY.md` §3.1 states that strain and declines to redesign the
vocabulary to relieve it.

---

## 4. First-wave proposal

Four sources, in prose only, at `docs/IMPLEMENTATION_PLAN.md` §5.4. **None is
enabled and none declares an intended operation in the registry.**

| Source | Operation proposed | The evidence still needed |
| --- | --- | --- |
| `src-0062` Scam Sniffer open database | `retrieval`, `local_storage` | The file itself, read once; an operator decision on GPL-3.0 in an AGPL-3.0-only distribution; a measurement of what the published **seven-day delay** costs |
| `src-0008` Phishing.Database | `retrieval`, `local_storage` | File shapes; an overlap measurement against `src-0022`; note that `IndependenceClaimable` is **false** here |
| `src-0022` HaGeZi — **TIF list only** | `retrieval`, `local_storage` | That the TIF list can be taken without the tiers; the overlap measurement; an explicit decision to exclude the advertising and tracking tiers |
| `src-0024` CERT Polska Warning List | `retrieval`, `local_storage` | **A written answer on reuse terms.** Everything else about this source is better than its alternatives — statutory basis, six-month expiry, statutory appeal, RPZ export, five-minute cadence — and none of it can be used without one |

**Rejected, with reasons in §5.4:** OpenPhish (terms forbid detection and
enrichment), Phishing Army (aggregates four catalog entries; inherits a
redistribution conflict), StevenBlack (mixed upstream licences including
non-commercial; mostly advertising), Spamhaus DBL (a live query discloses
household browsing), the account-gated feeds (registering is an operator
decision), FakeFilter and CryptoScamDB (no licence at all), and all 21
`commercial-approval-required` records.

**No source was selected for having been marked "VERY HIGH".** The catalog as
supplied carried no priority labels at all, and `requested_priority` reads
`unknown` on all 85 records.

**The adapter specification** — `docs/IMPLEMENTATION_PLAN.md` §5.5, for
`src-0062` — specifies a parser and converter with synthetic examples and
expected validation behaviour, produces a `feed.Manifest` that goes through the
existing signed feed path, and specifies **no network code and no threat
score**. It records that `feed.Record` has no field naming its source, which is
a Phase 3 schema change the first wave cannot ship without.

---

## 5. Test totals and exit statuses

| Command | Result | Direct exit status |
| --- | --- | --- |
| `bash scripts/check.sh` on the clean committed tree at `d38a072` | **26 passed, 0 failed, 2 BLOCKED, 0 optional-skipped** | **1** |
| `go test -race -count=1 ./...` | 9 packages ok, 0 failed | **0** |
| `internal/sourceregistry` | 109 top-level tests, 158 with sub-tests, 0 failed | 0 |
| `scripts/tests/runtime-verify-test.sh` | **358 tests, 0 failed** | 0 |
| `scripts/tests/operator-handoff-test.sh` | **393 tests, 0 failed** | 0 |

`check.sh` exits 1 because two required gates could not run, not because any
gate failed. Both are the Docker pair: `docker version` succeeds, `docker ps`
returns `permission denied ... unix:///var/run/docker.sock`. The service account
is not in the `docker` group and **no attempt was made to change that**.

Evidence: `docs/VERIFICATION.md` §3.24.

---

## 6. Remaining blockers, by kind

### Access — nothing in this repository can resolve these

| Blocker | Effect |
| --- | --- |
| Docker daemon unreachable by the service account | 2 gates permanently BLOCKED locally; every image-bound row needs an operator run |
| The operator's sanitized transcripts are root-owned mode 0700 | The run stands at evidence grade (B). Three files would reach (A): `evidence/verify.log`, `evidence/build.log`, `evidence/version.log` — **not `raw/`** |
| No push, so no hosted run | SW-P1-12 cannot move |
| 11 providers' documentation unreachable — 403, unverifiable TLS, refused host, timeout | Those catalog entries stay `unresolved` |
| Registering accounts, accepting terms, buying services | 35 records at `credentials-required` or `commercial-approval-required` cannot advance |

### Implementation — work this project can do when authorised

| Blocker |
| --- |
| `feed.Record` has no field naming its source. The first wave cannot ship without one; it is a Phase 3 schema change |
| No attribution mechanism exists, so every MIT, CC-BY and GPL notice condition in the registry is recorded unsatisfied |
| `domain.Normalize` still conflates invalidity with a homograph signal, so a mixed-script domain is dropped as unparseable — `docs/IMPLEMENTATION_PLAN.md` §5 item 5 |
| No fetch, scheduling or snapshot-retention code exists |
| FINDING-68's wording fix is deferred, because editing the verifier's emitted text demotes the rows the operator's run just renewed |

### Evidence — questions someone must answer

| Question | Who |
| --- | --- |
| CERT Polska's reuse terms | Requires asking CERT Polska |
| Is ScamWall a commercial product? | The requesting party. Several first-wave records turn on a NonCommercial term recorded `unknown` for exactly this reason |
| GPL-3.0 data in an AGPL-3.0-only distribution | The requesting party, on advice |
| What a false block costs this household; which tasks are essential | The household |
| Every threshold in `docs/EVALUATION_PROTOCOL.md` §8 | See §8.1 for who owns which |

---

## 7. The single next operator action

> **Review the two commits, and if they are acceptable, approve a push of
> `feat/phase-1-core` so a hosted run can execute the 28-gate list against a
> commit newer than `72bc84c`.**

That is the only action that moves the one open Phase 1 row. SW-P1-12 is the
last thing standing between this branch and a complete Phase 1, and no local
work can touch it.

**Second, if a further local action is wanted rather than a push:** attach the
three sanitized transcript files named in §6, or their hashes, to
`docs/VERIFICATION.md` §3.23. That costs nothing, risks nothing, and moves the
operator evidence from grade (B) to grade (A).

**Do not** run steps B, C or D of `docs/VERIFICATION.md` §6.5 on the strength of
this session. Nothing here establishes that the container can authenticate,
read its mounted secret, or reach the appliance safely.

---

## 8. Confirmation

* **Nothing was pushed.** `git push` was not run. The branch is local and ahead
  of its upstream.
* **No live Pi-hole operation occurred.** No request was sent to the household
  appliance, no credential was opened, and no operator step was executed.
* **No indicator data was fetched.** Research was provider documentation only.
  No feed, dataset, sample or message corpus was retrieved.
* **No account was created, no terms accepted, nothing bought.**
* **No privileges were widened.** No `sudo`, no group change, no permission or
  ownership change, and no `safe.directory` exception.
* **Nothing was reset or discarded.** The uncommitted documentation changes
  present at session start were preserved and are part of `d38a072`; no
  `git reset --hard`, `git clean` or temporary commit was used.
