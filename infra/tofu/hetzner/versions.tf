terraform {
  required_version = "= 1.12.6"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "= 1.68.0"
    }
  }

  # Supply bucket, key, region, endpoint, and credentials at init time from the
  # operator environment/private backend config. They are deliberately absent
  # from tracked source. The object store must enforce encryption, versioning,
  # and retention; use_lockfile serializes the one owned replacement run.
  backend "s3" {
    encrypt      = true
    use_lockfile = true
  }
}

provider "hcloud" {
  # HCLOUD_TOKEN is read by the provider. Never add it to configuration/state.
}
