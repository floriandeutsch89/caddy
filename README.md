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

**You need:** Docker with Compose, a domain whose A/AAAA record points to the host, and
ports 80 and 443 (TCP + UDP) reachable from the internet.

1. **Copy the example stack**

   ```sh
   mkdir caddy && cd caddy
   base=https://raw.githubusercontent.com/floriandeutsch89/caddy/main/examples
   curl -fsSL -O "$base/compose.yaml" -O "$base/Caddyfile"
   curl -fsSL "$base/.env.example" -o .env
   ```

   If the repo is private, clone it instead and `cd examples && cp .env.example .env`.
   If the image is private, run `docker login ghcr.io` first (token with `read:packages`).

2. **Configure:** set `DOMAIN` and `ACME_EMAIL` in `.env`. Replace the `app` service in
   `compose.yaml` and the `reverse_proxy app:80` line with your upstream.

3. **Start and check**

   ```sh
   docker compose up -d
   docker compose logs -f caddy        # wait for "certificate obtained successfully"
   curl -I "https://$(grep ^DOMAIN= .env | cut -d= -f2)"
   ```

4. **Change the config** without a restart:

   ```sh
   docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
   ```

The example runs read-only, with all capabilities dropped and as UID `10001`. New named
volumes take their ownership from the image, so nothing to chown on a fresh install.

### Enable the plugins

All three are prepared in [`examples/Caddyfile`](examples/Caddyfile); uncomment and fill `.env`.

- **Rate limit** (on by default in the example): 300 requests/min per client IP. Behind
  another proxy or CDN, `{remote_host}` is that proxy; configure `trusted_proxies` and key on
  `{client_ip}` instead.
- **CrowdSec:** needs a running CrowdSec LAPI that reads Caddy's access log. Create the key
  with `cscli bouncers add caddy-bouncer`, put it into `CROWDSEC_API_KEY`, uncomment the
  `crowdsec` blocks.
- **acme-dns (DNS-01):** for wildcard certificates or hosts not reachable on 80/443. Register
  once against your acme-dns server (`curl -X POST https://auth.acme-dns.io/register`), set
  the CNAME `_acme-challenge.<domain>` to the returned `fulldomain`, fill the `ACMEDNS_*`
  values, uncomment the `acme_dns` block.

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
