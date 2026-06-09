#!/usr/bin/env bash
# Queue one forced MPOS backup from the admin System Status page.
# No arguments are accepted so the sudoers rule cannot be used to run
# arbitrary commands as root.
set -euo pipefail

if [ "$#" -ne 0 ]; then
    echo "backup helper does not accept arguments" >&2
    exit 64
fi

UNIT="blakestream-mpos-backup-manual.service"
BACKUP_SCRIPT="/opt/blakestream-mpos/bin/backup.sh"
BACKUP_DIR="/var/backups/blakestream-mpos"
LOG_FILE="/var/log/blakestream-mpos/backup.log"

if [ ! -x "$BACKUP_SCRIPT" ]; then
    echo "backup script is not installed" >&2
    exit 1
fi

if systemctl is-active --quiet blakestream-mpos-backup.service ||
   systemctl is-active --quiet "$UNIT"; then
    echo "backup already running"
    exit 0
fi

systemctl reset-failed "$UNIT" >/dev/null 2>&1 || true
systemd-run --quiet \
    --unit="$UNIT" \
    --collect \
    --property=Type=oneshot \
    --property=TimeoutStartSec=15min \
    --property=StandardOutput=append:"$LOG_FILE" \
    --property=StandardError=append:"$LOG_FILE" \
    --setenv=BACKUP_FORCE=1 \
    "$BACKUP_SCRIPT" "$BACKUP_DIR"

echo "backup queued"
