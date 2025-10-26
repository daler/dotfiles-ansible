terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
  }
}

# Variables for Hetzner configuration
variable "hetzner_token" {
  type        = string
  description = "Hetzner Cloud API token (can be set via TF_VAR_hetzner_token env var)"
  sensitive   = true
}

variable "hetzner_server_type" {
  type        = string
  description = "Hetzner server type (e.g., cx21, cpx31, ccx33)"
}

variable "hetzner_location" {
  type        = string
  description = "Hetzner datacenter location (nbg1, fsn1, hel1, ash, hil)"
}

variable "hcloud_ssh_key_file" {
  type        = string
  description = "SSH key to set up server login"
}

variable "hetzner_server_name" {
  type        = string
  default     = "devbox"
  description = "Name for the Hetzner server"
}

# Provider configuration
provider "hcloud" {
  token = var.hetzner_token
}

# SSH Key
resource "hcloud_ssh_key" "default" {
  name       = "devbox-key"
  public_key = file("${var.hcloud_ssh_key_file}.pub")
}

# Array of volumes with this label.
data "hcloud_volumes" "existing" {
  with_selector = "name=devboxdata"
}

# Keep track of volumes we've identified. Lets us conditionally attach without
# errors later.
locals {
  volume_id = length(data.hcloud_volumes.existing.volumes) > 0 ? data.hcloud_volumes.existing.volumes[0].id : null
}

resource "hcloud_volume_attachment" "main" {

  # This is the terraform mechanism for conditionally creating this resource,
  # here, depending on if the length of detected volumes is exactly 1.
  count = local.volume_id != null ? 1 : 0
  volume_id = local.volume_id
  server_id = hcloud_server.devbox.id
  automount = true
}

# Firewall for SSH access
resource "hcloud_firewall" "devbox" {
  name = "devbox-firewall"

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "22"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }
}

# Create the server
resource "hcloud_server" "devbox" {
  name        = var.hetzner_server_name
  server_type = var.hetzner_server_type
  location    = var.hetzner_location
  image       = "ubuntu-24.04"

  ssh_keys = [
    hcloud_ssh_key.default.id
  ]

  firewall_ids = [
    hcloud_firewall.devbox.id
  ]

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  labels = {
    type = "devbox"
  }
}


# Outputs
output "hetzner_server_ip" {
  value       = hcloud_server.devbox.ipv4_address
  description = "Public IP address of the Hetzner server"
}

output "hetzner_server_id" {
  value       = hcloud_server.devbox.id
  description = "ID of the Hetzner server"
}


# Create hosts file for Ansible
resource "local_file" "hosts_hetzner" {
  content         = "[hetzner]\n${hcloud_server.devbox.ipv4_address}\n"
  file_permission = "0600"
  filename        = "${path.module}/hosts"
}

# vim: ft=hcl
