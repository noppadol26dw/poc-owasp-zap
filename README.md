# OWASP ZAP CI/CD POC

A comprehensive DevSecOps implementation of OWASP ZAP security scanning in CI/CD pipelines using Docker and GitHub Actions.

## Overview

This project provides automated security scanning using [OWASP ZAP](https://www.zaproxy.org/) (Zed Attack Proxy) integrated into CI/CD workflows. It supports both unauthenticated and authenticated scanning of web applications and APIs.

### Features

- **Baseline Scans**: Fast passive scanning on every PR/push
- **Full Scans**: Deep active scanning on schedule
- **Authenticated Scans**: Scan protected pages with login support
- **API Daemon**: On-demand scanning via REST API
- **Risk & Confidence Reports**: Organized findings by severity and confidence
- **CI/CD Integration**: GitHub Actions and Jenkins support

---

## Quick Start

### Prerequisites

- Docker
- Bash (Linux/macOS/WSL)
- Git

### Local Testing

```bash
# Clone and enter directory
cd /path/to/poc-owasp-zap

# Run baseline scan against public URL
./security/zap/run-baseline.sh https://www.example.com

# View reports
ls -la reports/
open reports/zap_baseline_risk-confidence.html
```

### With Staging URL

```bash
export STAGING_URL=https://your-staging.example.com
./security/zap/run-baseline.sh
```

---

## Project Structure

```
poc-owasp-zap/
├── .github/workflows/          # CI/CD pipelines
│   ├── zap-baseline.yml        # Phase 1: PR/push scans
│   ├── zap-full-nightly.yml    # Phase 2: Scheduled scans
│   ├── zap-authenticated.yml   # Phase 3: Auth scans
│   └── zap-api-daemon.yml      # Phase 5: API daemon
├── security/
│   ├── zap/
│   │   ├── run-baseline.sh           # Baseline scan script
│   │   ├── run-full.sh               # Full scan script
│   │   ├── run-authenticated-baseline.sh  # Auth baseline
│   │   ├── run-authenticated-full.sh      # Auth full scan
│   │   ├── run-zap-api-scan.sh       # API trigger - baseline
│   │   ├── run-zap-api-scan-full.sh  # API trigger - full
│   │   └── zap-daemon.sh             # Daemon manager
│   └── docs/README.md          # Detailed documentation
├── tests/security/             # Validation tests
│   └── test-auth-setup.sh    # Test auth configuration
├── reports/                  # Generated reports (gitignored)
├── docker-compose.yml        # ZAP daemon services
├── .gitignore              # Excludes reports, logs
└── README.md               # This file
```

---

## Project Roadmap

| Phase | Status | Description |
|-------|--------|-------------|
| **Phase 1** | ✅ Done | Baseline scan on PR/push - fails on HIGH/CRITICAL |
| **Phase 2** | ✅ Done | Nightly full scan - reports only, no fail |
| **Phase 3** | ✅ Done | Authenticated scan with form/API token auth |
| **Phase 4** | 🔧 TODO | SARIF export for GitHub Code Scanning |
| **Phase 5** | ✅ Done | ZAP API Daemon - on-demand scanning via REST API |

### Active vs passive scan

| Type | What it does | When we use it |
|------|----------------|----------------|
| **Passive** | Observes traffic and responses only; does not send attack payloads. Finds issues like missing headers, info leakage, passive SSL checks. | Baseline scan (Phase 1) – fast, safe for every PR. |
| **Active** | Sends probes and attack payloads (e.g. SQL injection, XSS) to find vulnerabilities. | Full scan (Phase 2) and authenticated full – scheduled or on-demand, not every commit. |

---

## Phase Details

### Phase 1 - Baseline Scan

Fast passive scan on every code change. Fails CI if HIGH/CRITICAL issues found.

**Usage:**
```bash
./security/zap/run-baseline.sh [TARGET_URL]
```

**Reports:**
- `reports/zap_baseline_report.json`
- `reports/zap_baseline_risk-confidence.html`

**CI/CD:** `.github/workflows/zap-baseline.yml`

---

### Phase 2 - Full Scan

Comprehensive active scan with attack simulation. Runs on schedule.

**Usage:**
```bash
./security/zap/run-full.sh [TARGET_URL]
```

**Reports:**
- `reports/zap_full_report.json`
- `reports/zap_full_risk-confidence.html`

**CI/CD:** `.github/workflows/zap-full-nightly.yml`

---

### Phase 3 - Authenticated Scan

Scan protected pages requiring login.

**Supported Authentication:**
- Form-based (username/password)
- API Token (Bearer, custom headers)

**Environment Variables:**

| Variable | Required | Description |
|----------|----------|-------------|
| `STAGING_URL` | Yes | Target URL to scan |
| `ZAP_AUTH_URL` | For form auth | Login page URL |
| `ZAP_AUTH_USERNAME` | For form auth | Username |
| `ZAP_AUTH_PASSWORD` | For form auth | Password |
| `ZAP_AUTH_METHOD` | Yes | `form` or `token` |
| `ZAP_AUTH_TOKEN` | For token auth | API token value |
| `ZAP_AUTH_HEADER` | No | Header name (default: Authorization) |
| `ZAP_AUTH_HEADER_PREFIX` | No | Prefix (default: Bearer) |

**Usage:**
```bash
# Form-based auth
export STAGING_URL=https://app.example.com
export ZAP_AUTH_URL=https://app.example.com/login
export ZAP_AUTH_USERNAME=user@example.com
export ZAP_AUTH_PASSWORD=secret
export ZAP_AUTH_METHOD=form
./security/zap/run-authenticated-baseline.sh

# Token-based auth
export STAGING_URL=https://api.example.com
export ZAP_AUTH_TOKEN="your-token"
export ZAP_AUTH_METHOD=token
./security/zap/run-authenticated-baseline.sh
```

**Reports:**
- `reports/zap_auth_baseline_report.json`
- `reports/zap_auth_baseline_risk-confidence.html`

> **Note:** AJAX Spider is disabled due to ZAP Automation Framework context URL matching issue. Regular spider works correctly.

---

### Phase 5 - ZAP API Daemon

Run ZAP as a long-running Docker service for on-demand scanning.

**Features:**
- REST API access (port 8090)
- Proxy support (port 8080)
- Trigger scans on-demand
- Post-deployment scanning

**Quick Start:**
```bash
# Start daemon
./security/zap/zap-daemon.sh start

# Or use docker-compose
docker-compose up -d zap-daemon

# Run scan via API
./security/zap/run-zap-api-scan.sh https://target.example.com

# Check status
./security/zap/zap-daemon.sh status

# View logs
./security/zap/zap-daemon.sh logs

# Stop daemon
./security/zap/zap-daemon.sh stop
```

**Access Points:**
- ZAP Proxy: http://localhost:8080
- ZAP API: http://localhost:8090
- API Key: `changeme` (set via `ZAP_API_KEY` env var)

**Docker Compose:**
```bash
# Start
docker-compose up -d zap-daemon

# Scale (multiple instances)
docker-compose up -d --scale zap-daemon=3
```

---

## Reports

All scans generate reports in the `reports/` folder:

| File | Format | Purpose |
|------|--------|---------|
| `zap_<type>_report.json` | JSON | Machine-readable, CI parsing |
| `zap_<type>_risk-confidence.html` | HTML | Human-readable, risk-organized |

**Report Types:**
- `baseline` - Phase 1 scans
- `full` - Phase 2 scans
- `auth_baseline` - Phase 3 baseline
- `auth_full` - Phase 3 full

**Viewing Reports:**
```bash
# macOS
open reports/zap_baseline_risk-confidence.html

# Linux
xdg-open reports/zap_baseline_risk-confidence.html

# Or open file in browser manually
```

---

## CI/CD Integration

### GitHub Actions

All workflows support `workflow_dispatch` for manual triggering.

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `zap-baseline.yml` | Push/PR | Fast security check |
| `zap-full-nightly.yml` | Schedule | Deep security scan |
| `zap-authenticated.yml` | Schedule/Manual | Auth-required scanning |
| `zap-api-daemon.yml` | Manual | On-demand API scanning |

**Setup:**
1. Go to Settings > Secrets and Variables > Actions
2. Add `STAGING_URL` as a variable
3. Add auth credentials as secrets (for Phase 3)

### Manual Trigger

```bash
# Via GitHub CLI
gh workflow run zap-baseline.yml
gh workflow run zap-api-daemon.yml -f target_url=https://staging.example.com
```

---

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `STAGING_URL` | - | Target URL for scans |
| `ZAP_IMAGE` | `ghcr.io/zaproxy/zaproxy:stable` | Docker image |
| `ZAP_API_KEY` | `changeme` | API key for daemon |

### Policy Tuning

Edit `security/zap/zap.conf` to customize scan rules:

```
# Format: ruleId<TAB>ACTION<TAB>message
10021	IGNORE	Known false positive
```

### Security Best Practices

**Never commit sensitive data:**
- `.env` files - Use environment variables or GitHub Secrets
- `.key`, `.pem`, `.p12` files - Certificate and key files
- `secrets.*`, `credentials.*` files - Any credential storage
- ZAP reports in `reports/` - May contain vulnerability details

**Credential handling:**
- Use GitHub Secrets for `ZAP_AUTH_PASSWORD`, `ZAP_AUTH_TOKEN`
- Use GitHub Variables for non-sensitive config like `STAGING_URL`
- Never hardcode credentials in scripts or documentation

The `.gitignore` is configured to exclude these automatically.

## Testing

Validate your setup:

```bash
# Run security gate tests (ZAP fail-on-high logic)
./tests/security/test-zap-gate.sh

# Auth setup check (secrets not in repo)
./tests/security/test-auth-setup.sh

# Test baseline scan against a URL
./security/zap/run-baseline.sh https://example.com
```

See [SECURITY.md](SECURITY.md) for security gates and checklist.

---

## Archive

Old Python-based authentication scripts in `archive/` (gitignored):
- `form-auth.py` - Old form auth (replaced by YAML automation plans)
- `api-token-auth.py` - Old token auth (replaced by YAML automation plans)
- `authenticated.context` - Old ZAP context file

Kept for reference but not used by current implementation. The `archive/` directory is excluded from version control.

---

## TODO / Future Enhancements

| Feature | Priority | Phase |
|---------|----------|-------|
| SARIF Export | Medium | 4 |
| OpenAPI Import | Medium | - |
| Post-deploy Triggers | Low | - |
| AJAX Spider Re-enable | Low | 3 |
| Custom Scan Policies | Low | - |

---

## References

- [OWASP ZAP](https://www.zaproxy.org/)
- [ZAP Automation Framework](https://www.zaproxy.org/docs/automate/automation-framework/)
- [Risk and Confidence HTML Report](https://www.zaproxy.org/docs/desktop/addons/report-generation/report-risk-confidence/)
- [GitHub Code Scanning](https://docs.github.com/en/code-security/code-scanning)

---

## License

This is a POC (Proof of Concept) project for educational and security testing purposes.
