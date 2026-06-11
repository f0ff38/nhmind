locals {
  name_prefix = "nhmind-relay"
  volume_type = "fast.${var.availability_zone}"
  flavor_id   = var.flavor_id != "" ? var.flavor_id : data.openstack_compute_flavor_v2.relay[0].id

  project_id_hex = lower(replace(trimspace(var.selectel_project_id), "-", ""))
  selectel_project_id = length(local.project_id_hex) == 32 ? format(
    "%s-%s-%s-%s-%s",
    substr(local.project_id_hex, 0, 8),
    substr(local.project_id_hex, 8, 4),
    substr(local.project_id_hex, 16, 4),
    substr(local.project_id_hex, 20, 4),
    substr(local.project_id_hex, 24, 12),
  ) : trimspace(var.selectel_project_id)
}
