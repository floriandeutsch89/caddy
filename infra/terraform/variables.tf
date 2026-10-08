variable "hcloud_token" {
  description = "Hetzner Cloud API token (read+write). Pass via TF_VAR_hcloud_token, never commit it."
  type        = string
  sensitive   = true
}

variable "server_name" {
  description = "Server name in the Hetzner console; also prefixes the firewall and SSH key."
  type        = string
  default     = "caddy"
}

variable "server_type" {
  description = "Hetzner server type. The images are amd64 and arm64, so ARM types (cax11) work too. Check `hcloud server-type list`."
  type        = string
  default     = "cx23"
}

variable "location" {
  description = "Hetzner location, e.g. fsn1, nbg1 (Germany), hel1."
  type        = string
  default     = "fsn1"
}

variable "ssh_public_key" {
  description = "SSH public key for root (content of ~/.ssh/id_ed25519.pub)."
  type        = string
}

variable "ssh_allowed_cidrs" {
  description = "Sources allowed to reach SSH. Narrow to your own IP if it is static, e.g. [\"203.0.113.5/32\"]."
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]
}

variable "backups" {
  description = "Hetzner daily backups of the whole server (7 kept, +20% of the server price). Covers certificates and CrowdSec state off the disk."
  type        = bool
  default     = true
}
