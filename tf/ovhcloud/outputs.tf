# Cluster outputs
output "cluster_id" {
  description = "ID of the OVH Managed Kubernetes cluster"
  value       = ovh_cloud_project_kube.cluster.id
}

output "cluster_name" {
  description = "Name of the OVH Managed Kubernetes cluster"
  value       = ovh_cloud_project_kube.cluster.name
}

output "cluster_url" {
  description = "URL of the OVH Managed Kubernetes cluster"
  value       = ovh_cloud_project_kube.cluster.url
}

output "cluster_version" {
  description = "Version of the OVH Managed Kubernetes cluster"
  value       = ovh_cloud_project_kube.cluster.version
}

output "cluster_status" {
  description = "Status of the OVH Managed Kubernetes cluster"
  value       = ovh_cloud_project_kube.cluster.status
}

# Node pool outputs
output "node_pool_id" {
  description = "ID of the default node pool"
  value       = ovh_cloud_project_kube_nodepool.default_pool.id
}

output "node_pool_status" {
  description = "Status of the default node pool"
  value       = ovh_cloud_project_kube_nodepool.default_pool.status
}

output "node_pool_current_nodes" {
  description = "Current number of nodes in the default node pool"
  value       = ovh_cloud_project_kube_nodepool.default_pool.current_nodes
}

# Kubeconfig output (sensitive)
output "kubeconfig" {
  description = "Kubeconfig file content for the cluster"
  value       = data.ovh_cloud_project_kube_config.cluster_config.content
  sensitive   = true
}

# Ingress controller load balancer IP
output "ingress_ip" {
  description = "External IP address of the ingress controller load balancer"
  value       = try(data.kubernetes_service.ingress_service.status[0].load_balancer[0].ingress[0].ip, "pending")
  depends_on  = [helm_release.ingress]
}

# Object Storage outputs
output "object_storage_buckets" {
  description = "List of created Object Storage containers"
  value       = [for container in ovh_cloud_project_object_storage_container.containers : container.name]
}

output "s3_endpoint" {
  description = "S3-compatible endpoint for Object Storage"
  value       = length(var.object_storage_buckets) > 0 ? "https://s3.${var.object_storage_region}.cloud.ovh.net" : null
}

output "s3_access_key" {
  description = "S3 access key for Object Storage"
  value       = length(var.object_storage_buckets) > 0 ? ovh_cloud_project_object_storage_s3_credential.s3_credentials[0].access_key_id : null
  sensitive   = true
}

output "s3_secret_key" {
  description = "S3 secret key for Object Storage"
  value       = length(var.object_storage_buckets) > 0 ? ovh_cloud_project_object_storage_s3_credential.s3_credentials[0].secret_access_key : null
  sensitive   = true
}

# Data source for ingress service to get external IP
data "kubernetes_service" "ingress_service" {
  metadata {
    name      = "ingress-ingress-nginx-controller"
    namespace = "support"
  }
  depends_on = [helm_release.ingress]
}

# Region and project information
output "ovh_region" {
  description = "OVH region where resources are created"
  value       = var.region
}

output "ovh_service_name" {
  description = "OVH Cloud Project ID (service name)"
  value       = var.ovh_service_name
}