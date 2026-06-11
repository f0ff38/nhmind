locals {
  name_prefix = "nhmind-relay"
  volume_type = "fast.${var.availability_zone}"
  ssh_cidrs   = distinct(concat(var.github_actions_cidrs, var.extra_ssh_cidrs))
  flavor_id   = var.flavor_id != "" ? var.flavor_id : data.openstack_compute_flavor_v2.relay[0].id
}
