# Infra

## Ubuntu Server Proxmox template

`scripts/create-ubuntu-template.sh` uses Canonical's Ubuntu image-stream
metadata to select and download the highest supported Ubuntu Server amd64 cloud
image, then creates a cloud-init Proxmox template named `ubuntu-latest`.

The template always uses VM ID `9000`. Before it downloads an image or creates
a VM, the script verifies that neither the ID nor `ubuntu-latest` is already
in use. It fails without modifying an existing VM or template.

### Requirements

- Bash, `curl`, and `jq` on the machine that runs the script
- An HTTPS-accessible Proxmox API
- A Proxmox API token with permission to inspect cluster resources, create and
  configure QEMU VMs, upload/delete import content, and convert VMs to templates
- An image storage that has **Import** content enabled, and a target storage
  that supports VM disks and cloud-init disks

Set API credentials in the environment; do not pass the token secret on the
command line:

```bash
export PVE_API_URL='https://pve.example.test:8006'
export PVE_TOKEN_ID='automation@pve!template-builder'
export PVE_TOKEN_SECRET='replace-with-token-secret'
```

Create the template:

```bash
./scripts/create-ubuntu-template.sh \
  --node pve1 \
  --image-storage local \
  --disk-storage local-lvm \
  --bridge vmbr0 \
  --disk-size 20G \
  --cores 2 \
  --memory 2048
```

`--image-storage` temporarily stores the cloud image as import content while
Proxmox imports it into `--disk-storage`; the script removes that temporary
remote image after a successful import. If the build fails after VM creation,
the script attempts to remove the partial VM as well.

TLS certificates are verified by default. Use `--insecure` only for a
development environment with a deliberately untrusted certificate.

## Terraform: k3s cluster

`tf/` full-clones the `ubuntu-latest` template (VM ID 9000) into three VMs with
VM IDs 200-202 using the `telmate/proxmox` provider, then installs
[k3s](https://k3s.io) over SSH: `k3s-node-1` (200) is the server and
`k3s-node-2`/`k3s-node-3` (201/202) join as agents. CPU, memory and disk are
inherited from the template.

- **Credentials:** the provider reads `PM_API_URL`, `PM_USER` and `PM_PASS`
  (as in `~/.prox`). Set `PM_API_URL` to the hostname on the server's TLS
  certificate, `https://technodrome.xhousebreakx.org:8006/api2/json`, so
  verification stays on. The certificate is not valid for the `.local` name; if
  you must use it, pass `-var tls_insecure=true` (skips TLS verification).
- **Addressing:** static IPs from `network_cidr` (default `192.168.1.0/24`)
  starting at host `first_host_num` (default 201), so `192.168.1.201-203`, with
  `gateway`/`nameserver` defaulting to `192.168.1.1`. Make sure those
  addresses are free.
- **Access:** Terraform generates an SSH key (`tf/k3s_ssh_key`) and the k3s join
  token. Both are kept in state, so keep state local and private. The key and
  `tf/kubeconfig` are gitignored.
- **DNS:** each node gets an A record in the existing DigitalOcean zone
  `dns_domain` (default `xhousebreakx.org`): `k3s-node-1/2/3.xhousebreakx.org`
  pointing at the node IPs, with TTL `dns_ttl` (default 30 seconds). Terraform
  manages only the records, not the zone. Export a DigitalOcean API token
  (`export DIGITALOCEAN_TOKEN=...`) before running; it is never stored in files.
  These records publish private LAN addresses in public DNS.
- **Sizing:** `cores` (2), `memory` (2048 MiB), `disk_size` (20G), `disk_storage`
  (`local-lvm`) and `bridge` (`vmbr0`) are variables. `kvm` defaults to `true`
  (CPU type `host`). On a host without `/dev/kvm`, set `-var kvm=false` to use slow
  emulation instead.
- **Flux:** after k3s is up, `flux bootstrap github` installs Flux, commits its
  manifests to `github_owner/github_repository` (default `roylarsen/infra`)
  on branch `flux_branch` (default `new-k3s`) under `flux_path` (default
  `flux/clusters/k3s`), and syncs from there. It needs the `flux` CLI on the
  machine running Terraform and a GitHub token with repo access:
  `export TF_VAR_github_token=...` (the token is stored in Terraform state).
  Set `-var bootstrap_flux=false` to skip it. The bootstrap is idempotent.
- **Install:** the machine running `terraform apply` must reach the VMs over
  SSH. Set `k3s_version` (for example `v1.30.4+k3s1`) to pin a release;
  empty installs the latest stable.

```bash
. ~/.prox
cd tf
terraform init
terraform plan -var tls_insecure=true
terraform apply -var tls_insecure=true
$(terraform output -raw kubeconfig) && kubectl get nodes
```
