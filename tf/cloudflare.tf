variable "cloudflare_zone_name" {
  description = "Existing Cloudflare zone that hosts the tunnel hostname."
  type        = string
  default     = "roylarsen.xyz"
}

variable "cloudflare_tunnel_name" {
  description = "Name of the Terraform-managed Cloudflare tunnel."
  type        = string
  default     = "plex"
}

variable "cloudflare_tunnel_subdomain" {
  description = "Record name inside the zone that is routed through the tunnel."
  type        = string
  default     = "home"
}

variable "cloudflare_tunnel_origin" {
  description = "Local service the tunnel forwards to."
  type        = string
  default     = "http://plex.xhousebreakx.org:32400"
}

# The zone already exists; it is only looked up here.
data "cloudflare_zone" "this" {
  filter = {
    name = var.cloudflare_zone_name
  }
}

locals {
  cloudflare_account_id    = data.cloudflare_zone.this.account.id
  cloudflare_tunnel_fqdn   = "${var.cloudflare_tunnel_subdomain}.${var.cloudflare_zone_name}"
  cloudflare_tunnel_target = "${cloudflare_zero_trust_tunnel_cloudflared.plex.id}.cfargotunnel.com"
}

# Remotely managed tunnel: Cloudflare stores the ingress rules defined below.
resource "cloudflare_zero_trust_tunnel_cloudflared" "plex" {
  account_id = local.cloudflare_account_id
  name       = var.cloudflare_tunnel_name
  config_src = "cloudflare"
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "plex" {
  account_id = local.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.plex.id

  config = {
    ingress = [
      {
        hostname = local.cloudflare_tunnel_fqdn
        service  = var.cloudflare_tunnel_origin
      },
      {
        service = "http_status:404"
      },
    ]
  }
}

resource "cloudflare_dns_record" "tunnel" {
  zone_id = data.cloudflare_zone.this.zone_id
  name    = var.cloudflare_tunnel_subdomain
  type    = "CNAME"
  content = local.cloudflare_tunnel_target
  proxied = true
  ttl     = 1
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "plex" {
  account_id = local.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.plex.id
}
