#!/usr/bin/env python3
"""
Pytest-based normal load tests for eoAPI services

This module provides realistic mixed-workload tests that simulate
normal production traffic patterns and sustained usage.

Fixtures are imported from conftest.py to avoid duplication.
"""

import time

from .load_tester import LoadTester


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
                f"{endpoint} failed with {result['success_rate']:.1f}% success rate "
                f"under mixed load (p95 latency: {result.get('latency_p95', 0):.0f}ms)"
            )
            assert result["total_requests"] > 0, (
                f"No requests made to {endpoint} during normal load test"
            )
            # Verify latency metrics are collected
            assert "latency_p50" in result, "Missing latency metrics"
            assert "throughput" in result, "Missing throughput metric"

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
            metrics = tester.test_concurrency_level(url, workers=3, duration=8)
            total_success += metrics["success_count"]
            total_requests += metrics["total_requests"]

            # Brief pause between workflow steps
            time.sleep(1)

        workflow_success_rate = (total_success / total_requests) * 100
        assert workflow_success_rate >= 92.0, (
            f"STAC workflow success rate {workflow_success_rate:.1f}% too low "
            f"({total_success}/{total_requests} successful, expected >= 92%)"
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
            metrics = tester.test_concurrency_level(url, workers, duration)
            results.append(metrics["success_rate"])
            time.sleep(2)  # Transition time

        avg_performance = sum(results) / len(results)
        assert avg_performance >= 95.0, (
            f"Realistic traffic pattern handling failed: {avg_performance:.1f}% "
            f"average across {len(results)} traffic phases (expected >= 95%)"
        )


class TestNormalSustained:
    """Tests for sustained normal load over extended periods"""

    def test_sustained_moderate_load(self, base_url: str):
        """Test sustained moderate load over time"""
        tester = LoadTester(base_url, max_workers=10, timeout=15)
        url = f"{base_url}/stac/collections"

        # Sustained load for 45 seconds
        metrics = tester.test_concurrency_level(url, workers=5, duration=45)

        assert metrics["success_rate"] >= 95.0, (
            f"Sustained moderate load failed: {metrics['success_rate']:.1f}% success rate "
            f"with 5 workers over 45s (expected >= 95%)"
        )
        assert metrics["total_requests"] >= 200, (
            f"Too few requests for sustained test: {metrics['total_requests']} (expected >= 200)"
        )

    def test_consistent_response_times(self, base_url: str):
        """Test that response times remain consistent under normal load"""
        tester = LoadTester(base_url, max_workers=8, timeout=10)
        url = f"{base_url}/stac/collections"

        # Collect response time samples
        response_times = []
        for _ in range(10):
            success, latency_ms = tester.make_request(url)

            if success:
                response_times.append(latency_ms / 1000)  # Convert to seconds

            time.sleep(0.5)

        if response_times:
            avg_time = sum(response_times) / len(response_times)
            max_time = max(response_times)

            # Response times should be reasonable and consistent
            assert avg_time <= 2.0, (
                f"Average response time too high: {avg_time:.2f}s "
                f"(expected <= 2.0s under normal load)"
            )
            assert max_time <= 5.0, (
                f"Max response time too high: {max_time:.2f}s "
                f"(expected <= 5.0s under normal load)"
            )

    def test_memory_stability_under_load(self, base_url: str):
        """Test that service remains stable under prolonged normal load"""
        tester = LoadTester(base_url, max_workers=8, timeout=10)
        url = f"{base_url}/raster/healthz"  # Health endpoint should be very stable

        # Run for 60 seconds with steady load
        metrics = tester.test_concurrency_level(url, workers=4, duration=60)

        # Health endpoints should be extremely reliable
        assert metrics["success_rate"] >= 98.0, (
            f"Health endpoint instability under 60s load: {metrics['success_rate']:.1f}% success rate "
            f"(expected >= 98%)"
        )


class TestNormalUserPatterns:
    """Tests simulating realistic user interaction patterns"""

    def test_concurrent_user_sessions(self, base_url: str):
        """Test multiple concurrent user sessions"""
        tester = LoadTester(base_url, max_workers=12, timeout=12)

        # Simulate 6 concurrent users, each making requests over time
        url = f"{base_url}/stac/collections"
        metrics = tester.test_concurrency_level(url, workers=6, duration=25)

        assert metrics["success_rate"] >= 93.0, (
            f"Concurrent user test failed: {metrics['success_rate']:.1f}% success rate "
            f"with 6 concurrent users over 25s (expected >= 93%)"
        )
        assert metrics["total_requests"] >= 100, (
            f"Insufficient concurrent user simulation: {metrics['total_requests']} requests (expected >= 100)"
        )

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
            metrics = tester.test_concurrency_level(url, workers, duration)
            total_success_rate += metrics["success_rate"]

        avg_session_success = total_success_rate / len(session_patterns)
        assert avg_session_success >= 94.0, (
            f"User session patterns failed: {avg_session_success:.1f}% average "
            f"across {len(session_patterns)} session types (expected >= 94%)"
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
            metrics = tester.test_concurrency_level(url, workers, duration)
            results[endpoint] = metrics

        # All endpoints should perform well under their expected load
        for endpoint, result in results.items():
            assert result["success_rate"] >= 90.0, (
                f"{endpoint} failed under expected load: {result['success_rate']:.1f}% "
                f"({result['total_requests']} requests, expected >= 90% success)"
            )
