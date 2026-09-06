# syntax=docker/dockerfile:1
# SPDX-License-Identifier: AGPL-3.0-only

# =============================================================================
# ScamWall container image
#
# Two stages. The build stage has a toolchain; the final stage has a single
# static binary and nothing else — no shell, no package manager, no libc, no
# setuid binaries. There is nothing in the final image for an attacker who
# achieves code execution to pivot with.
#
# The Pi-hole CA and the application password are NEVER baked in. They are
# read-only mounts supplied at run time, so the image contains no secret and
# can be rebuilt or shared without exposing anything.
# =============================================================================

# Pinned by digest, not by tag: a tag is mutable and can be repointed at
# different content, which would silently change what is being built.
#
# golang:1.26.8-trixie
#   index  sha256:771f3162219f7a66bb6be3fea1ba31f418932946a99ad9eac26ffd555dfcf393
#   amd64  sha256:2d54f6c8c6ea532a321e0b4c69553b2ed3637608d4f4357dbed37939fe2620cc
# The index digest is used so the image remains correct on other architectures;
# on this host (linux/amd64) it resolves to the amd64 manifest above, verified
# against the registry before pinning.
#
# Go 1.26.8 is a CURRENTLY SUPPORTED release. The previous pin was 1.24, which
# is end-of-life upstream and which govulncheck flagged for 24 standard-library
# vulnerabilities, several reachable from this code. The toolchain version is a
# security control, not a preference, and it must match go.mod's toolchain
# directive so local, CI and container builds agree.
FROM golang:1.26.8-trixie@sha256:771f3162219f7a66bb6be3fea1ba31f418932946a99ad9eac26ffd555dfcf393 AS build

# Build metadata, supplied by the build command rather than baked into source.
ARG VERSION=dev
ARG COMMIT=unknown
ARG BUILD_DATE=unknown

WORKDIR /src

# GOTOOLCHAIN=local forbids an implicit toolchain download anywhere in this
# stage. It is set BEFORE the module steps: `go mod download` will happily
# fetch a different compiler if go.mod asks for one, which would make the
# build silently non-hermetic and dependent on network reachability. If the
# base image Go does not satisfy go.mod, the build must fail visibly instead.
ENV GOTOOLCHAIN=local

# Dependencies are resolved before the source is copied so that a source-only
# change does not invalidate the module download layer.
COPY go.mod go.sum ./
RUN go mod download && go mod verify

COPY . .

# Reproducibility and hardening:
#   CGO_ENABLED=0  static binary; nothing to resolve at run time, so the final
#                  stage needs no libc and the image can be scratch
#   -trimpath      removes build-host paths from the binary
#   -buildid=      removes a non-deterministic build id
#   -s -w          strips symbol and DWARF tables
ENV CGO_ENABLED=0 GOOS=linux GOFLAGS=-trimpath
RUN go build \
      -ldflags="-s -w -buildid= \
        -X main.version=${VERSION} \
        -X main.commit=${COMMIT} \
        -X main.built=${BUILD_DATE}" \
      -o /out/scamwall ./cmd/scamwall

# Fail the build rather than ship a dynamically linked binary: a dynamic
# binary would not run in the scratch stage, and discovering that at run time
# is worse than discovering it here.
#
# The previous form of this assertion was:
#
#   RUN ! ldd /out/scamwall 2>/dev/null | grep -q "=>" || (echo ... && exit 1)
#
# which proved nothing. `ldd` exits nonzero and prints nothing useful for a
# static binary, for a MISSING binary, for a corrupt one, and when `ldd` itself
# is absent — all four produced "no => lines", i.e. a pass. It also may execute
# the object it is asked about.
#
# elfcheck parses the ELF structure with debug/elf and asserts the intended
# properties positively: an executable object type, no PT_INTERP and no
# .interp, no PT_DYNAMIC and no SHT_DYNAMIC, and no DT_NEEDED library. A file
# that cannot be opened or parsed is a FAILURE. It needs no tool beyond the Go
# toolchain this stage already has, so there is no "checker was not installed"
# path that silently passes. Its positive and negative controls are
# internal/buildcheck/elfcheck/main_test.go.
#
# Scope: this proves the binary carries no dynamic linking apparatus. It does
# not prove the binary is safe, secret-free, or built from this source.
RUN go run ./internal/buildcheck/elfcheck /out/scamwall

# Verify the binary runs and reports enforcement as absent. This is a build-time
# assertion of the Phase 1 boundary.
#
# The output is captured to a file first and matched afterwards. `producer |
# grep -q` lets grep exit at the first match and the producer take SIGPIPE,
# which under a pipefail-enabled shell turns a satisfied assertion into a
# failed one (docs/VERIFICATION.md 4.1). RUN uses /bin/sh without pipefail
# today, so the bug was latent rather than active — but the form is the one
# this repository has already been burned by, so it is not used anywhere.
RUN /out/scamwall version > /out/version.txt \
      && grep -qE "enforcement compiled in[[:space:]]+false" /out/version.txt \
      || (echo "enforcement must not be compiled in; observed:" \
          && cat /out/version.txt \
          && exit 1)

# =============================================================================
# Final stage: scratch.
#
# ScamWall never consults the system trust store — it trusts only the Pi-hole
# private CA supplied as a read-only mount — so no ca-certificates bundle is
# needed. Name resolution for the API host is supplied via extra_hosts, which
# Docker writes into /etc/hosts, so no resolver configuration is needed either.
# =============================================================================
FROM scratch AS final

ARG VERSION=dev
ARG COMMIT=unknown
ARG BUILD_DATE=unknown

LABEL org.opencontainers.image.title="ScamWall" \
      org.opencontainers.image.description="Read-only, dry-run fraud-domain protection engine for Pi-hole" \
      org.opencontainers.image.source="https://github.com/LordHorkos/scamwall" \
      org.opencontainers.image.licenses="AGPL-3.0-only" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${COMMIT}" \
      org.opencontainers.image.created="${BUILD_DATE}"

COPY --from=build /out/scamwall /usr/local/bin/scamwall

# A fixed, high, non-root UID/GID. 65532 is the conventional "nonroot" id and
# is well outside the range of real host accounts, so a mount that escaped its
# intended permissions would still not match a privileged host user.
#
# There is no /etc/passwd in this image, which is why a numeric id is used
# rather than a name.
USER 65532:65532

# There is deliberately no HEALTHCHECK.
#
# Phase 1 is a one-shot task: the container runs `sync --dry-run`, prints a
# plan, and exits. Docker only probes a RUNNING container, and the first probe
# fires no earlier than the start period — by which time this container has
# already exited. A healthcheck here would never report on anything, while
# implying to a reader that liveness is being monitored. That is worse than
# having none.
#
# `scamwall doctor --offline` remains the right pre-flight check: it validates
# configuration, the CA, the feed signature, and the absence of enforcement,
# without touching the network and without a credential. Run it as its own
# invocation, where its exit status is actually observed:
#
#   docker compose -f deploy/compose/compose.yaml run --rm scamwall doctor --offline
#
# When Phase 2 introduces a long-running service, a healthcheck becomes
# meaningful and should be added then.

ENTRYPOINT ["/usr/local/bin/scamwall"]
CMD ["sync", "--dry-run"]
