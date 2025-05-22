output "vpc_self_link" {
  value = module.network.vpc_self_link
}

output "subnet_cidrs" {
  value = module.network.subnet_cidrs
}

output "debug_subnets" {
  value = module.network.subnets
}