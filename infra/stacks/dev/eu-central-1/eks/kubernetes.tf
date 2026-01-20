resource "time_sleep" "wait_for_cluster_access" {
  depends_on = [module.eks]

  create_duration = "60s"
}

resource "kubernetes_namespace_v1" "apps" {
  metadata {
    name = var.app_namespace
  }

  depends_on = [time_sleep.wait_for_cluster_access]
}

resource "kubernetes_config_map_v1" "hello_php" {
  metadata {
    name      = var.app_name
    namespace = kubernetes_namespace_v1.apps.metadata[0].name
  }

  data = {
    "index.php" = <<-EOT
<?php
echo "Hello from Amazon EKS!";
echo "<br>";
echo "Pod: " . gethostname();
?>
EOT
  }

  depends_on = [time_sleep.wait_for_cluster_access]
}

resource "kubernetes_deployment_v1" "hello_php" {
  metadata {
    name      = var.app_name
    namespace = kubernetes_namespace_v1.apps.metadata[0].name
    labels    = local.app_labels
  }

  spec {
    replicas = var.app_replicas

    selector {
      match_labels = local.app_labels
    }

    template {
      metadata {
        labels = local.app_labels
      }

      spec {
        container {
          name  = var.app_name
          image = "php:8.2-apache"

          port {
            container_port = 80
          }

          volume_mount {
            name       = "web"
            mount_path = "/var/www/html/index.php"
            sub_path   = "index.php"
          }
        }

        volume {
          name = "web"

          config_map {
            name = kubernetes_config_map_v1.hello_php.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [time_sleep.wait_for_cluster_access]
}

resource "kubernetes_service_v1" "hello_php" {
  metadata {
    name      = var.app_name
    namespace = kubernetes_namespace_v1.apps.metadata[0].name
    labels    = local.app_labels

    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type"   = "nlb"
      "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
    }
  }

  spec {
    selector = local.app_labels

    port {
      port        = 80
      target_port = 80
    }

    type = "LoadBalancer"
  }

  wait_for_load_balancer = true
  depends_on             = [time_sleep.wait_for_cluster_access]
}

resource "helm_release" "kubernetes_dashboard" {
  count = var.dashboard_enabled ? 1 : 0

  name       = "kubernetes-dashboard"
  repository = "https://kubernetes.github.io/dashboard/"
  chart      = "kubernetes-dashboard"
  version    = var.kubernetes_dashboard_chart_version

  namespace        = "kubernetes-dashboard"
  create_namespace = true

  set {
    name  = "service.type"
    value = "ClusterIP"
  }

  set {
    name  = "metricsScraper.enabled"
    value = "true"
  }

  depends_on = [time_sleep.wait_for_cluster_access]
}

resource "kubernetes_service_account_v1" "dashboard_admin" {
  count = var.dashboard_enabled ? 1 : 0

  metadata {
    name      = "dashboard-admin"
    namespace = "kubernetes-dashboard"
  }

  depends_on = [helm_release.kubernetes_dashboard]
}

resource "kubernetes_cluster_role_binding_v1" "dashboard_admin" {
  count = var.dashboard_enabled ? 1 : 0

  metadata {
    name = "dashboard-admin"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "dashboard-admin"
    namespace = "kubernetes-dashboard"
  }

  depends_on = [kubernetes_service_account_v1.dashboard_admin]
}
