#!/usr/bin/env bash
# mpos-watch-sync.sh — live dashboard for the bootstrap-rotation step.
# Run from a second SSH session while deploy-mainnet.sh is in step 21.
# Reads status files written by 21-bootstrap-coins.sh.
#
# Usage:
#   ssh root@vps /root/php-mpos/deploy-bundle/scripts/mpos-watch-sync.sh
#
# Ctrl+C exits and restores the cursor.

set -u

DASHBOARD_STATUS_DIR="${DASHBOARD_STATUS_DIR:-/var/run/mpos-sync}"
REFRESH_S="${REFRESH_S:-3}"

COINS=(elt umo pho lit bbtc blc)
declare -A COIN_DATADIR=(
    [blc]="/root/.blakecoin"
    [pho]="/root/.photon"
    [bbtc]="/root/.blakebitcoin"
    [elt]="/root/.electron"
    [umo]="/root/.universalmolecule"
    [lit]="/root/.lithium"
)
N_ROWS=$((${#COINS[@]} + 2))   # banner + 6 coin rows + footer

if [ ! -d "$DASHBOARD_STATUS_DIR" ]; then
    echo "no status dir at ${DASHBOARD_STATUS_DIR}"
    echo "is a deploy currently running 21-bootstrap-coins.sh?"
    exit 1
fi

# Hide cursor, clear screen, restore on exit
printf '\033[2J\033[H\033[?25l'
trap 'printf "\033[?25h\n"' EXIT INT TERM

# Seed N_ROWS blank lines so the first redraw has rows to clear
for ((i=0; i<N_ROWS; i++)); do echo; done

render() {
    printf '\033[%dA\033[J' "$N_ROWS"
    printf '   === MPOS Sync Dashboard (live) — %s UTC ===\n' "$(date -u +%H:%M:%S)"
    local c s state h t d
    for c in "${COINS[@]}"; do
        s=$(cat "${DASHBOARD_STATUS_DIR}/${c}.status" 2>/dev/null || echo "QUEUED|||")
        IFS='|' read -r state h t d <<<"$s"
        case "$state" in
            DOWNLOADING)
                local cur tmp_path pct
                tmp_path=$(find "${COIN_DATADIR[$c]}" -maxdepth 1 -name '*-bootstrap-*.dat.xz.tmp' -print -quit 2>/dev/null || true)
                cur=$(stat -c '%s' "$tmp_path" 2>/dev/null || echo "${h:-0}")
                pct=0
                [ "${t:-0}" -gt 0 ] && pct=$(( cur * 100 / t ))
                [ "$pct" -gt 100 ] && pct=100
                printf '   %-5s [DL]    %-10s / %-10s (%3d%%)\n' "${c}:" \
                    "$(numfmt --to=iec --suffix=B "$cur" 2>/dev/null || echo "$cur")" \
                    "$(numfmt --to=iec --suffix=B "$t"   2>/dev/null || echo "$t")" \
                    "$pct"
                ;;
            DECOMPRESSING)
                local cur tmp_path
                tmp_path="${COIN_DATADIR[$c]}/bootstrap.dat.tmp"
                cur=$(stat -c '%s' "$tmp_path" 2>/dev/null || echo "${h:-0}")
                printf '   %-5s [XZ]    staging bootstrap.dat (%s)\n' "${c}:" \
                    "$(numfmt --to=iec --suffix=B "$cur" 2>/dev/null || echo "$cur")"
                ;;
            STAGED)
                printf '   %-5s [STAGED] bootstrap.dat=%s\n' "${c}:" \
                    "$(numfmt --to=iec --suffix=B "$h" 2>/dev/null || echo "$h")"
                ;;
            IMPORTING)
                local pct
                pct=0
                [ "${t:-0}" -gt 0 ] && pct=$(( h * 100 / t ))
                [ "$pct" -gt 100 ] && pct=100
                printf '   %-5s [IMPORT] h=%-12s target=%-12s (%3d%%)\n' "${c}:" "$h" "$t" "$pct"
                ;;
            SYNCING)
                printf '   %-5s [SYNC]  h=%-12s tip=%-12s delta=%s\n' "${c}:" "$h" "$t" "$d"
                ;;
            FINISHED)
                printf '   %-5s [DONE]  final=%s\n' "${c}:" \
                    "$(numfmt --to=iec --suffix=B "$h" 2>/dev/null || echo "$h")"
                ;;
            FAILED)
                printf '   %-5s [FAILED]\n' "${c}:"
                ;;
            QUEUED|*)
                printf '   %-5s [QUEUED]\n' "${c}:"
                ;;
        esac
    done
    printf '   (refresh every %ss; Ctrl+C to quit)\n' "$REFRESH_S"
}

while true; do
    render
    sleep "$REFRESH_S"
done
