mock_provider "hcloud" {
  mock_resource "hcloud_ssh_key" { defaults = { id = "801" } }
  mock_resource "hcloud_primary_ip" { defaults = { id = "802", ip_address = "192.0.2.20" } }
  mock_resource "hcloud_server" { defaults = { id = "803" } }
  mock_resource "hcloud_volume" { defaults = { id = "804" } }
  mock_resource "hcloud_network" { defaults = { id = "805" } }
  mock_resource "hcloud_firewall" { defaults = { id = "806" } }
}

variables {
  location            = "nbg1"
  server_type         = "cx33"
  server_image_id     = "123456789"
  ssh_public_key      = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG5vdC1hLXJlYWwta2V5LWJ1dC12YWxpZC1zaGFwZQ== test"
  admin_source_cidr   = "192.0.2.1/32"
  replacement_run_id  = "test-run-0001"
  data_volume_size_gb = 160
}

run "benchmark_graph_is_exactly_owned" {
  command = apply

  assert {
    condition     = hcloud_server.benchmark.server_type == "cx33" && hcloud_server.benchmark.location == "nbg1"
    error_message = "benchmark server must match the approved catalog selection"
  }

  assert {
    condition     = one(hcloud_server.benchmark.public_net).ipv4 == hcloud_primary_ip.benchmark.id && !one(hcloud_server.benchmark.public_net).ipv6_enabled
    error_message = "benchmark must own exactly one explicit IPv4 and no IPv6"
  }

  assert {
    condition     = hcloud_volume.benchmark.size == 160 && !hcloud_volume_attachment.benchmark.automount
    error_message = "benchmark must own the exact unmounted 160 GB volume"
  }

  assert {
    condition     = strcontains(hcloud_server.benchmark.user_data, "mountpoint -q /srv/keepling-benchmark") && strcontains(hcloud_server.benchmark.user_data, "touch /run/keepling-benchmark-ready")
    error_message = "readiness must be published only after the disposable volume is mounted"
  }

  assert {
    condition     = hcloud_ssh_key.benchmark.labels["keepling-run"] == "test-run-0001" && hcloud_primary_ip.benchmark.labels["keepling-run"] == "test-run-0001"
    error_message = "disposable identities must retain exact run ownership"
  }
}

run "global_ssh_is_refused" {
  command = plan
  variables { admin_source_cidr = "0.0.0.0/0" }
  expect_failures = [var.admin_source_cidr]
}

run "wrong_size_is_refused" {
  command = plan
  variables { data_volume_size_gb = 80 }
  expect_failures = [var.data_volume_size_gb]
}
