output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "EKS Kubernetes version."
  value       = module.eks.cluster_version
}

output "kubeconfig_command" {
  description = "Command to update local kubeconfig for this cluster."
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region} --alias ${module.eks.cluster_name}"
}

output "kubectl_context" {
  description = "kubectl context name (same as cluster name)."
  value       = module.eks.cluster_name
}

output "app_url" {
  description = "Public URL for the hello PHP app (after LoadBalancer is ready)."
  value       = local.app_url
}

output "dashboard_url" {
  description = "Local URL for Kubernetes Dashboard when port-forward is running."
  value       = var.dashboard_enabled ? "https://localhost:8443/" : ""
}

output "dashboard_token_command" {
  description = "Command to obtain a login token for Kubernetes Dashboard."
  value       = var.dashboard_enabled ? "kubectl -n kubernetes-dashboard create token dashboard-admin" : ""
}
