# eoAPI Load Testing

This directory contains load testing utilities and scripts for eoAPI services with comprehensive performance metrics.

## Features

- **Response Time Tracking**: Measure p50, p95, p99 latency percentiles
- **Throughput Metrics**: Track requests/second over time
- **Infrastructure Monitoring**: Optional Prometheus integration for pod/HPA metrics
- **Flexible Reporting**: Console output + JSON export for CI/CD
- **Multiple Test Scenarios**: Stress, normal, chaos, and autoscaling tests

## Components

### `load_tester.py`
Core module containing the `LoadTester` class and unified CLI for all test types.

**Usage:**
```bash
# Run stress test with default settings
python3 -m tests.load.load_tester stress

# Normal load test with metrics export
python3 -m tests.load.load_tester normal \
  --base-url http://my-eoapi.com \
  --duration 60 \
  --users 10 \
  --report-json results.json

# Stress test with Prometheus integration
python3 -m tests.load.load_tester stress \
  --base-url http://my-eoapi.com \
  --max-workers 100 \
  --prometheus-url http://prometheus:9090 \
  --collect-infra-metrics \
  --report-json stress-results.json

# Chaos test with pod killing
python3 -m tests.load.load_tester chaos \
  --base-url http://my-eoapi.com \
  --namespace eoapi \
  --duration 300 \
  --kill-interval 60
```

**Common Parameters:**
- `--base-url`: Base URL for eoAPI services
- `--timeout`: Request timeout in seconds (default: 30)
- `--report-json FILE`: Export metrics to JSON file
- `--prometheus-url URL`: Prometheus URL for infrastructure metrics
- `--namespace NAME`: Kubernetes namespace (default: eoapi)
- `--collect-infra-metrics`: Collect Prometheus infrastructure metrics

**Stress Test Parameters:**
- `--endpoint`: Specific endpoint to test (default: `/stac/collections`)
- `--max-workers`: Maximum concurrent workers (default: 50)
- `--success-threshold`: Minimum success rate % (default: 95.0)
- `--step-size`: Worker increment step (default: 5)
- `--test-duration`: Duration per concurrency level in seconds (default: 10)
- `--cooldown`: Time between test levels in seconds (default: 2)

**Normal Test Parameters:**
- `--duration`: Test duration in seconds (default: 60)
- `--users`: Concurrent users (default: 10)

**Chaos Test Parameters:**
- `--duration`: Test duration in seconds (default: 300)
- `--kill-interval`: Seconds between pod kills (default: 60)

### Test Modules

#### `test_load.py`
Baseline load tests and shared fixtures for basic functionality verification.

**Test Classes:**
- `TestLoadBaseline`: Light load tests for basic service functionality
- `TestLoadScalability`: Response time and scalability tests
- `TestLoadIntegration`: Multi-service integration tests

#### `test_stress.py`
Stress testing to find breaking points and verify resilience under high load.

**Test Classes:**
- `TestStressBreakingPoints`: Find service breaking points
- `TestStressResilience`: Service recovery and sustained load tests
- `TestStressLimits`: Maximum capacity and error rate tests

#### `test_normal.py`
Realistic production workload patterns and sustained usage simulation.

**Test Classes:**
- `TestNormalMixedLoad`: Mixed endpoint realistic traffic patterns
- `TestNormalSustained`: Long-running moderate load tests
- `TestNormalUserPatterns`: User session and interaction simulation

#### `test_chaos.py`
Chaos engineering tests for infrastructure failure resilience.

**Test Classes:**
- `TestChaosResilience`: Pod failure and recovery tests
- `TestChaosNetwork`: Network instability and timeout handling
- `TestChaosResource`: Resource exhaustion and constraint tests
- `TestChaosRecovery`: Recovery timing and degradation patterns

**Running Load Tests:**
```bash
# Run all load tests
pytest tests/load/

# Run specific test types
pytest tests/load/test_load.py
pytest tests/load/test_normal.py
pytest tests/load/test_stress.py
pytest tests/load/test_chaos.py

# Run specific test classes
pytest tests/load/test_stress.py::TestStressBreakingPoints
pytest tests/load/test_normal.py::TestNormalMixedLoad

### `prometheus_utils.py`
Optional Prometheus integration for collecting infrastructure metrics during load tests.

**Features:**
- Query pod CPU/memory usage during tests
- Track HPA scaling events and replica counts
- Monitor request rates from ingress controller
- Collect database connection metrics
- Graceful degradation if Prometheus unavailable

**Usage:**
```python
from tests.load.prometheus_utils import PrometheusClient, collect_test_metrics

# Create client (automatically checks availability)
client = PrometheusClient("http://prometheus:9090")

if client.available:
    # Collect metrics for test period
    metrics = collect_test_metrics(
        prometheus_url="http://prometheus:9090",
        namespace="eoapi",
        start=test_start_time,
        end=test_end_time
    )
```

## Performance Metrics

All load tests now collect comprehensive metrics:

### Response Time Metrics
- **p50 (Median)**: Typical response time
- **p95**: 95th percentile - catches most slow requests
- **p99**: 99th percentile - identifies outliers
- **Min/Max/Avg**: Response time range and average

### Throughput Metrics
- **Requests/second**: Actual throughput during test
- **Success Rate**: Percentage of successful requests
- **Total Requests**: Count of all requests made

### Infrastructure Metrics (Optional, via Prometheus)
- **Pod Resources**: CPU/memory usage during test
- **HPA Events**: Autoscaling replica changes
- **Request Rates**: Ingress controller metrics
- **Database**: Connection counts and query times

### Example Output
```
============================================================
Stress Test - Breaking Point at 45 workers
============================================================
Success Rate:  92.3% (1156/1253)
Latency (ms):  p50=45 p95=123 p99=234 (min=12, max=456, avg=67)
Throughput:    41.8 req/s
Duration:      30.0s

Infrastructure Metrics:
  pod_cpu: Collected
  pod_memory: Collected
  hpa_scaling: Observed
  ingress_rate: Collected
============================================================
```

## Integration with Shell Scripts

The load testing is integrated with the main `eoapi-cli` script:

```bash
# Run all load tests
./eoapi-cli load all

# Run stress tests with metrics export
./eoapi-cli load stress --debug --report-json stress.json

# Run normal load with Prometheus
./eoapi-cli load normal \
  --prometheus-url http://prometheus:9090 \
  --collect-infra-metrics \
  --report-json normal.json

# Run chaos test
./eoapi-cli load chaos --debug
```

The shell script automatically:
- Installs Python dependencies
- Sets up environment variables
- Configures endpoints based on cluster state
- Runs tests with appropriate parameters
- Exports metrics if requested

## Configuration

### Environment Variables
- `STAC_ENDPOINT`: STAC service URL
- `RASTER_ENDPOINT`: Raster service URL
- `VECTOR_ENDPOINT`: Vector service URL
- `DEBUG_MODE`: Enable debug output

### Test Parameters
Tests can be configured via pytest markers:
- `@pytest.mark.slow`: Long-running stress tests
- `@pytest.mark.integration`: Multi-service tests

### Performance Thresholds
Default success rate thresholds:
- Health endpoints: 98%
- API endpoints: 95%
- Stress tests: 90%

Default latency expectations (normal load):
- p50: < 100ms
- p95: < 500ms
- p99: < 2000ms

## Best Practices

### Local Development
```bash
# Quick smoke test with metrics
python3 -m tests.load.load_tester stress \
  --max-workers 10 \
  --test-duration 5 \
  --report-json quick-test.json

# Baseline verification
pytest tests/load/test_load.py::TestLoadBaseline -v

# Check specific latency performance
pytest tests/load/test_normal.py::TestNormalSustained::test_consistent_response_times -v
```

### CI/CD Integration
```bash
# Fast load tests for CI with JSON export
pytest tests/load/ -m "not slow" --tb=short
./eoapi-cli load normal --report-json ci-metrics.json

# Full load testing with metrics
./eoapi-cli test all --debug

# Store metrics as CI artifacts
./eoapi-cli load stress --report-json artifacts/stress-metrics.json
```

### Production Validation
```bash
# Conservative stress test with Prometheus
python3 -m tests.load.load_tester stress \
  --base-url https://prod-eoapi.example.com \
  --max-workers 200 \
  --success-threshold 95.0 \
  --test-duration 30 \
  --cooldown 5 \
  --prometheus-url http://prometheus:9090 \
  --collect-infra-metrics \
  --report-json prod-stress-results.json

# Review metrics
cat prod-stress-results.json | jq '.metrics[] | {workers: .workers, success_rate, latency_p95, throughput}'
```

## Monitoring

### Real-time Monitoring
During load tests, monitor:
- **Test Metrics**: Watch console output for real-time p50/p95/p99 latencies
- **Pod Resources**: `kubectl top pods -n eoapi`
- **HPA Scaling**: `kubectl get hpa -n eoapi -w`
- **Pod Status**: `kubectl get pods -n eoapi -w`

### Prometheus Integration
If Prometheus is available, enable infrastructure metrics:
```bash
# Set Prometheus URL
export PROMETHEUS_URL=http://prometheus:9090

# Run test with infrastructure metrics
./eoapi-cli load stress --collect-infra-metrics --report-json results.json

# Review infrastructure metrics
cat results.json | jq '.metrics[].infrastructure'
```

### Metrics Analysis
```bash
# Extract latency trends
cat results.json | jq '.metrics[] | {workers, p95: .latency_p95, p99: .latency_p99}'

# Compare success rates across worker counts
cat results.json | jq '.metrics[] | {workers, success_rate, throughput}'

# Check if HPA scaled
cat results.json | jq '.metrics[].infrastructure.hpa_metrics'
```

## Troubleshooting

### Common Issues

**ImportError: No module named 'tests.load'**
- Ensure you're running from the project root directory
- Install dependencies: `pip install -r tests/requirements.txt`

**Connection refused errors**
- Verify services are running: `kubectl get pods -n eoapi`
- Check endpoints are accessible: `curl http://localhost/stac`
- Ensure ingress is configured correctly

**Low success rates**
- Check resource limits and requests in Helm values
- Verify HPA is configured for autoscaling
- Monitor pod logs for errors: `kubectl logs -f deployment/eoapi-stac -n eoapi`

### Debug Mode
Enable debug output for detailed information:
```bash
DEBUG_MODE=true python3 -m tests.load.stress_test
./scripts/load.sh stress --debug
```

## Extending

### Adding New Test Endpoints
1. Add endpoints to appropriate test modules (`test_load.py`, `test_stress.py`, etc.)
2. Update `load_tester.py` with endpoint-specific logic if needed
3. Add endpoint validation to shell scripts

### Custom Load Patterns
Create new test classes in the appropriate module:
```python
# In test_stress.py
class TestStressCustom:
    def test_my_stress_scenario(self, base_url: str):
        # Custom stress testing logic
        pass

# In test_normal.py
class TestNormalCustom:
    def test_my_normal_scenario(self, base_url: str):
        # Custom normal load testing logic
        pass
```

### Integration with Monitoring
Extend tests to collect metrics:
```python
from tests.load.load_tester import LoadTester
from tests.load.prometheus_utils import PrometheusClient

class MonitoringLoadTester(LoadTester):
    def __init__(self, base_url, prometheus_url=None, **kwargs):
        super().__init__(base_url, prometheus_url=prometheus_url, **kwargs)

    def test_with_metrics(self, url, workers, duration):
        # Run test with infrastructure metrics
        return self.test_concurrency_level(
            url, workers, duration,
            collect_infra_metrics=True
        )
```

### Custom Prometheus Queries
```python
from tests.load.prometheus_utils import PrometheusClient
from datetime import datetime

client = PrometheusClient("http://prometheus:9090")

# Custom query
result = client.query('rate(http_requests_total[5m])')

# Range query
result = client.query_range(
    'container_cpu_usage_seconds_total{namespace="eoapi"}',
    start=datetime.now() - timedelta(minutes=10),
    end=datetime.now(),
    step="15s"
)
```

## Metrics Reference

### Collected Metrics
Every load test collects:
- `success_count`: Number of successful requests (2xx status)
- `total_requests`: Total requests made
- `success_rate`: Percentage (0-100)
- `duration`: Actual test duration in seconds
- `throughput`: Requests per second
- `latency_min`: Minimum response time (ms)
- `latency_max`: Maximum response time (ms)
- `latency_avg`: Average response time (ms)
- `latency_p50`: 50th percentile (ms)
- `latency_p95`: 95th percentile (ms)
- `latency_p99`: 99th percentile (ms)

### Optional Infrastructure Metrics
When `--collect-infra-metrics` is enabled:
- `infrastructure.pod_metrics.cpu`: Pod CPU usage over time
- `infrastructure.pod_metrics.memory`: Pod memory usage over time
- `infrastructure.hpa_metrics.current_replicas`: HPA replica count
- `infrastructure.hpa_metrics.desired_replicas`: HPA target replicas
- `infrastructure.request_metrics.request_rate`: Ingress request rate
- `infrastructure.request_metrics.request_latency_p95`: Ingress latency
- `infrastructure.database_metrics.db_connections`: Database connections
- `infrastructure.database_metrics.db_query_duration`: Query duration

### JSON Export Format
```json
{
  "breaking_point": 45,
  "metrics": {
    "45": {
      "success_count": 1156,
      "total_requests": 1253,
      "success_rate": 92.3,
      "duration": 30.0,
      "throughput": 41.8,
      "
