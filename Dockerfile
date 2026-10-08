# syntax=docker/dockerfile:1
# Caddy with plugins. Modules are pinned + checksummed in go.mod/go.sum (bumped
# by Dependabot) instead of resolved by xcaddy at build time.

# Builder runs natively and cross-compiles (pure Go), so arm64 needs no QEMU here.
FROM --platform=$BUILDPLATFORM golang:1.27-alpine@sha256:8a5910f31396cd4d89662f56c68b3ae31d374308270a1c3bd96672ee5ed43414 AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download && go mod verify
COPY main.go ./
ARG TARGETOS TARGETARCH
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -trimpath -ldflags='-s -w' -o /out/caddy .

# Runtime base only supplies the filesystem layout (Caddyfile, mime types, CA
# certs, XDG env); the binary is ours, so its tag may lag go.mod briefly.
FROM caddy:2.11.7-alpine@sha256:d8542f48d34a9cf4e4c11a478865229840e87e4c96ea3f439101f31a5d35f75f
# Fixed non-root UID; group 0 with g=u so arbitrary UIDs (OpenShift, always GID 0)
# can write too. Volumes from the root-running stock image need a one-time chown (README).
RUN addgroup -S -g 10001 caddy \
 && adduser -S -D -H -u 10001 -G caddy -h /data caddy \
 && mkdir -p /var/log/caddy \
 && chown -R 10001:0 /data /config /var/log/caddy \
 && chmod -R g=u /data /config /var/log/caddy
COPY --from=builder /out/caddy /usr/bin/caddy
USER 10001:0
LABEL org.opencontainers.image.title="caddy" \
      org.opencontainers.image.description="Caddy 2 with crowdsec-bouncer, acmedns and ratelimit plugins" \
      org.opencontainers.image.source="https://github.com/floriandeutsch89/caddy" \
      org.opencontainers.image.licenses="Apache-2.0 AND MIT"
