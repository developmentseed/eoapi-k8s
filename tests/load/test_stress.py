#!/usr/bin/env python3
"""
Pytest-based stress tests for eoAPI services

Refactored to use parametrization, centralized config, and test helpers
to reduce duplication and improve maintainability.
"""

import time

import pytest

from .config import Concurrency, Durations, Endpoints, Thresholds
from .test_helpers import (
    assert_recovery,
    assert_success_rate,
    build_url,
    run_and_assert,
)


class TestStressBreakingPoints:
    """Tests to find service breaking points under increasing load"""

    @pytest.mark.slow
    @pytest.mark.parametrize(
        "endpoint,threshold,step,duration",
        [
            (Endpoints.STAC_COLLECTIONS, Thresholds.STRESS_HIGH, 3, 5),
            (Endpoints.STAC_SEARCH, Thresholds.RECOVERY, 2, 8),
        ],
    )
    def test_api_endpoint_stress(
        self,
        stress_tester,
        endpoint: str,
        threshold: float,
        step: int,
        duration: int,
    ):
        """Find breaking point for API endpoints"""
        breaking_point, all_metrics = stress_tester.find_breaking_point(
            endpoint=endpoint,
            success_threshold=threshold,
            step_size=step,
            test_duration=duration,
            cooldown=1,
        )

        min_workers = 4 if "search" in endpoint else 6
        assert (
            breaking_point >= min_workers
        ), f"{endpoint} breaking point {breaking_point} < {min_workers} workers"

    @pytest.mark.parametrize(
        "endpoint,threshold",
        [
            (Endpoints.RASTER_HEALTH, Thresholds.API_ENDPOINTS),
            (Endpoints.VECTOR_HEALTH, Thresholds.API_ENDPOINTS),
        ],
    )
    def test_health_endpoints_stress(
        self, stress_tester, endpoint: str, threshold: float
    ):
        """Test health endpoints under stress - should handle high load"""
        breaking_point, _ = stress_tester.find_breaking_point(
            endpoint=endpoint,
            success_threshold=threshold,
            step_size=5,
            test_duration=3,
            cooldown=1,
        )

        assert breaking_point >= 10, (
            f"{endpoint} breaking point {breaking_point} < 10 workers "
            f"(health endpoints should handle higher load)"
        )


class TestStressResilience:
    """Tests for service resilience and recovery under stress"""

    @pytest.mark.slow
    def test_service_recovery_after_stress(self, load_tester):
        """Test that services recover properly after high stress"""
        url = build_url(load_tester.base_url, Endpoints.STAC_COLLECTIONS)

        # Apply high stress
        stress_metrics = load_tester.test_concurrency_level(
            url, workers=Concurrency.HIGH, duration=Durations.SHORT
        )

        # Recovery period
        time.sleep(3)

        # Test normal load
        recovery_metrics = load_tester.test_concurrency_level(
            url, workers=Concurrency.SINGLE + 1, duration=Durations.SHORT
        )

        assert_recovery(stress_metrics, recovery_metrics, context="stress recovery")

    def test_sustained_high_load(self, load_tester):
        """Test service behavior under sustained high load"""
        metrics = run_and_assert(
            load_tester,
            Endpoints.STAC_COLLECTIONS,
            workers=Concurrency.NORMAL - 2,
            duration=Durations.MODERATE,
            min_success_rate=Thresholds.STRESS_MODERATE,
        )

        assert_success_rate(metrics, Thresholds.STRESS_MODERATE, "sustained load")

    def test_burst_load_handling(self, load_tester):
        """Test handling of burst traffic patterns"""
        url = build_url(load_tester.base_url, Endpoints.STAC_COLLECTIONS)

        # Burst pattern: low -> high -> low -> high
        burst_pattern = [
            (Concurrency.SINGLE, Durations.QUICK),
            (Concurrency.MODERATE + 7, Durations.SHORT),
            (Concurrency.SINGLE + 1, Durations.QUICK),
            (Concurrency.MODERATE + 10, Durations.SHORT),
        ]

        results = []
        for workers, duration in burst_pattern:
            metrics = load_tester.test_concurrency_level(url, workers, duration)
            results.append(metrics["success_rate"])
            time.sleep(1)

        avg_performance = sum(results) / len(results)
        assert avg_performance >= Thresholds.RECOVERY, (
            f"Burst handling failed: {avg_performance:.1f}% avg "
            f"< {Thresholds.RECOVERY:.1f}%"
        )


class TestStressLimits:
    """Tests to verify service limits and thresholds"""

    @pytest.mark.slow
    def test_maximum_concurrent_users(self, stress_tester):
        """Test behavior at maximum designed concurrent user limit"""
        metrics = run_and_assert(
            stress_tester,
            Endpoints.STAC_COLLECTIONS,
            workers=Concurrency.EXTREME,
            duration=Durations.NORMAL,
            min_success_rate=Thresholds.STRESS_LOW,
        )

        assert_success_rate(metrics, Thresholds.STRESS_LOW, "high concurrency")

    def test_timeout_behavior_under_load(self, load_tester):
        """Test timeout behavior when system is under stress"""
        # Use short timeout to trigger timeouts
        from .test_helpers import create_tester

        tester = create_tester(base_url=load_tester.base_url, max_workers=20, timeout=2)

        url = build_url(tester.base_url, Endpoints.STAC_COLLECTIONS)
        metrics = tester.test_concurrency_level(
            url, workers=Concurrency.NORMAL, duration=Durations.NORMAL - 2
        )

        # Should make reasonable attempts despite timeouts
        assert metrics["total_requests"] >= 30, (
            f"Too few requests under stress with short timeout: "
            f"{metrics['total_requests']} < 30"
        )

    def test_error_rate_under_stress(self, load_tester):
        """Test that error rates remain within acceptable bounds under stress"""
        url = build_url(load_tester.base_url, Endpoints.STAC_COLLECTIONS)

        metrics = load_tester.test_concurrency_level(
            url, workers=Concurrency.STRESS, duration=Durations.MODERATE // 2
        )

        error_count = metrics["total_requests"] - metrics["success_count"]
        total = metrics["total_requests"]
        error_rate = (error_count / total * 100) if total > 0 else 0

        assert error_rate <= 30.0, (
            f"Error rate too high: {error_rate:.1f}% "
            f"({error_count}/{total} failures)"
        )
