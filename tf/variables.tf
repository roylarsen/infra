variable "target_node" {
  description = "Proxmox node that hosts the VMs and the template"
  type        = string
  default     = "technodrome"
}

variable "template_name" {
  description = "Name of the template to clone (VM ID 9000)"
  type        = string
  default     = "ubuntu-latest"
}

variable "vm_count" {
  description = "Number of VMs to create"
  type        = number
  default     = 3
}

variable "base_vmid" {
  description = "VM ID of the first VM; subsequent VMs increment from it"
  type        = number
  default     = 200
}

variable "name_prefix" {
  description = "Prefix for VM names (suffixed with 1..vm_count)"
  type        = string
  default     = "k3s-node-"
}

variable "cores" {
  description = "vCPU cores per VM"
  type        = number
  default     = 2
}

variable "memory" {
  description = "Memory per VM in MiB"
  type        = number
  default     = 4096
}

variable "kvm" {
  description = "Use KVM hardware virtualization; false falls back to slow emulation (this host has no /dev/kvm)"
  type        = bool
  default     = false
}

variable "bridge" {
  description = "Network bridge for the VMs"
  type        = string
  default     = "vmbr0"
}

variable "disk_storage" {
  description = "Proxmox storage for the VM disk and cloud-init drive"
  type        = string
  default     = "local-lvm"
}

variable "disk_size" {
  description = "Root disk size (must be at least the template's 20G)"
  type        = string
  default     = "20G"
}

variable "ci_user" {
  description = "Cloud-init user"
  type        = string
  default     = "ubuntu"
}

variable "network_cidr" {
  description = "Subnet the VMs live in"
  type        = string
  default     = "192.168.1.0/24"
}

variable "first_host_num" {
  description = "Host number of the first VM within network_cidr (e.g. 201 -> 192.168.1.201)"
  type        = number
  default     = 201
}

variable "gateway" {
  description = "Default gateway for the VMs"
  type        = string
  default     = "192.168.1.1"
}

variable "nameserver" {
  description = "DNS server for the VMs"
  type        = string
  default     = "192.168.1.1"
}

variable "k3s_version" {
  description = "k3s release to install (e.g. v1.30.4+k3s1); empty installs the latest stable"
  type        = string
  default     = ""
}

variable "dns_domain" {
  description = "Existing DigitalOcean DNS zone that receives the node records"
  type        = string
  default     = "xhousebreakx.org"
}

variable "dns_ttl" {
  description = "TTL in seconds for the node DNS records"
  type        = number
  default     = 30
}

variable "bootstrap_flux" {
  description = "Bootstrap Flux into the cluster after k3s is installed"
  type        = bool
  default     = true
}

variable "github_token" {
  description = "GitHub token with repo access for flux bootstrap; set via TF_VAR_github_token"
  type        = string
  default     = ""
  sensitive   = true
}

variable "github_owner" {
  description = "GitHub user that owns the Flux repository"
  type        = string
  default     = "roylarsen"
}

variable "github_repository" {
  description = "GitHub repository Flux commits its manifests to and syncs from"
  type        = string
  default     = "infra"
}

variable "flux_branch" {
  description = "Git branch Flux tracks"
  type        = string
  default     = "new-k3s"
}

variable "flux_path" {
  description = "Path in the repository that holds this cluster's Flux manifests"
  type        = string
  default     = "flux/clusters/k3s"
}

variable "tls_insecure" {
  description = "Skip TLS verification of the Proxmox API (development only)"
  type        = bool
  default     = false
}
