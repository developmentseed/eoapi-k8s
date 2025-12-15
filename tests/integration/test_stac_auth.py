"""Test STAC API with auth proxy authentication."""

import os
import time

import httpx
import pytest

timeout = httpx.Timeout(15.0, connect=60.0)
client = httpx.Client(
    timeout=timeout,
    verify=not bool(os.getenv("IGNORE_SSL_VERIFICATION", False)),
)


@pytest.fixture
def valid_token(auth_token: str) -> str:
    """Get valid JWT token for auth testing."""
    return auth_token


def test_stac_auth_without_token(stac_endpoint: str) -> None:
    """Test write operation without token - should be rejected."""
    resp = client.post(
        f"{stac_endpoint}/collections/noaa-emergency-response/items",
        headers={"Content-Type": "application/json"},
        json={
            "id": f"test-no-token-{int(time.time() * 1000)}",
            "type": "Feature",
            "stac_version": "1.0.0",
            "properties": {"datetime": "2024-01-01T00:00:00Z"},
            "geometry": {"type": "Point", "coordinates": [0, 0]},
            "links": [],
            "assets": {},
            "collection": "noaa-emergency-response",
            "bbox": [-0.1, -0.1, 0.1, 0.1],
        },
    )

    if resp.status_code in [200, 201]:
        # Auth proxy should reject requests without tokens
        assert resp.status_code in [
            401,
            403,
        ], f"Expected auth error, got {resp.status_code}: {resp.text[:100]}"


def test_stac_auth_with_invalid_token(stac_endpoint: str) -> None:
    """Test write operation with invalid token - should be rejected."""
    resp = client.post(
        f"{stac_endpoint}/collections/noaa-emergency-response/items",
        headers={
            "Authorization": "Bearer invalid-token",
            "Content-Type": "application/json",
        },
        json={
            "id": f"test-invalid-token-{int(time.time() * 1000)}",
            "type": "Feature",
            "stac_version": "1.0.0",
            "properties": {"datetime": "2024-01-01T00:00:00Z"},
            "geometry": {"type": "Point", "coordinates": [0, 0]},
            "links": [],
            "assets": {},
            "collection": "noaa-emergency-response",
            "bbox": [-0.1, -0.1, 0.1, 0.1],
        },
    )

    assert (
        resp.status_code in [401, 403]
    ), f"Expected auth error with invalid token, got {resp.status_code}: {resp.text[:100]}"


def test_stac_auth_with_valid_token(stac_endpoint: str, valid_token: str) -> None:
    """Test write operation with valid token - tests actual auth proxy behavior."""
    resp = client.post(
        f"{stac_endpoint}/collections/noaa-emergency-response/items",
        headers={
            "Authorization": valid_token,
            "Content-Type": "application/json",
        },
        json={
            "id": f"test-valid-token-{int(time.time() * 1000)}",
            "type": "Feature",
            "stac_version": "1.0.0",
            "properties": {"datetime": "2024-01-01T00:00:00Z"},
            "geometry": {"type": "Point", "coordinates": [0, 0]},
            "links": [],
            "assets": {},
            "collection": "noaa-emergency-response",
            "bbox": [-0.1, -0.1, 0.1, 0.1],
        },
    )

    # With valid token from mock OIDC server, request should succeed
    assert resp.status_code in [
        200,
        201,
    ], f"Expected success with valid token, got {resp.status_code}: {resp.text[:100]}"


def test_stac_read_operations_work(stac_endpoint: str) -> None:
    """Test that read operations work without auth."""
    resp = client.get(stac_endpoint)
    assert resp.status_code == 200

    resp = client.get(f"{stac_endpoint}/collections")
    assert resp.status_code == 200


def test_stac_auth_custom_filters_mounted() -> None:
    """Test that custom filters ConfigMap, env vars, and file mount work correctly."""
    import subprocess

    namespace = os.getenv("NAMESPACE", "eoapi")
    release = os.getenv("RELEASE_NAME", "eoapi")

    # Check ConfigMap exists
    result = subprocess.run(
        [
            "kubectl",
            "get",
            "configmap",
            "-n",
            namespace,
            "eoapi-stac-auth-proxy-custom-filters",
            "-o",
            "jsonpath={.data.custom_filters\\.py}",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        pytest.skip("Custom filters ConfigMap not found (feature may be disabled)")

    # Verify ConfigMap contains filter classes
    assert "class CollectionsFilter" in result.stdout
    assert "class ItemsFilter" in result.stdout

    # Get stac-auth-proxy pod name
    result = subprocess.run(
        [
            "kubectl",
            "get",
            "pod",
            "-n",
            namespace,
            "-l",
            f"app.kubernetes.io/name=stac-auth-proxy,app.kubernetes.io/instance={release}",
            "-o",
            "jsonpath={.items[0].metadata.name}",
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    pod_name = result.stdout.strip()

    if not pod_name:
        pytest.skip("stac-auth-proxy pod not found")

    # Check env vars are set
    result = subprocess.run(
        [
            "kubectl",
            "exec",
            "-n",
            namespace,
            pod_name,
            "--",
            "printenv",
            "COLLECTIONS_FILTER_CLS",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, "COLLECTIONS_FILTER_CLS env var not set"
    assert (
        "stac_auth_proxy.custom_filters:CollectionsFilter" in result.stdout
    ), f"Unexpected COLLECTIONS_FILTER_CLS value: {result.stdout}"

    result = subprocess.run(
        [
            "kubectl",
            "exec",
            "-n",
            namespace,
            pod_name,
            "--",
            "printenv",
            "ITEMS_FILTER_CLS",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, "ITEMS_FILTER_CLS env var not set"
    assert (
        "stac_auth_proxy.custom_filters:ItemsFilter" in result.stdout
    ), f"Unexpected ITEMS_FILTER_CLS value: {result.stdout}"

    # Check if custom_filters.py is mounted at correct path
    result = subprocess.run(
        [
            "kubectl",
            "exec",
            "-n",
            namespace,
            pod_name,
            "--",
            "cat",
            "/app/src/stac_auth_proxy/custom_filters.py",
        ],
        capture_output=True,
        text=True,
        check=True,
    )

    # Verify mounted file contains expected filter classes
    assert "class CollectionsFilter" in result.stdout
    assert "class ItemsFilter" in result.stdout
    assert 'return "1=1"' in result.stdout
