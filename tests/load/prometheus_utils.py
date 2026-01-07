#!/usr/bin/env python3
"""
Prometheus Integration for Load Testing

Optional module for querying Prometheus metrics during load tests.
Gracefully degrades if Prometheus is unavailable.
"""

import logging
from datetime import datetime
from typing import Dict, Optional

import requests

logger = logging.getLogger(__name__)

DEFAULT_PROMETHEUS_URL = "http://localhost:9090"
DEFAULT_TIMEOUT = 10


class PrometheusClient:
    """Simple Prometheus client for querying metrics during load tests"""

    def __init__(
        self, url: str = DEFAULT_PROMETHEUS_URL, timeout: int = DEFAULT_TIMEOUT
    ):
        """
        Initialize Prometheus client

        Args:
            url: Prometheus server URL
            timeout: Request timeout in seconds
        """
        self.url = url.rstrip("/")
        self.timeout = timeout
        self.available = self._check_availability()

    def _check_availability(self) -> bool:
        """Check if Prometheus is available"""
        try:
            response = requests.get(
                f"{self.url}/api/v1/status/config",
                timeout=self.timeout,
            )
            if response.status_code == 200:
                logger.info(f"Prometheus available at {self.url}")
                return True
            logger.warning(f"Prometheus returned status {response.status_code}")
            return False
        except Exception as e:
            logger.debug(f"Prometheus not available at {self.url}: {e}")
            return False

    def query(self, query: str, time: Optional[datetime] = None) -> Optional[Dict]:
        """
        Execute instant Prometheus query

        Args:
            query: PromQL query string
            time: Optional time for query (defaults to now)

        Returns:
            Query result dict or None if unavailable
        """
        if not self.available:
            return None

        try:
            params: dict[str, str | float] = {"query": query}
            if time:
                params["time"] = time.timestamp()

            response = requests.get(
                f"{self.url}/api/v1/query",
                params=params,
                timeout=self.timeout,
            )

            if response.status_code == 200:
                data = response.json()
                if data.get("status") == "success":
                    return data.get("data", {})

            logger.warning(f"Prometheus query failed: {response.status_code}")
            return None
        except Exception as e:
            logger.debug(f"Prometheus query error: {e}")
            return None

    def query_range(
        self,
        query: str,
        start: datetime,
        end: datetime,
        step: str = "15s",
    ) -> Optional[Dict]:
        """
        Execute range Prometheus query

        Args:
            query: PromQL query string
            start: Start time
            end: End time
            step: Query resolution step

        Returns:
            Query result dict or None if unavailable
        """
        if not self.available:
            return None

        try:
            params: dict[str, str | float] = {
                "query": query,
                "start": start.timestamp(),
                "end": end.timestamp(),
                "step": step,
            }

            response = requests.get(
                f"{self.url}/api/v1/query_range",
                params=params,
                timeout=self.timeout,
            )

            if response.status_code == 200:
                data = response.json()
                if data.get("status") == "success":
                    return data.get("data", {})

            logger.warning(f"Prometheus range query failed: {response.status_code}")
            return None
        except Exception as e:
            logger.debug(f"Prometheus range query error: {e}")
            return None


def get_pod_metrics(
    client: PrometheusClient,
    namespace: str,
    start: datetime,
    end: datetime,
) -> Dict[str, Optional[Dict]]:
    """
    Get pod CPU and memory metrics for the test duration

    Args:
        client: PrometheusClient instance
        namespace: Kubernetes namespace
        start: Test start time
        end: Test end time

    Returns:
        Dict with CPU and memory metrics or empty values if unavailable
    """
    metrics = {}

    # CPU usage
    cpu_query = (
        f'rate(container_cpu_usage_seconds_total{{namespace="{namespace}",'
        f'container!="",container!="POD"}}[1m])'
    )
    metrics["cpu"] = client.query_range(cpu_query, start, end)

    # Memory usage
    memory_query = (
        f'container_memory_working_set_bytes{{namespace="{namespace}",'
        f'container!="",container!="POD"}}'
    )
    metrics["memory"] = client.query_range(memory_query, start, end)

    return metrics


def get_hpa_metrics(
    client: PrometheusClient,
    namespace: str,
    start: datetime,
    end: datetime,
) -> Dict[str, Optional[Dict]]:
    """
    Get HPA scaling events and replica counts

    Args:
        client: PrometheusClient instance
        namespace: Kubernetes namespace
        start: Test start time
        end: Test end time

    Returns:
        Dict with HPA metrics or empty values if unavailable
    """
    metrics = {}

    # Current replicas
    replicas_query = f'kube_horizontalpodautoscaler_status_current_replicas{{namespace="{namespace}"}}'
    metrics["current_replicas"] = client.query_range(replicas_query, start, end)

    # Desired replicas
    desired_query = f'kube_horizontalpodautoscaler_status_desired_replicas{{namespace="{namespace}"}}'
    metrics["desired_replicas"] = client.query_range(desired_query, start, end)

    return metrics


def get_request_metrics(
    client: PrometheusClient,
    namespace: str,
    start: datetime,
    end: datetime,
) -> Dict[str, Optional[Dict]]:
    """
    Get request rate and latency from ingress/service mesh

    Args:
        client: PrometheusClient instance
        namespace: Kubernetes namespace
        start: Test start time
        end: Test end time

    Returns:
        Dict with request metrics or empty values if unavailable
    """
    metrics = {}

    # Request rate (depends on ingress controller)
    # Try nginx ingress first
    rate_query = (
        f'rate(nginx_ingress_controller_requests{{namespace="{namespace}"}}[1m])'
    )
    metrics["request_rate"] = client.query_range(rate_query, start, end)

    # Request duration
    latency_query = (
        f"histogram_quantile(0.95, "
        f"rate(nginx_ingress_controller_request_duration_seconds_bucket"
        f'{{namespace="{namespace}"}}[1m]))'
    )
    metrics["request_latency_p95"] = client.query_range(latency_query, start, end)

    return metrics


def get_database_metrics(
    client: PrometheusClient,
    namespace: str,
    start: datetime,
    end: datetime,
) -> Dict[str, Optional[Dict]]:
    """
    Get database connection and query metrics

    Args:
        client: PrometheusClient instance
        namespace: Kubernetes namespace
        start: Test start time
        end: Test end time

    Returns:
        Dict with database metrics or empty values if unavailable
    """
    metrics = {}

    # PostgreSQL connections
    connections_query = f'pg_stat_activity_count{{namespace="{namespace}"}}'
    metrics["db_connections"] = client.query_range(connections_query, start, end)

    # Query duration
    query_duration = (
        f'rate(pg_stat_statements_mean_exec_time{{namespace="{namespace}"}}[1m])'
    )
    metrics["db_query_duration"] = client.query_range(query_duration, start, end)

    return metrics


def collect_test_metrics(
    prometheus_url: Optional[str],
    namespace: str,
    start: datetime,
    end: datetime,
) -> Dict[str, Dict]:
    """
    Collect all available infrastructure metrics for a test

    Args:
        prometheus_url: Prometheus URL (None to skip)
        namespace: Kubernetes namespace
        start: Test start time
        end: Test end time

    Returns:
        Dict with all collected metrics (empty dicts if unavailable)
    """
    if not prometheus_url:
        logger.info("Prometheus URL not provided, skipping metrics collection")
        return {}

    client = PrometheusClient(prometheus_url)
    if not client.available:
        logger.info("Prometheus unavailable, skipping metrics collection")
        return {}

    logger.info(f"Collecting infrastructure metrics from {start} to {end}")

    all_metrics = {
        "pod_metrics": get_pod_metrics(client, namespace, start, end),
        "hpa_metrics": get_hpa_metrics(client, namespace, start, end),
        "request_metrics": get_request_metrics(client, namespace, start, end),
        "database_metrics": get_database_metrics(client, namespace, start, end),
    }

    # Filter out None values
    return {k: v for k, v in all_metrics.items() if v and any(v.values())}


def summarize_metrics(metrics: Dict) -> Dict[str, str]:
    """
    Create human-readable summary of infrastructure metrics

    Args:
        metrics: Infrastructure metrics dict

    Returns:
        Dict with summarized metrics for display
    """
    summary = {}

    # Pod metrics
    if "pod_metrics" in metrics:
        pod = metrics["pod_metrics"]
        if pod.get("cpu"):
            summary["pod_cpu"] = "Collected"
        if pod.get("memory"):
            summary["pod_memory"] = "Collected"

    # HPA metrics
    if "hpa_metrics" in metrics:
        hpa = metrics["hpa_metrics"]
        if hpa.get("current_replicas"):
            summary["hpa_scaling"] = "Observed"

    # Request metrics
    if "request_metrics" in metrics:
        req = metrics["request_metrics"]
        if req.get("request_rate"):
            summary["ingress_rate"] = "Collected"
        if req.get("request_latency_p95"):
            summary["ingress_latency"] = "Collected"

    # Database metrics
    if "database_metrics" in metrics:
        db = metrics["database_metrics"]
        if db.get("db_connections"):
            summary["db_connections"] = "Collected"

    return summary if summary else {"status": "No metrics available"}
