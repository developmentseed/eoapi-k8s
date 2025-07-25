# Configure Helm provider
provider "helm" {
  kubernetes {
    host                   = yamldecode(data.ovh_cloud_project_kube_config.cluster_config.content)["clusters"][0]["cluster"]["server"]
    client_certificate     = base64decode(yamldecode(data.ovh_cloud_project_kube_config.cluster_config.content)["users"][0]["user"]["client-certificate-data"])
    client_key             = base64decode(yamldecode(data.ovh_cloud_project_kube_config.cluster_config.content)["users"][0]["user"]["client-key-data"])
    cluster_ca_certificate = base64decode(yamldecode(data.ovh_cloud_project_kube_config.cluster_config.content)["clusters"][0]["cluster"]["certificate-authority-data"])
  }
}

# Install cluster autoscaler
resource "helm_release" "autoscaler" {
  name             = "cluster-autoscaler"
  repository       = "https://kubernetes.github.io/autoscaler"
  chart            = "cluster-autoscaler"
  version          = var.cluster_autoscaler_version
  namespace        = "cluster-autoscaler"
  create_namespace = true

  set {
    name  = "autoDiscovery.clusterName"
    value = "${var.cluster_name}-${var.cluster_version}"
  }

  set {
    name  = "cloudProvider"
    value = "ovhcloud"
  }

  set {
    name  = "ovhcloud.projectID"
    value = var.ovh_service_name
  }

  set {
    name  = "ovhcloud.region"
    value = var.region
  }

  wait = true

  depends_on = [
    ovh_cloud_project_kube_nodepool.default_pool,
    time_sleep.wait_for_cluster
  ]
}

# Install nginx ingress controller
resource "helm_release" "ingress" {
  name             = "ingress"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "support"
  create_namespace = true
  version          = var.nginx_ingress_version

  set {
    name  = "controller.enableLatencyMetrics"
    value = true
  }

  set {
    name  = "controller.metrics.enabled"
    value = true
  }

  set {
    name  = "controller.metrics.service.annotations.prometheus\\.io/scrape"
    value = "true"
    type  = "string"
  }

  set {
    name  = "controller.metrics.service.annotations.prometheus\\.io/port"
    value = "10254"
    type  = "string"
  }

  # Use LoadBalancer service type for OVHcloud
  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  wait = true
  depends_on = [
    ovh_cloud_project_kube_nodepool.default_pool,
    time_sleep.wait_for_cluster
  ]
}

# Install cert-manager
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  version          = var.cert_manager_version

  set {
    # We can manage CRDs from inside Helm itself, no need for a separate kubectl apply
    name  = "installCRDs"
    value = true
  }
  
  wait = true
  depends_on = [
    ovh_cloud_project_kube_nodepool.default_pool,
    time_sleep.wait_for_cluster
  ]
}

