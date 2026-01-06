#!/usr/bin/env python3
"""
Shared pytest fixtures for load testing

Enhanced fixtures using centralized configuration and test helpers.
"""

import os
from typing import Dict

import pytest

from .config import Endpoints, Profiles, Thresholds
from .load_tester import LoadTester
from .test_helpers import create_tester


@pytest.fixture(scope="session")
def base_url() -> str:
    """
    Get the base URL for eoAPI services

    Returns base URL from STAC_ENDPOINT env or defaults to http://localhost
    """
    stac_endpoint = os.getenv("STAC_ENDPOINT", "http://localhost/stac")
    return stac_endpoint.replace("/stac", "")


@pytest.fixture(scope="session")
def endpoints() -> type[Endpoints]:
    """Provide endpoints configuration"""
    return Endpoints


@pytest.fixture(scope="session")
def thresholds() -> type[Thresholds]:
    """Provide success rate thresholds"""
    return Thresholds


@pytest.fixture(scope="function")
def load_tester(base_url: str) -> LoadTester:
    """
    Create LoadTester for general load testing

    Args:
        base_url: Base URL from base_url fixture

    Returns:
        LoadTester configured with normal profile
    """
    return create_tester(
        base_url=base_url,
        max_workers=Profiles.NORMAL.max_workers,
        timeout=Profiles.NORMAL.timeout,
    )


@pytest.fixture(scope="function")
def stress_tester(base_url: str) -> LoadTester:
    """
    Create LoadTester optimized for stress testing

    Args:
        base_url: Base URL from base_url fixture

    Returns:
        LoadTester configured with stress profile
    """
    return create_tester(
        base_url=base_url,
        max_workers=Profiles.STRESS.max_workers,
        timeout=Profiles.STRESS.timeout,
    )


@pytest.fixture(scope="function")
def chaos_tester(base_url: str) -> LoadTester:
    """
    Create LoadTester for chaos testing

    Args:
        base_url: Base URL from base_url fixture

    Returns:
        LoadTester configured with chaos profile
    """
    return create_tester(
        base_url=base_url,
        max_workers=Profiles.CHAOS.max_workers,
        timeout=Profiles.CHAOS.timeout,
    )


@pytest.fixture(scope="function")
def light_tester(base_url: str) -> LoadTester:
    """
    Create LoadTester for light load testing

    Args:
        base_url: Base URL from base_url fixture

    Returns:
        LoadTester configured with light profile
    """
    return create_tester(
        base_url=base_url,
        max_workers=Profiles.LIGHT.max_workers,
        timeout=Profiles.LIGHT.timeout,
    )


@pytest.fixture(scope="session")
def endpoint_thresholds() -> Dict[str, float]:
    """
    Map endpoints to appropriate success rate thresholds

    Returns:
        Dictionary mapping endpoint patterns to thresholds
    """
    return {
        "healthz": Thresholds.HEALTH_ENDPOINTS,
        "collections": Thresholds.API_ENDPOINTS,
        "search": Thresholds.API_ENDPOINTS,
    }
