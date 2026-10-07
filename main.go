// Caddy entry point with plugins linked in. This is what xcaddy generates; kept
// as source so go.mod/go.sum pin and checksum every module and Dependabot can bump them.
package main

import (
	caddycmd "github.com/caddyserver/caddy/v2/cmd"

	_ "github.com/caddyserver/caddy/v2/modules/standard"

	_ "github.com/caddy-dns/acmedns"
	_ "github.com/hslatman/caddy-crowdsec-bouncer/http"
	_ "github.com/mholt/caddy-ratelimit"
)

func main() {
	caddycmd.Main()
}
