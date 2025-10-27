"""Test observability stack deployment and functionality."""

import json
import os
import subprocess
import time

import pytest
import requests


def get_namespace():
    """Get the target namespace from environment or default."""
    return os.environ.get("NAMESPACE", "eoapi")


def get_release_name():
    """Get the release name from environment or default."""
    return os.environ.get("RELEASE_NAME", "eoapi")


def kubectl_get(resource, namespace=None, label_selector=None, output="json"):
    """Execute kubectl get command with optional parameters."""
    cmd = ["kubectl", "get", resource]

    if namespace:
        cmd.extend(["-n", namespace])

    if label_selector:
        cmd.extend(["-l", label_selector])

    if output:
        cmd.extend(["-o", output])

    result = subprocess.run(cmd, capture_output=True, text=True)
    return result


def kubectl_port_forward(service, local_port, remote_port, namespace):
    """Start kubectl port-forward in background."""
    cmd = [
        "kubectl",
        "port-forward",
        f"svc/{service}",
        f"{local_port}:{remote_port}",
        "-n",
        namespace,
    ]

    process = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )

    # Give it time to establish connection
    time.sleep(3)
    return process


def wait_for_url(url, timeout=30, interval=2):
    """Wait for URL to become available."""
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            response = requests.get(url, timeout=5)
            if response.status_code == 200:
                return True
        except (requests.RequestException, requests.ConnectionError):
            pass
        time.sleep(interval)
    return False


class TestMonitoringStackDeployment:
    """Test core monitoring components deployment."""

    def test_prometheus_server_deployment(self):
        """Verify Prometheus server is deployed and running."""
        namespace = get_namespace()
        result = kubectl_get(
            "pods",
            namespace=namespace,
            label_selector="app.kubernetes.io/name=prometheus,app.kubernetes.io/component=server",
        )

        if result.returncode != 0:
            pytest.skip("Prometheus server not deployed - monitoring disabled")

        pods = json.loads(result.stdout)
        assert len(pods["items"]) > 0, "No Prometheus server pods found"

        # Check pod is running
        for pod in pods["items"]:
            assert pod["status"]["phase"] == "Running", (
                f"Prometheus pod {pod['metadata']['name']} not running"
            )

            # Check readiness
            conditions = pod["status"].get("conditions", [])
            ready_condition = next(
                (c for c in conditions if c["type"] == "Ready"), None
            )
            assert ready_condition and ready_condition["status"] == "True", (
                "Prometheus pod not ready"
            )

    def test_grafana_deployment(self):
        """Verify Grafana is deployed and running."""
        namespace = get_namespace()
        result = kubectl_get(
            "pods",
            namespace=namespace,
            label_selector="app.kubernetes.io/name=grafana",
        )

        if result.returncode != 0:
            pytest.skip("Grafana not deployed - observability disabled")

        pods = json.loads(result.stdout)
        assert len(pods["items"]) > 0, "No Grafana pods found"

        # Check pod is running
        for pod in pods["items"]:
            assert pod["status"]["phase"] == "Running", (
                f"Grafana pod {pod['metadata']['name']} not running"
            )

    def test_prometheus_adapter_deployment(self):
        """Verify prometheus-adapter is deployed and provides custom metrics API."""
        namespace = get_namespace()
        result = kubectl_get(
            "pods",
            namespace=namespace,
            label_selector="app.kubernetes.io/name=prometheus-adapter",
        )

        if result.returncode != 0:
            pytest.skip("prometheus-adapter not deployed")

        pods = json.loads(result.stdout)
        assert len(pods["items"]) > 0, "No prometheus-adapter pods found"

        # Check pod is running
        for pod in pods["items"]:
            assert pod["status"]["phase"] == "Running", (
                f"prometheus-adapter pod {pod['metadata']['name']} not running"
            )

    def test_kube_state_metrics_deployment(self):
        """Verify kube-state-metrics is collecting Kubernetes object metrics."""
        namespace = get_namespace()
        result = kubectl_get(
            "pods",
            namespace=namespace,
            label_selector="app.kubernetes.io/name=kube-state-metrics",
        )

        if result.returncode != 0:
            pytest.skip("kube-state-metrics not deployed")

        pods = json.loads(result.stdout)
        assert len(pods["items"]) > 0, "No kube-state-metrics pods found"

        # Check pod is running
        for pod in pods["items"]:
            assert pod["status"]["phase"] == "Running", (
                f"kube-state-metrics pod {pod['metadata']['name']} not running"
            )

    def test_node_exporter_deployment(self):
        """Verify node-exporter is collecting node metrics."""
        namespace = get_namespace()
        result = kubectl_get(
            "pods",
            namespace=namespace,
            label_selector="app.kubernetes.io/name=prometheus-node-exporter",
        )

        if result.returncode != 0:
            pytest.skip("prometheus-node-exporter not deployed")

        pods = json.loads(result.stdout)
        assert len(pods["items"]) > 0, "No prometheus-node-exporter pods found"

        # Check pods are running (should be one per node in DaemonSet)
        for pod in pods["items"]:
            assert pod["status"]["phase"] == "Running", (
                f"node-exporter pod {pod['metadata']['name']} not running"
            )


class TestMetricsCollection:
    """Test metrics collection functionality."""

    def test_custom_metrics_api_available(self):
        """Verify custom metrics API is available."""
        result = subprocess.run(
            ["kubectl", "get", "--raw", "/apis/custom.metrics.k8s.io/v1beta1"],
            capture_output=True,
            text=True,
        )

        if result.returncode != 0:
            pytest.skip(
                "Custom metrics API not available - prometheus-adapter may not be configured"
            )

        api_response = json.loads(result.stdout)
        assert api_response["kind"] == "APIResourceList", (
            "Invalid custom metrics API response"
        )
        assert (
            api_response["groupVersion"] == "custom.metrics.k8s.io/v1beta1"
        ), "Wrong API version"

    def test_metrics_server_integration(self):
        """Verify metrics-server is working for resource metrics."""
        # Test if we can get pod metrics
        result = subprocess.run(
            ["kubectl", "top", "pods", "-n", get_namespace(), "--no-headers"],
            capture_output=True,
            text=True,
        )

        if result.returncode != 0:
            pytest.skip("metrics-server not available or not ready")

        # Should have some metrics output
        lines = result.stdout.strip().split("\n")
        assert len(lines) > 0, "No pod metrics available"

        # Check format includes CPU and Memory columns
        for line in lines:
            if line.strip():  # Skip empty lines
                parts = line.split()
                assert len(parts) >= 3, f"Invalid metrics format: {line}"

    def test_prometheus_targets_reachable(self):
        """Test that Prometheus can reach its scrape targets (when accessible)."""
        namespace = get_namespace()

        # Check if Prometheus service exists
        result = kubectl_get(
            "svc",
            namespace=namespace,
            label_selector="app.kubernetes.io/name=prometheus",
        )
        if result.returncode != 0:
            pytest.skip("Prometheus service not found")

        services = json.loads(result.stdout)
        if not services["items"]:
            pytest.skip("No Prometheus services found")

        prometheus_service = None
        for svc in services["items"]:
            if "server" in svc["metadata"]["name"]:
                prometheus_service = svc["metadata"]["name"]
                break

        if not prometheus_service:
            pytest.skip("Prometheus server service not found")

        # Try to port-forward and check targets (with timeout)
        port_forward = None
        try:
            port_forward = kubectl_port_forward(
                prometheus_service, 9090, 80, namespace
            )

            if wait_for_url("http://localhost:9090", timeout=15):
                # Try to get targets endpoint
                try:
                    response = requests.get(
                        "http://localhost:9090/api/v1/targets", timeout=10
                    )
                    if response.status_code == 200:
                        targets_data = response.json()
                        assert targets_data["status"] == "success", (
                            "Prometheus targets API error"
                        )

                        # Check we have some targets
                        targets = targets_data.get("data", {}).get(
                            "activeTargets", []
                        )
                        healthy_targets = [
                            t for t in targets if t.get("health") == "up"
                        ]

                        # Should have at least some healthy targets
                        assert len(healthy_targets) > 0, (
                            "No healthy Prometheus targets found"
                        )
                        print(
                            f"✅ Found {len(healthy_targets)}/{len(targets)} healthy targets"
                        )

                    else:
                        pytest.skip(
                            f"Cannot access Prometheus API: {response.status_code}"
                        )

                except requests.RequestException:
                    pytest.skip(
                        "Cannot connect to Prometheus API via port-forward"
                    )
            else:
                pytest.skip("Cannot establish port-forward to Prometheus")

        finally:
            if port_forward:
                port_forward.terminate()
                port_forward.wait(timeout=5)


class TestAutoscalingIntegration:
    """Test HPA and autoscaling functionality."""

    def test_hpa_resources_exist(self):
        """Verify HPA resources are configured."""
        namespace = get_namespace()
        result = kubectl_get("hpa", namespace=namespace)

        if result.returncode != 0:
            pytest.skip("No HPA resources found - autoscaling not enabled")

        hpas = json.loads(result.stdout)
        assert len(hpas["items"]) > 0, "No HPA resources configured"

        # Check common HPA resources
        hpa_names = [hpa["metadata"]["name"] for hpa in hpas["items"]]
        expected_hpas = [
            "eoapi-stac-hpa",
            "eoapi-raster-hpa",
            "eoapi-vector-hpa",
        ]

        found_hpas = [
            name
            for name in expected_hpas
            if any(name in hpa_name for hpa_name in hpa_names)
        ]
        assert len(found_hpas) > 0, (
            f"No expected HPA resources found. Available: {hpa_names}"
        )

        print(f"✅ Found HPA resources: {found_hpas}")

    def test_hpa_metrics_available(self):
        """Verify HPA can read required metrics."""
        namespace = get_namespace()
        result = kubectl_get("hpa", namespace=namespace)

        if result.returncode != 0:
            pytest.skip("No HPA resources found")

        hpas = json.loads(result.stdout)

        for hpa in hpas["items"]:
            hpa_name = hpa["metadata"]["name"]

            # Check HPA status has current metrics
            status = hpa.get("status", {})
            current_metrics = status.get("currentMetrics", [])

            # Should have at least CPU metrics
            cpu_metrics = [
                m
                for m in current_metrics
                if m.get("type") == "Resource"
                and m.get("resource", {}).get("name") == "cpu"
            ]

            if not cpu_metrics:
                # Check if it's still initializing
                conditions = status.get("conditions", [])
                scaling_active = next(
                    (c for c in conditions if c["type"] == "ScalingActive"),
                    None,
                )

                if scaling_active and scaling_active["status"] == "False":
                    print(
                        f"⚠️  HPA {hpa_name} not yet active: {scaling_active.get('message', 'Unknown')}"
                    )
                else:
                    print(
                        f"✅ HPA {hpa_name} is configured but may still be initializing"
                    )
            else:
                cpu_value = cpu_metrics[0]["resource"]["current"][
                    "averageUtilization"
                ]
                print(f"✅ HPA {hpa_name} CPU metric: {cpu_value}%")

    def test_service_resource_requests_configured(self):
        """Verify services have resource requests (required for HPA CPU metrics)."""
        namespace = get_namespace()
        services = ["stac", "raster", "vector"]

        for service in services:
            result = kubectl_get(
                "pods",
                namespace=namespace,
                label_selector=f"app=eoapi-{service}",
            )

            if result.returncode != 0:
                continue

            pods = json.loads(result.stdout)
            running_pods = [
                p for p in pods["items"] if p["status"]["phase"] == "Running"
            ]

            if not running_pods:
                continue

            # Check first running pod for resource requests
            pod = running_pods[0]
            containers = pod["spec"]["containers"]

            for container in containers:
                if container["name"] == service:  # Main service container
                    resources = container.get("resources", {})
                    requests = resources.get("requests", {})

                    assert "cpu" in requests, (
                        f"Service {service} missing CPU resource requests (required for HPA)"
                    )
                    assert "memory" in requests, (
                        f"Service {service} missing memory resource requests"
                    )

                    print(
                        f"✅ Service {service} has resource requests: CPU={requests['cpu']}, Memory={requests['memory']}"
                    )
                    break


class TestGrafanaDashboards:
    """Test Grafana dashboard functionality (when accessible)."""

    def test_grafana_service_accessibility(self):
        """Test if Grafana service is accessible."""
        namespace = get_namespace()
        result = kubectl_get(
            "svc",
            namespace=namespace,
            label_selector="app.kubernetes.io/name=grafana",
        )

        if result.returncode != 0:
            pytest.skip("Grafana service not found")

        services = json.loads(result.stdout)
        if not services["items"]:
            pytest.skip("No Grafana services found")

        grafana_service = services["items"][0]["metadata"]["name"]

        # Try port-forward to test accessibility
        port_forward = None
        try:
            port_forward = kubectl_port_forward(
                grafana_service, 3000, 80, namespace
            )

            if wait_for_url("http://localhost:3000", timeout=15):
                # Try to access login page
                response = requests.get(
                    "http://localhost:3000/login", timeout=10
                )
                assert response.status_code == 200, (
                    "Cannot access Grafana login page"
                )
                assert "Grafana" in response.text, "Invalid Grafana response"
                print("✅ Grafana service is accessible")
            else:
                pytest.skip("Cannot establish connection to Grafana")

        except requests.RequestException as e:
            pytest.skip(f"Cannot access Grafana: {e}")
        finally:
            if port_forward:
                port_forward.terminate()
                port_forward.wait(timeout=5)

    def test_grafana_admin_secret_exists(self):
        """Verify Grafana admin password secret exists."""
        namespace = get_namespace()
        release_name = get_release_name()

        result = kubectl_get("secret", namespace=namespace, output="json")
        if result.returncode != 0:
            pytest.skip("Cannot list secrets")

        secrets = json.loads(result.stdout)
        grafana_secrets = [
            s
            for s in secrets["items"]
            if "grafana" in s["metadata"]["name"].lower()
        ]

        if not grafana_secrets:
            pytest.skip("No Grafana secrets found")

        # Check for admin password key
        found_password = False
        for secret in grafana_secrets:
            if "admin-password" in secret.get("data", {}):
                found_password = True
                print(
                    f"✅ Found Grafana admin password in secret: {secret['metadata']['name']}"
                )
                break

        assert found_password, "Grafana admin password secret not found"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
