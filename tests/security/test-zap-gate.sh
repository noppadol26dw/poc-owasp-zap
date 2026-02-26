#!/usr/bin/env bash
# Test that ZAP baseline gate fails on HIGH/CRITICAL (riskcode 3 or 4).
# DevSecOps TDD: verify security gate logic before relying on it in CI.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES="$SCRIPT_DIR/fixtures"

count_high_critical() {
  local report="$1"
  python3 -c "
import json, sys
try:
    with open('$report') as f:
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
"
}

echo "Test 1: Report with HIGH should yield count >= 1"
COUNT=$(count_high_critical "$FIXTURES/zap_report_high.json")
if [ "${COUNT:-0}" -lt 1 ]; then
  echo "FAIL: expected HIGH count >= 1, got $COUNT"
  exit 1
fi
echo "  OK: count=$COUNT"

echo "Test 2: Clean report should yield HIGH/CRITICAL count 0"
COUNT=$(count_high_critical "$FIXTURES/zap_report_clean.json")
if [ "${COUNT:-0}" -gt 0 ]; then
  echo "FAIL: expected HIGH/CRITICAL count 0, got $COUNT"
  exit 1
fi
echo "  OK: count=$COUNT"

echo ""
echo "ZAP gate tests passed."
exit 0
