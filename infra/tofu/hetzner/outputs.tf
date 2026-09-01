output "replacement_ssh_key_identity" {
  description = "Exact provider identity retained in the private run workspace for read-before-delete cleanup."
  value = {
    id   = hcloud_ssh_key.replacement.id
    name = hcloud_ssh_key.replacement.name
  }
  sensitive = true
}

output "candidate_identity" {
  description = "Bounded candidate identity consumed by the credentialed proof runner."
  value = {
    id           = hcloud_server.replacement.id
    name         = hcloud_server.replacement.name
    ipv4_address = hcloud_server.replacement.ipv4_address
    network_id   = hcloud_network.replacement.id
    volume_id    = hcloud_volume.replacement.id
  }
  sensitive = true
}
