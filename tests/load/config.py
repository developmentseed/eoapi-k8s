#!/usr/bin/env python3
"""
Load testing configuration and constants

Centralized configuration for all load testing parameters, thresholds,
and test profiles.
"""

from dataclasses import dataclass


@dataclass(frozen=True)
class TestProfile:
    """Test profile with worker and timeout configuration"""

    max_workers: int
    timeout: int


class Profiles:
    """Predefined test profiles for different load scenarios"""

    LIGHT = TestProfile(max_workers=5, timeout=10)
    NORMAL = TestProfile(max_workers=10, timeout=15)
    STRESS = TestProfile(max_workers=50, timeout=10)
    CHAOS = TestProfile(max_workers=20, timeout=8)


class Thresholds:
    """Success rate thresholds for different test scenarios"""

    HEALTH_ENDPOINTS = 98.0
    API_ENDPOINTS = 95.0
    API_NORMAL = 93.0
    API_SUSTAINED = 90.0
    STRESS_HIGH = 90.0
    STRESS_MODERATE = 80.0
    STRESS_LOW = 70.0
    CHAOS_HIGH = 70.0
    CHAOS_MODERATE = 60.0
    CHAOS_LOW = 50.0
    DEGRADED = 30.0
    RECOVERY = 85.0


class Endpoints:
    """Common API endpoints for testing"""

    STAC_COLLECTIONS = "/stac/collections"
    STAC_SEARCH = "/stac/search"
    RASTER_HEALTH = "/raster/healthz"
    VECTOR_HEALTH = "/vector/healthz"

    @classmethod
    def all_health(cls) -> list[str]:
        """Return all health check endpoints"""
        return [cls.RASTER_HEALTH, cls.VECTOR_HEALTH]

    @classmethod
    def all_api(cls) -> list[str]:
        """Return all API endpoints"""
        return [cls.STAC_COLLECTIONS, cls.STAC_SEARCH]

    @classmethod
    def all_endpoints(cls) -> list[str]:
        """Return all endpoints"""
        return cls.all_api() + cls.all_health()


class Durations:
    """Test duration constants (seconds)"""

    QUICK = 3
    SHORT = 5
    NORMAL = 10
    MODERATE = 30
    LONG = 60
    EXTENDED = 300


class Concurrency:
    """Concurrency level constants"""

    SINGLE = 1
    LIGHT = 3
    MODERATE = 5
    NORMAL = 10
    HIGH = 15
    STRESS = 20
    EXTREME = 25


class Latency:
    """Latency threshold constants (milliseconds)"""

    P50_FAST = 100
    P50_ACCEPTABLE = 200
    P95_FAST = 500
    P95_ACCEPTABLE = 1000
    P99_FAST = 2000
    P99_ACCEPTABLE = 5000


# Default values
DEFAULT_MAX_WORKERS = 50
DEFAULT_TIMEOUT = 30
DEFAULT_SUCCESS_THRESHOLD = 95.0
DEFAULT_NAMESPACE = "eoapi"

# Load testing parameters
REQUEST_DELAY = 0.1  # Delay between request submissions
RETRY_TOTAL = 3
RETRY_BACKOFF_FACTOR = 1
RETRY_STATUS_CODES = [429, 500, 502, 503, 504]
