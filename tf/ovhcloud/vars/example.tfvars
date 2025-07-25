# OVH API endpoint - ovh-eu for Europe, ovh-ca for Canada, ovh-us for US
ovh_endpoint = "ovh-eu"

# Your OVH Cloud Project ID (service name)
# You can find this in the OVH Control Panel under Cloud Projects
ovh_service_name = "your-project-id-here"

# OVH region - GRA (Gravelines), SBG (Strasbourg), BHS (Beauharnois), WAW (Warsaw)
region = "GRA"

# Cluster configuration
cluster_name = "eoapi"
cluster_version = "v1"
kubernetes_version = "1.28"

# Node pool configuration
node_pool_flavor = "b2-7"  # 2 vCPU, 7GB RAM
node_pool_desired_nodes = 1
node_pool_max_nodes = 5
node_pool_min_nodes = 0



# Object Storage configuration
object_storage_region = "GRA"
object_storage_buckets = ["eoapi-data-store"]

# Optional: Use private networking
# private_network_id = "your-private-network-id"
# subnet_id = "your-subnet-id"
# enable_private_nodes = true