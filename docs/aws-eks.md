---
title: "AWS EKS Setup"
description: "Complete EKS cluster setup with OIDC, node autoscaling, EBS CSI, and NGINX ingress"
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

If you're familiar with Terraform and would like an IaC choice that is more terse consider setting up your cluster with that: https://github.com/developmentseed/eoapi-k8s-terraform


## Table of Contents:
1. [Create EKS Cluster](#create-cluster)
2. [Make sure EKS Cluster has OIDC Provider](#check-oidc)
3. [Install Node Autoscaling](#node-autoscaler)
4. [Install EBS CSI Add-on](#ebs-addon)
5. [Install NGINX Ingress Controller](#nginx-ingress)

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

## Install Nginx Ingress Controller <a name="nginx-ingress"></a>

Please look through the [Nginx Docs](https://github.com/kubernetes/ingress-nginx) to verify nothing has changed below. There are multiple ways to provision and configure. Below is the simplest we found:

   ```sh
   helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
   kubectl create namespace ingress-nginx
   helm upgrade -i ingress-nginx \
       ingress-nginx/ingress-nginx \
       --set controller.service.type=LoadBalancer \
       --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"="nlb" \
       --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-scheme"="internet-facing" \
       --namespace ingress-nginx

   # helm delete ingress-nginx -n ingress-nginx
   ```

Depending on what NGINX functionality you need you might also want to configure `kind: ConfigMap` as [talked about on their docs](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/).
Below we enable gzip by patching `use-gzip` into the `ConfigMap`:

   ```sh
   kubectl get cm  | grep ingress-nginx | cut -d' ' -f1 | xargs -I{} kubectl patch cm/{} --type merge -p '{"data":{"use-gzip":"true"}}'

   # kubectl get cm --all-namespaces| grep ingress-nginx-controller | awk '{print $1 " " $2}' | while read ns cm; do kubectl patch cm -n $ns $cm --type merge -p '{"data":{"use-gzip":"true"}}'; done

   kubectl get deploy --all-namespaces | grep ingress-nginx-conto | cut -d' ' -f1 | xargs -I{} kubectl rollout restart deploy/{}

   # kubectl get deploy --all-namespaces| grep ingress-nginx-controller | awk '{print $1 " " $2}' | while read ns deploy; do kubectl rollout restart deploy/$deploy -n $ns; done
   ```

Assert that things are set up correctly:

   ```sh
   kubectl get deploy,pod,svc --all-namespaces | grep nginx

   # deployment.apps/nginx-ingress-nginx-controller   1/1     1            1           2d17h
   # pod/nginx-ingress-nginx-controller-76d7f6f4d5-g6fkv   1/1     Running   0          27h
   # service/nginx-ingress-nginx-controller             LoadBalancer   10.100.36.152    eoapi-k8s-553d3ea234b-3eef2e6e61e5d161.elb.us-west-1.amazonaws.com   80:30342/TCP,443:30742/TCP   2d17h
   # service/nginx-ingress-nginx-controller-admission   ClusterIP      10.100.34.22     <none>                                                                          443/TCP                      2d17h
   ```
