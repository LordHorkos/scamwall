# ScamWall

ScamWall is a local-first fraud-domain protection engine for home networks.

The first integration targets Pi-hole v6 through its documented HTTPS API. ScamWall runs separately in a hardened Docker container and does not modify Pi-hole files, databases, services, or source code.

## Project status

ScamWall is under active development and is not ready for production use.

The first release will operate in read-only dry-run mode while its policy validation, ownership model, rollback behavior, and Pi-hole compatibility are tested.

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
