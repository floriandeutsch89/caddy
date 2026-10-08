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

Only `:edge` gets new builds; `:latest` is a promoted `:edge`. Older tags are not patched.

## What the build does

- Go modules pinned and checksummed (`go.sum`), base images and actions pinned by digest/SHA,
  Dependabot with a 7-day cooldown.
- Every PR and push to main: govulncheck, zizmor, and a `docker-security` job per image (hadolint,
  Trivy image scan failing on fixable HIGH/CRITICAL, Trivy Dockerfile misconfiguration scan).
  Accepted findings live in `.trivyignore.yaml` and `.govulncheck-ignore`, each with a reason
  and an expiry; an expired entry fails CI again.
- Every push and PR, docs included: gitleaks over the full history and a check that no `.env`,
  key or CrowdSec credentials file is tracked (`.github/workflows/secrets.yml`).
- Weekly re-scan with fresh vulnerability data; base image fixes arrive as Dependabot PRs.
- Images carry an SBOM, BuildKit provenance and a Sigstore-signed GitHub attestation
  (`gh attestation verify`, see README).
- Accepted: CVE-2026-44982 (AppSec ignores bodies of chunked/HTTP/2 requests; fixed in
  CrowdSec 1.7.8). Trivy and govulncheck flag the Caddy binary because the bouncer pulls in
  the crowdsec Go module v1.6.3, but the binary links only its API client, not the AppSec
  engine. The engine runs in the CrowdSec image (1.8.1, fixed). The bouncer does not yet
  compile against crowdsec >= 1.7.8; the exception goes once a bouncer release does.
- The CrowdSec image is upstream `crowdsecurity/crowdsec` plus config. Its CVE scan is reported
  but does not block: fixes come from upstream releases via Dependabot.

## Runtime protection (example stack)

- Caddy runs as UID 10001, group 0, without capabilities, read-only root filesystem.
- CrowdSec runs as root (upstream entrypoint) but without capabilities and with a read-only
  root filesystem, so it cannot bypass file permissions; it reads Caddy's log via its group.
- CrowdSec bans IPs from Caddy's access log and the community blocklist; Caddy blocks them.
- CrowdSec AppSec (WAF) checks each request against virtual patches for known CVEs and
  generic attack rules and answers 403. It sits after the rate limit, inspects bodies up to
  1 MiB, is reachable only from Caddy (`caddy_egress`, bouncer key) and fails open: if
  CrowdSec is down, sites stay up without WAF and IP blocking.
