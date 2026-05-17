#!/usr/bin/env bash
# Final health check. Exits 0 only if the whole stack is responsive.
set -uo pipefail

ok=1
fail() { ok=0; printf '\033[1;31m  FAIL: %s\033[0m\n' "$*"; }
pass() { printf '\033[1;32m  OK:   %s\033[0m\n' "$*"; }

say() { printf '\033[1;33m   %s\033[0m\n' "$*"; }

NODE_RPC_USER="${MPOS_NODE_RPC_USER:-blakestream}"
NODE_RPC_PASS="${MPOS_NODE_RPC_PASS:-blakestream-testnet}"

say "daemon RPCs"
for entry in \
    "blakecoin:29332" \
    "blakebitcoin:29112" \
    "electron:26852" \
    "lithium:32004" \
    "photon:28998" \
    "universalmolecule:29738"; do
    name=${entry%:*}
    port=${entry#*:}
    h=$(curl -fsSL --max-time 3 -u "${NODE_RPC_USER}:${NODE_RPC_PASS}" \
        --data '{"jsonrpc":"1.0","id":"verify","method":"getblockcount"}' \
        -H 'content-type: text/plain' "http://127.0.0.1:${port}/" 2>/dev/null \
        | sed -n 's/.*"result":\([0-9]*\).*/\1/p')
    if [ -n "$h" ]; then
        pass "${name} height ${h}"
    else
        fail "${name} RPC at :${port} unreachable"
    fi
done

say "pool services"
systemctl is-active --quiet blakestream-mpos-eloipool.service && pass "eloipool active" || fail "eloipool not active"
systemctl is-active --quiet blakestream-mpos-mergeminer.service && pass "mergeminer active" || fail "mergeminer not active"
# cronjobs-py is opt-in — only verify it when the operator has activated
# it. Otherwise the production scheduler is the PHP cronjob set, which
# this verify script does not currently exercise (PHP cronjobs are
# triggered ad-hoc / via system cron, not as a long-lived service).
if [ "${MPOS_PYTHON_CRONJOBS_ACTIVE:-0}" = "1" ]; then
    systemctl is-active --quiet blakestream-mpos-cronjobs.service && pass "cronjobs-py active" || fail "cronjobs-py not active"
else
    pass "cronjobs-py installed but disabled (PHP cron is authoritative)"
fi

say "ports"
for entry in "stratum:3334" "mmproxy:19335" "pool-jsonrpc:19334" "http:${MPOS_HTTP_PORT}"; do
    name=${entry%:*}; port=${entry#*:}
    if ss -tln | awk '{print $4}' | grep -qE ":(${port})\$"; then
        pass "${name} listening on :${port}"
    else
        fail "nothing listening on :${port}"
    fi
done

say "MPOS HTTP"
HOST_IP=$(hostname -I | awk '{print $1}')
status=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:${MPOS_HTTP_PORT}/")
case "$status" in
    200|301|302|303) pass "MPOS UI returns ${status}" ;;
    *) fail "MPOS UI returned HTTP ${status}" ;;
esac

say "MPOS DB"
if mariadb -N -B -e "USE \`${MPOS_DB_NAME}\`; SELECT COUNT(*) FROM accounts;" 2>/dev/null | grep -q '^[0-9]'; then
    pass "MPOS DB reachable"
else
    fail "MPOS DB query failed"
fi

say "disk stats sudo helper"
if sudo -u www-data sudo -n /usr/local/sbin/blakestream-mpos-disk-stats >/dev/null 2>&1; then
    pass "www-data can run the allowlisted disk stats helper"
else
    fail "www-data cannot run /usr/local/sbin/blakestream-mpos-disk-stats via sudo"
fi

if [ "$ok" = "1" ]; then
    printf '\033[1;32m\n=== verify: ALL CHECKS PASSED ===\033[0m\n'
    exit 0
else
    printf '\033[1;31m\n=== verify: FAILURES ABOVE ===\033[0m\n'
    exit 1
fi
