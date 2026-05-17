#!/usr/bin/env bash
# Read-only disk usage helper for the MPOS System Status page.
#
# This script is intentionally no-argument and path-allowlisted so sudoers
# can grant www-data exactly this command without allowing arbitrary `du`.
set -euo pipefail

PATH=/usr/sbin:/usr/bin:/sbin:/bin
export LC_ALL=C

if [ "$#" -ne 0 ]; then
    echo "usage: $(basename "$0")" >&2
    exit 64
fi

DU=/usr/bin/du
TIMEOUT=/usr/bin/timeout
if [ ! -x "$DU" ]; then
    echo "du not available" >&2
    exit 69
fi

run_du() {
    local path="$1"
    if [ ! -d "$path" ]; then
        return 0
    fi

    local out="" mb=""
    if [ -x "$TIMEOUT" ]; then
        out="$("$TIMEOUT" 20s "$DU" -sm -- "$path" 2>/dev/null || true)"
    else
        out="$("$DU" -sm -- "$path" 2>/dev/null || true)"
    fi

    mb="$(printf '%s\n' "$out" | awk 'NR == 1 { print $1 }')"
    if [[ "$mb" =~ ^[0-9]+$ ]]; then
        printf '%s\t%s\n' "$path" "$mb"
    fi
}

run_du /var/backups/blakestream-mpos
run_du /var/lib/mysql
run_du /var/log/blakestream-mpos
run_du /var/lib/docker
