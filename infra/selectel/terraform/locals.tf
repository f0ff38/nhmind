locals {
  name_prefix = "nhmind-relay"
  volume_type = "fast.${var.availability_zone}"
  flavor_id   = var.flavor_id

  project_id_hex      = lower(replace(trimspace(var.selectel_project_id), "-", ""))
  selectel_project_id = length(local.project_id_hex) == 32 ? local.project_id_hex : trimspace(var.selectel_project_id)
}
