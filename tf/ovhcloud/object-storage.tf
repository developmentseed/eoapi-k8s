# Create Object Storage containers (buckets)
resource "ovh_cloud_project_object_storage_container" "containers" {
  for_each     = toset(var.object_storage_buckets)
  service_name = var.ovh_service_name
  name         = each.key
  region       = var.object_storage_region
}

# Create S3 credentials for Object Storage access
resource "ovh_cloud_project_object_storage_s3_credential" "s3_credentials" {
  count        = length(var.object_storage_buckets) > 0 ? 1 : 0
  service_name = var.ovh_service_name
  name         = "${var.cluster_name}-${var.cluster_version}-s3-credentials"
  region       = var.object_storage_region
}

# Create a Kubernetes secret with S3 credentials
resource "kubernetes_secret" "s3_credentials" {
  count = length(var.object_storage_buckets) > 0 ? 1 : 0
  
  metadata {
    name      = "ovh-s3-credentials"
    namespace = "default"
  }

  data = {
    access_key = ovh_cloud_project_object_storage_s3_credential.s3_credentials[0].access_key_id
    secret_key = ovh_cloud_project_object_storage_s3_credential.s3_credentials[0].secret_access_key
    endpoint   = "https://s3.${var.object_storage_region}.cloud.ovh.net"
    region     = var.object_storage_region
  }

  type = "Opaque"

  depends_on = [
    ovh_cloud_project_kube_nodepool.default_pool,
    time_sleep.wait_for_cluster
  ]
}

# Create a ConfigMap with bucket information
resource "kubernetes_config_map" "s3_buckets" {
  count = length(var.object_storage_buckets) > 0 ? 1 : 0
  
  metadata {
    name      = "ovh-s3-buckets"
    namespace = "default"
  }

  data = {
    buckets = join(",", var.object_storage_buckets)
    endpoint = "https://s3.${var.object_storage_region}.cloud.ovh.net"
    region   = var.object_storage_region
  }

  depends_on = [
    ovh_cloud_project_kube_nodepool.default_pool,
    time_sleep.wait_for_cluster
  ]
}