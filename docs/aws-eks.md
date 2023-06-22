# AWS EKS Cluster Walk-through

This walk-through uses `eksctl` and assumes you already have an AWS account and have the [eksctl prerequisites installed](https://docs.aws.amazon.com/eks/latest/userguide/getting-started-eksctl.html)

---

## create your k8s cluster

An example command below. See the [eksctl docs](https://eksctl.io/usage/creating-and-managing-clusters/) for all the options

```python
$ eksctl create cluster \
    --name sandbox \
    --region us-west-2 \
    # useful if you want to ssh into your nodes
    --ssh-access=true --ssh-public-key=~/.ssh/id_ed25519_k8veda.pub \
    --nodegroup-name=hub-node \
    --node-type=t2.xlarge \
    --nodes=1 --nodes-min=1 --nodes-max=5
```

You might need to iterate on the command above, so to delete the cluster:

```python
$ eksctl delete cluster --name=sandbox --region us-west-2
```

---

## check OIDC provider set up for you cluster

Best to walk through the [AWS docs](https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html) for this
but below is the relevant bits:

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

## add the EBS CSI Addon for dynamic EBS provisioning 

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
  # the naming of this is up to you
  --role-name eksctl-veda-sandbox-addon-aws-ebs-csi-driver
```

Then check how to see whgat the compatible EBS CSI addon version works for you cluster version. [AWS docs](https://docs.aws.amazon.com/eks/latest/userguide/managing-ebs-csi.html).
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
    # this is the ARN of the role you created two steps ago
    --service-account-role-arn arn:aws:iam::444055461661:role/eksctl-veda-sandbox-addon-aws-ebs-csi-driver \
    --force
```
Finally, do some checking to assert things are set up correctly:

```python
# check to make the ServiceAccount has an annotation of your IAM role
$ kubectl get sa ebs-csi-controller-sa -n kube-system -o yaml | grep -a2 annotations
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

### install AWS load balancer controller

# Good to read about all the EKS cluster addons and check that the versions are correct
https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html
https://docs.aws.amazon.com/eks/latest/userguide/service-accounts.html#boundserviceaccounttoken-validated-add-on-versions

# Walkthrough
https://docs.aws.amazon.com/eks/latest/userguide/alb-ingress.html
https://repost.aws/knowledge-center/load-balancer-troubleshoot-creating

# get the policy
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.4.7/docs/install/iam_policy.json

# create the policy
aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam_policy.json

# create the role and attach policy
eksctl create iamserviceaccount \
  --region us-west-1 \
  --cluster=veda-sandbox \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn=arn:aws:iam::444055461661:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve

# QC to make sure it was created and has an annotation
$ kubectl get sa aws-load-balancer-controller -n kube-system
NAME                           SECRETS   AGE
aws-load-balancer-controller   0         13s

$ kubectl describe sa aws-load-balancer-controller -n kube-system | grep Annotations
Annotations:         eks.amazonaws.com/role-arn: arn:aws:iam::444055461661:role/AmazonEKSLoadBalancerControllerRole

# install the K8s AWS Controller

helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=veda-sandbox \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

# QC to make sure it's working
kubectl get deployment -n kube-system aws-load-balancer-controller


