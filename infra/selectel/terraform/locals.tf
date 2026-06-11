locals {
  name_prefix = "nhmind-relay"
  volume_type = "fast.${var.availability_zone}"

  relay_flavor_matches = var.flavor_id != "" ? [] : [
    for flavor in try(data.openstack_compute_flavors_v2.catalog[0].flavors, []) :
    flavor
    if flavor.vcpus == 2 && flavor.ram == 2048 && flavor.disk == 0
  ]
  relay_flavor_name = length(local.relay_flavor_matches) > 0 ? sort([
    for flavor in local.relay_flavor_matches : flavor.name
  ])[0] : null
  relay_flavor_auto = length(local.relay_flavor_matches) > 0 ? one([
    for flavor in local.relay_flavor_matches : flavor if flavor.name == local.relay_flavor_name
  ]) : null
  flavor_id = var.flavor_id != "" ? var.flavor_id : try(local.relay_flavor_auto.id, "")

  project_id_hex      = lower(replace(trimspace(var.selectel_project_id), "-", ""))
  selectel_project_id = length(local.project_id_hex) == 32 ? local.project_id_hex : trimspace(var.selectel_project_id)
}
