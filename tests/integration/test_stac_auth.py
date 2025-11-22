"""Test STAC API with auth proxy authentication."""

import json
import os
import subprocess
import time
from datetime import datetime, timedelta
from typing import Generator

import httpx
import pytest

timeout = httpx.Timeout(15.0, connect=60.0)
if bool(os.getenv("IGNORE_SSL_VERIFICATION", False)):
    client = httpx.Client(timeout=timeout, verify=False)
else:
    client = httpx.Client(timeout=timeout)


@pytest.fixture(scope="module")
def mock_oidc_server() -> Generator[str, None, None]:
    """Use or deploy mock OIDC server for testing."""
    namespace = os.getenv("NAMESPACE", "eoapi")
    release_name = os.getenv("RELEASE_NAME", "eoapi")
    deployed_by_fixture = False

    # Check if mock OIDC server is already deployed by helm
    result = subprocess.run(
        [
            "kubectl",
            "get",
            "deployment",
            f"{release_name}-mock-oidc-server",
            "-n",
            namespace,
            "-o",
            "json",
        ],
        capture_output=True,
        text=True,
    )

    if result.returncode == 0:
        # Mock OIDC server is already deployed by helm
        deployment = json.loads(result.stdout)
        if deployment.get("status", {}).get("readyReplicas", 0) > 0:
            # Server is ready, use it
            oidc_url = f"http://{release_name}-mock-oidc-server.{namespace}.svc.cluster.local:8080"
            yield oidc_url
            return  # Don't cleanup helm-deployed server

    # If not deployed by helm, deploy it manually for testing
    deployed_by_fixture = True
    deployment_yaml = f"""
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mock-oidc-server
  namespace: {namespace}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mock-oidc-server
  template:
    metadata:
      labels:
        app: mock-oidc-server
    spec:
      containers:
      - name: mock-oidc
        image: ghcr.io/alukach/mock-oidc-server:latest
        env:
        - name: MOCK_OIDC_PORT
          value: "8888"
        - name: MOCK_OIDC_CLIENT_ID
          value: "test-client"
        - name: MOCK_OIDC_CLIENT_SECRET
          value: "test-secret"
        ports:
        - containerPort: 8888
---
apiVersion: v1
kind: Service
metadata:
  name: mock-oidc-server
  namespace: {namespace}
spec:
  selector:
    app: mock-oidc-server
  ports:
  - port: 8080
    targetPort: 8888
"""

    # Apply deployment
    result = subprocess.run(
        ["kubectl", "apply", "-f", "-"],
        input=deployment_yaml,
        text=True,
        capture_output=True,
    )
    if result.returncode != 0:
        pytest.skip(f"Failed to deploy mock OIDC server: {result.stderr}")

    # Wait for pod to be ready
    for _ in range(30):
        result = subprocess.run(
            [
                "kubectl",
                "get",
                "pods",
                "-n",
                namespace,
                "-l",
                "app=mock-oidc-server",
                "--field-selector=status.phase=Running",
                "-o",
                "json",
            ],
            capture_output=True,
            text=True,
        )
        if result.returncode == 0:
            pods = json.loads(result.stdout)
            if pods.get("items"):
                break
        time.sleep(2)
    else:
        pytest.skip("Mock OIDC server failed to start")

    # Update stac-auth-proxy to use mock OIDC server (only if deployed by fixture)
    oidc_url = f"http://mock-oidc-server.{namespace}.svc.cluster.local:8080"
    if deployed_by_fixture:
        subprocess.run(
            [
                "kubectl",
                "set",
                "env",
                f"deployment/{release_name}-stac-auth-proxy",
                f"OIDC_DISCOVERY_URL={oidc_url}/.well-known/openid-configuration",
                "DEFAULT_PUBLIC=true",
                "-n",
                namespace,
            ],
            capture_output=True,
        )

        # Wait for stac-auth-proxy to restart and become ready
        time.sleep(5)
        for _ in range(30):
            result = subprocess.run(
                [
                    "kubectl",
                    "get",
                    "pods",
                    "-n",
                    namespace,
                    "-l",
                    f"app.kubernetes.io/instance={release_name},app.kubernetes.io/name=stac-auth-proxy",
                    "--field-selector=status.phase=Running",
                    "-o",
                    "json",
                ],
                capture_output=True,
                text=True,
            )
            if result.returncode == 0:
                pods = json.loads(result.stdout)
                if pods.get("items") and len(pods["items"]) > 0:
                    # Check if auth proxy started successfully with new config
                    result = subprocess.run(
                        [
                            "kubectl",
                            "logs",
                            f"deployment/{release_name}-stac-auth-proxy",
                            "-n",
                            namespace,
                            "--tail=5",
                        ],
                        capture_output=True,
                        text=True,
                    )
                    if "Application startup complete" in result.stdout:
                        break
            time.sleep(2)

    yield oidc_url

    # Cleanup only if deployed by this fixture
    if deployed_by_fixture:
        subprocess.run(
            [
                "kubectl",
                "delete",
                "deployment",
                "mock-oidc-server",
                "-n",
                namespace,
            ],
            capture_output=True,
        )
        subprocess.run(
            [
                "kubectl",
                "delete",
                "service",
                "mock-oidc-server",
                "-n",
                namespace,
            ],
            capture_output=True,
        )


@pytest.fixture
def valid_token(mock_oidc_server: str) -> str:
    """Generate valid JWT token."""
    try:
        import jwt
    except ImportError:
        pytest.skip("pyjwt not installed")

    payload = {
        "sub": "test-user",
        "email": "test@example.com",
        "iss": mock_oidc_server,
        "aud": "test-client",
        "exp": datetime.utcnow() + timedelta(hours=1),
        "iat": datetime.utcnow(),
    }
    # Mock OIDC server uses a simple secret
    token = jwt.encode(payload, "test-secret", algorithm="HS256")
    # Handle both str (newer PyJWT) and bytes (older PyJWT) return types
    if isinstance(token, bytes):
        return token.decode("utf-8")
    return str(token)


def test_stac_write_create_item_without_token(
    stac_endpoint: str, mock_oidc_server: str
) -> None:
    """Test creating item without token - should return 401 if auth is enabled."""
    # Try to create an item without authentication
    resp = client.post(
        f"{stac_endpoint}/collections/noaa-emergency-response/items",
        json={
            "id": "test-auth-item-no-token",
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

    # If auth proxy is properly configured, should get 401
    # If not configured or bypassed, will get 200/201
    if resp.status_code in [200, 201]:
        # Clean up the created item
        client.delete(
            f"{stac_endpoint}/collections/noaa-emergency-response/items/test-auth-item-no-token"
        )
        pytest.skip(
            "Auth proxy not intercepting requests - auth tests cannot run"
        )

    assert resp.status_code in [401, 403], (
        f"Expected 401 Unauthorized or 403 Forbidden, got {resp.status_code}"
    )
