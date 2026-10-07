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
   - `sites/`: one `*.caddy` file per site. Edit `app1.caddy`/`app2.caddy`, copy them for
     more sites. Every hostname gets its own certificate (see [Certificates](#certificates)).
   - `compose.yaml`: replace the demo `app1`/`app2` services with your apps, or remove them
     and attach apps from their own stacks ([Adding an app](#adding-an-app)).

3. **Start and check**

   ```sh
   docker compose up -d
   docker compose logs -f caddy        # wait for "certificate obtained successfully" per host
   curl -I https://app1.example.com
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
| `compose.yaml` | Caddy on `caddy_egress` (internet) plus one internal network per app |
| `sites/wildcard.caddy.example` | Wildcard certificate via acme-dns; rename to `.caddy` to enable |

### Networks: one per app

Caddy joins every app network; each app joins only its own. Apps therefore cannot reach each
other, only Caddy reaches them:

```
internet ── caddy_egress ── caddy ──┬── caddy_app1 ── app1
                                    └── caddy_app2 ── app2
```

App networks are `internal: true`, so apps have no internet access either. An app that needs
outbound traffic (APIs, SMTP) gets an extra, non-internal network of its own, never a shared
one. Networks have fixed names (`name:`), so stacks in other directories can join them.

### Adding an app

1. Create its network once in `compose.yaml` (`caddy_app3`, `internal: true`), add it to the
   `caddy` service and run `docker compose up -d caddy`.
2. In the app's own stack, join that network only:

   ```yaml
   services:
     web:
       image: example/app3
       networks:
         caddy_app3:
           aliases: [app3] # unique name for Caddy
   networks:
     caddy_app3:
       external: true
   ```

   Caddy sits on every app network, so plain service names like `web` would collide between
   stacks; always give each app a unique alias.

3. Add `sites/app3.caddy` with `reverse_proxy app3:<port>` and reload Caddy (step 4 above).

Adding a network to Caddy recreates its container (a few seconds without TLS); adding a site
file only needs a reload.

### Certificates

Every hostname in `sites/` gets its own certificate from Let's Encrypt, renewed automatically.
Two ways to prove you own the domain:

**Option 1: DNS (acme-dns, DNS-01)**
- Needed for **wildcards** (`*.example.net`) and hosts not reachable on 80/443.
- Per base domain: register against your acme-dns server
  (`curl -X POST https://auth.acme-dns.io/register`), CNAME `_acme-challenge.<domain>` to the
  returned `fulldomain`, put the credentials into `.env`, rename
  `sites/wildcard.caddy.example` to `.caddy`. A second wildcard domain needs its own
  registration and variable names.
- Set per site (`tls { dns acmedns … }`), so only those sites use DNS-01.

**Option 2: Hosting (HTTP-01 / TLS-ALPN-01, the default)**
- The hostname's A/AAAA record points to this server and ports 80/443 are reachable. Nothing
  else to configure: add the site file, reload, and Caddy obtains the certificate.
- One certificate per hostname, no DNS credentials on the server.
- Behind a CDN or proxy (e.g. Cloudflare orange cloud), the challenge may not reach Caddy; use
  Option 1 then.

**Which one:** Option 2 for normal sites; Option 1 only for wildcards or hosts that are not
publicly reachable. Both can be mixed on the same instance.

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
- **acme-dns:** see [Certificates, Option 1](#certificates).

Plugin directives have no default order, so the Caddyfile must set one (`order …` in the
global options); [`test/Caddyfile`](test/Caddyfile) shows every plugin's syntax and is
validated in CI.

### Ship the config with the app

Only for a proxy dedicated to one app whose Caddyfile belongs to its release (e.g. it pins
CSP hashes). For the multi-site setup above, keep `sites/` mounted instead.

```dockerfile
FROM ghcr.io/floriandeutsch89/caddy:2.11.7@sha256:<digest>
COPY Caddyfile /etc/caddy/Caddyfile
```

### Running as non-root (UID 10001)

Applies to every install:

- **Named volumes** (as in the example): new ones take their ownership from the image, nothing
  to do.
- **Bind mounts** (`./data:/data`): Docker creates a missing host directory as root, and Caddy
  cannot write certificates. Create them first:
  `mkdir -p data config && sudo chown 10001:10001 data config`.
- **Kubernetes PVCs** and volume drivers without copy-on-first-mount (NFS, cloud volumes,
  `nocopy`): set `securityContext.fsGroup: 10001` or chown as for bind mounts.
- **Ports 80/443** bind without capabilities because Docker (≥ 20.10) sets
  `net.ipv4.ip_unprivileged_port_start=0` in the container's network namespace. Not with
  `network_mode: host` (the host's value applies, default 1024) or on Kubernetes: set that
  sysctl (pod `securityContext.sysctls`, a "safe" sysctl since 1.22). Podman/rootless Docker:
  check before relying on it.

### Upgrading from the stock image

The official `caddy` image runs as root, so its volumes are root-owned. Fix them once, before
the switch, or Caddy cannot renew certificates:

```sh
docker run --rm -v caddy-data:/data -v caddy-config:/config alpine chown -R 10001:10001 /data /config
```

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
