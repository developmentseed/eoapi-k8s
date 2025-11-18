"""Test pgstac notification triggers."""

import json
import os
import subprocess
import time
from typing import Any, Generator

import pytest


@pytest.fixture(scope="session")
def notifications_enabled() -> bool:
    """Check if notifications are enabled in the deployment config by checking Helm values."""
    try:
        # Get release name from environment or default
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

        # Parse JSON and check notifications.sources.pgstac value
        values = json.loads(result.stdout)
        return bool(
            values.get("notifications", {})
            .get("sources", {})
            .get("pgstac", False)
        )
    except (subprocess.CalledProcessError, json.JSONDecodeError, Exception):
        # If we can't check the Helm values, assume notifications are disabled
        return False


@pytest.fixture
def notification_listener(db_connection: Any) -> Generator[Any, None, None]:
    """Set up notification listener for pgstac_items_change."""
    cursor = db_connection.cursor()
    cursor.execute("LISTEN pgstac_items_change;")
    yield cursor
    cursor.execute("UNLISTEN pgstac_items_change;")
    cursor.close()


def test_notification_triggers_exist(
    db_connection: Any, notifications_enabled: bool
) -> None:
    """Test that notification triggers and function are properly installed."""
    if not notifications_enabled:
        pytest.skip(
            "PgSTAC notifications not enabled - set notifications.sources.pgstac=true to test"
        )

    cursor = db_connection.cursor()

    # Check that the notification function exists
    cursor.execute("""
        SELECT EXISTS(
            SELECT 1 FROM pg_proc
            WHERE proname = 'notify_items_change_func'
        );
    """)
    assert cursor.fetchone()[0], (
        "notify_items_change_func function should exist"
    )

    # Check that all three triggers exist
    trigger_names = [
        "notify_items_change_insert",
        "notify_items_change_update",
        "notify_items_change_delete",
    ]

    for trigger_name in trigger_names:
        cursor.execute(
            """
            SELECT EXISTS(
                SELECT 1 FROM pg_trigger
                WHERE tgname = %s
                AND tgrelid = 'pgstac.items'::regclass
            );
        """,
            (trigger_name,),
        )
        assert cursor.fetchone()[0], (
            f"Trigger {trigger_name} should exist on pgstac.items"
        )

    cursor.close()


def test_insert_notification(
    db_connection: Any, notification_listener: Any, notifications_enabled: bool
) -> None:
    """Test that INSERT operations trigger notifications."""
    if not notifications_enabled:
        pytest.skip(
            "PgSTAC notifications not enabled - set notifications.sources.pgstac=true to test"
        )

    cursor = db_connection.cursor()

    # Clear any pending notifications
    db_connection.poll()
    while db_connection.notifies:
        db_connection.notifies.pop(0)

    # Use existing collection
    test_collection_id = "noaa-emergency-response"

    # Insert a test item using pgstac.create_item
    test_item_id = f"test-item-{int(time.time())}"
    item_data = json.dumps(
        {
            "id": test_item_id,
            "type": "Feature",
            "stac_version": "1.0.0",
            "collection": test_collection_id,
            "geometry": {"type": "Point", "coordinates": [0, 0]},
            "bbox": [0, 0, 0, 0],
            "properties": {"datetime": "2020-01-01T00:00:00Z"},
            "assets": {},
        }
    )

    cursor.execute("SELECT pgstac.create_item(%s);", (item_data,))

    # Wait for notification
    timeout = 5
    start_time = time.time()
    received_notification = False

    while time.time() - start_time < timeout:
        db_connection.poll()
        if db_connection.notifies:
            notify = db_connection.notifies.pop(0)
            assert notify.channel == "pgstac_items_change"

            # Parse the notification payload
            payload = json.loads(notify.payload)
            assert payload["operation"] == "INSERT"
            assert "items" in payload
            assert len(payload["items"]) == 1
            assert payload["items"][0]["id"] == test_item_id
            assert payload["items"][0]["collection"] == test_collection_id

            received_notification = True
            break
        time.sleep(0.1)

    assert received_notification, "Should have received INSERT notification"

    # Cleanup
    cursor.execute("SELECT pgstac.delete_item(%s);", (test_item_id,))
    cursor.close()


def test_update_notification(
    db_connection: Any, notification_listener: Any, notifications_enabled: bool
) -> None:
    """Test that UPDATE operations trigger notifications."""
    if not notifications_enabled:
        pytest.skip(
            "PgSTAC notifications not enabled - set notifications.sources.pgstac=true to test"
        )

    cursor = db_connection.cursor()

    # Clear any pending notifications
    db_connection.poll()
    while db_connection.notifies:
        db_connection.notifies.pop(0)

    test_collection_id = "noaa-emergency-response"

    # Insert a test item first using pgstac.create_item
    test_item_id = f"test-item-update-{int(time.time())}"
    item_data = json.dumps(
        {
            "id": test_item_id,
            "type": "Feature",
            "stac_version": "1.0.0",
            "collection": test_collection_id,
            "geometry": {"type": "Point", "coordinates": [0, 0]},
            "bbox": [0, 0, 0, 0],
            "properties": {"datetime": "2020-01-01T00:00:00Z"},
            "assets": {},
        }
    )

    cursor.execute("SELECT pgstac.create_item(%s);", (item_data,))

    # Clear INSERT notification
    db_connection.poll()
    while db_connection.notifies:
        db_connection.notifies.pop(0)

    # Update the item using pgstac.update_item
    updated_item_data = json.dumps(
        {
            "id": test_item_id,
            "type": "Feature",
            "stac_version": "1.0.0",
            "collection": test_collection_id,
            "geometry": {"type": "Point", "coordinates": [0, 0]},
            "bbox": [0, 0, 0, 0],
            "properties": {"datetime": "2020-01-01T00:00:00Z", "updated": True},
            "assets": {},
        }
    )

    cursor.execute("SELECT pgstac.update_item(%s);", (updated_item_data,))

    # Wait for notification
    timeout = 5
    start_time = time.time()
    received_notification = False

    while time.time() - start_time < timeout:
        db_connection.poll()
        if db_connection.notifies:
            notify = db_connection.notifies.pop(0)
            assert notify.channel == "pgstac_items_change"

            # Parse the notification payload - PgSTAC update uses DELETE+INSERT, so accept both
            payload = json.loads(notify.payload)
            assert payload["operation"] in [
                "DELETE",
                "INSERT",
                "UPDATE",
            ], (
                f"Operation should be DELETE, INSERT, or UPDATE, got {payload['operation']}"
            )
            assert "items" in payload
            assert len(payload["items"]) == 1
            assert payload["items"][0]["id"] == test_item_id
            assert payload["items"][0]["collection"] == test_collection_id

            received_notification = True
            break
        time.sleep(0.1)

    assert received_notification, "Should have received UPDATE notification"

    # Cleanup
    cursor.execute("SELECT pgstac.delete_item(%s);", (test_item_id,))
    cursor.close()


def test_delete_notification(
    db_connection: Any, notification_listener: Any, notifications_enabled: bool
) -> None:
    """Test that DELETE operations trigger notifications."""
    if not notifications_enabled:
        pytest.skip(
            "PgSTAC notifications not enabled - set notifications.sources.pgstac=true to test"
        )

    cursor = db_connection.cursor()

    # Clear any pending notifications
    db_connection.poll()
    while db_connection.notifies:
        db_connection.notifies.pop(0)

    test_collection_id = "noaa-emergency-response"

    # Insert a test item first using pgstac.create_item
    test_item_id = f"test-item-delete-{int(time.time())}"
    item_data = json.dumps(
        {
            "id": test_item_id,
            "type": "Feature",
            "stac_version": "1.0.0",
            "collection": test_collection_id,
            "geometry": {"type": "Point", "coordinates": [0, 0]},
            "bbox": [0, 0, 0, 0],
            "properties": {"datetime": "2020-01-01T00:00:00Z"},
            "assets": {},
        }
    )

    cursor.execute("SELECT pgstac.create_item(%s);", (item_data,))

    # Clear INSERT notification
    db_connection.poll()
    while db_connection.notifies:
        db_connection.notifies.pop(0)

    # Delete the item using pgstac.delete_item
    cursor.execute("SELECT pgstac.delete_item(%s);", (test_item_id,))

    # Wait for notification
    timeout = 5
    start_time = time.time()
    received_notification = False

    while time.time() - start_time < timeout:
        db_connection.poll()
        if db_connection.notifies:
            notify = db_connection.notifies.pop(0)
            assert notify.channel == "pgstac_items_change"

            # Parse the notification payload
            payload = json.loads(notify.payload)
            assert payload["operation"] == "DELETE"
            assert "items" in payload
            assert len(payload["items"]) == 1
            assert payload["items"][0]["id"] == test_item_id
            assert payload["items"][0]["collection"] == test_collection_id

            received_notification = True
            break
        time.sleep(0.1)

    assert received_notification, "Should have received DELETE notification"
    cursor.close()


def test_bulk_operations_notification(
    db_connection: Any, notification_listener: Any, notifications_enabled: bool
) -> None:
    """Test that bulk operations send notifications with multiple items."""
    if not notifications_enabled:
        pytest.skip(
            "PgSTAC notifications not enabled - set notifications.sources.pgstac=true to test"
        )

    cursor = db_connection.cursor()

    # Clear any pending notifications
    db_connection.poll()
    while db_connection.notifies:
        db_connection.notifies.pop(0)

    test_collection_id = "noaa-emergency-response"

    # Insert multiple items using pgstac.create_item
    test_items = [f"bulk-item-{i}-{int(time.time())}" for i in range(3)]

    for item_id in test_items:
        item_data = json.dumps(
            {
                "id": item_id,
                "type": "Feature",
                "stac_version": "1.0.0",
                "collection": test_collection_id,
                "geometry": {"type": "Point", "coordinates": [0, 0]},
                "bbox": [0, 0, 0, 0],
                "properties": {"datetime": "2020-01-01T00:00:00Z"},
                "assets": {},
            }
        )

        cursor.execute("SELECT pgstac.create_item(%s);", (item_data,))

    # Wait for notifications (should get one per insert since we're doing separate statements)
    timeout = 10
    start_time = time.time()
    notifications_received = 0

    while time.time() - start_time < timeout and notifications_received < len(
        test_items
    ):
        db_connection.poll()
        while db_connection.notifies:
            notify = db_connection.notifies.pop(0)
            assert notify.channel == "pgstac_items_change"

            payload = json.loads(notify.payload)
            assert payload["operation"] == "INSERT"
            assert "items" in payload
            notifications_received += len(payload["items"])

    assert notifications_received >= len(test_items), (
        f"Should have received notifications for all {len(test_items)} items"
    )

    # Cleanup
    for item_id in test_items:
        cursor.execute("SELECT pgstac.delete_item(%s);", (item_id,))

    cursor.close()
