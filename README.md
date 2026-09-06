# ScamWall

ScamWall is a local-first fraud-domain protection engine for home networks.

The first integration targets Pi-hole v6 through its documented HTTPS API. ScamWall runs separately in a hardened Docker container and does not modify Pi-hole files, databases, services, or source code.

## Project status

ScamWall is under active development and is not ready for production use.

The first release will operate in read-only dry-run mode while its policy validation, ownership model, rollback behavior, and Pi-hole compatibility are tested.

## Documentation

| Document | What it is for |
| --- | --- |
| [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md) | The phased plan: what is built, in what order, and what each phase must prove before it closes |
| [`docs/REQUIREMENTS_MATRIX.md`](docs/REQUIREMENTS_MATRIX.md) | Every requirement, with a stable ID, its status, its tests, and the evidence it needs |
| [`docs/VERIFICATION.md`](docs/VERIFICATION.md) | The evidence record: what was actually run, against which commit and tools, and what came out |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | How the pieces fit together |
| [`docs/THREAT_MODEL.md`](docs/THREAT_MODEL.md) | Assets, adversaries, and what is out of scope |
| [`docs/SECURITY_BOUNDARIES.md`](docs/SECURITY_BOUNDARIES.md) | The boundaries themselves, and the discovery work behind them |
| [`docs/PIHOLE_API_CONTRACT.md`](docs/PIHOLE_API_CONTRACT.md) | The Pi-hole v6 API as observed, and the obligations it places on the client |

A note on how to read them: a requirement marked `VERIFIED` means the evidence
exists and is recorded against a specific commit. `BLOCKED` means a required
check could not run here — it is never treated as a pass, and it fails the gate
suite. Nothing in this repository yet constitutes a claim about how well
ScamWall detects scam domains; that is Phase 4 and has not begun.

## Security principles

- Fail safely without interrupting DNS
- Verify TLS certificates
- Keep credentials out of source code and logs
- Require signed, versioned threat feeds
- Preserve user-managed Pi-hole entries
- Apply deterministic safety gates before enforcement
- Collect no telemetry by default
- Never claim complete scam protection

## License

ScamWall is licensed under the GNU Affero General Public License v3.0 only (AGPL-3.0-only).
