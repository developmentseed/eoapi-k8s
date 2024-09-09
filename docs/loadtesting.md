## Load Testing

#### Naive Load Testing using `hey`

Everything mentioned below assumes you've already gone through the [Autoscaling Doc](autoscaling.md) and
that you're deploying using `ingress.className: "nginx"`.

0. Install `hey` utility locally

1. Find the external IP of your shared nginx ingress

```sh
export INGRESS_ENDPOINT=$(kubectl -n ingress-nginx get ingress/nginx-service-ingress-shared-eoapi -o=jsonpath='{.spec.rules[0].host}')
# eoapi-35.234.254.12.nip.io%

## EKS cluster
export INGRESS_ENDPOINT=$(kubectl -n ingress-nginx  get svc/ingress-nginx-controller -o=jsonpath='{.status.loadBalancer.ingress[0].hostname}')
# k8s-eoapi-ingressn-404721dbb4-e6dec70321c3eddd.elb.us-west-2.amazonaws.com
```

2. Then run some naive load testing against some static read-only endpoints in a couple different terminals 

```sh
hey -n 2000000 -q 150 -c 20 "http://${INGRESS_ENDPOINT}/vector/collections/public.my_data/items?f=geojson"
hey -n 2000000 -q 150 -c 20 "http://${INGRESS_ENDPOINT}/stac/"
```
   
3. Go to Grafana again and watch your services autoscaling for services you are actually hitting

![](./images/grafanaautoscale.png)