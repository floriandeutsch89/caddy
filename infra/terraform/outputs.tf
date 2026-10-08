output "ipv4" {
  description = "Public IPv4: A records of your sites."
  value       = hcloud_server.host.ipv4_address
}

output "ipv6" {
  description = "Public IPv6: AAAA records of your sites."
  value       = hcloud_server.host.ipv6_address
}

output "ssh" {
  description = "Log in, then follow README \"Server on Hetzner\"."
  value       = "ssh root@${hcloud_server.host.ipv4_address}"
}
