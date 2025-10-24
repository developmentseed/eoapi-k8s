---
title: "Azure AKS Setup"
description: "Azure configuration with managed PostgreSQL, Key Vault integration, and Workload Identity"
external_links:
  - name: "eoapi-k8s Repository"
    url: "https://github.com/developmentseed/eoapi-k8s"
  - name: "Azure Kubernetes Service Documentation"
    url: "https://docs.microsoft.com/en-us/azure/aks/"
  - name: "Azure CLI Documentation"
    url: "https://docs.microsoft.com/en-us/cli/azure/"
  - name: "Azure PostgreSQL Documentation"
    url: "https://docs.microsoft.com/en-us/azure/postgresql/"
---

# Microsoft Azure Setup

## Using Azure Managed PostgreSQL

With the unified PostgreSQL configuration, connecting to an Azure managed PostgreSQL instance has become more straightforward. Here's how to set it up:

1. **Create an Azure PostgreSQL server**: Create a PostgreSQL server using the Azure portal or the Azure CLI.

   ```bash
   # Example of creating an Azure PostgreSQL flexible server
   az postgres flexible-server create \
     --resource-group myResourceGroup \
     --name mypostgresserver \
     --location westus \
     --admin-user myusername \
     --admin-password mypassword \
     --sku-name Standard_B1ms
   ```

2. **Create a PostgreSQL database**: After creating the server, create a database for your EOAPI deployment.

   ```bash
   # Create a database on the Azure PostgreSQL server
   az postgres flexible-server db create \
     --resource-group myResourceGroup \
     --server-name mypostgresserver \
     --database-name eoapi
   ```

3. **Configure firewall rules**: Ensure that the PostgreSQL server allows connections from your Kubernetes cluster's IP address.

   ```bash
   # Allow connections from your AKS cluster's outbound IP
   az postgres flexible-server firewall-rule create \
     --resource-group myResourceGroup \
     --server-name mypostgresserver \
     --name AllowAKS \
     --start-ip-address <AKS-outbound-IP> \
     --end-ip-address <AKS-outbound-IP>
   ```

4. **Store PostgreSQL credentials in Azure Key Vault**: Create secrets in your Azure Key Vault to store the database connection information.

   ```bash
   # Create Key Vault secrets for PostgreSQL connection
   az keyvault secret set --vault-name your-keyvault-name --name db-host --value "mypostgresserver.postgres.database.azure.com"
   az keyvault secret set --vault-name your-keyvault-name --name db-port --value "5432"
   az keyvault secret set --vault-name your-keyvault-name --name db-name --value "eoapi"
   az keyvault secret set --vault-name your-keyvault-name --name db-username --value "myusername@mypostgresserver"
   az keyvault secret set --vault-name your-keyvault-name --name db-password --value "mypassword"
   ```

## Azure Configuration for eoapi-k8s

When deploying on Azure, you'll need to configure several settings in your values.yaml file. Below are the configurations needed for proper integration with Azure services.

### Common Azure Configuration

First, configure the service account with Azure Workload Identity:

```yaml
# Service Account Configuration
serviceAccount:
  create: true
  annotations:
    azure.workload.identity/client-id: "your-client-id"
    azure.workload.identity/tenant-id: "your-tenant-id"
```

### Unified PostgreSQL Configuration

Use the unified PostgreSQL configuration with the `external-secret` type to connect to your Azure managed PostgreSQL:

```yaml
# Configure PostgreSQL connection to use Azure managed PostgreSQL with secrets from Key Vault
postgresql:
  # Use external-secret type to get credentials from a pre-existing secret
  type: "external-secret"

  # Basic connection information
  external:
    host: "mypostgresserver.postgres.database.azure.com"  # Can be overridden by secret values
    port: "5432"                                          # Can be overridden by secret values
    database: "eoapi"                                     # Can be overridden by secret values

    # Reference to a secret that will be created by Azure Key Vault integration
    existingSecret:
      name: "azure-pg-credentials"
      keys:
        username: "username"     # Secret key for the username
        password: "password"     # Secret key for the password
        host: "host"             # Secret key for the host (optional)
        port: "port"             # Secret key for the port (optional)
        database: "database"     # Secret key for the database name (optional)
```

With this configuration, you're telling the PostgreSQL components to use an external PostgreSQL database and to get its connection details from a Kubernetes secret named `azure-pg-credentials`. This secret will be created using Azure Key Vault integration as described below.

### Disable internal PostgreSQL cluster

When using Azure managed PostgreSQL, you should disable the internal PostgreSQL cluster:

```yaml
postgrescluster:
  enabled: false
```

### Azure Key Vault Integration

To allow your Kubernetes pods to access PostgreSQL credentials stored in Azure Key Vault, create a SecretProviderClass:

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: azure-pg-secret-provider
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    clientID: "your-client-id"
    keyvaultName: "your-keyvault-name"
    tenantId: "your-tenant-id"
    objects: |
      array:
        - |
          objectName: db-host
          objectType: secret
          objectAlias: host
        - |
          objectName: db-port
          objectType: secret
          objectAlias: port
        - |
          objectName: db-name
          objectType: secret
          objectAlias: database
        - |
          objectName: db-username
          objectType: secret
          objectAlias: username
        - |
          objectName: db-password
          objectType: secret
          objectAlias: password
  secretObjects:
    - secretName: azure-pg-credentials
      type: Opaque
      data:
        - objectName: host
          key: host
        - objectName: port
          key: port
        - objectName: database
          key: database
        - objectName: username
          key: username
        - objectName: password
          key: password
```

### Service Configuration

For services that need to mount the Key Vault secrets, add the following configuration to each service (pgstacBootstrap, raster, stac, vector, multidim):

```yaml
# Define a common volume configuration for all services
commonVolumeConfig: &commonVolumeConfig
  labels:
    azure.workload.identity/use: "true"
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
          secretProviderClass: azure-pg-secret-provider

# Apply the common volume configuration to each service
pgstacBootstrap:
  enabled: true
  settings:
    <<: *commonVolumeConfig

raster:
  enabled: true
  settings:
    <<: *commonVolumeConfig

stac:
  enabled: true
  settings:
    <<: *commonVolumeConfig

vector:
  enabled: true
  settings:
    <<: *commonVolumeConfig

multidim:
  enabled: false  # set to true if needed
  settings:
    <<: *commonVolumeConfig
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

## Complete Example

Here's a complete example configuration for connecting EOAPI to an Azure managed PostgreSQL database:

```yaml
# Service Account Configuration with Azure Workload Identity
serviceAccount:
  create: true
  annotations:
    azure.workload.identity/client-id: "12345678-1234-1234-1234-123456789012"
    azure.workload.identity/tenant-id: "87654321-4321-4321-4321-210987654321"

# Unified PostgreSQL Configuration - using external-secret type
postgresql:
  type: "external-secret"
  external:
    host: "mypostgresserver.postgres.database.azure.com"
    port: "5432"
    database: "eoapi"
    existingSecret:
      name: "azure-pg-credentials"
      keys:
        username: "username"
        password: "password"
        host: "host"
        port: "port"
        database: "database"

# Disable internal PostgreSQL cluster
postgrescluster:
  enabled: false

# Define common volume configuration with Azure Key Vault integration
commonVolumeConfig: &commonVolumeConfig
  labels:
    azure.workload.identity/use: "true"
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
          secretProviderClass: azure-pg-secret-provider

# Apply the common volume configuration to each service
pgstacBootstrap:
  enabled: true
  settings:
    <<: *commonVolumeConfig

stac:
  enabled: true
  settings:
    <<: *commonVolumeConfig

raster:
  enabled: true
  settings:
    <<: *commonVolumeConfig

vector:
  enabled: true
  settings:
    <<: *commonVolumeConfig

multidim:
  enabled: false
  settings:
    <<: *commonVolumeConfig
```

Make sure to create the SecretProviderClass as shown in the "Azure Key Vault Integration" section above before deploying EOAPI with this configuration.
