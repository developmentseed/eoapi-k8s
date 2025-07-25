variable "ovh_endpoint" {
  type        = string
  default     = "ovh-eu"
  description = <<-EOT
  OVH API endpoint to use. Available endpoints:
  - ovh-eu for OVH Europe API
  - ovh-ca for OVH Canada API
  - ovh-us for OVH US API
  EOT
  
  validation {
    condition     = contains(["ovh-eu", "ovh-ca", "ovh-us"], var.ovh_endpoint)
    error_message = "The ovh_endpoint value must be one of: ovh-eu, ovh-ca, ovh-us."
  }
}

variable "ovh_service_name" {
  type        = string
  description = <<-EOT
  OVH Cloud Project ID (service name) where resources will be created
  EOT
}

variable "region" {
  type        = string
  default     = "GRA"
  description = <<-EOT
  OVH region to perform all our operations in.
  Common regions: GRA (Gravelines), SBG (Strasbourg), BHS (Beauharnois), WAW (Warsaw)
  EOT
}

variable "cluster_name" {
  type        = string
  description = <<-EOT
  Name of OVH Managed Kubernetes cluster to create
  EOT
}

variable "cluster_version" {
  type        = string
  default     = "v1"
  description = <<-EOT
  A version string that we append to certain resources to make them unique
  EOT
}

variable "kubernetes_version" {
  type        = string
  default     = "1.28"
  description = <<-EOT
  Kubernetes version to use for the cluster
  EOT
}

variable "ovh_tags" {
  type        = map(string)
  default     = {}
  description = <<-EOT
  (Optional) OVH resource tags.
  EOT
}

variable "node_pool_name" {
  type        = string
  default     = "default-pool"
  description = <<-EOT
  Name of the default node pool
  EOT
}

variable "node_pool_flavor" {
  type        = string
  default     = "b2-7"
  description = <<-EOT
  OVH instance flavor for worker nodes.
  Common flavors: b2-7, b2-15, b2-30, c2-7, c2-15, c2-30
  EOT
}

variable "node_pool_desired_nodes" {
  type        = number
  default     = 1
  description = <<-EOT
  Desired number of nodes in the default node pool
  EOT
}

variable "node_pool_max_nodes" {
  type        = number
  default     = 10
  description = <<-EOT
  Maximum number of nodes in the default node pool
  EOT
}

variable "node_pool_min_nodes" {
  type        = number
  default     = 0
  description = <<-EOT
  Minimum number of nodes in the default node pool
  EOT
}

variable "node_pool_autoscale" {
  type        = bool
  default     = true
  description = <<-EOT
  Enable autoscaling for the default node pool
  EOT
}

variable "enable_private_nodes" {
  type        = bool
  default     = false
  description = <<-EOT
  Whether to create private nodes (nodes without public IP)
  EOT
}

variable "private_network_id" {
  type        = string
  default     = null
  description = <<-EOT
  (Optional) ID of existing private network to use for the cluster.
  If not provided, cluster will use public networking.
  EOT
}

variable "subnet_id" {
  type        = string
  default     = null
  description = <<-EOT
  (Optional) ID of existing subnet to use for the cluster.
  Required if private_network_id is provided.
  EOT
}



variable "cluster_autoscaler_version" {
  type        = string
  default     = "9.35.0"
  description = <<-EOT
  Version of cluster autoscaler helm chart to install.
  EOT
}

variable "cert_manager_version" {
  type        = string
  default     = "1.14.3"
  description = <<-EOT
  Version of cert-manager helm chart to install.
  EOT
}

variable "nginx_ingress_version" {
  type        = string
  default     = "4.8.3"
  description = <<-EOT
  Version of the nginx ingress controller chart to install
  EOT
}



variable "object_storage_buckets" {
  type        = list(string)
  default     = []
  description = <<-EOT
  List of OVH Object Storage bucket names to create
  EOT
}

variable "object_storage_region" {
  type        = string
  default     = "GRA"
  description = <<-EOT
  Region for Object Storage buckets
  EOT
}