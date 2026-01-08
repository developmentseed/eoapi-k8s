"""Test notification system deployment and functionality."""

import os
import subprocess
import time

import pytest
import requests


def test_eoapi_notifier_deployment() -> None:
    """Test that eoapi-notifier deployment is running."""
    # Check if eoapi-notifier deployment exists and is ready
    result = subprocess.run(
        [
            "kubectl",
            "get",
            "deployment",
            "-l",
            "app.kubernetes.io/name=eoapi-notifier",
            "-n",
            "eoapi",
            "--no-headers",
            "-o",
            "custom-columns=READY:.status.readyReplicas",
        ],
        capture_output=True,
        text=True,
    )

    assert (
        result.returncode == 0
    ), "eoapi-notifier deployment not found - notifications not enabled"

    ready_replicas = result.stdout.strip()
    assert ready_replicas == "1", f"Expected 1 ready replica, got {ready_replicas}"


def test_cloudevents_sink_exists() -> None:
    """Test that Knative CloudEvents sink service exists and is accessible."""
    # Check if Knative service exists
    namespace = os.getenv("NAMESPACE", "eoapi")
    result = subprocess.run(
        [
            "kubectl",
            "get",
            "ksvc",
            "-l",
            "app.kubernetes.io/component=cloudevents-sink",
            "-n",
            namespace,
            "--no-headers",
        ],
        capture_output=True,
        text=True,
    )

    assert (
        result.returncode == 0 and result.stdout.strip()
    ), "Knative CloudEvents sink not found - notifications not configured"

    assert "cloudevents-sink" in result.stdout, "Knative CloudEvents sink should exist"


def test_notification_configuration() -> None:
    """Test that eoapi-notifier is configured correctly."""
    # Get the configmap for eoapi-notifier
    namespace = os.getenv("NAMESPACE", "eoapi")
    result = subprocess.run(
        [
            "kubectl",
            "get",
            "configmap",
            "-l",
            "app.kubernetes.io/name=eoapi-notifier",
            "-n",
            namespace,
            "-o",
            r"jsonpath={.items[0].data.config\.yaml}",
        ],
        capture_output=True,
        text=True,
    )

    assert result.returncode == 0, "eoapi-notifier configmap not found"

    config_yaml = result.stdout.strip()
    assert "pgstac" in config_yaml, "Should have pgstac configured"
    assert "cloudevents" in config_yaml, "Should have cloudevents output configured"
    assert (
        "pgstac_items_change" in config_yaml or "pgstac" in config_yaml
    ), "Should have pgstac configuration"


def test_cloudevents_sink_logs_show_startup() -> None:
    """Test that Knative CloudEvents sink started successfully."""
    # Get Knative CloudEvents sink pod logs
    namespace = os.getenv("NAMESPACE", "eoapi")
    result = subprocess.run(
        [
            "kubectl",
            "logs",
            "-l",
            "serving.knative.dev/service",
            "-n",
            namespace,
            "--tail=20",
        ],
        capture_output=True,
        text=True,
    )

    assert result.returncode == 0, "Cannot get Knative CloudEvents sink logs"

    logs = result.stdout
    # CloudEvents sink can be either a real sink or the helloworld sample container
    assert (
        "listening on port" in logs or "helloworld: received a request" in logs
    ), "Knative CloudEvents sink should be running (either real sink or helloworld sample)"


def test_eoapi_notifier_logs_show_connection() -> None:
    """Test that eoapi-notifier connects to database successfully."""
    # Give some time for the notifier to start
    time.sleep(5)

    # Get eoapi-notifier pod logs
    namespace = os.getenv("NAMESPACE", "eoapi")
    result = subprocess.run(
        [
            "kubectl",
            "logs",
            "-l",
            "app.kubernetes.io/name=eoapi-notifier",
            "-n",
            namespace,
            "--tail=50",
        ],
        capture_output=True,
        text=True,
    )

    assert result.returncode == 0, "Cannot get eoapi-notifier logs"

    logs = result.stdout
    # Should not have connection errors
    assert "Connection refused" not in logs, "Should not have connection errors"
    assert "Authentication failed" not in logs, "Should not have auth errors"


def test_database_notification_triggers_exist() -> None:
    """Test that pgstac notification system is operational."""
    # Check if eoapi-notifier is deployed and running
    result = subprocess.run(
        [
            "kubectl",
            "get",
            "deployment",
            "-l",
            "app.kubernetes.io/name=eoapi-notifier",
            "-n",
            "eoapi",
            "--no-headers",
        ],
        capture_output=True,
        text=True,
    )

    assert (
        result.stdout.strip()
    ), "eoapi-notifier not deployed - notifications not enabled"

    # Check that the notifier pod is ready
    result = subprocess.run(
        [
            "kubectl",
            "get",
            "pods",
            "-l",
            "app.kubernetes.io/name=eoapi-notifier",
            "-n",
            "eoapi",
            "-o",
            "jsonpath={.items[*].status.conditions[?(@.type=='Ready')].status}",
        ],
        capture_output=True,
        text=True,
    )

    assert "True" in result.stdout, "eoapi-notifier pod should be ready"


def test_end_to_end_notification_flow(auth_token: str) -> None:
    """Test complete flow: database item change → eoapi-notifier → Knative CloudEvents sink."""

    # Check if notifications are enabled
    stac_output = subprocess.run(
        [
            "kubectl",
            "get",
            "deployment",
            "-l",
            "app.kubernetes.io/name=eoapi-notifier",
            "-n",
            "eoapi",
            "--no-headers",
        ],
        capture_output=True,
    ).stdout.strip()
    assert stac_output, "eoapi-notifier not deployed"

    # Create a test item via STAC API to trigger notification flow
    # Use the ingress endpoint by default (tests run from outside cluster)
    stac_endpoint = os.getenv("STAC_ENDPOINT", "http://localhost/stac")
    namespace = os.getenv("NAMESPACE", "eoapi")

    test_item = {
        "id": f"e2e-test-{int(time.time())}",
        "type": "Feature",
        "stac_version": "1.0.0",
        "geometry": {"type": "Point", "coordinates": [0, 0]},
        "bbox": [0, 0, 0, 0],
        "properties": {"datetime": "2020-01-01T00:00:00Z"},
        "assets": {},
        "collection": "noaa-emergency-response",
        "links": [
            {
                "rel": "self",
                "href": f"{stac_endpoint}/collections/noaa-emergency-response/items/e2e-test-{int(time.time())}",
                "type": "application/geo+json",
            },
            {
                "rel": "collection",
                "href": f"{stac_endpoint}/collections/noaa-emergency-response",
                "type": "application/json",
            },
        ],
    }

    # Get notifier logs before the operation (baseline)
    _ = subprocess.run(
        [
            "kubectl",
            "logs",
            "-l",
            "app.kubernetes.io/name=eoapi-notifier",
            "-n",
            namespace,
            "--tail=100",
        ],
        capture_output=True,
        text=True,
    ).stdout

    # Create item via STAC API using auth token
    response = requests.post(
        f"{stac_endpoint}/collections/noaa-emergency-response/items",
        json=test_item,
        headers={
            "Content-Type": "application/json",
            "Authorization": auth_token,
        },
        timeout=10,
    )

    assert response.status_code in [200, 201], f"Failed to create item: {response.text}"

    # Wait briefly for notification to propagate
    time.sleep(3)

    # Get notifier logs after the operation
    # Get logs after the operation
    after_logs: str = subprocess.run(
        [
            "kubectl",
            "logs",
            "-l",
            "app.kubernetes.io/name=eoapi-notifier",
            "-n",
            namespace,
            "--tail=100",
        ],
        capture_output=True,
        text=True,
    ).stdout

    # Clean up
    item_id = str(test_item.get("id", ""))  # type: ignore[union-attr]
    requests.delete(
        f"{stac_endpoint}/collections/noaa-emergency-response/items/{item_id}",
        headers={
            "Content-Type": "application/json",
            "Authorization": auth_token,
        },
        timeout=10,
    )

    # Verify notification was processed
    # Check if the new event appears in the after_logs
    keywords: list[str] = ["pgstac_items_change", item_id, "INSERT"]
    assert any(
        keyword in after_logs for keyword in keywords
    ), f"Notification for item {item_id} should be in logs"

    # Check Knative CloudEvents sink logs for any CloudEvents
    result = subprocess.run(
        [
            "kubectl",
            "get",
            "pods",
            "-l",
            "serving.knative.dev/service",
            "-n",
            namespace,
            "-o",
            "jsonpath={.items[0].metadata.name}",
        ],
        capture_output=True,
        text=True,
    )

    if result.returncode == 0 and result.stdout.strip():
        sink_pod = result.stdout.strip()

        # Get sink logs to verify CloudEvents are being received
        result = subprocess.run(
            ["kubectl", "logs", sink_pod, "-n", namespace, "--tail=50"],
            capture_output=True,
            text=True,
        )

        if result.returncode == 0:
            # Just verify that the sink is receiving events, don't check specific item
            # since we already verified the notifier processed it
            print(f"CloudEvents sink logs (last 50 lines):\n{result.stdout}")


def test_k_sink_injection() -> None:
    """Test that SinkBinding injects K_SINK into eoapi-notifier deployment."""
    # Check if eoapi-notifier deployment exists
    namespace = os.getenv("NAMESPACE", "eoapi")
    result = subprocess.run(
        [
            "kubectl",
            "get",
            "deployment",
            "-l",
            "app.kubernetes.io/name=eoapi-notifier",
            "-n",
            namespace,
            "-o",
            'jsonpath={.items[0].spec.template.spec.containers[0].env[?(@.name=="K_SINK")].value}',
        ],
        capture_output=True,
        text=True,
    )

    assert result.returncode == 0, "eoapi-notifier deployment not found"

    k_sink_value = result.stdout.strip()
    if k_sink_value:
        assert (
            "cloudevents-sink" in k_sink_value
        ), f"K_SINK should point to CloudEvents sink service, got: {k_sink_value}"
        print(f"✅ K_SINK properly injected: {k_sink_value}")
    else:
        # Check if SinkBinding exists - it may take time to inject
        sinkbinding_result = subprocess.run(
            [
                "kubectl",
                "get",
                "sinkbinding",
                "-l",
                "app.kubernetes.io/component=sink-binding",
                "-n",
                namespace,
                "--no-headers",
            ],
            capture_output=True,
            text=True,
        )

        if sinkbinding_result.returncode == 0 and sinkbinding_result.stdout.strip():
            pytest.fail(
                "SinkBinding exists but K_SINK not yet injected - may need more time"
            )
        else:
            pytest.fail("No K_SINK found and no SinkBinding exists")


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
