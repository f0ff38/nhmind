provider "openstack" {
  auth_url    = "https://cloud.api.selcloud.ru/identity/v3"
  domain_name = var.selectel_account_id
  tenant_id   = var.selectel_project_id
  user_name   = var.selectel_service_user
  password    = var.selectel_service_password
  region      = var.selectel_region
}
