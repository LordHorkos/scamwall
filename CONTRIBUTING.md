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

### Gate tooling

`scripts/check.sh` needs these in addition to Go. Any that is missing is
reported `BLOCKED` and fails the suite, so install them rather than working
around them.

| Tool | Version used | Install |
| --- | --- | --- |
| staticcheck | 2026.2.1 | `go install honnef.co/go/tools/cmd/staticcheck@2026.2.1` |
| govulncheck | v1.7.0 | `go install golang.org/x/vuln/cmd/govulncheck@v1.7.0` |
| ShellCheck | 0.11.0 | `apt install shellcheck`, or the static release binary |
| gitleaks | 8.30.0 | the release binary from `gitleaks/gitleaks` |
| jq | 1.7 | `apt install jq` |

`go install` puts binaries in `$(go env GOPATH)/bin`, which a non-interactive
shell may not have on `PATH`. `check.sh` adds it, so tools installed that way
are found even when your shell does not see them.

The pinned versions match `.github/workflows/gates.yml`. Bumping one is a
deliberate change that invalidates prior evidence — see
`docs/REQUIREMENTS_MATRIX.md` §5.

## Quality gates

One command runs everything, and it is the definition of "the gates":

```bash
./scripts/check.sh
```

It exits 0 only when every **required** gate actually ran and passed. A gate
that could not run — a missing tool, an unreachable Docker daemon — is reported
`BLOCKED` and fails the suite. It is never a silent skip: a green summary that
omits half the gates is worse than a red one, because it invites you to believe
the work is verified when it is not.

The individual gates, should you want to run one on its own:

```bash
gofmt -l .                                    # must print nothing
go vet ./...
go test -race ./...
staticcheck ./...
shellcheck --severity=style $(git ls-files '*.sh')
./scripts/govulncheck-gate.sh                 # decides by CONTENT, see below
```

Repository hygiene — two secret scanners, deliberately:

```bash
./scripts/secret-scan.sh --tree               # ScamWall-specific rules
./scripts/independent-secret-scan.sh          # gitleaks over history + tree
./scripts/tests/secret-scan-test.sh           # controls for the above
./scripts/tests/pipefail-sigpipe-test.sh      # see "A shell rule" below
./scripts/container-security-check.sh         # repository content only
./scripts/tests/runtime-verify-test.sh        # verifier regression tests
```

Neither scanner is a superset of the other. `secret-scan.sh` knows ScamWall —
which paths must never be tracked, that the Pi-hole password lives at a fixed
location, that a certificate body means the private CA leaked. gitleaks knows
the world's credential formats. Both are required.

`govulncheck-gate.sh` exists because `govulncheck -format json` **exits 0 even
when it has findings**. A gate that trusts the exit status in that mode reports
a vulnerable dependency set as clean. The gate parses the result instead, and
treats output it cannot parse as UNPROVEN rather than as a pass.

With Docker daemon access, operator-executed:

```bash
docker build -f container/Dockerfile -t scamwall:local .
SCAMWALL_EXPECTED_IMAGE_ID="$(docker image inspect -f '{{.Id}}' scamwall:local)" \
  ./scripts/container-runtime-verify.sh       # image + container; needs no git
```

The runtime verifier is a separate program from the repository checker because
it runs on the other side of a privilege boundary. See
`docs/SECURITY_BOUNDARIES.md` §5.5.

### A shell rule you must follow

In any script that sets `pipefail`, **never let a short-circuiting consumer
decide a condition**:

```bash
if producer | grep -q PATTERN; then ...   # WRONG
```

`grep -q` exits at the first match; the producer takes SIGPIPE and dies with
141; `pipefail` makes that the pipeline's status; the `if` reads false for input
that *did* match. This is not theoretical — it produced a 100% false-clean in
the secret scanner for files larger than the pipe buffer, and a silent false
PASS in a regression test. Use a herestring, a direct file argument, or a
captured variable:

```bash
if grep -q PATTERN <<<"$producer_output"; then ...   # right
if grep -q PATTERN somefile; then ...                # right
```

`scripts/tests/pipefail-sigpipe-test.sh` enforces this. See
`docs/VERIFICATION.md` §4.1.

### Before every commit

```bash
./scripts/secret-scan.sh              # staged content
./scripts/independent-secret-scan.sh --staged
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
