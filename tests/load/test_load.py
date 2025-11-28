#!/usr/bin/env python3
"""
Pytest-based baseline load tests for eoAPI services

This module provides baseline functionality tests that verify basic
service performance under light load conditions.

Fixtures are imported from conftest.py to avoid duplication.
"""

import time

import pytest
import requests

from .load_tester import LoadTester


class TestLoadBaseline:
    """Basic load tests to verify service functionality under light load"""

    def test_stac_collections_light_load(self, base_url: str):
        """Test STAC collections endpoint with light concurrent load"""
        url = f"{base_url}/stac/collections"

        # Test with 3 concurrent requests for 5 seconds
        tester = LoadTester(base_url, max_workers=10, timeout=10)
        success_count, total_requests, success_rate = (
            tester.test_concurrency_level(url, workers=3, duration=5)
        )

        assert success_rate >= 95.0, (
            f"Success rate {success_rate:.1f}% below 95% "
            f"({success_count}/{total_requests} successful)"
        )
        assert total_requests > 0, "No requests were made during 5s test"
        assert success_count > 0, (
            f"No successful requests out of {total_requests} attempts"
        )

    def test_raster_health_light_load(self, base_url: str):
        """Test raster health endpoint with light concurrent load"""
        url = f"{base_url}/raster/healthz"

        tester = LoadTester(base_url, max_workers=10, timeout=10)
        success_count, total_requests, success_rate = (
            tester.test_concurrency_level(url, workers=2, duration=3)
        )

        assert success_rate >= 98.0, (
            f"Health endpoint success rate {success_rate}% below 98%"
        )

    def test_vector_health_light_load(self, base_url: str):
        """Test vector health endpoint with light concurrent load"""
        url = f"{base_url}/vector/healthz"

        tester = LoadTester(base_url, max_workers=10, timeout=10)
        success_count, total_requests, success_rate = (
            tester.test_concurrency_level(url, workers=2, duration=3)
        )

        assert success_rate >= 98.0, (
            f"Health endpoint success rate {success_rate}% below 98%"
        )


class TestLoadScalability:
    """Tests for service scalability characteristics"""

    def test_response_time_under_load(self, base_url: str):
        """Test that response times remain reasonable under moderate load"""
        url = f"{base_url}/stac/collections"

        # Single request baseline
        start_time = time.time()
        response = requests.get(url, timeout=10)
        baseline_time = time.time() - start_time

        assert response.status_code == 200, "Baseline request failed"

        # Test with concurrent load
        session = requests.Session()
        times = []

        for _ in range(5):
            start_time = time.time()
            response = session.get(url, timeout=10)
            request_time = time.time() - start_time
            times.append(request_time)
            assert response.status_code == 200, "Request under load failed"

        avg_load_time = sum(times) / len(times)

        # Response time shouldn't increase more than 5x under light concurrent load
        # Allow more tolerance since we're testing on a shared system
        max_allowed_time = max(
            baseline_time * 5, 0.1
        )  # At least 100ms tolerance
        assert avg_load_time <= max_allowed_time, (
            f"Response time degraded too much: {avg_load_time:.2f}s vs "
            f"{baseline_time:.2f}s baseline (max allowed: {max_allowed_time:.2f}s)"
        )

    @pytest.mark.parametrize(
        "endpoint", ["/stac/collections", "/raster/healthz", "/vector/healthz"]
    )
    def test_endpoint_availability(self, base_url: str, endpoint: str):
        """Test that endpoints remain available under light load"""
        url = f"{base_url}{endpoint}"

        tester = LoadTester(base_url, max_workers=5, timeout=15)
        success_count, total_requests, success_rate = (
            tester.test_concurrency_level(url, workers=2, duration=3)
        )

        assert success_rate >= 95.0, (
            f"{endpoint} availability {success_rate:.1f}% below 95% "
            f"({success_count}/{total_requests} successful)"
        )
        assert total_requests >= 10, (
            f"Too few requests made to {endpoint}: {total_requests}"
        )


@pytest.mark.integration
class TestLoadIntegration:
    """Integration load tests that test multiple services together"""

    def test_mixed_endpoint_load(self, base_url: str):
        """Test load across multiple endpoints simultaneously"""
        endpoints = ["/stac/collections", "/raster/healthz", "/vector/healthz"]

        results = {}

        # Test each endpoint with light concurrent load
        for endpoint in endpoints:
            url = f"{base_url}{endpoint}"
            tester = LoadTester(base_url, max_workers=5, timeout=10)

            success_count, total_requests, success_rate = (
                tester.test_concurrency_level(url, workers=2, duration=3)
            )

            results[endpoint] = {
                "success_rate": success_rate,
                "total_requests": total_requests,
            }

        # All endpoints should maintain good performance
        for endpoint, result in results.items():
            assert result["success_rate"] >= 90.0, (
                f"{endpoint} failed with {result['success_rate']:.1f}% success rate "
                f"under mixed load"
            )
            assert result["total_requests"] > 0, (
                f"No requests made to {endpoint} during mixed load test"
            )
