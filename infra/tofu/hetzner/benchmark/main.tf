locals {
  resource_name = "keepling-${var.replacement_run_id}-benchmark"
  ownership_labels = {
    "managed-by"   = "opentofu"
    "keepling-run" = var.replacement_run_id
    purpose        = "host-replacement-benchmark"
  }
}

resource "hcloud_ssh_key" "benchmark" {
  name       = "${local.resource_name}-ssh"
  public_key = trimspace(var.ssh_public_key)
  labels     = local.ownership_labels
}

resource "hcloud_primary_ip" "benchmark" {
  name              = "${local.resource_name}-ipv4"
  type              = "ipv4"
  location          = var.location
  auto_delete       = false
  delete_protection = false
  labels            = local.ownership_labels
}

resource "hcloud_firewall" "benchmark" {
  name   = "${local.resource_name}-firewall"
  labels = local.ownership_labels

  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "22"
    source_ips  = [var.admin_source_cidr]
    description = "Exact benchmark operator source"
  }

  rule {
    direction       = "out"
    protocol        = "tcp"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "Bootstrap and benchmark egress"
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
    description     = "Bounded diagnostics"
  }
}

resource "hcloud_network" "benchmark" {
  name     = "${local.resource_name}-network"
  ip_range = "10.78.0.0/16"
  labels   = local.ownership_labels
}

resource "hcloud_network_subnet" "benchmark" {
  network_id   = hcloud_network.benchmark.id
  type         = "cloud"
  network_zone = "eu-central"
  ip_range     = "10.78.1.0/24"
}

resource "hcloud_server" "benchmark" {
  name        = "${local.resource_name}-host"
  location    = var.location
  server_type = var.server_type
  image       = var.server_image_id
  ssh_keys    = [hcloud_ssh_key.benchmark.id]
  labels      = local.ownership_labels
  user_data   = file("${path.module}/cloud-init.yml")

  backups            = false
  delete_protection  = false
  rebuild_protection = false

  public_net {
    ipv4         = hcloud_primary_ip.benchmark.id
    ipv4_enabled = true
    ipv6_enabled = false
  }
}

resource "hcloud_firewall_attachment" "benchmark" {
  firewall_id = hcloud_firewall.benchmark.id
  server_ids  = [hcloud_server.benchmark.id]
}

resource "hcloud_server_network" "benchmark" {
  server_id  = hcloud_server.benchmark.id
  network_id = hcloud_network.benchmark.id
  depends_on = [hcloud_network_subnet.benchmark]
}

resource "hcloud_volume" "benchmark" {
  name      = "${local.resource_name}-volume"
  location  = var.location
  size      = var.data_volume_size_gb
  format    = "ext4"
  automount = false
  labels    = local.ownership_labels
}

resource "hcloud_volume_attachment" "benchmark" {
  volume_id = hcloud_volume.benchmark.id
  server_id = hcloud_server.benchmark.id
  automount = false
}
