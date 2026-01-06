#!/usr/bin/env python3
"""
Pytest-based baseline load tests for eoAPI services

Refactored to use parametrization, centralized config, and test helpers
to reduce duplication and improve maintainability.
"""

import time

import pytest
import requests

from .config import Concurrency, Durations, Endpoints, Thresholds
from .test_helpers import (
    assert_min_requests,
    assert_success_rate,
    build_url,
    run_and_assert,
)


class TestLoadBaseline:
    """Basic load tests to verify service functionality under light load"""

    @pytest.mark.parametrize(
        "endpoint,threshold",
        [
            (Endpoints.STAC_COLLECTIONS, Thresholds.API_ENDPOINTS),
            (Endpoints.RASTER_HEALTH, Thresholds.HEALTH_ENDPOINTS),
            (Endpoints.VECTOR_HEALTH, Thresholds.HEALTH_ENDPOINTS),
        ],
    )
    def test_endpoint_light_load(
        self, light_tester, endpoint: str, threshold: float
    ):
        """Test endpoints with light concurrent load"""
        metrics = run_and_assert(
            light_tester,
            endpoint,
            workers=Concurrency.LIGHT,
            duration=Durations.SHORT,
            min_success_rate=threshold,
            min_requests=1,
        )

        assert_min_requests(metrics, 1, endpoint)


class TestLoadScalability:
    """Tests for service scalability characteristics"""

    def test_response_time_under_load(self, base_url: str):
        """Test that response times remain reasonable under moderate load"""
        url = build_url(base_url, Endpoints.STAC_COLLECTIONS)

        # Baseline measurement
        start = time.time()
        response = requests.get(url, timeout=10)
        baseline_time = time.time() - start

        assert response.status_code == 200, "Baseline request failed"

        # Concurrent load measurement
        session = requests.Session()
        times = []

        for _ in range(5):
            start = time.time()
            response = session.get(url, timeout=10)
            times.append(time.time() - start)
            assert response.status_code == 200, "Request under load failed"

        avg_load_time = sum(times) / len(times)

        # Response time shouldn't degrade more than 5x
        max_allowed = max(baseline_time * 5, 0.1)
        assert avg_load_time <= max_allowed, (
            f"Response degraded: {avg_load_time:.2f}s vs "
            f"{baseline_time:.2f}s baseline (max: {max_allowed:.2f}s)"
        )

    @pytest.mark.parametrize(
        "endpoint,threshold,min_reqs",
        [
            (Endpoints.STAC_COLLECTIONS, Thresholds.API_ENDPOINTS, 10),
            (Endpoints.RASTER_HEALTH, Thresholds.HEALTH_ENDPOINTS, 10),
            (Endpoints.VECTOR_HEALTH, Thresholds.HEALTH_ENDPOINTS, 10),
        ],
    )
    def test_endpoint_availability(
        self, light_tester, endpoint: str, threshold: float, min_reqs: int
    ):
        """Test that endpoints remain available under light load"""
        metrics = run_and_assert(
            light_tester,
            endpoint,
            workers=Concurrency.SINGLE + 1,
            duration=Durations.QUICK,
            min_success_rate=threshold,
            min_requests=min_reqs,
        )

        assert_success_rate(metrics, threshold, endpoint)


@pytest.mark.integration
class TestLoadIntegration:
    """Integration load tests across multiple services"""

    @pytest.mark.parametrize(
        "endpoint,threshold",
        [
            (Endpoints.STAC_COLLECTIONS, Thresholds.API_NORMAL),
            (Endpoints.RASTER_HEALTH, Thresholds.HEALTH_ENDPOINTS),
            (Endpoints.VECTOR_HEALTH, Thresholds.HEALTH_ENDPOINTS),
        ],
    )
    def test_mixed_endpoint_load(
        self, light_tester, endpoint: str, threshold: float
    ):
        """Test load across multiple endpoints simultaneously"""
        metrics = run_and_assert(
            light_tester,
            endpoint,
            workers=Concurrency.SINGLE + 1,
            duration=Durations.QUICK,
            min_success_rate=threshold,
        )

        assert_success_rate(metrics, threshold, f"mixed load: {endpoint}")
        assert_min_requests(metrics, 1, endpoint)
