# ScamWall Security Boundaries

This document states, in operational terms, what ScamWall is permitted to do,
what it is structurally incapable of doing, and what was observed about this
specific deployment during Phase 1 discovery.

It is written to be checkable. Every claim should be falsifiable by running a
command.

---

## 1. Hard boundaries (Phase 1)

ScamWall **must not**, and in Phase 1 **cannot**:

| # | Boundary | Enforcement |
| --- | --- | --- |
| 1 | Modify, restart, reconfigure, upgrade, containerise, or patch Pi-hole | No such code path; no mutating endpoint is reachable |
| 2 | Modify Pi-hole files, databases, systemd units, or web interface | `/etc/pihole` is never mounted; container has no host write access |
| 3 | Enable `webserver.api.app_sudo` | `/api/config` is never called |
| 4 | Enable destructive API operations | No `POST`/`PUT`/`PATCH`/`DELETE` except `DELETE /api/auth` (own session) |
| 5 | Modify firewall, router, DNS clients, Apache, or host networking | No `NET_ADMIN`; all capabilities dropped; no host networking |
| 6 | Expose container ports | No `ports:` key; verified by compose inspection |
| 7 | Mount `/etc/pihole` or `/var/run/docker.sock` | No such mount; verified by compose inspection |
| 8 | Print, inspect, copy, log, or commit the application password | `Secret` type + logger redaction + secret scan in CI |
| 9 | Disable TLS verification | `InsecureSkipVerify` absent; asserted by test |
| 10 | Use `curl -k` or equivalent | Never used in code, scripts, or tooling |
| 11 | Push to GitHub during Phase 1 | Local commits only |
| 12 | Make any Pi-hole API mutation | See #4 |
| 13 | Download or enforce third-party domain feeds | Feed source is a repository-owned fixture only |
| 14 | Install host packages without approval | Approvals recorded in this document |

`DELETE /api/auth` is the single non-`GET` request ScamWall issues besides
`POST /api/auth`. It deletes **only ScamWall's own session** and changes no
Pi-hole configuration, no blocklist, and no persistent state. Not logging out
would be the less safe choice: abandoned sessions remain valid for 30 minutes
and consume finite session seats.

---

## 2. Stop conditions

Phase 1 halts immediately if any of these hold. Status as assessed:

| Condition | Status |
| --- | --- |
| `pi.hole` cannot be mapped to the container's view of the Pi-hole host | **Resolved** — pinned via `extra_hosts` (§4) |
| The certificate does not validate for `pi.hole` | **Passes** — `Verify return code: 0 (ok)` with `-verify_hostname pi.hole` |
| The secret cannot be made readable to a non-root container without becoming world-readable | **Open** — deferred; see §5 |
| Docker requires privileged mode, host networking, added capabilities, or socket access | **Passes** — none required |
| The installed API differs materially from its live documentation | **Passes** — no divergence; see `PIHOLE_API_CONTRACT.md` §6 |

---

## 3. Discovery observations

Captured read-only. No host state was changed.

| Item | Observation |
| --- | --- |
| Working directory | `/home/scamwall/scamwall` — ScamWall refuses to operate elsewhere |
| Service account | `uid=1000(scamwall) gid=1000(scamwall)` |
| Supplementary groups | `cdrom, floppy, audio, dip, video, plugdev, users, netdev` — **not** `docker` |
| Docker Engine | 29.8.0, `containerd.io` 2.3.4, buildx 0.37.0, compose 5.5.1 |
| Docker socket | `srw-rw---- root:docker /var/run/docker.sock`; group `docker` (gid 990) is empty |
| User-namespace remapping | **Not active** |
| Rootless mode | **Not active** — `DOCKER_HOST` unset, no `/run/user/1000/docker.sock` |
| Docker bridge | `docker0` at `172.17.0.1/16`, state DOWN (no containers running) |
| Firewall managers | `ufw`, `firewalld`, `nftables`, `netfilter-persistent` all **inactive**; `ufw` not installed |
| Firewall rules | Enumeration requires root; attempted read-only, denied, **not escalated** |
| Occupied ports | `53/tcp+udp` (Pi-hole), `443/tcp` (Pi-hole API), `80/tcp` (Apache), `22/tcp` (sshd), `123/udp` (ntp), `68/udp` (dhcp client) |
| Port conflicts | None — ScamWall publishes no ports |
| Git | 2.47.3 |
| GitHub CLI | 2.100.0, authenticated as `LordHorkos`, scopes `gist, read:org, repo`. Token masked by `gh`; **never printed or stored** |
| Repository | `github.com/LordHorkos/scamwall`, **public**, default branch `main` (**protected**) |
| Working branch | `feat/phase-1-core` — the only branch ScamWall commits to |

Because the repository is **public**, `.gitignore` is deny-by-default for
credentials, certificates, keys, state, and logs, and a secret scan runs before
each commit.

---

## 4. Finding: `pi.hole` does not resolve to the Pi-hole host

**This is the most operationally significant discovery of Phase 1.**

On this network, DNS resolution of `pi.hole` returns `<unrelated-appliance-ip>` — a different
appliance, presenting a self-signed certificate `CN=<unrelated-appliance>`
(SAN `IP:<unrelated-appliance-ip>, DNS:<unrelated-appliance>`). The host actually running Pi-hole is a
different machine on the same subnet.

Consequences:

* A naive `curl https://pi.hole/api/...` from this host fails with `unknown CA`.
  That failure is **correct behaviour** — TLS refused to trust a device that is
  not the intended peer. The correct response is to fix resolution, never to
  add `-k`.
* Anything on this host that trusts DNS for the name `pi.hole` is talking to
  another device. This is worth reviewing independently of ScamWall.

Resolution: `pi.hole` is pinned to the Pi-hole host's address via `extra_hosts`,
overriding **name resolution only**. Certificate and hostname verification are
unchanged — the leaf must still present `SAN DNS:pi.hole` and chain to the
configured private CA.

```yaml
extra_hosts:
  # PIHOLE_HOST_IP comes from a local, gitignored .env file so that no
  # site-specific address is ever committed to this public repository.
  # It defaults to the Docker bridge gateway when unset.
  - "pi.hole:${PIHOLE_HOST_IP:-host-gateway}"
```

Two forms are supported and verify identically:

* **`host-gateway`** — resolves to the `docker0` bridge gateway. Keeps
  container&rarr;host traffic on the Docker bridge. This is the default.
* **An explicit LAN address** — routes container&rarr;host traffic over the host's
  LAN interface instead. Set `PIHOLE_HOST_IP` in `.env` to use it.

The same pinning is available to the binary outside a container through a
configured address override, which is the exact analogue of `curl --resolve`.
It is not, and must never become, a verification bypass.

---

## 5. Open verification items

Honest accounting of what is **not** yet proven on live infrastructure.

### 5.1 Secret readability — deferred by decision

`/etc/scamwall/secrets` is `drwx------ root:root`. Neither uid 1000 nor a
non-root container user can read the application password. Live authentication
is therefore unproven end-to-end.

Recommended minimal grant, never world-readable:

```bash
sudo groupadd -r swsecret
sudo chgrp swsecret /etc/scamwall/secrets /etc/scamwall/secrets/pihole_app_password
sudo chmod 0750 /etc/scamwall/secrets
sudo chmod 0640 /etc/scamwall/secrets/pihole_app_password
```

The container then runs with that GID as a supplementary group. This is
preferred over granting to gid 1000, which would additionally expose the
password to the interactive `scamwall` shell session.

Until applied: `POST /api/auth` success, authenticated `GET /api/info/version`,
and `DELETE /api/auth` &rarr; `204` are exercised **only** against the fake Pi-hole
HTTPS server in the test suite, never live.

### 5.2 Docker daemon access

The service account is not in the `docker` group and has no passwordless sudo.
By operator decision, Docker commands are executed by the operator rather than
granting the account root-equivalent access. Image build, `docker compose
config`, and container-security assertions are therefore operator-executed.

This is the more conservative choice: `docker` group membership is effectively
root on this host, since it permits mounting the host filesystem into a
container.

### 5.3 Go toolchain

Not installed at time of writing. Approved for installation via
`sudo apt-get install -y golang-go` (Debian trixie, Go 1.24). Until present,
`go vet`, `go test -race`, `staticcheck`, and `govulncheck` cannot be run, and
their results must be reported as unrun rather than as passing.

---

## 6. What a full ScamWall compromise would yield

Assume an attacker achieves arbitrary code execution inside the container.

They obtain: the Pi-hole application password, a valid API session, and
read access to version information and the feed fixture.

They do **not** obtain: any capability (all dropped), any writable host path
(read-only root filesystem, read-only mounts), the Docker socket, host
networking, any listening port, or the ability to escalate privileges
(`no-new-privileges`).

They **could** authenticate to the Pi-hole API with the stolen password and call
mutating endpoints directly — ScamWall's own inability to mutate does not
constrain an attacker holding the credential. This is the principal residual
risk of Phase 1 and is addressed in `docs/THREAT_MODEL.md`. It is the reason
the application password should be scoped as narrowly as Pi-hole permits and
rotated if the container is ever suspected of compromise.
