#!/usr/bin/env python3
"""
Pytest-based chaos tests for eoAPI services

This module provides chaos engineering tests to verify service resilience
during infrastructure failures, network issues, and resource constraints.

Fixtures are imported from conftest.py to avoid duplication.
"""

import subprocess
import time

import pytest

from .load_tester import LoadTester


class TestChaosResilience:
    """Tests for service resilience during infrastructure chaos"""

    @pytest.mark.slow
    def test_pod_failure_resilience(self, base_url: str):
        """Test service resilience during pod failures"""
        try:
            subprocess.run(
                ["kubectl", "version", "--client"],
                check=True,
                capture_output=True,
            )
        except (subprocess.CalledProcessError, FileNotFoundError):
            pytest.skip("kubectl not available or not in cluster environment")

        tester = LoadTester(base_url, timeout=5)

        results = tester.run_chaos_test(
            duration=60, kill_interval=30, endpoint="/stac/collections"
        )

        # Even with chaos, should maintain some service level
        assert results["success_rate"] >= 60.0, (
            f"Chaos test failed: {results['success_rate']:.1f}% success rate "
            f"during pod failures (expected >= 60%)"
        )

    @pytest.mark.slow
    def test_multiple_service_failures(self, base_url: str):
        """Test resilience when multiple services experience issues"""
        try:
            subprocess.run(
                ["kubectl", "get", "pods"],
                check=True,
                capture_output=True,
            )
        except (subprocess.CalledProcessError, FileNotFoundError):
            pytest.skip("kubectl not available")

        tester = LoadTester(base_url, timeout=8)

        # Test different endpoints during chaos
        endpoints = ["/stac/collections", "/raster/healthz", "/vector/healthz"]
        results = []

        for endpoint in endpoints:
            chaos_results = tester.run_chaos_test(
                duration=45,
                kill_interval=20,
                endpoint=endpoint,
            )
            results.append(chaos_results["success_rate"])

        # At least one service should maintain reasonable uptime
        max_success_rate = max(results)
        assert max_success_rate >= 70.0, (
            f"All services failed during chaos: max {max_success_rate:.1f}% "
            f"across {len(results)} endpoints (expected >= 70%)"
        )

    def test_gradual_failure_recovery(self, base_url: str):
        """Test service recovery after gradual failure introduction"""
        tester = LoadTester(base_url, max_workers=10, timeout=3)
        url = f"{base_url}/stac/collections"

        # Phase 1: Normal operation
        _, _, normal_rate = tester.test_concurrency_level(url, 3, 10)

        # Phase 2: Introduce failures (simulate with aggressive timeouts)
        aggressive_tester = LoadTester(base_url, max_workers=10, timeout=1)
        _, _, degraded_rate = aggressive_tester.test_concurrency_level(
            url, 5, 15
        )

        # Phase 3: Recovery (return to normal)
        time.sleep(5)  # Recovery time
        _, _, recovery_rate = tester.test_concurrency_level(url, 3, 10)

        assert normal_rate >= 90.0, (
            f"Baseline performance too low: {normal_rate:.1f}% (expected >= 90%)"
        )
        assert recovery_rate >= 85.0, (
            f"Service didn't recover properly after failure: {recovery_rate:.1f}% "
            f"(expected >= 85%)"
        )


class TestChaosNetwork:
    """Tests for network-related chaos scenarios"""

    def test_network_instability(self, base_url: str):
        """Test behavior under network instability"""
        # Simulate network issues with very short timeouts
        tester = LoadTester(base_url, max_workers=5, timeout=2)
        url = f"{base_url}/stac/collections"

        success, total, rate = tester.test_concurrency_level(url, 3, 10)

        # Should handle some failures gracefully
        assert rate >= 50.0, (
            f"Complete failure under network instability: {rate:.1f}% "
            f"(expected >= 50% with 2s timeout)"
        )
        assert total > 0, (
            "No requests made during instability test (expected > 0)"
        )

    def test_timeout_cascade_prevention(self, base_url: str):
        """Test that timeout issues don't cascade across requests"""
        # Use progressively shorter timeouts to simulate degradation
        timeouts = [5, 3, 1, 2, 4]  # Recovery pattern
        url = f"{base_url}/stac/collections"

        results = []
        for timeout in timeouts:
            tester = LoadTester(base_url, max_workers=3, timeout=timeout)
            _, _, rate = tester.test_concurrency_level(url, 2, 5)
            results.append(rate)
            time.sleep(1)

        # Should show recovery in later phases
        recovery_rate = results[-1]
        assert recovery_rate >= 80.0, (
            f"No recovery from timeout cascade: {recovery_rate:.1f}% in final phase "
            f"(expected >= 80%)"
        )

    def test_concurrent_failure_modes(self, base_url: str):
        """Test multiple failure modes occurring simultaneously"""
        # Combine short timeouts with high concurrency
        tester = LoadTester(base_url, max_workers=5, timeout=10)

        endpoints = ["/stac/collections", "/raster/healthz", "/vector/healthz"]
        concurrent_results = []

        # Test all endpoints simultaneously under stress
        for endpoint in endpoints:
            url = f"{base_url}{endpoint}"
            _, _, rate = tester.test_concurrency_level(url, 4, 12)
            concurrent_results.append(rate)

        # At least health endpoints should maintain some reliability
        health_rates = [r for i, r in enumerate(concurrent_results) if i > 0]
        if health_rates:
            max_health_rate = max(health_rates)
            assert max_health_rate >= 60.0, (
                f"All health endpoints failed: max {max_health_rate:.1f}% "
                f"(expected >= 60% even under concurrent failure)"
            )


class TestChaosResource:
    """Tests for resource constraint chaos scenarios"""

    def test_resource_exhaustion_simulation(self, base_url: str):
        """Test behavior when resources are constrained"""
        # Simulate resource exhaustion with many concurrent requests
        tester = LoadTester(base_url, max_workers=25, timeout=5)
        url = f"{base_url}/stac/collections"

        success, total, rate = tester.test_concurrency_level(url, 20, 15)

        # Should gracefully degrade, not completely fail
        assert rate >= 30.0, (
            f"Complete failure under resource pressure: {rate:.1f}% "
            f"with 20 workers (expected >= 30% graceful degradation)"
        )
        assert total >= 50, (
            f"Insufficient load applied for resource test: {total} requests "
            f"(expected >= 50)"
        )

    def test_memory_pressure_resilience(self, base_url: str):
        """Test resilience under simulated memory pressure"""
        # Use many concurrent connections to simulate memory pressure
        tester = LoadTester(base_url, max_workers=30, timeout=8)

        # Test with sustained high concurrency
        url = (
            f"{base_url}/raster/healthz"  # Health endpoint should be resilient
        )
        success, total, rate = tester.test_concurrency_level(url, 15, 20)

        # Health endpoints should maintain higher reliability
        assert rate >= 50.0, (
            f"Health endpoint failed under memory pressure: {rate:.1f}% "
            f"with 15 workers over 20s (expected >= 50%)"
        )

    def test_connection_pool_exhaustion(self, base_url: str):
        """Test behavior when connection pools are exhausted"""
        # Create multiple testers to exhaust connection pools
        testers = [
            LoadTester(base_url, max_workers=10, timeout=3) for _ in range(3)
        ]

        url = f"{base_url}/stac/collections"
        results = []

        # Concurrent tests from multiple testers
        for i, tester in enumerate(testers):
            _, _, rate = tester.test_concurrency_level(url, 6, 8)
            results.append(rate)

        # At least one connection pool should work reasonably
        max_rate = max(results)
        assert max_rate >= 40.0, (
            f"All connection pools failed: max {max_rate:.1f}% "
            f"across {len(results)} testers (expected >= 40%)"
        )


class TestChaosRecovery:
    """Tests for service recovery patterns after chaos events"""

    def test_automatic_recovery_timing(self, base_url: str):
        """Test automatic service recovery after failures"""
        tester = LoadTester(base_url, max_workers=8, timeout=15)
        url = f"{base_url}/stac/collections"

        # Phase 1: Induce failures
        failure_tester = LoadTester(base_url, max_workers=20, timeout=1)
        _, _, failure_rate = failure_tester.test_concurrency_level(url, 15, 10)

        # Phase 2: Monitor recovery over time
        recovery_times = [5, 10, 15]  # Recovery intervals
        recovery_rates = []

        for wait_time in recovery_times:
            time.sleep(wait_time)
            _, _, rate = tester.test_concurrency_level(url, 3, 5)
            recovery_rates.append(rate)

        # Should show progressive recovery
        final_rate = recovery_rates[-1]
        assert final_rate >= 80.0, (
            f"No recovery after chaos: {final_rate:.1f}% after {recovery_times[-1]}s "
            f"(expected >= 80%)"
        )

    def test_service_degradation_levels(self, base_url: str):
        """Test graceful degradation under increasing chaos"""
        url = f"{base_url}/stac/collections"

        # Progressive degradation test
        chaos_levels = [
            (5, 10, 5),  # Light chaos
            (3, 15, 8),  # Medium chaos
            (1, 20, 12),  # Heavy chaos
        ]

        degradation_rates = []
        for timeout, workers, duration in chaos_levels:
            tester = LoadTester(base_url, max_workers=25, timeout=timeout)
            _, _, rate = tester.test_concurrency_level(url, workers, duration)
            degradation_rates.append(rate)
            time.sleep(3)  # Brief recovery between tests

        # Should show controlled degradation, not cliff-edge failure
        assert degradation_rates[0] >= 70.0, (
            f"Failed at low chaos level: {degradation_rates[0]:.1f}% (expected >= 70%)"
        )
        assert min(degradation_rates) >= 20.0, (
            f"Complete failure under chaos: {min(degradation_rates):.1f}% "
            f"(expected >= 20% even at high chaos)"
        )
