# Configuration Options

## Required Values

The required values to pass to `helm install` or `helm template` commands can be found by showing what is validated:

```bash
$ head -n 9 <eoapi-k8s-repo>/values.schema.json
{
  "$schema": "http://json-schema.org/schema#",
  "type": "object",
  "required": [
    "service",
    "gitSha"
  ],
```

Most of the required fields have common-sense defaults. 
The table below and the `values.yaml` comments should explain what the options and defaults are:

|                               **Values Key**                              |                                                              **Description**                                                              |  **Default** | **Choices**            |
|:-------------------------------------------------------------------------|:-----------------------------------------------------------------------------------------------------------------------------------------|:------------|:------------------------|
| `service.port`                                                              | the port that all vector/raster/stac services run on<br>used in `kind: Service` and `kind: Ingress`                                       |     8080     |   your favorite port   |
| `gitSha`                                                                    | sha attached to a `kind: Deployment` key `metadata.labels`                                                                                | gitshaABC123 | your favorite sha      |


--- 

## Default Configuration

Running `helm install` from https://devseed.com/eoapi-k8s/ should spin up similar infrastructure in EKS or GKE:

In EKS or GKE you'll by default get:

* a HA PostgreSQL database deployment and service via [Crunchdata's Postgresl Operator](https://access.crunchydata.com/documentation/postgres-operator)
* the same vector and raster data fixtures used for testing loaded into the DB
* a load balancer and nginx-compatible ingress with the following path rewrites:
    * a `/stac` service for `stac_fastapi.pgstac`
    * a `/raster` service for `titler.pgstac`
    * a `/vector` service for `tipg.pgstac`

Here's a simplified high-level diagram to grok:
![](./images/default_architecture.png)

---

## Additional Options

---

### Key `autoscaling`

#### `autoscaling.type`

|   **Values Key**  |                                                                 **Description**                                                                 | **Default** | **Choices**  |
|:-----------------|:-----------------------------------------------------------------------------------------------------------------------------------------------|:-----------|:--------------|
| `autoscaling.type` | a simple example of a default metric (`cpu`) and custom metric (`requestRate`) to scale by. If selecting `both` the metric that results in the "highest amount of change" wins. See [k8s documentation](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/#scaling-on-multiple-metrics) for more info  | requestRate       | requestRate<br>cpu<br>both<br> |

#### `autoscaling.behaviour.[scaleDown||scaleUp]`

These are normal k8s autoscaling pass throughs. They are stablization windows in seconds to for scaling up or down to prevent flapping from happening. Read more about [the options on the k8s documentation](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/#configurable-scaling-behavior)