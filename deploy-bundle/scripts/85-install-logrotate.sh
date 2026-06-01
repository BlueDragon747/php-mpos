#!/usr/bin/env bash
# Install the MPOS log retention policy for testnet deploys.
set -euo pipefail
say() { printf '\033[1;33m   %s\033[0m\n' "$*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="${MPOS_DEPLOY_BUNDLE:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
POLICY_SRC="${BUNDLE_DIR}/logrotate/blakestream-mpos"
POLICY_DST="/etc/logrotate.d/blakestream-mpos"

[ -r "$POLICY_SRC" ] || { echo "missing logrotate policy: $POLICY_SRC" >&2; exit 1; }
command -v logrotate >/dev/null 2>&1 || { echo "logrotate is not installed" >&2; exit 1; }

say "installing ${POLICY_DST}"
install -m 644 -o root -g root "$POLICY_SRC" "$POLICY_DST"

say "validating with logrotate --debug"
if ! logrotate --debug "$POLICY_DST" >/tmp/blakestream-mpos-logrotate-debug.out 2>&1; then
    echo "logrotate validation failed:" >&2
    cat /tmp/blakestream-mpos-logrotate-debug.out >&2
    exit 1
fi

say "logrotate policy live"
