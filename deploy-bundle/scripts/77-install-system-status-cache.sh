#!/usr/bin/env bash
# Install the System Status memcached collector.
set -euo pipefail

say() { printf '\033[1;33m   %s\033[0m\n' "$*"; }

WEB_ROOT="${MPOS_WEB_ROOT:-/var/www/blakestream-mpos}"
LOG_ROOT="${MPOS_LOG_ROOT:-/var/log/blakestream-mpos}"
RUN_USER="${MPOS_RUN_USER:-www-data}"
RUN_GROUP="${MPOS_RUN_GROUP:-www-data}"
PHP_BIN="${PHP_BIN:-/usr/bin/php}"
COLLECTOR="${WEB_ROOT}/include/tools/system_status_collector.php"

[ -f "$COLLECTOR" ] || { echo "missing ${COLLECTOR}" >&2; exit 1; }
[ -x "$PHP_BIN" ] || { echo "missing ${PHP_BIN}" >&2; exit 1; }

mkdir -p "$LOG_ROOT"
touch "${LOG_ROOT}/system-status-cache.stdout" "${LOG_ROOT}/system-status-cache.stderr"
chown "${RUN_USER}:${RUN_GROUP}" \
    "${LOG_ROOT}/system-status-cache.stdout" \
    "${LOG_ROOT}/system-status-cache.stderr"

say "warming System Status cache once"
sudo -u "$RUN_USER" "$PHP_BIN" "$COLLECTOR" --once >/dev/null

say "writing /etc/systemd/system/blakestream-mpos-system-status-cache.service"
cat > /etc/systemd/system/blakestream-mpos-system-status-cache.service <<EOF
[Unit]
Description=Blakestream-MPOS System Status memcached collector
After=memcached.service mariadb.service
Wants=memcached.service mariadb.service

[Service]
Type=simple
User=${RUN_USER}
Group=${RUN_GROUP}
WorkingDirectory=${WEB_ROOT}
ExecStart=${PHP_BIN} ${COLLECTOR} --loop --interval 60 --quiet
StandardOutput=append:${LOG_ROOT}/system-status-cache.stdout
StandardError=append:${LOG_ROOT}/system-status-cache.stderr
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable blakestream-mpos-system-status-cache.service >/dev/null
systemctl restart blakestream-mpos-system-status-cache.service
sleep 2
systemctl is-active --quiet blakestream-mpos-system-status-cache.service

say "step 77 done - System Status cache refreshes every 60 seconds"
