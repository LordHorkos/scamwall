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
| 6 | Expose container ports | No `ports:` key; verified by compose inspection and by container inspection (§5.4) |
| 7 | Mount `/etc/pihole` or `/var/run/docker.sock` | No such mount; verified by compose inspection and by container inspection (§5.4) |
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

### 5.1 Secret readability — grant applied, live authentication still unverified

The minimal grant below has been applied on this host. A dedicated system group
owns the secret; the service account is not a member of it, and the password is
never world-readable:

```bash
sudo groupadd -r swsecret
sudo chgrp swsecret /etc/scamwall/secrets /etc/scamwall/secrets/pihole_app_password
sudo chmod 0750 /etc/scamwall/secrets
sudo chmod 0640 /etc/scamwall/secrets/pihole_app_password
```

Operator-verified host metadata: the `swsecret` group exists,
`/etc/scamwall/secrets` is `root:swsecret 0750`, and
`/etc/scamwall/secrets/pihole_app_password` is `root:swsecret 0640`. The
compose definition resolves `group_add` to that group's GID — but only when
`--env-file deploy/compose/.env` is passed explicitly, because Compose reads a
bare `.env` from the current directory, not from the compose file's directory.
Omit it and `group_add` silently falls back to the `65532` default, which grants
nothing.

**This establishes configured permissions, not proven access.** No ScamWall
process has been observed reading the password file, and no live authentication
has been performed. The grant makes success *possible*; it does not demonstrate
it.

Still unverified against live infrastructure: `POST /api/auth` success,
authenticated `GET /api/info/version`, and `DELETE /api/auth` &rarr; `204`. These
are exercised **only** against the fake Pi-hole HTTPS server in the test suite.

### 5.2 Docker daemon access

The service account is not in the `docker` group and has no passwordless sudo.
By operator decision, Docker commands are executed by the operator rather than
granting the account root-equivalent access.

This is the more conservative choice: `docker` group membership is effectively
root on this host, since it permits mounting the host filesystem into a
container.

Consequently `docker build` and the container-security **runtime** assertions
are operator-executed and are reported as BLOCKED — never as passing — when
`scripts/check.sh` runs as the service account.

`docker compose config` is **not** in that set. It parses, interpolates and
validates the definition entirely client-side, so it runs without daemon
access and is gated separately. It was previously grouped with the daemon
checks, which reported a runnable check as BLOCKED on every host without socket
access.

### 5.3 Go toolchain — RESOLVED, and a finding in its own right

Go is installed. The distribution package is `go1.24.4`, which is **end-of-life
upstream**: the supported set at the time of writing is `go1.26.8` and
`go1.27.1`.

Running `govulncheck` against the 1.24.4 build produced **26 findings** — 24 in
the standard library plus two in dependencies. Two were reachable from
ScamWall's own code, both through the same call path that processes untrusted
feed content:

| Finding | Reached via | Effect |
| --- | --- | --- |
| `GO-2026-5970` | `domain.Normalize` &rarr; `idna.ToASCII` &rarr; `norm.Form.Bytes` | Infinite loop on crafted input in `golang.org/x/text` — a denial of service in domain validation |
| `GO-2026-5026` | `domain.Normalize` &rarr; `idna.Profile.ToASCII` | Vulnerability in `golang.org/x/net/idna` |

That a feed-processing path reached a denial-of-service bug is the reason the
toolchain and dependency versions are treated as security controls rather than
housekeeping.

Resolution:

* `go.mod` pins `toolchain go1.26.8`, a currently supported release.
* `golang.org/x/net` raised to `v0.58.0`, `golang.org/x/text` to `v0.41.0`.
* The container base image is pinned to `golang:1.26.8-trixie` by digest, so
  local, CI and container builds use the same compiler.
* `GOTOOLCHAIN=local` in the image build forbids an implicit toolchain download,
  so a mismatch fails visibly instead of silently fetching another compiler.

`govulncheck` now reports **no vulnerabilities**.

Note that `go1.26.8` is obtained through Go's own toolchain mechanism rather
than from apt, and is verified against the Go checksum database. The apt package
remains at 1.24.4 and is not used for this module.

### 5.4 Container runtime verification — evidence, and its limits

Operator-executed, since the service account cannot reach the daemon (§5.2).

> **This evidence describes a SUPERSEDED image.** It was collected before the
> `HEALTHCHECK` was removed from `container/Dockerfile` and before
> `scripts/container-security-check.sh` was corrected. The image must be
> rebuilt and the runtime checks rerun before these results describe what is
> actually shipped. Until then, treat this section as a record of what *was*
> observed, not as current verification.

**Build.** Exit 0. Image config digest
`sha256:303426340aa1d68c3740aafb2ffc18f33e54b1d7ef3c6da4960a9f706f6c08eb`. All
claims below are scoped to that digest.

**Container creation.** With `--env-file deploy/compose/.env` passed
explicitly, `docker compose create --no-build` returned exit 0 and the service
container reached `Created` state. It was inspected, never started, so no
authenticated workflow ran.

**Inspected `HostConfig` / `Config`** — the hardening the compose definition
claims, observed as effective on a real container:

| Property | Observed |
| --- | --- |
| `User` | `65532:65532` |
| `ReadonlyRootfs` | `true` |
| `Privileged` | `false` |
| `CapDrop` / `CapAdd` | `["ALL"]` / `null` |
| `SecurityOpt` | `["no-new-privileges:true"]` |
| `GroupAdd` | the `swsecret` GID, resolved from `.env` |
| `NetworkMode` | project-scoped bridge network — **not** host |
| `PortBindings` | `{}` — nothing published |
| `Tmpfs` `/tmp` | `rw,noexec,nosuid,nodev,size=16m` |
| `Memory` | 128 MiB |
| `NanoCpus` | 0.5 CPU |
| `PidsLimit` | 64 |
| `RestartPolicy` | `no`, max retries 0 |

All four mounts reported `RW=false`: the config file, the feed fixture, the
application password, and the Pi-hole CA.

**Offline execution.** `plan` was run with `--network none`, no password mount,
read-only rootfs, uid/gid 65532, all capabilities dropped, `no-new-privileges`,
restricted tmpfs, and the resource limits above. It produced a plan over the
repository's signed test fixture and exited 0:

```
proposed plan (scamwall-plan-v1)
feed:   scamwall-test-feed (manifest 1.0)
digest: sha256:4d1ed4ba4d3c7de138258360b2ed5e7b25442fc5bb42cca14693b0a35cbb952f
...
5 proposed, 3 excluded (1 not block, 1 below confidence, 1 expired)
```

This demonstrates that plan computation is genuinely offline: it completed with
no network namespace at all, and with no credential present.

**What this evidence does NOT establish:**

* **Not** live authentication. The subcommand was `plan` — not `doctor`, not
  `status`, not `sync`. `POST /api/auth` remains unverified against live
  infrastructure (§5.1).
* **Not** runtime password access. §5.1's grant is a permissions
  configuration; no process has been observed reading the file.
* **Not** the current image. See the notice above.
* The excerpt returned by the operator did not repeat the full `docker run`
  invocation, so the exact flag set used for the offline run is recorded here
  as described rather than as transcribed.

---
### 5.5 Operator rerun procedure

The evidence in §5.4 describes a superseded image. These are the exact commands
that replace it. Run them from the repository root as the operator (the service
account cannot reach the daemon — §5.2).

`--env-file` is explicit in every Compose invocation. Compose resolves a bare
`.env` against the current working directory, so omitting it silently drops
site-specific values, including the `swsecret` GID in `group_add`.

**1. Rebuild the updated image.**

```bash
cd /home/scamwall/scamwall

docker build \
  -f container/Dockerfile \
  -t scamwall:local \
  --build-arg VERSION="$(git describe --tags --always --dirty)" \
  --build-arg COMMIT="$(git rev-parse --short HEAD)" \
  --build-arg BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  .

# Record the new digest; it supersedes the one in 5.4.
docker image inspect -f '{{.Id}}' scamwall:local
```

**2. Recreate the container WITHOUT starting it.**

`create` builds the container and stops. Do **not** use `up`, `start` or `run`
on the default command here: the image's `CMD` is `sync --dry-run`, which
performs a live authenticated read. Creating and inspecting keeps this step
free of any credential use.

```bash
docker compose --env-file deploy/compose/.env -f deploy/compose/compose.yaml \
  down --remove-orphans

docker compose --env-file deploy/compose/.env -f deploy/compose/compose.yaml \
  create --no-build

docker compose --env-file deploy/compose/.env -f deploy/compose/compose.yaml \
  ps -a
```

**3. Rerun the corrected runtime checks.**

The checker creates and removes its own container, so remove the one from step 2
first if it is still present. It now FAILS rather than skips when an inspection
cannot run, and establishes shell absence by enumerating the image filesystem
rather than by attempting execution.

```bash
docker compose --env-file deploy/compose/.env -f deploy/compose/compose.yaml rm -fs

bash scripts/container-security-check.sh --runtime   # runtime assertions only
bash scripts/check.sh                                # every gate
```

**4. Repeat the offline plan.**

`plan` reads only the configuration and the signed feed — it never opens the CA
or the password, so neither is mounted. With `--network none` there is no
network namespace at all, which is what makes this a real offline proof rather
than a claim about intent.

```bash
docker run --rm \
  --network none \
  --read-only \
  --user 65532:65532 \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --tmpfs /tmp:rw,noexec,nosuid,nodev,size=16m \
  --memory 128m --memory-swap 128m --pids-limit 64 --cpus 0.50 \
  -v "$PWD/deploy/compose/config.example.json:/etc/scamwall/config.json:ro" \
  -v "$PWD/testdata/feed.json:/etc/scamwall/feed.json:ro" \
  scamwall:local plan
echo "PLAN exit=$?"
```

**Live authentication remains UNVERIFIED.** None of the four steps above
authenticates to Pi-hole, and none is intended to. Proving `POST /api/auth`,
authenticated `GET /api/info/version`, and `DELETE /api/auth` &rarr; `204`
against live infrastructure is a separate, explicitly authorised step (§5.1),
and until it is performed those paths are exercised only against the test
suite's fake HTTPS server.

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
