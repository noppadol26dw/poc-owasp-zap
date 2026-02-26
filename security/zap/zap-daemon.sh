#!/usr/bin/env bash
# Phase 5 - ZAP Daemon management script
# Usage: zap-daemon.sh [start|stop|status|logs|restart]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

COMPOSE_FILE="${REPO_ROOT}/docker-compose.yml"
SERVICE_NAME="zap-daemon"

show_help() {
    echo "ZAP Daemon Manager - Phase 5"
    echo "============================"
    echo ""
    echo "Usage: zap-daemon.sh [command]"
    echo ""
    echo "Commands:"
    echo "  start       Start ZAP daemon (docker-compose up)"
    echo "  stop        Stop ZAP daemon (docker-compose down)"
    echo "  restart     Restart ZAP daemon"
    echo "  status      Check if ZAP is running"
    echo "  logs        View ZAP daemon logs"
    echo "  api-test    Test API connectivity"
    echo "  scan        Run a quick scan (shorthand for run-zap-api-scan.sh)"
    echo ""
    echo "Environment Variables:"
    echo "  ZAP_API_KEY      API key for ZAP (default: changeme)"
    echo "  STAGING_URL      Default target URL"
    echo ""
    echo "Examples:"
    echo "  ./security/zap/zap-daemon.sh start"
    echo "  ./security/zap/zap-daemon.sh status"
    echo "  ./security/zap/zap-daemon.sh scan https://example.com"
    echo ""
}

cmd_start() {
    echo "Starting ZAP daemon..."
    docker-compose -f "$COMPOSE_FILE" up -d "$SERVICE_NAME"
    
    echo ""
    echo "Waiting for ZAP to be ready..."
    for i in {1..30}; do
        if curl -s http://localhost:8080 > /dev/null 2>&1; then
            echo "✓ ZAP is ready!"
            echo ""
            echo "ZAP Proxy:    http://localhost:8080"
            echo "ZAP API:      http://localhost:8090"
            echo "API Key:      ${ZAP_API_KEY:-changeme}"
            echo ""
            echo "To run a scan:"
            echo "  ./security/zap/run-zap-api-scan.sh"
            return 0
        fi
        echo -ne "  Waiting... ($i/30)\r"
        sleep 2
    done
    
    echo "ERROR: ZAP failed to start within 60 seconds"
    echo "Check logs: ./security/zap/zap-daemon.sh logs"
    return 1
}

cmd_stop() {
    echo "Stopping ZAP daemon..."
    docker-compose -f "$COMPOSE_FILE" down
    echo "✓ ZAP daemon stopped"
}

cmd_restart() {
    cmd_stop
    sleep 2
    cmd_start
}

cmd_status() {
    if docker-compose -f "$COMPOSE_FILE" ps | grep -q "zap-daemon"; then
        echo "✓ ZAP daemon is running"
        echo ""
        docker-compose -f "$COMPOSE_FILE" ps
        echo ""
        
        # Check API connectivity
        if curl -s http://localhost:8090 > /dev/null 2>&1; then
            echo "✓ ZAP API is accessible"
        else
            echo "⚠ ZAP container running but API not responding"
        fi
    else
        echo "✗ ZAP daemon is not running"
        echo ""
        echo "Start with: ./security/zap/zap-daemon.sh start"
    fi
}

cmd_logs() {
    docker-compose -f "$COMPOSE_FILE" logs -f "$SERVICE_NAME"
}

cmd_api_test() {
    echo "Testing ZAP API connectivity..."
    echo ""
    
    ZAP_API_KEY="${ZAP_API_KEY:-changeme}"
    
    # Test version endpoint
    echo "1. Testing version endpoint..."
    if curl -s "http://localhost:8090/JSON/core/view/version/?apikey=${ZAP_API_KEY}" | grep -q "version"; then
        echo "   ✓ Version API working"
        curl -s "http://localhost:8090/JSON/core/view/version/?apikey=${ZAP_API_KEY}" | python3 -m json.tool 2>/dev/null | grep version || true
    else
        echo "   ✗ Version API failed"
    fi
    
    echo ""
    echo "2. Testing alerts endpoint..."
    if curl -s "http://localhost:8090/JSON/core/view/alerts/?apikey=${ZAP_API_KEY}" | grep -q "alerts"; then
        echo "   ✓ Alerts API working"
    else
        echo "   ✗ Alerts API failed"
    fi
    
    echo ""
    echo "3. Testing spider endpoint..."
    if curl -s "http://localhost:8090/JSON/spider/view/status/?apikey=${ZAP_API_KEY}" | grep -q "status"; then
        echo "   ✓ Spider API working"
    else
        echo "   ✗ Spider API failed"
    fi
}

cmd_scan() {
    local target="${1:-${STAGING_URL:-}}"
    if [[ -z "$target" ]]; then
        echo "ERROR: No target URL specified"
        echo "Usage: zap-daemon.sh scan [TARGET_URL]"
        exit 1
    fi
    
    # Check if running
    if ! curl -s http://localhost:8080 > /dev/null 2>&1; then
        echo "ZAP daemon not running. Starting..."
        cmd_start
        sleep 5
    fi
    
    # Run scan
    "${SCRIPT_DIR}/run-zap-api-scan.sh" "$target"
}

# Main
case "${1:-}" in
    start)
        cmd_start
        ;;
    stop)
        cmd_stop
        ;;
    restart)
        cmd_restart
        ;;
    status)
        cmd_status
        ;;
    logs)
        cmd_logs
        ;;
    api-test)
        cmd_api_test
        ;;
    scan)
        shift
        cmd_scan "$@"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        show_help
        exit 1
        ;;
esac
