variable "tenancy_ocid" {}
variable "user_ocid" {}
variable "fingerprint" {}
variable "private_key_path" {}
variable "compartment_ocid" {}
variable "region" {}
variable "AD" {
    default = 1
}
variable "rtCount" {
    default = 2
}

variable "instance_image_ocid" {
  type = map(string)

  default = {
    // See https://docs.ap-melbourne-1.oraclecloud.com/images/
    // Oracle-provided image "Oracle-Linux-7.4-2018.02.21-1"
    #ap-1melbourne-1  = ocid1.tenancy.oc1.aaaaaaaamlogbdgjzh7hv5qex4oi5gkk67m7b5kxq2o2lrwyac3whqkahx3q
  }
}
provider "oci" {
  tenancy_ocid     = "${var.ocid1.tenancy.oc1.aaaaaaaamlogbdgjzh7hv5qex4oi5gkk67m7b5kxq2o2lrwyac3whqkahx3q}"
  user_ocid        = "${var.ocid1.user.oc1.aaaaaaaaeuvr2lz25vzuwen3mamdxlfve6dskjmf2l2bgjwyutacupu2klka}"
  #fingerprint      = "${var.fingerprint}"
  #private_key_path = "${var.private_key_path}"
  region           = "${var.ap-melbourne-1}"
}

resource "oci_core_virtual_network" "ExampleVCN" {
  cidr_block     = "192.168.0.0/16"
  compartment_id = "${var.ocid1.compartment.oc1.aaaaaaaau6q764pdtgij26iginnl6kxbu2ci56efza26ww7yrdh6iou2u67}"
  display_name   = "TFExampleVCN"
  dns_label      = "tfexamplevcn"
}

data "oci_identity_availability_domains" "ADs" {
    compartment_id = "${var.ocid1.compartment.oc1.aaaaaaaau6q764pdtgij26iginnl6kxbu2ci56efza26ww7yrdh6iou2u67}"
}

resource "oci_core_subnet" "ExampleSubnet" {
  availability_domain = "${lookup(data.oci_identity_availability_domains.ADs.availability_domains[var.AD - 1],"name")}"
  cidr_block          = "192.168.1.0/24"
  display_name        = "TFExampleSubnet"
  dns_label           = "tfexamplesubnet"
  security_list_ids   = ["${oci_core_virtual_network.ExampleVCN.default_security_list_id}"]
  compartment_id      = "${var.ocid1.compartment.oc1.aaaaaaaau6q764pdtgij26iginnl6kxbu2ci56efza26ww7yrdh6iou2u67}"
  vcn_id              = "${oci_core_virtual_network.ExampleVCN.id}"
  route_table_id      = "${oci_core_virtual_network.ExampleVCN.default_route_table_id}"
  dhcp_options_id     = "${oci_core_virtual_network.ExampleVCN.default_dhcp_options_id}"
}

resource "oci_core_subnet" "NATSubnet" {
  count = "${var.rtCount}"
  availability_domain = "${lookup(data.oci_identity_availability_domains.ADs.availability_domains[var.AD - 1],"name")}"
  cidr_block          = "192.168.10.0/25"
  display_name        = "NATSubnet${count.index}"
  dns_label           = "natsubnet${count.index}"
  security_list_ids   = ["${oci_core_virtual_network.ExampleVCN.default_security_list_id}"]
  compartment_id      = "${var.ocid1.compartment.oc1.aaaaaaaau6q764pdtgij26iginnl6kxbu2ci56efza26ww7yrdh6iou2u67}"
  vcn_id              = "${oci_core_virtual_network.ExampleVCN.id}"
  route_table_id      = "${oci_core_route_table.ExampleRouteTable.*.id[count.index]}"
  dhcp_options_id     = "${oci_core_virtual_network.ExampleVCN.default_dhcp_options_id}"
}

# Create Instance
resource "oci_core_instance" "instance1" {
  availability_domain = "${lookup(data.oci_identity_availability_domains.ADs.availability_domains[var.AD - 1],"name")}"
  compartment_id      = "${var.ocid1.compartment.oc1.aaaaaaaau6q764pdtgij26iginnl6kxbu2ci56efza26ww7yrdh6iou2u67}"
  display_name        = "TFInstance"
  hostname_label      = "instance"
  image               = "${var.instance_image_ocid[var.region]}"
  shape               = "VM.Standard1.2"

  create_vnic_details {
    subnet_id = "${oci_core_subnet.ExampleSubnet.id}"
    skip_source_dest_check = true
    assign_public_ip = true
  }
}

# Gets a list of VNIC attachments on the instance
data "oci_core_vnic_attachments" "InstanceVnics" {
  compartment_id      = "${var.ocid1.user.oc1.aaaaaaaaeuvr2lz25vzuwen3mamdxlfve6dskjmf2l2bgjwyutacupu2klka}"
  availability_domain = "${lookup(data.oci_identity_availability_domains.ADs.availability_domains[var.AD - 1],"name")}"
  instance_id         = "${oci_core_instance.TFInstance1.id}"
}

# Gets the OCID of the first (default) VNIC
data "oci_core_vnic" "InstanceVnic" {
  vnic_id = "${lookup(data.oci_core_vnic_attachments.InstanceVnics.vnic_attachments[0],"vnic_id")}"
}

module "ip" {
  source = "./module"
  vnic_id        = "${lookup(data.oci_core_vnic_attachments.InstanceVnics.vnic_attachments[0],"vnic_id")}"
}

locals { 
anywhere = "0.0.0.0/0"
}

resource "oci_core_route_table" "ExampleRouteTable" {
  count = "${var.rtCount}"
  compartment_id = "${var.compartment_ocid}"
  vcn_id         = "${oci_core_virtual_network.ExampleVCN.id}"
  display_name   = "TFExampleRouteTable"


  route_rules {
    destination        = "${local.anywhere}"
    destination_type = "CIDR_BLOCK"
    #network_entity_id = "${oci_core_private_ip.TFPrivateIP.*.id[count.index]}"
    network_entity_id = "${module.ip.PrivateIPID[count.index]}"
  }
  route_rules {
    destination       = "${lookup(data.oci_core_services.test_services.services[0], "cidr_block")}"
    destination_type = "SERVICE_CIDR_BLOCK"
    network_entity_id = "${oci_core_service_gateway.test_service_gateway.id}"
  }
}

resource "oci_core_service_gateway" "test_service_gateway" {
  #Required
  compartment_id = "${var.compartment_ocid}"

  services {
    service_id = "${lookup(data.oci_core_services.test_services.services[0], "id")}"
  }

  vcn_id = "${oci_core_virtual_network.ExampleVCN.id}"
}

# data "oci_core_services" "test_services" {
#   filter {
#     name   = "name"
#     values = [".*Object.*Storage"]
#     regex  = true
#   }
#}
variable "vnic_id" {}

# Create PrivateIP
resource "oci_core_private_ip" "TFPrivateIP" {
  count = 2
  vnic_id        = "${var.vnic_id}"
  display_name   = "someDisplayName${count.index}"
  hostname_label = "somehostnamelabel${count.index}"
}

output "PrivateIPID" {
    value = "${oci_core_private_ip.TFPrivateIP.*.id}"
}
