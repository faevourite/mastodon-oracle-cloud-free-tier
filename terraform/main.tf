# Based on https://github.com/oracle/terraform-provider-oci/blob/master/examples/always_free/main.tf

terraform {
  required_providers {
    oci = {
      source = "oracle/oci"
    }
  }
}

provider "oci" {
}

# If you don't have an ed25519 SSH key, run
#   ssh-keygen -t ed25519 -C "<your@email.address>"
# Then set this variable to ~/.ssh/id_ed25519.pub
# It should be one line (no line breaks)
variable "ssh_public_key" {
  type = string
}

# In the Oracle Cloud web console, click on the user icon in the top right,
# then click Tenancy, and copy the OCID.
variable "tenancy_ocid" {
  type = string
}

# Go to https://cloud.oracle.com/identity/compartments and copy the OCID
variable "compartment_ocid" {
  type = string
}

# Go to https://docs.oracle.com/en-us/iaas/images/ubuntu-2204/ .
# Find the latest "Canonical-Ubuntu-22.04-aarch64" image, click on it, then find the OCID
# of this image that resides in your tenancy.
# The default here is for "Canonical-Ubuntu-22.04-aarch64-2022.08.10-0" in Toronto, which
# was current at the time of writing (but is not anymore).
variable "instance_image_ocid" {
  default = "ocid1.image.oc1.ca-toronto-1.aaaaaaaa5thzsi5g7wn2x24dtmfgffgbqaeyalvugpuy65kxq22wr77mxfua"
}

variable "instance_shape" { default = "VM.Standard.A1.Flex" }

variable "instance_ocpus" { default = 4 }

variable "instance_shape_config_memory_in_gbs" { default = 24 }

data "oci_identity_availability_domain" "ad" {
  compartment_id = var.tenancy_ocid
  ad_number      = 1
}

/* Network */

resource "oci_core_virtual_network" "mastodon" {
  cidr_block     = "10.1.0.0/16"
  compartment_id = var.compartment_ocid
  display_name   = "mastodon"
  dns_label      = "mastodon"
}

resource "oci_core_security_list" "mastodon" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_virtual_network.mastodon.id
  display_name   = "mastodon"

  egress_security_rules {
    protocol    = "6"
    destination = "0.0.0.0/0"
  }

  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"

    tcp_options {
      max = "22"
      min = "22"
    }
  }

  # Uncomment if you can't use the Cloudflare DNS provider in Caddy.
  # Otherwise, HTTP access is not needed for Mastodon itself.
  #  ingress_security_rules {
  #    protocol = "6"
  #    source   = "0.0.0.0/0"
  #
  #    tcp_options {
  #      max = "80"
  #      min = "80"
  #    }
  #  }

  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"

    tcp_options {
      max = "443"
      min = "443"
    }
  }
}

resource "oci_core_internet_gateway" "mastodon" {
  compartment_id = var.compartment_ocid
  display_name   = "mastodon"
  vcn_id         = oci_core_virtual_network.mastodon.id
}

resource "oci_core_route_table" "mastodon" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_virtual_network.mastodon.id
  display_name   = "mastodon"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.mastodon.id
  }
}

resource "oci_core_subnet" "mastodon" {
  cidr_block        = "10.1.20.0/24"
  display_name      = "mastodon"
  dns_label         = "mastodon"
  security_list_ids = [oci_core_security_list.mastodon.id]
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_virtual_network.mastodon.id
  route_table_id    = oci_core_route_table.mastodon.id
  dhcp_options_id   = oci_core_virtual_network.mastodon.default_dhcp_options_id
}

data "oci_core_vnic_attachments" "app_vnics" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domain.ad.name
  instance_id         = oci_core_instance.mastodon.id
}

data "oci_core_vnic" "app_vnic" {
  vnic_id = data.oci_core_vnic_attachments.app_vnics.vnic_attachments[0]["vnic_id"]
}

/* Instances */

resource "oci_core_instance" "mastodon" {
  availability_domain = data.oci_identity_availability_domain.ad.name
  compartment_id      = var.compartment_ocid
  display_name        = "mastodon"
  shape               = var.instance_shape

  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_shape_config_memory_in_gbs
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.mastodon.id
    display_name     = "mastodon"
    assign_public_ip = true
    hostname_label   = "mastodon"
  }

  source_details {
    source_type = "image"
    source_id   = var.instance_image_ocid
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
  }
}

/* Storage */
resource "oci_core_volume" "mastodon" {
  availability_domain = data.oci_identity_availability_domain.ad.name
  compartment_id      = var.compartment_ocid
  display_name        = "mastodon"
  size_in_gbs         = 150 # 200 total; auto 50gb for boot volume.
}
resource "oci_core_volume_attachment" "mastodon" {
  attachment_type = "paravirtualized"
  instance_id     = oci_core_instance.mastodon.id
  volume_id       = oci_core_volume.mastodon.id
  # Use a consistent volume name
  # https://docs.oracle.com/en-us/iaas/Content/Block/References/consistentdevicepaths.htm
  device = "/dev/oracleoci/oraclevdb"

  display_name = "mastodon"
}


/* Output */
output "public_ip" {
  value = data.oci_core_vnic.app_vnic.public_ip_address
}
