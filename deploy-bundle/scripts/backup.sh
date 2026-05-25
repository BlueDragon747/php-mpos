#!/usr/bin/env bash
# Blakestream-MPOS backup script.
#
# Captures the operator-relevant state of a deploy as a single
# tarball:
#
#   - `mpos` MariaDB dump (full DB, gzipped)
#   - `.deploy.env` (rendered secrets — DB pass, admin pass, MMP secret)
#   - rendered `eloipool/config.py` and `pool` log dir tail
#   - rendered MPOS `global.inc.php`
#   - rendered systemd unit files for the stack
#
# Excludes the per-coin daemon datadirs (`/var/lib/blakestream-mpos`,
# `/var/lib/blakestream-25.2`, or Docker volumes)
# because they're large, easy to re-sync from any peer, and not part
# of pool state. If you also want them, snapshot them separately or
# use the daemon's own `backupwallet` RPC.
#
# Intended to run from cron / systemd timer on the deploy host:
#
#   /opt/blakestream-mpos/bin/backup.sh /var/backups/blakestream-mpos
#
# Operators set up rotation externally (e.g. `find ... -mtime +14 -delete`).
set -euo pipefail

OUT_DIR="${1:-/var/backups/blakestream-mpos}"
mkdir -p "$OUT_DIR"

MPOS_INSTALL_ROOT="${MPOS_INSTALL_ROOT:-/opt/blakestream-mpos}"
DEPLOY_ENV="${MPOS_DEPLOY_ENV_FILE:-${MPOS_INSTALL_ROOT}/.deploy.env}"
if [ ! -f "$DEPLOY_ENV" ]; then
    echo "ERROR: ${DEPLOY_ENV} missing; is this a Blakestream-MPOS host?" >&2
    exit 1
fi

# shellcheck source=/dev/null
. "$DEPLOY_ENV"

MPOS_INSTALL_ROOT="${MPOS_INSTALL_ROOT:-/opt/blakestream-mpos}"
MPOS_WEB_ROOT="${MPOS_WEB_ROOT:-/var/www/blakestream-mpos}"
MPOS_LOG_ROOT="${MPOS_LOG_ROOT:-/var/log/blakestream-mpos}"
MPOS_DB_NAME="${MPOS_DB_NAME:?MPOS_DB_NAME missing from deploy env}"
MPOS_DB_USER="${MPOS_DB_USER:?MPOS_DB_USER missing from deploy env}"
MPOS_DB_PASS="${MPOS_DB_PASS:?MPOS_DB_PASS missing from deploy env}"
STATUS_FILE="${MPOS_BACKUP_STATUS_FILE:-${MPOS_LOG_ROOT}/backup-status.ini}"

ini_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

write_backup_status() {
    local status="$1"
    local tarball="$2"
    local wallets="$3"
    local db_name="$4"
    local db_size="$5"
    local tmp
    tmp="${STATUS_FILE}.tmp.$$"
    mkdir -p "$(dirname "$STATUS_FILE")"
    {
        printf 'status="%s"\n' "$(ini_escape "$status")"
        printf 'last_run_utc="%s"\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf 'last_mtime="%s"\n' "$(stat -c %Y "$tarball" 2>/dev/null || echo 0)"
        printf 'last_size="%s"\n' "$(stat -c %s "$tarball" 2>/dev/null || echo 0)"
        printf 'tarball="%s"\n' "$(ini_escape "$(basename "$tarball")")"
        printf 'out_dir="%s"\n' "$(ini_escape "$OUT_DIR")"
        printf 'wallets="%s"\n' "$(ini_escape "$wallets")"
        printf 'database="%s"\n' "$(ini_escape "$db_name")"
        printf 'database_size="%s"\n' "$db_size"
    } > "$tmp"
    chmod 644 "$tmp"
    mv "$tmp" "$STATUS_FILE"
}

# Kill switch: operator can pause backups from the admin Settings UI
# without touching the systemd timer (which they may not have SSH
# access to). The settings.backups_enabled row is seeded to 1; when
# the operator flips it to 0 via the web UI, every subsequent timer
# tick wakes up, reads this value, and exits 0 cheaply. Re-enabling
# is the same path in reverse, with no service restart needed.
ENABLED_RAW=$(mariadb -BNe \
    "SELECT value FROM settings WHERE name='backups_enabled' LIMIT 1;" \
    -u "${MPOS_DB_USER}" "-p${MPOS_DB_PASS}" "${MPOS_DB_NAME}" 2>/dev/null \
    || echo 1)
ENABLED=$(printf '%s' "${ENABLED_RAW:-1}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
case "${ENABLED:-1}" in
    0|false|no|off|disabled)
        echo "==> backups_enabled=${ENABLED} in settings; exiting (operator-disabled)"
        exit 0
        ;;
esac

# Schedule + retention come from the same `settings` table the web UI
# edits — the systemd timer fires every 30 minutes; this script checks
# whether we're inside the operator's chosen window (HH:MM ± 30 min in
# UTC) AND no backup has succeeded in the last 22 hours, and bails
# cheaply if not. That keeps schedule changes admin-editable without
# touching systemd / sudoers.
read_setting() {
    local key="$1" default="$2" val
    val=$(mariadb -BNe \
        "SELECT value FROM settings WHERE name='${key}' LIMIT 1;" \
        -u "${MPOS_DB_USER}" "-p${MPOS_DB_PASS}" "${MPOS_DB_NAME}" 2>/dev/null || true)
    if [ -z "$val" ]; then val="$default"; fi
    printf '%s' "$val"
}
SCHED_H=$(read_setting backup_schedule_hour   3)
SCHED_M=$(read_setting backup_schedule_minute 30)
BACKUP_RETENTION_DAYS=$(read_setting backup_retention_days 14)
export BACKUP_RETENTION_DAYS

if [ "${BACKUP_FORCE:-0}" = "1" ]; then
    echo "==> BACKUP_FORCE=1; bypassing schedule window + age debounce"
else
    NOW_H=$(date -u +%-H)
    NOW_M=$(date -u +%-M)
    TARGET_MOD=$((10#$SCHED_H * 60 + 10#$SCHED_M))
    NOW_MOD=$((10#$NOW_H * 60 + 10#$NOW_M))
    DELTA=$(( NOW_MOD - TARGET_MOD ))
    if [ "$DELTA" -lt 0 ]; then DELTA=$((DELTA + 1440)); fi
    if [ "$DELTA" -ge 30 ]; then
        echo "==> outside backup window (target ${SCHED_H}:${SCHED_M} UTC, now ${NOW_H}:${NOW_M}, delta=${DELTA}m); skipping"
        exit 0
    fi
fi

LATEST="${OUT_DIR}/latest.tar.gz"
if [ "${BACKUP_FORCE:-0}" != "1" ] && [ -e "$LATEST" ]; then
    LAST_MTIME=$(stat -c %Y "$LATEST" 2>/dev/null || echo 0)
    NOW_EPOCH=$(date +%s)
    AGE=$(( NOW_EPOCH - LAST_MTIME ))
    if [ "$AGE" -lt 79200 ]; then  # 22h debounce
        echo "==> last backup is ${AGE}s old (< 22h); skipping"
        exit 0
    fi
fi

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
HOSTNAME=$(hostname -s)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "==> dumping ${MPOS_DB_NAME}"
mariadb-dump --single-transaction --quick --routines --triggers \
    -u "${MPOS_DB_USER}" "-p${MPOS_DB_PASS}" \
    "${MPOS_DB_NAME}" \
    | gzip -9 > "${WORK}/${MPOS_DB_NAME}.sql.gz"

echo "==> capturing rendered configs"
cp "${MPOS_INSTALL_ROOT}/.deploy.env"       "${WORK}/.deploy.env"
cp "${MPOS_INSTALL_ROOT}/.mmp-secret"       "${WORK}/.mmp-secret" 2>/dev/null || true
cp "${MPOS_INSTALL_ROOT}/eloipool/config.py" "${WORK}/eloipool-config.py" 2>/dev/null || true
cp "${MPOS_WEB_ROOT}/include/config/global.inc.php" \
    "${WORK}/global.inc.php" 2>/dev/null || true

# Per-coin wallet backup via daemon RPC. Support both deployment shapes:
# local host daemons under /opt/blakestream-25.2 and Docker containers
# named by ticker. A raw wallet.dat copy can catch a half-flushed file;
# `backupwallet` asks the daemon to create a consistent backup.
echo "==> backing up wallets (RPC backupwallet)"
mkdir -p "${WORK}/wallets"
WALLETS=()
WALLET_FAILURES=0
declare -A DAEMON_BIN=(
    [blc]=blakecoin-cli
    [pho]=photon-cli
    [bbtc]=blakebitcoin-cli
    [elt]=electron-cli
    [umo]=universalmolecule-cli
    [lit]=lithium-cli
)
declare -A DAEMON_DATADIR=(
    [blc]=/root/.blakecoin
    [pho]=/root/.photon
    [bbtc]=/root/.blakebitcoin
    [elt]=/root/.electron
    [umo]=/root/.universalmolecule
    [lit]=/root/.lithium
)
declare -A LOCAL_CONF=(
    [blc]=/etc/blakestream-25.2/blakecoin.conf
    [pho]=/etc/blakestream-25.2/photon.conf
    [bbtc]=/etc/blakestream-25.2/blakebitcoin.conf
    [elt]=/etc/blakestream-25.2/electron.conf
    [umo]=/etc/blakestream-25.2/universalmolecule.conf
    [lit]=/etc/blakestream-25.2/lithium.conf
)
declare -A LOCAL_DATADIR=(
    [blc]=/var/lib/blakestream-25.2/blakecoin
    [pho]=/var/lib/blakestream-25.2/photon
    [bbtc]=/var/lib/blakestream-25.2/blakebitcoin
    [elt]=/var/lib/blakestream-25.2/electron
    [umo]=/var/lib/blakestream-25.2/universalmolecule
    [lit]=/var/lib/blakestream-25.2/lithium
)

wallet_safe_name() {
    local name="${1:-default}"
    if [ -z "$name" ] || [ "$name" = "__default__" ]; then
        name="default"
    fi
    printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '_'
}

wallet_label() {
    local wallet="${1:-default}"
    if [ -z "$wallet" ] || [ "$wallet" = "__default__" ]; then
        printf 'default'
    else
        printf '%s' "$wallet"
    fi
}

list_local_wallets() {
    local cli="$1" conf="$2" datadir="$3" wallets
    wallets=$("$cli" -conf="$conf" -datadir="$datadir" listwallets 2>/dev/null \
        | sed -n 's/^[[:space:]]*"\(.*\)"[[:space:]]*,\{0,1\}[[:space:]]*$/\1/p' \
        || true)
    if [ -z "$wallets" ]; then
        printf '%s\n' "__default__"
    else
        printf '%s\n' "$wallets"
    fi
}

backup_local_wallets() {
    local sym="$1" cli="$2" conf="$3" datadir="$4"
    local wallet safe label tmp out ok failures total
    local -a cmd
    ok=0
    failures=0
    total=0
    while IFS= read -r wallet; do
        [ -n "$wallet" ] || wallet="__default__"
        safe="$(wallet_safe_name "$wallet")"
        label="$(wallet_label "$wallet")"
        tmp="${datadir}/${sym}-wallet-${STAMP}-${safe}.dat"
        out="${WORK}/wallets/${sym}-${safe}.dat"
        total=$((total + 1))
        cmd=("$cli" -conf="$conf" -datadir="$datadir")
        if [ "$wallet" != "__default__" ]; then
            cmd+=("-rpcwallet=$wallet")
        fi
        cmd+=(backupwallet "$tmp")
        if "${cmd[@]}" >/dev/null 2>&1 && cp "$tmp" "$out" 2>/dev/null; then
            rm -f "$tmp" 2>/dev/null || true
            echo "    [$sym] local wallet ${label} backed up ($(du -h "$out" | cut -f1))"
            WALLETS+=("${sym}/${label}")
            ok=$((ok + 1))
        else
            rm -f "$tmp" 2>/dev/null || true
            echo "    [$sym] WARN: local wallet ${label} backup failed"
            failures=$((failures + 1))
        fi
    done < <(list_local_wallets "$cli" "$conf" "$datadir")

    [ "$total" -gt 0 ] && [ "$ok" -gt 0 ] && [ "$failures" -eq 0 ]
}

backup_docker_wallet() {
    local sym="$1" cli="$2" container="$3" inner_path="$4"
    if ! command -v docker >/dev/null 2>&1 \
        || ! docker ps --format '{{.Names}}' | grep -qx "$container"; then
        return 1
    fi
    if docker exec "$container" "$cli" backupwallet "$inner_path" >/dev/null 2>&1; then
        if docker cp "${container}:${inner_path}" "${WORK}/wallets/${sym}.dat" 2>/dev/null; then
            echo "    [$sym] Docker wallet backed up ($(du -h "${WORK}/wallets/${sym}.dat" | cut -f1))"
            WALLETS+=("${sym}/default")
            docker exec "$container" rm -f "$inner_path" 2>/dev/null || true
            return 0
        fi
        echo "    [$sym] WARN: Docker backupwallet succeeded but docker cp failed"
        return 1
    fi
    echo "    [$sym] WARN: Docker wallet RPC backup failed"
    return 1
}

mkdir -p "${WORK}/daemon-configs"
for sym in blc pho bbtc elt umo lit; do
    container="$sym"
    cli="${DAEMON_BIN[$sym]}"
    local_cli="${MPOS_DAEMON_BIN_DIR:-/opt/blakestream-25.2/bin}/${cli}"
    local_conf="${LOCAL_CONF[$sym]}"
    local_datadir="${LOCAL_DATADIR[$sym]}"
    if [ -x "$local_cli" ] && [ -r "$local_conf" ] && [ -d "$local_datadir" ]; then
        cp -p "$local_conf" "${WORK}/daemon-configs/${sym}.conf" 2>/dev/null || true
        if backup_local_wallets "$sym" "$local_cli" "$local_conf" "$local_datadir"; then
            continue
        fi
        echo "    [$sym] local backup failed; trying Docker fallback"
    fi

    inner_path="${DAEMON_DATADIR[$sym]}/${sym}-wallet-${STAMP}.dat"
    if backup_docker_wallet "$sym" "$cli" "$container" "$inner_path"; then
        continue
    else
        echo "    [$sym] WARN: no working local or Docker wallet backup path"
        WALLET_FAILURES=$((WALLET_FAILURES + 1))
    fi
done

echo "==> capturing systemd units"
mkdir -p "${WORK}/systemd"
cp /etc/systemd/system/blakestream-mpos-*.service "${WORK}/systemd/" 2>/dev/null || true
cp /etc/systemd/system/blakestream-mpos-*.timer "${WORK}/systemd/" 2>/dev/null || true

echo "==> recent log tails"
mkdir -p "${WORK}/logs"
for f in cronjobs.stdout cronjobs.stderr pool/eloipool.stderr pool/mmp.log; do
    src="${MPOS_LOG_ROOT}/${f}"
    [ -f "$src" ] && tail -c 1M "$src" > "${WORK}/logs/$(basename "$src")"
done

OUT="${OUT_DIR}/blakestream-mpos-${HOSTNAME}-${STAMP}.tar.gz"
( cd "$WORK" && tar -czf "$OUT" . )
chmod 600 "$OUT"

# Symlink "latest" for easy retrieval.
ln -snf "$(basename "$OUT")" "${OUT_DIR}/latest.tar.gz"

echo "==> wrote ${OUT} ($(du -h "$OUT" | cut -f1))"
WALLETS_CSV=$(IFS=,; printf '%s' "${WALLETS[*]}")
BACKUP_STATUS=ok
if [ "$WALLET_FAILURES" -gt 0 ]; then
    BACKUP_STATUS=partial
fi
DB_DUMP_SIZE=$(stat -c %s "${WORK}/${MPOS_DB_NAME}.sql.gz" 2>/dev/null || echo 0)
if ! write_backup_status "$BACKUP_STATUS" "$OUT" "$WALLETS_CSV" "$MPOS_DB_NAME" "$DB_DUMP_SIZE"; then
    echo "==> WARN: could not write backup status file ${STATUS_FILE}"
fi

# Optional: prune backups older than retention window (default 14 days).
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"
find "$OUT_DIR" -maxdepth 1 -name 'blakestream-mpos-*.tar.gz' \
    -mtime "+${RETENTION_DAYS}" -delete 2>/dev/null || true

if [ "$WALLET_FAILURES" -gt 0 ]; then
    echo "==> ERROR: ${WALLET_FAILURES} wallet backup(s) failed; tarball is partial"
    exit 1
fi
