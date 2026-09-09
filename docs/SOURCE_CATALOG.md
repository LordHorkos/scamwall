# ScamWall Source Catalog — the 85 entries as supplied

<!-- SPDX-License-Identifier: AGPL-3.0-only -->

**Status: THIS IS A RESEARCH SCOPE, NOT A FINDING.** It is the list of
candidates the requesting party supplied, transcribed. It is not a statement
that any entry is available, current, lawfully usable for this project, or
suitable. Availability, rights and suitability are researched per entry and
recorded in `docs/source-registry.json` under the rules in
`docs/SOURCE_REGISTRY.md`.

---

## 1. Why this file exists

The catalog was supplied in the text of ORDER 2 and again in the text of the
present order. It had never been written into the repository, so the only copy
lived in a conversation. `docs/SOURCE_REGISTRY.md` §1 recorded that as a
blocker in plain terms: the tracked tree, the untracked and ignored files and
the full history across all branches were searched, and the catalog was in none
of them, so no record could be written without reconstructing provider names
from memory — the precise failure the registry exists to prevent.

This file removes that failure mode. A cleared conversation can no longer erase
the research scope.

**Transcription is the only claim made here.** Where an entry names a project
ambiguously, it is preserved as supplied and the ambiguity is resolved — with
evidence — in the registry record, not here.

## 2. Numbering

Two identifier spaces exist, and they are deliberately not the same one:

| Space | Owner | Rule |
| --- | --- | --- |
| **Catalog number**, 01 … 85 | the requesting party | Fixed by this list. It is an index into what was asked for, and it never changes, even if an entry proves to be a duplicate, a discontinued product or a renamed company |
| **`source_id`**, `src-NNNN` | this project | Assigned in the registry, never reused, never renumbered — `docs/SOURCE_REGISTRY.md` §2. Retirement is permanent |

A registry record carries `catalog_ref` to point back here. The mapping is
one-to-one where an entry resolves to one product, and one-to-many where an
entry names a provider with several distinct products under different terms —
Spamhaus is the clearest case, and entries 10, 11 and 12 name three of them.
Where that happens the catalog entry keeps its number and the registry carries
the additional records with `catalog_ref: "none"`, cross-referenced in their
`disposition_reason`. Nothing here is renumbered to make that tidy.

## 3. The catalog

| # | Entry as supplied | Broad family, as supplied — not a finding |
| --- | --- | --- |
| 01 | URLhaus | Malware URL feed |
| 02 | ThreatFox | IOC exchange |
| 03 | Feodo Tracker | Botnet C2 tracker |
| 04 | SSL Blacklist / SSLBL | Malicious TLS certificate / JA3 list |
| 05 | MalwareBazaar | Malware sample repository |
| 06 | PhishTank | Community phishing URL corpus |
| 07 | OpenPhish | Phishing URL feed |
| 08 | Phishing.Database — mitchellkrogza/Phishing.Database | Aggregated phishing domain/URL lists |
| 09 | Phishing Army | Aggregated phishing blocklist |
| 10 | Spamhaus | Provider — multiple distinct products |
| 11 | Spamhaus DROP | IP netblock list |
| 12 | Spamhaus DBL | Domain blocklist |
| 13 | SURBL | URI reputation list |
| 14 | URIBL | URI reputation list |
| 15 | MISP and its feed directory | Platform and feed directory |
| 16 | AlienVault OTX | Community threat-intelligence platform |
| 17 | Emerging Threats Open | IDS ruleset and IP lists |
| 18 | DShield | Internet Storm Center sensor data |
| 19 | Blocklist.de | Attacker IP list from fail2ban reports |
| 20 | FireHOL IP Lists | Aggregated IP blocklists |
| 21 | IPsum — stamparm/ipsum | Aggregated malicious IP list |
| 22 | HaGeZi DNS Blocklists | DNS blocklists |
| 23 | StevenBlack Hosts | Aggregated hosts file |
| 24 | CERT Polska Warning List | National phishing domain warning list |
| 25 | URLScan.io | URL scanning and observation service |
| 26 | Google Safe Browsing | URL reputation API |
| 27 | Google Web Risk | Commercial URL reputation API |
| 28 | VirusTotal | Multi-engine scanning and enrichment |
| 29 | AbuseIPDB | Community IP abuse reports |
| 30 | GreyNoise | Internet background-noise attribution |
| 31 | Pulsedive | Threat-intelligence enrichment platform |
| 32 | CINS Score | IP reputation score list |
| 33 | Project Honey Pot | Spam harvester and comment-spam observations |
| 34 | Stop Forum Spam | Forum-spam identity reports |
| 35 | CleanTalk Blacklist | Spam identity/IP reputation |
| 36 | BotScout | Bot registration identity reports |
| 37 | disposable-email-domains/disposable-email-domains | Disposable email domain list |
| 38 | FakeFilter — 7c/fakefilter | Disposable email domain detection data |
| 39 | MailChecker — FGRibreau/mailchecker | Disposable/temporary email detection library and list |
| 40 | UCI SMS Spam Collection | Historical SMS corpus |
| 41 | Apache SpamAssassin Public Corpus | Historical email corpus |
| 42 | Enron-Spam | Historical email corpus |
| 43 | UCI Spambase | Historical feature dataset |
| 44 | TREC Spam Track Data | Historical email corpora |
| 45 | Nazario Phishing Corpus | Historical phishing email corpus |
| 46 | Hiya | Phone-call reputation, commercial |
| 47 | Truecaller | Phone-number identification, commercial |
| 48 | Transaction Network Services / TNS | Call-traffic analytics, commercial |
| 49 | First Orion | Call-scoring, commercial |
| 50 | YouMail | Robocall data, commercial |
| 51 | Nomorobo | Robocall blocking service |
| 52 | RoboKiller | Robocall blocking service |
| 53 | IPQualityScore | Multi-indicator fraud scoring, commercial |
| 54 | Twilio Lookup | Phone-number metadata API, commercial |
| 55 | Chainabuse | Community crypto scam reports |
| 56 | BitcoinAbuse | Community crypto abuse reports |
| 57 | CryptoScamDB | Crypto scam address/domain dataset |
| 58 | EtherScamDB | Crypto scam dataset |
| 59 | Chainalysis | Blockchain analytics, commercial |
| 60 | TRM Labs | Blockchain analytics, commercial |
| 61 | Elliptic | Blockchain analytics, commercial |
| 62 | Scam Sniffer | Web3 phishing detection |
| 63 | Netcraft | Phishing takedown and feeds, commercial |
| 64 | Bolster | Brand-protection / phishing detection, commercial |
| 65 | CheckPhish | URL scanning service |
| 66 | Recorded Future | Threat-intelligence platform, commercial |
| 67 | Flashpoint | Threat-intelligence platform, commercial |
| 68 | Intel 471 | Threat-intelligence platform, commercial |
| 69 | Group-IB | Threat-intelligence platform, commercial |
| 70 | ZeroFox | Digital-risk protection, commercial |
| 71 | SOCRadar | Digital-risk protection, commercial |
| 72 | Cybersixgill | Threat-intelligence platform, commercial |
| 73 | KELA | Threat-intelligence platform, commercial |
| 74 | ICANN RDAP | Registration data access protocol |
| 75 | SecurityTrails | DNS/domain history, commercial |
| 76 | DomainTools | DNS/domain intelligence, commercial |
| 77 | WhoisXML API | Registration data, commercial |
| 78 | Certificate Transparency / crt.sh | CT log search |
| 79 | Anti-Phishing Working Group / APWG | Industry body and data exchange |
| 80 | CISA | US government advisory source |
| 81 | NCSC UK | UK government advisory source |
| 82 | Canadian Centre for Cyber Security | Canadian government advisory source |
| 83 | CERT-EU | EU institutions CERT |
| 84 | Australian Cyber Security Centre / ACSC | Australian government advisory source |
| 85 | Shadowserver Foundation | Non-profit sensor and victim-notification network |

**85 entries. None is omitted, and none has been replaced by a substitute.**
Entries that later prove historical, overlapping, unavailable, discontinued or
commercial stay on this list with their number. Removing them would destroy the
mapping the registry's `catalog_ref` depends on, and would quietly rewrite what
was asked for.

## 4. Intended indicator scope, as supplied

Domains, URLs, IPs, email addresses, disposable email domains, usernames, phone
numbers, social handles, crypto addresses, payment identifiers, message
corpora, certificate hashes, registration and DNS observations, and campaign
relationships.

**Two things this scope must not be read as saying.**

* **No provider supplies every indicator type.** The families in the table
  above are the requesting party's framing; what a given provider actually
  publishes is a per-record finding in the registry, in the registry's own
  vocabulary, and several entries publish exactly one type.
* **DNS filtering cannot enforce a decision about a phone number, a wallet
  address, a payment identifier or the text of a message.** The Phase 1
  deployment target is a DNS sinkhole. An indicator type that a DNS resolver
  cannot act on is a *research and product* scope item with its own delivery
  mechanism still undesigned — see `docs/EVALUATION_PROTOCOL.md` on the
  distinction between a DNS pilot and the multi-indicator product.

## 5. What this file does not do

* It does not qualify any entry. Qualification is `docs/source-registry.json`.
* It does not enable anything. Enabling requires a `verified-available`
  disposition and per-operation authorisation — `docs/SOURCE_REGISTRY.md` §2.1.
* It does not assert that any entry still exists under the name supplied. A
  rename, an acquisition or a discontinuation is a finding that needs evidence,
  and the catalog number stays mapped to the entry as supplied when one is
  found.
