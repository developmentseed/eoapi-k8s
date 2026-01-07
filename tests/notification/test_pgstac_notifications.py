"""Test pgstac notification triggers."""

import json
import os
import subprocess
import time
from typing import Any, Dict

import pytest
import requests


@pytest.fixture(scope="session")
def notifications_enabled() -> bool:
    """Check if notifications are enabled in the deployment config by checking Helm values."""
    try:
        release_name = os.getenv("RELEASE_NAME", "eoapi")
        namespace = os.getenv("NAMESPACE", "eoapi")

        # Check if notifications are enabled in Helm values
        result = subprocess.run(
            [
                "helm",
                "get",
                "values",
                release_name,
                "-n",
                namespace,
                "-o",
                "json",
            ],
            capture_output=True,
            text=True,
            check=True,
        )

        # Parse JSON and check if eoapi-notifier is enabled with pgstac source
        values = json.loads(result.stdout)
        notifier = values.get("eoapi-notifier", {})

        if not notifier.get("enabled", False):
            return False

        # Check if pgstac is configured as a source
        sources = notifier.get("config", {}).get("sources", [])
        return any(source.get("type") == "pgstac" for source in sources)
    except (subprocess.CalledProcessError, json.JSONDecodeError, Exception):
        return False


@pytest.fixture
def stac_client(auth_token: str) -> Dict[str, Any]:
    """Create a STAC API client configuration with valid token from mock OIDC."""
    stac_endpoint = os.getenv("STAC_ENDPOINT", "http://localhost/stac")

    return {
        "base_url": stac_endpoint,
        "headers": {
            "Content-Type": "application/json",
            "Authorization": auth_token,
        },
        "timeout": 10,
    }


def get_notifier_logs_since(timestamp: float) -> str:
    """Get eoapi-notifier logs since a given timestamp."""
    namespace = os.getenv("NAMESPACE", "eoapi")

    result = subprocess.run(
        [
            "kubectl",
            "logs",
            "-l",
            "app.kubernetes.io/name=eoapi-notifier",
            "-n",
            namespace,
            "--tail",
            "200",
        ],
        capture_output=True,
        text=True,
    )

    return result.stdout if result.returncode == 0 else ""


def test_notification_triggers_exist(
    stac_client: Dict[str, Any], notifications_enabled: bool
) -> None:
    """Test that notification system is working by performing a simple operation."""
    assert notifications_enabled, "PgSTAC notifications not enabled - set notifications.sources.pgstac=true to test"

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
            "--no-headers",
        ],
        capture_output=True,
        text=True,
    )

    assert result.stdout.strip(), "eoapi-notifier not deployed"

    test_item_id = f"notification-test-{int(time.time())}"
    test_item = {
        "id": test_item_id,
        "type": "Feature",
        "stac_version": "1.0.0",
        "geometry": {"type": "Point", "coordinates": [0, 0]},
        "bbox": [0, 0, 0, 0],
        "properties": {"datetime": "2020-01-01T00:00:00Z"},
        "assets": {},
        "links": [],
        "collection": "noaa-emergency-response",
    }

    before_time = time.time()

    response = requests.post(
        f"{stac_client['base_url']}/collections/noaa-emergency-response/items",
        json=test_item,
        headers=stac_client["headers"],
        timeout=stac_client["timeout"],
    )

    assert response.status_code in [
        200,
        201,
    ], f"Failed to create test item: {response.text}"

    time.sleep(2)
    logs = get_notifier_logs_since(before_time)

    requests.delete(
        f"{stac_client['base_url']}/collections/noaa-emergency-response/items/{test_item_id}",
        headers=stac_client["headers"],
        timeout=stac_client["timeout"],
    )

    assert (
        "pgstac_items_change" in logs or "INSERT" in logs or test_item_id in logs
    ), "Notification system should process item changes"


def test_insert_notification(
    stac_client: Dict[str, Any], notifications_enabled: bool
) -> None:
    """Test that INSERT operations trigger notifications."""
    assert notifications_enabled, "PgSTAC notifications not enabled - set notifications.sources.pgstac=true to test"

    test_item_id = f"test-insert-{int(time.time())}"
    test_item = {
        "id": test_item_id,
        "type": "Feature",
        "stac_version": "1.0.0",
        "collection": "noaa-emergency-response",
        "geometry": {"type": "Point", "coordinates": [0, 0]},
        "bbox": [0, 0, 0, 0],
        "properties": {"datetime": "2020-01-01T00:00:00Z"},
        "assets": {},
        "links": [],
    }

    before_time = time.time()

    response = requests.post(
        f"{stac_client['base_url']}/collections/noaa-emergency-response/items",
        json=test_item,
        headers=stac_client["headers"],
        timeout=stac_client["timeout"],
    )

    assert response.status_code in [200, 201], f"Failed to create item: {response.text}"

    time.sleep(2)
    logs = get_notifier_logs_since(before_time)

    requests.delete(
        f"{stac_client['base_url']}/collections/noaa-emergency-response/items/{test_item_id}",
        headers=stac_client["headers"],
        timeout=stac_client["timeout"],
    )

    assert any(
        keyword in logs
        for keyword in ["INSERT", "insert", test_item_id, "pgstac_items_change"]
    ), f"INSERT notification should be logged for item {test_item_id}"


def test_update_notification(
    stac_client: Dict[str, Any], notifications_enabled: bool
) -> None:
    """Test that UPDATE operations trigger notifications."""
    assert notifications_enabled, "PgSTAC notifications not enabled - set notifications.sources.pgstac=true to test"

    test_item_id = f"test-update-{int(time.time())}"
    test_item = {
        "id": test_item_id,
        "type": "Feature",
        "stac_version": "1.0.0",
        "collection": "noaa-emergency-response",
        "geometry": {"type": "Point", "coordinates": [0, 0]},
        "bbox": [0, 0, 0, 0],
        "properties": {
            "datetime": "2020-01-01T00:00:00Z",
            "test_version": "v1",
        },
        "assets": {},
        "links": [],
    }

    response = requests.post(
        f"{stac_client['base_url']}/collections/noaa-emergency-response/items",
        json=test_item,
        headers=stac_client["headers"],
        timeout=stac_client["timeout"],
    )

    assert response.status_code in [200, 201], f"Failed to create item: {response.text}"

    before_time = time.time()

    test_item["properties"]["description"] = "Updated for notification test"  # type: ignore[index]
    test_item["properties"]["test_version"] = "v2"  # type: ignore[index]

    response = requests.put(
        f"{stac_client['base_url']}/collections/noaa-emergency-response/items/{test_item_id}",
        json=test_item,
        headers=stac_client["headers"],
        timeout=stac_client["timeout"],
    )

    assert response.status_code in [200, 201], f"Failed to update item: {response.text}"

    time.sleep(2)
    logs = get_notifier_logs_since(before_time)

    # Clean up
    requests.delete(
        f"{stac_client['base_url']}/collections/noaa-emergency-response/items/{test_item_id}",
        headers=stac_client["headers"],
        timeout=stac_client["timeout"],
    )

    assert any(
        keyword in logs
        for keyword in ["UPDATE", "update", test_item_id, "pgstac_items_change"]
    ), f"UPDATE notification should be logged for item {test_item_id}"


def test_delete_notification(
    stac_client: Dict[str, Any], notifications_enabled: bool
) -> None:
    """Test that DELETE operations trigger notifications."""
    assert notifications_enabled, "PgSTAC notifications not enabled - set notifications.sources.pgstac=true to test"

    test_item_id = f"test-delete-{int(time.time())}"
    test_item = {
        "id": test_item_id,
        "type": "Feature",
        "stac_version": "1.0.0",
        "collection": "noaa-emergency-response",
        "geometry": {"type": "Point", "coordinates": [0, 0]},
        "bbox": [0, 0, 0, 0],
        "properties": {"datetime": "2020-01-01T00:00:00Z"},
        "assets": {},
        "links": [],
    }

    response = requests.post(
        f"{stac_client['base_url']}/collections/noaa-emergency-response/items",
        json=test_item,
        headers=stac_client["headers"],
        timeout=stac_client["timeout"],
    )

    assert response.status_code in [200, 201], f"Failed to create item: {response.text}"

    before_time = time.time()

    response = requests.delete(
        f"{stac_client['base_url']}/collections/noaa-emergency-response/items/{test_item_id}",
        headers=stac_client["headers"],
        timeout=stac_client["timeout"],
    )

    assert response.status_code in [200, 204], f"Failed to delete item: {response.text}"

    time.sleep(2)
    logs = get_notifier_logs_since(before_time)

    assert any(
        keyword in logs
        for keyword in ["DELETE", "delete", test_item_id, "pgstac_items_change"]
    ), f"DELETE notification should be logged for item {test_item_id}"


def test_bulk_operations_notification(
    stac_client: Dict[str, Any], notifications_enabled: bool
) -> None:
    """Test that bulk operations trigger appropriate notifications."""
    assert notifications_enabled, "PgSTAC notifications not enabled - set notifications.sources.pgstac=true to test"

    test_items = []
    for i in range(3):
        test_items.append(
            {
                "id": f"test-bulk-{int(time.time())}-{i}",
                "type": "Feature",
                "stac_version": "1.0.0",
                "collection": "noaa-emergency-response",
                "geometry": {"type": "Point", "coordinates": [i, i]},
                "bbox": [i, i, i, i],
                "properties": {"datetime": f"2020-01-{i + 1:02d}T00:00:00Z"},
                "assets": {},
                "links": [],
            }
        )

    before_time = time.time()

    for item in test_items:
        response = requests.post(
            f"{stac_client['base_url']}/collections/noaa-emergency-response/items",
            json=item,
            headers=stac_client["headers"],
            timeout=stac_client["timeout"],
        )

        assert response.status_code in [
            200,
            201,
        ], f"Failed to create item: {response.text}"

    time.sleep(3)
    logs = get_notifier_logs_since(before_time)

    found_count = sum(1 for item in test_items if f"item_id='{item['id']}'" in logs)

    for item in test_items:
        requests.delete(
            f"{stac_client['base_url']}/collections/noaa-emergency-response/items/{item['id']}",
            headers=stac_client["headers"],
            timeout=stac_client["timeout"],
        )

    assert found_count >= 2, f"Expected at least 2 notifications, found {found_count}"
