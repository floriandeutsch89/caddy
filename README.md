# caddy

[![ci](https://github.com/floriandeutsch89/caddy/actions/workflows/ci.yml/badge.svg)](https://github.com/floriandeutsch89/caddy/actions/workflows/ci.yml)

Caddy 2 for hosting many small sites on one server, with these plugins (amd64, arm64):

- [caddy-crowdsec-bouncer](https://github.com/hslatman/caddy-crowdsec-bouncer) (Apache-2.0): block IPs banned by CrowdSec
- [caddy-dns/acmedns](https://github.com/caddy-dns/acmedns) (MIT): wildcard certificates via DNS
- [caddy-ratelimit](https://github.com/mholt/caddy-ratelimit) (Apache-2.0): per-IP rate limits

Plus a matching CrowdSec image with the Caddy collections baked in. Both: amd64 and arm64.

```
ghcr.io/floriandeutsch89/caddy:latest
ghcr.io/floriandeutsch89/crowdsec:latest
```

## Getting started

You need Docker with Compose, DNS records for each hostname pointing to the server, and ports
80/443 open.

```sh
git clone --depth 1 https://github.com/floriandeutsch89/caddy.git caddy-src
cp -r caddy-src/examples caddy && cd caddy && cp .env.example .env
sed -i "s/^CROWDSEC_API_KEY=.*/CROWDSEC_API_KEY=$(openssl rand -hex 32)/" .env
# set ACME_EMAIL in .env, edit sites/*.caddy and the apps in compose.yaml
docker compose up -d
docker compose logs -f caddy   # wait for "certificate obtained successfully"
```

| File | Purpose |
|---|---|
| `Caddyfile` | Global options, shared `(common)` snippet, `import sites/*.caddy` |
| `sites/*.caddy` | One file per site |
| `compose.yaml` | Caddy, CrowdSec, demo apps, one network per app, resource limits |

## Sites

Caddy reads `/etc/caddy/Caddyfile`, which loads every `sites/*.caddy`. A new site is a new file:

```caddyfile
# sites/shop.caddy
shop.example.com {
	import common
	reverse_proxy shop:8080
}
```

Apply without downtime (a broken config is rejected, the old one keeps running):

```sh
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
```

`import common` adds compression, security headers, CrowdSec, the access log and the rate
limit. Files not ending in
`.caddy` are ignored.

## Apps and networks

Each app gets its own internal network; only Caddy is on all of them, so apps cannot reach each
other or the internet:

```
internet ── caddy_egress ── caddy ──┬── caddy_app1 ── app1
                                    └── caddy_app2 ── app2
```

To add an app: add `caddy_app3` (`internal: true`) to `compose.yaml` and to the `caddy`
service, run `docker compose up -d caddy`, then join it from the app's own stack:

```yaml
services:
  web:
    image: example/app3
    networks:
      caddy_app3:
        aliases: [app3] # unique; "web" would collide across stacks
networks:
  caddy_app3:
    external: true
```

An app that needs outbound internet gets an extra network of its own.

## Certificates

Every hostname gets its own Let's Encrypt certificate, renewed automatically.

- **Option 1: DNS (acme-dns).** For wildcards (`*.example.net`) or hosts not reachable from the
  internet. Register once per domain (`curl -X POST https://auth.acme-dns.io/register`), CNAME
  `_acme-challenge.<domain>` to the returned `fulldomain`, put the credentials into `.env`,
  rename `sites/wildcard.caddy.example` to `.caddy`.
- **Option 2: Hosting (default).** The hostname points to this server. Nothing to configure.
  Not behind a proxying CDN (e.g. Cloudflare orange cloud); use option 1 there.

Use option 2 unless you need a wildcard. Both can be mixed.

## Plugins

- **Rate limit:** 1000 requests/min per IP for pages and API calls; static assets (CSS, JS,
  images, fonts) are not counted. Behind a CDN, key on `{client_ip}` with `trusted_proxies`.
- **CrowdSec:** runs next to Caddy, reads its access log and bans attacking IPs; Caddy blocks
  them on every site. The image brings the collections `crowdsecurity/caddy` (HTTP probing,
  crawling, brute force, CVE probes) and `crowdsecurity/whitelist-good-actors` and the log
  config ([`crowdsec/`](crowdsec/)). Also pulls the community blocklist.
  If CrowdSec is down, sites keep working without blocking. Check it:
  `docker compose exec crowdsec cscli metrics` and `cscli decisions list`.

## Limits

`compose.yaml` caps Caddy at 1 CPU, 512 MB (`GOMEMLIMIT` 460MiB, change both together), 256
processes, and rotates logs (3 × 10 MB). Plenty for small sites. Give your apps limits and log
rotation too.

## Non-root

The image runs as UID `10001`. New named volumes work as is. Otherwise:

- **Bind mounts:** `sudo chown 10001:10001` the host directories first.
- **From the stock `caddy` image:** chown the old volumes once:
  `docker run --rm -v caddy-data:/data -v caddy-config:/config alpine chown -R 10001:10001 /data /config`
- **Ports 80/443** work in Docker's default network mode. With `network_mode: host` or on
  Kubernetes, set `net.ipv4.ip_unprivileged_port_start=0`.

## Tags and updates

| Tag | Moves when |
|---|---|
| `latest` | Only when promoted by hand. Use this in compose. |
| `edge` | Every push to `main` (tested, not yet promoted) |
| `2.11.7` / `1.8.1` | Upstream version; newest build of it |
| `sha-<commit>` | Never |

To release: try `edge`, then run **Actions → promote** (image, tag `edge`), then
`docker compose pull && docker compose up -d` on the server. To roll back, promote the previous
digest shown in the run summary. Promote only non-breaking builds; a breaking one needs a
compose change first.

Verify an image: `gh attestation verify oci://ghcr.io/floriandeutsch89/caddy:latest --owner floriandeutsch89`

## Build and update

- Modules are pinned in `go.mod`/`go.sum` (`main.go` replaces xcaddy); Dependabot opens update
  PRs weekly. Manual: `go get github.com/caddyserver/caddy/v2@vX.Y.Z && go mod tidy`.
- New plugin: blank import in `main.go`, `go mod tidy`, add it to the CI smoke test and
  `test/Caddyfile`.
- CI lints, builds, smoke-tests, scans (govulncheck, Trivy) and publishes with SBOM and a
  signed attestation. Accepted findings: `.trivyignore.yaml`, `.govulncheck-ignore`.
- Local build: `docker build -t caddy:dev .`

Security: [SECURITY.md](SECURITY.md). License: MIT for this repo; Caddy and plugins as listed.
