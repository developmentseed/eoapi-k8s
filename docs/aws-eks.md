step 1)
eksctl create cluster \
--name veda-sandbox --region us-west-1 \
--ssh-access=true --ssh-public-key=~/.ssh/id_ed25519_k8veda.pub \
--nodegroup-name=hub-node --node-type=t2.xlarge \
--nodes=1 --nodes-min=1 --nodes-max=5 --dry-run > /tmp/eksctl_config.yaml

eksctl delete cluster --name=veda-sandbox --region us-west-1

step 2) OIDC
https://aws.amazon.com/premiumsupport/knowledge-center/eks-troubleshoot-ebs-volume-mounts/
-start: https://docs.aws.amazon.com/eks/latest/userguide/managing-ebs-csi.html
        https://github.com/kubernetes-sigs/aws-ebs-csi-driver/blob/master/docs/install.md
        https://docs.aws.amazon.com/eks/latest/userguide/csi-iam-role.html

# https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html
eksctl utils associate-iam-oidc-provider --cluster veda-sandbox --region us-west-1 --approve


step 3) EBS Addon
# https://docs.aws.amazon.com/eks/latest/userguide/csi-iam-role.html
# NOTE: the k8 ServiceAccount or the controller isn't created yet even though the docs make you think it already is
eksctl create iamserviceaccount \
  --region us-west-1 \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster veda-sandbox \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve \
  --role-only \
  --role-name eksctl-veda-sandbox-addon-aws-ebs-csi-driver

https://docs.aws.amazon.com/eks/latest/userguide/managing-ebs-csi.html
# find the ebs-csi plugin version that works for my EKS cluster version
aws eks describe-addon-versions --addon-name aws-ebs-csi-driver --region us-west-1 | grep -e addonVersion -e clusterVersion
v1.15.0-eksbuild.1

# create the ebs-sci driver addon
# NOTE: this step creates k8 ServiceAccount and ebs-sci pods
eksctl create addon --name aws-ebs-csi-driver --region us-west-1 --cluster veda-sandbox --service-account-role-arn arn:aws:iam::444055461661:role/eksctl-veda-sandbox-addon-aws-ebs-csi-driver --force

# check to make the ServiceAccount has an annotation of your IAM role
$ kubectl get sa ebs-csi-controller-sa -n kube-system -o yaml | grep -a1 annotations
metadata:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::444055461661:role/eksctl-veda-sandbox-addon-aws-ebs-csi-driver

# check to make sure we have controller pods up for ebs-csi
kubectl get pod  -n kube-system | grep ebs-csi
ebs-csi-controller-5cbc775dc5-hr6mz   6/6     Running   0          4m51s
ebs-csi-controller-5cbc775dc5-knqnr   6/6     Running   0          4m51s

helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
helm repo update
helm upgrade --install aws-ebs-csi-driver \
    --namespace kube-system \
    aws-ebs-csi-driver/aws-ebs-csi-driver

step 4) AWS Load Balancer Addon

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


