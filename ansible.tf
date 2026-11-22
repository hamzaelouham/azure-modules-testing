# =============================================================================
# Ansible integration
# =============================================================================

resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/ansible/inventory"
  file_permission = "0600"

  content = templatefile("${path.module}/templates/inventory.tftpl", {
    master_ip            = module.master.private_ip_address
    worker_ips           = [for worker in values(module.worker) : worker.private_ip_address]
    ssh_user             = var.admin_username
    ssh_private_key_path = pathexpand(var.ssh_private_key_path)
  })
}

# Wait for the VMs to boot. Re-runs whenever a VM is created or replaced.
resource "terraform_data" "wait_for_vms" {
  triggers_replace = concat(
    [module.master.vm_id],
    [for worker in values(module.worker) : worker.vm_id],
  )

  provisioner "local-exec" {
    command = "echo 'Waiting 60 seconds for VMs to boot...' && sleep 60"
  }
}

# Set up the Kubernetes cluster. Re-runs only when the VMs, the inventory or
# the Kubernetes version change.
resource "terraform_data" "run_ansible" {
  triggers_replace = {
    vm_ids      = terraform_data.wait_for_vms.id
    inventory   = local_file.ansible_inventory.content_sha256
    k8s_version = var.k8s_version
  }

  provisioner "local-exec" {
    command     = "ansible-playbook -i inventory k8s/setup/k8s-main.yaml -e k8s_version=${var.k8s_version}"
    working_dir = "${path.module}/ansible"

    environment = {
      ANSIBLE_HOST_KEY_CHECKING = "False"
    }
  }
}
