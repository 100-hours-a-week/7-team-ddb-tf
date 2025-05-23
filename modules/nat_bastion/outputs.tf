output "instance_self_link" {
  description = "NAT_Bastion instance의 self_link"
  value       = google_compute_instance.nat_bastion.self_link
}

output "nat_ip" {
  description = " NAT_Bastion instance의 ip"
  value       = google_compute_address.nat_bastion.address
}

output "nat_bastion_tag" {
  description = "nat_bastion의 태그"
  value = local.bastion_tag
}