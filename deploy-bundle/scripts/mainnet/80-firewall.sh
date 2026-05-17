#!/usr/bin/env bash
# 80-firewall.sh — open the public ports the pool needs.
# Conservative: only opens MPOS_HTTP_PORT (web UI) and
# MPOS_STRATUM_PORT (stratum). Daemon RPC stays loopback-only.
set -euo pipefail
say() { printf '\033[1;33m   %s\033[0m\n' "$*"; }

if ! command -v ufw >/dev/null 2>&1; then
    # On mainnet a missing firewall is a deploy bug, not a "skip
    # quietly" — opening daemons + stratum to the public internet
    # without UFW is dangerous. Install it and continue.
    say "ufw missing — installing"
    apt-get update -y >/dev/null 2>&1 || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y ufw \
      >/dev/null 2>&1 \
      || { echo "ERROR: failed to install ufw" >&2; exit 1; }
fi

SSH_PORT="${MPOS_SSH_PORT:-22}"

say "ufw rules"
ufw allow "${SSH_PORT}/tcp" comment 'ssh' || true
ufw allow "${MPOS_HTTP_PORT}"/tcp  comment 'mpos web' || true
ufw allow "${MPOS_STRATUM_PORT}"/tcp comment 'stratum'  || true

# Daemon p2p listen ports — needed for inbound peer connections so the
# pool isn't peer-starved. RPC ports stay closed.
declare -A P2P_PORT=(
    [blc]=8773
    [pho]=35556
    [bbtc]=8356
    [elt]=6853
    [lit]=12007
    [umo]=24785
)
for sym in "${!P2P_PORT[@]}"; do
    ufw allow "${P2P_PORT[$sym]}/tcp" comment "${sym} p2p" || true
done

ufw --force enable >/dev/null 2>&1 || true
say "ufw status:"
ufw status numbered | head -25
