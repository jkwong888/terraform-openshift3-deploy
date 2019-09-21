locals {
  all_node_ips = "${concat(var.master_private_ip, var.infra_private_ip, var.worker_private_ip, var.storage_private_ip)}"
  all_node_ips_incl_bastion = "${concat(list(var.bastion_ip_address), var.master_private_ip, var.infra_private_ip, var.worker_private_ip, var.storage_private_ip)}"
}

resource "null_resource" "dependency" {
  triggers = {
    all_dependencies = "${join(",", var.dependson)}"
  }
}

module "prepare_bastion" {
  source = "github.com/ibm-cloud-architecture/terraform-ansible-runplaybooks.git"

  dependson = "${
    list(null_resource.dependency.id)
  }"

  ansible_playbook_dir = "${path.module}/playbooks"
  ansible_playbooks = [
      "playbooks/prepare_bastion.yaml"
  ]

  ansible_vars       = {
    "docker_block_device" = "${var.docker_block_device}"
    "openshift_vers" = "${var.openshift_version}"
    "ansible_vers" = "${var.ansible_version}"
  }

  ssh_user           = "${var.ssh_user}"
  ssh_password       = "${var.ssh_password}"
  ssh_private_key    = "${var.ssh_private_key}"

  bastion_ip_address       = "${var.bastion_ip_address}"
  bastion_ssh_user         = "${var.bastion_ssh_user}"
  bastion_ssh_password     = "${var.bastion_ssh_password}"
  bastion_ssh_private_key  = "${var.bastion_ssh_private_key}"

  node_ips        = "${list(var.bastion_ip_address)}"
  node_hostnames  = "${list(var.bastion_ip_address)}"

  # ansible_verbosity = "-vvv"
}

module "prepare_nodes" {
  source = "github.com/ibm-cloud-architecture/terraform-ansible-runplaybooks.git"

  dependson = "${
    list(null_resource.dependency.id, 
    module.prepare_bastion.module_completed)
  }"

  ansible_playbook_dir = "${path.module}/playbooks"
  ansible_playbooks = [
      "playbooks/prepare_nodes.yaml"
  ]

  ansible_vars       = {
    "docker_block_device" = "${var.docker_block_device}"
    "openshift_vers" = "${var.openshift_version}"
    "ansible_vers" = "${var.ansible_version}"
  }

  ssh_user           = "${var.ssh_user}"
  ssh_password       = "${var.ssh_password}"
  ssh_private_key    = "${var.ssh_private_key}"

  bastion_ip_address       = "${var.bastion_ip_address}"
  bastion_ssh_user         = "${var.bastion_ssh_user}"
  bastion_ssh_password     = "${var.bastion_ssh_password}"
  bastion_ssh_private_key  = "${var.bastion_ssh_private_key}"

  node_ips        = "${local.all_node_ips}"
  node_hostnames  = "${local.all_node_ips}"

  # ansible_verbosity = "-vvv"
}

resource "null_resource" "write_master_cert" {
  count = "${var.master_cert != "" ? 1 : 0}"

  connection {
    type = "ssh"
    
    host        = "${var.bastion_ip_address}"
    user        = "${var.bastion_ssh_user}"
    password    = "${var.bastion_ssh_password}"
    private_key = "${var.bastion_ssh_private_key}"

  }

  provisioner "file" {
    content = <<EOF
${var.master_cert}
EOF
    destination = "~/master.crt"
  }
}

resource "null_resource" "write_master_key" {
  count = "${var.master_key != "" ? 1 : 0}"

  connection {
    type = "ssh"

    host        = "${var.bastion_ip_address}"
    user        = "${var.bastion_ssh_user}"
    password    = "${var.bastion_ssh_password}"
    private_key = "${var.bastion_ssh_private_key}"

  }

  provisioner "file" {
    content = <<EOF
${var.master_key}
EOF
    destination = "~/master.key"
  }
}

resource "null_resource" "write_router_cert" {
  count = "${var.router_cert != "" ? 1 : 0}"

  connection {
    type = "ssh"
    
    host        = "${var.bastion_ip_address}"
    user        = "${var.bastion_ssh_user}"
    password    = "${var.bastion_ssh_password}"
    private_key = "${var.bastion_ssh_private_key}"

  }

  provisioner "file" {
    content = <<EOF
${var.router_cert}
EOF
    destination = "~/router.crt"
  }
}

resource "null_resource" "write_router_key" {
  count = "${var.router_key != "" ? 1 : 0}"

  connection {
    type = "ssh"
    
    host        = "${var.bastion_ip_address}"
    user        = "${var.bastion_ssh_user}"
    password    = "${var.bastion_ssh_password}"
    private_key = "${var.bastion_ssh_private_key}"

  }

  provisioner "file" {
    content = <<EOF
${var.router_key}
EOF
    destination = "~/router.key"
  }
}

# write out the letsencrypt CA
resource "null_resource" "write_router_ca_cert" {
  count = "${var.router_ca_cert != "" ? 1 : 0}"

  connection {
    type = "ssh"
    
    host        = "${var.bastion_ip_address}"
    user        = "${var.bastion_ssh_user}"
    password    = "${var.bastion_ssh_password}"
    private_key = "${var.bastion_ssh_private_key}"

  }


  provisioner "file" {
    content = <<EOF
${var.router_ca_cert}
EOF
    destination = "~/router_ca.crt"
  }
}

#################################################
# Install Openshift
#################################################

module "prerequisites" {
  source = "github.com/ibm-cloud-architecture/terraform-ansible-runplaybooks.git"

  dependson = "${
    concat(list(null_resource.dependency.id, 
    module.prepare_bastion.module_completed,
    module.prepare_nodes.module_completed),
    null_resource.write_master_cert.*.id,
    null_resource.write_master_key.*.id,
    null_resource.write_router_cert.*.id,
    null_resource.write_router_key.*.id,
    null_resource.write_router_ca_cert.*.id)
  }"

  ansible_inventory = "${data.template_file.ansible_inventory.rendered}"
        
  ansible_playbooks = [
      "/usr/share/ansible/openshift-ansible/playbooks/prerequisites.yml"
  ]

  ssh_user           = "${var.ssh_user}"
  ssh_password       = "${var.ssh_password}"
  ssh_private_key    = "${var.ssh_private_key}"

  bastion_ip_address       = "${var.bastion_ip_address}"
  bastion_ssh_user         = "${var.bastion_ssh_user}"
  bastion_ssh_password     = "${var.bastion_ssh_password}"
  bastion_ssh_private_key  = "${var.bastion_ssh_private_key}"

  # ansible_verbosity = "-vvv"
}

module "deploy_cluster" {
  source = "github.com/ibm-cloud-architecture/terraform-ansible-runplaybooks.git"

  dependson = "${
    concat(list(null_resource.dependency.id, 
    module.prepare_bastion.module_completed,
    module.prepare_nodes.module_completed,
    module.prerequisites.module_completed),
    null_resource.write_master_cert.*.id,
    null_resource.write_master_key.*.id,
    null_resource.write_router_cert.*.id,
    null_resource.write_router_key.*.id,
    null_resource.write_router_ca_cert.*.id)
  }"

  ansible_inventory = "${data.template_file.ansible_inventory.rendered}"
        
  ansible_playbooks = [
      "/usr/share/ansible/openshift-ansible/playbooks/deploy_cluster.yml"
  ]

  ssh_user           = "${var.ssh_user}"
  ssh_password       = "${var.ssh_password}"
  ssh_private_key    = "${var.ssh_private_key}"

  bastion_ip_address       = "${var.bastion_ip_address}"
  bastion_ssh_user         = "${var.bastion_ssh_user}"
  bastion_ssh_password     = "${var.bastion_ssh_password}"
  bastion_ssh_private_key  = "${var.bastion_ssh_private_key}"

  # ansible_verbosity = "-vvv"
}

resource "null_resource" "create_cluster_admin" {
    connection {
      type = "ssh"
      host = "${element(var.master_private_ip, 0)}"
      user = "${var.ssh_user}"
      private_key = "${var.ssh_private_key}"
      
      bastion_host        = "${var.bastion_ip_address}"
      bastion_user        = "${var.bastion_ssh_user}"
      bastion_password    = "${var.bastion_ssh_password}"
      bastion_private_key = "${var.bastion_ssh_private_key}"
    }

    provisioner "remote-exec" {
        when = "create"
        inline = [ 
          "oc adm policy add-cluster-role-to-user cluster-admin ${var.openshift_admin_user}"
        ]
    }

    depends_on    = [
      "module.deploy_cluster"
    ]
}

#################################################
# Perform post-install configurations for Openshift
#################################################
# resource "null_resource" "post_install_cluster" {
#   count = "${length(local.all_node_ips)}"
#
#   connection {
#       type = "ssh"
#       host = "${element(local.all_node_ips, count.index)}"
#       user = "${var.ssh_user}"
#       private_key = "${file(var.bastion_private_ssh_key)}"
#       bastion_host = "${var.bastion_ip_address}"
#       bastion_host_key = "${file(var.bastion_private_ssh_key)}"
#   }
#
#   provisioner "file" {
#     source      = "${path.module}/scripts/post_install_node.sh"
#     destination = "/tmp/post_install_node.sh"
#   }
#
#   provisioner "remote-exec" {
#     inline = [
#       "chmod u+x /tmp/post_install_node.sh",
#       "sudo /tmp/post_install_node.sh"
#     ]
#   }
#
#   depends_on    = ["null_resource.deploy_cluster"]
# }
