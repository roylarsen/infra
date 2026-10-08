# tf

Terraform for a 3-node k3s cluster on Proxmox, with DigitalOcean DNS and a Flux bootstrap.

## What it creates

- 3 VMs (`k3s-node-1..3`, IDs 200-202) cloned from template 9000 (see `../scripts`), static IPs `192.168.1.201-203`
- k3s: node 1 is the server, nodes 2-3 are agents. A kubeconfig is written to `tf/kubeconfig`
- A records `k3s-node-N.xhousebreakx.org` in DigitalOcean
- Flux, bootstrapped into the cluster against `roylarsen/infra` (`new-k3s`, `flux/clusters/k3s`)

## Prerequisites

Terraform >= 1.5, `flux` and `kubectl` on PATH, and these environment variables:

- `PM_API_URL` (ending `/api2/json`), `PM_USER`, `PM_PASS`: Proxmox
- `DIGITALOCEAN_TOKEN`: DNS
- `TF_VAR_github_token`: GitHub PAT with repo access (needed when `bootstrap_flux=true`)

## Usage

```sh
terraform init
terraform apply -var tls_insecure=true   # needed if the Proxmox cert doesn't match the hostname
```

Set `-var bootstrap_flux=false` to skip Flux. `kvm` defaults to `true`; use `-var kvm=false` on hosts without `/dev/kvm` (slow emulation).

Common variables are in `variables.tf`: `vm_count`, `base_vmid`, `network_cidr`, `gateway`, `cores`, `memory`, `disk_size`, `dns_domain`, `dns_ttl`, `flux_branch`, `flux_path`.

## Files

`main.tf` (VMs and k3s), `dns.tf`, `flux.tf`, `variables.tf`, `outputs.tf`, `versions.tf`.

## Secrets

State contains the SSH private key, k3s token and GitHub token. `tf/k3s_ssh_key`, `tf/kubeconfig` and state files are gitignored; keep them private.
