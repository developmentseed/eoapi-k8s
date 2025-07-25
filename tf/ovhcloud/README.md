# OVHcloud OpenTofu Configuration

This directory contains OpenTofu configuration for deploying a Kubernetes cluster on OVHcloud using OVH Managed Kubernetes Service.

## What This Creates

- OVH Managed Kubernetes cluster
- Default node pool with autoscaling
- Essential Helm charts (nginx-ingress, cert-manager, cluster-autoscaler)

- OVH Object Storage containers (S3-compatible buckets)
- Kubernetes secrets for Object Storage access

## Prerequisites

1. **OVHcloud Account**: You need an active OVHcloud account with a Cloud Project
2. **OpenTofu**: Version 1.7.4 or later
3. **OVH API Credentials**: API keys for programmatic access
4. **kubectl**: For cluster management

## Authentication Setup

### 1. Create OVH API Credentials

1. Visit the OVH API token creation page for your region:
   - **Europe**: https://api.ovh.com/createToken/
   - **Canada**: https://ca.api.ovh.com/createToken/
   - **US**: https://api.us.ovhcloud.com/createToken/

2. Set the following permissions for your Cloud Project:
   ```
   GET    /cloud/project
   GET    /cloud/project/*
   POST   /cloud/project/*
   PUT    /cloud/project/*
   DELETE /cloud/project/*
   ```

3. Export the credentials as environment variables:
   ```bash
   export OVH_ENDPOINT=ovh-eu           # ovh-eu, ovh-ca, or ovh-us
   export OVH_APPLICATION_KEY=your_application_key
   export OVH_APPLICATION_SECRET=your_application_secret
   export OVH_CONSUMER_KEY=your_consumer_key
   ```

### 2. Find Your Cloud Project ID

You'll need your OVH Cloud Project ID (service name):
1. Log into the [OVH Control Panel](https://www.ovh.com/manager/)
2. Go to "Public Cloud" → "Projects"
3. Copy the Project ID (usually a long alphanumeric string)

## Quick Start

### 1. Setup Backend Storage

Create an Object Storage container for OpenTofu state:

```bash
# Copy and customize backend configuration
cp backend-configs/example.tfbackend backend-configs/my-project.tfbackend

# Edit the file to set your bucket name and region
# bucket = "my-terraform-state-bucket"
# region = "GRA"
# endpoint = "https://s3.gra.cloud.ovh.net"
```

### 2. Configure Variables

```bash
# Copy and customize variables
cp vars/example.tfvars vars/my-project.tfvars

# Edit vars/my-project.tfvars with your settings:
# - ovh_service_name = "your-project-id"
# - region = "GRA"  # or SBG, BHS, WAW
# - cluster_name = "my-cluster"
```

### 3. Initialize and Deploy

```bash
# Initialize OpenTofu
tofu init -backend-config=backend-configs/my-project.tfbackend

# Create workspace
tofu workspace create my-project

# Plan deployment
tofu plan -var-file=vars/my-project.tfvars

# Deploy infrastructure
tofu apply -var-file=vars/my-project.tfvars
```

### 4. Access Your Cluster

```bash
# Get kubeconfig
tofu output -raw kubeconfig > kubeconfig.yaml
export KUBECONFIG=./kubeconfig.yaml

# Verify access
kubectl get nodes
```

## Configuration Variables

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `ovh_service_name` | OVH Cloud Project ID | `"1a2b3c4d5e6f7g8h"` |
| `cluster_name` | Name for your cluster | `"eoapi"` |

### Important Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ovh_endpoint` | `"ovh-eu"` | OVH API endpoint (ovh-eu, ovh-ca, ovh-us) |
| `region` | `"GRA"` | OVH region (GRA, SBG, BHS, WAW) |
| `node_pool_flavor` | `"b2-7"` | Instance type for worker nodes |
| `node_pool_max_nodes` | `10` | Maximum nodes in autoscaling group |
| `kubernetes_version` | `"1.28"` | Kubernetes version to deploy |

| `object_storage_buckets` | `[]` | List of S3 buckets to create |

### Available OVH Instance Flavors

| Flavor | vCPU | RAM | Use Case |
|--------|------|-----|----------|
| `b2-7` | 2 | 7GB | General purpose, small workloads |
| `b2-15` | 4 | 15GB | General purpose, medium workloads |
| `b2-30` | 8 | 30GB | General purpose, large workloads |
| `c2-7` | 2 | 7GB | CPU-optimized |
| `c2-15` | 4 | 15GB | CPU-optimized |
| `r2-15` | 2 | 15GB | Memory-optimized |
| `r2-30` | 4 | 30GB | Memory-optimized |

### Available OVH Regions

| Region Code | Location | Description |
|-------------|----------|-------------|
| `GRA` | Gravelines, France | Europe West |
| `SBG` | Strasbourg, France | Europe Central |
| `BHS` | Beauharnois, Canada | North America East |
| `WAW` | Warsaw, Poland | Europe Central |

## Outputs

After deployment, the following outputs are available:

```bash
# Cluster information
tofu output cluster_id
tofu output cluster_name
tofu output cluster_url

# Access information
tofu output kubeconfig          # Sensitive
tofu output ingress_ip

# Storage information
tofu output object_storage_buckets
tofu output s3_endpoint
tofu output s3_access_key       # Sensitive
tofu output s3_secret_key       # Sensitive
```

## Installed Components

### Core Components
- **OVH Managed Kubernetes**: Fully managed control plane
- **Cluster Autoscaler**: Automatic node scaling
- **nginx-ingress**: Ingress controller with LoadBalancer
- **cert-manager**: Automatic SSL certificate management



## Object Storage Integration

The configuration can create S3-compatible Object Storage buckets:

```hcl
object_storage_buckets = [
  "my-data-bucket",
  "my-backup-bucket"
]
```

Kubernetes secrets are automatically created with S3 credentials:
- Secret name: `ovh-s3-credentials`
- ConfigMap name: `ovh-s3-buckets`

## Networking

### Load Balancer
The nginx-ingress controller automatically creates an OVHcloud Load Balancer. The external IP is available via:

```bash
tofu output ingress_ip
```

### Private Networking (Optional)
You can use OVH Private Networks:

```hcl
private_network_id = "your-private-network-id"
subnet_id = "your-subnet-id"
enable_private_nodes = true
```



## Troubleshooting

### Common Issues

1. **Authentication Error**
   ```bash
   # Verify environment variables are set
   echo $OVH_APPLICATION_KEY
   echo $OVH_APPLICATION_SECRET
   echo $OVH_CONSUMER_KEY
   echo $OVH_ENDPOINT
   ```

2. **Invalid Project ID**
   ```bash
   # List available projects
   curl -X GET \
     "https://api.ovh.com/1.0/cloud/project" \
     -H "X-Ovh-Application: $OVH_APPLICATION_KEY" \
     -H "X-Ovh-Consumer: $OVH_CONSUMER_KEY"
   ```

3. **Backend State Issues**
   ```bash
   # Reconfigure backend
   tofu init -reconfigure -backend-config=backend-configs/your-config.tfbackend
   ```

4. **Cluster Not Ready**
   ```bash
   # Check cluster status
   tofu output cluster_status

   # Wait for cluster to be ready (can take 5-10 minutes)
   ```

### Getting Help

- Check cluster status in [OVH Control Panel](https://www.ovh.com/manager/)
# Review OpenTofu logs with `TF_LOG=DEBUG`
- Consult [OVH Kubernetes documentation](https://docs.ovh.com/gb/en/kubernetes/)

## Cleanup

To destroy all resources:

```bash
tofu destroy -var-file=vars/my-project.tfvars
```

**Warning**: This will permanently delete your cluster and all data. Make sure to backup any important information first.

## Cost Optimization

- Use `monthly_billed = true` for long-running workloads
- Choose appropriate instance flavors for your workload
- Enable autoscaling to scale down during low usage
- Use spot instances where possible (check OVH documentation)

## Security Best Practices

1. **API Credentials**: Use restricted API keys with minimal required permissions
2. **Network Security**: Consider using private networks for production workloads
3. **Secrets Management**: Use Kubernetes secrets for sensitive data
4. **Updates**: Keep cluster and node pools updated regularly
5. **Monitoring**: Enable logging and monitoring for security events
