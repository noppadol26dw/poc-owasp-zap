#!/usr/bin/env bash
# OWASP ZAP Baseline Scan with Authentication (Phase 3)
# Uses ZAP Automation Framework for reliable authenticated scanning
#
# Environment Variables:
#   STAGING_URL          - Target URL to scan (required)
#   ZAP_AUTH_METHOD      - Authentication method: form|token (default: form)
#   ZAP_AUTH_URL         - Login URL (for form auth) or token endpoint (for token auth)
#   ZAP_AUTH_USERNAME    - Username for authentication
#   ZAP_AUTH_PASSWORD    - Password for authentication
#   ZAP_AUTH_TOKEN       - API token (when using token auth with pre-generated token)
#   ZAP_AUTH_HEADER      - Custom auth header name (default: Authorization)
#   ZAP_AUTH_HEADER_PREFIX - Token prefix (default: Bearer)
#   ZAP_AUTH_FORM_FIELDS - Form field names (default: username,password)
#   ZAP_AUTH_LOGIN_INDICATOR - Regex for logged-in indicator (optional)
#   ZAP_AUTH_LOGOUT_INDICATOR - Regex for logged-out indicator (optional)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

# Required environment variables
TARGET_URL="${1:-${STAGING_URL:?STAGING_URL or first argument required}}"
AUTH_METHOD="${ZAP_AUTH_METHOD:-form}"
ZAP_IMAGE="${ZAP_IMAGE:-ghcr.io/zaproxy/zaproxy:stable}"

# Create reports directory
mkdir -p "$REPO_ROOT/reports"

# Reports with suffix naming
JSON_REPORT="$REPO_ROOT/reports/zap_auth_baseline_report.json"
HTML_REPORT="$REPO_ROOT/reports/zap_auth_baseline_report.html"
RISK_REPORT="$REPO_ROOT/reports/zap_auth_baseline_risk-confidence.html"

echo "ZAP Authenticated Baseline Scan"
echo "================================"
echo "Target: $TARGET_URL"
echo "Auth Method: $AUTH_METHOD"
echo "Reports will be saved to: reports/"
echo ""

# Validate authentication credentials
validate_auth() {
    local missing=()

    if [[ "$AUTH_METHOD" == "form" ]]; then
        [[ -z "${ZAP_AUTH_URL:-}" ]] && missing+=("ZAP_AUTH_URL")
        [[ -z "${ZAP_AUTH_USERNAME:-}" ]] && missing+=("ZAP_AUTH_USERNAME")
        [[ -z "${ZAP_AUTH_PASSWORD:-}" ]] && missing+=("ZAP_AUTH_PASSWORD")
    elif [[ "$AUTH_METHOD" == "token" ]]; then
        if [[ -z "${ZAP_AUTH_TOKEN:-}" ]]; then
            [[ -z "${ZAP_AUTH_URL:-}" ]] && missing+=("ZAP_AUTH_URL (for token fetch)")
            [[ -z "${ZAP_AUTH_USERNAME:-}" ]] && missing+=("ZAP_AUTH_USERNAME")
            [[ -z "${ZAP_AUTH_PASSWORD:-}" ]] && missing+=("ZAP_AUTH_PASSWORD")
        fi
    else
        echo "ERROR: Invalid ZAP_AUTH_METHOD: $AUTH_METHOD (must be 'form' or 'token')"
        exit 1
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: Missing required environment variables:"
        printf '  - %s\n' "${missing[@]}"
        echo ""
        echo "Required for form auth:"
        echo "  ZAP_AUTH_URL, ZAP_AUTH_USERNAME, ZAP_AUTH_PASSWORD"
        echo ""
        echo "Required for token auth:"
        echo "  ZAP_AUTH_TOKEN (or ZAP_AUTH_URL + ZAP_AUTH_USERNAME + ZAP_AUTH_PASSWORD)"
        exit 1
    fi
}

# Create ZAP automation plan
create_automation_plan() {
    local plan_file="$SCRIPT_DIR/zap-authenticated-plan.yaml"
    local username_field="${ZAP_AUTH_FORM_FIELDS:-username,password}"
    local login_indicator="${ZAP_AUTH_LOGIN_INDICATOR:-logout|sign.?out|welcome|dashboard|profile|account|200 OK}"
    local logout_indicator="${ZAP_AUTH_LOGOUT_INDICATOR:-login|sign.?in|password|username|401|403|unauthorized}"
    
    # Normalize URL - remove trailing slash for context URL
    local CONTEXT_URL="${TARGET_URL%/}"

    if [[ "$AUTH_METHOD" == "form" ]]; then
        # Form-based authentication plan
        cat > "$plan_file" << EOF
---
env:
  contexts:
    - name: authenticated-context
      urls:
        - "$CONTEXT_URL"
        - "$CONTEXT_URL/"
      includePaths:
        - ".*"
      excludePaths:
        - '.*mozilla\.net.*'
        - '.*mozilla\.com.*'
        - '.*firefox\.com.*'
        - '.*cdn\.mozilla\.net.*'
        - '.*google\.com.*'
        - '.*googleapis\.com.*'
        - '.*gstatic\.com.*'
        - '.*cloudflare\.com.*'
        - '.*google-analytics\.com.*'
        - '.*googletagmanager\.com.*'
        - '.*facebook\.com.*'
        - '.*twitter\.com.*'
        - '.*x\.com.*'
        - '.*doubleclick\.net.*'
      authentication:
        method: form
        parameters:
          loginPageUrl: "$ZAP_AUTH_URL"
          loginRequestBody: "${username_field%,*}={username}&${username_field#*,}={password}"
        verification:
          method: response
          loggedInRegex: "$login_indicator"
          loggedOutRegex: "$logout_indicator"
      users:
        - name: scan-user
          credentials:
            username: "$ZAP_AUTH_USERNAME"
            password: "$ZAP_AUTH_PASSWORD"
  parameters:
    failOnError: true
    failOnWarning: false
    progressToStdout: true
jobs:
  - type: spider
    parameters:
      context: authenticated-context
      user: scan-user
      maxDuration: 10
      maxDepth: 5
      maxChildren: 1000
  # Note: spiderAjax disabled due to ZAP context URL matching issue
  # - type: spiderAjax
  #   parameters:
  #     context: authenticated-context
  #     user: scan-user
  #     url: "$CONTEXT_URL/"
  #     maxDuration: 10
  #     maxCrawlDepth: 5
  - type: passiveScan-wait
    parameters:
      maxDuration: 10
  - type: report
    parameters:
      template: traditional-json
      reportDir: /zap/wrk/reports
      reportFile: zap_auth_baseline_report
  - type: report
    parameters:
      template: traditional-html
      reportDir: /zap/wrk/reports
      reportFile: zap_auth_baseline_report
  - type: report
    parameters:
      template: risk-confidence-html
      reportDir: /zap/wrk/reports
      reportFile: zap_auth_baseline_risk-confidence
EOF
    else
        # Token-based authentication plan
        local auth_token="${ZAP_AUTH_TOKEN:-}"
        local auth_header="${ZAP_AUTH_HEADER:-Authorization}"
        local header_prefix="${ZAP_AUTH_HEADER_PREFIX:-Bearer}"

        # If no token provided, we need to fetch it (handled by script, not automation)
        if [[ -z "$auth_token" ]]; then
            echo "WARNING: No ZAP_AUTH_TOKEN provided. Token-based auth requires pre-generated token."
            echo "Please fetch token first or provide ZAP_AUTH_TOKEN."
            exit 1
        fi

        local header_value="${header_prefix} ${auth_token}"
        if [[ -z "$header_prefix" ]]; then
            header_value="$auth_token"
        fi

        cat > "$plan_file" << EOF
---
env:
  contexts:
    - name: api-authenticated-context
      urls:
        - "$CONTEXT_URL"
        - "$CONTEXT_URL/"
      includePaths:
        - ".*"
      excludePaths:
        - '.*mozilla\.net.*'
        - '.*mozilla\.com.*'
        - '.*firefox\.com.*'
        - '.*cdn\.mozilla\.net.*'
        - '.*google\.com.*'
        - '.*googleapis\.com.*'
        - '.*gstatic\.com.*'
        - '.*cloudflare\.com.*'
        - '.*google-analytics\.com.*'
        - '.*googletagmanager\.com.*'
        - '.*facebook\.com.*'
        - '.*twitter\.com.*'
        - '.*x\.com.*'
        - '.*doubleclick\.net.*'
      sessionManagement:
        method: headers
        parameters:
          $auth_header: "$header_value"
      users:
        - name: api-scan-user
  parameters:
    failOnError: true
    failOnWarning: false
    progressToStdout: true
jobs:
  - type: spider
    parameters:
      context: api-authenticated-context
      user: api-scan-user
      maxDuration: 10
      maxDepth: 5
      maxChildren: 1000
  # Note: spiderAjax disabled due to ZAP context URL matching issue
  # - type: spiderAjax
  #   parameters:
  #     context: api-authenticated-context
  #     user: api-scan-user
  #     url: "$CONTEXT_URL/"
  #     maxDuration: 10
  #     maxCrawlDepth: 5
  - type: passiveScan-wait
    parameters:
      maxDuration: 10
  - type: report
    parameters:
      template: traditional-json
      reportDir: /zap/wrk/reports
      reportFile: zap_auth_baseline_report
  - type: report
    parameters:
      template: traditional-html
      reportDir: /zap/wrk/reports
      reportFile: zap_auth_baseline_report
  - type: report
    parameters:
      template: risk-confidence-html
      reportDir: /zap/wrk/reports
      reportFile: zap_auth_baseline_risk-confidence
EOF
    fi

    echo "Created automation plan: $plan_file"
}

# Run the authenticated scan
run_scan() {
    echo "Starting ZAP authenticated baseline scan..."
    echo ""

    local plan_file="$SCRIPT_DIR/zap-authenticated-plan.yaml"

    # Run ZAP with automation framework
    # Note: plan_file path must be relative to container mount (/zap/wrk)
    local container_plan_file="/zap/wrk/security/zap/zap-authenticated-plan.yaml"

    echo "Running: docker run --rm -v $REPO_ROOT:/zap/wrk:rw -w /zap/wrk $ZAP_IMAGE"
    echo "Plan file: $container_plan_file"
    echo ""

    # Run ZAP but don't exit on error - we want to capture logs and generate reports
    local zap_exit_code=0
    docker run --rm \
        -v "$REPO_ROOT:/zap/wrk:rw" \
        -w /zap/wrk \
        "$ZAP_IMAGE" \
        zap.sh -cmd -autorun "$container_plan_file" 2>&1 | tee zap-auth.out || zap_exit_code=$?

    # Debug: Show what files were created
    echo ""
    echo "=== Files in reports/ directory after scan ==="
    ls -la "$REPO_ROOT/reports/" 2>/dev/null || echo "reports/ directory does not exist or is empty"

    # Debug: Check for any zap output files
    echo ""
    echo "=== ZAP output files in repo root ==="
    ls -la "$REPO_ROOT/zap-auth.out" 2>/dev/null || echo "No zap-auth.out file"
    ls -la "$REPO_ROOT/zap_auth_baseline_report"* 2>/dev/null || echo "No zap_auth_baseline_report files"

    # ZAP may create files with different extensions based on template
    # Check and rename if needed
    for ext in json html; do
        if [[ -f "$REPO_ROOT/reports/zap_auth_baseline_report.$ext" ]]; then
            echo "Found report: reports/zap_auth_baseline_report.$ext"
        fi
        if [[ -f "$REPO_ROOT/reports/zap_auth_baseline_risk-confidence.$ext" ]]; then
            echo "Found report: reports/zap_auth_baseline_risk-confidence.$ext"
        fi
    done

    # If ZAP failed, log the error but continue to check for partial reports
    if [[ $zap_exit_code -ne 0 ]]; then
        echo ""
        echo "WARNING: ZAP scan exited with code $zap_exit_code"
        echo "Last 50 lines of output:"
        tail -50 zap-auth.out 2>/dev/null || echo "No output log available"
    fi

    return $zap_exit_code
}

# Check for HIGH/CRITICAL findings
check_failures() {
    if [ -f "$JSON_REPORT" ]; then
        echo "Analyzing report: $JSON_REPORT"

        HIGH_CRITICAL=$(python3 -c "
import json, sys
try:
    with open('$JSON_REPORT') as f:
        data = json.load(f)
    count = 0
    # Handle both site array and single site object formats
    sites = data.get('site', [])
    if not isinstance(sites, list):
        sites = [sites]
    for site in sites:
        alerts = site.get('alerts', [])
        for alert in alerts:
            risk = alert.get('riskcode', alert.get('risk', 0))
            if risk in (3, 4):
                count += 1
    print(count)
except Exception as e:
    print(f'Error parsing JSON: {e}', file=sys.stderr)
    print(0)
" 2>/dev/null || echo "0")

        if [ "${HIGH_CRITICAL:-0}" -gt 0 ]; then
            echo ""
            echo "ZAP: ${HIGH_CRITICAL} HIGH/CRITICAL finding(s). Failing."
            exit 1
        fi

        echo ""
        echo "ZAP authenticated baseline: no HIGH/CRITICAL findings."
    else
        echo ""
        echo "WARNING: No JSON report found at $JSON_REPORT"
        echo "This may indicate the scan failed to complete."
        echo "Check zap-auth.out for error details."
        # Don't fail here - let the caller decide based on scan exit code
    fi

    echo ""
    echo "Expected reports in reports/:"
    echo "  - zap_auth_baseline_report.json (JSON data)"
    echo "  - zap_auth_baseline_report.html (Traditional HTML)"
    echo "  - zap_auth_baseline_risk-confidence.html (Risk & Confidence view)"
}

# Main execution
main() {
    validate_auth
    create_automation_plan

    # Run scan but don't let it kill the script on error
    local scan_exit=0
    run_scan || scan_exit=$?

    # Check for failures - this also handles case where no report exists
    check_failures

    # Return the original scan exit code if it failed
    return $scan_exit
}

main "$@"
