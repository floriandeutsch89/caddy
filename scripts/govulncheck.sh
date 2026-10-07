#!/usr/bin/env bash
# govulncheck with an expiring allowlist (.govulncheck-ignore). Fails on any
# called (symbol-level) finding that is not allowlisted or whose entry expired.
set -euo pipefail
out=$(mktemp)
go run golang.org/x/vuln/cmd/govulncheck@v1.8.0 -format json "$@" ./... > "$out"
today=$(date -u +%F)
fail=0
for id in $(jq -r 'select(.finding) | select(.finding.trace[0].function) | .finding.osv' "$out" | sort -u); do
  expiry=$(awk -v id="$id" '$1 == id { print $2 }' .govulncheck-ignore)
  if [[ -n "$expiry" && ! "$today" > "$expiry" ]]; then
    echo "::warning::$id allowlisted until $expiry (.govulncheck-ignore)"
  else
    [[ -n "$expiry" ]] && echo "::error::$id allowlist entry expired on $expiry"
    echo "::error::$id: $(jq -r --arg id "$id" 'select(.osv.id == $id) | .osv.summary' "$out")"
    fail=1
  fi
done
exit "$fail"
