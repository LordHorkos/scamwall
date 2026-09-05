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
# GOTOOLCHAIN=local forbids an implicit toolchain download during the image
# build. If the base image Go does not satisfy go.mod, the build fails visibly
# instead of silently fetching a different compiler over the network.
ENV CGO_ENABLED=0 GOOS=linux GOFLAGS=-trimpath GOTOOLCHAIN=local
RUN go build \
      -ldflags="-s -w -buildid= \
        -X main.version=${VERSION} \
        -X main.commit=${COMMIT} \
        -X main.built=${BUILD_DATE}" \
      -o /out/scamwall ./cmd/scamwall

# Fail the build rather than ship a dynamically linked binary: a dynamic
# binary would not run in the scratch stage, and discovering that at run time
# is worse than discovering it here.
RUN ! ldd /out/scamwall 2>/dev/null | grep -q "=>" || (echo "binary is not static" && exit 1)

# Verify the binary runs and reports enforcement as absent. This is a build-time
# assertion of the Phase 1 boundary.
RUN /out/scamwall version | grep -qE "enforcement compiled in[[:space:]]+false" \
      || (echo "enforcement must not be compiled in" && exit 1)

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

# The healthcheck runs entirely offline: it validates configuration, the CA,
# the feed signature, and that enforcement is absent, without touching the
# network and without authenticating. A health probe should not have side
# effects, and it should not need a credential.
HEALTHCHECK --interval=60s --timeout=10s --start-period=5s --retries=3 \
  CMD ["/usr/local/bin/scamwall", "doctor", "--offline"]

ENTRYPOINT ["/usr/local/bin/scamwall"]
CMD ["sync", "--dry-run"]
