import pytest
import os
import psycopg2
import psycopg2.extensions


@pytest.fixture(scope='session')
def raster_endpoint():
    return os.getenv('RASTER_ENDPOINT', "http://127.0.0.1/raster")


@pytest.fixture(scope='session')
def vector_endpoint():
    return os.getenv('VECTOR_ENDPOINT', "http://127.0.0.1/vector")


@pytest.fixture(scope='session')
def stac_endpoint():
    return os.getenv('STAC_ENDPOINT', "http://127.0.0.1/stac")


@pytest.fixture(scope='session')
def db_connection():
    """Create database connection for testing."""
    # Require all database connection parameters to be explicitly set
    required_vars = ['PGHOST', 'PGPORT', 'PGDATABASE', 'PGUSER', 'PGPASSWORD']
    missing_vars = [var for var in required_vars if not os.getenv(var)]

    if missing_vars:
        pytest.fail(f"Required environment variables not set: {', '.join(missing_vars)}")

    connection_params = {
        'host': os.getenv('PGHOST'),
        'port': int(os.getenv('PGPORT')),
        'database': os.getenv('PGDATABASE'),
        'user': os.getenv('PGUSER'),
        'password': os.getenv('PGPASSWORD')
    }

    try:
        conn = psycopg2.connect(**connection_params)
        conn.set_isolation_level(psycopg2.extensions.ISOLATION_LEVEL_AUTOCOMMIT)
        yield conn
        conn.close()
    except psycopg2.Error as e:
        pytest.fail(f"Cannot connect to database: {e}")
