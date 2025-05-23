 # GCP GKE Cluster Setup

This is a verbose walkthrough. It uses `gcloud` and assumes you already have an GCP account and project where you want to run eoapi. We also assume that you have some prerequisites installed including `gcloud`, `kubectl` and `helm`.

If you're familiar with Terraform and would like an IaC choice that is more terse consider setting up your cluster with that: https://github.com/developmentseed/eoapi-k8s-terraform

# Table of Contents
- [Pre-requisites](#pre-requisites)
- [Enable GKE API](#enable-gke-api)
- [Create GKE k8s Cluster](#create-gke-k8s-cluster)
- [Enable CSI Driver](#enable-csi-driver)
- [Install NGINX Ingress Controller](#install-nginx-ingress-controller)
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

# Install NGINX Ingress Controller

NGINX Ingress Controller can be installed through `helm` using the following command:
```
kubectl create ns eoapi

helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace eoapi
```

See the [NGINX Ingress Controller docs](https://kubernetes.github.io/ingress-nginx/deploy/) for more details and configuration options.

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

Now we are ready to install eoapi. See the [eoapi installation instructions](../README.md/#helm-installation) for more details.
