#!/usr/bin/env bash
# Runs the examples/ stack with the images under test and checks routing,
# network isolation and CrowdSec end to end. Local certs instead of ACME.
set -euo pipefail
E2E_IMAGE=${E2E_IMAGE:-caddy:test}
E2E_CROWDSEC_IMAGE=${E2E_CROWDSEC_IMAGE:-crowdsec:test}
dir=$(mktemp -d)
cp -r examples/. "$dir"
cd "$dir"
rm config/sites/*.caddy
# Local CA instead of ACME; non-root cannot install it into a trust store anyway.
# shellcheck disable=SC2016 # literal Caddyfile placeholder
sed -i 's/^\temail {\$ACME_EMAIL}$/&\n\tskip_install_trust/' config/Caddyfile
grep -q skip_install_trust config/Caddyfile
for app in app1 app2; do
  printf '%s.example.test {\n\ttls internal\n\timport common\n\treverse_proxy %s:80\n}\n' "$app" "$app" > "config/sites/$app.caddy"
done
printf 'ACME_EMAIL=ci@example.com\nCROWDSEC_API_KEY=%s\n' "$(openssl rand -hex 32)" > .env
# pull_policy never: fail instead of silently testing a published image.
# DISABLE_ONLINE_API: no Central API registration for every CI run.
printf 'services:\n  caddy:\n    image: %s\n    pull_policy: never\n  crowdsec:\n    image: %s\n    pull_policy: never\n    environment:\n      DISABLE_ONLINE_API: "true"\n' \
  "$E2E_IMAGE" "$E2E_CROWDSEC_IMAGE" > compose.ci.yaml
chmod -R a+rX .
dc() { docker compose -f compose.yaml -f compose.ci.yaml "$@"; }
cleanup() {
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "== diagnostics"
    curl -skv --max-time 5 --resolve app1.example.test:443:127.0.0.1 https://app1.example.test/ -o /dev/null 2>&1 | tail -15 || true
    docker inspect "$(dc ps -q caddy)" --format '{{json .NetworkSettings.Ports}} {{range $n, $e := .NetworkSettings.Networks}}{{$n}} gw={{$e.Gateway}} prio={{$e.GwPriority}}; {{end}}' || true
    echo "== crowdsec metrics"; dc exec -T crowdsec cscli metrics show acquisition parsers 2>&1 | tail -30 || true
    echo "== access.log (last 3)"; dc exec -T caddy tail -n 3 /var/log/caddy/access.log 2>&1 || true
    for svc in caddy crowdsec app1 socket-proxy watchtower; do echo "== logs: $svc"; dc logs --no-color "$svc" | tail -60; done
  fi
  dc down -v >/dev/null 2>&1 || true
  docker network rm caddy_app1 caddy_app2 >/dev/null 2>&1 || true
  exit "$rc"
}
trap cleanup EXIT

# External app networks, created like on a server (README).
for net in caddy_app1 caddy_app2; do docker network create --internal "$net" >/dev/null; done
dc up -d --quiet-pull
# .example.test, not .localhost: curl and Caddy both special-case localhost names.
get() { curl -sk -o /dev/null -w '%{http_code}' --resolve "$1.example.test:443:127.0.0.1" "https://$1.example.test/"; }
# Re-runs the request on every try; `test "$(get x)" = 200` as a wait_for argument
# would expand once and compare a stale status forever.
status_is() { [ "$(get "$1")" = "$2" ]; }
wait_for() { # wait_for <seconds> <description> <command...>
  local t=$1 what=$2; shift 2
  for _ in $(seq "$t"); do "$@" && return 0; sleep 1; done
  echo "::error::timed out: $what"; return 1
}

echo "== routing"
wait_for 60 "app1 via Caddy" status_is app1 200
test "$(get app2)" = 200

echo "== health checks and IPv6"
healthy() { [ "$(docker inspect -f '{{.State.Health.Status}}' "$(dc ps -q "$1")")" = healthy ]; }
wait_for 120 "caddy healthy" healthy caddy
wait_for 120 "crowdsec healthy" healthy crowdsec
[ "$(docker network inspect caddy_egress -f '{{.EnableIPv6}}')" = true ] || { echo "::error::caddy_egress without IPv6"; exit 1; }

echo "== isolation"
if docker run --rm --network caddy_app1 busybox wget -qT 3 -O /dev/null http://app2 2>/dev/null; then
  echo "::error::app network caddy_app1 reaches app2"; exit 1; fi
if docker run --rm --network caddy_app1 busybox wget -qT 3 -O /dev/null http://1.1.1.1 2>/dev/null; then
  echo "::error::app network caddy_app1 reaches the internet"; exit 1; fi

echo "== socket proxy and watchtower"
proxy_net=$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' "$(dc ps -q socket-proxy)")
proxy() { docker run --rm --network "$proxy_net" curlimages/curl -s -o /dev/null -w '%{http_code}' "http://socket-proxy:2375$1"; }
proxy_up() { [ "$(proxy /_ping)" = 200 ]; }
wait_for 30 "socket proxy answers" proxy_up
[ "$(proxy /containers/json)" = 200 ] || { echo "::error::proxy blocks container listing"; exit 1; }
for denied in /volumes /secrets /exec/x/json /swarm; do
  code=$(proxy "$denied")
  [ "$code" = 403 ] || { echo "::error::proxy allows $denied ($code)"; exit 1; }
done
# nickfedor fork: "Next scheduled run" (containrrr said "Scheduling first run").
watchtower_scheduled() { dc logs watchtower 2>&1 | grep -q -E 'Next scheduled run|Scheduling first run'; }
wait_for 30 "watchtower scheduled" watchtower_scheduled
[ "$(docker inspect -f '{{.State.Running}}' "$(dc ps -q watchtower)")" = true ] || { echo "::error::watchtower not running"; exit 1; }

echo "== crowdsec reads the access log and the bouncer is registered"
# CrowdSec tails from the end of the file once its hub setup is done, so lines
# written earlier (the routing checks) are never read: keep sending requests.
crowdsec_reads_log() {
  get app1 >/dev/null
  dc exec -T crowdsec cscli metrics show acquisition -o json 2>/dev/null | grep -q 'access.log'
}
wait_for 120 "acquisition of access.log" crowdsec_reads_log
wait_for 90 "bouncer pull" sh -c "docker compose -f compose.yaml -f compose.ci.yaml exec -T crowdsec cscli bouncers list -o json | jq -e '.[] | select(.name == \"caddy\") | (.last_pull // \"\") | tostring | test(\"^20\")' >/dev/null"

echo "== a ban blocks the client"
ip=$(dc exec -T caddy tail -n 1 /var/log/caddy/access.log | jq -r .request.remote_ip)
echo "client ip as seen by Caddy: $ip"
dc exec -T crowdsec cscli decisions add --ip "$ip" --duration 5m --reason e2e >/dev/null
wait_for 90 "403 for banned ip" status_is app1 403
dc exec -T crowdsec cscli decisions delete --ip "$ip" >/dev/null
wait_for 90 "200 after unban" status_is app1 200
echo "e2e ok"
