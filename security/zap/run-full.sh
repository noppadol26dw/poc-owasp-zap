#!/usr/bin/env bash
# Run OWASP ZAP full scan in Docker (Phase 2 – e.g. nightly).
# Uses ZAP Automation Framework with Risk and Confidence HTML report.
# Does not fail the run by default; reports are for review.
# Usage: run-full.sh [TARGET_URL]
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
JSON_REPORT="$REPO_ROOT/reports/zap_full_report.json"
HTML_REPORT="$REPO_ROOT/reports/zap_full_report.html"
RISK_REPORT="$REPO_ROOT/reports/zap_full_risk-confidence.html"

echo "ZAP full scan target: $TARGET_URL"
echo "Reports will be saved to: reports/"

# Create automation plan for full scan
cat > "$SCRIPT_DIR/zap-full-plan.yaml" << EOF
---
env:
  contexts:
    - name: full-scan-context
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
      context: full-scan-context
      maxDuration: 30
      maxDepth: 10
      maxChildren: 5000
  - type: spiderAjax
    parameters:
      context: full-scan-context
      maxDuration: 30
      maxCrawlDepth: 10
  - type: passiveScan-wait
    parameters:
      maxDuration: 30
  - type: activeScan
    parameters:
      context: full-scan-context
      policy: Default Policy
      maxRuleDuration: 10
      maxScanDuration: 60
  - type: report
    parameters:
      template: traditional-json
      reportDir: /zap/wrk/reports
      reportFile: zap_full_report
  - type: report
    parameters:
      template: risk-confidence-html
      reportDir: /zap/wrk/reports
      reportFile: zap_full_risk-confidence
EOF

# Run ZAP with automation framework
docker run --rm \
  -v "$REPO_ROOT:/zap/wrk:rw" \
  -w /zap/wrk \
  "$ZAP_IMAGE" \
  zap.sh -cmd -autorun "/zap/wrk/security/zap/zap-full-plan.yaml" 2>&1 | tee zap-full.out

echo "ZAP full scan finished."
echo ""
echo "Reports generated in reports/:"
echo "  - zap_full_report.json (JSON)"
echo "  - zap_full_risk-confidence.html (Risk & Confidence view)"
