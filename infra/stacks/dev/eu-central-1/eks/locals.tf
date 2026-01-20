locals {
  name_prefix = "${var.project_name}-${var.environment}"

  cluster_name = "${local.name_prefix}-eks"
  vpc_name     = "${local.name_prefix}-vpc"

  app_labels = {
    app = var.app_name
  }

  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  public_subnet_cidrs = [
    for idx, _az in local.azs : cidrsubnet(var.vpc_cidr, 8, idx)
  ]

  default_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = var.owner
    },
    var.extra_tags
  )

  app_lb_hostname = try(kubernetes_service_v1.hello_php.status[0].load_balancer[0].ingress[0].hostname, "")
  app_lb_ip       = try(kubernetes_service_v1.hello_php.status[0].load_balancer[0].ingress[0].ip, "")
  app_host        = local.app_lb_hostname != "" ? local.app_lb_hostname : local.app_lb_ip
  app_url         = local.app_host != "" ? "http://${local.app_host}" : ""
}
