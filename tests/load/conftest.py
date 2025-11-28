#!/usr/bin/env python3
"""
Shared pytest fixtures for load testing

"""

import os

import pytest

from .load_tester import LoadTester

# Constants for load testing
DEFAULT_MAX_WORKERS = 20
DEFAULT_TIMEOUT = 10
STRESS_MAX_WORKERS = 50
STRESS_TIMEOUT = 10


@pytest.fixture(scope="session")
def base_url() -> str:
    """
    Get the base URL for eoAPI services

    Returns the base URL derived from STAC_ENDPOINT environment variable
    or defaults to http://localhost
    """
    stac_endpoint = os.getenv("STAC_ENDPOINT", "http://localhost/stac")
    return stac_endpoint.replace("/stac", "")


@pytest.fixture(scope="function")
def load_tester(base_url: str) -> LoadTester:
    """
    Create a LoadTester instance for general load testing

    Args:
        base_url: Base URL from base_url fixture

    Returns:
        LoadTester configured for standard load tests
    """
    return LoadTester(
        base_url=base_url,
        max_workers=DEFAULT_MAX_WORKERS,
        timeout=DEFAULT_TIMEOUT,
    )


@pytest.fixture(scope="function")
def stress_tester(base_url: str) -> LoadTester:
    """
    Create a LoadTester instance optimized for stress testing

    Args:
        base_url: Base URL from base_url fixture

    Returns:
        LoadTester configured with higher capacity for stress tests
    """
    return LoadTester(
        base_url=base_url,
        max_workers=STRESS_MAX_WORKERS,
        timeout=STRESS_TIMEOUT,
    )
