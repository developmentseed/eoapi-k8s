"""Test STAC API with auth proxy authentication."""

import os

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
            "id": "test-no-token",
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
        assert resp.status_code in [401, 403], (
            f"Expected auth error, got {resp.status_code}: {resp.text[:100]}"
        )


def test_stac_auth_with_invalid_token(stac_endpoint: str) -> None:
    """Test write operation with invalid token - should be rejected."""
    resp = client.post(
        f"{stac_endpoint}/collections/noaa-emergency-response/items",
        headers={
            "Authorization": "Bearer invalid-token",
            "Content-Type": "application/json",
        },
        json={
            "id": "test-invalid-token",
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

    assert resp.status_code in [401, 403], (
        f"Expected auth error with invalid token, got {resp.status_code}: {resp.text[:100]}"
    )


def test_stac_auth_with_valid_token(
    stac_endpoint: str, valid_token: str
) -> None:
    """Test write operation with valid token - tests actual auth proxy behavior."""
    resp = client.post(
        f"{stac_endpoint}/collections/noaa-emergency-response/items",
        headers={
            "Authorization": valid_token,
            "Content-Type": "application/json",
        },
        json={
            "id": "test-valid-token",
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
    assert resp.status_code in [200, 201], (
        f"Expected success with valid token, got {resp.status_code}: {resp.text[:100]}"
    )


def test_stac_read_operations_work(stac_endpoint: str) -> None:
    """Test that read operations work without auth."""
    resp = client.get(stac_endpoint)
    assert resp.status_code == 200

    resp = client.get(f"{stac_endpoint}/collections")
    assert resp.status_code == 200
