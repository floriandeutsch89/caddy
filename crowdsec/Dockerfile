# CrowdSec for the Caddy stack: collections and log acquisition baked in, so
# compose needs no CrowdSec config beyond the bouncer key.
FROM crowdsecurity/crowdsec:v1.8.1@sha256:0f2523fa61ef507f15d953045cface490cc880670c62f2755ced17524107f71a
# caddy: log parser + HTTP scenarios (probing, crawling, brute force, CVE probes).
# whitelist-good-actors: never ban well-known bots, CDNs and DNS resolvers.
# The entrypoint installs and upgrades these on every start.
ENV COLLECTIONS="crowdsecurity/caddy crowdsecurity/whitelist-good-actors"
# The entrypoint copies /staging/etc/crowdsec into the /etc/crowdsec volume on
# first start only (rsync --ignore-existing): later changes need a manual copy.
COPY acquis.d/caddy.yaml /staging/etc/crowdsec/acquis.d/caddy.yaml
LABEL org.opencontainers.image.title="crowdsec" \
      org.opencontainers.image.description="CrowdSec with Caddy collections and log acquisition for ghcr.io/floriandeutsch89/caddy" \
      org.opencontainers.image.source="https://github.com/floriandeutsch89/caddy" \
      org.opencontainers.image.licenses="MIT"
