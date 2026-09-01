terraform {
  required_version = "= 1.12.6"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "= 1.68.0"
    }
  }

  backend "s3" {
    encrypt      = true
    use_lockfile = true
  }
}

provider "hcloud" {
  endpoint = var.hcloud_endpoint
}
