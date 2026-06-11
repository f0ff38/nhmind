output "public_ip" {
  description = "Floating public IPv4 for relay (PTR, A record, SSH)."
  value       = openstack_networking_floatingip_v2.relay.address
}

output "private_ip" {
  description = "Private IPv4 on the relay subnet."
  value       = openstack_networking_port_v2.relay.all_fixed_ips[0]
}

output "server_id" {
  description = "OpenStack instance ID."
  value       = openstack_compute_instance_v2.relay.id
}

output "server_name" {
  description = "Cloud server name."
  value       = openstack_compute_instance_v2.relay.name
}

output "flavor_id" {
  description = "Resolved OpenStack flavor ID for the relay VM."
  value       = local.flavor_id
}

output "flavor_name" {
  description = "Resolved flavor name when auto-picked; empty when flavor_id override is set."
  value       = var.flavor_id != "" ? "" : try(data.openstack_compute_flavor_v2.relay[0].name, "")
}
