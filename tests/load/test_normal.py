#!/usr/bin/env python3
"""
Pytest-based normal load tests for eoAPI services

Refactored to use parametrization, centralized config, and test helpers
to reduce duplication and improve maintainability.
"""

import time

from .config import Concurrency, Durations, Endpoints, Thresholds
from .test_helpers import (
    assert_has_latency_metrics,
    assert_has_throughput,
    assert_min_requests,
    assert_success_rate,
    build_url,
    run_and_assert,
)


class TestNormalMixedLoad:
    """Tests with realistic mixed workload patterns"""

    def test_mixed_endpoint_load(self, load_tester):
        """Test normal load with mixed endpoints simultaneously"""
        results = load_tester.run_normal_load(
            duration=Durations.MODERATE, concurrent_users=8, ramp_up=10
        )

        for endpoint, metrics in results.items():
            assert_success_rate(metrics, Thresholds.API_SUSTAINED, endpoint)
            assert_min_requests(metrics, 1, endpoint)
            assert_has_latency_metrics(metrics)
            assert_has_throughput(metrics)

    def test_stac_workflow_simulation(self, load_tester):
        """Simulate typical STAC API workflow"""
        workflow = [
            (
                Endpoints.STAC_COLLECTIONS,
                Concurrency.LIGHT,
                Durations.NORMAL - 2,
            ),
            (Endpoints.STAC_SEARCH, Concurrency.LIGHT, Durations.NORMAL - 2),
            (
                Endpoints.STAC_COLLECTIONS,
                Concurrency.LIGHT,
                Durations.NORMAL - 2,
            ),
        ]

        total_success = 0
        total_requests = 0

        for endpoint, workers, duration in workflow:
            metrics = run_and_assert(
                load_tester,
                endpoint,
                workers,
                duration,
                min_success_rate=Thresholds.API_NORMAL,
            )
            total_success += metrics["success_count"]
            total_requests += metrics["total_requests"]
            time.sleep(1)

        workflow_success_rate = (total_success / total_requests) * 100
        assert workflow_success_rate >= Thresholds.API_NORMAL, (
            f"STAC workflow: {workflow_success_rate:.1f}% < {Thresholds.API_NORMAL:.1f}% "
            f"({total_success}/{total_requests})"
        )

    def test_realistic_traffic_pattern(self, load_tester):
        """Test with realistic traffic pattern variations"""
        traffic_pattern = [
            (Concurrency.SINGLE + 1, Durations.SHORT),  # Low morning
            (Concurrency.MODERATE, Durations.NORMAL - 2),  # Moderate midday
            (Concurrency.LIGHT, Durations.SHORT),  # Afternoon dip
            (Concurrency.MODERATE + 1, Durations.NORMAL),  # Peak evening
        ]

        results = []
        for workers, duration in traffic_pattern:
            metrics = run_and_assert(
                load_tester,
                Endpoints.STAC_COLLECTIONS,
                workers,
                duration,
                min_success_rate=Thresholds.API_ENDPOINTS,
            )
            results.append(metrics["success_rate"])
            time.sleep(2)

        avg_performance = sum(results) / len(results)
        assert avg_performance >= Thresholds.API_ENDPOINTS, (
            f"Traffic pattern handling: {avg_performance:.1f}% < {Thresholds.API_ENDPOINTS:.1f}%"
        )


class TestNormalSustained:
    """Tests for sustained normal load over extended periods"""

    def test_sustained_moderate_load(self, load_tester):
        """Test sustained moderate load over time"""
        metrics = run_and_assert(
            load_tester,
            Endpoints.STAC_COLLECTIONS,
            workers=Concurrency.MODERATE,
            duration=Durations.MODERATE + 15,
            min_success_rate=Thresholds.API_ENDPOINTS,
            min_requests=200,
        )

        assert_success_rate(metrics, Thresholds.API_ENDPOINTS, "sustained load")
        assert_min_requests(metrics, 200, "sustained load")

    def test_consistent_response_times(self, load_tester):
        """Test that response times remain consistent under normal load"""
        url = build_url(load_tester.base_url, Endpoints.STAC_COLLECTIONS)

        response_times = []
        for _ in range(10):
            success, latency_ms = load_tester.make_request(url)
            if success:
                response_times.append(latency_ms / 1000)
            time.sleep(0.5)

        assert response_times, "No successful requests collected"

        avg_time = sum(response_times) / len(response_times)
        max_time = max(response_times)

        assert avg_time <= 2.0, f"Avg response time {avg_time:.2f}s > 2.0s"
        assert max_time <= 5.0, f"Max response time {max_time:.2f}s > 5.0s"

    def test_memory_stability_under_load(self, load_tester):
        """Test that service remains stable under prolonged normal load"""
        metrics = run_and_assert(
            load_tester,
            Endpoints.RASTER_HEALTH,
            workers=Concurrency.MODERATE - 1,
            duration=Durations.LONG,
            min_success_rate=Thresholds.HEALTH_ENDPOINTS,
        )

        assert_success_rate(
            metrics, Thresholds.HEALTH_ENDPOINTS, "60s stability test"
        )


class TestNormalUserPatterns:
    """Tests simulating realistic user interaction patterns"""

    def test_concurrent_user_sessions(self, load_tester):
        """Test multiple concurrent user sessions"""
        metrics = run_and_assert(
            load_tester,
            Endpoints.STAC_COLLECTIONS,
            workers=Concurrency.MODERATE + 1,
            duration=Durations.MODERATE - 5,
            min_success_rate=Thresholds.API_NORMAL,
            min_requests=100,
        )

        assert_success_rate(metrics, Thresholds.API_NORMAL, "concurrent users")
        assert_min_requests(metrics, 100, "concurrent users")

    def test_user_session_duration(self, load_tester):
        """Test typical user session duration patterns"""
        session_patterns = [
            (
                Endpoints.STAC_COLLECTIONS,
                Concurrency.LIGHT,
                Durations.NORMAL - 2,
            ),
            (
                Endpoints.STAC_SEARCH,
                Concurrency.SINGLE + 1,
                Durations.MODERATE // 2 + 2,
            ),
            (Endpoints.VECTOR_HEALTH, Concurrency.SINGLE, Durations.SHORT),
        ]

        total_success_rate = 0
        for endpoint, workers, duration in session_patterns:
            metrics = run_and_assert(
                load_tester,
                endpoint,
                workers,
                duration,
                min_success_rate=Thresholds.API_NORMAL,
            )
            total_success_rate += metrics["success_rate"]

        avg_session_success = total_success_rate / len(session_patterns)
        assert avg_session_success >= Thresholds.API_NORMAL + 1, (
            f"User sessions: {avg_session_success:.1f}% < {Thresholds.API_NORMAL + 1:.1f}%"
        )

    def test_api_usage_distribution(self, load_tester):
        """Test realistic API endpoint usage distribution"""
        usage_pattern = [
            (
                Endpoints.STAC_COLLECTIONS,
                Concurrency.MODERATE - 1,
                Durations.MODERATE // 2,
            ),
            (Endpoints.STAC_SEARCH, Concurrency.SINGLE + 1, Durations.NORMAL),
            (Endpoints.RASTER_HEALTH, Concurrency.SINGLE, Durations.SHORT),
            (Endpoints.VECTOR_HEALTH, Concurrency.SINGLE, Durations.SHORT),
        ]

        for endpoint, workers, duration in usage_pattern:
            metrics = run_and_assert(
                load_tester,
                endpoint,
                workers,
                duration,
                min_success_rate=Thresholds.API_SUSTAINED,
            )
            assert_success_rate(metrics, Thresholds.API_SUSTAINED, endpoint)
