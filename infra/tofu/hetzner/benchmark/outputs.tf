output "teardown_inventory" {
  value = {
    server_id     = hcloud_server.benchmark.id
    volume_id     = hcloud_volume.benchmark.id
    primary_ip_id = hcloud_primary_ip.benchmark.id
    network_id    = hcloud_network.benchmark.id
    firewall_id   = hcloud_firewall.benchmark.id
    ssh_key_id    = hcloud_ssh_key.benchmark.id
    ipv4_address  = hcloud_primary_ip.benchmark.ip_address
    labels        = local.ownership_labels
  }
  sensitive = true
}
