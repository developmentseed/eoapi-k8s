#! /usr/bin/env python3

# This script is used to setup the pgstac database.
# It is run as a job in the pgstacbootstrap pod.
# It is important that this script and all of its steps are idempotent.

import os
import psycopg
from psycopg import sql
from psycopg.conninfo import make_conninfo
from pypgstac.db import PgstacDB
from pypgstac.migrate import Migrate

admin_db_conninfo = make_conninfo(os.environ['PGADMIN_URI'])
print("[ REGISTER ]: postgis")
with psycopg.connect(admin_db_conninfo, autocommit=True) as conn:
    with conn.cursor() as cur:
        cur.execute(sql.SQL("CREATE EXTENSION IF NOT EXISTS postgis;"))

pgdb = PgstacDB(dsn=os.environ['PGADMIN_URI'], debug=True)
print(f"[ VERSION ]: {pgdb.version=}")
Migrate(pgdb).run_migration(pgdb.version)

with psycopg.connect(admin_db_conninfo, autocommit=True) as conn:
    with conn.cursor() as cur:
        # NOTE: most of these should've been set up by postgresql operator
        # see `helm-chart/eoapi/values.yaml:postgrescluster` but in case
        # they haven't been
        cur.execute(
            sql.SQL(
                "GRANT CONNECT ON DATABASE {db_name} TO {username};"
                "GRANT CREATE ON DATABASE {db_name} TO {username};"  # Allow schema creation
                "GRANT USAGE ON SCHEMA public TO {username};"
                "ALTER DEFAULT PRIVILEGES IN SCHEMA public "
                "GRANT ALL PRIVILEGES ON TABLES TO {username};"
                "ALTER DEFAULT PRIVILEGES IN SCHEMA public "
                "GRANT ALL PRIVILEGES ON SEQUENCES TO {username};"
                "GRANT pgstac_read TO {username};"
                "GRANT pgstac_ingest TO {username};"
                "GRANT pgstac_admin TO {username};"
                "ALTER USER {username} SET search_path TO pgstac, public;" # add pgstac to search_path by default
            ).format(
                db_name=sql.Identifier(os.environ["POSTGRES_DBNAME"]),
                username=sql.Identifier(os.environ["POSTGRES_USER"]),
            )
        )

with psycopg.connect(admin_db_conninfo, autocommit=True) as conn:
    with conn.cursor() as cur:
        cur.execute(
            sql.SQL(
                "INSERT INTO pgstac.pgstac_settings (name, value) "
                "   VALUES "
                "       ('context', 'auto'),"
                "       ('context_estimated_count', '100000'),"
                "       ('context_estimated_cost', '100000'),"
                "       ('context_stats_ttl', '1 day')"
                "   ON CONFLICT ON CONSTRAINT pgstac_settings_pkey DO UPDATE SET value = excluded.value;"
            )
        )
