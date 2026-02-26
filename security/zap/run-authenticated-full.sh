#!/usr/bin/env bash
# OWASP ZAP Full Scan with Authentication (Phase 3)
# Uses ZAP Automation Framework for reliable authenticated scanning
#
# Environment Variables:
#   STAGING_URL          - Target URL to scan (required)
#   ZAP_AUTH_METHOD      - Authentication method: form|token (default: form)
#   ZAP_AUTH_URL         - Login URL (for form auth) or token endpoint (for token auth)
#   ZAP_AUTH_USERNAME    - Username for authentication
#   ZAP_AUTH_PASSWORD    - Password for authentication
#   ZAP_AUTH_TOKEN       - API token (when using token auth)
#   ZAP_AUTH_HEADER      - Custom auth header name (default: Authorization)
#   ZAP_AUTH_HEADER_PREFIX - Token prefix (default: Bearer)
#   ZAP_AUTH_FORM_FIELDS - Form field names (default: username,password)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

TARGET_URL="${1:-${STAGING_URL:?STAGING_URL or first argument required}}"
AUTH_METHOD="${ZAP_AUTH_METHOD:-form}"
ZAP_IMAGE="${ZAP_IMAGE:-ghcr.io/zaproxy/zaproxy:stable}"

# Create reports directory
mkdir -p "$REPO_ROOT/reports"

# Reports with suffix naming
JSON_REPORT="$REPO_ROOT/reports/zap_auth_full_report.json"
HTML_REPORT="$REPO_ROOT/reports/zap_auth_full_report.html"
RISK_REPORT="$REPO_ROOT/reports/zap_auth_full_risk-confidence.html"

echo "ZAP Authenticated Full Scan"
echo "==========================="
echo "Target: $TARGET_URL"
echo "Auth Method: $AUTH_METHOD"
echo "Reports will be saved to: reports/"
echo ""

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
        exit 1
    fi
}

create_automation_plan() {
    local plan_file="$SCRIPT_DIR/zap-auth-full-plan.yaml"
    local username_field="${ZAP_AUTH_FORM_FIELDS:-username,password}"
    local login_indicator="${ZAP_AUTH_LOGIN_INDICATOR:-logout|sign.?out|welcome|dashboard|profile|account|200 OK}"
    local logout_indicator="${ZAP_AUTH_LOGOUT_INDICATOR:-login|sign.?in|password|username|401|403|unauthorized}"
    
    # Normalize URL - remove trailing slash for context URL
    local CONTEXT_URL="${TARGET_URL%/}"

    if [[ "$AUTH_METHOD" == "form" ]]; then
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
      maxDuration: 30
      maxDepth: 10
      maxChildren: 5000
  # Note: spiderAjax disabled due to ZAP context URL matching issue
  # - type: spiderAjax
  #   parameters:
  #     context: authenticated-context
  #     user: scan-user
  #     url: "$CONTEXT_URL/"
  #     maxDuration: 30
  #     maxCrawlDepth: 10
  - type: passiveScan-wait
    parameters:
      maxDuration: 30
  - type: activeScan
    parameters:
      context: authenticated-context
      user: scan-user
      policy: Default Policy
      maxRuleDuration: 10
      maxScanDuration: 60
  - type: report
    parameters:
      template: traditional-json
      reportDir: /zap/wrk/reports
      reportFile: zap_auth_full_report
  - type: report
    parameters:
      template: traditional-html
      reportDir: /zap/wrk/reports
      reportFile: zap_auth_full_report
  - type: report
    parameters:
      template: risk-confidence-html
      reportDir: /zap/wrk/reports
      reportFile: zap_auth_full_risk-confidence
EOF
    else
        local auth_token="${ZAP_AUTH_TOKEN:-}"
        local auth_header="${ZAP_AUTH_HEADER:-Authorization}"
        local header_prefix="${ZAP_AUTH_HEADER_PREFIX:-Bearer}"

        if [[ -z "$auth_token" ]]; then
            echo "WARNING: No ZAP_AUTH_TOKEN provided."
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
      maxDuration: 30
      maxDepth: 10
      maxChildren: 5000
  # Note: spiderAjax disabled due to ZAP context URL matching issue
  # - type: spiderAjax
  #   parameters:
  #     context: api-authenticated-context
  #     user: api-scan-user
  #     url: "$CONTEXT_URL/"
  #     maxDuration: 30
  #     maxCrawlDepth: 10
  - type: passiveScan-wait
    parameters:
      maxDuration: 30
  - type: activeScan
    parameters:
      context: api-authenticated-context
      user: api-scan-user
      policy: Default Policy
      maxRuleDuration: 10
      maxScanDuration: 60
  - type: report
    parameters:
      template: traditional-json
      reportDir: /zap/wrk/reports
      reportFile: zap_auth_full_report
  - type: report
    parameters:
      template: traditional-html
      reportDir: /zap/wrk/reports
      reportFile: zap_auth_full_report
  - type: report
    parameters:
      template: risk-confidence-html
      reportDir: /zap/wrk/reports
      reportFile: zap_auth_full_risk-confidence
EOF
    fi

    echo "Created automation plan: $plan_file"
}

run_scan() {
    echo "Starting ZAP authenticated full scan..."
    echo "This may take 15-30 minutes depending on application size."
    echo ""

    local plan_file="$SCRIPT_DIR/zap-auth-full-plan.yaml"

    # Note: plan_file path must be relative to container mount (/zap/wrk)
    local container_plan_file="/zap/wrk/security/zap/zap-auth-full-plan.yaml"

    docker run --rm \
        -v "$REPO_ROOT:/zap/wrk:rw" \
        -w /zap/wrk \
        "$ZAP_IMAGE" \
        zap.sh -cmd -autorun "$container_plan_file" 2>&1 | tee zap-auth-full.out

    if [[ -f "$REPO_ROOT/zap-auth-full-report.json" ]]; then
        echo "JSON report generated: zap-auth-full-report.json"
    fi
    if [[ -f "$REPO_ROOT/zap-auth-full-report.html" ]]; then
        echo "HTML report generated: zap-auth-full-report.html"
    fi
}

main() {
    validate_auth
    create_automation_plan
    run_scan

    echo ""
echo "ZAP authenticated full scan finished."
echo ""
echo "Reports generated in reports/:"
echo "  - zap_auth_full_report.json (JSON data)"
echo "  - zap_auth_full_report.html (Traditional HTML)"
echo "  - zap_auth_full_risk-confidence.html (Risk & Confidence view)"
}

main "$@"
