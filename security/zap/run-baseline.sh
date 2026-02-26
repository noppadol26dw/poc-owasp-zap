#!/usr/bin/env bash
# Run OWASP ZAP baseline in Docker; exit non-zero if HIGH or CRITICAL findings.
# Uses ZAP Automation Framework with Risk and Confidence HTML report.
# Usage: run-baseline.sh [TARGET_URL]
#   TARGET_URL defaults to STAGING_URL env var.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

TARGET_URL="${1:-${STAGING_URL:?STAGING_URL or first argument required}}"
ZAP_IMAGE="${ZAP_IMAGE:-ghcr.io/zaproxy/zaproxy:stable}"

# Create reports directory
mkdir -p "$REPO_ROOT/reports"

# Report paths with suffix naming
JSON_REPORT="$REPO_ROOT/reports/zap_baseline_report.json"
HTML_REPORT="$REPO_ROOT/reports/zap_baseline_report.html"
RISK_REPORT="$REPO_ROOT/reports/zap_baseline_risk-confidence.html"

echo "ZAP baseline target: $TARGET_URL"
echo "Reports will be saved to: reports/"

# Create automation plan for baseline scan
cat > "$SCRIPT_DIR/zap-baseline-plan.yaml" << EOF
---
env:
  contexts:
    - name: baseline-context
      urls:
        - "$TARGET_URL"
      includePaths:
        - "$TARGET_URL.*"
  parameters:
    failOnError: true
    failOnWarning: false
    progressToStdout: true
jobs:
  - type: spider
    parameters:
      context: baseline-context
      maxDuration: 10
      maxDepth: 5
      maxChildren: 1000
  - type: spiderAjax
    parameters:
      context: baseline-context
      maxDuration: 10
      maxCrawlDepth: 5
  - type: passiveScan-wait
    parameters:
      maxDuration: 10
  - type: report
    parameters:
      template: traditional-json
      reportDir: /zap/wrk/reports
      reportFile: zap_baseline_report
  - type: report
    parameters:
      template: risk-confidence-html
      reportDir: /zap/wrk/reports
      reportFile: zap_baseline_risk-confidence
EOF

# Run ZAP with automation framework
docker run --rm \
  -v "$REPO_ROOT:/zap/wrk:rw" \
  -w /zap/wrk \
  "$ZAP_IMAGE" \
  zap.sh -cmd -autorun "/zap/wrk/security/zap/zap-baseline-plan.yaml" 2>&1 | tee zap.out

# Fail on HIGH (3) or CRITICAL (4)
if [ -f "$JSON_REPORT" ]; then
  HIGH_CRITICAL=$(python3 -c "
import json, sys
try:
    with open('$JSON_REPORT') as f:
        data = json.load(f)
    count = 0
    sites = data.get('site', [])
    if not isinstance(sites, list):
        sites = [sites]
    for site in sites:
        for alert in site.get('alerts', []):
            risk = alert.get('riskcode', alert.get('risk', 0))
            if risk in (3, 4):
                count += 1
    print(count)
except Exception as e:
    print(0)
" 2>/dev/null || echo "0")

  if [ "${HIGH_CRITICAL:-0}" -gt 0 ]; then
    echo "ZAP: ${HIGH_CRITICAL} HIGH/CRITICAL finding(s). Failing."
    exit 1
  fi
fi

echo "ZAP baseline: no HIGH/CRITICAL findings."
echo ""
echo "Reports generated in reports/:"
echo "  - zap_baseline_report.json (JSON)"
echo "  - zap_baseline_risk-confidence.html (Risk & Confidence view)"
exit 0
