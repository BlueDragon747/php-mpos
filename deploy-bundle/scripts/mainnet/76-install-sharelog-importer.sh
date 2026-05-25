#!/usr/bin/env bash
# 76-install-sharelog-importer.sh — bridge Go Eloipool share logs into MPOS.
set -euo pipefail
say() { printf '\033[1;33m   %s\033[0m\n' "$*"; }

INSTALL_ROOT=${MPOS_INSTALL_ROOT:-/opt/blakestream-mpos}
LOG_ROOT=${MPOS_LOG_ROOT:-/var/log/blakestream-mpos}
MPOS_REPO=/root/Blakestream-MPOS
BIN_DIR="${INSTALL_ROOT}/bin"
STATE_DIR=/var/lib/blakestream-mpos
CRON_DEST="${INSTALL_ROOT}/cronjobs-py"
VENV="${CRON_DEST}/.venv"
IMPORTER_SRC="${MPOS_REPO}/deploy-bundle/scripts/go-share-log-importer.py"
IMPORTER_DEST="${BIN_DIR}/go-share-log-importer.py"
SHARE_LOG_PATH="${GO_SHARE_LOG_PATH:-/var/log/blakestream-eliopool-25.2-go/shares.log}"

if ! id blakestream-mpos >/dev/null 2>&1; then
    useradd --system --no-create-home --shell /usr/sbin/nologin blakestream-mpos
fi

[ -x "${VENV}/bin/python" ] || { echo "missing ${VENV}/bin/python; run 70-install-cronjobs-py.sh first" >&2; exit 1; }
[ -f "${IMPORTER_SRC}" ] || { echo "missing ${IMPORTER_SRC}" >&2; exit 1; }

say "installing Go share-log importer"
install -d -m 0755 -o root -g root "${BIN_DIR}"
install -m 0755 -o root -g root "${IMPORTER_SRC}" "${IMPORTER_DEST}"
install -d -m 0755 -o blakestream-mpos -g blakestream-mpos "${STATE_DIR}"
install -d -m 0755 -o blakestream-mpos -g blakestream-mpos "${LOG_ROOT}"

say "writing /etc/systemd/system/blakestream-mpos-sharelog-importer.service"
cat > /etc/systemd/system/blakestream-mpos-sharelog-importer.service <<EOF
[Unit]
Description=Blakestream-MPOS Go share-log importer
After=mariadb.service blakestream-eloipool-25.2-go.service blakestream-eliopool-25.2-go.service
Wants=mariadb.service

[Service]
Type=simple
User=blakestream-mpos
Group=blakestream-mpos
WorkingDirectory=${INSTALL_ROOT}
EnvironmentFile=${INSTALL_ROOT}/.deploy.env
Environment=GO_SHARE_LOG_PATH=${SHARE_LOG_PATH}
Environment=SHARE_IMPORT_STATE=${STATE_DIR}/go-share-log-importer.state
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
