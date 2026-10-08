# caddy

[![ci](https://github.com/floriandeutsch89/caddy-crowdsec/actions/workflows/ci.yml/badge.svg)](https://github.com/floriandeutsch89/caddy-crowdsec/actions/workflows/ci.yml)

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

You need Docker ≥ 28 with Compose ≥ 2.33, DNS records for each hostname pointing to the server, and ports
80/443 open.

```sh
git clone --depth 1 https://github.com/floriandeutsch89/caddy-crowdsec.git caddy-src
cp -r caddy-src/examples caddy && cd caddy && cp .env.example .env
sed -i "s/^CROWDSEC_API_KEY=.*/CROWDSEC_API_KEY=$(openssl rand -hex 32)/" .env
# set ACME_EMAIL in .env, edit config/sites/*.caddy and the apps in compose.yaml
docker network create --internal caddy_app1   # once per app, see below
docker network create --internal caddy_app2
docker compose up -d
docker compose logs -f caddy   # wait for "certificate obtained successfully"
```

| File | Purpose |
|---|---|
| `config/Caddyfile` | Global options, shared `(common)` snippet, `import sites/*.caddy` |
| `config/sites/*.caddy` | One file per site |
| `compose.yaml` | Caddy, CrowdSec, demo apps, one network per app, resource limits |

## Sites

`config/` is mounted as `/etc/caddy`. Caddy reads `Caddyfile`, which loads every `sites/*.caddy`.
A new site is a new file:

```caddyfile
# config/sites/shop.caddy
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
limit. Files not ending in `.caddy` are ignored. Files must be readable for UID 10001 (`0644`,
directories `0755`; the default with `git clone`).

HSTS is set without `includeSubDomains`, which would force HTTPS for a year on subdomains hosted
elsewhere. Where every subdomain is HTTPS, add it per site:
`header Strict-Transport-Security "max-age=31536000; includeSubDomains"`.

## Apps and networks

Each app gets its own internal network; only Caddy is on all of them, so apps cannot reach each
other or the internet. The networks belong to no stack (`external: true` everywhere), so Caddy
and every app stack start, stop and redeploy independently:

```
internet ── caddy_egress ── caddy ──┬── caddy_app1 ── app1
                                    └── caddy_app2 ── app2
```

To add an app:

1. `docker network create --internal caddy_app3`
2. Add `caddy_app3` to the `caddy` service and as `external: true` to `compose.yaml`, then
   `docker compose up -d caddy`.
3. Join it from the app's own stack:

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

4. Add `config/sites/app3.caddy` and reload Caddy.

An app that needs outbound internet gets an extra network of its own.

## Certificates

Every hostname gets its own Let's Encrypt certificate, renewed automatically.

- **Option 1: Hosting (default).** The hostname points to this server. Nothing to configure.
  Not behind a proxying CDN (e.g. Cloudflare orange cloud); use option 2 there.
- **Option 2: DNS (acme-dns).** For wildcards (`*.example.net`) or hosts not reachable from the
  internet. Register once per domain (`curl -X POST https://auth.acme-dns.io/register`), CNAME
  `_acme-challenge.<domain>` to the returned `fulldomain`, put the credentials into `.env`,
  rename `config/sites/wildcard.caddy.example` to `.caddy`.

Use option 1 unless you need a wildcard. Both can be mixed.

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

Caddy and CrowdSec have health checks (`docker compose ps` shows `healthy`). Caddy waits for
CrowdSec on start but does not depend on it: if CrowdSec stays unhealthy, Caddy starts anyway.

`caddy_egress` has IPv6 enabled so Caddy sees real IPv6 client addresses. Without it, Docker
relays IPv6 visitors through a proxy and they all share one address: one rate limit, one
CrowdSec ban for everybody. Check with
`docker compose exec caddy tail -n 50 /var/log/caddy/access.log | jq -r .request.remote_ip | sort | uniq -c`;
a `172.x.0.1`-style gateway address there means it does not work on your host.

## Backups

Two volumes hold state you do not want to lose: `caddy-data` (certificates, ACME account;
re-issuing everything can hit Let's Encrypt limits) and `crowdsec-config` (Central API
registration). Everything else is rebuilt on start. Back up both, e.g. nightly via cron:

```sh
for v in caddy-data crowdsec-config; do
  docker run --rm -v "caddy_$v:/v:ro" -v "$PWD/backup:/b" alpine \
    tar -czf "/b/$v-$(date +%F).tar.gz" -C /v .
done
```

The volume prefix is the compose project name (the directory, here `caddy`; see
`docker volume ls`). Restore into a stopped stack with `tar -xzf … -C /v` the same way. Never use
`docker compose down -v` unless you mean to delete them.

## Non-root

The stock `caddy` image runs as root. This one runs as UID `10001`, group `0`, without any
capabilities: a compromised Caddy, the one container facing the internet, is not root, and
without user namespaces container UIDs are host UIDs, so a high UID matches no real host user.
The state directories belong to group `0` with the owner's permissions, so the image also runs
under an arbitrary UID (OpenShift's `restricted-v2` always uses GID 0); there, listen on
8080/8443 or allow the sysctl below.

New named volumes work as is. Otherwise:

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

**Automatic updates:** Watchtower checks daily at 04:00 and recreates Caddy and CrowdSec
(label `com.centurylinklabs.watchtower.enable=true`) when their `:latest` changed, i.e. after a
promote. It reaches Docker only through a socket proxy that allows containers, images and
networks; everything else is blocked. Without Watchtower: `docker compose pull && docker compose up -d`.

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
