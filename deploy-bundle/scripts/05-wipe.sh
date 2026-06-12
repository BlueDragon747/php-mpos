#!/usr/bin/env bash
# Idempotent purge of any prior MPOS deploy state. Does NOT wipe the
# Eliopool stack — that is the responsibility of the operator (or a
# subsequent --wipe pass through Eliopool's own deploy script).
set -euo pipefail

say() { printf '\033[1;33m   %s\033[0m\n' "$*"; }

# Destructive-op confirmation. This permanently deletes the web/install/data
# roots and drops the MPOS database. The deploy --wipe flag opts in, but we
# also require an explicit confirmation — a typed phrase at the terminal, or
# MPOS_WIPE_ASSUME_YES=1 for non-interactive/CI runs — so a fat-fingered
# --wipe can't silently nuke a live pool.
confirm_wipe() {
    say "ABOUT TO PERMANENTLY DELETE:"
    printf '     web root:     %s\n' "${MPOS_WEB_ROOT}"
    printf '     install root: %s\n' "${MPOS_INSTALL_ROOT}"
    printf '     data root:    %s\n' "${MPOS_DATA_ROOT:-/var/lib/blakestream-mpos}"
    printf '     database:     %s (user %s@localhost)\n' "${MPOS_DB_NAME}" "${MPOS_DB_USER}"
    if [ "${MPOS_WIPE_ASSUME_YES:-0}" = "1" ]; then
        say "MPOS_WIPE_ASSUME_YES=1 — proceeding without an interactive prompt"
        return
    fi
    # No controlling terminal (CI / piped) -> fail closed; the prompt write
    # to /dev/tty is the interactivity probe.
    if ! printf 'Type the database name (%s) to confirm the wipe: ' "${MPOS_DB_NAME}" > /dev/tty 2>/dev/null; then
        printf 'ERROR: refusing to wipe non-interactively. Set MPOS_WIPE_ASSUME_YES=1 to confirm.\n' >&2
        exit 1
    fi
    read -r _wipe_reply < /dev/tty || _wipe_reply=""
    if [ "$_wipe_reply" != "${MPOS_DB_NAME}" ]; then
        printf 'Confirmation did not match; aborting wipe.\n' >&2
        exit 1
    fi
}
confirm_wipe

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

say "wiping web, install, and daemon data roots"
rm -rf "${MPOS_WEB_ROOT}"
rm -rf "${MPOS_INSTALL_ROOT}"
rm -rf "${MPOS_DATA_ROOT:-/var/lib/blakestream-mpos}"

say "removing nginx vhost"
rm -f /etc/nginx/sites-available/blakestream-mpos
rm -f /etc/nginx/sites-enabled/blakestream-mpos

say "dropping MPOS database (if exists)"
if command -v mariadb >/dev/null 2>&1 && systemctl is-active --quiet mariadb; then
    mariadb -e "DROP DATABASE IF EXISTS \`${MPOS_DB_NAME}\`;" || true
    mariadb -e "DROP USER IF EXISTS '${MPOS_DB_USER}'@'localhost';" || true
fi

say "wipe complete"
