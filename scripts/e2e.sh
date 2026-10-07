#!/usr/bin/env bash
# Runs the examples/ stack with the image under test (IMAGE) and checks routing,
# network isolation and CrowdSec end to end. Local certs instead of ACME.
set -euo pipefail
IMAGE=${IMAGE:-caddy:test}
dir=$(mktemp -d)
cp -r examples/. "$dir"
cd "$dir"
rm sites/*.caddy
for app in app1 app2; do
  printf '%s.localhost {\n\ttls internal\n\timport common\n\treverse_proxy %s:80\n}\n' "$app" "$app" > "sites/$app.caddy"
done
printf 'ACME_EMAIL=ci@example.com\nCROWDSEC_API_KEY=%s\n' "$(openssl rand -hex 32)" > .env
printf 'services:\n  caddy:\n    image: %s\n' "$IMAGE" > compose.ci.yaml
chmod -R a+rX .
dc() { docker compose -f compose.yaml -f compose.ci.yaml "$@"; }
cleanup() {
  local rc=$?
  if [ "$rc" -ne 0 ]; then dc logs --no-color | tail -200; fi
  dc down -v >/dev/null 2>&1 || true
  exit "$rc"
}
trap cleanup EXIT

dc up -d --quiet-pull
get() { curl -sk -o /dev/null -w '%{http_code}' --resolve "$1.localhost:443:127.0.0.1" "https://$1.localhost/"; }
wait_for() { # wait_for <seconds> <description> <command...>
  local t=$1 what=$2; shift 2
  for _ in $(seq "$t"); do "$@" && return 0; sleep 1; done
  echo "::error::timed out: $what"; return 1
}

echo "== routing"
wait_for 60 "app1 via Caddy" test "$(get app1)" = 200
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
wait_for 90 "403 for banned ip" test "$(get app1)" = 403
dc exec -T crowdsec cscli decisions delete --ip "$ip" >/dev/null
wait_for 90 "200 after unban" test "$(get app1)" = 200
echo "e2e ok"
