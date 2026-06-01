#!/usr/bin/env bash
# Bridge Go Eloipool share logs into the MPOS shares table for testnet.
set -euo pipefail

say() { printf '\033[1;33m   %s\033[0m\n' "$*"; }

INSTALL_ROOT=${MPOS_INSTALL_ROOT:-/opt/blakestream-mpos}
LOG_ROOT=${MPOS_LOG_ROOT:-/var/log/blakestream-mpos}
BIN_DIR="${INSTALL_ROOT}/bin"
STATE_DIR=/var/lib/blakestream-mpos
CRON_DEST="${INSTALL_ROOT}/cronjobs-py"
VENV="${CRON_DEST}/.venv"
IMPORTER_SRC="${MPOS_REPO_ROOT}/deploy-bundle/scripts/go-share-log-importer.py"
IMPORTER_DEST="${BIN_DIR}/go-share-log-importer.py"
SHARE_LOG_PATH="${GO_SHARE_LOG_PATH:-${LOG_ROOT}/pool/shares.log}"
SYSTEMD_ENV="${INSTALL_ROOT}/.sharelog-importer.env"

[ -x "${VENV}/bin/python" ] || {
    echo "missing ${VENV}/bin/python; run 60-install-cronjobs-py.sh first" >&2
    exit 1
}
[ -f "${IMPORTER_SRC}" ] || {
    echo "missing ${IMPORTER_SRC}" >&2
    exit 1
}

say "installing Go share-log importer"
install -d -m 0755 -o root -g root "${BIN_DIR}"
install -m 0755 -o root -g root "${IMPORTER_SRC}" "${IMPORTER_DEST}"
install -d -m 0755 -o blakestream-mpos -g blakestream-mpos "${STATE_DIR}"
install -d -m 0755 -o blakestream-mpos -g blakestream-mpos "${LOG_ROOT}"
install -d -m 0755 -o blakestream-mpos -g blakestream-mpos "$(dirname "$SHARE_LOG_PATH")"
touch "$SHARE_LOG_PATH"
chown blakestream-mpos:blakestream-mpos "$SHARE_LOG_PATH"

cat > "$SYSTEMD_ENV" <<EOF
MPOS_DB_HOST=${MPOS_DB_HOST:-127.0.0.1}
MPOS_DB_PORT=${MPOS_DB_PORT:-3306}
MPOS_DB_USER=${MPOS_DB_USER:-mpos}
MPOS_DB_PASS=${MPOS_DB_PASS}
MPOS_DB_NAME=${MPOS_DB_NAME:-mpos}
GO_SHARE_LOG_PATH=${SHARE_LOG_PATH}
SHARE_IMPORT_STATE=${STATE_DIR}/go-share-log-importer.state
SHARE_IMPORT_BATCH=${SHARE_IMPORT_BATCH:-2000}
SHARE_IMPORT_POLL_SECONDS=${SHARE_IMPORT_POLL_SECONDS:-1}
SHARE_IMPORT_WORKER_REFRESH_SECONDS=${SHARE_IMPORT_WORKER_REFRESH_SECONDS:-10}
EOF
chown root:blakestream-mpos "$SYSTEMD_ENV"
chmod 640 "$SYSTEMD_ENV"

say "writing /etc/systemd/system/blakestream-mpos-sharelog-importer.service"
cat > /etc/systemd/system/blakestream-mpos-sharelog-importer.service <<EOF
[Unit]
Description=Blakestream-MPOS Go share-log importer (testnet)
After=mariadb.service blakestream-mpos-eloipool.service
Wants=mariadb.service

[Service]
Type=simple
User=blakestream-mpos
Group=blakestream-mpos
WorkingDirectory=${INSTALL_ROOT}
EnvironmentFile=${SYSTEMD_ENV}
ExecStart=${VENV}/bin/python ${IMPORTER_DEST}
StandardOutput=append:${LOG_ROOT}/sharelog-importer.stdout
StandardError=append:${LOG_ROOT}/sharelog-importer.stderr
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now blakestream-mpos-sharelog-importer.service

say "share-log importer installed"
say "  log:   ${SHARE_LOG_PATH}"
say "  state: ${STATE_DIR}/go-share-log-importer.state"
