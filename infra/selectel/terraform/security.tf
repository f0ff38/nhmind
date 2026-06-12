resource "openstack_networking_secgroup_v2" "relay" {
  name        = "${local.name_prefix}-sg"
  description = "nhmind relay canary: SSH key-only (0.0.0.0/0), HTTPS public (TLS via Selectel LE)"
}

resource "openstack_networking_secgroup_rule_v2" "ssh_ingress" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.relay.id
}

resource "openstack_networking_secgroup_rule_v2" "https_ingress" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.relay.id
}

# Selectel/OpenStack adds a default egress allow-all rule when the SG is created.

resource "openstack_networking_port_secgroup_associate_v2" "relay" {
  port_id            = openstack_networking_port_v2.relay.id
  security_group_ids = [openstack_networking_secgroup_v2.relay.id]
}
