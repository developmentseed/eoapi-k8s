import os
from typing import Any, Generator

import psycopg2
import psycopg2.extensions
import pytest


@pytest.fixture(scope="session")
def raster_endpoint() -> str:
    return os.getenv("RASTER_ENDPOINT", "http://127.0.0.1/raster")


@pytest.fixture(scope="session")
def vector_endpoint() -> str:
    return os.getenv("VECTOR_ENDPOINT", "http://127.0.0.1/vector")


@pytest.fixture(scope="session")
def stac_endpoint() -> str:
    return os.getenv("STAC_ENDPOINT", "http://127.0.0.1/stac")


@pytest.fixture(scope="session")
def db_connection() -> Generator[Any, None, None]:
    """Create database connection for testing."""
    # Require all database connection parameters to be explicitly set
    required_vars = ["PGHOST", "PGPORT", "PGDATABASE", "PGUSER", "PGPASSWORD"]
    missing_vars = [var for var in required_vars if not os.getenv(var)]

    if missing_vars:
        pytest.fail(
            f"Required environment variables not set: {', '.join(missing_vars)}"
        )

    # All required vars are guaranteed to exist due to check above
    try:
        conn = psycopg2.connect(
            host=os.environ["PGHOST"],
            port=int(os.environ["PGPORT"]),
            database=os.environ["PGDATABASE"],
            user=os.environ["PGUSER"],
            password=os.environ["PGPASSWORD"],
        )
        conn.set_isolation_level(psycopg2.extensions.ISOLATION_LEVEL_AUTOCOMMIT)
        yield conn
        conn.close()
    except psycopg2.Error as e:
        pytest.fail(f"Cannot connect to database: {e}")
