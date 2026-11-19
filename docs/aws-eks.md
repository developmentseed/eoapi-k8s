---
title: "AWS EKS Setup"
description: "Complete EKS cluster setup with OIDC, node autoscaling, EBS CSI, and Traefik ingress"
external_links:
  - name: "eoapi-k8s Repository"
    url: "https://github.com/developmentseed/eoapi-k8s"
  - name: "AWS EKS Documentation"
    url: "https://docs.aws.amazon.com/eks/"
  - name: "eksctl Documentation"
    url: "https://eksctl.io/"
  - name: "Terraform Alternative"
    url: "https://github.com/developmentseed/eoapi-k8s-terraform"
---

# AWS EKS Cluster Walkthrough

This is a verbose walkthrough. It uses `eksctl` and assumes you already have an AWS account, have the [eksctl prerequisites installed](https://docs.aws.amazon.com/eks/latest/userguide/getting-started-eksctl.html) including `eksctl` and `helm`.

If you're familiar with Terraform and would like an IaC choice that is more terse consider setting up your cluster with that: https://github.com/developmentseed/eoapi-k8s-terraform. It installs the retired ingress-nginx controller, so replace that with Traefik as described [below](#ingress).


## Table of Contents:
1. [Create EKS Cluster](#create-cluster)
2. [Make sure EKS Cluster has OIDC Provider](#check-oidc)
3. [Install Node Autoscaling](#node-autoscaler)
4. [Install EBS CSI Add-on](#ebs-addon)
5. [Install the Ingress Controller](#ingress)

---

## Create your k8s cluster <a name="create-cluster"></a>

An example command below. See the [eksctl docs](https://eksctl.io/usage/creating-and-managing-clusters/) for all the options

   ```sh
   # Useful ssh-access if you want to ssh into your nodes
   # Check latest supported versions: eksctl get clusters --region us-west-2
   eksctl create cluster \
       --name sandbox \
       --region us-west-2 \
       --ssh-access=true \
       --ssh-public-key=~/.ssh/id_ed25519_k8_sandbox.pub \
       --nodegroup-name=hub-node \
       --node-type=t2.medium \
       --nodes=1 --nodes-min=1 --nodes-max=5 \
       --version 1.28 \
       --asg-access
   ```

TODO:  Add autoscaling config

*Note*: To generate your `ssh-public-key`, use:

  ```sh
  ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_k8_sandbox
  ```


You might need to iterate on the command above, so to delete the cluster:

   ```sh
   eksctl delete cluster --name=sandbox --region us-west-2
   ```

---

## Check OIDC provider set up for you cluster <a name="check-oidc"></a>

For k8s `ServiceAccount`(s) to do things on behalf of pods in AWS you need an OIDC provider set up. Best to walk through
the [AWS docs](https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html) for this
but below are the relevant bits. Note that `eksctl` "should" set up an OIDC provider for you by default

   ```sh
   export CLUSTER_NAME=sandbox
   export REGION=us-west-2

   oidc_id=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text | cut -d '/' -f 5)
   existing_oidc_id=$(aws iam list-open-id-connect-providers | grep $oidc_id | cut -d "/" -f4)
   if [ -z "$existing_oidc_id" ]; then
    echo "no existing OIDC provider, associating one..."
    eksctl utils associate-iam-oidc-provider --cluster $CLUSTER_NAME --region $REGION --approve
   else
    echo "already have an existing OIDC provider, skipping..."
   fi
   ```

---

## Install Node Autoscaler  <a name="node-autoscaler"></a>

To run the autoscaler on EKS, we need to create a policy and install Auto-Discovery Setup, which is the preferred method to configure [Cluster Autoscaler in EKS](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws/README.md#auto-discovery-setup).

   ```sh
   aws iam create-policy --policy-name ${CLUSTER_NAME}-asg --policy-document file://configs/aws-asg-policy.json
   # Update the cluster name ins case you changed in configs/cluster-autoscaler-autodiscover.yaml file
   kubectl apply -f configs/cluster-autoscaler-autodiscover.yaml
   ```

## Install the EBS CSI Addon for dynamic EBS provisioning <a name="ebs-addon"></a>

Best to walk through the [AWS docs](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html) about this
since there are potential version conflicts and footguns

First, create an IAM Role for the future EBS CSI `ServiceAccount` binding:

>  &#9432; the AWS docs make it seem like the k8 `ServiceAccount` and related `kind: Controller` are already created, but they aren't

   ```sh
   eksctl create iamserviceaccount \
       --region us-west-2 \
       --name ebs-csi-controller-sa \
       --namespace kube-system \
       --cluster sandbox \
       --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
       --approve \
       --role-only \
       --role-name eksctl-veda-sandbox-addon-aws-ebs-csi-driver # arbitrary, the naming is up to you
   ```

Check the compatible EBS CSI addon version for your cluster version using [AWS docs](https://docs.aws.amazon.com/eks/latest/userguide/managing-ebs-csi.html).

   ```sh
   # Get your cluster version
   export CLUSTER_VERSION=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query "cluster.version" --output text)

   # Find compatible addon versions
   aws eks describe-addon-versions \
       --addon-name aws-ebs-csi-driver \
       --kubernetes-version $CLUSTER_VERSION \
       --region $REGION \
       --query "addons[0].addonVersions[0].addonVersion" --output text
   ```

Then create the EBS CSI Addon:

>  &#9432; note that this step creates k8 `ServiceAccount` and ebs-csi pods and `kind: Controller`

   ```sh
   # Get the latest compatible addon version and install
   export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
   export CLUSTER_VERSION=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query "cluster.version" --output text)
   export EBS_CSI_VERSION=$(aws eks describe-addon-versions \
       --addon-name aws-ebs-csi-driver \
       --kubernetes-version $CLUSTER_VERSION \
       --region $REGION \
       --query "addons[0].addonVersions[0].addonVersion" --output text)

   eksctl create addon \
       --name aws-ebs-csi-driver \
       --region $REGION \
       --cluster $CLUSTER_NAME \
       --version $EBS_CSI_VERSION \
       --service-account-role-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/eksctl-veda-sandbox-addon-aws-ebs-csi-driver \
       --force
   ```

Finally, do some checking to assert things are set up correctly:

   ```sh
   # Check to make the ServiceAccount has an annotation of your IAM role
   kubectl get sa ebs-csi-controller-sa -n kube-system -o yaml | grep -a1 annotations
   # metadata:
   #     annotations:
   #         eks.amazonaws.com/role-arn: arn:aws:iam::<AWS_ACCOUNT_ID>:role/eksctl-veda-sandbox-addon-aws-ebs-csi-driver
   ```

   ```sh
   # Check to make sure we have controller pods up for ebs-csi and that they aren't in state `CrashLoopBack`
   kubectl get pod  -n kube-system | grep ebs-csi
   # ebs-csi-controller-5cbc775dc5-hr6mz   6/6     Running   0          4m51s
   # ebs-csi-controller-5cbc775dc5-knqnr   6/6     Running   0          4m51s
   ```

You can additionally run through these [AWS docs](https://docs.aws.amazon.com/eks/latest/userguide/ebs-sample-app.html) to deploy
a sample application to make sure it dynamically mounts an EBS volume

---

## Install the Ingress Controller <a name="ingress"></a>

We use Traefik: the community ingress-nginx controller was retired in March 2026 and its repository is archived. To move a cluster that already runs ingress-nginx, see [Unified Ingress](unified-ingress.md#existing-ingress-nginx-clusters).

Install Traefik behind an NLB with the repository's [`traefik-values.yaml`](https://github.com/developmentseed/eoapi-k8s/blob/main/docs/traefik-values.yaml):

   ```sh
   curl -fsSLO https://raw.githubusercontent.com/developmentseed/eoapi-k8s/main/docs/traefik-values.yaml
   helm upgrade --install traefik traefik \
       --repo https://traefik.github.io/charts --version 42.4.1 \
       --namespace traefik --create-namespace \
       -f traefik-values.yaml \
       --set-string service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"="nlb" \
       --set-string service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-scheme"="internet-facing"

   # helm delete traefik -n traefik
   ```

The values file redirects HTTP to HTTPS and sends HSTS, as ingress-nginx did. See [Unified Ingress](unified-ingress.md#traefik-ingress-controller) for the other differences, such as compression.

Then set the ingress class in the `config.yaml` you pass to [`helm install`](./helm-install.md). Because of the redirect, serve eoAPI over TLS, for example with a certificate from [cert-manager](unified-ingress.md#setting-up-tls-with-cert-manager):

   ```yaml
   ingress:
     className: "traefik"
     host: "eoapi.example.com"
     tls:
       enabled: true
   ```

If you enable autoscaling, use `type: "cpu"`: request-rate autoscaling reads ingress-nginx metrics (see [Autoscaling](autoscaling.md)).

Assert that things are set up correctly:

   ```sh
   kubectl -n traefik get deploy,pod,svc

   # The traefik Service is a LoadBalancer with an *.elb.<region>.amazonaws.com EXTERNAL-IP
   ```

---

## Configure IRSA for S3 Bucket Access

eoAPI services (especially the raster API) need to access COG files in S3 buckets. Instead of using long-lived credentials, use IRSA (IAM Roles for Service Accounts) for secure, temporary credential access:

1. **Create an IAM policy** for S3 bucket access:

   ```sh
   cat <<EOF > eoapi-s3-policy.json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "s3:GetObject",
           "s3:ListBucket"
         ],
         "Resource": [
           "arn:aws:s3:::your-bucket-name/*",
           "arn:aws:s3:::your-bucket-name"
         ]
       }
     ]
   }
   EOF

   aws iam create-policy \
       --policy-name eoapi-s3-access \
       --policy-document file://eoapi-s3-policy.json
   ```

2. **Create an IAM role and service account**:

   ```sh
   eksctl create iamserviceaccount \
       --name eoapi-sa \
       --namespace default \
       --cluster $CLUSTER_NAME \
       --region $REGION \
       --attach-policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/eoapi-s3-access \
       --approve
   ```

   This command automatically creates a service account with the necessary annotation:
   ```yaml
   # This is what eksctl creates for you:
   apiVersion: v1
   kind: ServiceAccount
   metadata:
     name: eoapi-sa
     namespace: default
     annotations:
       eks.amazonaws.com/role-arn: arn:aws:iam::${AWS_ACCOUNT_ID}:role/eksctl-${CLUSTER_NAME}-addon-iamserviceaccount-default-eoapi-sa
   ```

3. **Configure EOAPI** to use the service account in your `values.yaml`:

   ```yaml
   serviceAccount:
     create: false  # We already created it with eksctl
     name: eoapi-sa
   ```

   **Alternative:** If you prefer to let the Helm chart create the service account, skip step 2 and use:
   ```yaml
   serviceAccount:
     create: true
     annotations:
       eks.amazonaws.com/role-arn: arn:aws:iam::${AWS_ACCOUNT_ID}:role/your-existing-iam-role
   ```

The raster service will automatically use IRSA credentials via the AWS SDK credential chain. No hardcoded credentials needed!
