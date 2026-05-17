#!/usr/bin/env bash
# 70-install-cronjobs-py.sh — install cronjobs-py as AUTHORITATIVE.
# PHP cron is staged for ad-hoc diagnostics only and is not scheduled.
set -euo pipefail
say() { printf '\033[1;33m   %s\033[0m\n' "$*"; }

INSTALL_ROOT=/opt/blakestream-mpos
LOG_ROOT=/var/log/blakestream-mpos
WEB_ROOT=/var/www/blakestream-mpos
MPOS_REPO=/root/Blakestream-MPOS
CRON_SRC="${MPOS_REPO}/cronjobs-py"
CRON_DEST="${INSTALL_ROOT}/cronjobs-py"
VENV="${CRON_DEST}/.venv"

# Service user.
if ! id blakestream-mpos >/dev/null 2>&1; then
    useradd --system --no-create-home --shell /usr/sbin/nologin blakestream-mpos
fi
# www-data owns global.inc.php; service user needs read access.
usermod -a -G www-data blakestream-mpos || true

say "rsync cronjobs-py -> ${CRON_DEST}"
mkdir -p "$CRON_DEST"
rsync -a --delete \
    --exclude='.venv' --exclude='__pycache__' --exclude='*.egg-info' \
    --exclude='tests' \
    "${CRON_SRC}/" "${CRON_DEST}/"

# Chown the source tree BEFORE creating the venv — pip needs write
# access to ${CRON_DEST} to drop the .egg-info dir and the .venv
# parent dir to write the venv itself.
chown -R blakestream-mpos:blakestream-mpos "$CRON_DEST"

say "creating venv at ${VENV}"
[ -d "$VENV" ] || sudo -u blakestream-mpos -H python3 -m venv "$VENV"
# pip cache: blakestream-mpos has no $HOME, so disable the cache to
# avoid "WARNING: directory '/nonexistent' is not writable" spam.
sudo -u blakestream-mpos -H PIP_NO_CACHE_DIR=1 "${VENV}/bin/pip" install -q --upgrade pip
sudo -u blakestream-mpos -H PIP_NO_CACHE_DIR=1 "${VENV}/bin/pip" install -q -e "${CRON_DEST}"

# Sanity import.
sudo -u blakestream-mpos "${VENV}/bin/python" -c \
    "import cronjobs_py.jobs.findblock; import cronjobs_py.drift" >/dev/null

say "writing systemd unit (AUTHORITATIVE)"
cat > /etc/systemd/system/blakestream-mpos-cronjobs.service <<EOF
[Unit]
Description=Blakestream-MPOS cronjobs-py scheduler (mainnet authoritative)
After=mariadb.service blakestream-mpos-eloipool.service
Wants=mariadb.service

[Service]
Type=simple
User=blakestream-mpos
Group=blakestream-mpos
WorkingDirectory=${CRON_DEST}
Environment=MPOS_CONFIG=${WEB_ROOT}/include/config/global.inc.php
# AUTHORITATIVE: cronjobs-py is the live scheduler for findblock,
# pplns_payout, payouts, reconcile_payouts, blockupdate, etc. PHP
# /etc/cron.d/blakestream-mpos is intentionally NOT installed by
# 60-install-php-cron.sh — running both would race on the same
# shares/transactions tables and double-send payouts. To temporarily
# return to shadow mode (e.g. for drift testing during a rebase), set
# CRONJOBS_PY_SHADOW_MODE=1 below and re-install /etc/cron.d/...
ExecStart=${VENV}/bin/cronjobs-py --log-level INFO serve
StandardOutput=append:${LOG_ROOT}/cronjobs.stdout
StandardError=append:${LOG_ROOT}/cronjobs.stderr
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now blakestream-mpos-cronjobs.service
say "step 70 done — cronjobs-py is AUTHORITATIVE; PHP cron NOT installed."
say "  drift gate (shadow mode): set CRONJOBS_PY_SHADOW_MODE=1 in unit + reinstall /etc/cron.d/blakestream-mpos"
