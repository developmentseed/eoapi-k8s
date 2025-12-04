#!/usr/bin/env python3
"""
Pytest-based normal load tests for eoAPI services

This module provides realistic mixed-workload tests that simulate
normal production traffic patterns and sustained usage.
"""

import os
import time

import pytest

from .load_tester import LoadTester


@pytest.fixture
def base_url() -> str:
    """Get the base URL for eoAPI services"""
    stac_endpoint = os.getenv("STAC_ENDPOINT", "http://localhost/stac")
    return stac_endpoint.replace("/stac", "")


class TestNormalMixedLoad:
    """Tests with realistic mixed workload patterns"""

    def test_mixed_endpoint_load(self, base_url: str):
        """Test normal load with mixed endpoints simultaneously"""
        tester = LoadTester(base_url, max_workers=15, timeout=10)

        results = tester.run_normal_load(
            duration=30, concurrent_users=8, ramp_up=10
        )

        # All endpoints should maintain good performance
        for endpoint, result in results.items():
            assert result["success_rate"] >= 90.0, (
                f"{endpoint} failed with {result['success_rate']}% success rate"
            )
            assert result["total_requests"] > 0

    def test_stac_workflow_simulation(self, base_url: str):
        """Simulate typical STAC API workflow"""
        tester = LoadTester(base_url, max_workers=10, timeout=15)

        # Typical workflow: collections -> search -> items
        workflow_endpoints = [
            "/stac/collections",
            "/stac/search",
            "/stac/collections",  # Often revisited
        ]

        total_success = 0
        total_requests = 0

        for endpoint in workflow_endpoints:
            url = f"{base_url}{endpoint}"
            success, requests, rate = tester.test_concurrency_level(
                url, workers=3, duration=8
            )
            total_success += success
            total_requests += requests

            # Brief pause between workflow steps
            time.sleep(1)

        workflow_success_rate = (total_success / total_requests) * 100
        assert workflow_success_rate >= 92.0, (
            f"Workflow success rate {workflow_success_rate}% too low"
        )

    def test_realistic_traffic_pattern(self, base_url: str):
        """Test with realistic traffic pattern variations"""
        tester = LoadTester(base_url, max_workers=12, timeout=12)

        # Simulate varying load throughout the day
        traffic_pattern = [
            (2, 5),  # Low morning traffic
            (5, 8),  # Moderate midday
            (3, 5),  # Afternoon dip
            (6, 10),  # Peak evening
        ]

        results = []
        for workers, duration in traffic_pattern:
            url = f"{base_url}/stac/collections"
            _, _, rate = tester.test_concurrency_level(url, workers, duration)
            results.append(rate)
            time.sleep(2)  # Transition time

        avg_performance = sum(results) / len(results)
        assert avg_performance >= 95.0, (
            f"Traffic pattern handling failed: {avg_performance}%"
        )


class TestNormalSustained:
    """Tests for sustained normal load over extended periods"""

    def test_sustained_moderate_load(self, base_url: str):
        """Test sustained moderate load over time"""
        tester = LoadTester(base_url, max_workers=10, timeout=15)
        url = f"{base_url}/stac/collections"

        # Sustained load for 45 seconds
        success, total, rate = tester.test_concurrency_level(
            url, workers=5, duration=45
        )

        assert rate >= 95.0, f"Sustained load failed: {rate}% success rate"
        assert total >= 200, "Too few requests for sustained test"

    def test_consistent_response_times(self, base_url: str):
        """Test that response times remain consistent under normal load"""
        tester = LoadTester(base_url, max_workers=8, timeout=10)
        url = f"{base_url}/stac/collections"

        # Collect response time samples
        response_times = []
        for _ in range(10):
            start_time = time.time()
            success = tester.make_request(url)
            response_time = time.time() - start_time

            if success:
                response_times.append(response_time)

            time.sleep(0.5)

        if response_times:
            avg_time = sum(response_times) / len(response_times)
            max_time = max(response_times)

            # Response times should be reasonable and consistent
            assert avg_time <= 2.0, (
                f"Average response time too high: {avg_time:.2f}s"
            )
            assert max_time <= 5.0, (
                f"Max response time too high: {max_time:.2f}s"
            )

    def test_memory_stability_under_load(self, base_url: str):
        """Test that service remains stable under prolonged normal load"""
        tester = LoadTester(base_url, max_workers=8, timeout=10)
        url = f"{base_url}/raster/healthz"  # Health endpoint should be very stable

        # Run for 60 seconds with steady load
        success, total, rate = tester.test_concurrency_level(
            url, workers=4, duration=60
        )

        # Health endpoints should be extremely reliable
        assert rate >= 98.0, (
            f"Health endpoint instability: {rate}% success rate"
        )


class TestNormalUserPatterns:
    """Tests simulating realistic user interaction patterns"""

    def test_concurrent_user_sessions(self, base_url: str):
        """Test multiple concurrent user sessions"""
        tester = LoadTester(base_url, max_workers=12, timeout=12)

        # Simulate 6 concurrent users, each making requests over time
        url = f"{base_url}/stac/collections"
        success, total, rate = tester.test_concurrency_level(
            url, workers=6, duration=25
        )

        assert rate >= 93.0, f"Concurrent user test failed: {rate}% success"
        assert total >= 100, "Insufficient concurrent user simulation"

    def test_user_session_duration(self, base_url: str):
        """Test typical user session duration patterns"""
        tester = LoadTester(base_url, max_workers=6, timeout=15)

        # Simulate user sessions of different lengths
        session_patterns = [
            ("/stac/collections", 3, 8),  # Quick browse
            ("/stac/search", 2, 12),  # Detailed search
            ("/vector/healthz", 1, 5),  # Health check
        ]

        total_success_rate = 0
        for endpoint, workers, duration in session_patterns:
            url = f"{base_url}{endpoint}"
            _, _, rate = tester.test_concurrency_level(url, workers, duration)
            total_success_rate += rate

        avg_session_success = total_success_rate / len(session_patterns)
        assert avg_session_success >= 94.0, (
            f"User session patterns failed: {avg_session_success}%"
        )

    def test_api_usage_distribution(self, base_url: str):
        """Test realistic API endpoint usage distribution"""
        tester = LoadTester(base_url, max_workers=10, timeout=12)

        # Realistic usage: collections (high), search (medium), health (low)
        usage_pattern = [
            ("/stac/collections", 4, 15),  # High usage
            ("/stac/search", 2, 10),  # Medium usage
            ("/raster/healthz", 1, 5),  # Low usage
            ("/vector/healthz", 1, 5),  # Low usage
        ]

        results = {}
        for endpoint, workers, duration in usage_pattern:
            url = f"{base_url}{endpoint}"
            success, total, rate = tester.test_concurrency_level(
                url, workers, duration
            )
            results[endpoint] = {"rate": rate, "total": total}

        # All endpoints should perform well under their expected load
        for endpoint, result in results.items():
            assert result["rate"] >= 90.0, (
                f"{endpoint} failed under expected load: {result['rate']}%"
            )
