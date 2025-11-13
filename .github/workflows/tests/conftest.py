import json
import os
import subprocess
import time
from typing import Any, Dict, Generator, List, Optional, cast

import psycopg2
import psycopg2.extensions
import pytest
import requests


@pytest.fixture(scope="session")
def raster_endpoint() -> str:
    return os.getenv("RASTER_ENDPOINT", "http://127.0.0.1/raster")


@pytest.fixture(scope="session")
def vector_endpoint() -> str:
    return os.getenv("VECTOR_ENDPOINT", "http://127.0.0.1/vector")


@pytest.fixture(scope="session")
def stac_endpoint() -> str:
    return os.getenv("STAC_ENDPOINT", "http://127.0.0.1/stac")


@pytest.fixture(scope="session")
def db_connection() -> Generator[psycopg2.extensions.connection, None, None]:
    required_vars = ["PGHOST", "PGPORT", "PGDATABASE", "PGUSER", "PGPASSWORD"]
    missing_vars = [var for var in required_vars if not os.getenv(var)]
    if missing_vars:
        pytest.fail(
            f"Required environment variables not set: {', '.join(missing_vars)}"
        )

    connection_params = {
        "host": os.getenv("PGHOST"),
        "port": os.getenv("PGPORT"),
        "database": os.getenv("PGDATABASE"),
        "user": os.getenv("PGUSER"),
        "password": os.getenv("PGPASSWORD"),
    }

    # All required vars are guaranteed to exist due to check above
    try:
        conn = psycopg2.connect(
            host=os.environ["PGHOST"],
            port=int(os.environ["PGPORT"]),
            database=os.environ["PGDATABASE"],
            user=os.environ["PGUSER"],
            password=os.environ["PGPASSWORD"],
        )
        conn.set_isolation_level(psycopg2.extensions.ISOLATION_LEVEL_AUTOCOMMIT)
        yield conn
        conn.close()
    except psycopg2.Error as e:
        pytest.fail(f"Cannot connect to database: {e}")


def get_namespace() -> str:
    """Get the namespace from environment variable."""
    return os.environ.get("NAMESPACE", "eoapi")


def get_release_name() -> str:
    """Get the release name from environment variable."""
    return os.environ.get("RELEASE_NAME", "eoapi")


def kubectl_get(
    resource: str,
    namespace: Optional[str] = None,
    label_selector: Optional[str] = None,
    output: str = "json",
) -> subprocess.CompletedProcess[str]:
    cmd: List[str] = ["kubectl", "get", resource]

    if namespace:
        cmd.extend(["-n", namespace])

    if label_selector:
        cmd.extend(["-l", label_selector])

    if output:
        cmd.extend(["-o", output])

    result = subprocess.run(cmd, capture_output=True, text=True)
    return result


def kubectl_port_forward(
    service: str, local_port: int, remote_port: int, namespace: str
) -> subprocess.Popen[str]:
    cmd = [
        "kubectl",
        "port-forward",
        f"svc/{service}",
        f"{local_port}:{remote_port}",
        "-n",
        namespace,
    ]

    process = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )

    time.sleep(3)
    return process


def wait_for_url(url: str, timeout: int = 30, interval: int = 2) -> bool:
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


def make_request(url: str, timeout: int = 10) -> bool:
    try:
        response = requests.get(url, timeout=timeout)
        return response.status_code == 200
    except requests.RequestException:
        return False


def get_base_url() -> str:
    """Get the base URL for API access."""
    namespace = get_namespace()

    # Check if we have an ingress
    result = subprocess.run(
        ["kubectl", "get", "ingress", "-n", namespace, "-o", "json"],
        capture_output=True,
        text=True,
    )

    if result.returncode == 0:
        ingress_data = json.loads(result.stdout)
        if ingress_data["items"]:
            ingress = ingress_data["items"][0]
            rules = ingress.get("spec", {}).get("rules", [])
            if rules:
                host = rules[0].get("host", "localhost")
                # Check if host is accessible
                try:
                    response = requests.get(
                        f"http://{host}/stac/collections", timeout=5
                    )
                    if response.status_code == 200:
                        return f"http://{host}"
                except requests.RequestException:
                    pass

    return "http://localhost:8080"


def get_pod_metrics(namespace: str, service_name: str) -> List[Dict[str, str]]:
    """Get CPU and memory metrics for pods of a specific service."""
    release_name_val = get_release_name()
    result = subprocess.run(
        [
            "kubectl",
            "top",
            "pods",
            "-n",
            namespace,
            "-l",
            f"app={release_name_val}-{service_name}",
            "--no-headers",
        ],
        capture_output=True,
        text=True,
    )

    if result.returncode != 0:
        return []

    metrics: List[Dict[str, str]] = []
    for line in result.stdout.strip().split("\n"):
        if line.strip():
            parts = line.split()
            if len(parts) >= 3:
                pod_name = parts[0]
                cpu = parts[1]  # e.g., "25m"
                memory = parts[2]  # e.g., "128Mi"
                metrics.append({"pod": pod_name, "cpu": cpu, "memory": memory})

    return metrics


def get_hpa_status(namespace: str, hpa_name: str) -> Optional[Dict[str, Any]]:
    """Get HPA status for a specific HPA."""
    result = kubectl_get("hpa", namespace=namespace, output="json")
    if result.returncode != 0:
        return None

    hpas = json.loads(result.stdout)
    for hpa in hpas["items"]:
        if hpa["metadata"]["name"] == hpa_name:
            return cast(Dict[str, Any], hpa)

    return None


def get_pod_count(namespace: str, service_name: str) -> int:
    """Get the count of running pods for a specific service."""
    release_name_val = get_release_name()
    result = kubectl_get(
        "pods",
        namespace=namespace,
        label_selector=f"app={release_name_val}-{service_name}",
    )

    if result.returncode != 0:
        return 0

    pods = json.loads(result.stdout)
    running_pods = [
        pod for pod in pods["items"] if pod["status"]["phase"] == "Running"
    ]

    return len(running_pods)
