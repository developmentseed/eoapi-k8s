# Upgrading eoAPI

## General Upgrade Process

To upgrade your eoAPI installation, use the standard Helm upgrade command:

```bash
helm upgrade eoapi devseed/eoapi
```

## Special Considerations for Pre-0.7.0 Versions

### Database Permission Changes

When upgrading from a version prior to 0.7.0, there are important database permission changes that need to be handled. In versions before 0.7.0, database schema updates were run with superuser privileges. Starting from 0.7.0, these operations are performed with the eoapi user account.

### Using the PostgreSQL Subchart

If you're using the built-in PostgreSQL cluster (default setup), follow these steps:

1. Specify your current version during the upgrade:
```bash
helm upgrade eoapi devseed/eoapi --set previousVersion=0.6.0
```

This will trigger a special upgrade job that:
- Runs with superuser privileges
- Grants necessary permissions to the eoapi user
- Ensures database schema permissions are properly configured

### Using an External Database

If you're using an external PostgreSQL database (postgresql.type set to "external-plaintext" or "external-secret"), you'll need to apply the permission changes manually. Connect to your database with superuser privileges and execute the following SQL:

```sql
\c your_database_name
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE ROLE pgstac_admin;
CREATE ROLE pgstac_read;
CREATE ROLE pgstac_ingest;
ALTER DATABASE your_database_name OWNER TO your_eoapi_user;
ALTER USER your_eoapi_user SET search_path TO pgstac, public;
ALTER DATABASE your_database_name set search_path to pgstac, public;
GRANT CONNECT ON DATABASE your_database_name TO your_eoapi_user;
GRANT ALL PRIVILEGES ON TABLES TO your_eoapi_user;
GRANT ALL PRIVILEGES ON SEQUENCES TO your_eoapi_user;
GRANT pgstac_read TO your_eoapi_user WITH ADMIN OPTION;
GRANT pgstac_ingest TO your_eoapi_user WITH ADMIN OPTION;
GRANT pgstac_admin TO your_eoapi_user WITH ADMIN OPTION;
```

Replace:
- `your_database_name` with your database name (default: eoapi)
- `your_eoapi_user` with your eoapi user name (default: eoapi)

### Upgrade Steps

1. First, check your current version:
```bash
helm list -n eoapi
```

2. If you're running a version earlier than 0.7.0:
   - For subchart users:
     ```bash
     export CURRENT_VERSION=$(helm list -n eoapi -o json | jq -r '.[].app_version')
     helm upgrade eoapi devseed/eoapi \
       --set previousVersion=$CURRENT_VERSION \
       --namespace eoapi
     ```
   - For external database users:
     Execute the SQL script shown above with superuser privileges.

3. Verify the upgrade:
```bash
# Check that all pods are running
kubectl get pods -n eoapi

# For subchart users, check the upgrade job status:
kubectl get jobs -n eoapi | grep eoapiuser-permissions-upgrade
```

### Troubleshooting

If you encounter issues during the upgrade:

1. For subchart users, check the upgrade job logs:
```bash
kubectl logs -n eoapi -l app=pgstac-eoapiuser-permissions-upgrade
```

2. Verify database permissions:
```bash
# Connect to your database (method varies based on setup)
psql -U your_superuser -d your_database_name

# Check role permissions
\du

# Verify extensions
\dx

# Check database owner
\l
```

For external databases, ensure:
- You have superuser privileges when executing the permission script
- All extensions are properly installed
- The database owner is correctly set
- The eoapi user has all necessary role memberships
