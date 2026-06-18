#!/usr/bin/env bash
# 85-install-logrotate.sh — install the MPOS log retention policy.
# See deploy-bundle/logrotate/blakestream-mpos for the installed rules.
set -euo pipefail
say() { printf '\033[1;33m   %s\033[0m\n' "$*"; }

MPOS_REPO="${MPOS_UPDATE_REPO_ROOT:-/root/Blakestream-MPOS}"
INSTALL_ROOT="${MPOS_INSTALL_ROOT:-/opt/blakestream-mpos}"
LOG_ROOT="${MPOS_LOG_ROOT:-/var/log/blakestream-mpos}"

say "installing /etc/logrotate.d/blakestream-mpos"
sed \
    -e "s#/var/log/blakestream-mpos#${LOG_ROOT%/}#g" \
    -e "s#/opt/blakestream-mpos#${INSTALL_ROOT%/}#g" \
    "${MPOS_REPO}/deploy-bundle/logrotate/blakestream-mpos" \
    > /tmp/blakestream-mpos.logrotate
install -m 644 -o root -g root /tmp/blakestream-mpos.logrotate /etc/logrotate.d/blakestream-mpos
rm -f /tmp/blakestream-mpos.logrotate

# Validate via dry-run so a typo doesn't ship.
say "validating with logrotate --debug"
if ! logrotate --debug /etc/logrotate.d/blakestream-mpos >/tmp/logrotate-debug.out 2>&1; then
    echo "logrotate validation failed:" >&2
    cat /tmp/logrotate-debug.out >&2
    exit 1
fi

say "step 85 done — logrotate policy live"
