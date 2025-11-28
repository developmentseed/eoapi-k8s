#!/usr/bin/env python3
"""
Pytest-based stress tests for eoAPI services

This module provides stress testing functionality to find breaking points
and test service resilience under high load.

Fixtures are imported from conftest.py to avoid duplication.
"""

import time

import pytest

from .load_tester import LoadTester


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

        assert breaking_point >= 6, (
            f"Breaking point {breaking_point} too low for STAC collections endpoint"
        )

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
            f"Search endpoint breaking point {breaking_point} too low "
            f"(threshold may need adjustment for this endpoint)"
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
                f"{endpoint} breaking point {breaking_point} too low "
                f"(health endpoints should handle higher load)"
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
            f"Service didn't recover properly after stress: {recovery_rate:.1f}% "
            f"(expected >= 95%)"
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
            f"Sustained high load performance too low: {success_rate:.1f}% "
            f"(expected >= 80%)"
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
            f"Burst traffic handling failed: {avg_performance:.1f}% average "
            f"(expected >= 85% across {len(results)} burst phases)"
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
            f"High concurrency test failed: {success_rate:.1f}% success rate "
            f"with 25 concurrent workers (expected >= 70%)"
        )

    def test_timeout_behavior_under_load(self, base_url: str):
        """Test timeout behavior when system is under stress"""
        # Use shorter timeout to trigger timeout conditions
        tester = LoadTester(base_url, max_workers=20, timeout=2)
        url = f"{base_url}/stac/collections"

        _, total, _ = tester.test_concurrency_level(url, workers=10, duration=8)

        # Should make reasonable number of attempts even with timeouts
        assert total >= 30, (
            f"Too few requests attempted under stress with short timeout: {total} "
            f"(expected >= 30)"
        )

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
            f"Error rate too high under stress: {error_rate:.1f}% "
            f"({total - success}/{total} failures, expected error rate <= 30%)"
        )
