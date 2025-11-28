# eoAPI Load Testing

This directory contains load testing utilities and scripts for eoAPI services.

## Components

### `load_tester.py`
Core module containing the `LoadTester` class and unified CLI for all test types.

**Usage:**
```bash
# Run with defaults (localhost, 50 max workers)
python3 -m tests.load.load_tester

# Custom configuration
python3 -m tests.load.load_tester \
  --base-url http://my-eoapi.com \
  --endpoint /stac/search \
  --max-workers 100 \
  --success-threshold 90.0 \
  --test-duration 15
```

**Parameters:**
- `--base-url`: Base URL for eoAPI services
- `--endpoint`: Specific endpoint to test (default: `/stac/collections`)
- `--max-workers`: Maximum concurrent workers (default: 50)
- `--success-threshold`: Minimum success rate % (default: 95.0)
- `--step-size`: Worker increment step (default: 5)
- `--test-duration`: Duration per concurrency level in seconds (default: 10)
- `--timeout`: Request timeout in seconds (default: 30)
- `--cooldown`: Time between test levels in seconds (default: 2)

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

## Integration with Shell Scripts

The load testing is integrated with the main `eoapi-cli` script:

```bash
./eoapi-cli load all

# Run stress tests with debug output
./eoapi-cli load stress --debug
```

The shell script automatically:
- Installs Python dependencies
- Sets up environment variables
- Configures endpoints based on cluster state
- Runs tests with appropriate parameters

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

## Best Practices

### Local Development
```bash
# Quick smoke test
python3 -m tests.load.stress_test --max-workers 10 --test-duration 5

# Baseline verification
pytest tests/load/test_load.py::TestLoadBaseline -v
```

### CI/CD Integration
```bash
# Fast load tests for CI
pytest tests/load/ -m "not slow" --tb=short

# Full load testing
./eoapi-cli test all --debug
```

### Production Validation
```bash
# Conservative stress test
python3 -m tests.load.stress_test \
  --max-workers 200 \
  --success-threshold 95.0 \
  --test-duration 30 \
  --cooldown 5
```

## Monitoring

During load tests, monitor:
- Pod CPU/Memory usage: `kubectl top pods -n eoapi`
- Service metrics: `kubectl get hpa -n eoapi`
- Response times and error rates in test output

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
from .load_tester import LoadTester

class MonitoringLoadTester(LoadTester):
    def collect_metrics(self):
        # Custom metrics collection
        pass
```
