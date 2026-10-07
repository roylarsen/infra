output "vms" {
  description = "Created VMs: name => VM ID"
  value = merge(
    { (proxmox_vm_qemu.server.name) = proxmox_vm_qemu.server.vmid },
    { for vm in proxmox_vm_qemu.agent : vm.name => vm.vmid }
  )
}

output "node_ips" {
  description = "Static IP of each node"
  value       = zipmap(local.node_names, local.node_ips)
}

output "kubeconfig" {
  description = "Use the cluster once applied"
  value       = "export KUBECONFIG=${abspath("${path.module}/kubeconfig")}"
  depends_on  = [null_resource.kubeconfig]
}

output "ssh_server" {
  description = "SSH into the k3s server"
  value       = "ssh -i ${abspath(local.ssh_key)} ${var.ci_user}@${local.server_ip}"
}

output "dns_names" {
  description = "Node FQDNs created in DigitalOcean DNS"
  value       = [for r in digitalocean_record.node : r.fqdn]
}

output "flux_sync" {
  description = "Repository location Flux syncs from"
  value       = var.bootstrap_flux ? "https://github.com/${var.github_owner}/${var.github_repository} (${var.flux_branch}:${var.flux_path})" : "disabled"
}
