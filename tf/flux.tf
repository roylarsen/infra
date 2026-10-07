# Bootstraps Flux with the flux CLI because the kubeconfig only exists after the
# cluster is built. Needs `flux` on the machine running Terraform; the bootstrap
# is idempotent, so reapplying is safe.
resource "null_resource" "flux_bootstrap" {
  count = var.bootstrap_flux ? 1 : 0

  triggers = {
    kubeconfig = null_resource.kubeconfig.id
    owner      = var.github_owner
    repository = var.github_repository
    branch     = var.flux_branch
    path       = var.flux_path
  }

  lifecycle {
    precondition {
      condition     = var.github_token != ""
      error_message = "Set github_token (TF_VAR_github_token) to bootstrap Flux, or set bootstrap_flux=false."
    }
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      flux check --pre
      flux bootstrap github \
        --token-auth \
        --personal \
        --owner='${var.github_owner}' \
        --repository='${var.github_repository}' \
        --branch='${var.flux_branch}' \
        --path='${var.flux_path}'
    EOT

    environment = {
      KUBECONFIG   = abspath("${path.module}/kubeconfig")
      GITHUB_TOKEN = var.github_token
    }
  }

  depends_on = [null_resource.kubeconfig]
}
