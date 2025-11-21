"""Test observability stack deployment and functionality."""

import json
import subprocess

import pytest
import requests
from conftest import (
    get_namespace,
    get_release_name,
    kubectl_get,
    kubectl_proxy,
    wait_for_url,
)


class TestMonitoringStackDeployment:
    def test_prometheus_server_deployment(self) -> None:
        namespace = get_namespace()
        result = kubectl_get(
            "deployment",
            namespace=namespace,
            label_selector="app.kubernetes.io/name=prometheus,app.kubernetes.io/component=server",
        )

        assert result.returncode == 0, "Failed to get Prometheus deployment"

        deployments = json.loads(result.stdout)
        assert deployments["items"], "No Prometheus server deployment found"

        deployment = deployments["items"][0]

        ready_replicas = deployment["status"].get("readyReplicas", 0)
        desired_replicas = deployment["spec"]["replicas"]
        assert ready_replicas == desired_replicas, (
            f"Prometheus not ready: {ready_replicas}/{desired_replicas} replicas"
        )

    def test_grafana_deployment(self) -> None:
        namespace = get_namespace()
        result = kubectl_get(
            "deployment",
            namespace=namespace,
            label_selector="app.kubernetes.io/name=grafana",
        )

        assert result.returncode == 0, "Failed to get Grafana deployment"

        deployments = json.loads(result.stdout)
        assert deployments["items"], "No Grafana deployment found"

        deployment = deployments["items"][0]
        ready_replicas = deployment["status"].get("readyReplicas", 0)
        desired_replicas = deployment["spec"]["replicas"]
        assert ready_replicas == desired_replicas, (
            f"Grafana not ready: {ready_replicas}/{desired_replicas} replicas"
        )

    def test_prometheus_adapter_deployment(self) -> None:
        namespace = get_namespace()
        result = kubectl_get(
            "deployment",
            namespace=namespace,
            label_selector="app.kubernetes.io/name=prometheus-adapter",
        )

        assert result.returncode == 0, (
            "Failed to get Prometheus Adapter deployment"
        )

        deployments = json.loads(result.stdout)
        assert deployments["items"], "No Prometheus Adapter deployment found"

        deployment = deployments["items"][0]
        ready_replicas = deployment["status"].get("readyReplicas", 0)
        desired_replicas = deployment["spec"]["replicas"]
        assert ready_replicas == desired_replicas, (
            f"Prometheus Adapter not ready: {ready_replicas}/{desired_replicas} replicas"
        )

    def test_kube_state_metrics_deployment(self) -> None:
        """Test kube-state-metrics deployment is running."""
        namespace = get_namespace()
        result = kubectl_get(
            "deployment",
            namespace=namespace,
            label_selector="app.kubernetes.io/name=kube-state-metrics",
        )

        assert result.returncode == 0, (
            "Failed to get kube-state-metrics deployment"
        )

        deployments = json.loads(result.stdout)
        assert deployments["items"], "No kube-state-metrics deployment found"

        deployment = deployments["items"][0]
        ready_replicas = deployment["status"].get("readyReplicas", 0)
        desired_replicas = deployment["spec"]["replicas"]
        assert ready_replicas == desired_replicas, (
            f"kube-state-metrics not ready: {ready_replicas}/{desired_replicas} replicas"
        )

    def test_node_exporter_deployment(self) -> None:
        """Test node-exporter DaemonSet is running."""
        namespace = get_namespace()
        result = kubectl_get(
            "daemonset",
            namespace=namespace,
            label_selector="app.kubernetes.io/name=prometheus-node-exporter",
        )

        assert result.returncode == 0, "Failed to get node-exporter daemonset"

        daemonsets = json.loads(result.stdout)
        assert daemonsets["items"], "No node-exporter daemonset found"

        daemonset = daemonsets["items"][0]
        ready = daemonset["status"].get("numberReady", 0)
        desired = daemonset["status"].get("desiredNumberScheduled", 0)
        assert ready > 0, "No node-exporter pods are ready"
        assert ready == desired, (
            f"node-exporter not fully deployed: {ready}/{desired} nodes"
        )


class TestMetricsCollection:
    def test_custom_metrics_api_available(self) -> None:
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

    def test_metrics_server_integration(self) -> None:
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

    def test_prometheus_targets_reachable(self) -> None:
        """Test that Prometheus can reach its scrape targets (when accessible)."""
        namespace = get_namespace()

        # Check if Prometheus service exists
        result = kubectl_get(
            "svc",
            namespace=namespace,
            label_selector="app.kubernetes.io/name=prometheus,app.kubernetes.io/component=server",
        )

        if result.returncode != 0 or not json.loads(result.stdout)["items"]:
            pytest.skip("Prometheus service not found")

        service = json.loads(result.stdout)["items"][0]
        service_name = service["metadata"]["name"]

        # Try kubectl proxy instead of port-forward
        proxy_port = 8001

        process = None
        try:
            process = kubectl_proxy(proxy_port)

            # Build proxy URL for Prometheus service
            proxy_url = f"http://localhost:{proxy_port}/api/v1/namespaces/{namespace}/services/{service_name}:80/proxy"

            # Wait for proxy to establish
            if not wait_for_url(f"{proxy_url}/api/v1/targets"):
                pytest.skip(
                    "Could not establish connection to Prometheus via proxy"
                )

            # Check Prometheus targets
            response = requests.get(f"{proxy_url}/api/v1/targets")
            assert response.status_code == 200, (
                "Failed to get Prometheus targets"
            )

            targets_data = response.json()
            assert targets_data["status"] == "success", (
                "Failed to retrieve targets"
            )

            active_targets = targets_data["data"]["activeTargets"]

            # Should have at least some targets
            assert len(active_targets) > 0, "No active Prometheus targets found"

            # Check for expected target labels
            expected_jobs = {
                "kubernetes-pods",
                "kubernetes-nodes",
                "kubernetes-service-endpoints",
                "kubernetes-apiservers",
            }

            found_jobs = {
                target["labels"].get("job") for target in active_targets
            }

            # At least some of the expected jobs should be present
            common_jobs = expected_jobs.intersection(found_jobs)
            assert len(common_jobs) > 0, (
                f"None of the expected jobs found. Expected: {expected_jobs}, "
                f"Found: {found_jobs}"
            )

            # Check health of targets
            unhealthy_targets = [
                target for target in active_targets if target["health"] != "up"
            ]

            # Warning about unhealthy targets but don't fail the test
            if unhealthy_targets:
                print(
                    f"Warning: {len(unhealthy_targets)} unhealthy targets found"
                )

        finally:
            if process:
                process.terminate()
                process.wait()


class TestAutoscalingIntegration:
    """Test HPA and metrics integration for autoscaling."""

    def test_hpa_resources_exist(self) -> None:
        """Verify HPA resources are created for eoAPI services."""
        namespace = get_namespace()
        release = get_release_name()
        result = kubectl_get("hpa", namespace=namespace)

        assert result.returncode == 0, "Failed to get HPA resources"

        hpas = json.loads(result.stdout)["items"]

        # Expected HPA names based on the Helm chart
        expected_hpas = [
            f"{release}-multidim-hpa",
            f"{release}-raster-hpa",
            f"{release}-stac-hpa",
            f"{release}-vector-hpa",
        ]

        found_hpas = {hpa["metadata"]["name"] for hpa in hpas}

        # Check which expected HPAs exist
        existing_hpas = [hpa for hpa in expected_hpas if hpa in found_hpas]

        if not existing_hpas:
            pytest.skip(
                "No eoAPI HPA resources found - autoscaling may be disabled"
            )

        # For each found HPA, check configuration
        for hpa_name in existing_hpas:
            hpa = next(h for h in hpas if h["metadata"]["name"] == hpa_name)
            spec = hpa["spec"]

            assert spec["minReplicas"] >= 1, (
                f"HPA {hpa_name} min replicas too low"
            )
            assert spec["maxReplicas"] > spec["minReplicas"], (
                f"HPA {hpa_name} max replicas not greater than min"
            )

    def test_hpa_metrics_available(self) -> None:
        """Test that HPA can access metrics for scaling decisions."""
        namespace = get_namespace()
        result = kubectl_get("hpa", namespace=namespace)

        if result.returncode != 0:
            pytest.skip("HPA resources not accessible")

        hpas = json.loads(result.stdout)["items"]

        if not hpas:
            pytest.skip("No HPA resources found")

        # Check each HPA for metric availability
        for hpa in hpas:
            name = hpa["metadata"]["name"]
            status = hpa.get("status", {})

            # Check if HPA has current metrics (may be None initially)
            current_metrics = status.get("currentMetrics")

            # Conditions tell us if metrics are available
            conditions = status.get("conditions", [])

            # Look for ScalingActive condition
            scaling_active = next(
                (c for c in conditions if c["type"] == "ScalingActive"), None
            )

            if scaling_active:
                assert scaling_active["status"] == "True", (
                    f"HPA {name} scaling is not active: {scaling_active.get('message', 'Unknown reason')}"
                )

            # If we have been running for a while, we should have metrics
            # But on fresh deployments, metrics might not be available yet
            if current_metrics is not None:
                assert len(current_metrics) > 0, (
                    f"HPA {name} has no current metrics"
                )

    def test_service_resource_requests_configured(self) -> None:
        """Verify pods have resource requests for HPA to function."""
        namespace = get_namespace()
        release = get_release_name()
        result = kubectl_get(
            "deployment",
            namespace=namespace,
            label_selector=f"app.kubernetes.io/instance={release}",
        )

        if result.returncode != 0:
            pytest.skip("Could not get eoAPI deployments")

        deployments = json.loads(result.stdout)["items"]

        if not deployments:
            pytest.skip("No eoAPI deployments found")

        for deployment in deployments:
            name = deployment["metadata"]["name"]
            containers = deployment["spec"]["template"]["spec"]["containers"]

            for container in containers:
                container_name = container["name"]
                resources = container.get("resources", {})
                requests = resources.get("requests", {})

                # At minimum, CPU requests should be set for HPA
                # Memory is optional but recommended
                if "cpu" not in requests:
                    print(
                        f"Warning: Container {container_name} in {name} "
                        f"has no CPU request - HPA may not function properly"
                    )

                # If HPA is configured, we need resource requests
                # This is more of a warning than a failure
                if not requests:
                    print(
                        f"Warning: Container {container_name} in {name} "
                        f"has no resource requests defined"
                    )


class TestGrafanaDashboards:
    def test_grafana_service_accessibility(self) -> None:
        namespace = get_namespace()
        result = kubectl_get(
            "svc",
            namespace=namespace,
            label_selector="app.kubernetes.io/name=grafana",
        )

        if result.returncode != 0:
            pytest.skip("Grafana service not found")

        services = json.loads(result.stdout)["items"]
        if not services:
            pytest.skip("No Grafana service found")

        service = services[0]
        service_name = service["metadata"]["name"]

        # Use kubectl proxy to access Grafana
        proxy_port = 8002

        process = None
        try:
            process = kubectl_proxy(proxy_port)

            # Build proxy URL for Grafana service
            proxy_url = f"http://localhost:{proxy_port}/api/v1/namespaces/{namespace}/services/{service_name}:80/proxy"

            if not wait_for_url(f"{proxy_url}/api/health"):
                pytest.skip("Could not connect to Grafana via proxy")

            response = requests.get(f"{proxy_url}/api/health")
            assert response.status_code == 200, "Grafana health check failed"

            health_data = response.json()
            assert health_data.get("database") == "ok", (
                "Grafana database not healthy"
            )

        finally:
            if process:
                process.terminate()
                process.wait()

    def test_grafana_admin_secret_exists(self) -> None:
        namespace = get_namespace()
        result = kubectl_get(
            "secret",
            namespace=namespace,
            label_selector="app.kubernetes.io/name=grafana",
        )

        assert result.returncode == 0, "Failed to get Grafana secrets"

        secrets = json.loads(result.stdout)["items"]
        assert secrets, "No Grafana secrets found"

        admin_secret = None
        for secret in secrets:
            name = secret["metadata"]["name"]
            if "grafana" in name:
                data = secret.get("data", {})
                # Check if it contains admin credentials
                if "admin-password" in data or "admin-user" in data:
                    admin_secret = secret
                    break

        assert admin_secret is not None, (
            "Grafana admin credentials secret not found"
        )

        secret_data = admin_secret.get("data", {})
        assert "admin-password" in secret_data, (
            "admin-password not found in Grafana secret"
        )
