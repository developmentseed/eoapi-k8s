#!/bin/bash
# rm deploys (which will remove replicasets and pods)
kubectl get deploy | grep -v NAME | grep $1 | cut -d' ' -f1 | xargs -I{} kubectl delete deploy/{}
# rm svc
kubectl get svc | grep -v NAME | grep $1 | cut -d' ' -f1 | xargs -I{} kubectl delete svc/{}
# rm ingress
kubectl get ingress | grep -v NAME | grep $1 | cut -d' ' -f1 | xargs -I{} kubectl delete ingress/{}
# rm pvc
kubectl get pvc | grep -v NAME | grep $1 | cut -d' ' -f1 | xargs -I{} kubectl delete pvc/{}
# rm secrets
kubectl get secret | grep -v NAME | grep $1 | cut -d' ' -f1 | xargs -I{} kubectl delete secret/{}
# rm configmap
kubectl get configmap | grep -v NAME | grep $1 | cut -d' ' -f1 | xargs -I{} kubectl delete configmap/{}
