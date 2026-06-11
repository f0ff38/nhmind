resource "openstack_compute_keypair_v2" "relay" {
  name       = "${local.name_prefix}-key"
  public_key = var.deploy_ssh_public_key
}

data "openstack_compute_flavors_v2" "catalog" {
  count = var.flavor_id == "" ? 1 : 0
}

check "relay_flavor_resolved" {
  assert {
    condition = var.flavor_id != "" || try(local.relay_flavor_auto.id, "") != ""
    error_message = join(" ", [
      "No flavor matches 2 vCPU / 2048 MB RAM / disk 0 (boot volume).",
      "Set workflow input flavor_id from Selectel panel (openstack flavor list).",
    ])
  }
}

data "openstack_images_image_v2" "ubuntu" {
  name        = var.image_name
  most_recent = true
  visibility  = "public"
}

resource "openstack_blockstorage_volume_v3" "relay_boot" {
  name                 = "${local.name_prefix}-boot"
  size                 = var.boot_volume_size_gb
  image_id             = data.openstack_images_image_v2.ubuntu.id
  volume_type          = local.volume_type
  availability_zone    = var.availability_zone
  enable_online_resize = true

  lifecycle {
    ignore_changes = [image_id]
  }
}

resource "openstack_compute_instance_v2" "relay" {
  name              = var.server_name
  flavor_id         = local.flavor_id
  key_pair          = openstack_compute_keypair_v2.relay.name
  availability_zone = var.availability_zone
  user_data = templatefile("${path.module}/../cloud-init/relay-bootstrap.yaml", {
    deploy_ssh_public_key = trimspace(var.deploy_ssh_public_key)
  })

  network {
    port = openstack_networking_port_v2.relay.id
  }

  block_device {
    uuid             = openstack_blockstorage_volume_v3.relay_boot.id
    source_type      = "volume"
    destination_type = "volume"
    boot_index       = 0
  }

  vendor_options {
    ignore_resize_confirmation = true
  }

  depends_on = [
    openstack_networking_port_secgroup_associate_v2.relay,
    openstack_networking_floatingip_associate_v2.relay,
  ]
}
