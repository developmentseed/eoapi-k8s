# Microsoft Azure Setup

## Using Azure managed PostgreSQL
To use Azure managed PostgreSQL with the `eoapi-k8s` chart, you need to set up the following:
1. **Create an Azure PostgreSQL server**: You can create a PostgreSQL server using the Azure portal or the Azure CLI. Make sure to note down the server name, username, and password.
2. **Create a PostgreSQL database**: After creating the server, create a database that will be used by the `eoapi-k8s` chart.
3. **Configure firewall rules**: Ensure that the PostgreSQL server allows connections from your Kubernetes cluster's IP address. You can do this by adding a firewall rule in the Azure portal or using the Azure CLI.

## Azure Configuration for eoapi-k8s

When deploying on Azure, you'll need to configure several settings in your values.yaml file. Below are the configurations needed for proper integration with Azure services.

### Common Azure Configuration

Add the following to your values.yaml:

```yaml
# Main Azure Configuration 
azure:
  aksSecretsProviderAvailable: true  # set to true when using Azure Key Vault
  keyvault:
    name: "your-keyvault-name"
    clientId: "your-client-id"
    tenantId: "your-tenant-id"
  # Mapping of name inside Azure Vault to name inside k8s secret object
  secretKeys:
    pgpassword: POSTGRES_PASSWORD
    pghost: POSTGRES_HOST
    dbname: POSTGRES_DBNAME
    # Add any other secrets your services need

# Service Account Configuration
serviceAccount:
  create: true
  annotations:
    azure.workload.identity/client-id: "your-client-id"
    azure.workload.identity/tenant-id: "your-tenant-id"
```

### PostgreSQL Configuration

Disable the internal PostgreSQL cluster when using Azure's managed PostgreSQL:

```yaml
postgrescluster:
  enabled: false
```

### PgSTAC Bootstrap Configuration

Configure the pgstacBootstrap service for Azure:

```yaml
pgstacBootstrap:
  enabled: true
  settings:
    labels:
      azure.workload.identity/use: "true"
    extraEnvVars:
      - name: POSTGRES_USER
        value: postgres
      - name: POSTGRES_PORT
        value: "5432"
    extraEnvFrom:
      - secretRef:
          name: pgstac-secrets-{{ $.Release.Name }}
    extraVolumeMounts:
      - name: azure-keyvault-secrets
        mountPath: /mnt/secrets-store
        readOnly: true
    extraVolumes:
      - name: azure-keyvault-secrets
        csi:
          driver: secrets-store.csi.k8s.io
          readOnly: true
          volumeAttributes:
            secretProviderClass: azure-secret-provider-{{ $.Release.Name }}
```

### API Services Configuration

For each API service (raster, multidim, stac, vector), add the following configuration:

```yaml
# Example for the raster service
raster:
  enabled: true
  settings:
    labels:
      azure.workload.identity/use: "true"
    extraEnvFrom:
      - secretRef:
          name: pgstac-secrets-{{ $.Release.Name }}
    extraVolumeMounts:
      - name: azure-keyvault-secrets
        mountPath: /mnt/secrets-store
        readOnly: true
    extraVolumes:
      - name: azure-keyvault-secrets
        csi:
          driver: secrets-store.csi.k8s.io
          readOnly: true
          volumeAttributes:
            secretProviderClass: azure-secret-provider-{{ $.Release.Name }}

# Example for the stac service
stac:
  enabled: true
  settings:
    labels:
      azure.workload.identity/use: "true"
    extraEnvFrom:
      - secretRef:
          name: pgstac-secrets-{{ $.Release.Name }}
    extraVolumeMounts:
      - name: azure-keyvault-secrets
        mountPath: /mnt/secrets-store
        readOnly: true
    extraVolumes:
      - name: azure-keyvault-secrets
        csi:
          driver: secrets-store.csi.k8s.io
          readOnly: true
          volumeAttributes:
            secretProviderClass: azure-secret-provider-{{ $.Release.Name }}

# Example for the vector service
vector:
  enabled: true
  settings:
    labels:
      azure.workload.identity/use: "true"
    extraEnvFrom:
      - secretRef:
          name: pgstac-secrets-{{ $.Release.Name }}
    extraVolumeMounts:
      - name: azure-keyvault-secrets
        mountPath: /mnt/secrets-store
        readOnly: true
    extraVolumes:
      - name: azure-keyvault-secrets
        csi:
          driver: secrets-store.csi.k8s.io
          readOnly: true
          volumeAttributes:
            secretProviderClass: azure-secret-provider-{{ $.Release.Name }}

# Example for the multidim service (if enabled)
multidim:
  enabled: false  # set to true if needed
  settings:
    labels:
      azure.workload.identity/use: "true"
    extraEnvFrom:
      - secretRef:
          name: pgstac-secrets-{{ $.Release.Name }}
    extraVolumeMounts:
      - name: azure-keyvault-secrets
        mountPath: /mnt/secrets-store
        readOnly: true
    extraVolumes:
      - name: azure-keyvault-secrets
        csi:
          driver: secrets-store.csi.k8s.io
          readOnly: true
          volumeAttributes:
            secretProviderClass: azure-secret-provider-{{ $.Release.Name }}
```

## Azure Key Vault Secret Provider Configuration

Create the following Secret Provider Class to access the secrets in Azure Key Vault:

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: azure-secret-provider-{{ $.Release.Name }}
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    clientID: {{ .Values.azure.keyvault.clientId }}
    keyvaultName: {{ .Values.azure.keyvault.name }}
    tenantId: {{ .Values.azure.keyvault.tenantId }}
    objects: |
      array:
    {{- range $name, $value := .Values.azure.secretKeys }}
        - |
          objectName: {{ $value | replace "_" "-" }}
          objectType: secret
    {{- end }}
  secretObjects:
    - secretName: pgstac-secrets-{{ $.Release.Name }}
      type: Opaque
      data:
      {{- range $name, $value := .Values.azure.secretKeys }}
        - objectName: {{ $value | replace "_" "-" }}
          key: {{ $name }}
      {{- end }}
```

## Azure Managed Identity Setup

To use Azure Managed Identity with your Kubernetes cluster:

1. **Enable Workload Identity on your AKS cluster**:
   ```bash
   az aks update -g <resource-group> -n <cluster-name> --enable-workload-identity
   ```

2. **Create a Managed Identity**:
   ```bash
   az identity create -g <resource-group> -n eoapi-identity
   ```

3. **Configure Key Vault access**:
   ```bash
   # Get the client ID of the managed identity
   CLIENT_ID=$(az identity show -g <resource-group> -n eoapi-identity --query clientId -o tsv)
   
   # Grant access to Key Vault
   az keyvault set-policy -n <keyvault-name> --secret-permissions get list --spn $CLIENT_ID
   ```

4. **Create a federated identity credential** to connect the Kubernetes service account to the Azure managed identity:
   ```bash
   az identity federated-credential create \
     --name eoapi-federated-credential \
     --identity-name eoapi-identity \
     --resource-group <resource-group> \
     --issuer <aks-oidc-issuer> \
     --subject system:serviceaccount:<namespace>:eoapi-sa
   ```
