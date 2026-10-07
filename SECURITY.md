# Security policy

## Reporting a vulnerability

Please report privately via **Security → Report a vulnerability** on this repository
(GitHub private vulnerability reporting), not in a public issue.

Vulnerabilities in Caddy itself or a plugin belong upstream:
[Caddy](https://github.com/caddyserver/caddy/security),
[caddy-crowdsec-bouncer](https://github.com/hslatman/caddy-crowdsec-bouncer/security),
[caddy-dns/acmedns](https://github.com/caddy-dns/acmedns),
[caddy-ratelimit](https://github.com/mholt/caddy-ratelimit). Once fixed there, the fix
lands here via Dependabot and the next build.

## Supported versions

Only the latest image (`:latest`, `:2`, and the newest `:2.x.y`) gets rebuilds.

## What the build does

- Go modules pinned and checksummed (`go.sum`), base images and actions pinned by digest/SHA,
  Dependabot with a 7-day cooldown.
- Every build: govulncheck, Trivy (fails on fixable HIGH/CRITICAL), zizmor for workflows.
  Accepted findings live in `.trivyignore.yaml` and `.govulncheck-ignore`, each with a reason
  and an expiry; an expired entry fails CI again.
- Weekly rebuild for base image fixes; images carry an SBOM, BuildKit provenance and a
  Sigstore-signed GitHub attestation (`gh attestation verify`, see README).
