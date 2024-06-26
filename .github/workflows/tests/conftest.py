import pytest
import os


@pytest.fixture(scope='session')
def raster_endpoint():
    return os.getenv('RASTER_ENDPOINT', "http://127.0.0.1/raster")


@pytest.fixture(scope='session')
def vector_endpoint():
    return os.getenv('VECTOR_ENDPOINT', "http://127.0.0.1/vector")


@pytest.fixture(scope='session')
def stac_endpoint():
    return os.getenv('STAC_ENDPOINT', "http://127.0.0.1/stac")
