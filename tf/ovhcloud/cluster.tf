# Create OVH Managed Kubernetes cluster
resource "ovh_cloud_project_kube" "cluster" {
  service_name = var.ovh_service_name
  name         = "${var.cluster_name}-${var.cluster_version}"
  region       = var.region
  version      = var.kubernetes_version

  dynamic "private_network_configuration" {
    for_each = var.private_network_id != null ? [1] : []
    content {
      default_vrack_gateway              = ""
      private_network_routing_as_default = false
    }
  }

  kube_proxy_mode = "ipvs"
  
  update_policy = "ALWAYS_UPDATE"
}

# Create default node pool
resource "ovh_cloud_project_kube_nodepool" "default_pool" {
  service_name  = var.ovh_service_name
  kube_id       = ovh_cloud_project_kube.cluster.id
  name          = var.node_pool_name
  flavor_name   = var.node_pool_flavor
  desired_nodes = var.node_pool_desired_nodes
  max_nodes     = var.node_pool_max_nodes
  min_nodes     = var.node_pool_min_nodes
  autoscale     = var.node_pool_autoscale

  # Anti-affinity ensures nodes are spread across different hosts
  anti_affinity = true
  
  # Monthly billing is usually cheaper for long-running workloads
  monthly_billed = false
}

# Get kubeconfig for the cluster
data "ovh_cloud_project_kube_config" "cluster_config" {
  service_name = var.ovh_service_name
  kube_id      = ovh_cloud_project_kube.cluster.id
}

# Configure Kubernetes provider
provider "kubernetes" {
  host                   = yamldecode(data.ovh_cloud_project_kube_config.cluster_config.content)["clusters"][0]["cluster"]["server"]
  client_certificate     = base64decode(yamldecode(data.ovh_cloud_project_kube_config.cluster_config.content)["users"][0]["user"]["client-certificate-data"])
  client_key             = base64decode(yamldecode(data.ovh_cloud_project_kube_config.cluster_config.content)["users"][0]["user"]["client-key-data"])
  cluster_ca_certificate = base64decode(yamldecode(data.ovh_cloud_project_kube_config.cluster_config.content)["clusters"][0]["cluster"]["certificate-authority-data"])
}

# Wait for cluster to be ready
resource "time_sleep" "wait_for_cluster" {
  depends_on = [ovh_cloud_project_kube_nodepool.default_pool]
  create_duration = "60s"
}