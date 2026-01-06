#!/usr/bin/env python3
"""
eoAPI Load Testing Utility

This module provides the core LoadTester class and CLI for all types of
load testing: stress, normal, and chaos testing.
"""

import argparse
import concurrent.futures
import json
import logging
import os
import random
import statistics
import subprocess
import sys
import time
from datetime import datetime
from typing import Dict, List, Optional, Tuple

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

try:
    from .prometheus_utils import (
        PrometheusClient,
        collect_test_metrics,
        summarize_metrics,
    )

    PROMETHEUS_AVAILABLE = True
except ImportError:
    PROMETHEUS_AVAILABLE = False
    logger.warning("Prometheus utilities not available")

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)

# Constants
DEFAULT_MAX_WORKERS = 50
DEFAULT_TIMEOUT = 30
DEFAULT_SUCCESS_THRESHOLD = 95.0
LIGHT_LOAD_WORKERS = 3
LIGHT_LOAD_DURATION = 5
MODERATE_LOAD_WORKERS = 10
STRESS_TEST_WORKERS = 20
REQUEST_DELAY = 0.1  # Delay between request submissions
RETRY_TOTAL = 3
RETRY_BACKOFF_FACTOR = 1
RETRY_STATUS_CODES = [429, 500, 502, 503, 504]


class LoadTester:
    """Load tester for eoAPI endpoints supporting stress, normal, and chaos testing"""

    def __init__(
        self,
        base_url: str,
        max_workers: int = DEFAULT_MAX_WORKERS,
        timeout: int = DEFAULT_TIMEOUT,
        prometheus_url: Optional[str] = None,
        namespace: str = "eoapi",
    ):
        """
        Initialize LoadTester with validation

        Args:
            base_url: Base URL for eoAPI services
            max_workers: Maximum number of concurrent workers
            timeout: Request timeout in seconds
            prometheus_url: Optional Prometheus URL for infrastructure metrics
            namespace: Kubernetes namespace for Prometheus queries

        Raises:
            ValueError: If parameters are invalid
        """
        # Validate inputs
        if not base_url or not isinstance(base_url, str):
            raise ValueError(f"Invalid base_url: {base_url}")
        if not base_url.startswith(("http://", "https://")):
            raise ValueError(
                f"base_url must start with http:// or https://: {base_url}"
            )
        if not isinstance(max_workers, int) or max_workers <= 0:
            raise ValueError(
                f"max_workers must be a positive integer: {max_workers}"
            )
        if not isinstance(timeout, int) or timeout <= 0:
            raise ValueError(f"timeout must be a positive integer: {timeout}")

        self.base_url = base_url.rstrip("/")
        self.max_workers = max_workers
        self.timeout = timeout
        self.prometheus_url = prometheus_url
        self.namespace = namespace
        self.session = self._create_session()

        # Initialize Prometheus client if available and URL provided
        self.prometheus = None
        if PROMETHEUS_AVAILABLE and prometheus_url:
            self.prometheus = PrometheusClient(prometheus_url)
            if self.prometheus.available:
                logger.info(f"Prometheus integration enabled: {prometheus_url}")
            else:
                logger.info("Prometheus integration disabled (unavailable)")
                self.prometheus = None

        logger.info(
            f"LoadTester initialized: base_url={self.base_url}, "
            f"max_workers={self.max_workers}, timeout={self.timeout}"
        )

    def _create_session(self) -> requests.Session:
        """Create a session with retry strategy"""
        session = requests.Session()

        # Retry strategy
        retry_strategy = Retry(
            total=RETRY_TOTAL,
            backoff_factor=RETRY_BACKOFF_FACTOR,
            status_forcelist=RETRY_STATUS_CODES,
        )

        adapter = HTTPAdapter(max_retries=retry_strategy)
        session.mount("http://", adapter)
        session.mount("https://", adapter)

        logger.debug("HTTP session created with retry strategy")
        return session

    def make_request(self, url: str) -> Tuple[bool, float]:
        """
        Make a single request and return success status with latency

        Args:
            url: URL to request

        Returns:
            Tuple of (success, latency_ms) where success is True if 200 status
        """
        start_time = time.time()
        try:
            response = self.session.get(url, timeout=self.timeout)
            latency_ms = (time.time() - start_time) * 1000
            success = response.status_code == 200
            if not success:
                logger.debug(
                    f"Request to {url} returned status {response.status_code}"
                )
            return success, latency_ms
        except requests.exceptions.Timeout:
            latency_ms = (time.time() - start_time) * 1000
            logger.debug(f"Request to {url} timed out after {self.timeout}s")
            return False, latency_ms
        except requests.exceptions.ConnectionError as e:
            latency_ms = (time.time() - start_time) * 1000
            logger.debug(f"Connection error for {url}: {e}")
            return False, latency_ms
        except requests.exceptions.RequestException as e:
            latency_ms = (time.time() - start_time) * 1000
            logger.debug(f"Request failed for {url}: {e}")
            return False, latency_ms
        except Exception as e:
            latency_ms = (time.time() - start_time) * 1000
            logger.error(f"Unexpected error in make_request for {url}: {e}")
            return False, latency_ms

    def test_concurrency_level(
        self,
        url: str,
        workers: int,
        duration: int = 10,
        collect_infra_metrics: bool = False,
    ) -> Dict:
        """
        Test a specific concurrency level for a given duration

        Args:
            url: URL to test
            workers: Number of concurrent workers
            duration: Test duration in seconds
            collect_infra_metrics: Whether to collect Prometheus infrastructure metrics

        Returns:
            Dict with metrics including success rate, latencies, throughput, and optional infra metrics
        """
        logger.info(
            f"Testing {url} with {workers} concurrent requests for {duration}s"
        )

        test_start = datetime.now()
        start_time = time.time()
        success_count = 0
        total_requests = 0
        latencies: List[float] = []

        with concurrent.futures.ThreadPoolExecutor(
            max_workers=workers
        ) as executor:
            futures = []

            # Submit requests for the specified duration
            while time.time() - start_time < duration:
                future = executor.submit(self.make_request, url)
                futures.append(future)
                total_requests += 1
                time.sleep(REQUEST_DELAY)

            # Collect results and latencies
            for future in concurrent.futures.as_completed(futures):
                success, latency_ms = future.result()
                if success:
                    success_count += 1
                latencies.append(latency_ms)

        test_end = datetime.now()
        actual_duration = time.time() - start_time
        success_rate = (
            (success_count / total_requests) * 100 if total_requests > 0 else 0
        )

        # Calculate latency metrics
        metrics = {
            "success_count": success_count,
            "total_requests": total_requests,
            "success_rate": success_rate,
            "duration": actual_duration,
            "throughput": total_requests / actual_duration
            if actual_duration > 0
            else 0,
        }

        if latencies:
            sorted_latencies = sorted(latencies)
            metrics.update(
                {
                    "latency_min": min(latencies),
                    "latency_max": max(latencies),
                    "latency_avg": statistics.mean(latencies),
                    "latency_p50": statistics.median(sorted_latencies),
                    "latency_p95": sorted_latencies[
                        int(len(sorted_latencies) * 0.95)
                    ]
                    if len(sorted_latencies) > 1
                    else sorted_latencies[0],
                    "latency_p99": sorted_latencies[
                        int(len(sorted_latencies) * 0.99)
                    ]
                    if len(sorted_latencies) > 1
                    else sorted_latencies[0],
                }
            )

        logger.info(
            f"Workers: {workers}, Success: {success_rate:.1f}% ({success_count}/{total_requests}), "
            f"Latency p50/p95/p99: {metrics.get('latency_p50', 0):.0f}/{metrics.get('latency_p95', 0):.0f}/{metrics.get('latency_p99', 0):.0f}ms, "
            f"Throughput: {metrics['throughput']:.1f} req/s"
        )

        # Collect infrastructure metrics if requested and available
        if collect_infra_metrics and self.prometheus:
            logger.info("Collecting infrastructure metrics from Prometheus...")
            infra_metrics = collect_test_metrics(
                self.prometheus_url, self.namespace, test_start, test_end
            )
            if infra_metrics:
                metrics["infrastructure"] = infra_metrics
                summary = summarize_metrics(infra_metrics)
                logger.info(f"Infrastructure metrics: {summary}")

        return metrics

    def find_breaking_point(
        self,
        endpoint: str = "/stac/collections",
        success_threshold: float = DEFAULT_SUCCESS_THRESHOLD,
        step_size: int = 5,
        test_duration: int = 10,
        cooldown: int = 2,
    ) -> Tuple[int, Dict]:
        """
        Find the breaking point by gradually increasing concurrent load

        Args:
            endpoint: API endpoint to test (relative to base_url)
            success_threshold: Minimum success rate to maintain
            step_size: Increment for number of workers
            test_duration: Duration to test each concurrency level
            cooldown: Time to wait between tests

        Returns:
            Tuple of (breaking_point_workers, all_metrics)
        """
        url = f"{self.base_url}{endpoint}"
        logger.info(f"Starting stress test on {url}")
        logger.info(
            f"Max workers: {self.max_workers}, Success threshold: {success_threshold}%"
        )

        all_metrics = {}
        for workers in range(step_size, self.max_workers + 1, step_size):
            metrics = self.test_concurrency_level(url, workers, test_duration)
            all_metrics[workers] = metrics

            # Stop if success rate drops below threshold
            if metrics["success_rate"] < success_threshold:
                logger.info(
                    f"Breaking point found at {workers} concurrent requests "
                    f"(success rate: {metrics['success_rate']:.1f}%)"
                )
                return workers, all_metrics

            # Cool down between test levels
            if cooldown > 0:
                time.sleep(cooldown)

        logger.info("Stress test completed - no breaking point found")
        return self.max_workers, all_metrics

    def run_normal_load(
        self,
        endpoints: list = None,
        duration: int = 60,
        concurrent_users: int = MODERATE_LOAD_WORKERS,
        ramp_up: int = 30,
    ) -> dict:
        """
        Run realistic mixed-workload test

        Args:
            endpoints: List of endpoints to test
            duration: Total test duration
            concurrent_users: Peak concurrent users
            ramp_up: Time to reach peak load (currently unused)

        Returns:
            Dict with results for each endpoint
        """
        if endpoints is None:
            endpoints = [
                "/stac/collections",
                "/raster/healthz",
                "/vector/healthz",
            ]

        results = {}
        logger.info(
            f"Starting normal load test ({duration}s, {concurrent_users} users)"
        )

        for endpoint in endpoints:
            url = f"{self.base_url}{endpoint}"
            logger.info(f"Testing {endpoint}...")

            # Gradual ramp-up
            workers = max(1, concurrent_users // len(endpoints))
            metrics = self.test_concurrency_level(
                url, workers, duration // len(endpoints)
            )

            results[endpoint] = metrics

        # Add infrastructure summary if Prometheus is enabled
        if self.prometheus:
            logger.info(
                "Note: Use --collect-infra-metrics for detailed infrastructure data"
            )

        return results

    def run_chaos_test(
        self,
        namespace: str = "eoapi",
        duration: int = 300,
        kill_interval: int = 60,
        endpoint: str = "/stac/collections",
    ) -> dict:
        """
        Run chaos test by killing pods during load

        Args:
            namespace: Kubernetes namespace
            duration: Test duration
            kill_interval: Seconds between pod kills
            endpoint: Endpoint to test

        Returns:
            Test results and pod kill events
        """
        url = f"{self.base_url}{endpoint}"
        logger.info(f"Starting chaos test on {url} (namespace: {namespace})")

        # Get initial pod list
        try:
            pods = (
                subprocess.check_output(
                    [
                        "kubectl",
                        "get",
                        "pods",
                        "-n",
                        namespace,
                        "-l",
                        "app.kubernetes.io/component in (stac,raster,vector)",
                        "-o",
                        "jsonpath={.items[*].metadata.name}",
                    ],
                    text=True,
                )
                .strip()
                .split()
            )
            logger.info(f"Found {len(pods)} pods for chaos testing")
        except subprocess.CalledProcessError as e:
            logger.warning(f"Could not get pod list, chaos disabled: {e}")
            pods = []

        results = {"killed_pods": [], "success_rate": 0}
        start_time = time.time()

        # Background load generation
        import threading

        load_results = {"success": 0, "total": 0}

        def generate_load():
            while time.time() - start_time < duration:
                success, _ = self.make_request(url)
                if success:
                    load_results["success"] += 1
                load_results["total"] += 1
                time.sleep(0.5)

        # Start load generation with daemon thread for cleanup
        load_thread = threading.Thread(target=generate_load, daemon=True)
        load_thread.start()

        try:
            # Kill pods periodically
            while time.time() - start_time < duration and pods:
                time.sleep(kill_interval)

                if pods:
                    pod_to_kill = random.choice(pods)
                    logger.info(f"Killing pod: {pod_to_kill}")
                    try:
                        subprocess.run(
                            [
                                "kubectl",
                                "delete",
                                "pod",
                                pod_to_kill,
                                "-n",
                                namespace,
                            ],
                            check=True,
                            capture_output=True,
                        )
                        results["killed_pods"].append(pod_to_kill)
                        pods.remove(pod_to_kill)
                    except subprocess.CalledProcessError as e:
                        logger.error(f"Failed to kill pod {pod_to_kill}: {e}")
        finally:
            # Ensure we wait for load thread to complete
            load_thread.join(timeout=duration + 10)

        if load_results["total"] > 0:
            results["success_rate"] = (
                load_results["success"] / load_results["total"]
            ) * 100
            results.update(load_results)

        logger.info(
            f"Chaos test completed: {results['success_rate']:.1f}% success rate, "
            f"killed {len(results['killed_pods'])} pods"
        )
        return results


def print_metrics_summary(metrics: Dict, title: str = "Test Results"):
    """
    Print concise, readable metrics summary

    Args:
        metrics: Metrics dictionary from test
        title: Title for the summary
    """
    print(f"\n{'=' * 60}")
    print(f"{title}")
    print(f"{'=' * 60}")
    print(
        f"Success Rate:  {metrics.get('success_rate', 0):.1f}% "
        f"({metrics.get('success_count', 0)}/{metrics.get('total_requests', 0)})"
    )

    if "latency_p50" in metrics:
        print(
            f"Latency (ms):  p50={metrics['latency_p50']:.0f} "
            f"p95={metrics['latency_p95']:.0f} "
            f"p99={metrics['latency_p99']:.0f} "
            f"(min={metrics['latency_min']:.0f}, max={metrics['latency_max']:.0f}, avg={metrics['latency_avg']:.0f})"
        )

    if "throughput" in metrics:
        print(f"Throughput:    {metrics['throughput']:.1f} req/s")

    if "duration" in metrics:
        print(f"Duration:      {metrics['duration']:.1f}s")

    # Infrastructure metrics summary
    if "infrastructure" in metrics:
        print("\nInfrastructure Metrics:")
        summary = summarize_metrics(metrics["infrastructure"])
        for key, value in summary.items():
            print(f"  {key}: {value}")

    print(f"{'=' * 60}\n")


def export_metrics_json(metrics: Dict, filename: str):
    """
    Export metrics to JSON file

    Args:
        metrics: Metrics dictionary to export
        filename: Output filename
    """
    try:
        with open(filename, "w") as f:
            json.dump(metrics, f, indent=2)
        logger.info(f"Metrics exported to {filename}")
    except Exception as e:
        logger.error(f"Failed to export metrics: {e}")


def main():
    """Main entry point for eoAPI load testing CLI"""
    parser = argparse.ArgumentParser(description="eoAPI Load Testing CLI")

    # Test type selection
    parser.add_argument(
        "test_type",
        choices=["stress", "normal", "chaos"],
        default="stress",
        nargs="?",
        help="Type of test to run (default: stress)",
    )

    # Common arguments
    parser.add_argument(
        "--base-url",
        default=os.getenv("STAC_ENDPOINT", "http://localhost").replace(
            "/stac", ""
        ),
        help="Base URL for eoAPI (default: from STAC_ENDPOINT env or http://localhost)",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=DEFAULT_TIMEOUT,
        help=f"Request timeout in seconds (default: {DEFAULT_TIMEOUT})",
    )
    parser.add_argument(
        "--verbose",
        "-v",
        action="store_true",
        help="Enable verbose debug logging",
    )
    parser.add_argument(
        "--report-json",
        type=str,
        help="Export metrics to JSON file",
    )
    parser.add_argument(
        "--prometheus-url",
        type=str,
        default=os.getenv("PROMETHEUS_URL"),
        help="Prometheus URL for infrastructure metrics (default: from PROMETHEUS_URL env)",
    )
    parser.add_argument(
        "--namespace",
        type=str,
        default="eoapi",
        help="Kubernetes namespace (default: eoapi)",
    )
    parser.add_argument(
        "--collect-infra-metrics",
        action="store_true",
        help="Collect infrastructure metrics from Prometheus during tests",
    )

    # Stress test arguments
    stress_group = parser.add_argument_group("stress test options")
    stress_group.add_argument("--endpoint", default="/stac/collections")
    stress_group.add_argument(
        "--max-workers", type=int, default=DEFAULT_MAX_WORKERS
    )
    stress_group.add_argument(
        "--success-threshold", type=float, default=DEFAULT_SUCCESS_THRESHOLD
    )
    stress_group.add_argument("--step-size", type=int, default=5)
    stress_group.add_argument("--test-duration", type=int, default=10)
    stress_group.add_argument("--cooldown", type=int, default=2)

    # Normal test arguments
    normal_group = parser.add_argument_group("normal test options")
    normal_group.add_argument(
        "--duration", type=int, default=60, help="Test duration (default: 60)"
    )
    normal_group.add_argument(
        "--users",
        type=int,
        default=MODERATE_LOAD_WORKERS,
        help=f"Concurrent users (default: {MODERATE_LOAD_WORKERS})",
    )

    # Chaos test arguments
    chaos_group = parser.add_argument_group("chaos test options")
    chaos_group.add_argument(
        "--kill-interval",
        type=int,
        default=60,
        help="Seconds between pod kills (default: 60)",
    )

    args = parser.parse_args()

    # Set logging level based on verbosity
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
        logger.setLevel(logging.DEBUG)

    try:
        tester = LoadTester(
            base_url=args.base_url,
            max_workers=getattr(args, "max_workers", DEFAULT_MAX_WORKERS),
            timeout=args.timeout,
            prometheus_url=args.prometheus_url,
            namespace=args.namespace,
        )

        if args.test_type == "stress":
            breaking_point, all_metrics = tester.find_breaking_point(
                endpoint=args.endpoint,
                success_threshold=args.success_threshold,
                step_size=args.step_size,
                test_duration=args.test_duration,
                cooldown=args.cooldown,
            )

            # Print summary for breaking point
            if breaking_point in all_metrics:
                print_metrics_summary(
                    all_metrics[breaking_point],
                    f"Stress Test - Breaking Point at {breaking_point} workers",
                )

            # Export if requested
            if args.report_json:
                export_metrics_json(
                    {"breaking_point": breaking_point, "metrics": all_metrics},
                    args.report_json,
                )

            logger.info(
                f"Stress test completed. Breaking point: {breaking_point} workers"
            )
            sys.exit(1 if breaking_point < args.max_workers else 0)

        elif args.test_type == "normal":
            results = tester.run_normal_load(
                duration=args.duration,
                concurrent_users=args.users,
            )

            # Print summary for each endpoint
            for endpoint, metrics in results.items():
                print_metrics_summary(metrics, f"Normal Load Test - {endpoint}")

            avg_success = sum(
                r["success_rate"] for r in results.values()
            ) / len(results)

            # Export if requested
            if args.report_json:
                export_metrics_json(results, args.report_json)

            logger.info(
                f"Normal load test completed. Average success rate: {avg_success:.1f}%"
            )
            sys.exit(0 if avg_success >= DEFAULT_SUCCESS_THRESHOLD else 1)

        elif args.test_type == "chaos":
            results = tester.run_chaos_test(
                namespace=args.namespace,
                duration=args.duration,
                kill_interval=args.kill_interval,
            )

            # Print summary
            print_metrics_summary(results, "Chaos Test Results")

            # Export if requested
            if args.report_json:
                export_metrics_json(results, args.report_json)

            logger.info(
                f"Chaos test completed. Success rate: {results['success_rate']:.1f}%"
            )
            sys.exit(0 if results["success_rate"] >= 80 else 1)

    except ValueError as e:
        logger.error(f"Invalid configuration: {e}")
        sys.exit(1)
    except KeyboardInterrupt:
        logger.info(f"{args.test_type.title()} test interrupted by user")
        sys.exit(2)
    except Exception as e:
        logger.error(
            f"{args.test_type.title()} test failed: {e}", exc_info=args.verbose
        )
        sys.exit(1)


if __name__ == "__main__":
    main()
