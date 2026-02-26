#!/usr/bin/env bash
# Phase 5 - Full ZAP scan via API (with active scanning)
# Usage: run-zap-api-scan-full.sh [TARGET_URL]
# Requires ZAP daemon to be running

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

# Configuration
TARGET_URL="${1:-${STAGING_URL:?STAGING_URL or first argument required}}"
ZAP_API_HOST="${ZAP_API_HOST:-localhost}"
ZAP_API_PORT="${ZAP_API_PORT:-8090}"
ZAP_API_KEY="${ZAP_API_KEY:-changeme}"
REPORTS_DIR="$REPO_ROOT/reports"

mkdir -p "$REPORTS_DIR"

echo "ZAP API Full Scan (with Active Scan)"
echo "===================================="
echo "Target: $TARGET_URL"
echo ""

# Check if ZAP is running
if ! curl -s "http://${ZAP_API_HOST}:${ZAP_API_PORT}" > /dev/null 2>&1; then
    echo "ERROR: ZAP daemon is not running"
    echo "Start with: docker-compose up -d zap-daemon"
    exit 1
fi

echo "✓ ZAP daemon is running"

SCAN_ID=$(date +%s)
REPORT_BASE="zap_api_full_scan_${SCAN_ID}"

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
echo "Step 1: Spider scan..."
SPIDER_RESPONSE=$(call_api "/JSON/spider/action/scan" "url=${TARGET_URL}&maxChildren=5000&recurse=true")
SPIDER_ID=$(echo "$SPIDER_RESPONSE" | grep -o '"scan":"[0-9]*"' | cut -d'"' -f4)

while true; do
    PROGRESS=$(call_api "/JSON/spider/view/status" "scanId=${SPIDER_ID}")
    STATUS=$(echo "$PROGRESS" | grep -o '"status":"[0-9]*"' | cut -d'"' -f4)
    echo -ne "  Spider: ${STATUS:-0}%\r"
    [[ "$STATUS" == "100" ]] && break
    sleep 2
done
echo -e "\n  ✓ Spider complete"

echo ""
echo "Step 2: Active scan..."
ASCAN_RESPONSE=$(call_api "/JSON/ascan/action/scan" "url=${TARGET_URL}&recurse=true&inScopeOnly=false")
ASCAN_ID=$(echo "$ASCAN_RESPONSE" | grep -o '"scan":"[0-9]*"' | cut -d'"' -f4)

while true; do
    PROGRESS=$(call_api "/JSON/ascan/view/status" "scanId=${ASCAN_ID}")
    STATUS=$(echo "$PROGRESS" | grep -o '"status":"[0-9]*"' | cut -d'"' -f4)
    echo -ne "  Active: ${STATUS:-0}%\r"
    [[ "$STATUS" == "100" ]] && break
    sleep 5
done
echo -e "\n  ✓ Active scan complete"

echo ""
echo "Step 3: Generating reports..."
curl -s "http://${ZAP_API_HOST}:${ZAP_API_PORT}/OTHER/core/other/jsonreport/?apikey=${ZAP_API_KEY}" \
    -o "${REPORTS_DIR}/${REPORT_BASE}.json"
curl -s "http://${ZAP_API_HOST}:${ZAP_API_PORT}/OTHER/core/other/htmlreport/?apikey=${ZAP_API_KEY}" \
    -o "${REPORTS_DIR}/${REPORT_BASE}.html"
echo "  ✓ Reports generated"

echo ""
echo "Full scan complete. Reports: ${REPORT_BASE}.*"
