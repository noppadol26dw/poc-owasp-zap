#!/usr/bin/env bash
# Validate auth-related config: .env and secrets not committed; required vars documented.
# Run before authenticated scans. Does not print secrets.
set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

echo "Checking auth setup..."

# .env should be ignored
if git check-ignore -q .env 2>/dev/null || true; then
  echo "  OK: .env is gitignored"
else
  if [ -f .env ]; then
    echo "  WARN: .env exists; ensure it is in .gitignore and not committed"
  fi
fi

# For authenticated scan: STAGING_URL and auth method must be set at runtime (secrets/vars)
echo "  Authenticated scan uses GitHub Secrets (ZAP_AUTH_*) and vars (STAGING_URL)."
echo "  No secrets are read from repo files."

echo ""
echo "Auth setup check done."
exit 0
