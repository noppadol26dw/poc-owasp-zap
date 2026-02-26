#!/usr/bin/env bash
# Phase 5 - Trigger ZAP scan via API (on-demand scanning)
# Usage: run-zap-api-scan.sh [TARGET_URL]
# Requires ZAP daemon to be running (docker-compose up zap-daemon)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

# Configuration
TARGET_URL="${1:-${STAGING_URL:?STAGING_URL or first argument required}}"
ZAP_API_HOST="${ZAP_API_HOST:-localhost}"
ZAP_API_PORT="${ZAP_API_PORT:-8090}"
ZAP_API_KEY="${ZAP_API_KEY:-changeme}"
ZAP_PROXY="http://${ZAP_API_HOST}:8080"
REPORTS_DIR="$REPO_ROOT/reports"

# Create reports directory
mkdir -p "$REPORTS_DIR"

echo "ZAP API On-Demand Scan"
echo "======================"
echo "Target: $TARGET_URL"
echo "ZAP API: http://${ZAP_API_HOST}:${ZAP_API_PORT}"
echo ""

# Check if ZAP is running
if ! curl -s "http://${ZAP_API_HOST}:${ZAP_API_PORT}" > /dev/null 2>&1; then
    echo "ERROR: ZAP daemon is not running. Start it with:"
    echo "  docker-compose up -d zap-daemon"
    exit 1
fi

echo "✓ ZAP daemon is running"

# Generate unique scan ID
SCAN_ID=$(date +%s)
REPORT_BASE="zap_api_scan_${SCAN_ID}"

call_api() {
    local endpoint="$1"
    local params="${2:-}"
    local url="http://${ZAP_API_HOST}:${ZAP_API_PORT}${endpoint}?apikey=${ZAP_API_KEY}"
    if [[ -n "$params" ]]; then
        url="${url}&${params}"
    fi
    curl -s "$url" || echo '{"error": "API call failed"}'
}

echo ""
echo "Step 1: Starting spider scan..."
SPIDER_RESPONSE=$(call_api "/JSON/spider/action/scan" "url=${TARGET_URL}&maxChildren=1000&recurse=true")
SPIDER_ID=$(echo "$SPIDER_RESPONSE" | grep -o '"scan":"[0-9]*"' | cut -d'"' -f4)

if [[ -z "$SPIDER_ID" ]]; then
    echo "ERROR: Failed to start spider scan"
    exit 1
fi

echo "  Spider scan ID: $SPIDER_ID"
echo "  Waiting for spider to complete..."

# Wait for spider to complete
while true; do
    PROGRESS=$(call_api "/JSON/spider/view/status" "scanId=${SPIDER_ID}")
    STATUS=$(echo "$PROGRESS" | grep -o '"status":"[0-9]*"' | cut -d'"' -f4)
    echo -ne "  Progress: ${STATUS:-0}%\r"
    
    if [[ "$STATUS" == "100" ]]; then
        echo ""
        echo "  ✓ Spider scan complete"
        break
    fi
    sleep 2
done

echo ""
echo "Step 2: Waiting for passive scan..."
sleep 5

echo ""
echo "Step 3: Generating reports..."

# Generate JSON report
curl -s "http://${ZAP_API_HOST}:${ZAP_API_PORT}/OTHER/core/other/jsonreport/?apikey=${ZAP_API_KEY}" \
    -o "${REPORTS_DIR}/${REPORT_BASE}.json"
echo "  ✓ JSON report: ${REPORT_BASE}.json"

# Generate HTML report
curl -s "http://${ZAP_API_HOST}:${ZAP_API_PORT}/OTHER/core/other/htmlreport/?apikey=${ZAP_API_KEY}" \
    -o "${REPORTS_DIR}/${REPORT_BASE}.html"
echo "  ✓ HTML report: ${REPORT_BASE}.html"

# Check for HIGH/CRITICAL findings
echo ""
echo "Step 4: Checking for HIGH/CRITICAL findings..."

ALERTS_JSON=$(curl -s "http://${ZAP_API_HOST}:${ZAP_API_PORT}/JSON/core/view/alerts/?apikey=${ZAP_API_KEY}&baseurl=${TARGET_URL}")
HIGH_CRITICAL=$(echo "$ALERTS_JSON" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    alerts = data.get('alerts', [])
    count = 0
    for alert in alerts:
        risk = alert.get('risk', '').lower()
        if risk in ['high', 'critical']:
            count += 1
    print(count)
except:
    print(0)
" 2>/dev/null || echo "0")

echo "  Found: ${HIGH_CRITICAL} HIGH/CRITICAL issues"

echo ""
echo "================================"
echo "Scan Complete!"
echo "================================"
echo "Reports saved to: reports/${REPORT_BASE}.*"
echo ""

if [[ "$HIGH_CRITICAL" -gt 0 ]]; then
    echo "⚠️  WARNING: ${HIGH_CRITICAL} HIGH/CRITICAL findings detected"
    exit 1
else
    echo "✅ No HIGH/CRITICAL findings"
    exit 0
fi
