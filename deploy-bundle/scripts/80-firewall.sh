#!/usr/bin/env bash
# Open public testnet pool ports. Daemon RPC remains loopback-only.
set -euo pipefail

say() { printf '\033[1;33m   %s\033[0m\n' "$*"; }
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib-apt.sh"

if ! command -v ufw >/dev/null 2>&1; then
    say "ufw missing - installing"
    wait_for_apt_locks
    apt-get update -y >/dev/null 2>&1 || true
    wait_for_apt_locks
    DEBIAN_FRONTEND=noninteractive apt-get install -y ufw >/dev/null 2>&1
fi

SSH_PORT="${MPOS_SSH_PORT:-22}"
HTTP_PORT="${MPOS_HTTP_PORT:-80}"
STRATUM_PORT="${MPOS_STRATUM_PORT:-3334}"

say "ufw rules"
ufw allow "${SSH_PORT}/tcp" comment 'ssh' || true
ufw allow "${HTTP_PORT}/tcp" comment 'mpos web' || true
ufw allow "${STRATUM_PORT}/tcp" comment 'stratum' || true

ufw --force enable >/dev/null 2>&1 || true
say "ufw status:"
ufw status numbered | head -25
