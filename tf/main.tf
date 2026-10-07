locals {
  node_names = [for i in range(var.vm_count) : "${var.name_prefix}${i + 1}"]
  node_ips   = [for i in range(var.vm_count) : cidrhost(var.network_cidr, var.first_host_num + i)]
  prefix_len = split("/", var.network_cidr)[1]
  server_ip  = local.node_ips[0]
  ssh_key    = "${path.module}/k3s_ssh_key"
  k3s_env    = "INSTALL_K3S_VERSION='${var.k3s_version}' K3S_TOKEN=\"$(cat /tmp/k3s-token)\""
}

resource "tls_private_key" "ssh" {
  algorithm = "ED25519"
}

resource "local_file" "ssh_private_key" {
  content         = tls_private_key.ssh.private_key_openssh
  filename        = local.ssh_key
  file_permission = "0600"
}

resource "random_password" "k3s_token" {
  length  = 48
  special = false
}

# k3s-node-1 is the k3s server (control plane).
resource "proxmox_vm_qemu" "server" {
  vmid        = var.base_vmid
  name        = local.node_names[0]
  target_node = var.target_node

  clone      = var.template_name
  full_clone = true
  agent      = 1

  cores    = var.cores
  sockets  = 1
  memory   = var.memory
  scsihw   = "virtio-scsi-pci"
  kvm      = var.kvm
  cpu_type = var.kvm ? "host" : "max"

  os_type      = "cloud-init"
  ciuser       = var.ci_user
  sshkeys      = tls_private_key.ssh.public_key_openssh
  ipconfig0    = "ip=${local.server_ip}/${local.prefix_len},gw=${var.gateway}"
  nameserver   = var.nameserver
  searchdomain = ""

  boot = "order=scsi0"

  network {
    id     = 0
    model  = "virtio"
    bridge = var.bridge
  }

  disks {
    scsi {
      scsi0 {
        disk {
          storage = var.disk_storage
          size    = var.disk_size
        }
      }
    }
    ide {
      ide2 {
        cloudinit {
          storage = var.disk_storage
        }
      }
    }
  }

  serial {
    id   = 0
    type = "socket"
  }
  vga {
    type = "serial0"
  }

  connection {
    type        = "ssh"
    host        = local.server_ip
    user        = var.ci_user
    private_key = tls_private_key.ssh.private_key_openssh
    timeout     = "10m"
  }

  provisioner "file" {
    content     = random_password.k3s_token.result
    destination = "/tmp/k3s-token"
  }

  provisioner "remote-exec" {
    inline = [
      # exit 2 is cloud-init "done with recoverable warnings"
      "cloud-init status --wait > /dev/null || [ $? -eq 2 ]",
      "curl -sfL https://get.k3s.io | sudo env ${local.k3s_env} sh -s - server --tls-san ${local.server_ip}",
      "timeout 600 bash -c 'until sudo k3s kubectl get nodes --no-headers 2>/dev/null | grep -q .; do sleep 5; done'",
      "sudo k3s kubectl wait --for=condition=Ready node --all --timeout=900s",
    ]
  }
}

# The remaining nodes join the server as k3s agents.
resource "proxmox_vm_qemu" "agent" {
  count = var.vm_count - 1

  vmid        = var.base_vmid + count.index + 1
  name        = local.node_names[count.index + 1]
  target_node = var.target_node

  clone      = var.template_name
  full_clone = true
  agent      = 1

  cores    = var.cores
  sockets  = 1
  memory   = var.memory
  scsihw   = "virtio-scsi-pci"
  kvm      = var.kvm
  cpu_type = var.kvm ? "host" : "max"

  os_type      = "cloud-init"
  ciuser       = var.ci_user
  sshkeys      = tls_private_key.ssh.public_key_openssh
  ipconfig0    = "ip=${local.node_ips[count.index + 1]}/${local.prefix_len},gw=${var.gateway}"
  nameserver   = var.nameserver
  searchdomain = ""

  boot = "order=scsi0"

  network {
    id     = 0
    model  = "virtio"
    bridge = var.bridge
  }

  disks {
    scsi {
      scsi0 {
        disk {
          storage = var.disk_storage
          size    = var.disk_size
        }
      }
    }
    ide {
      ide2 {
        cloudinit {
          storage = var.disk_storage
        }
      }
    }
  }

  serial {
    id   = 0
    type = "socket"
  }
  vga {
    type = "serial0"
  }

  connection {
    type        = "ssh"
    host        = local.node_ips[count.index + 1]
    user        = var.ci_user
    private_key = tls_private_key.ssh.private_key_openssh
    timeout     = "10m"
  }

  provisioner "file" {
    content     = random_password.k3s_token.result
    destination = "/tmp/k3s-token"
  }

  provisioner "remote-exec" {
    inline = [
      # exit 2 is cloud-init "done with recoverable warnings"
      "cloud-init status --wait > /dev/null || [ $? -eq 2 ]",
      "curl -sfL https://get.k3s.io | sudo env ${local.k3s_env} K3S_URL='https://${local.server_ip}:6443' sh -s - agent",
    ]
  }

  depends_on = [proxmox_vm_qemu.server]
}

resource "null_resource" "kubeconfig" {
  triggers = {
    server_id = proxmox_vm_qemu.server.id
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      umask 077
      ssh -i '${local.ssh_key}' -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
        ${var.ci_user}@${local.server_ip} 'sudo cat /etc/rancher/k3s/k3s.yaml' \
        | sed 's/127\.0\.0\.1/${local.server_ip}/' > '${path.module}/kubeconfig'
    EOT
  }

  depends_on = [local_file.ssh_private_key, proxmox_vm_qemu.agent]
}
