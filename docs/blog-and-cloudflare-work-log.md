# Blog and Cloudflare work log

This document records the infrastructure and blog work discussed in the
November 2026 Copilot session. It covers the Cloudflare Tunnel setup, migration
of the Pelican blog from DigitalOcean App Platform to k3s, monitoring, later
content updates, and issues encountered. No tokens or secret values are
included.

## Current status

- The public blog is served by two k3s pods through the existing Cloudflare
  Tunnel. The Flux `blag` Kustomization was Ready at the last verification.
- The current deployment image is pinned in
  `flux/clusters/k3s/blag/blag.yaml` to
  `ghcr.io/roylarsen/blag:6b7699167b5fc990bd15244492e649697d4e434e`.
- GitHub Actions publishes a new image from the blog repository, but it does
  not update the image pin in the infra repository. Image promotion to k3s has
  therefore been a separate infra Git change.
- The old DigitalOcean App Platform app and its committed `blag/output/` were
  retained as a rollback. The planned post-soak-period decommission has not
  been done.

## k3s cluster buildout

### Compute and Kubernetes

- Added `scripts/create-ubuntu-template.sh` to resolve the current Ubuntu
  Server cloud image through Canonical's image-stream metadata and create a
  cloud-init Proxmox template named `ubuntu-latest` (VM ID 9000).
- Added Terraform in `tf/` to full-clone that template into three VMs:
  `k3s-node-1` (VM 200, server/control plane) and `k3s-node-2`/`k3s-node-3`
  (VMs 201-202, agents). Each is configured for 2 vCPUs, 4 GiB RAM, a 20 GiB
  root disk, cloud-init, a generated SSH key, and static LAN addresses
  `192.168.1.201`-`192.168.1.203`.
- Terraform installs k3s over SSH, creates a random cluster join token, waits
  for node registration, and fetches a kubeconfig. The SSH private key,
  kubeconfig, and Terraform state are gitignored; state contains sensitive
  generated values and must stay private.
- Added DigitalOcean A records for the nodes in the existing
  `xhousebreakx.org` zone.
- Flux bootstraps from the `roylarsen/infra` repository and reconciles
  `flux/clusters/k3s`. The GitOps configuration installs:
  - MetalLB with an L2 address pool for LAN LoadBalancer services.
  - Istio base, control plane, and ingress gateway.
  - cert-manager with Let's Encrypt production/staging issuers and DNS-01
    credentials stored in SOPS-encrypted Secrets.
  - kube-prometheus-stack (Prometheus, Alertmanager, Grafana) with persistent
    local-path volumes and Istio dashboards.
  - external-dns for the DigitalOcean zone.
  - Cloudflare Tunnel connectors for public service access.
  - SOPS/age decryption for encrypted Kubernetes Secret manifests.
- k3s has its built-in ServiceLB and Traefik disabled so MetalLB and Istio own
  the cluster's load-balancer and ingress responsibilities.

### Cluster buildout issues

- The initial Proxmox provider version (2.9.14) panicked against Proxmox VE
  8.4. The provider was upgraded to `3.0.2-rc10`, and Terraform itself was
  upgraded from 0.13.5 to 1.16.5.
- Proxmox's TLS certificate is valid for its `.org` hostname, not its `.local`
  hostname. Terraform API access uses the certificate-matching name; TLS
  verification remains enabled by default.
- Initial template clones lacked usable disk/network configuration. Explicit
  disk, cloud-init drive, network, boot, serial, and VGA blocks were added.
- The Proxmox host initially lacked `/dev/kvm`, so VMs ran under slow software
  emulation and cluster startup took a long time. The user enabled hardware
  virtualization; Terraform now defaults to KVM with CPU type `host`. Memory
  was raised to 4 GiB per node after the overloaded control plane caused
  Kubernetes API and metrics trouble.
- Cloud-init can exit with status 2 when it has completed with recoverable
  warnings. Terraform now accepts that status and waits for k3s nodes to
  register before proceeding.
- The k3s join token is passed to the VMs through a temporary file rather than
  being interpolated into logged provisioner commands. It is still present in
  Terraform state, so state storage and backups need protection.
- Early Flux bootstrap attempts encountered an invalid GitHub PAT, a missing
  target branch, and outdated local Flux/kubectl clients. The token and branch
  were corrected, and Flux is now syncing the configured branch. Later, a PAT
  rotation caused Flux Git authentication to fail until the in-cluster
  `flux-system` Secret was updated.

## Work completed

### Existing tunnel and Plex

- Reused the existing `home` Cloudflare Tunnel rather than creating another
  tunnel. Its connector runs in k3s as two `cloudflared` replicas, with the
  connector token stored in a SOPS-encrypted Kubernetes Secret.
- Added Terraform management for the existing tunnel's ingress configuration
  and the proxied `home.roylarsen.xyz` DNS record. Existing Plex ingress was
  retained. The final ingress has a 404 catch-all.
- Routed both `home.roylarsen.xyz` and `plex.roylarsen.xyz` to the Plex service.
  The working origin is `plex.xhousebreakx.local:32400`.

### Pelican container and publishing

In `roylarsen/roylarsen.xyz`:

- Added pinned Pelican/Markdown dependencies and changed the publish URL to
  `https://www.roylarsen.xyz`.
- Added a multi-stage Dockerfile: Pelican builds the static site, then
  `nginxinc/nginx-unprivileged` serves it on port 8080.
- Added nginx behavior for apex and `blog` redirects to `www`, legacy
  Ghost-style `/slug/` paths, cache headers, compression, and `/healthz`.
- Added `.dockerignore` and `.github/workflows/blag.yaml`. Pull requests build
  without publishing. Pushes to `main` that change `blag/**` publish
  `ghcr.io/roylarsen/blag` tagged with the commit SHA and `latest`.
- Left the committed `blag/output/` intact to preserve the DigitalOcean
  rollback.
- Merged PR [#36](https://github.com/roylarsen/roylarsen.xyz/pull/36) for
  containerization and image publishing.

### k3s deployment and Cloudflare cutover

In `roylarsen/infra`:

- Added `flux/clusters/k3s/blag/` with a Namespace, Deployment, Service,
  PodDisruptionBudget, and Flux Kustomization. The Deployment runs two
  replicas, spreads them across nodes, uses a read-only root filesystem and
  health probes, and pins an image by commit SHA.
- Added tunnel routes for `blag`, `www`, `blog`, and the zone apex to the
  in-cluster service at `blag.blag.svc.cluster.local:8080`.
- Added a proxied `blag` staging DNS record. Imported the existing `www`,
  `blog`, and apex records into Terraform, then pointed them at the tunnel.
  Existing MX and TXT records were left unchanged.
- The apex and `blog` redirect to `www`; all three public hostnames were
  verified over HTTPS. The DigitalOcean app was retained for rollback.

### Prometheus metrics

- Added nginx `stub_status` on port 8081 for in-cluster scraping.
- Added the `nginx-prometheus-exporter` sidecar on port 9113, a Service metrics
  port, and a `ServiceMonitor`. The `blag` Flux Kustomization depends on
  `monitoring`.
- Prometheus returned `nginx_up == 1` and request counters for both pods.
  `/stub_status` through the public tunnel returned 404; the status endpoint is
  not routed publicly.
- Merged PR [#37](https://github.com/roylarsen/roylarsen.xyz/pull/37). No
  Grafana dashboard was added.

### Subsequent page and content work

- Published several requested updates to the blog's About page, including its
  location/age copy, professional interests, SaaS wording, and technology links
  (FluxCD, Proxmox, k3s, Cloudflare Tunnel). The current page was checked live.
- DNS lookup for `www.roylarsen.xyz` returned Cloudflare proxy addresses
  `104.21.50.49` and `172.67.157.28`, both announced by Cloudflare (AS13335).
- Created and pushed branch `haters-guide-to-ai-1` with an uncommitted-to-main
  article draft committed as `d420b7d`. It remains unpublished and no PR was
  created.

## Problems encountered and resolutions

- **Local image building unavailable:** Docker was installed, but the Docker
  daemon was not running and there was no sudo access. Pelican built in a local
  Python virtual environment; the image itself was built by GitHub Actions.
- **Local nginx test binary initially would not execute:** extracting the image
  layers lost executable permissions. Restoring those permissions allowed
  `nginx -t` and HTTP checks to run. Redirects, legacy paths, caching,
  compression, health checks, and 404 behavior were verified.
- **GitHub token lacked workflow permission:** the first push of the Actions
  workflow was rejected. After the token was updated with workflow scope, the
  workflow pushed successfully and CI published the image.
- **SSH remote did not use the HTTPS token header:** a push to the blog repo
  initially failed because its configured remote was SSH. Pushing to the HTTPS
  URL with an ephemeral authorization header worked.
- **Flux Git access broke after the token rotation:** Flux reported an invalid
  GitHub token. The `flux-system` Secret was updated in the cluster and Flux
  resumed syncing. A future PAT rotation must also update this Secret.
- **Incorrect Plex origin caused 502 responses:** the `.org` hostname resolved
  to an unreachable LAN address. Changing the tunnel origin to the working
  `.local` Plex hostname fixed it.
- **Terraform CLI imports tried to contact Proxmox:** a hostname/certificate
  mismatch prevented those import commands from completing. Declarative
  Terraform import blocks were used instead; the three DNS records were
  imported and changed in place, with nothing destroyed.
- **`flux.io` was not the Flux project site:** it redirected to a domain-for-sale
  page. The About page link was corrected to `https://fluxcd.io`.

## Follow-ups and risks

- **DigitalOcean decommission is pending.** After a suitable soak period,
  remove the old App Platform app, stale DigitalOcean DNS/IaC and deployment
  workflow, then update the blog README. Keep the existing rollback until that
  work is explicitly approved.
- **Image deployment is not fully automated.** GitHub Actions publishes the
  image; the Deployment's SHA still has to be changed in the infra repo.
  Flux image automation controllers and image policies have not been set up.
- **External-dns still uses DigitalOcean.** It is configured for
  `xhousebreakx.org`, not Cloudflare. The existing Cloudflare SOPS Secret is a
  Tunnel connector token, not a DNS API token, and cannot be reused for
  external-dns. Cloudflare automation would need a separate scoped API token
  and provider configuration.
- **Nginx security update needs review.** During the November 23 check, the
  running nginx version was 1.31.7 and the
  `nginxinc/nginx-unprivileged:1.31-alpine` tag also resolved to 1.31.7, while
  nginx.org listed fixes in later 1.31 releases. The official nginx 1.31.10
  Alpine image existed, but it was not substituted because compatibility with
  the unprivileged runtime configuration had not been tested. Recheck the
  current unprivileged image and advisories, then rebuild and redeploy if
  needed.
- **Home/cluster availability is now blog availability:** an outage affecting
  the home network, cluster, or tunnel can take down the blog. The DigitalOcean
  app remains the rollback option until decommission.
- A prior audit noted sensitive artifacts in the old infra `main` history and
  recommended rotating the DigitalOcean DNS token. No credential values are
  recorded here; rotation status was not confirmed. Keep the SOPS age private
  key backed up.
