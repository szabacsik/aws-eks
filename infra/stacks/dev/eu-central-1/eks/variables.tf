variable "project_name" {
  type        = string
  description = "Project identifier used for naming and tagging."
  default     = "aws-eks-learning"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "project_name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  type        = string
  description = "Environment name (dev, stage, prod)."
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "owner" {
  type        = string
  description = "Tag value for Owner."
  default     = "unknown"
}

variable "aws_region" {
  type        = string
  description = "AWS region for the stack."
  default     = "eu-central-1"
}

variable "kubernetes_version" {
  type        = string
  description = "EKS Kubernetes version."
  default     = "1.30"

  validation {
    condition     = can(regex("^1\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must look like 1.xx (example: 1.30)."
  }
}

variable "cluster_endpoint_public_access_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to reach the EKS public endpoint."
  default     = ["0.0.0.0/0"]
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block."
  default     = "10.0.0.0/16"
}

variable "az_count" {
  type        = number
  description = "Number of availability zones to use."
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be between 2 and 3."
  }
}

variable "node_instance_type" {
  type        = string
  description = "Instance type for EKS managed nodes."
  default     = "t3.small"
}

variable "node_capacity_type" {
  type        = string
  description = "Capacity type for nodes (ON_DEMAND or SPOT)."
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "node_desired_size" {
  type        = number
  description = "Desired node count."
  default     = 2
}

variable "node_min_size" {
  type        = number
  description = "Minimum node count."
  default     = 2
}

variable "node_max_size" {
  type        = number
  description = "Maximum node count."
  default     = 2
}

variable "app_namespace" {
  type        = string
  description = "Kubernetes namespace for the demo app."
  default     = "apps"
}

variable "app_name" {
  type        = string
  description = "Kubernetes app name for the demo app."
  default     = "hello-php"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.app_name))
    error_message = "app_name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "app_replicas" {
  type        = number
  description = "Replica count for the demo app."
  default     = 1
}

variable "dashboard_enabled" {
  type        = bool
  description = "Deploy Kubernetes Dashboard via Helm."
  default     = true
}

variable "kubernetes_dashboard_chart_version" {
  type        = string
  description = "Helm chart version for Kubernetes Dashboard."
  default     = "7.0.0"
}

variable "extra_tags" {
  type        = map(string)
  description = "Additional tags applied via default_tags."
  default     = {}
}
