# Security Policy

ScamWall handles a credential that grants full API access to a Pi-hole instance,
and it proposes changes to DNS blocking — a system whose failure takes a network
offline. Security issues here are taken seriously.

## Project status

ScamWall is in **Phase 1**: read-only and dry-run. It is not ready for
production use. It cannot modify Pi-hole, and enforcement is not compiled into
the binary.

Do not deploy ScamWall as a protective control. It does not yet provide one, and
it must never be described as complete scam protection.

## Supported versions

No released versions yet. Only the current development branch receives fixes.

| Version | Supported |
| --- | --- |
| `main` / `feat/phase-1-core` | Yes |
| Everything else | No |

## Reporting a vulnerability

**Please do not open a public issue for a security vulnerability.**

Use GitHub's private vulnerability reporting:

1. Go to the **Security** tab of `LordHorkos/scamwall`.
2. Choose **Report a vulnerability**.

This keeps the report private until a fix is available.

Helpful to include: affected component, ScamWall and Pi-hole versions, a
reproduction, and the impact you believe it has. A proof of concept is welcome
but never required — a clear description of the flaw is enough.

**Never include a real Pi-hole application password, session ID, CA private key,
or feed signing key in a report.** If you believe a credential has been exposed,
say so and rotate it immediately; do not paste it.

Expect an acknowledgement within a few days. This is a small project, so please
allow reasonable time before public disclosure. Credit is given for reported
issues unless you prefer otherwise.

## What we consider a vulnerability

High interest:

- Any path by which ScamWall mutates Pi-hole in a phase where it must not.
- Any way to bypass TLS certificate or hostname verification.
- Leakage of the application password, session ID, or CSRF token into logs,
  errors, process arguments, environment, crash output, or a committed file.
- Accepting a feed with an invalid, missing, or replayed signature.
- Feed content that escapes validation — wildcards, public suffixes, IP
  literals, or IDN confusables reaching a plan.
- Container escape, privilege escalation, or capability acquisition.
- Non-deterministic plan output, which would undermine operator review.

Also in scope, lower severity: resource exhaustion via oversized feeds or
responses, and denial of service against ScamWall itself.

## Not vulnerabilities

- Findings that require an already-compromised Pi-hole host. Pi-hole is the
  trust anchor; if it is compromised, ScamWall's guarantees are moot by design.
- Findings that require root on the container host.
- ScamWall failing closed. Refusing to run on a TLS error, an expired feed, or a
  bad signature is intended behaviour, not a bug.
- The fact that a stolen application password permits mutation *by the
  attacker*. This is a documented residual risk
  (`docs/THREAT_MODEL.md` §6.1), not a flaw in ScamWall — ScamWall's read-only
  design constrains ScamWall, not an attacker holding its credential.
- Missing hardening in an example or fixture that is clearly marked as such.

## Intended security properties

These are the properties ScamWall is **designed** to have. They are design
commitments, not certifications — each is only as good as the implementation and
the test that exercises it. Where a property is not yet substantiated by a
passing test against this codebase, it is marked as such rather than presented
as a guarantee.

If you find any of these to be false in the code, that is a vulnerability and we
want to hear about it.

1. ScamWall issues no Pi-hole API request that mutates state, other than
   `DELETE /api/auth` against its own session.
2. TLS verification is never disabled. `InsecureSkipVerify` does not appear in
   the tree, and no flag can bypass verification.
3. Trust is anchored to the configured private CA only; system roots are not
   consulted for the Pi-hole connection.
4. The application password and session ID never appear in logs, errors,
   process arguments, or the environment.
5. The session ID is transmitted only in the `X-FTL-SID` header, never in a URL.
6. Logout is attempted on every exit path, including error and cancellation.
7. Feeds are rejected unless signed by a configured trust key and unexpired.
8. Plans are deterministic: identical input yields byte-identical output.
9. The container runs non-root, read-only, with no capabilities, no published
   ports, and no Docker socket.
10. No secret or installation-specific certificate is ever committed.

### Verification status

Properties above are exercised by the test suite and by container inspection.
Two caveats apply to Phase 1 and are stated openly:

- The **authenticated** Pi-hole path (successful login, authenticated read,
  `DELETE /api/auth` returning `204`) is proven against a fake Pi-hole HTTPS
  server, **not** yet against the live instance, because the application
  password is not readable by a non-root process on the deployment host. See
  `docs/SECURITY_BOUNDARIES.md` §5.1.
- Container properties hold for the shipped compose definition. A deployment
  that overrides it — for example with a `docker-compose.override.yml` — is
  outside these commitments.

## Handling of credentials

- The application password is read only from `/run/secrets/pihole_app_password`.
- It is never accepted from a flag, an environment variable, or a config file.
- It is wrapped in a type that redacts itself on every formatting path.
- The session ID is held in memory only and is destroyed at logout.
- The CSRF token is discarded at parse time; header authentication does not need
  it.
