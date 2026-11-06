variable "cloudflare_zone_name" {
  description = "Existing Cloudflare zone that hosts the tunnel hostname."
  type        = string
  default     = "roylarsen.xyz"
}

variable "cloudflare_tunnel_id" {
  description = "ID of the existing Cloudflare tunnel (the one the in-cluster cloudflared connects to)."
  type        = string
  default     = "cf1ee413-2a43-4dc7-997f-18c3a17946b1"
}

variable "cloudflare_tunnel_subdomain" {
  description = "Record name inside the zone that is routed through the tunnel."
  type        = string
  default     = "home"
}

variable "cloudflare_tunnel_origin" {
  description = "Local service the tunnel forwards to."
  type        = string
  default     = "http://plex.xhousebreakx.local:32400"
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
  cloudflare_tunnel_target = "${var.cloudflare_tunnel_id}.cfargotunnel.com"
}

# The tunnel itself already exists and its connector runs in the cluster; only its
# ingress config and DNS are managed here.
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "plex" {
  account_id = local.cloudflare_account_id
  tunnel_id  = var.cloudflare_tunnel_id

  config = {
    ingress = [
      {
        hostname = local.cloudflare_tunnel_fqdn
        service  = var.cloudflare_tunnel_origin
      },
      {
        hostname = "plex.roylarsen.xyz"
        service  = "http://plex.xhousebreakx.local:32400"
      },
      {
        service = "http_status:404"
      },
    ]
    warp-routing = {
      enabled = false
    }
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
