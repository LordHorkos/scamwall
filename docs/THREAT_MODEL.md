# ScamWall Threat Model (Phase 1)

Scope: the Phase 1 read-only, dry-run vertical slice. Enforcement, third-party
feed ingestion, and persistent state are out of scope and are modelled in
Phase 2.

---

## 1. Assets

| Asset | Why it matters | Where it lives |
| --- | --- | --- |
| Pi-hole application password | Grants full API access, including mutation | `/etc/scamwall/secrets/...` on host; `/run/secrets/...` read-only in container; process memory |
| Pi-hole session ID (SID) | Bearer credential for the session lifetime | Process memory only |
| Pi-hole private CA | Trust anchor for the API connection | `/etc/scamwall/certs/pihole-ca.crt`, read-only |
| Feed trust public key | Determines which feeds are accepted | Configuration; committed |
| DNS availability | Losing it breaks the whole network | Pi-hole, which ScamWall must never disturb |
| Pi-hole blocklist integrity | Wrongly blocking a bank or hospital domain is a real harm | Pi-hole database, untouched in Phase 1 |
| Operator trust in the plan | Enforcement decisions rest on reviewed plans | Plan output |

The last asset is easy to overlook. If a plan is not reproducible, review is
theatre — so plan determinism is treated as a security control.

---

## 2. Trust boundaries

```
   Internet ─────────────╳──────────  (no ScamWall egress in Phase 1)

   ┌──────────── host ────────────────────────────────────────────┐
   │                                                              │
   │  root ──── B1 ────▶ /etc/scamwall/{certs,secrets}            │
   │                            │ read-only bind                  │
   │                            ▼                                 │
   │  ┌─────── container (uid≠0, ro rootfs, cap_drop ALL) ──────┐  │
   │  │  ScamWall process                                       │  │
   │  └─────────────────────────────────────────────────────────┘  │
   │                            │ B2: TLS, private CA, SAN pi.hole │
   │                            ▼                                  │
   │  Pi-hole FTL :443 ◀── B3: authenticated API surface           │
   └───────────────────────────────────────────────────────────────┘
                                ▲
                                │ B4: LAN — other devices, incl. the
                                     appliance that answers DNS "pi.hole"
```

* **B1 — host filesystem &rarr; container.** Crossed only by three read-only
  mounts: CA, secret, config. Anything else is a boundary violation.
* **B2 — container &rarr; Pi-hole over TLS.** The only network crossing. Trust is
  the private CA alone; system roots are not consulted.
* **B3 — API authorisation.** Pi-hole, not ScamWall, is the authority. ScamWall's
  self-restriction to reads is defence in depth, not the control.
* **B4 — the LAN.** Untrusted. Notably, DNS for `pi.hole` here answers with a
  different device (see `SECURITY_BOUNDARIES.md` §4).

---

## 3. Adversaries

| Adversary | Capability | Motivation |
| --- | --- | --- |
| A1 — Malicious/compromised feed publisher | Controls feed contents; may hold a signing key | Block a competitor, cause a DoS, poison the plan |
| A2 — Network attacker on the LAN | Spoof DNS/ARP, impersonate `pi.hole`, MITM | Harvest the application password |
| A3 — Compromised ScamWall container | Arbitrary code execution as the container user | Escalate to host or to Pi-hole mutation |
| A4 — Malicious dependency | Code execution at build or run time | Supply-chain compromise |
| A5 — Local unprivileged host user | Read world-readable files, inspect processes | Harvest credentials |
| A6 — Careless operator (non-malicious) | Misconfiguration, copy-paste of unsafe commands | — |

A6 is included deliberately. Most real incidents in a homelab are
self-inflicted, and a design that only resists malice is fragile.

---

## 4. Threats and mitigations

### 4.1 A2 — Impersonating Pi-hole to steal the password

**This is the highest-severity network threat**, and this environment is already
in the precondition state: the name `pi.hole` resolves to a device that is not
Pi-hole.

| Attack | Mitigation |
| --- | --- |
| DNS spoofing / rogue responder for `pi.hole` | `extra_hosts` pins the name to a fixed address; DNS is not consulted |
| Presenting any publicly-trusted certificate | Trust pool contains **only** the Pi-hole private CA; system roots never loaded |
| Presenting a cert for another name | `ServerName` fixed to `pi.hole`; SAN must match |
| Downgrade to plaintext | `http` refused before dialling; TLS 1.2 floor |
| Redirect to an attacker origin | Cross-origin redirects refused |
| Operator "fixes" a TLS error with `-k` | Documented as prohibited; no bypass flag exists in the binary; asserted by test |

The last row is the one that actually bites in practice. A TLS error is a
finding, not an obstacle — the design deliberately offers no escape hatch,
because an escape hatch that exists will eventually be used.

### 4.2 A1 — Malicious or compromised feed

| Attack | Mitigation |
| --- | --- |
| Unsigned or altered feed | Ed25519 signature verified over canonical bytes before parsing |
| Signature over re-serialised data (parser differential) | Signature covers the exact on-disk payload bytes |
| Replay of an old feed | Manifest `issued_at`/`expires_at`; expired manifests rejected |
| Stale indicators inside a fresh manifest | Per-record expiry enforced independently |
| Feed bloat &rarr; memory exhaustion | Hard caps on file size and record count, enforced before decode |
| Blocking a public suffix (`com`, `co.uk`) | Public-suffix entries rejected |
| Wildcards to over-block | Wildcard entries rejected; exact domains only |
| IDN homograph confusion | IDNA normalisation to a single canonical lowercase form |
| Duplicate/conflicting records | Rejected, not silently resolved |
| Low-confidence noise reaching a plan | Only `high` confidence + `block` action enter a plan |
| Blocking critical infrastructure | Plans are reviewable, deterministic, and never auto-applied in Phase 1 |

A signed feed is still an *untrusted* feed. Signing proves origin, not
correctness — so bounds and sanity rules apply to signed feeds too.

### 4.3 A3 — Compromised container

| Goal | Mitigation |
| --- | --- |
| Escape to host | No privileged mode, no host networking, no Docker socket, all capabilities dropped |
| Gain privileges | `no-new-privileges:true`; non-root UID; no setuid binaries in the image |
| Persist | Read-only root filesystem; `/tmp` is `tmpfs` with `noexec,nosuid,nodev` |
| Read host files | Only three read-only mounts; `/etc/pihole` never mounted |
| Pivot to other hosts | No published ports; egress limited to the Pi-hole API |
| **Mutate Pi-hole with the stolen password** | **Not mitigated — see §6** |

### 4.4 A4 — Supply chain

| Attack | Mitigation |
| --- | --- |
| Malicious module | Minimal dependency surface; `go.sum` pinning; `govulncheck` |
| Base-image substitution | Base images pinned by digest, not tag |
| Build-time secret capture | Secrets never enter the build context; `.dockerignore` excludes them |
| Secrets baked into layers | Multi-stage build; final stage carries only the binary and CA trust files |

### 4.5 A5 / A6 — Local users and operator error

| Attack | Mitigation |
| --- | --- |
| Reading the secret file | `0640` with a dedicated group; never world-readable |
| Secret in `ps` output | Never passed as an argument or environment variable |
| Secret in logs | `Secret` type redacts on every formatting path; logger denylists keys |
| Secret committed to a **public** repo | Deny-by-default `.gitignore`; pre-commit secret scan |
| Accidental enforcement | Dry-run is the immutable default; enforcement not compiled |
| Operating on the wrong directory | Binary refuses to run outside its expected root |

---

## 5. Explicitly out of scope

Physical access; a compromised Pi-hole host (it is the trust anchor —
if it is compromised, ScamWall's guarantees are moot); a malicious Go toolchain
or kernel; and denial of service against Pi-hole itself.

---

## 6. Residual risks

Stated plainly, because unstated residual risk is the dangerous kind.

1. **Credential theft grants mutation.** ScamWall cannot mutate Pi-hole, but an
   attacker who steals the application password from ScamWall's memory or mount
   can call mutating endpoints directly. ScamWall's read-only design constrains
   *ScamWall*, not an attacker holding its credential. Mitigate by scoping the
   application password as narrowly as Pi-hole permits and rotating it on any
   suspicion of compromise. **This is the top residual risk of Phase 1.**

2. **The CA is a self-signed root with a short validity window**
   (2026-09-05 &rarr; 2026-10-22). Expiry causes a hard, correct failure. The
   operational hazard is that renewal pressure invites someone to disable
   verification. Rotation must be a documented procedure before Phase 2.

3. **`pi.hole` resolves to a foreign device on this network.** ScamWall is
   insulated by address pinning, but every *other* consumer of that name on this
   network is not. This warrants independent investigation.

4. **No feed revocation.** A feed signing key cannot be revoked in Phase 1;
   trust is a static configured key. Compromise requires manual reconfiguration.

5. **Session seats are finite.** Repeated crashes between authentication and
   logout could exhaust Pi-hole session seats (`429 no_seats`). Mitigated by
   always-attempted bounded logout, but not eliminated.

6. **Unverified live authentication.** The authenticated path has been proven
   only against a fake server, because the secret is not yet readable. Until it
   runs live, a divergence in the authenticated surface remains possible —
   assessed as low risk, since the unauthenticated surface matched the
   specification exactly.
