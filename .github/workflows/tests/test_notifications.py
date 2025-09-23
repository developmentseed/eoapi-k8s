"""Test notification system deployment and functionality."""
import json
import os
import psycopg2
import psycopg2.extensions
import requests
import subprocess
import time
import pytest
from datetime import datetime




def test_eoapi_notifier_deployment():
    """Test that eoapi-notifier deployment is running."""
    # Check if eoapi-notifier deployment exists and is ready
    result = subprocess.run([
        'kubectl', 'get', 'deployment',
        '-l', 'app.kubernetes.io/name=eoapi-notifier',
        '-n', 'eoapi',
        '--no-headers', '-o', 'custom-columns=READY:.status.readyReplicas'
    ], capture_output=True, text=True)

    if result.returncode != 0:
        pytest.skip("eoapi-notifier deployment not found - notifications not enabled")

    ready_replicas = result.stdout.strip()
    assert ready_replicas == "1", f"Expected 1 ready replica, got {ready_replicas}"


def test_cloudevents_sink_exists():
    """Test that Knative CloudEvents sink service exists and is accessible."""
    # Check if Knative service exists
    result = subprocess.run([
        'kubectl', 'get', 'ksvc',
        '-l', 'app.kubernetes.io/component=cloudevents-sink',
        '--no-headers'
    ], capture_output=True, text=True)

    if result.returncode != 0 or not result.stdout.strip():
        pytest.skip("Knative CloudEvents sink not found - notifications not configured")

    assert "cloudevents-sink" in result.stdout, "Knative CloudEvents sink should exist"


def test_notification_configuration():
    """Test that eoapi-notifier is configured correctly."""
    # Get the configmap for eoapi-notifier
    result = subprocess.run([
        'kubectl', 'get', 'configmap',
        '-l', 'app.kubernetes.io/name=eoapi-notifier',
        '-o', r'jsonpath={.items[0].data.config\.yaml}'
    ], capture_output=True, text=True)

    if result.returncode != 0:
        pytest.skip("eoapi-notifier configmap not found")

    config_yaml = result.stdout.strip()
    assert "postgres" in config_yaml, "Should have postgres source configured"
    assert "cloudevents" in config_yaml, "Should have cloudevents output configured"
    assert "pgstac_items_change" in config_yaml, "Should listen to pgstac_items_change channel"


def test_cloudevents_sink_logs_show_startup():
    """Test that Knative CloudEvents sink started successfully."""
    # Get Knative CloudEvents sink pod logs
    result = subprocess.run([
        'kubectl', 'logs',
        '-l', 'serving.knative.dev/service',
        '-n', 'eoapi',
        '--tail=20'
    ], capture_output=True, text=True)

    if result.returncode != 0:
        pytest.skip("Cannot get Knative CloudEvents sink logs")

    logs = result.stdout
    assert "listening on port" in logs, "Knative CloudEvents sink should have started successfully"


def test_eoapi_notifier_logs_show_connection():
    """Test that eoapi-notifier connects to database successfully."""
    # Give some time for the notifier to start
    time.sleep(5)

    # Get eoapi-notifier pod logs
    result = subprocess.run([
        'kubectl', 'logs',
        '-l', 'app.kubernetes.io/name=eoapi-notifier',
        '--tail=50'
    ], capture_output=True, text=True)

    if result.returncode != 0:
        pytest.skip("Cannot get eoapi-notifier logs")

    logs = result.stdout
    # Should not have connection errors
    assert "Connection refused" not in logs, "Should not have connection errors"
    assert "Authentication failed" not in logs, "Should not have auth errors"


def test_database_notification_triggers_exist(db_connection):
    """Test that pgstac notification triggers are installed."""
    with db_connection.cursor() as cur:
            # Check if the notification function exists
            cur.execute("""
                SELECT EXISTS(
                    SELECT 1 FROM pg_proc p
                    JOIN pg_namespace n ON p.pronamespace = n.oid
                    WHERE n.nspname = 'public'
                    AND p.proname = 'notify_items_change_func'
                );
            """)
            result = cur.fetchone()
            function_exists = result[0] if result else False
            assert function_exists, "notify_items_change_func should exist"

            # Check if triggers exist
            cur.execute("""
                SELECT COUNT(*) FROM information_schema.triggers
                WHERE trigger_name LIKE 'notify_items_change_%'
                AND event_object_table = 'items'
                AND event_object_schema = 'pgstac';
            """)
            result = cur.fetchone()
            trigger_count = result[0] if result else 0
            assert trigger_count >= 3, f"Should have at least 3 triggers (INSERT, UPDATE, DELETE), found {trigger_count}"




def test_end_to_end_notification_flow(db_connection):
    """Test complete flow: database → eoapi-notifier → Knative CloudEvents sink."""

    # Skip if notifications not enabled
    if not subprocess.run(['kubectl', 'get', 'deployment', '-l', 'app.kubernetes.io/name=eoapi-notifier', '--no-headers'], capture_output=True).stdout.strip():
        pytest.skip("eoapi-notifier not deployed")

    # Find Knative CloudEvents sink pod
    result = subprocess.run(['kubectl', 'get', 'pods', '-l', 'serving.knative.dev/service', '-o', 'jsonpath={.items[0].metadata.name}'], capture_output=True, text=True)

    if result.returncode != 0 or not result.stdout.strip():
        pytest.skip("Knative CloudEvents sink pod not found")

    sink_pod = result.stdout.strip()

    # Insert test item and check for CloudEvent
    test_item_id = f"e2e-test-{int(time.time())}"
    try:
        with db_connection.cursor() as cursor:
            cursor.execute("SELECT pgstac.create_item(%s);", (json.dumps({
                "id": test_item_id,
                "type": "Feature",
                "stac_version": "1.0.0",
                "collection": "noaa-emergency-response",
                "geometry": {"type": "Point", "coordinates": [0, 0]},
                "bbox": [0, 0, 0, 0],
                "properties": {"datetime": "2020-01-01T00:00:00Z"},
                "assets": {}
            }),))

        # Check CloudEvents sink logs for CloudEvent
        found_event = False
        for _ in range(20):  # 20 second timeout
            time.sleep(1)
            result = subprocess.run(['kubectl', 'logs', sink_pod, '--since=30s'], capture_output=True, text=True)
            if result.returncode == 0 and "CloudEvent received" in result.stdout and test_item_id in result.stdout:
                found_event = True
                break

        assert found_event, f"CloudEvent for {test_item_id} not received by CloudEvents sink"

    finally:
        # Cleanup
        with db_connection.cursor() as cursor:
            cursor.execute("SELECT pgstac.delete_item(%s);", (test_item_id,))


def test_k_sink_injection():
    """Test that SinkBinding injects K_SINK into eoapi-notifier deployment."""
    # Check if eoapi-notifier deployment exists
    result = subprocess.run([
        'kubectl', 'get', 'deployment',
        '-l', 'app.kubernetes.io/name=eoapi-notifier',
        '-o', 'jsonpath={.items[0].spec.template.spec.containers[0].env[?(@.name=="K_SINK")].value}'
    ], capture_output=True, text=True)

    if result.returncode != 0:
        pytest.skip("eoapi-notifier deployment not found")

    k_sink_value = result.stdout.strip()
    if k_sink_value:
        assert "cloudevents-sink" in k_sink_value, f"K_SINK should point to CloudEvents sink service, got: {k_sink_value}"
        print(f"✅ K_SINK properly injected: {k_sink_value}")
    else:
        # Check if SinkBinding exists - it may take time to inject
        sinkbinding_result = subprocess.run([
            'kubectl', 'get', 'sinkbinding',
            '-l', 'app.kubernetes.io/component=sink-binding',
            '--no-headers'
        ], capture_output=True, text=True)

        if sinkbinding_result.returncode == 0 and sinkbinding_result.stdout.strip():
            pytest.skip("SinkBinding exists but K_SINK not yet injected - may need more time")
        else:
            pytest.fail("No K_SINK found and no SinkBinding exists")


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
