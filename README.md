# caddy

[![ci](https://github.com/floriandeutsch89/caddy/actions/workflows/ci.yml/badge.svg)](https://github.com/floriandeutsch89/caddy/actions/workflows/ci.yml)

Caddy 2 with these plugins compiled in, as a hardened multi-arch image (amd64, arm64):

| Plugin | Modules | License |
|---|---|---|
| [hslatman/caddy-crowdsec-bouncer](https://github.com/hslatman/caddy-crowdsec-bouncer) (`/http`) | `crowdsec`, `http.handlers.crowdsec` | Apache-2.0 |
| [caddy-dns/acmedns](https://github.com/caddy-dns/acmedns) | `dns.providers.acmedns` | MIT |
| [mholt/caddy-ratelimit](https://github.com/mholt/caddy-ratelimit) | `http.handlers.rate_limit` | Apache-2.0 |

```
ghcr.io/floriandeutsch89/caddy:2.11.7   # also :2.11, :2, :latest, :sha-<commit>
```

## Getting started

**You need:** Docker with Compose, A/AAAA records for every hostname pointing to the host,
and ports 80 and 443 (TCP + UDP) reachable from the internet.

1. **Get the example stack**

   ```sh
   git clone --depth 1 https://github.com/floriandeutsch89/caddy.git caddy-src
   cp -r caddy-src/examples caddy && cd caddy && cp .env.example .env
   ```

   If the image is private, run `docker login ghcr.io` first (token with `read:packages`).

2. **Configure**
   - `.env`: set `ACME_EMAIL` (Let's Encrypt expiry and problem notices).
   - `sites/`: one `*.caddy` file per site. Edit `sites/app.caddy`, copy it for more sites.
     Every hostname gets its own certificate; nothing else to configure for TLS.
   - `compose.yaml`: replace the demo `app` service with your upstreams. They must share a
     Docker network with Caddy (the default compose network does).

3. **Start and check**

   ```sh
   docker compose up -d
   docker compose logs -f caddy        # wait for "certificate obtained successfully" per host
   curl -I https://app.example.com
   ```

4. **Add or change a site** without a restart: edit `sites/`, then

   ```sh
   docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
   ```

   A broken config is rejected and the running one stays active.

The example runs read-only, with all capabilities dropped and as UID `10001`. New named
volumes take their ownership from the image, so nothing to chown on a fresh install.

### Layout

| File | Purpose |
|---|---|
| `Caddyfile` | Global options, the shared `(common)` snippet (compression, security headers, rate limit, CrowdSec), `import sites/*.caddy` |
| `sites/*.caddy` | One file per site; start each with `import common` |
| `sites/wildcard.caddy.example` | Wildcard certificate via acme-dns; rename to `.caddy` to enable |

Many sites on one host are fine: certificates are issued and renewed independently, and
Let's Encrypt's limits (50 certificates per registered domain per week) only matter for
hundreds of subdomains. Then use a wildcard instead.

### Enable the plugins

- **Rate limit** (on by default via `common`): 300 requests/min per client IP. Behind another
  proxy or CDN, `{remote_host}` is that proxy; configure `trusted_proxies` and key on
  `{client_ip}` instead.
- **CrowdSec:** needs a running CrowdSec LAPI that reads Caddy's access log. Create the key
  with `cscli bouncers add caddy-bouncer`, put it into `CROWDSEC_API_KEY`, uncomment the
  `crowdsec` lines in `Caddyfile` (global block and `common`).
- **acme-dns (DNS-01):** only for wildcards or hosts not reachable on 80/443; the other sites
  keep the default HTTP challenge. Per base domain: register against your acme-dns server
  (`curl -X POST https://auth.acme-dns.io/register`), CNAME `_acme-challenge.<domain>` to the
  returned `fulldomain`, put the credentials into `.env`, rename
  `sites/wildcard.caddy.example`. A second wildcard domain needs its own registration, so give
  it its own variable names.

Plugin directives have no default order, so the Caddyfile must set one (`order …` in the
global options); [`test/Caddyfile`](test/Caddyfile) shows every plugin's syntax and is
validated in CI.

### Ship the config with the app

When the Caddyfile belongs to an app release (e.g. it pins CSP hashes), build it in:

```dockerfile
FROM ghcr.io/floriandeutsch89/caddy:2.11.7@sha256:<digest>
COPY Caddyfile /etc/caddy/Caddyfile
```

### Migrating from the stock image

The official `caddy` image runs as root, so its volumes are root-owned. Fix them once,
before the switch, or Caddy cannot write certificates:

```sh
docker run --rm -v caddy-data:/data -v caddy-config:/config alpine chown -R 10001:10001 /data /config
```

Same for bind mounts. Ports 80/443 work as non-root because Docker (≥ 20.10) sets
`net.ipv4.ip_unprivileged_port_start=0` in the container. With `network_mode: host` or on
Kubernetes, set that sysctl yourself (pod `securityContext.sysctls`).

### Pinning and verifying

Tags are rebuilt weekly, so they move. In production, pin the digest and verify its origin:

```sh
docker buildx imagetools inspect ghcr.io/floriandeutsch89/caddy:2.11.7   # shows the digest
gh attestation verify oci://ghcr.io/floriandeutsch89/caddy:2.11.7 --owner floriandeutsch89
```

## How it is built

- **`main.go` + `go.mod`/`go.sum`** instead of xcaddy: every module is pinned and checksummed
  (`go mod verify` in the build), and updates arrive as Dependabot PRs. This is the program
  xcaddy would generate.
- **Dockerfile:** the builder cross-compiles natively (`CGO_ENABLED=0`, no QEMU for Go); the
  runtime is the official `caddy:*-alpine` image with our binary, non-root, no file
  capabilities. Both bases pinned by digest.

### CI ([`.github/workflows/ci.yml`](.github/workflows/ci.yml))

| Job | When | What |
|---|---|---|
| `lint` | always | hadolint, `go mod tidy -diff`, gofmt, `go vet`, govulncheck, zizmor |
| `test` | always | build; smoke test: version == go.mod, all plugin modules, UID, `caddy validate` of `test/` and `examples/`, serving on :80 read-only with all caps dropped; Trivy (fails on fixable HIGH/CRITICAL) |
| `publish` | `main`, weekly, manual | multi-arch push, SBOM, provenance, signed GitHub attestation |

Actions are pinned by commit SHA. Dependabot updates Go modules, base images and actions weekly
with a 7-day cooldown.

## Updating

- **Caddy or a plugin:** merge the Dependabot PR, or locally
  `go get github.com/caddyserver/caddy/v2@vX.Y.Z && go mod tidy`. Bump the runtime base
  (`caddy:X.Y.Z-alpine`) along with it; it only supplies the filesystem, but should match.
- **Add a plugin:** add a blank import to `main.go`, `go mod tidy`, then extend the module list
  in the CI smoke test and `test/Caddyfile`.
- **Build locally:** `docker build -t caddy:dev .`

## Security

See [SECURITY.md](SECURITY.md).

## License

Build recipe: MIT ([LICENSE](LICENSE)). Shipped binaries: see the plugin table above.
