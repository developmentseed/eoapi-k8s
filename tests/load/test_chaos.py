#!/usr/bin/env python3
"""
Pytest-based chaos tests for eoAPI services

Refactored to use parametrization, centralized config, and test helpers
to reduce duplication and improve maintainability.
"""

import subprocess
import time

import pytest

from .config import Concurrency, Durations, Endpoints, Thresholds
from .test_helpers import (
    assert_recovery,
    assert_success_rate,
    build_url,
    create_tester,
)


def check_kubectl_available() -> bool:
    """Check if kubectl is available"""
    try:
        subprocess.run(
            ["kubectl", "version", "--client"],
            check=True,
            capture_output=True,
        )
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False


class TestChaosResilience:
    """Tests for service resilience during infrastructure chaos"""

    @pytest.mark.slow
    def test_pod_failure_resilience(self, chaos_tester):
        """Test service resilience during pod failures"""
        if not check_kubectl_available():
            pytest.skip("kubectl not available")

        results = chaos_tester.run_chaos_test(
            duration=Durations.LONG // 5,
            kill_interval=30,
            endpoint=Endpoints.STAC_COLLECTIONS,
        )

        assert_success_rate(results, Thresholds.CHAOS_MODERATE, "pod failure chaos")

    @pytest.mark.slow
    @pytest.mark.parametrize(
        "endpoint,threshold",
        [
            (Endpoints.STAC_COLLECTIONS, Thresholds.CHAOS_MODERATE),
            (Endpoints.RASTER_HEALTH, Thresholds.CHAOS_HIGH),
            (Endpoints.VECTOR_HEALTH, Thresholds.CHAOS_HIGH),
        ],
    )
    def test_multiple_service_failures(
        self, chaos_tester, endpoint: str, threshold: float
    ):
        """Test resilience when services experience chaos"""
        if not check_kubectl_available():
            pytest.skip("kubectl not available")

        results = chaos_tester.run_chaos_test(
            duration=45, kill_interval=20, endpoint=endpoint
        )

        assert_success_rate(results, threshold, f"chaos: {endpoint}")

    def test_gradual_failure_recovery(self, load_tester):
        """Test service recovery after gradual failure introduction"""
        url = build_url(load_tester.base_url, Endpoints.STAC_COLLECTIONS)

        # Phase 1: Normal operation
        normal_metrics = load_tester.test_concurrency_level(
            url, Concurrency.LIGHT, Durations.NORMAL
        )

        # Phase 2: Introduce failures (aggressive timeout)
        aggressive = create_tester(
            base_url=load_tester.base_url, max_workers=10, timeout=1
        )
        degraded_metrics = aggressive.test_concurrency_level(
            url, Concurrency.MODERATE, Durations.MODERATE // 2
        )

        # Phase 3: Recovery
        time.sleep(5)
        recovery_metrics = load_tester.test_concurrency_level(
            url, Concurrency.LIGHT, Durations.NORMAL
        )

        assert_success_rate(normal_metrics, Thresholds.API_SUSTAINED, "baseline")
        assert_recovery(degraded_metrics, recovery_metrics, context="gradual")


class TestChaosNetwork:
    """Tests for network-related chaos scenarios"""

    def test_network_instability(self, load_tester):
        """Test behavior under network instability"""
        tester = create_tester(base_url=load_tester.base_url, max_workers=5, timeout=2)
        url = build_url(tester.base_url, Endpoints.STAC_COLLECTIONS)

        metrics = tester.test_concurrency_level(
            url, Concurrency.LIGHT, Durations.NORMAL
        )

        assert_success_rate(metrics, Thresholds.CHAOS_LOW, "network instability")
        assert metrics["total_requests"] > 0, "No requests made"

    def test_timeout_cascade_prevention(self, load_tester):
        """Test that timeout issues don't cascade across requests"""
        timeouts = [5, 3, 1, 2, 4]  # Recovery pattern
        url = build_url(load_tester.base_url, Endpoints.STAC_COLLECTIONS)

        results = []
        for timeout in timeouts:
            tester = create_tester(
                base_url=load_tester.base_url, max_workers=3, timeout=timeout
            )
            metrics = tester.test_concurrency_level(
                url, Concurrency.SINGLE + 1, Durations.SHORT
            )
            results.append(metrics)
            time.sleep(1)

        recovery_rate = results[-1]["success_rate"]
        assert recovery_rate >= Thresholds.STRESS_MODERATE, (
            f"No recovery from timeout cascade: {recovery_rate:.1f}% "
            f"< {Thresholds.STRESS_MODERATE:.1f}%"
        )

    @pytest.mark.parametrize(
        "endpoint,threshold",
        [
            (Endpoints.STAC_COLLECTIONS, Thresholds.CHAOS_MODERATE),
            (Endpoints.RASTER_HEALTH, Thresholds.CHAOS_MODERATE),
            (Endpoints.VECTOR_HEALTH, Thresholds.CHAOS_MODERATE),
        ],
    )
    def test_concurrent_failure_modes(
        self, load_tester, endpoint: str, threshold: float
    ):
        """Test multiple failure modes occurring simultaneously"""
        metrics = load_tester.test_concurrency_level(
            build_url(load_tester.base_url, endpoint),
            Concurrency.MODERATE - 1,
            Durations.MODERATE // 2 + 2,
        )

        assert_success_rate(metrics, threshold, f"concurrent failure: {endpoint}")


class TestChaosResource:
    """Tests for resource constraint chaos scenarios"""

    def test_resource_exhaustion_simulation(self, load_tester):
        """Test behavior when resources are constrained"""
        tester = create_tester(base_url=load_tester.base_url, max_workers=25, timeout=5)
        url = build_url(tester.base_url, Endpoints.STAC_COLLECTIONS)

        metrics = tester.test_concurrency_level(
            url, Concurrency.STRESS, Durations.MODERATE // 2
        )

        assert_success_rate(metrics, Thresholds.DEGRADED, "resource exhaustion")
        assert (
            metrics["total_requests"] >= 50
        ), f"Insufficient load: {metrics['total_requests']} < 50"

    def test_memory_pressure_resilience(self, load_tester):
        """Test resilience under simulated memory pressure"""
        tester = create_tester(base_url=load_tester.base_url, max_workers=30, timeout=8)
        url = build_url(tester.base_url, Endpoints.RASTER_HEALTH)

        metrics = tester.test_concurrency_level(
            url, Concurrency.HIGH, Durations.MODERATE - 10
        )

        assert_success_rate(metrics, Thresholds.CHAOS_LOW, "memory pressure")

    def test_connection_pool_exhaustion(self, load_tester):
        """Test behavior when connection pools are exhausted"""
        testers = [
            create_tester(base_url=load_tester.base_url, max_workers=10, timeout=3)
            for _ in range(3)
        ]

        url = build_url(load_tester.base_url, Endpoints.STAC_COLLECTIONS)
        results = []

        for tester in testers:
            metrics = tester.test_concurrency_level(
                url, Concurrency.MODERATE + 1, Durations.NORMAL - 2
            )
            results.append(metrics["success_rate"])

        max_rate = max(results)
        assert max_rate >= Thresholds.CHAOS_MODERATE - 20, (
            f"All pools exhausted: max {max_rate:.1f}% "
            f"< {Thresholds.CHAOS_MODERATE - 20:.1f}%"
        )


class TestChaosRecovery:
    """Tests for service recovery patterns after chaos events"""

    def test_automatic_recovery_timing(self, load_tester):
        """Test automatic service recovery after failures"""
        url = build_url(load_tester.base_url, Endpoints.STAC_COLLECTIONS)

        # Induce failures
        failure_tester = create_tester(
            base_url=load_tester.base_url, max_workers=20, timeout=1
        )
        # Induce failures (don't need metrics, just stress the system)
        _ = failure_tester.test_concurrency_level(
            url, Concurrency.HIGH, Durations.NORMAL
        )

        # Monitor recovery
        recovery_times = [5, 10, 15]
        recovery_rates = []

        for wait_time in recovery_times:
            time.sleep(wait_time)
            metrics = load_tester.test_concurrency_level(
                url, Concurrency.LIGHT, Durations.SHORT
            )
            recovery_rates.append(metrics["success_rate"])

        final_rate = recovery_rates[-1]
        assert final_rate >= Thresholds.STRESS_MODERATE, (
            f"No recovery after {recovery_times[-1]}s: {final_rate:.1f}% "
            f"< {Thresholds.STRESS_MODERATE:.1f}%"
        )

    def test_service_degradation_levels(self, load_tester):
        """Test graceful degradation under increasing chaos"""
        url = build_url(load_tester.base_url, Endpoints.STAC_COLLECTIONS)

        chaos_levels = [
            (5, Concurrency.NORMAL, Durations.SHORT),  # Light
            (3, Concurrency.HIGH, Durations.NORMAL - 2),  # Medium
            (1, Concurrency.STRESS, Durations.MODERATE // 2 + 2),  # Heavy
        ]

        degradation_rates = []
        for timeout, workers, duration in chaos_levels:
            tester = create_tester(
                base_url=load_tester.base_url, max_workers=25, timeout=timeout
            )
            metrics = tester.test_concurrency_level(url, workers, duration)
            degradation_rates.append(metrics["success_rate"])
            time.sleep(3)

        assert degradation_rates[0] >= Thresholds.STRESS_LOW, (
            f"Failed at low chaos: {degradation_rates[0]:.1f}% "
            f"< {Thresholds.STRESS_LOW:.1f}%"
        )
        assert min(degradation_rates) >= Thresholds.DEGRADED - 10, (
            f"Complete failure: {min(degradation_rates):.1f}% "
            f"< {Thresholds.DEGRADED - 10:.1f}%"
        )
