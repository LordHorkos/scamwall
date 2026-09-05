# Pi-hole v6 API Contract (as observed)

This document records the **live** API contract of the Pi-hole instance ScamWall
integrates with. It is derived from the OpenAPI specification served by that
instance and from unauthenticated probes against it, not from upstream
documentation on the internet.

Nothing in this document is installation-specific. It contains no hostnames
beyond the public service name `pi.hole`, no IP addresses, no certificates, no
session identifiers, and no credentials.

---

## 1. How this contract was captured

The specification was fetched over TLS with full certificate **and hostname**
verification against the Pi-hole private CA:

```
curl --cacert <pihole-ca.crt> --resolve pi.hole:443:<pihole-host-ip> \
     https://pi.hole/api/docs/specs/main.yaml
```

Two properties of that command matter and are preserved everywhere in ScamWall:

* `--cacert` pins trust to the Pi-hole private CA only.
* `--resolve` overrides **name resolution only**. The TLS peer is still
  validated against the name `pi.hole`, matching the leaf certificate's
  `subjectAltName`. This is not a verification bypass; `-k` /
  `InsecureSkipVerify` are never used, in tooling or in code.

The resolution override is required because in this environment the DNS name
`pi.hole` does not resolve to the host running Pi-hole. See
`docs/SECURITY_BOUNDARIES.md`.

Specification documents retrieved:

| Document | Result |
| --- | --- |
| `/api/docs/specs/main.yaml` | `200`, `text/plain`, 8511 bytes |
| `/api/docs/specs/auth.yaml` | `200`, 22143 bytes |
| `/api/docs/specs/info.yaml` | `200`, 50388 bytes |
| `/api/docs` | `301` &rarr; `/api/docs/` (same origin) |

Specification identity:

```yaml
openapi: 3.0.2
info:
  title: Pi-hole API
  version: "6.0"
```

---

## 2. Transport requirements

| Property | Value |
| --- | --- |
| Scheme | `https` only |
| Default port | `443` |
| Base path | `/api` |
| Response media type | `application/json; charset=utf-8` |
| Certificate chain | Pi-hole private CA &rarr; leaf `CN=pi.hole`, SAN `DNS:pi.hole` |

The specification also advertises an `http://{url}:{port}/{path}` server on port
`80`. **ScamWall refuses plaintext HTTP unconditionally.** On this host port 80
is served by Apache and returns `404` for `/api/auth`, so no plaintext API
surface exists to fall back to — but the refusal is enforced in code regardless
of what the remote offers.

Every successful JSON response carries a `took` field (seconds, floating point)
describing server-side processing time. ScamWall tolerates but ignores it.

---

## 3. Authentication

### 3.1 Declared security schemes

`main.yaml` declares five schemes:

| Scheme | Location | Name | ScamWall |
| --- | --- | --- | --- |
| `x_header_sid` | header | `X-FTL-SID` | **Used** |
| `header_sid` | header | `sid` | Not used |
| `cookie_sid` | cookie | `sid` | Not used |
| `query_sid` | query | `sid` | **Refused** — would place the session ID in a URL |
| `query_password` | query | `password` | **Refused** — would place the password in a URL |

ScamWall transmits the session identifier **only** in the `X-FTL-SID` request
header. URLs are never used to carry authentication material, because URLs are
routinely captured by proxy logs, access logs, browser history, and error
reports.

### 3.2 `POST /api/auth` — establish a session

Request body (`application/json`):

```json
{ "password": "<application password>" }
```

Per the specification: *"The password isn't stored in the session nor used to
create the session token. Instead, the session token is produced using a
cryptographically secure random number generator."*

Success response `200`:

```json
{
  "session": {
    "valid":    true,
    "totp":     false,
    "sid":      "<opaque session id>",
    "csrf":     "<opaque csrf token>",
    "validity": 1800,
    "message":  null
  },
  "took": 0.0001
}
```

Schema (`auth.yaml#/components/schemas/session`), required keys `valid`, `sid`,
`validity`, `message`, `totp`:

| Field | Type | Notes |
| --- | --- | --- |
| `valid` | boolean | Client is authenticated |
| `totp` | boolean | 2FA enabled on this Pi-hole |
| `sid` | string, nullable | Session ID |
| `csrf` | string, nullable | CSRF token; required only for cookie auth |
| `validity` | integer | Remaining lifetime in seconds |
| `message` | string, nullable | Human-readable status |

Session lifetime defaults to **30 minutes** and is extended by any authenticated
action. A session is invalidated by logout, by session deletion, by a password
change, or by creation of a new application password.

Because ScamWall authenticates with the `X-FTL-SID` header rather than a cookie,
**the CSRF token is not needed and is never retained**. It is discarded at parse
time and never logged.

Documented failure responses:

| Status | Meaning | Observed body shape |
| --- | --- | --- |
| `400` | Bad Request | `no_payload`, `no_password`, `password_inval`, `totp_missing` |
| `401` | Unauthorized | `totp_invalid`, `totp_reused` |
| `429` | Too Many Requests | `rate_limit`, `no_seats`, `totp_rate_limit` |

### 3.3 `DELETE /api/auth` — destroy the session

| Status | Meaning |
| --- | --- |
| `204` | No Content — session deleted |
| `404` | No session active |
| `401` | Unauthorized |

`204` matches the behaviour previously observed on this installation. ScamWall
treats `204` and `404` as equivalent success outcomes for logout, since both end
with no live session.

### 3.4 `GET /api/auth` — probe session state

Requires no credentials. Returns `200` with a valid session when the server
requires no authentication, otherwise `401` with `valid: false`. ScamWall uses
this endpoint in `doctor` to determine whether authentication is required
**without transmitting a password**.

---

## 4. Read-only endpoints used in Phase 1

Phase 1 reads **only** version and status information. It touches no endpoint
that returns query logs, client identities, network device inventories, DHCP
leases, or configuration.

### 4.1 `GET /api/info/version`

Documented as *"Request versions of the individual Pi-hole components."*
Response shape (`info.yaml#/components/schemas/version`):

```json
{
  "version": {
    "core": { "local": { "branch": "...", "version": "...", "hash": "..." },
              "remote": { "version": "...", "hash": "..." } },
    "web":  { "local": { "branch": "...", "version": "...", "hash": "..." },
              "remote": { "version": "...", "hash": "..." } },
    "ftl":  { "local": { "branch": "...", "version": "...", "hash": "...",
                         "date": "..." },
              "remote": { "version": "...", "hash": "..." } }
  },
  "took": 0.0001
}
```

Every leaf string is `nullable`. ScamWall's decoder treats all of them as
optional and never panics on a null.

This endpoint is **non-sensitive**: it exposes software version numbers only.

---

## 5. Endpoints deliberately NOT used in Phase 1

The specification exposes a large mutating surface. Phase 1 issues **no**
request to any of the following, and the client contains no code path that can
construct one:

| Category | Endpoints |
| --- | --- |
| Domain management | `POST/PUT/DELETE /api/domains/...`, `/api/domains:batchDelete` |
| Group management | `/api/groups`, `/api/groups:batchDelete` |
| Client management | `/api/clients`, `/api/clients:batchDelete` |
| List management | `/api/lists`, `/api/lists:batchDelete` |
| DNS control | `/api/dns/blocking` |
| Actions | `/api/action/gravity`, `/api/action/restartdns`, `/api/action/flush/*` |
| Configuration | `/api/config`, `/api/config/{element}`, `/api/config/{element}/{value}` |
| Teleporter | `/api/teleporter` (backup/restore) |
| DHCP | `/api/dhcp/leases` |

Additionally, these **read** endpoints are avoided in Phase 1 because they return
personally identifying or otherwise sensitive data:

`/api/queries`, `/api/history*`, `/api/stats/top_domains`,
`/api/stats/top_clients`, `/api/network/devices`, `/api/dhcp/leases`,
`/api/logs/*`, `/api/info/messages`, `/api/padd`.

---

## 6. Live behaviour observed on this installation

All probes below were issued **without credentials**. No mutation was attempted.

| Probe | Status | Body |
| --- | --- | --- |
| `GET /api/auth` | `401` | `{"session":{"valid":false,"totp":false,"sid":null,"validity":-1,"message":"no SID provided"},"took":...}` |
| `GET /api/info/version` | `401` | `{"error":{"key":"unauthorized","message":"Unauthorized","hint":null},"took":...}` |
| `POST /api/auth` body `{}` | `400` | `{"error":{"key":"bad_request","message":"No password found in JSON payload","hint":null},"took":...}` |
| `GET /api/docs` | `301` | `Location: /api/docs/` (same origin) |
| `GET http://<host>:80/api/auth` | `404` | Apache; no API surface |

The error envelope is consistent:

```json
{ "error": { "key": "...", "message": "...", "hint": null }, "took": 0.0 }
```

`hint` is nullable. ScamWall surfaces `key` and `message` in redacted operator
errors and never echoes a request body.

### Divergence assessment

**No material divergence.** Every endpoint reachable without credentials
returned exactly the status code, media type, and JSON envelope described by the
specification served by that same instance. The `session` object returned by
`GET /api/auth` contains precisely the five required fields declared in
`auth.yaml`.

The authenticated paths (`POST /api/auth` success, `GET /api/info/version`
success, `DELETE /api/auth` &rarr; `204`) have **not** yet been re-verified live by
ScamWall, because the application password is not readable by a non-root
process on this host. They are exercised in full against a fake Pi-hole HTTPS
server in the test suite. See "Open verification items" in
`docs/SECURITY_BOUNDARIES.md`.

---

## 7. Client obligations derived from this contract

These are requirements on ScamWall, enforced in `internal/adapters/pihole`:

1. HTTPS only; plaintext refused before a connection is attempted.
2. Trust anchored to the configured private CA. System roots are not consulted.
3. Hostname verified as `pi.hole`, independent of the address dialled.
4. Session ID carried only in `X-FTL-SID`; never in a URL, never in a log.
5. Password read from a file, held as narrowly as possible, never logged.
6. CSRF token discarded immediately; unused under header authentication.
7. `DELETE /api/auth` attempted on **every** exit path, including error and
   cancellation, under its own bounded timeout.
8. Response bodies bounded by a hard byte limit before decoding.
9. `Content-Type` verified as JSON before decoding.
10. Cross-origin redirects refused.
11. Retries with jitter permitted only for idempotent, side-effect-free reads.
12. All errors redacted: no bodies, no headers, no credentials.
