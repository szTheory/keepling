mock_provider "hcloud" {
  mock_resource "hcloud_ssh_key" {
    defaults = {
      id = "701"
    }
  }

  mock_resource "hcloud_server" {
    defaults = {
      id           = "702"
      ipv4_address = "192.0.2.10"
    }
  }

  mock_resource "hcloud_primary_ip" {
    defaults = {
      id         = "706"
      ip_address = "192.0.2.10"
    }
  }

  mock_resource "hcloud_firewall" {
    defaults = {
      id = "705"
    }
  }

  mock_resource "hcloud_network" {
    defaults = {
      id = "703"
    }
  }

  mock_resource "hcloud_volume" {
    defaults = {
      id = "704"
    }
  }
}

variables {
  location            = "nbg1"
  server_type         = "cpx32"
  server_image_id     = "123456789"
  tested_oci_digest   = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  ssh_public_key      = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG5vdC1hLXJlYWwta2V5LWJ1dC12YWxpZC1zaGFwZQ== keepling-test"
  replacement_run_id  = "test-run-0001"
  admin_source_cidrs  = ["192.0.2.0/24"]
  data_volume_size_gb = 160
}

run "replacement_graph_is_owned_and_bounded" {
  command = apply

  assert {
    condition     = hcloud_server.replacement.location == "nbg1" && hcloud_server.replacement.server_type == "cpx32"
    error_message = "the server must use the selected location and x86 server type"
  }

  assert {
    condition     = length(hcloud_server.replacement.ssh_keys) == 1 && tonumber(one(hcloud_server.replacement.ssh_keys)) == tonumber(hcloud_ssh_key.replacement.id)
    error_message = "the candidate must reference only the exact owned SSH key resource"
  }

  assert {
    condition     = one(hcloud_server.replacement.public_net).ipv4 == hcloud_primary_ip.replacement.id && !one(hcloud_server.replacement.public_net).ipv6_enabled
    error_message = "the candidate must own one explicit IPv4 and disable IPv6"
  }

  assert {
    condition     = hcloud_ssh_key.replacement.labels["keepling-run"] == "test-run-0001" && hcloud_ssh_key.replacement.labels["managed-by"] == "opentofu"
    error_message = "the SSH key must carry exact run-ownership labels"
  }

  assert {
    condition = length([
      for rule in hcloud_firewall.replacement.rule : rule
      if rule.direction == "in"
      ]) == 3 && length([
      for rule in hcloud_firewall.replacement.rule : rule
      if rule.direction == "in" && contains(["80", "443", "22"], rule.port)
    ]) == 3
    error_message = "only the declared edge and bounded admin ingress may be exposed"
  }

  assert {
    condition     = hcloud_server_network.replacement.network_id == tonumber(hcloud_network.replacement.id)
    error_message = "the server must attach to the declared private network"
  }

  assert {
    condition     = hcloud_volume_attachment.replacement.volume_id == tonumber(hcloud_volume.replacement.id) && !hcloud_volume_attachment.replacement.automount
    error_message = "declared storage must remain empty and unmounted until the restore runner admits it"
  }
}

run "global_ssh_is_refused" {
  command = plan

  variables {
    admin_source_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.admin_source_cidrs]
}

run "mutable_image_alias_is_refused" {
  command = plan

  variables {
    server_image_id = "ubuntu-24.04"
  }

  expect_failures = [var.server_image_id]
}

run "unsupported_architecture_is_refused" {
  command = plan

  variables {
    target_architecture = "aarch64"
  }

  expect_failures = [var.target_architecture]
}

run "undersized_storage_is_refused" {
  command = plan

  variables {
    data_volume_size_gb = 20
  }

  expect_failures = [var.data_volume_size_gb]
}
