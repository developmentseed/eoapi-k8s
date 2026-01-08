"""Test autoscaling behavior and HPA functionality."""

import json
import subprocess
import threading
import time
from typing import Any, Dict, List

import pytest
import requests
from conftest import (
    get_base_url,
    get_namespace,
    get_pod_count,
    get_pod_metrics,
    get_release_name,
    kubectl_get,
)


def generate_load(
    base_url: str,
    endpoints: List[str],
    duration: int = 60,
    concurrent_requests: int = 5,
    delay: float = 0.1,
) -> Dict[str, Any]:
    """Generate HTTP load against specified endpoints."""
    end_time = time.time() + duration
    success_count = 0
    error_count = 0
    scaling_errors = 0
    error_details: dict[str, int] = {}  # Track specific error types

    def worker() -> None:
        nonlocal success_count, error_count, scaling_errors, error_details
        while time.time() < end_time:
            for endpoint in endpoints:
                url = f"{base_url}{endpoint}"
                try:
                    response = requests.get(url, timeout=10)
                    if response.status_code in [200, 201]:
                        success_count += 1
                    elif response.status_code in [502, 503, 504]:
                        # These are expected during scaling
                        scaling_errors += 1
                        error_key = f"HTTP_{response.status_code}"
                        error_details[error_key] = error_details.get(error_key, 0) + 1
                    else:
                        error_count += 1
                        error_key = f"HTTP_{response.status_code}"
                        error_details[error_key] = error_details.get(error_key, 0) + 1
                except requests.Timeout:
                    scaling_errors += 1
                    error_details["Timeout"] = error_details.get("Timeout", 0) + 1
                except requests.ConnectionError:
                    scaling_errors += 1
                    error_details["ConnectionError"] = (
                        error_details.get("ConnectionError", 0) + 1
                    )
                except requests.RequestException as e:
                    scaling_errors += 1
                    error_key = type(e).__name__
                    error_details[error_key] = error_details.get(error_key, 0) + 1
                time.sleep(delay)

    # Start concurrent workers
    threads = []
    for _ in range(concurrent_requests):
        thread = threading.Thread(target=worker)
        thread.start()
        threads.append(thread)

    # Wait for all threads to complete
    for thread in threads:
        thread.join()

    total = success_count + error_count + scaling_errors
    # Calculate success rate treating scaling errors as partial failures (50% weight)
    effective_success = success_count + (scaling_errors * 0.5)

    return {
        "total_requests": total,
        "successful_requests": success_count,
        "failed_requests": error_count,
        "scaling_errors": scaling_errors,
        "error_details": error_details,
        "success_rate": effective_success / total if total > 0 else 0,
    }


class TestHPAConfiguration:
    def test_hpa_resources_properly_configured(self) -> None:
        namespace = get_namespace()
        result = kubectl_get("hpa", namespace=namespace)

        if result.returncode != 0:
            pytest.skip("No HPA resources found - autoscaling not enabled")

        hpas = json.loads(result.stdout)
        assert len(hpas["items"]) > 0, "No HPA resources configured"

        for hpa in hpas["items"]:
            spec = hpa["spec"]
            hpa_name = hpa["metadata"]["name"]

            assert "scaleTargetRef" in spec, f"HPA {hpa_name} missing scaleTargetRef"
            assert "minReplicas" in spec, f"HPA {hpa_name} missing minReplicas"
            assert "maxReplicas" in spec, f"HPA {hpa_name} missing maxReplicas"
            assert "metrics" in spec, f"HPA {hpa_name} missing metrics configuration"

            min_replicas = spec["minReplicas"]
            max_replicas = spec["maxReplicas"]
            assert min_replicas > 0, f"HPA {hpa_name} minReplicas must be > 0"
            assert (
                max_replicas > min_replicas
            ), f"HPA {hpa_name} maxReplicas must be > minReplicas"

            metrics = spec["metrics"]
            assert len(metrics) > 0, f"HPA {hpa_name} has no metrics configured"

            cpu_metrics = [
                m
                for m in metrics
                if m.get("type") == "Resource"
                and m.get("resource", {}).get("name") == "cpu"
            ]
            assert (
                len(cpu_metrics) > 0
            ), f"HPA {hpa_name} must have CPU metric configured"

            print(
                f"✅ HPA {hpa_name}: {min_replicas}-{max_replicas} replicas, {len(metrics)} metrics"
            )

    def test_target_deployments_exist(self) -> None:
        namespace = get_namespace()
        result = kubectl_get("hpa", namespace=namespace)

        if result.returncode != 0:
            pytest.skip("No HPA resources found")

        hpas = json.loads(result.stdout)

        for hpa in hpas["items"]:
            target_ref = hpa["spec"]["scaleTargetRef"]
            target_name = target_ref["name"]
            hpa_name = hpa["metadata"]["name"]

            # Check target deployment exists
            deploy_result = kubectl_get(
                "deployment", namespace=namespace, output="json"
            )
            assert deploy_result.returncode == 0, "Cannot list deployments"

            deployments = json.loads(deploy_result.stdout)
            target_deployment = next(
                (
                    d
                    for d in deployments["items"]
                    if d["metadata"]["name"] == target_name
                ),
                None,
            )

            assert (
                target_deployment is not None
            ), f"HPA {hpa_name} target deployment {target_name} not found"

            # Check deployment has ready replicas
            status = target_deployment.get("status", {})
            ready_replicas = status.get("readyReplicas", 0)
            assert (
                ready_replicas > 0
            ), f"Target deployment {target_name} has no ready replicas"

            print(
                f"✅ HPA {hpa_name} target deployment {target_name} is ready ({ready_replicas} replicas)"
            )


class TestCPUScaling:
    def test_cpu_metrics_collection(self) -> None:
        """Verify CPU metrics are being collected for HPA targets."""
        namespace = get_namespace()
        services = ["stac", "raster", "vector"]

        metrics_available = []

        for service in services:
            try:
                pod_metrics = get_pod_metrics(namespace, service)
                if pod_metrics:
                    metrics_available.append(service)
                    for metric in pod_metrics:
                        print(
                            f"✅ {service} pod {metric['pod']}: CPU={metric['cpu']}, Memory={metric['memory']}"
                        )
            except Exception as e:
                print(f"⚠️  Cannot get metrics for {service}: {e}")

        assert len(metrics_available) > 0, "No CPU metrics available for any service"

    def test_hpa_cpu_utilization_calculation(self) -> None:
        """Verify HPA calculates CPU utilization correctly."""
        namespace = get_namespace()
        result = kubectl_get("hpa", namespace=namespace)

        if result.returncode != 0:
            pytest.skip("No HPA resources found")

        hpas = json.loads(result.stdout)

        for hpa in hpas["items"]:
            hpa_name = hpa["metadata"]["name"]
            status = hpa.get("status", {})

            # Check if HPA has current metrics
            current_metrics = status.get("currentMetrics", [])
            cpu_metrics = [
                m
                for m in current_metrics
                if m.get("type") == "Resource"
                and m.get("resource", {}).get("name") == "cpu"
            ]

            if cpu_metrics:
                cpu_utilization = cpu_metrics[0]["resource"]["current"].get(
                    "averageUtilization"
                )
                if cpu_utilization is not None:
                    assert (
                        0 <= cpu_utilization <= 1000
                    ), f"Invalid CPU utilization: {cpu_utilization}%"
                    print(f"✅ HPA {hpa_name} CPU utilization: {cpu_utilization}%")
                else:
                    print(
                        f"⚠️  HPA {hpa_name} CPU metric exists but no utilization value"
                    )
            else:
                # Check conditions for why metrics might not be available
                conditions = status.get("conditions", [])
                for condition in conditions:
                    if (
                        condition["type"] == "ScalingActive"
                        and condition["status"] == "False"
                    ):
                        print(
                            f"⚠️  HPA {hpa_name} scaling not active: {condition.get('message', 'Unknown reason')}"
                        )
                        break
                else:
                    print(f"⚠️  HPA {hpa_name} no CPU metrics available yet")

    def test_cpu_resource_requests_alignment(self) -> None:
        """Verify CPU resource requests are properly set for percentage calculations."""
        namespace = get_namespace()
        services = ["stac", "raster", "vector"]

        for service in services:
            release_name = get_release_name()
            result = kubectl_get(
                "pods",
                namespace=namespace,
                label_selector=f"app={release_name}-{service}",
            )

            if result.returncode != 0:
                continue

            pods = json.loads(result.stdout)
            running_pods = [
                p for p in pods["items"] if p["status"]["phase"] == "Running"
            ]

            if not running_pods:
                continue

            pod = running_pods[0]  # Check first running pod
            containers = pod["spec"]["containers"]

            main_container = next((c for c in containers if c["name"] == service), None)
            if not main_container:
                continue

            resources = main_container.get("resources", {})
            requests = resources.get("requests", {})

            if "cpu" not in requests:
                print(
                    f"⚠️  Service {service} missing CPU requests - HPA percentage calculation may be inaccurate"
                )
                continue

            cpu_request = requests["cpu"]
            print(f"✅ Service {service} CPU request: {cpu_request}")

            # Parse CPU request to verify it's reasonable
            if cpu_request.endswith("m"):
                cpu_millicores = int(cpu_request[:-1])
                assert cpu_millicores > 0, f"Service {service} has zero CPU request"
                assert (
                    cpu_millicores <= 2000
                ), f"Service {service} has very high CPU request: {cpu_millicores}m"


class TestScalingBehavior:
    """Test actual scaling behavior under load."""

    @pytest.mark.slow
    def test_load_response_scaling(self) -> None:
        """Generate load and verify scaling response (when possible)."""
        namespace = get_namespace()
        base_url = get_base_url()

        # Test endpoints that should generate CPU load
        # Use simple GET endpoints that are guaranteed to work
        load_endpoints = [
            "/stac/collections",
            "/stac",
            "/raster/",
            "/vector/collections",
        ]

        # Check initial state
        initial_pod_counts: Dict[str, int] = {}
        services = ["stac", "raster", "vector"]

        for service in services:
            initial_pod_counts[service] = get_pod_count(namespace, service)

        print(f"Initial pod counts: {initial_pod_counts}")

        # Skip test if we can't connect to services
        try:
            response = requests.get(f"{base_url}/stac/collections", timeout=5)
            if response.status_code != 200:
                pytest.skip("Cannot access API endpoints for load testing")
        except requests.RequestException:
            pytest.skip("API endpoints not accessible for load testing")

        # Generate moderate load for limited time (suitable for CI)
        load_duration = 90  # 1.5 minutes
        concurrent_requests = 8

        print(
            f"Generating load: {concurrent_requests} concurrent requests for {load_duration}s"
        )

        # Start load generation
        load_stats = generate_load(
            base_url=base_url,
            endpoints=load_endpoints,
            duration=load_duration,
            concurrent_requests=concurrent_requests,
            delay=0.05,  # 20 requests/second per worker
        )

        print(f"Load test completed: {load_stats}")
        if load_stats.get("scaling_errors", 0) > 0:
            print(
                f"  Note: {load_stats['scaling_errors']} scaling-related errors (502/503/504 or timeouts)"
            )
        if load_stats.get("error_details"):
            print(f"  Error breakdown: {load_stats['error_details']}")

        # Wait a bit for metrics to propagate and scaling to potentially occur
        print("Waiting for metrics to propagate and potential scaling...")
        time.sleep(30)

        # Check final state
        final_pod_counts: Dict[str, int] = {}
        for service in services:
            final_pod_counts[service] = get_pod_count(namespace, service)

        print(f"Final pod counts: {final_pod_counts}")

        # Check HPA metrics after load
        result = kubectl_get("hpa", namespace=namespace)
        if result.returncode == 0:
            hpas = json.loads(result.stdout)
            for hpa in hpas["items"]:
                hpa_name = hpa["metadata"]["name"]
                status = hpa.get("status", {})
                current_metrics = status.get("currentMetrics", [])

                cpu_metrics = [
                    m
                    for m in current_metrics
                    if m.get("type") == "Resource"
                    and m.get("resource", {}).get("name") == "cpu"
                ]

                if cpu_metrics:
                    cpu_utilization = cpu_metrics[0]["resource"]["current"].get(
                        "averageUtilization"
                    )
                    print(f"Post-load HPA {hpa_name} CPU: {cpu_utilization}%")

        # During scaling, we expect some transient errors
        # Accept 80% success rate as pods scale up/down
        assert load_stats["success_rate"] > 0.8, (
            f"Load test had low success rate: {load_stats['success_rate']:.2%} "
            f"(scaling errors: {load_stats.get('scaling_errors', 0)})"
        )
        assert (
            load_stats["total_requests"] > 100
        ), "Load test generated insufficient requests"

        # Note: In CI environments with limited resources, actual scaling may not occur
        # The important thing is that the system handled the load successfully
        scaling_occurred = any(
            final_pod_counts[svc] > initial_pod_counts[svc]
            for svc in services
            if svc in initial_pod_counts and svc in final_pod_counts
        )

        if scaling_occurred:
            print("✅ Scaling occurred during load test")
        else:
            print(
                "⚠️  No scaling occurred - may be due to CI resource constraints or low load thresholds"
            )

    def test_scaling_stabilization_windows(self) -> None:
        """Verify HPA respects stabilization windows in configuration."""
        namespace = get_namespace()
        result = kubectl_get("hpa", namespace=namespace)

        if result.returncode != 0:
            pytest.skip("No HPA resources found")

        hpas = json.loads(result.stdout)

        for hpa in hpas["items"]:
            hpa_name = hpa["metadata"]["name"]
            spec = hpa["spec"]

            behavior = spec.get("behavior", {})
            if not behavior:
                print(f"⚠️  HPA {hpa_name} has no scaling behavior configured")
                continue

            # Check scale up behavior
            scale_up = behavior.get("scaleUp", {})
            if scale_up:
                stabilization = scale_up.get("stabilizationWindowSeconds", 0)
                policies = scale_up.get("policies", [])
                print(
                    f"✅ HPA {hpa_name} scale-up: {stabilization}s stabilization, {len(policies)} policies"
                )

            # Check scale down behavior
            scale_down = behavior.get("scaleDown", {})
            if scale_down:
                stabilization = scale_down.get("stabilizationWindowSeconds", 0)
                policies = scale_down.get("policies", [])
                print(
                    f"✅ HPA {hpa_name} scale-down: {stabilization}s stabilization, {len(policies)} policies"
                )


class TestRequestRateScaling:
    """Test request rate-based autoscaling (when available)."""

    def test_custom_metrics_for_request_rate(self) -> None:
        """Check if custom metrics for request rate scaling are available."""
        # Check if custom metrics API has request rate metrics
        result = subprocess.run(
            ["kubectl", "get", "--raw", "/apis/custom.metrics.k8s.io/v1beta1"],
            capture_output=True,
            text=True,
        )

        if result.returncode != 0:
            pytest.skip("Custom metrics API not available")

        api_response = json.loads(result.stdout)
        resources = api_response.get("resources", [])

        # Look for nginx ingress controller metrics
        request_rate_metrics = [
            r
            for r in resources
            if "nginx_ingress_controller" in r.get("name", "")
            and "requests" in r.get("name", "")
        ]

        if request_rate_metrics:
            print(f"✅ Found {len(request_rate_metrics)} request rate metrics")
            for metric in request_rate_metrics:
                print(f"  - {metric['name']}")
        else:
            print(
                "⚠️  No request rate metrics available - may require ingress controller metrics configuration"
            )

    def test_hpa_request_rate_metrics(self) -> None:
        """Verify HPA can access request rate metrics (when configured)."""
        namespace = get_namespace()
        result = kubectl_get("hpa", namespace=namespace)

        if result.returncode != 0:
            pytest.skip("No HPA resources found")

        hpas = json.loads(result.stdout)

        for hpa in hpas["items"]:
            hpa_name = hpa["metadata"]["name"]
            status = hpa.get("status", {})
            current_metrics = status.get("currentMetrics", [])

            # Look for custom metrics (request rate)
            custom_metrics = [
                m
                for m in current_metrics
                if m.get("type") in ["Pods", "Object"]
                and "nginx_ingress_controller" in str(m)
            ]

            if custom_metrics:
                print(f"✅ HPA {hpa_name} has custom metrics available")
                for metric in custom_metrics:
                    print(f"  - {metric}")
            else:
                # Check if it's configured but not yet available
                spec_metrics = hpa["spec"]["metrics"]
                configured_custom = [
                    m for m in spec_metrics if m.get("type") in ["Pods", "Object"]
                ]

                if configured_custom:
                    print(
                        f"⚠️  HPA {hpa_name} has custom metrics configured but not available yet"
                    )
                else:
                    print(
                        f"ℹ️  HPA {hpa_name} uses only CPU metrics (no request rate scaling)"
                    )


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
