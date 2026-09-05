# ScamWall Architecture (Phase 1)

ScamWall is a local-first fraud-domain protection engine. Phase 1 delivers a
**read-only, dry-run vertical slice**: it can authenticate to a native Pi-hole
v6 instance, read non-sensitive version and status information, validate a
signed threat feed, and compute a proposed blocking plan — but it has no code
path capable of changing Pi-hole in any way.

---

## 1. Design position

ScamWall is a **separate, unprivileged consumer** of the Pi-hole HTTPS API. It
is not a Pi-hole plugin, patch, fork, or sidecar with special access.

```
┌───────────────────────────────── host ─────────────────────────────────┐
│                                                                        │
│   Pi-hole v6 (native, untouched)          ScamWall (Docker, hardened)  │
│   ┌───────────────────────────┐           ┌─────────────────────────┐  │
│   │ FTL + embedded webserver  │           │ non-root, read-only fs  │  │
│   │ :53 DNS   :443 HTTPS API  │◀──TLS─────│ cap_drop ALL            │  │
│   │ private CA, CN=pi.hole    │  GET only │ no ports, no socket     │  │
│   └───────────────────────────┘           └─────────────────────────┘  │
│            ▲                                        │                  │
│            │ read-only, authenticated               │ read-only mounts │
│            │ POST /api/auth → X-FTL-SID             ▼                  │
│            │ GET  /api/info/version         CA cert, secret, config    │
│            └ DELETE /api/auth (always)                                 │
└────────────────────────────────────────────────────────────────────────┘
```

The blast radius is deliberately asymmetric: ScamWall can be fully compromised
without gaining the ability to modify Pi-hole, because in Phase 1 it holds no
credential capable of mutation *and no code capable of issuing one*.

---

## 2. Package layout

| Package | Responsibility | Depends on |
| --- | --- | --- |
| `cmd/scamwall` | CLI surface, flag parsing, exit codes, wiring | all internal |
| `internal/config` | Load + validate configuration, redacted rendering | domain |
| `internal/domain` | Canonical domain type, IDNA normalisation, validation | — |
| `internal/feed` | Manifest schema, Ed25519 verification, bounds, expiry | domain |
| `internal/policy` | Deterministic plan computation, confidence gating | domain, feed |
| `internal/audit` | Structured logging with mandatory redaction | — |
| `internal/adapters/pihole` | HTTPS client, session lifecycle, read-only reads | audit, config |

Dependencies point inward. `internal/domain` has no dependencies on any other
ScamWall package, so its guarantees hold no matter who calls it.

Critically, **`internal/policy` does not import `internal/adapters/pihole`.**
A plan is a pure function of the feed and configuration. There is no wiring
through which a computed plan can reach the Pi-hole client, which is the
structural reason Phase 1 cannot submit one.

---

## 3. Command surface

| Command | Network | Purpose |
| --- | --- | --- |
| `scamwall version` | none | Build identity; prints enforcement compile state |
| `scamwall doctor` | TLS handshake + `GET /api/auth` | Preflight: config, CA, secret, DNS pinning, TLS, reachability |
| `scamwall status` | full session | Authenticate, read `/api/info/version`, log out |
| `scamwall validate-feed` | none | Parse, verify signature, enforce bounds, report |
| `scamwall plan` | none | Compute the proposed blocking plan; print it |
| `scamwall sync --dry-run` | full session | Plan + live read + explicit statement that nothing was submitted |

`doctor` deliberately uses the credential-free `GET /api/auth` probe so that
connectivity can be diagnosed without transmitting a password.

---

## 4. Enforcement is absent, not merely disabled

Three independent mechanisms, any one of which is sufficient:

1. **Compile-time.** Enforcement lives behind the `enforce` build tag. The
   default build compiles `enforce_disabled.go`, which sets
   `EnforcementCompiledIn = false` and provides a submitter that returns an
   error. No enforcing implementation exists in the tree at all in Phase 1.
2. **Structural.** `internal/policy` cannot reach `internal/adapters/pihole`.
   The Pi-hole client exposes no exported method that performs a write.
3. **Runtime.** `--dry-run` defaults to `true`. Passing `--dry-run=false` is
   rejected with a diagnostic, not honoured.

Defence in depth matters here because a single forgotten flag default is a
plausible mistake; three failures at once is not.

---

## 5. Data flow

### 5.1 Feed validation (`validate-feed`, offline)

```
feed.json ──▶ size gate ──▶ JSON decode ──▶ manifest version check
    │                                            │
    │                                            ▼
    │                                   Ed25519 verify over
    │                                   canonical payload bytes
    │                                            │
    ▼                                            ▼
record-count gate                        manifest expiry check
    │                                            │
    └──────────────────┬─────────────────────────┘
                       ▼
        per-record: IDNA normalise → canonical form →
        reject IP literal / localhost / .local / single label /
        wildcard / public suffix / malformed IDN / over-length →
        dedupe + conflict detection → per-record expiry
                       ▼
              validated indicator set
```

Signature verification happens **before** any record is interpreted, and the
signature covers the exact canonical bytes that are later parsed. Verifying a
re-serialised structure would leave room for a parser-differential attack.

### 5.2 Plan computation (`plan`, offline)

Validated indicators are filtered to `action == "block"` **and**
`confidence == "high"`, then sorted into a canonical order. The plan carries a
content digest so two runs over the same feed are provably identical.

Determinism is a security property, not a convenience: an operator must be able
to review a plan and know the reviewed plan is what would be applied.

### 5.3 Live read (`status`, `sync --dry-run`)

```
load CA ──▶ build TLS config (private CA only, ServerName=pi.hole)
   │
   ▼
read secret from /run/secrets/pihole_app_password
   │
   ▼
POST /api/auth ──▶ SID held in memory only
   │                    │
   │                    ▼
   │            GET /api/info/version  (bounded, typed, redacted)
   │                    │
   └────────────────────┴──▶ DELETE /api/auth   ← always, incl. error/cancel
```

The logout is registered immediately after a successful authentication and runs
from a deferred path with its own bounded context, so a cancelled or failed read
still tears the session down rather than leaving it to expire.

---

## 6. The Pi-hole client

Hardening properties, all enforced in `internal/adapters/pihole`:

| Property | Mechanism |
| --- | --- |
| HTTPS only | Scheme checked before dial; `http` rejected |
| Private CA only | `tls.Config.RootCAs` set to a pool containing only the configured CA; system roots never loaded |
| Hostname verified | `ServerName` fixed to the configured API host, independent of dialled address |
| No verification bypass | `InsecureSkipVerify` never set; asserted by a unit test that greps the package |
| Address pinning | Custom `DialContext` maps the API host to a configured address — resolution override only, never a verification change |
| Bounded bodies | `io.LimitReader` with a hard cap; overflow is an error, not a truncation |
| Content-type gate | `application/json` required before decode |
| Strict timeouts | Per-request deadline plus overall client timeout |
| Context cancellation | Every request carries a context; cancellation is honoured |
| Bounded retries | Only for idempotent reads; capped attempts, exponential backoff with jitter; never for `POST /api/auth` |
| Redirect policy | Cross-origin redirects refused |
| Redacted errors | Errors carry status and endpoint, never bodies, headers, or credentials |

Retrying authentication would be actively harmful: the API rate-limits login
and returns `429 no_seats` when the session table is full, so a retry storm
could lock out legitimate operators.

---

## 7. Secret handling

The application password is read **only** from
`/run/secrets/pihole_app_password`, mounted read-only into the container.

* It is never placed in configuration files, environment variables, or flags.
* It is held in a `Secret` type whose `String()`, `GoString()`, `Format()`, and
  `MarshalJSON()` all return `"[REDACTED]"`, so it cannot be leaked by an
  accidental `%v` or a JSON dump.
* Its plaintext is reachable only through an explicit `Reveal()` call, which
  appears exactly once in the tree — in the auth request builder.
* It is zeroed after the authentication request is constructed.

The session ID receives the same `Secret` treatment.

---

## 8. Audit logging

`internal/audit` emits structured JSON to stdout. Redaction is applied by the
logger itself rather than trusted to call sites, because a call-site-only
discipline fails silently the first time someone forgets.

Denylisted keys (`password`, `sid`, `csrf`, `authorization`, `x-ftl-sid`,
`token`, `secret`, …) are replaced with `[REDACTED]` regardless of value, and
values carrying the `Secret` type are redacted structurally. Request and
response bodies are never logged at any level.

---

## 9. Container model

Single static binary in a minimal final stage. No shell, no package manager, no
interpreter. Runs as a fixed non-root UID/GID with a read-only root filesystem,
all capabilities dropped, `no-new-privileges`, `tmpfs` on `/tmp` with
`noexec,nosuid,nodev`, bounded memory/PID/CPU/log size, no published ports, no
host networking, and no Docker socket.

`pi.hole` is pinned via `extra_hosts` because DNS in this environment resolves
that name to a different device. See `docs/SECURITY_BOUNDARIES.md`.

---

## 10. Phase 1 non-goals

Explicitly out of scope: any Pi-hole mutation, third-party feed downloads,
enforcement, rollback, scheduling, persistent state, metrics export, telemetry,
and multi-instance orchestration.
