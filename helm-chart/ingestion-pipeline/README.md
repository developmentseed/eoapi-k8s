# Ingestion Pipeline for eoAPI

The ingestion pipeline is run on ArgoWorklow. There is an example pipeline in the [examples/maxar_opendata](examples/maxar_opendata/) folder.

To run the pipeline:

- build the [Docker image](examples/maxar_opendata/Dockerfile) and make sure it's accessible by k8s.
- Update the workflow definition in the [values file](examples/maxar_opendata/values.yaml) if necessary (eg: update the docker image)
- Run the workflow through helm: ```helm upgrade --install --force -f examples/maxar_opendata/values.yaml maxar-opendata-ingest . -n eoapi
```