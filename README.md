# caddy

Caddy 2 with these plugins compiled in, published as a multi-arch image (amd64, arm64):

| Plugin | Modules | License |
|---|---|---|
| [hslatman/caddy-crowdsec-bouncer](https://github.com/hslatman/caddy-crowdsec-bouncer) (`/http`) | `crowdsec`, `http.handlers.crowdsec` | Apache-2.0 |
| [caddy-dns/acmedns](https://github.com/caddy-dns/acmedns) | `dns.providers.acmedns` | MIT |
| [mholt/caddy-ratelimit](https://github.com/mholt/caddy-ratelimit) | `http.handlers.rate_limit` | Apache-2.0 |

```
ghcr.io/floriandeutsch89/caddy:2.11.7   # also :2.11, :2, :latest, :sha-<commit>
```

Tags are rebuilt weekly (base image fixes), so they move. In production, pin the digest:
`ghcr.io/floriandeutsch89/caddy:2.11.7@sha256:…`.

## How it is built

- **`main.go` + `go.mod`/`go.sum`** replace xcaddy: every module version is pinned and
  checksummed (`go mod verify` in the build), builds are reproducible, and updates arrive
  as reviewable Dependabot PRs. This is the layout xcaddy generates internally.
- **Dockerfile:** the builder cross-compiles natively (`CGO_ENABLED=0`, no QEMU for the
  Go build); the runtime is the official `caddy:*-alpine` image with our binary. Both base
  images are pinned by digest.
- **Non-root:** runs as UID/GID `10001`, no file capabilities on the binary (works with
  `cap_drop: [ALL]`).

## CI (`.github/workflows/ci.yml`)

| Job | When | What |
|---|---|---|
| `lint` | always | hadolint, `go mod tidy -diff`, gofmt, `go vet` |
| `test` | always | build, smoke test (version == go.mod, all plugin modules, UID, `caddy validate` of `test/Caddyfile`, serving on :80 as non-root), Trivy (fails on fixable HIGH/CRITICAL) |
| `publish` | `main`, weekly, manual | multi-arch push, BuildKit SBOM + provenance, signed GitHub build attestation |

Actions are pinned by commit SHA; Dependabot updates Go modules, base images and actions weekly.

Verify an image:

```sh
gh attestation verify oci://ghcr.io/floriandeutsch89/caddy:latest --owner floriandeutsch89
```

## Usage

No site config is baked in. Mount one:

```yaml
services:
  caddy:
    image: ghcr.io/floriandeutsch89/caddy:2.11.7
    ports: ["80:80", "443:443", "443:443/udp"]
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy-data:/data
      - caddy-config:/config
    cap_drop: [ALL]
    read_only: true
    security_opt: ["no-new-privileges:true"]
```

or ship it with the app (e.g. when the Caddyfile pins CSP hashes of that app version):

```dockerfile
FROM ghcr.io/floriandeutsch89/caddy:2.11.7
COPY Caddyfile /etc/caddy/Caddyfile
```

Plugin directives are not in Caddy's default order; set it in the global options:

```caddyfile
{
	order crowdsec first
	order rate_limit after crowdsec
}
```

`test/Caddyfile` shows working syntax for all three plugins.

### Non-root caveats

- **Existing volumes** created by the stock (root) image are owned by root. Before switching,
  fix ownership once:
  `docker run --rm -v caddy-data:/data -v caddy-config:/config alpine chown -R 10001:10001 /data /config`
- **Ports 80/443** work because Docker sets `net.ipv4.ip_unprivileged_port_start=0` in the
  container (Docker ≥ 20.10). With `network_mode: host` or on Kubernetes, set that sysctl
  (pod `securityContext.sysctls`) or listen on high ports.

## Updating

- **Caddy or a plugin:** merge the Dependabot PR, or locally
  `go get github.com/caddyserver/caddy/v2@vX.Y.Z && go mod tidy`. Bump the runtime base
  (`caddy:X.Y.Z-alpine`) along with it; it only supplies the filesystem, but should match.
- **Add a plugin:** add a blank import to `main.go`, `go mod tidy`, extend the module list in
  the smoke test and `test/Caddyfile`.

## License

Build recipe: MIT (`LICENSE`). Shipped binaries: see the table above.
