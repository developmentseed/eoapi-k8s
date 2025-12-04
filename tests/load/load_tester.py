#!/usr/bin/env python3
"""
eoAPI Load Testing Utility

This module provides the core LoadTester class and CLI for all types of
load testing: stress, normal, and chaos testing.
"""

import argparse
import concurrent.futures
import os
import random
import subprocess
import sys
import time
from typing import Tuple

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry


class LoadTester:
    """Load tester for eoAPI endpoints supporting stress, normal, and chaos testing"""

    def __init__(self, base_url: str, max_workers: int = 50, timeout: int = 30):
        self.base_url = base_url.rstrip("/")
        self.max_workers = max_workers
        self.timeout = timeout
        self.session = self._create_session()

    def _create_session(self) -> requests.Session:
        """Create a session with retry strategy"""
        session = requests.Session()

        # Retry strategy
        retry_strategy = Retry(
            total=3,
            backoff_factor=1,
            status_forcelist=[429, 500, 502, 503, 504],
        )

        adapter = HTTPAdapter(max_retries=retry_strategy)
        session.mount("http://", adapter)
        session.mount("https://", adapter)

        return session

    def make_request(self, url: str) -> bool:
        """Make a single request and return success status"""
        try:
            response = self.session.get(url, timeout=self.timeout)
            return response.status_code == 200
        except Exception:
            return False

    def test_concurrency_level(
        self, url: str, workers: int, duration: int = 10
    ) -> Tuple[int, int, float]:
        """Test a specific concurrency level for a given duration"""
        print(f"Testing with {workers} concurrent requests...")

        start_time = time.time()
        success_count = 0
        total_requests = 0

        with concurrent.futures.ThreadPoolExecutor(
            max_workers=workers
        ) as executor:
            futures = []

            # Submit requests for the specified duration
            while time.time() - start_time < duration:
                future = executor.submit(self.make_request, url)
                futures.append(future)
                total_requests += 1
                time.sleep(0.1)  # Small delay between request submissions

            # Collect results
            for future in concurrent.futures.as_completed(futures):
                if future.result():
                    success_count += 1

        success_rate = (
            (success_count / total_requests) * 100 if total_requests > 0 else 0
        )
        print(
            f"Workers: {workers}, Success rate: {success_rate:.1f}% ({success_count}/{total_requests})"
        )

        return success_count, total_requests, success_rate

    def find_breaking_point(
        self,
        endpoint: str = "/stac/collections",
        success_threshold: float = 95.0,
        step_size: int = 5,
        test_duration: int = 10,
        cooldown: int = 2,
    ) -> int:
        """
        Find the breaking point by gradually increasing concurrent load

        Args:
            endpoint: API endpoint to test (relative to base_url)
            success_threshold: Minimum success rate to maintain
            step_size: Increment for number of workers
            test_duration: Duration to test each concurrency level
            cooldown: Time to wait between tests

        Returns:
            Number of workers at breaking point
        """
        url = f"{self.base_url}{endpoint}"
        print(f"Starting stress test on {url}")
        print(
            f"Max workers: {self.max_workers}, Success threshold: {success_threshold}%"
        )

        for workers in range(step_size, self.max_workers + 1, step_size):
            _, _, success_rate = self.test_concurrency_level(
                url, workers, test_duration
            )

            # Stop if success rate drops below threshold
            if success_rate < success_threshold:
                print(
                    f"Breaking point found at {workers} concurrent requests (success rate: {success_rate:.1f}%)"
                )
                return workers

            # Cool down between test levels
            if cooldown > 0:
                time.sleep(cooldown)

        print("Stress test completed - no breaking point found")
        return self.max_workers

    def run_normal_load(
        self,
        endpoints: list = None,
        duration: int = 60,
        concurrent_users: int = 10,
        ramp_up: int = 30,
    ) -> dict:
        """
        Run realistic mixed-workload test

        Args:
            endpoints: List of endpoints to test
            duration: Total test duration
            concurrent_users: Peak concurrent users
            ramp_up: Time to reach peak load

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
        print(
            f"Starting normal load test ({duration}s, {concurrent_users} users)"
        )

        for endpoint in endpoints:
            url = f"{self.base_url}{endpoint}"
            print(f"Testing {endpoint}...")

            # Gradual ramp-up
            workers = max(1, concurrent_users // len(endpoints))
            success, total, rate = self.test_concurrency_level(
                url, workers, duration // len(endpoints)
            )

            results[endpoint] = {
                "success_count": success,
                "total_requests": total,
                "success_rate": rate,
            }

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
        print(f"Starting chaos test on {url} (namespace: {namespace})")

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
        except subprocess.CalledProcessError:
            print("Warning: Could not get pod list, chaos disabled")
            pods = []

        results = {"killed_pods": [], "success_rate": 0}
        start_time = time.time()

        # Background load generation
        import threading

        load_results = {"success": 0, "total": 0}

        def generate_load():
            while time.time() - start_time < duration:
                if self.make_request(url):
                    load_results["success"] += 1
                load_results["total"] += 1
                time.sleep(0.5)

        # Start load generation
        load_thread = threading.Thread(target=generate_load)
        load_thread.start()

        # Kill pods periodically
        while time.time() - start_time < duration and pods:
            time.sleep(kill_interval)

            if pods:
                pod_to_kill = random.choice(pods)
                print(f"Killing pod: {pod_to_kill}")
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
                    print(f"Failed to kill pod {pod_to_kill}: {e}")

        load_thread.join()

        if load_results["total"] > 0:
            results["success_rate"] = (
                load_results["success"] / load_results["total"]
            ) * 100
            results.update(load_results)

        print(
            f"Chaos test completed: {results['success_rate']:.1f}% success rate, killed {len(results['killed_pods'])} pods"
        )
        return results


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
        default=30,
        help="Request timeout in seconds (default: 30)",
    )

    # Stress test arguments
    stress_group = parser.add_argument_group("stress test options")
    stress_group.add_argument("--endpoint", default="/stac/collections")
    stress_group.add_argument("--max-workers", type=int, default=50)
    stress_group.add_argument("--success-threshold", type=float, default=95.0)
    stress_group.add_argument("--step-size", type=int, default=5)
    stress_group.add_argument("--test-duration", type=int, default=10)
    stress_group.add_argument("--cooldown", type=int, default=2)

    # Normal test arguments
    normal_group = parser.add_argument_group("normal test options")
    normal_group.add_argument(
        "--duration", type=int, default=60, help="Test duration (default: 60)"
    )
    normal_group.add_argument(
        "--users", type=int, default=10, help="Concurrent users (default: 10)"
    )

    # Chaos test arguments
    chaos_group = parser.add_argument_group("chaos test options")
    chaos_group.add_argument(
        "--namespace",
        default="eoapi",
        help="Kubernetes namespace (default: eoapi)",
    )
    chaos_group.add_argument(
        "--kill-interval",
        type=int,
        default=60,
        help="Seconds between pod kills (default: 60)",
    )

    args = parser.parse_args()

    try:
        tester = LoadTester(
            base_url=args.base_url,
            max_workers=getattr(args, "max_workers", 50),
            timeout=args.timeout,
        )

        if args.test_type == "stress":
            result = tester.find_breaking_point(
                endpoint=args.endpoint,
                success_threshold=args.success_threshold,
                step_size=args.step_size,
                test_duration=args.test_duration,
                cooldown=args.cooldown,
            )
            print(f"\nStress test completed. Breaking point: {result} workers")
            sys.exit(1 if result < args.max_workers else 0)

        elif args.test_type == "normal":
            results = tester.run_normal_load(
                duration=args.duration,
                concurrent_users=args.users,
            )
            avg_success = sum(
                r["success_rate"] for r in results.values()
            ) / len(results)
            print(
                f"\nNormal load test completed. Average success rate: {avg_success:.1f}%"
            )
            sys.exit(0 if avg_success >= 95 else 1)

        elif args.test_type == "chaos":
            results = tester.run_chaos_test(
                namespace=args.namespace,
                duration=args.duration,
                kill_interval=args.kill_interval,
            )
            print(
                f"\nChaos test completed. Success rate: {results['success_rate']:.1f}%"
            )
            sys.exit(0 if results["success_rate"] >= 80 else 1)

    except KeyboardInterrupt:
        print(f"\n{args.test_type.title()} test interrupted by user")
        sys.exit(2)
    except Exception as e:
        print(f"{args.test_type.title()} test failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
