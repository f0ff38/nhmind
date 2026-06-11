terraform {
  required_version = ">= 1.5.0"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "2.1.0"
    }
  }

  # bucket, region, endpoints, credentials — via -backend-config in CI (pool must match bucket location)
  backend "s3" {
    key                         = "nhmind-relay/terraform.tfstate"
    use_path_style              = true
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    skip_metadata_api_check     = true
  }
}
