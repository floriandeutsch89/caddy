# CrowdSec for the Caddy stack: collections and log acquisition baked in, so
# compose needs no CrowdSec config beyond the bouncer key.
FROM crowdsecurity/crowdsec:v1.8.1@sha256:0f2523fa61ef507f15d953045cface490cc880670c62f2755ced17524107f71a
# caddy: log parser + HTTP scenarios (probing, crawling, brute force, CVE probes).
# whitelist-good-actors: never ban well-known bots, CDNs and DNS resolvers.
# appsec-*: WAF rules (known CVEs, generic attacks) for the AppSec component.
# The entrypoint installs and upgrades these on every start.
ENV COLLECTIONS="crowdsecurity/caddy crowdsecurity/whitelist-good-actors crowdsecurity/appsec-virtual-patching crowdsecurity/appsec-generic-rules"
# The entrypoint copies /staging/etc/crowdsec into the /etc/crowdsec volume on
# first start only (rsync --ignore-existing): later changes need a manual copy.
COPY acquis.d/ /staging/etc/crowdsec/acquis.d/
# CrowdSec usually mounts the shared log volume before Caddy does, so Docker seeds
# it from this image: give it the owner Caddy (UID 10001) needs to write.
RUN mkdir -p /var/log/caddy && chown 10001:0 /var/log/caddy && chmod 0750 /var/log/caddy
LABEL org.opencontainers.image.title="crowdsec" \
      org.opencontainers.image.description="CrowdSec with Caddy collections and log acquisition for ghcr.io/floriandeutsch89/caddy" \
      org.opencontainers.image.source="https://github.com/floriandeutsch89/caddy-crowdsec" \
      org.opencontainers.image.licenses="MIT"
