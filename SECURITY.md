# Security (DevSecOps)

This project uses OWASP ZAP for DAST (Dynamic Application Security Testing) in CI/CD. This file summarizes security gates and practices.

## Security Gates

| Gate | When | Action |
|------|------|--------|
| **ZAP Baseline** | Push/PR to `main` | Fails CI if HIGH or CRITICAL findings. Shift-left DAST. |
| **ZAP Full** | Nightly | Report only; no fail. Deep scan for review. |
| **ZAP Authenticated** | Nightly / manual | Scans protected routes; optional fail on HIGH. |
| **ZAP API Daemon** | Manual / post-deploy | On-demand scan via API. |

## Practices

- **Least privilege**: Workflows use minimal `permissions` (e.g. `contents: read`); `issues: write` only where issues are created.
- **Secrets**: Auth credentials and tokens live in GitHub Secrets; never in code or logs.
- **Artifacts**: ZAP reports are uploaded as workflow artifacts with correct paths (`reports/`).

## Checklist (before release)

- [ ] `STAGING_URL` and auth secrets set in repo variables/secrets.
- [ ] Baseline gate tests pass: `./tests/security/test-zap-gate.sh`
- [ ] No HIGH/CRITICAL in baseline scan for the target app.
- [ ] ZAP image pinned (e.g. by digest) if you need supply-chain hardening.

## Running security tests

```bash
./tests/security/test-zap-gate.sh
```

These tests verify that the ZAP report parser correctly counts HIGH/CRITICAL and would fail the pipeline when appropriate.
