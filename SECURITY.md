# Security policy

## Reporting vulnerabilities

This repository only builds and publishes the image; it contains no code of its own beyond the
build recipe. Report vulnerabilities upstream:
[Caddy](https://github.com/caddyserver/caddy/security),
[caddy-crowdsec-bouncer](https://github.com/hslatman/caddy-crowdsec-bouncer/security),
[caddy-dns/acmedns](https://github.com/caddy-dns/acmedns),
[caddy-ratelimit](https://github.com/mholt/caddy-ratelimit). Once fixed there, the fix lands
here via Dependabot and the next build.

## Supported versions

Only the latest image (`:latest`, `:2`, and the newest `:2.x.y`) gets rebuilds.

## What the build does

- Go modules pinned and checksummed (`go.sum`), base images and actions pinned by digest/SHA,
  Dependabot with a 7-day cooldown.
- Every build: govulncheck, Trivy (fails on fixable HIGH/CRITICAL), zizmor for workflows.
  Accepted findings live in `.trivyignore.yaml` and `.govulncheck-ignore`, each with a reason
  and an expiry; an expired entry fails CI again.
- Weekly re-scan with fresh vulnerability data; base image fixes arrive as Dependabot PRs.
- Images carry an SBOM, BuildKit provenance and a Sigstore-signed GitHub attestation
  (`gh attestation verify`, see README).
