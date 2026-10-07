# Records are independent of VM provisioning; they only use the planned names and IPs.
resource "digitalocean_record" "node" {
  count = var.vm_count

  domain = var.dns_domain
  type   = "A"
  name   = local.node_names[count.index]
  value  = local.node_ips[count.index]
  ttl    = var.dns_ttl
}
