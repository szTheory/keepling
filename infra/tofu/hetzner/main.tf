locals {
  resource_name = "keepling-${var.replacement_run_id}"
  ownership_labels = {
    "managed-by"   = "opentofu"
    "keepling-run" = var.replacement_run_id
    purpose        = "host-replacement"
  }
}

resource "hcloud_ssh_key" "replacement" {
  name       = "${local.resource_name}-ssh"
  public_key = trimspace(var.ssh_public_key)
  labels     = local.ownership_labels
}

resource "hcloud_primary_ip" "replacement" {
  name              = "${local.resource_name}-ipv4"
  type              = "ipv4"
  location          = var.location
  auto_delete       = false
  delete_protection = false
  labels            = local.ownership_labels
}

resource "hcloud_firewall" "replacement" {
  name   = "${local.resource_name}-edge"
  labels = local.ownership_labels

  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "80"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "Public HTTP for Caddy redirect/proof"
  }

  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "443"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "Public HTTPS terminates at Caddy"
  }

  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "22"
    source_ips  = sort(tolist(var.admin_source_cidrs))
    description = "Bounded operator SSH"
  }

  rule {
    direction       = "out"
    protocol        = "tcp"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "Package, OCI, backup, and API egress"
  }

  rule {
    direction       = "out"
    protocol        = "udp"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "DNS and time egress"
  }

  rule {
    direction       = "out"
    protocol        = "icmp"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "Network diagnostics"
  }
}

resource "hcloud_network" "replacement" {
  name     = "${local.resource_name}-private"
  ip_range = var.network_cidr
  labels   = local.ownership_labels
}

resource "hcloud_network_subnet" "replacement" {
  network_id   = hcloud_network.replacement.id
  type         = "cloud"
  network_zone = "eu-central"
  ip_range     = var.subnet_cidr

  lifecycle {
    precondition {
      condition     = cidrcontains(var.network_cidr, cidrhost(var.subnet_cidr, 1))
      error_message = "subnet_cidr must be contained by network_cidr."
    }
  }
}

resource "hcloud_server" "replacement" {
  name        = "${local.resource_name}-host"
  location    = var.location
  server_type = var.server_type
  image       = var.server_image_id
  ssh_keys    = [hcloud_ssh_key.replacement.id]
  labels      = local.ownership_labels
  user_data = templatefile("${path.module}/cloud-init.yml", {
    tested_oci_digest = var.tested_oci_digest
    architecture      = var.target_architecture
  })

  backups            = false
  delete_protection  = false
  rebuild_protection = false

  public_net {
    ipv4         = hcloud_primary_ip.replacement.id
    ipv4_enabled = true
    ipv6_enabled = false
  }

  network {
    subnet_id = hcloud_network_subnet.replacement.id
    alias_ips = []
  }

  depends_on = [hcloud_network_subnet.replacement]

  lifecycle {
    precondition {
      condition     = var.target_architecture == "x86_64"
      error_message = "selected server and tested artifact must use x86_64."
    }
  }
}

resource "hcloud_firewall_attachment" "replacement" {
  firewall_id = hcloud_firewall.replacement.id
  server_ids  = [hcloud_server.replacement.id]
}

resource "hcloud_volume" "replacement" {
  name      = "${local.resource_name}-data"
  location  = var.location
  size      = var.data_volume_size_gb
  format    = "ext4"
  automount = false
  labels    = local.ownership_labels
}

resource "hcloud_volume_attachment" "replacement" {
  volume_id = hcloud_volume.replacement.id
  server_id = hcloud_server.replacement.id
  automount = false
}
