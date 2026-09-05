# Contributing to ScamWall

Thanks for your interest. ScamWall touches DNS — the system whose failure takes
a whole network offline — and it holds a credential that grants full API access
to a Pi-hole instance. Contributions are held to a correspondingly high bar.

Please read `docs/SECURITY_BOUNDARIES.md` before proposing changes. Several
things that look like ordinary improvements are prohibited by design.

## License

ScamWall is licensed under the **GNU Affero General Public License v3.0 only
(AGPL-3.0-only)**. See `LICENSE`.

By contributing, you agree that your contribution is licensed under
AGPL-3.0-only. Every original Go source file carries:

```go
// SPDX-License-Identifier: AGPL-3.0-only
```

AGPL §13 matters here: anyone who runs a modified ScamWall as a network service
must offer the corresponding source to its users. Keep that in mind when
vendoring or embedding ScamWall.

Do not add a dependency whose license is incompatible with AGPL-3.0-only, and do
not copy code from an incompatibly licensed project. If you are unsure about a
dependency's license, ask before writing code against it.

## Project phases

ScamWall is built in phases, and the phase boundary is a hard constraint, not a
roadmap suggestion.

**Phase 1 (current): read-only and dry-run.** ScamWall must not modify Pi-hole
in any way. Enforcement is not compiled into the binary.

A pull request will be rejected, regardless of quality, if it:

- adds any Pi-hole API call that mutates state (anything other than
  `POST /api/auth`, `DELETE /api/auth`, and documented read endpoints);
- enables enforcement, or makes it reachable without the `enforce` build tag;
- changes the dry-run default;
- weakens TLS verification, adds an "insecure" or "skip-verify" option, or
  introduces a flag that could bypass certificate or hostname checking;
- reads a credential from anywhere other than
  `/run/secrets/pihole_app_password`;
- logs a password, session ID, CSRF token, authorization header, or request
  body;
- adds a network fetch of a third-party feed;
- mounts `/etc/pihole` or `/var/run/docker.sock`, publishes a port, adds a
  capability, or requires privileged mode;
- commits a secret, an installation-specific certificate, a generated signing
  key, runtime state, logs, or coverage output.

If you believe one of these is genuinely necessary, open an issue and make the
case first. Do not open a pull request that quietly relaxes a boundary.

## Getting set up

Requirements: Go **1.26.8**, Git, and Docker (only for container work).

The toolchain version is pinned in `go.mod` (`toolchain go1.26.8`) and matched by
the container base image. Keep the three in step. This is a security control,
not a style preference: Go 1.24 is end-of-life upstream, and `govulncheck`
reported 24 standard-library vulnerabilities against it, several reachable from
ScamWall's own code. Before changing it, confirm the target release is still in
the supported set at <https://go.dev/dl/?mode=json>.

```bash
git clone https://github.com/LordHorkos/scamwall.git
cd scamwall
go build ./...
go test ./...
```

ScamWall needs no Pi-hole to develop against. The test suite runs a fake Pi-hole
HTTPS server with its own throwaway CA generated at test time.

**Never point a test at a production Pi-hole.** No test may mutate a real
instance.

## Quality gates

All of these must pass before a pull request is merged:

```bash
gofmt -l .                # must print nothing
go vet ./...
go test -race ./...
staticcheck ./...
govulncheck ./...
```

Plus, for container changes — these run without Docker daemon access:

```bash
docker compose --env-file deploy/compose/.env \
  -f deploy/compose/compose.yaml config     # client-side; no daemon needed
./scripts/container-security-check.sh        # repository content only
./scripts/tests/runtime-verify-test.sh       # verifier regression tests
```

And, with Docker daemon access, operator-executed:

```bash
docker build -f container/Dockerfile -t scamwall:local .
./scripts/container-runtime-verify.sh        # image + container; needs no git
```

The runtime verifier is a separate program from the repository checker because
it runs on the other side of a privilege boundary. See
`docs/SECURITY_BOUNDARIES.md` §5.5.

And before every commit:

```bash
./scripts/secret-scan.sh
```

`.gitignore` is a safety net, not a control. The repository is **public** —
check what you are actually staging with `git diff --cached` before committing.

## Coding standards

- Standard `gofmt`. No custom formatting.
- Keep the dependency surface minimal. ScamWall deliberately depends on the
  standard library plus `golang.org/x/net` (IDNA and public suffix data).
  Adding a dependency requires justification in the pull request.
- Errors wrap with `%w` and carry context, but **never** carry a credential, a
  response body, or a header value. Redact at the point of construction rather
  than trusting the caller.
- Every network call takes a `context.Context` as its first parameter and
  honours cancellation.
- Reads are bounded. Anything that reads from a network or a file needs an
  explicit size limit.
- Public identifiers are documented. Non-obvious security decisions get a
  comment explaining *why*, not *what* — the reason is the part that gets lost.

## Tests

New code needs tests. Security-relevant code needs tests for the failure paths,
which is where the interesting bugs live.

For anything touching the Pi-hole client, cover at minimum: `401`, `403`, `429`,
`500`, timeout, truncated JSON, oversized response, wrong content type,
cross-origin redirect, TLS failure, hostname mismatch, and context cancellation.

For anything touching feeds, cover: bad signature, wrong key, expired manifest,
expired record, oversized file, too many records, duplicate records, and each
rejected domain class.

Tests must also prove the absence of leaks — that captured log output contains
no password, session ID, CSRF token, or authorization header.

## Commits and branches

- Work on a feature branch. `main` is protected.
- Small, focused commits. Each commit should build and pass tests.
- Use [Conventional Commits](https://www.conventionalcommits.org/):
  `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`, `security:`.
- Write the *why* in the body when the *what* is not self-evident.

## Reporting security issues

Do not open a public issue. See `SECURITY.md` for private reporting.
