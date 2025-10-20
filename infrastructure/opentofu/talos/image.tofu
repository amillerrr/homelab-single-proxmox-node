locals {
  version      = var.image.version
  schematic    = file("${path.root}/${var.image.schematic_path}")
  schematic_id = jsondecode(data.http.schematic_id.response_body)["id"]

  update_version        = coalesce(var.image.update_version, var.image.version)
  update_schematic_path = coalesce(var.image.update_schematic_path, var.image.schematic_path)
  update_schematic      = file("${path.root}/${local.update_schematic_path}")
  update_schematic_id   = jsondecode(data.http.updated_schematic_id.response_body)["id"]

  image_id        = "${local.schematic_id}_${local.version}"
  update_image_id = "${local.update_schematic_id}_${local.update_version}"
}

data "http" "schematic_id" {
  url          = "${var.image.factory_url}/schematics"
  method       = "POST"
  request_body = local.schematic
}

data "http" "updated_schematic_id" {
  url          = "${var.image.factory_url}/schematics"
  method       = "POST"
  request_body = local.update_schematic
}

#
# DELETED resource "talos_image_factory_schematic" "this" {}
# DELETED resource "talos_image_factory_schematic" "updated" {}
#

resource "proxmox_virtual_environment_download_file" "this" {
  for_each = {
    for k, v in var.nodes :
    "${v.host_node}_${v.update == true ? local.update_image_id : local.image_id}" => {
      host_node = v.host_node
      # --- THIS IS THE BUG FIX ---
      # Use the same 'local' schematic IDs as the key, not the resource IDs
      schematic = v.update == true ? local.update_schematic_id : local.schematic_id
      version   = v.update == true ? local.update_version : local.version
    }...
  }

  node_name    = each.value[0].host_node
  content_type = "iso"
  datastore_id = var.image.proxmox_datastore

  file_name               = "talos-${each.value[0].schematic}-${each.value[0].version}-${var.image.platform}-${var.image.arch}.iso"
  url                     = "${var.image.factory_url}/image/${each.value[0].schematic}/${each.value[0].version}/${var.image.platform}-${var.image.arch}.iso"
  overwrite               = false
}
