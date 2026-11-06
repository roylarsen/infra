import {
  for_each = {
    www  = "9e6bf42d8fc3d3f9d832068d57aefc74"
    blog = "442d83245ba810ead178c629d77d7965"
    apex = "3ca84ed742ab51c75cff10ba575599d2"
  }
  to = cloudflare_dns_record.blog[each.key]
  id = "${data.cloudflare_zone.this.zone_id}/${each.value}"
}
