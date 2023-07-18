# AWS EKS Cluster Walk-through

This walk-through uses `eksctl` and assumes you already have an AWS account, have the [eksctl prerequisites installed](https://docs.aws.amazon.com/eks/latest/userguide/getting-started-eksctl.html) including `eksctl` and `helm`.
After creating the cluster we'll walk through installing the following add-ons and controllers:

* `aws-ebs-csi-driver` 
* `aws-load-balancer-controller`
* `nginx-ingress-controller`

## Table of Contents:
1. [Create EKS Cluster](#create-cluster)
2. [Make sure EKS Cluster has OIDC Provider](#check-oidc)
3. [Install EBS CSI Add-on](#ebs-addon)
4. [Install AWS LB Controller](#aws-lb)
4. [Install NGINX Ingress Controller](#nginx-ingress)

---

## Create your k8s cluster <a name="create-cluster"></a>

An example command below. See the [eksctl docs](https://eksctl.io/usage/creating-and-managing-clusters/) for all the options

```python
$ eksctl create cluster \
    --name sandbox \
    --region us-west-2 \
    # useful if you want to ssh into your nodes
    --ssh-access=true --ssh-public-key=~/.ssh/id_ed25519_k8_sandbox.pub \
    --nodegroup-name=hub-node \
    --node-type=t2.xlarge \
    --nodes=1 --nodes-min=1 --nodes-max=5
```

You might need to iterate on the command above, so to delete the cluster:

```python
$ eksctl delete cluster --name=sandbox --region us-west-2
```

---

## Check OIDC provider set up for you cluster <a name="check-oidc"></a>

For k8s `ServiceAccount`(s) to do things on behalf of pods in AWS you need an OIDC provider set up. Best to walk through 
the [AWS docs](https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html) for this
but below are the relevant bits. Note that `eksctl` "should" set up an OIDC provider for you by default

```python
export CLUSTER_NAME=my-cluster
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

## Install the EBS CSI Addon for dynamic EBS provisioning <a name="ebs-addon"></a>

Best to walk through the [AWS docs](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html) about this
since there are potential version conflicts and footguns

First, create an IAM Role for the future EBS CSI `ServiceAccount` binding:

>  &#9432; the AWS docs make it seem like the k8 `ServiceAccount` and related `kind: Controller` are already created, but they aren't

```python
$ eksctl create iamserviceaccount \
    --region us-west-2 \
    --name ebs-csi-controller-sa \
    --namespace kube-system \
    --cluster sandbox \
    --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
    --approve \
    --role-only \
    # arbitrary, the naming is up to you
    --role-name eksctl-veda-sandbox-addon-aws-ebs-csi-driver
```

Then check how to see what the compatible EBS CSI addon version works for you cluster version. [AWS docs](https://docs.aws.amazon.com/eks/latest/userguide/managing-ebs-csi.html).
Below is an example with sample output:

```python
$ aws eks describe-addon-versions \
    --addon-name aws-ebs-csi-driver \
    --region us-west-2 | grep -e addonVersion -e clusterVersion

 "addonVersion": "v1.6.0-eksbuild.1",
        "clusterVersion": "1.24",
        "clusterVersion": "1.23",
        "clusterVersion": "1.22",
        "clusterVersion": "1.21",
        "clusterVersion": "1.20",
"addonVersion": "v1.5.3-eksbuild.1",
        "clusterVersion": "1.24",
        "clusterVersion": "1.23",
        "clusterVersion": "1.22",
        "clusterVersion": "1.21",
        "clusterVersion": "1.20",
"addonVersion": "v1.5.2-eksbuild.1",
        "clusterVersion": "1.24",
        "clusterVersion": "1.23",
        "clusterVersion": "1.22",
        "clusterVersion": "1.21",
        "clusterVersion": "1.20",
"addonVersion": "v1.4.0-eksbuild.preview",
        "clusterVersion": "1.21",
        "clusterVersion": "1.20",
```

Then create the EBS CSI Addon:

>  &#9432; note that this step creates k8 `ServiceAccount` and ebs-csi pods and `kind: Controller`

```python
$ eksctl create addon \
    --name aws-ebs-csi-driver \
    --region us-west-2 \
    --cluster sandbox \
    --version v1.5.2-eksbuild.1 \
    # this is the ARN of the role you created two steps ago
    --service-account-role-arn arn:aws:iam::444055461661:role/eksctl-veda-sandbox-addon-aws-ebs-csi-driver \
    --force
```
Finally, do some checking to assert things are set up correctly:

```python
# check to make the ServiceAccount has an annotation of your IAM role
$ kubectl get sa ebs-csi-controller-sa -n kube-system -o yaml | grep -a1 annotations
metadata:
    annotations:
        eks.amazonaws.com/role-arn: arn:aws:iam::444055461661:role/eksctl-veda-sandbox-addon-aws-ebs-csi-driver
```

```python
# check to make sure we have controller pods up for ebs-csi and that they aren't in state `CrashLoopBack`
kubectl get pod  -n kube-system | grep ebs-csi
ebs-csi-controller-5cbc775dc5-hr6mz   6/6     Running   0          4m51s
ebs-csi-controller-5cbc775dc5-knqnr   6/6     Running   0          4m51s
```

You can additionally run through these [AWS docs](https://docs.aws.amazon.com/eks/latest/userguide/ebs-sample-app.html) to deploy
a sample application to make sure it dynamically mounts an EBS volume

---

### Install AWS load balancer controller <a name="aws-lb"></a>

Best to walk through the [AWS userguide](https://docs.aws.amazon.com/eks/latest/userguide/alb-ingress.html) and [docs](https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html) but
examples are provided below.

First, we create the policy, IAM role and the k8s `ServiceAccount`

```python
# download the policy aws-load-balancer policy
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.4.7/docs/install/iam_policy.json

# create the policy
aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam_policy.json

# create the IAM Role, the ServiceAccount and bind them
eksctl create iamserviceaccount \
  --region us-west-2 \
  --cluster=sandbox \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  # arbitrary, the naming is up to you
  --role-name AmazonEKSLoadBalancerControllerRole \
  # ARN from last step
  --attach-policy-arn=arn:aws:iam::444055461661:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve

# assert it was created and has an annotation
$ kubectl get sa aws-load-balancer-controller -n kube-system
NAME                           SECRETS   AGE
aws-load-balancer-controller   0         13s

$ kubectl describe sa aws-load-balancer-controller -n kube-system | grep Annotations
Annotations:         eks.amazonaws.com/role-arn: arn:aws:iam::444055461661:role/AmazonEKSLoadBalancerControllerRole
```

Then install the K8s AWS Controller:

```python
helm repo add eks https://aws.github.io/eks-charts;
helm repo update;
helm install aws-load-balancer-controller \
    eks/aws-load-balancer-controller \
    -n kube-system \
    --set clusterName=sandbox \
    # since the last steps already did this, set to false
    --set serviceAccount.create=false \
    --set serviceAccount.name=aws-load-balancer-controller
```

```python
$ kubectl get deployment -n kube-system aws-load-balancer-controller
NAME                           READY   UP-TO-DATE   AVAILABLE   AGE
aws-load-balancer-controller   2/2     2            2           36d
```

## Install Nginx Ingress Controller <a name="nginx-ingress"></a>

Please look through the [Nginx Docs](https://github.com/kubernetes/ingress-nginx) to verify nothing has changed below. There are multiple ways to provision and configure. Below is the simplest we found:

```python
$ helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
$ helm upgrade \
    -i ingress-nginx \
    ingress-nginx/ingress-nginx \
    --set controller.service.type=LoadBalancer
    # these next two annotations are the most important otherwise nginx controller will create an "internal" NLB
    --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"="nlb" \
    --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-scheme"="internet-facing" \
    --namespace <the-same-namespace-where-your-services-will-be-deployed>
```

Depending on what NGINX functionality you need you might also want to configure `kind: ConfigMap` as [talked about on their docs](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/). 
Below we enable gzip by patching `use-gzip` into the `ConfigMap`:

```python
$ kubectl get cm | grep ingress-nginx | cut -d' ' -f1 | xargs -I{} kubectl patch cm/{} --type merge -p '{"data":{"use-gzip":"true"}}'
$ kubectl get deploy | grep ingress-nginx | cut -d' ' -f1 | xargs -I{} kubectl rollout restart deploy/{}   
```

Assert that things are set up correctly:

```python
$ kubectl get deploy,pod,svc -namespace testing123 | grep nginx
deployment.apps/nginx-ingress-nginx-controller   1/1     1            1           2d17h

pod/nginx-ingress-nginx-controller-76d7f6f4d5-g6fkv   1/1     Running   0          27h

service/nginx-ingress-nginx-controller             LoadBalancer   10.100.36.152    eoapi-k8s-553d3ea234b-3eef2e6e61e5d161.elb.us-west-1.amazonaws.com   80:30342/TCP,443:30742/TCP   2d17h
service/nginx-ingress-nginx-controller-admission   ClusterIP      10.100.34.22     <none>                                                                          443/TCP                      2d17h
```