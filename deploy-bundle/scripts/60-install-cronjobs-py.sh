#!/usr/bin/env bash
# Install cronjobs-py as a systemd-managed scheduler.
#   - rsync source to ${MPOS_INSTALL_ROOT}/cronjobs-py/
#   - venv + pip install -e .
#   - systemd unit invokes `cronjobs-py serve`
#
# Default: install but DO NOT enable. Set MPOS_PYTHON_CRONJOBS_ACTIVE=1
# in the deploy environment to opt in. Running PHP cronjobs and
# cronjobs-py against the same DB is an idempotency hazard.
set -euo pipefail

say() { printf '\033[1;33m   %s\033[0m\n' "$*"; }

CRON_SRC="${MPOS_REPO_ROOT}/cronjobs-py"
CRON_DEST="${MPOS_INSTALL_ROOT}/cronjobs-py"
VENV="${CRON_DEST}/.venv"

if [ ! -d "$CRON_SRC" ]; then
    echo "missing ${CRON_SRC}" >&2
    exit 1
fi

# blakestream-mpos needs to read MPOS's global.inc.php (to load DB
# creds + RPC creds) which is owned by ${MPOS_RUN_USER}:${MPOS_RUN_GROUP}
# (typically www-data:www-data) with mode 640. Add the service user to
# the web group so the `php -r` bridge in settings.py can require_once it.
say "adding blakestream-mpos to ${MPOS_RUN_GROUP} group"
usermod -a -G "${MPOS_RUN_GROUP}" blakestream-mpos

say "syncing cronjobs-py source"
mkdir -p "$CRON_DEST"
rsync -a --delete --exclude='.venv' --exclude='__pycache__' --exclude='*.egg-info' \
    "${CRON_SRC}/" "${CRON_DEST}/"

say "creating venv at ${VENV}"
if [ ! -d "$VENV" ]; then
    python3 -m venv "$VENV"
fi
"${VENV}/bin/pip" install -q --upgrade pip
"${VENV}/bin/pip" install -q -e "${CRON_DEST}"

# Sanity import — fails fast if dependencies aren't right.
"${VENV}/bin/python" -c "import cronjobs_py.jobs.findblock" >/dev/null

chown -R blakestream-mpos:blakestream-mpos "$CRON_DEST"

say "writing systemd unit"
cat > /etc/systemd/system/blakestream-mpos-cronjobs.service <<EOF
[Unit]
Description=Blakestream-MPOS cronjobs-py scheduler
After=mariadb.service blakestream-mpos-eloipool.service
Wants=mariadb.service

[Service]
Type=simple
User=blakestream-mpos
Group=blakestream-mpos
WorkingDirectory=${CRON_DEST}
Environment=MPOS_CONFIG=${MPOS_WEB_ROOT}/include/config/global.inc.php
ExecStart=${VENV}/bin/cronjobs-py --log-level INFO serve
StandardOutput=append:${MPOS_LOG_ROOT}/cronjobs.stdout
StandardError=append:${MPOS_LOG_ROOT}/cronjobs.stderr
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

if [ "${MPOS_PYTHON_CRONJOBS_ACTIVE:-0}" = "1" ]; then
    systemctl enable --now blakestream-mpos-cronjobs.service
    say "cronjobs-py started (MPOS_PYTHON_CRONJOBS_ACTIVE=1)"
else
    # Make sure a previously-enabled unit (e.g. from a prior deploy
    # run before this default flip) gets stopped so we don't ghost-run
    # cronjobs-py against the DB while the operator thinks PHP cron
    # is the only writer.
    if systemctl is-active --quiet blakestream-mpos-cronjobs.service; then
        systemctl disable --now blakestream-mpos-cronjobs.service
        say "cronjobs-py was active — stopped + disabled (set MPOS_PYTHON_CRONJOBS_ACTIVE=1 to opt in)"
    else
        say "cronjobs-py installed but NOT enabled (set MPOS_PYTHON_CRONJOBS_ACTIVE=1 to opt in)"
    fi
fi

# Backup helper + daily timer.
say "installing backup helper + daily timer"
install -d "${MPOS_INSTALL_ROOT}/bin"
install -m 755 "${MPOS_DEPLOY_BUNDLE}/scripts/backup.sh" \
    "${MPOS_INSTALL_ROOT}/bin/backup.sh"
install -d /var/backups/blakestream-mpos
install -m 644 "${MPOS_DEPLOY_BUNDLE}/systemd/blakestream-mpos-backup.service" \
    /etc/systemd/system/blakestream-mpos-backup.service
install -m 644 "${MPOS_DEPLOY_BUNDLE}/systemd/blakestream-mpos-backup.timer" \
    /etc/systemd/system/blakestream-mpos-backup.timer
systemctl daemon-reload
systemctl enable --now blakestream-mpos-backup.timer
say "daily backup timer enabled (next: $(systemctl show -p NextElapseUSecRealtime --value blakestream-mpos-backup.timer 2>/dev/null || echo 'TBD'))"
