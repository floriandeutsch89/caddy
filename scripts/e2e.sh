#!/usr/bin/env bash
# Runs the examples/ stack with the images under test and checks routing,
# network isolation and CrowdSec end to end. Local certs instead of ACME.
set -euo pipefail
E2E_IMAGE=${E2E_IMAGE:-caddy:test}
E2E_CROWDSEC_IMAGE=${E2E_CROWDSEC_IMAGE:-crowdsec:test}
dir=$(mktemp -d)
cp -r examples/. "$dir"
cd "$dir"
rm sites/*.caddy
# Local CA instead of ACME; non-root cannot install it into a trust store anyway.
# shellcheck disable=SC2016 # literal Caddyfile placeholder
sed -i 's/^\temail {\$ACME_EMAIL}$/&\n\tskip_install_trust/' Caddyfile
grep -q skip_install_trust Caddyfile
for app in app1 app2; do
  printf '%s.example.test {\n\ttls internal\n\timport common\n\treverse_proxy %s:80\n}\n' "$app" "$app" > "sites/$app.caddy"
done
printf 'ACME_EMAIL=ci@example.com\nCROWDSEC_API_KEY=%s\n' "$(openssl rand -hex 32)" > .env
# pull_policy never: fail instead of silently testing a published image.
printf 'services:\n  caddy:\n    image: %s\n    pull_policy: never\n  crowdsec:\n    image: %s\n    pull_policy: never\n' \
  "$E2E_IMAGE" "$E2E_CROWDSEC_IMAGE" > compose.ci.yaml
chmod -R a+rX .
dc() { docker compose -f compose.yaml -f compose.ci.yaml "$@"; }
cleanup() {
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "== diagnostics"
    curl -skv --max-time 5 --resolve app1.example.test:443:127.0.0.1 https://app1.example.test/ -o /dev/null 2>&1 | tail -15 || true
    docker inspect "$(dc ps -q caddy)" --format '{{json .NetworkSettings.Ports}} {{range $n, $e := .NetworkSettings.Networks}}{{$n}} gw={{$e.Gateway}} prio={{$e.GwPriority}}; {{end}}' || true
    for svc in caddy crowdsec app1; do echo "== logs: $svc"; dc logs --no-color "$svc" | tail -60; done
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

echo "== isolation"
if docker run --rm --network caddy_app1 busybox wget -qT 3 -O /dev/null http://app2 2>/dev/null; then
  echo "::error::app network caddy_app1 reaches app2"; exit 1; fi
if docker run --rm --network caddy_app1 busybox wget -qT 3 -O /dev/null http://1.1.1.1 2>/dev/null; then
  echo "::error::app network caddy_app1 reaches the internet"; exit 1; fi

echo "== crowdsec reads the access log and the bouncer is registered"
wait_for 120 "acquisition of access.log" sh -c "docker compose -f compose.yaml -f compose.ci.yaml exec -T crowdsec cscli metrics 2>/dev/null | grep -q 'access.log'"
wait_for 90 "bouncer pull" sh -c "docker compose -f compose.yaml -f compose.ci.yaml exec -T crowdsec cscli bouncers list -o json | jq -e '.[] | select(.name == \"caddy\") | (.last_pull // \"\") | tostring | test(\"^20\")' >/dev/null"

echo "== a ban blocks the client"
ip=$(dc exec -T caddy tail -n 1 /var/log/caddy/access.log | jq -r .request.remote_ip)
echo "client ip as seen by Caddy: $ip"
dc exec -T crowdsec cscli decisions add --ip "$ip" --duration 5m --reason e2e >/dev/null
wait_for 90 "403 for banned ip" status_is app1 403
dc exec -T crowdsec cscli decisions delete --ip "$ip" >/dev/null
wait_for 90 "200 after unban" status_is app1 200
echo "e2e ok"
