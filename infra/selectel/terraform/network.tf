resource "openstack_networking_network_v2" "relay" {
  name                  = "${local.name_prefix}-net"
  admin_state_up        = true
  port_security_enabled = true
}

resource "openstack_networking_subnet_v2" "relay" {
  name       = "${local.name_prefix}-subnet"
  network_id = openstack_networking_network_v2.relay.id
  cidr       = var.private_subnet_cidr
  ip_version = 4
}

data "openstack_networking_network_v2" "external" {
  external = true
}

resource "openstack_networking_router_v2" "relay" {
  name                = "${local.name_prefix}-router"
  admin_state_up      = true
  external_network_id = data.openstack_networking_network_v2.external.id
}

resource "openstack_networking_router_interface_v2" "relay" {
  router_id = openstack_networking_router_v2.relay.id
  subnet_id = openstack_networking_subnet_v2.relay.id
}

resource "openstack_networking_port_v2" "relay" {
  name           = "${local.name_prefix}-port"
  network_id     = openstack_networking_network_v2.relay.id
  admin_state_up = true

  fixed_ip {
    subnet_id = openstack_networking_subnet_v2.relay.id
  }

  depends_on = [openstack_networking_router_interface_v2.relay]
}

resource "openstack_networking_floatingip_v2" "relay" {
  pool = var.floating_ip_pool
}

resource "openstack_networking_floatingip_associate_v2" "relay" {
  port_id     = openstack_networking_port_v2.relay.id
  floating_ip = openstack_networking_floatingip_v2.relay.address

  # Selectel pattern: associate public IP after the VM is attached to the port.
  depends_on = [openstack_compute_instance_v2.relay]
}
