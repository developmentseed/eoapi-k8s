#!/usr/bin/env python3
"""
Pytest-based stress tests for eoAPI services

This module provides stress testing functionality to find breaking points
and test service resilience under high load.
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


@pytest.fixture
def stress_tester(base_url: str) -> LoadTester:
    """Create a LoadTester instance optimized for stress testing"""
    return LoadTester(base_url=base_url, max_workers=50, timeout=10)


class TestStressBreakingPoints:
    """Tests to find service breaking points under increasing load"""

    @pytest.mark.slow
    def test_stac_collections_stress(self, stress_tester: LoadTester):
        """Find breaking point for STAC collections endpoint"""
        breaking_point = stress_tester.find_breaking_point(
            endpoint="/stac/collections",
            success_threshold=90.0,
            step_size=3,
            test_duration=5,
            cooldown=1,
        )

        assert breaking_point >= 6, f"Breaking point {breaking_point} too low"

    @pytest.mark.slow
    def test_stac_search_stress(self, stress_tester: LoadTester):
        """Find breaking point for STAC search endpoint"""
        breaking_point = stress_tester.find_breaking_point(
            endpoint="/stac/search",
            success_threshold=85.0,  # Lower threshold for search
            step_size=2,
            test_duration=8,
            cooldown=2,
        )

        assert breaking_point >= 4, (
            f"Search breaking point {breaking_point} too low"
        )

    def test_health_endpoints_stress(self, stress_tester: LoadTester):
        """Test health endpoints under stress - should handle high load"""
        for endpoint in ["/raster/healthz", "/vector/healthz"]:
            breaking_point = stress_tester.find_breaking_point(
                endpoint=endpoint,
                success_threshold=95.0,  # Health endpoints should be more resilient
                step_size=5,
                test_duration=3,
                cooldown=1,
            )

            assert breaking_point >= 10, (
                f"{endpoint} breaking point {breaking_point} too low"
            )


class TestStressResilience:
    """Tests for service resilience and recovery under stress"""

    @pytest.mark.slow
    def test_service_recovery_after_stress(self, base_url: str):
        """Test that services recover properly after high stress"""
        tester = LoadTester(base_url, max_workers=20, timeout=5)
        url = f"{base_url}/stac/collections"

        # Apply high stress load
        _, _, stress_rate = tester.test_concurrency_level(
            url, workers=15, duration=5
        )

        # Allow recovery time
        time.sleep(3)

        # Test normal load after stress
        _, _, recovery_rate = tester.test_concurrency_level(
            url, workers=2, duration=5
        )

        assert recovery_rate >= 95.0, (
            f"Service didn't recover properly: {recovery_rate}%"
        )

    def test_sustained_high_load(self, base_url: str):
        """Test service behavior under sustained high load"""
        tester = LoadTester(base_url, max_workers=15, timeout=8)
        url = f"{base_url}/stac/collections"

        # Sustained load for 30 seconds
        _, _, success_rate = tester.test_concurrency_level(
            url, workers=8, duration=30
        )

        assert success_rate >= 80.0, (
            f"Sustained load failed: {success_rate}% success rate"
        )

    def test_burst_load_handling(self, base_url: str):
        """Test handling of burst traffic patterns"""
        tester = LoadTester(base_url, max_workers=25, timeout=5)
        url = f"{base_url}/stac/collections"

        results = []

        # Simulate burst pattern: high -> low -> high
        for workers, duration in [(1, 3), (12, 5), (2, 3), (15, 5)]:
            _, _, rate = tester.test_concurrency_level(url, workers, duration)
            results.append(rate)
            time.sleep(1)  # Brief pause between bursts

        # All burst phases should maintain reasonable performance
        avg_performance = sum(results) / len(results)
        assert avg_performance >= 85.0, (
            f"Burst handling failed: {avg_performance}% average performance"
        )


class TestStressLimits:
    """Tests to verify service limits and thresholds"""

    @pytest.mark.slow
    def test_maximum_concurrent_users(self, stress_tester: LoadTester):
        """Test behavior at maximum designed concurrent user limit"""
        # Test at high concurrency level
        url = f"{stress_tester.base_url}/stac/collections"

        _, _, success_rate = stress_tester.test_concurrency_level(
            url, workers=25, duration=10
        )

        # Should handle some level of high concurrency
        assert success_rate >= 70.0, (
            f"High concurrency test failed: {success_rate}% success rate"
        )

    def test_timeout_behavior_under_load(self, base_url: str):
        """Test timeout behavior when system is under stress"""
        # Use shorter timeout to trigger timeout conditions
        tester = LoadTester(base_url, max_workers=20, timeout=2)
        url = f"{base_url}/stac/collections"

        _, total, _ = tester.test_concurrency_level(url, workers=10, duration=8)

        # Should make reasonable number of attempts even with timeouts
        assert total >= 30, f"Too few requests attempted: {total}"

    def test_error_rate_under_stress(self, base_url: str):
        """Test that error rates remain within acceptable bounds under stress"""
        tester = LoadTester(base_url, max_workers=30, timeout=5)
        url = f"{base_url}/stac/collections"

        success, total, success_rate = tester.test_concurrency_level(
            url, workers=20, duration=15
        )

        error_rate = ((total - success) / total) * 100 if total > 0 else 0

        # Error rate should be less than 30% even under high stress
        assert error_rate <= 30.0, (
            f"Error rate too high under stress: {error_rate}%"
        )
