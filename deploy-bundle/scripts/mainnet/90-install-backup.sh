#!/usr/bin/env bash
# 90-install-backup.sh — install daily backup timer for mainnet.
#
# Stages:
#   1. ${MPOS_INSTALL_ROOT}/bin/backup.sh          (the script)
#   2. /etc/systemd/system/blakestream-mpos-backup.service
#   3. /etc/systemd/system/blakestream-mpos-backup.timer
#   4. enables + starts the timer (daily at 03:17 UTC + jitter)
#
# Backup output: /var/backups/blakestream-mpos/
# Retention: BACKUP_RETENTION_DAYS in deploy env (default 14).
#
# Operators are responsible for offsiting the tarballs (rsync to a
# different host, S3 upload, etc.). The local copy is a recovery
# floor, not a complete DR plan.
set -euo pipefail
say() { printf '\033[1;33m   %s\033[0m\n' "$*"; }

if [ ! -f /root/.mpos-deploy.env ]; then
    echo "ERROR: /root/.mpos-deploy.env missing; deploy orchestrator did not provide environment" >&2
    exit 1
fi

# shellcheck source=/dev/null
. /root/.mpos-deploy.env

INSTALL_ROOT="${MPOS_INSTALL_ROOT:-/opt/blakestream-mpos}"
LOG_ROOT="${MPOS_LOG_ROOT:-/var/log/blakestream-mpos}"
MPOS_REPO="${MPOS_REPO:-/root/Blakestream-MPOS}"

mkdir -p "${INSTALL_ROOT}/bin"

say "install deploy env -> ${INSTALL_ROOT}/.deploy.env"
mkdir -p "${INSTALL_ROOT}"
install -m 600 -o root -g root \
    /root/.mpos-deploy.env \
    "${INSTALL_ROOT}/.deploy.env"

say "install backup.sh -> ${INSTALL_ROOT}/bin/backup.sh"
install -m 750 -o root -g root \
    "${MPOS_REPO}/deploy-bundle/scripts/backup.sh" \
    "${INSTALL_ROOT}/bin/backup.sh"

say "install systemd unit + timer"
install -m 644 -o root -g root \
    "${MPOS_REPO}/deploy-bundle/systemd/blakestream-mpos-backup.service" \
    /etc/systemd/system/blakestream-mpos-backup.service
install -m 644 -o root -g root \
    "${MPOS_REPO}/deploy-bundle/systemd/blakestream-mpos-backup.timer" \
    /etc/systemd/system/blakestream-mpos-backup.timer

mkdir -p /var/backups/blakestream-mpos
chmod 700 /var/backups/blakestream-mpos
mkdir -p "${LOG_ROOT}"
chmod 755 "${LOG_ROOT}"

systemctl daemon-reload
systemctl enable --now blakestream-mpos-backup.timer
# Run the first backup synchronously and bypass the schedule-window
# check (the regular timer fires every 30 min but the script normally
# skips unless within ±30 min of the configured hour). Without this,
# 99-verify reports "latest backup artifact missing". Run backup.sh
# directly so we can pass BACKUP_FORCE=1 into the process env (systemd
# unit's Environment= doesn't easily plumb to a transient one-shot).
say "running first backup synchronously (force, bypass schedule window)"
BACKUP_FORCE=1 /opt/blakestream-mpos/bin/backup.sh /var/backups/blakestream-mpos \
    >>"${LOG_ROOT}/backup.log" 2>&1 \
    || say "  WARN: first backup exited non-zero — check ${LOG_ROOT}/backup.log"

say "step 90 done — daily backup timer installed."
say "  output:    /var/backups/blakestream-mpos/"
say "  next run:  $(systemctl list-timers blakestream-mpos-backup.timer --no-pager | awk 'NR==2 {print $1, $2}')"
say "  ad-hoc:    systemctl start blakestream-mpos-backup.service"
