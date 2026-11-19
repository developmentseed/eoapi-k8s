---
title: "GCP GKE Setup"
description: "GKE cluster creation with CSI driver, Traefik ingress, and cert-manager"
external_links:
  - name: "eoapi-k8s Repository"
    url: "https://github.com/developmentseed/eoapi-k8s"
  - name: "Google Cloud Documentation"
    url: "https://cloud.google.com/kubernetes-engine/docs"
  - name: "gcloud CLI"
    url: "https://cloud.google.com/sdk/gcloud"
  - name: "Terraform Alternative"
    url: "https://github.com/developmentseed/eoapi-k8s-terraform"
---

# GCP GKE Cluster Setup

This is a verbose walkthrough. It uses `gcloud` and assumes you already have an GCP account and project where you want to run eoapi. We also assume that you have some prerequisites installed including `gcloud`, `kubectl` and `helm`.

If you're familiar with Terraform and would like an IaC choice that is more terse consider setting up your cluster with that: https://github.com/developmentseed/eoapi-k8s-terraform. It installs the retired ingress-nginx controller, so replace that with Traefik as described [below](#install-the-ingress-controller).

# Table of Contents
- [Pre-requisites](#pre-requisites)
- [Enable GKE API](#enable-gke-api)
- [Create GKE k8s Cluster](#create-gke-k8s-cluster)
- [Enable CSI Driver](#enable-csi-driver)
- [Install the Ingress Controller](#install-the-ingress-controller)
- [Install Cert Manager](#install-cert-manager)


 # Pre-requisites

 Before we begin, make sure you are logged in to your GCP account and have set up a project. You can do this by running the following commands:
 ```
    gcloud auth login
    gcloud config set project <project-name>
```

# Enable GKE API

Before we can create a cluster, we need to enable the GKE API. You can do this by running the following command:
```
  gcloud services enable container.googleapis.com
```

# Create GKE k8s Cluster

Here's an example command to create a cluster. See the [gcloud docs](https://cloud.google.com/sdk/gcloud/reference/container/clusters/create) for all available options
  ```
  gcloud container clusters create sandbox \
  --num-nodes=1 \
  --zone=us-central1-a \
  --node-locations=us-central1-a \
  --enable-autoscaling \
  --min-nodes=1 \
  --max-nodes=3 \
  --machine-type=n1-standard-2
  ```

You might need to iterate on the command above, so to delete the cluster:
  ```
  gcloud container clusters delete sandbox --zone=us-central1-a
  ```

# Enable CSI Driver

CSI Driver is required for persistent volumes to be mounted to pods. You can enable it by running the following command:

```
gcloud container clusters update sandbox --update-addons=GcePersistentDiskCsiDriver=ENABLED --zone=us-central1-a
```

# Connect to Your Cluster

See [GKE docs for installing and authenticating with kubectl](https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-access-for-kubectl#install_plugin)

See [docs for installing Helm](https://helm.sh/docs/intro/install/)

Configure kubectl to connect to your GKE cluster:

```
gcloud container clusters get-credentials sandbox \
    --region=us-central1-a
```

To test the connection, run:

```
kubectl get nodes
```

You should see something like:

```
NAME                                        STATUS   ROLES    AGE   VERSION
gke-eoapi-test-default-pool-94a2b7e7-vg4f   Ready    <none>   5m   v1.31.5-gke.1233000
```

# Install the Ingress Controller

We use Traefik: the community ingress-nginx controller was retired in March 2026 and its repository is archived. To move a cluster that already runs ingress-nginx, see [Unified Ingress](unified-ingress.md#existing-ingress-nginx-clusters).

Install Traefik with the repository's [`traefik-values.yaml`](https://github.com/developmentseed/eoapi-k8s/blob/main/docs/traefik-values.yaml):
```
kubectl create ns eoapi

curl -fsSLO https://raw.githubusercontent.com/developmentseed/eoapi-k8s/main/docs/traefik-values.yaml
helm upgrade --install traefik traefik \
  --repo https://traefik.github.io/charts --version 42.4.1 \
  --namespace traefik --create-namespace \
  -f traefik-values.yaml
```

The values file redirects HTTP to HTTPS and sends HSTS, as ingress-nginx did. See [Unified Ingress](unified-ingress.md#traefik-ingress-controller) for the other differences.

Then set the ingress class in the `config.yaml` you pass to [`helm install`](./helm-install.md). Because of the redirect, serve eoAPI over TLS with a certificate from cert-manager (next section):
```yaml
ingress:
  className: "traefik"
  host: "eoapi.example.com"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  tls:
    enabled: true
```

If you enable autoscaling, use `type: "cpu"`: request-rate autoscaling reads ingress-nginx metrics (see [Autoscaling](autoscaling.md)).

# Install Cert Manager

Cert Manager can be installed through `helm` using the following commands:
```
helm repo add jetstack https://charts.jetstack.io

helm repo update

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.12.0 \
  --set installCRDs=true
```

Then create a ClusterIssuer whose HTTP-01 solver uses `ingressClassName: traefik`, as shown in [Unified Ingress](unified-ingress.md#setting-up-tls-with-cert-manager).

Now we are ready to install eoapi. See the [eoapi installation instructions](./helm-install.md) for more details.

# Configure Workload Identity for GCS Bucket Access

eoAPI services need to access COG files in GCS buckets. Use Workload Identity for secure, temporary credential access instead of long-lived credentials:

1. **Enable Workload Identity on your cluster** (if not already enabled):
   ```bash
   gcloud container clusters update sandbox \
       --workload-pool=PROJECT_ID.svc.id.goog \
       --zone=us-central1-a
   ```

2. **Create a Google Service Account**:
   ```bash
   gcloud iam service-accounts create eoapi-gcs-sa \
       --display-name="eoAPI GCS Service Account"
   ```

3. **Grant GCS permissions** to the service account:
   ```bash
   # For specific bucket access
   gsutil iam ch serviceAccount:eoapi-gcs-sa@PROJECT_ID.iam.gserviceaccount.com:objectViewer gs://your-bucket-name

   # Or use IAM roles for multiple buckets
   gcloud projects add-iam-policy-binding PROJECT_ID \
       --member="serviceAccount:eoapi-gcs-sa@PROJECT_ID.iam.gserviceaccount.com" \
       --role="roles/storage.objectViewer"
   ```

4. **Create Kubernetes service account** and bind it:
   ```bash
   kubectl create serviceaccount eoapi-sa -n eoapi

   gcloud iam service-accounts add-iam-policy-binding eoapi-gcs-sa@PROJECT_ID.iam.gserviceaccount.com \
       --role roles/iam.workloadIdentityUser \
       --member "serviceAccount:PROJECT_ID.svc.id.goog[eoapi/eoapi-sa]"

   kubectl annotate serviceaccount eoapi-sa -n eoapi \
       iam.gke.io/gcp-service-account=eoapi-gcs-sa@PROJECT_ID.iam.gserviceaccount.com
   ```

5. **Configure eoAPI** in your `values.yaml`:
   ```yaml
   serviceAccount:
     create: false  # We already created it
     name: eoapi-sa
   ```

The raster service will automatically use Workload Identity credentials. No hardcoded credentials needed!
