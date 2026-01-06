#!/usr/bin/env python3
"""
Load testing helper utilities

Common utilities and assertions for load tests to reduce duplication
and improve test consistency.
"""

from typing import Dict, Optional

from .config import Thresholds
from .load_tester import LoadTester


def build_url(base_url: str, endpoint: str) -> str:
    """
    Build full URL from base and endpoint

    Args:
        base_url: Base URL (with or without trailing slash)
        endpoint: Endpoint path (with or without leading slash)

    Returns:
        Complete URL
    """
    base = base_url.rstrip("/")
    endpoint = endpoint if endpoint.startswith("/") else f"/{endpoint}"
    return f"{base}{endpoint}"


def create_tester(
    base_url: str,
    max_workers: int = 10,
    timeout: int = 10,
    prometheus_url: Optional[str] = None,
    namespace: str = "eoapi",
) -> LoadTester:
    """
    Factory for creating LoadTester instances

    Args:
        base_url: Base URL for testing
        max_workers: Maximum concurrent workers
        timeout: Request timeout
        prometheus_url: Optional Prometheus URL
        namespace: Kubernetes namespace

    Returns:
        Configured LoadTester instance
    """
    return LoadTester(
        base_url=base_url,
        max_workers=max_workers,
        timeout=timeout,
        prometheus_url=prometheus_url,
        namespace=namespace,
    )


def assert_success_rate(
    metrics: Dict,
    min_rate: float,
    context: str = "Test",
) -> None:
    """
    Assert success rate meets minimum threshold

    Args:
        metrics: Metrics dictionary with success_rate
        min_rate: Minimum acceptable success rate (%)
        context: Context description for assertion message

    Raises:
        AssertionError: If success rate below threshold
    """
    success_rate = metrics.get("success_rate", 0)
    success_count = metrics.get("success_count", 0)
    total = metrics.get("total_requests", 0)

    assert success_rate >= min_rate, (
        f"{context}: {success_rate:.1f}% < {min_rate:.1f}% "
        f"({success_count}/{total} successful)"
    )


def assert_min_requests(
    metrics: Dict,
    min_count: int,
    context: str = "Test",
) -> None:
    """
    Assert minimum number of requests were made

    Args:
        metrics: Metrics dictionary with total_requests
        min_count: Minimum expected request count
        context: Context description for assertion message

    Raises:
        AssertionError: If request count below minimum
    """
    total = metrics.get("total_requests", 0)
    assert total >= min_count, (
        f"{context}: {total} requests < {min_count} expected"
    )


def assert_has_latency_metrics(metrics: Dict) -> None:
    """
    Assert that latency metrics are present

    Args:
        metrics: Metrics dictionary

    Raises:
        AssertionError: If latency metrics missing
    """
    required = ["latency_p50", "latency_p95", "latency_p99"]
    missing = [k for k in required if k not in metrics]
    assert not missing, f"Missing latency metrics: {missing}"


def assert_latency_bounds(
    metrics: Dict,
    p50_max: Optional[float] = None,
    p95_max: Optional[float] = None,
    p99_max: Optional[float] = None,
    context: str = "Test",
) -> None:
    """
    Assert latency percentiles within bounds

    Args:
        metrics: Metrics dictionary with latency_p50, latency_p95, latency_p99
        p50_max: Maximum p50 latency (ms), None to skip
        p95_max: Maximum p95 latency (ms), None to skip
        p99_max: Maximum p99 latency (ms), None to skip
        context: Context description for assertion message

    Raises:
        AssertionError: If any latency exceeds bounds
    """
    assert_has_latency_metrics(metrics)

    if p50_max is not None:
        p50 = metrics["latency_p50"]
        assert p50 <= p50_max, f"{context}: p50={p50:.0f}ms > {p50_max:.0f}ms"

    if p95_max is not None:
        p95 = metrics["latency_p95"]
        assert p95 <= p95_max, f"{context}: p95={p95:.0f}ms > {p95_max:.0f}ms"

    if p99_max is not None:
        p99 = metrics["latency_p99"]
        assert p99 <= p99_max, f"{context}: p99={p99:.0f}ms > {p99_max:.0f}ms"


def assert_has_throughput(metrics: Dict) -> None:
    """
    Assert that throughput metric is present

    Args:
        metrics: Metrics dictionary

    Raises:
        AssertionError: If throughput metric missing
    """
    assert "throughput" in metrics, "Missing throughput metric"


def assert_recovery(
    before_metrics: Dict,
    after_metrics: Dict,
    min_improvement: float = 0,
    context: str = "Recovery",
) -> None:
    """
    Assert that service recovered after stress/chaos

    Args:
        before_metrics: Metrics before recovery
        after_metrics: Metrics after recovery
        min_improvement: Minimum improvement required (percentage points)
        context: Context description for assertion message

    Raises:
        AssertionError: If recovery insufficient
    """
    before_rate = before_metrics.get("success_rate", 0)
    after_rate = after_metrics.get("success_rate", 0)
    improvement = after_rate - before_rate

    assert after_rate >= Thresholds.RECOVERY, (
        f"{context}: {after_rate:.1f}% < {Thresholds.RECOVERY:.1f}% "
        f"(recovered from {before_rate:.1f}%)"
    )

    if min_improvement > 0:
        assert improvement >= min_improvement, (
            f"{context}: improvement {improvement:.1f}% < {min_improvement:.1f}%"
        )


def validate_metrics_structure(metrics: Dict) -> None:
    """
    Validate that metrics dictionary has required structure

    Args:
        metrics: Metrics dictionary to validate

    Raises:
        AssertionError: If required fields missing
    """
    required_fields = [
        "success_count",
        "total_requests",
        "success_rate",
        "duration",
        "throughput",
    ]

    missing = [f for f in required_fields if f not in metrics]
    assert not missing, f"Metrics missing required fields: {missing}"


def run_and_assert(
    tester: LoadTester,
    endpoint: str,
    workers: int,
    duration: int,
    min_success_rate: float,
    min_requests: int = 1,
) -> Dict:
    """
    Run load test and assert basic requirements

    Args:
        tester: LoadTester instance
        endpoint: Endpoint to test (relative path)
        workers: Number of concurrent workers
        duration: Test duration in seconds
        min_success_rate: Minimum acceptable success rate
        min_requests: Minimum expected request count

    Returns:
        Metrics dictionary

    Raises:
        AssertionError: If assertions fail
    """
    url = build_url(tester.base_url, endpoint)
    metrics = tester.test_concurrency_level(url, workers, duration)

    validate_metrics_structure(metrics)
    assert_success_rate(metrics, min_success_rate, endpoint)
    assert_min_requests(metrics, min_requests, endpoint)

    return metrics
