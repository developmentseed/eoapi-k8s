#!/usr/bin/env bash

# eoAPI Runbook - Load Test with HPA Validation
#
# Standalone load-test script for running on client infrastructure.
# Captures baseline, runs a hey-based HTTP load, and snapshots HPA / pod
# state at every phase.  All output goes to both the terminal and a
# timestamped log file under $LOG_DIR.
#
# Prerequisites: kubectl (configured), curl, hey (auto-installed if missing)
# Usage:
#   bash loadtest.sh                          # defaults
#   NS=data-access URL=https://... bash loadtest.sh
#   LOAD_DURATION=10m LOAD_CONCURRENCY=100 bash loadtest.sh
#
# WARNING: Do NOT source this script (. ./loadtest.sh) — run it as a subprocess.
#          Sourcing will apply set -e to your login shell and any failure
#          will kill your SSH session.

# Guard: refuse to run if sourced into an interactive shell
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    echo "ERROR: This script must not be sourced. Run it as:" >&2
    echo "  bash ${BASH_SOURCE[0]}" >&2
    return 1 2>/dev/null || exit 1
fi

set -euo pipefail

###############################################################################
# CONFIG — override via environment
###############################################################################
NS="${NS:-data-access}"
URL="${URL:-https://stac-k8s.terrabyte.lrz.de/stac/collections}"
LOAD_DURATION="${LOAD_DURATION:-5m}"
LOAD_CONCURRENCY="${LOAD_CONCURRENCY:-50}"
RELEASE_NAME="${RELEASE_NAME:-eoapi}"

###############################################################################
# LOGGING — tee everything to a timestamped file
###############################################################################
LOG_DIR="${LOG_DIR:-$HOME/eoapi-loadtest-logs}"
mkdir -p "$LOG_DIR"
LOGFILE="$LOG_DIR/loadtest-$(date -u +'%Y%m%d-%H%M%S').log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "Logging to: $LOGFILE"

###############################################################################
# PHASE 0: Install hey (skip if already present)
###############################################################################
if ! command -v hey &>/dev/null; then
    if [[ -x "$HOME/bin/hey" ]]; then
        export PATH="$HOME/bin:$PATH"
    else
        echo "Installing hey..."
        mkdir -p ~/bin
        curl -fL -o ~/bin/hey https://storage.googleapis.com/hey-releases/hey_linux_amd64
        chmod +x ~/bin/hey
        export PATH="$HOME/bin:$PATH"
    fi
fi
echo "hey: $(command -v hey)"

###############################################################################
# PHASE 1: Baseline snapshot (before load)
###############################################################################
echo ""
echo "=========================================="
echo "  BASELINE — $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
echo "=========================================="

echo "--- Deployments ---"
kubectl get deploy -n "$NS" | grep -iE 'NAME|stac|auth-proxy|raster|vector'

echo "--- HPA ---"
kubectl get hpa -n "$NS"

echo "--- Pod resource usage ---"
kubectl top pods -n "$NS" 2>&1 \
    | grep -iE 'NAME|stac|auth-proxy|raster|vector' \
    || echo "(metrics-server not ready)"

echo "--- STAC HPA detail ---"
kubectl describe hpa "${RELEASE_NAME}-stac-hpa" -n "$NS" 2>&1 | tail -20

echo "--- Auth-proxy HPA detail ---"
kubectl describe hpa -n "$NS" 2>&1 | grep -A15 'auth-proxy' || echo "(no auth-proxy HPA)"

echo "--- Smoke test ---"
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$URL" || echo "FAIL")
echo "GET $URL → HTTP $HTTP_CODE"
if [[ "$HTTP_CODE" != "200" ]]; then
    echo "WARNING: Endpoint not returning 200 — load test results will be misleading"
fi

###############################################################################
# PHASE 2: Load test
###############################################################################
echo ""
echo "=========================================="
echo "  LOAD TEST — $(date -u +'%H:%M:%S UTC')"
echo "  $LOAD_DURATION @ ${LOAD_CONCURRENCY}c → $URL"
echo "=========================================="
echo ">>> Open a second terminal and run:"
echo "    watch -n 5 'date -u +%H:%M:%S; echo; kubectl get hpa -n $NS; echo; kubectl top pods -n $NS 2>&1 | grep -iE \"NAME|stac|auth-proxy\"'"
echo ""

hey -z "$LOAD_DURATION" -c "$LOAD_CONCURRENCY" "$URL"

echo ""
echo "  LOAD ENDED — $(date -u +'%H:%M:%S UTC')"

###############################################################################
# PHASE 3: Post-load snapshot
###############################################################################
echo ""
echo "=========================================="
echo "  POST-LOAD — $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
echo "=========================================="

echo "--- HPA ---"
kubectl get hpa -n "$NS"

echo "--- Pod resource usage ---"
kubectl top pods -n "$NS" 2>&1 \
    | grep -iE 'NAME|stac|auth-proxy|raster|vector'

echo "--- STAC HPA detail ---"
kubectl describe hpa "${RELEASE_NAME}-stac-hpa" -n "$NS" 2>&1 | tail -30

echo "--- STAC logs (last 5min) ---"
kubectl logs -n "$NS" "deploy/${RELEASE_NAME}-stac" --since=5m --tail=40 2>&1

echo "--- Auth-proxy logs (last 5min) ---"
kubectl logs -n "$NS" "deploy/${RELEASE_NAME}-stac-auth-proxy" --since=5m --tail=40 2>&1

echo "--- Pod restarts ---"
kubectl get pods -n "$NS" -o wide | grep -iE 'NAME|stac|auth-proxy'

###############################################################################
# PHASE 4: Cooldown (wait for HPA scale-down)
###############################################################################
echo ""
echo "Waiting 5 minutes for scale-down cooldown..."
sleep 300

echo ""
echo "=========================================="
echo "  COOLDOWN — $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
echo "=========================================="
echo "--- HPA ---"
kubectl get hpa -n "$NS"
echo "--- Pods ---"
kubectl get pods -n "$NS" | grep -iE 'NAME|stac|auth-proxy'

echo ""
echo "=========================================="
echo "  DONE — full log at: $LOGFILE"
echo "=========================================="
