#!/usr/bin/env bash
# Idempotent purge of any prior MPOS deploy state. Does NOT wipe the
# Eliopool stack — that is the responsibility of the operator (or a
# subsequent --wipe pass through Eliopool's own deploy script).
set -euo pipefail

say() { printf '\033[1;33m   %s\033[0m\n' "$*"; }

say "stopping MPOS services"
# Wave 3: enumerate every blakestream-mpos-* unit (services AND timers)
# rather than naming a single one. The deploy bundle has grown to
# include a backup timer / service alongside the cronjobs unit, and
# a partial wipe that misses the backup timer leaves a phantom timer
# triggering a non-existent service post-redeploy.
mapfile -t MPOS_UNITS < <(
    systemctl list-unit-files --type=service,timer --no-legend --no-pager 2>/dev/null \
    | awk '$1 ~ /^blakestream-mpos-/ {print $1}'
)
for unit in "${MPOS_UNITS[@]:-}"; do
    [ -z "$unit" ] && continue
    say "  stopping ${unit}"
    systemctl stop "$unit" 2>/dev/null || true
    systemctl disable "$unit" 2>/dev/null || true
    rm -f "/etc/systemd/system/${unit}"
done
systemctl daemon-reload

say "wiping web root and install root"
rm -rf "${MPOS_WEB_ROOT}"
rm -rf "${MPOS_INSTALL_ROOT}/cronjobs-py"
rm -rf "${MPOS_INSTALL_ROOT}/.deploy.env"

say "removing nginx vhost"
rm -f /etc/nginx/sites-available/blakestream-mpos
rm -f /etc/nginx/sites-enabled/blakestream-mpos

say "dropping MPOS database (if exists)"
if command -v mariadb >/dev/null 2>&1 && systemctl is-active --quiet mariadb; then
    mariadb -e "DROP DATABASE IF EXISTS \`${MPOS_DB_NAME}\`;" || true
    mariadb -e "DROP USER IF EXISTS '${MPOS_DB_USER}'@'localhost';" || true
fi

say "wipe complete"
