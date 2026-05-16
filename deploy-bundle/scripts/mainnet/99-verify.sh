#!/usr/bin/env bash
# 99-verify.sh — health check the mainnet pool stack end-to-end.
set -euo pipefail
say() { printf '\033[1;33m   %s\033[0m\n' "$*"; }
pass() { printf '   \033[1;32m[OK]\033[0m   %s\n' "$*"; }
fail() { printf '   \033[1;31m[FAIL]\033[0m %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT+1)); }
FAIL_COUNT=0

say "daemon RPCs"
declare -A RPC_PORT=(
    [blc]=8772 [pho]=8984 [bbtc]=8243 [elt]=6852 [lit]=12345 [umo]=19738
)
for sym in blc pho bbtc elt lit umo; do
    port="${RPC_PORT[$sym]}"
    h=$(curl -fsSL --max-time 5 -u "${MPOS_NODE_RPC_USER}:${MPOS_NODE_RPC_PASS}" \
        --data '{"jsonrpc":"1.0","id":"verify","method":"getblockcount"}' \
        -H 'content-type: text/plain' "http://127.0.0.1:${port}/" 2>/dev/null \
        | sed -n 's/.*"result":\([0-9]*\).*/\1/p')
    if [ -n "$h" ]; then
        pass "${sym} height ${h}"
    else
        fail "${sym} RPC at :${port} unreachable"
    fi
done

say "pool services"
for unit in blakestream-mpos-eloipool blakestream-mpos-mergeminer blakestream-mpos-cronjobs; do
    if systemctl is-active --quiet "${unit}.service"; then
        pass "${unit} active"
    else
        fail "${unit} not active"
    fi
done

say "ports listening"
for entry in "stratum:${MPOS_STRATUM_PORT}" "mmproxy:19335" "pool-jsonrpc:19334" "http:${MPOS_HTTP_PORT}"; do
    name=${entry%:*}; port=${entry#*:}
    if ss -tln | awk '{print $4}' | grep -qE ":(${port})\$"; then
        pass "${name} listening on :${port}"
    else
        fail "nothing listening on :${port}"
    fi
done

say "backup policy"
BACKUPS_ENABLED=$(mariadb -BNe \
    "SELECT value FROM settings WHERE name='backups_enabled' LIMIT 1;" \
    -u "${MPOS_DB_USER}" "-p${MPOS_DB_PASS}" "${MPOS_DB_NAME}" 2>/dev/null \
    || true)
BACKUPS_ENABLED_NORM=$(printf '%s' "${BACKUPS_ENABLED:-1}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
if [ -n "${BACKUPS_ENABLED}" ]; then
    pass "settings.backups_enabled=${BACKUPS_ENABLED}"
else
    fail "settings.backups_enabled missing"
fi
if systemctl is-enabled --quiet blakestream-mpos-backup.timer; then
    pass "backup timer enabled"
else
    fail "backup timer not enabled"
fi
if systemctl is-active --quiet blakestream-mpos-backup.timer; then
    pass "backup timer active"
else
    fail "backup timer not active"
fi
if [[ "${BACKUPS_ENABLED_NORM:-1}" =~ ^(0|false|no|off|disabled)$ ]]; then
    pass "backup artifact check skipped; backups disabled by operator"
elif [ -s /var/backups/blakestream-mpos/latest.tar.gz ]; then
    pass "latest backup artifact present"
else
    fail "latest backup artifact missing while backups_enabled=${BACKUPS_ENABLED:-missing}"
fi
BACKUP_STATUS_FILE=/var/log/blakestream-mpos/backup-status.ini
if [ -r "$BACKUP_STATUS_FILE" ]; then
    pass "backup status manifest readable"
    BACKUP_STATUS=$(sed -n 's/^status="\([^"]*\)".*/\1/p' "$BACKUP_STATUS_FILE" | head -1)
    BACKUP_WALLETS=$(sed -n 's/^wallets="\([^"]*\)".*/\1/p' "$BACKUP_STATUS_FILE" | head -1)
else
    fail "backup status manifest missing"
    BACKUP_STATUS=""
    BACKUP_WALLETS=""
fi
if [[ "${BACKUPS_ENABLED_NORM:-1}" =~ ^(0|false|no|off|disabled)$ ]]; then
    pass "backup completeness check skipped; backups disabled by operator"
elif [ "$BACKUP_STATUS" = "ok" ]; then
    pass "latest backup status ok"
else
    fail "latest backup status is ${BACKUP_STATUS:-missing}"
fi
if [[ "${BACKUPS_ENABLED_NORM:-1}" =~ ^(0|false|no|off|disabled)$ ]]; then
    :
else
    BACKUP_WALLET_COUNT=$(printf '%s\n' "$BACKUP_WALLETS" \
        | awk -F, 'NF && $0 != "" { print NF; found=1 } END { if (!found) print 0 }')
    if [ "$BACKUP_WALLET_COUNT" -ge 6 ]; then
        pass "wallet backups present (${BACKUP_WALLETS})"
    else
        fail "wallet backups incomplete (${BACKUP_WALLETS:-none})"
    fi
fi

say "disk stats sudo helper"
if sudo -u www-data sudo -n /usr/local/sbin/blakestream-mpos-disk-stats >/dev/null 2>&1; then
    pass "www-data can run the allowlisted disk stats helper"
else
    fail "www-data cannot run /usr/local/sbin/blakestream-mpos-disk-stats via sudo"
fi

say "scheduler mode"
if [ -f /etc/cron.d/blakestream-mpos ]; then
    fail "/etc/cron.d/blakestream-mpos exists; PHP cron must not be scheduled with authoritative cronjobs-py"
else
    pass "PHP cron not scheduled"
fi
if systemctl show blakestream-mpos-cronjobs.service \
        --property=Environment --value 2>/dev/null \
        | grep -Eq '(^|[[:space:]])CRONJOBS_PY_SHADOW_MODE=1([[:space:]]|$)'; then
    fail "cronjobs-py unit is in shadow mode"
else
    pass "cronjobs-py unit is authoritative"
fi

say "MPOS web ping"
WEB_BODY=$(curl -fsSL --max-time 5 "http://127.0.0.1:${MPOS_HTTP_PORT}/" 2>/dev/null || true)
if grep -qiE "blakecoin home|getting started|mpos" <<< "$WEB_BODY"; then
    pass "MPOS UI responding"
else
    fail "MPOS UI not responding"
fi

say "drift-check (diagnostic only)"
sudo -u blakestream-mpos /opt/blakestream-mpos/cronjobs-py/.venv/bin/cronjobs-py \
    --log-level WARN drift-check 2>&1 | tail -10 || true

if [ "$FAIL_COUNT" -gt 0 ]; then
    echo
    echo "verify: ${FAIL_COUNT} check(s) FAILED"
    exit 1
fi
echo
echo "verify: all checks pass"
