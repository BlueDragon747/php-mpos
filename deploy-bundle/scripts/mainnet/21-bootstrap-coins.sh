#!/usr/bin/env bash
# =============================================================================
# 21-bootstrap-coins.sh — sequential solo bootstrap of all 6 BlakeStream
# daemon containers on the VPS.
#
# WHY THIS EXISTS
# ---------------
# On a 16 GB host running the full 6-coin merge-mining stack, starting
# all daemons concurrently with un-replayed bootstrap.dat files leads
# to deterministic OOM during the loadblk → validation transition:
# each daemon's working set spikes well past its dbcache cap while
# block files are read into memory before being flushed. We measured
# RSS=10.4 GB and 100% swap fill on ELT alone within 5 minutes when
# the other 4 daemons were also active.
#
# !!  ELECTRON (ELT) and UNIVERSALMOLECULE (UMO) MUST BOOTSTRAP SOLO. !!
#
# ELT's chain has ~6.18M blocks and a 4.3 GB bootstrap.dat; UMO's is
# 9+ GB on disk. With other daemons running, peak validation RSS for
# either pushes the host into thrashing. With every other daemon
# stopped, ELT and UMO bootstrap cleanly in ~30 minutes each, RSS
# plateaus at ~10 GB, and swap stays under 500 MB.
#
# The remaining four (BLC, BBTC, PHO, LIT) tolerate concurrent
# bootstrap better (smaller chains), but to keep the operational
# story uniform this script bootstraps ALL six the same way: one at
# a time, with peering OFF during loadblk, then peering ON to catch
# the network tip, then the daemon is stopped and the next coin
# begins.
#
# After the rotation, daemons are started one at a time at the end so
# the operator can confirm each container's logs and host headroom
# before the next one is brought online.
#
# IMPORTANT IMPLEMENTATION NOTES (lessons from the 2026-04-27 rotation)
# ---------------------------------------------------------------------
#  1. Listening on `listen=0` and `maxconnections=0` does NOT prevent
#     outbound peer connections when `addnode=` lines are present in
#     the config — addnode entries override maxconnections=0 and the
#     daemon dials them anyway. The actual isolation that protects RAM
#     comes from STOPPING THE OTHER DAEMONS, not from peers-off
#     settings. The peers-off block is kept here as defence-in-depth
#     (suppresses inbound) but don't rely on it for memory budget.
#
#  2. Hitting `progress=1.0` is *NOT* the moment chainstate is durably
#     flushed to disk. Validation completes in memory; chainstate is
#     only persisted on the next periodic flush (when dbcache fills)
#     or at clean shutdown. If you `docker rm -f` immediately after
#     `progress=1.0`, the daemon's clean-shutdown handler may rush a
#     partial flush and the chainstate on disk can lag by 100k+
#     blocks. On next start the daemon then has to re-validate that
#     gap from peers, which is the same problem we were trying to
#     avoid. We saw PHO roll back ~313k blocks and BBTC roll back
#     ~492k blocks because of this.
#
#  3. SAFER STOP SEQUENCE between coins:
#       a. `docker exec <coin> /usr/local/bin/<daemon>-cli stop`
#          (graceful RPC stop — daemon flushes chainstate explicitly).
#       b. Wait for the container to exit (poll `docker ps -a`).
#       c. Then `docker rm <coin>` (no -f).
#       OR alternatively just `docker stop <coin>` (NOT `rm -f`),
#       which respects --stop-timeout and lets the daemon shut down
#       cleanly. The script below uses `docker stop` then `docker rm`.
#
# Invocation
# ----------
#   bash 21-bootstrap-coins.sh                # rotate all 6
#   bash 21-bootstrap-coins.sh elt umo        # rotate a subset, in order
#   START_AFTER=0 bash 21-bootstrap-coins.sh  # skip the final start-all phase
#
# Pre-conditions
# --------------
#   - 20-deploy-daemons.sh already ran (containers/configs exist)
#   - This script downloads bootstrap.dat for each coin if missing
#   - dbcache=200 and maxmempool=50 set in each <coin>.conf (this
#     script will add them if missing)
# =============================================================================
set -euo pipefail

say()  { printf '\033[1;33m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;31m!!\033[0m %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m✓\033[0m  %s\n' "$*"; }

# Per-coin metadata: container_name|datadir|conf|daemon_binary
declare -A COIN_DATADIR=(
    [blc]="/root/.blakecoin"
    [pho]="/root/.photon"
    [bbtc]="/root/.blakebitcoin"
    [elt]="/root/.electron"
    [umo]="/root/.universalmolecule"
    [lit]="/root/.lithium"
)
declare -A COIN_CONF=(
    [blc]="blakecoin.conf"
    [pho]="photon.conf"
    [bbtc]="blakebitcoin.conf"
    [elt]="electron.conf"
    [umo]="universalmolecule.conf"
    [lit]="lithium.conf"
)
declare -A COIN_DAEMON=(
    [blc]="blakecoind"
    [pho]="photond"
    [bbtc]="blakebitcoind"
    [elt]="electrond"
    [umo]="universalmoleculed"
    [lit]="lithiumd"
)
declare -A COIN_CLI=(
    [blc]="blakecoin-cli"
    [pho]="photon-cli"
    [bbtc]="blakebitcoin-cli"
    [elt]="electron-cli"
    [umo]="universalmolecule-cli"
    [lit]="lithium-cli"
)
declare -A COIN_IMAGE_NAME=(
    [blc]="blakecoin"
    [pho]="photon"
    [bbtc]="blakebitcoin"
    [elt]="electron"
    [umo]="universalmolecule"
    [lit]="lithium"
)
declare -A BOOTSTRAP_PREFIX=(
    [blc]="blakecoin"
    [pho]="photon"
    [bbtc]="blakebitcoin"
    [elt]="electron"
    [umo]="universalmolecule"
    [lit]="lithium"
)

# Default rotation order: ELT first because it's the largest chain
# (and the one that historically OOM'd first with peers off). UMO
# next for the same reason. Then the smaller chains.
DEFAULT_ORDER=(elt umo pho lit bbtc blc)

# Phase B groups — coins inside a group sync concurrently, groups run
# in series. ELT and UMO are big enough that they get the whole host
# to themselves; the four smaller chains are paired (BLC+PHO and
# LIT+BBTC) since two of them comfortably fit in RAM at once with
# BOOTSTRAP_DBCACHE_MB=4000 each on a 15 GB host.
DEFAULT_GROUPS=(
    "elt"
    "umo"
    "blc pho"
    "lit bbtc"
)

# Phase A download concurrency: how many wget processes run at once.
# 3 saturates a typical 100Mbit Vultr link without hammering the
# bootstrap mirror.
DOWNLOAD_CONCURRENCY="${DOWNLOAD_CONCURRENCY:-3}"

# Tuning — dbcache flips between BOOTSTRAP_DBCACHE_MB during fresh-import
# (large in-memory UTXO buffer = fewer disk flushes during validation,
# faster catch-up) and STEADY_DBCACHE_MB once the chain is at tip and
# the daemon is running alongside its 5 peers.
# When MPOS_ADAPTIVE_DBCACHE=1 (default), bootstrap dbcache is sized
# from MemAvailable / SYNC_CONCURRENCY rather than hardcoded. Reserves
# OS_HEADROOM_MB for OS + docker + nginx + php-fpm + mariadb.
# Clamped to [MIN, MAX]. Override BOOTSTRAP_DBCACHE_MB to fix it.
MPOS_ADAPTIVE_DBCACHE="${MPOS_ADAPTIVE_DBCACHE:-1}"
OS_HEADROOM_MB="${OS_HEADROOM_MB:-2048}"
BOOTSTRAP_DBCACHE_MIN_MB="${BOOTSTRAP_DBCACHE_MIN_MB:-500}"
BOOTSTRAP_DBCACHE_MAX_MB="${BOOTSTRAP_DBCACHE_MAX_MB:-8000}"
BOOTSTRAP_DBCACHE_MB="${BOOTSTRAP_DBCACHE_MB:-}"
STEADY_DBCACHE_MB="${STEADY_DBCACHE_MB:-400}"
DBCACHE_MB="${DBCACHE_MB:-${STEADY_DBCACHE_MB}}"
MAXMEMPOOL_MB="${MAXMEMPOOL_MB:-50}"
PEERS_ON_MAXCONN="${PEERS_ON_MAXCONN:-32}"
BOOTSTRAP_IMPORT_TIMEOUT_S="${BOOTSTRAP_IMPORT_TIMEOUT_S:-21600}" # 6h max per coin
BOOTSTRAP_IMPORT_SLEEP_S="${BOOTSTRAP_IMPORT_SLEEP_S:-60}"
BOOTSTRAP_DOWNLOAD_ATTEMPTS="${BOOTSTRAP_DOWNLOAD_ATTEMPTS:-12}"
BOOTSTRAP_DOWNLOAD_RETRY_SLEEP_S="${BOOTSTRAP_DOWNLOAD_RETRY_SLEEP_S:-60}"
BOOTSTRAP_DOWNLOAD_CONNECT_TIMEOUT_S="${BOOTSTRAP_DOWNLOAD_CONNECT_TIMEOUT_S:-30}"
BOOTSTRAP_DOWNLOAD_READ_TIMEOUT_S="${BOOTSTRAP_DOWNLOAD_READ_TIMEOUT_S:-90}"
BOOTSTRAP_POST_IMPORT_CHECK_TIMEOUT_S="${BOOTSTRAP_POST_IMPORT_CHECK_TIMEOUT_S:-3600}"
BOOTSTRAP_POST_IMPORT_STALL_TIMEOUT_S="${BOOTSTRAP_POST_IMPORT_STALL_TIMEOUT_S:-300}"
BOOTSTRAP_SERIES="${BOOTSTRAP_SERIES:-25.2}"
BOOTSTRAP_URL="${BOOTSTRAP_URL:-https://bootstrap.blakestream.io}"
BOOTSTRAP_CANONICAL_HOST="${BOOTSTRAP_CANONICAL_HOST:-bootstrap.blakestream.io}"
BOOTSTRAP_MIRROR_DISCOVERY="${BOOTSTRAP_MIRROR_DISCOVERY:-1}"
BOOTSTRAP_MIRROR_HOST="${BOOTSTRAP_MIRROR_HOST:-}"
TIP_CATCH_TIMEOUT_S="${TIP_CATCH_TIMEOUT_S:-7200}"  # 2h max waiting for tip catch-up
TIP_CATCH_LAG="${TIP_CATCH_LAG:-5}"
START_AFTER="${START_AFTER:-1}"
MPOS_DOCKER_HUB="${MPOS_DOCKER_HUB:-sidgrip}"
MPOS_IMAGE_TAG="${MPOS_IMAGE_TAG:-25.2}"
DASHBOARD_STATUS_DIR="${DASHBOARD_STATUS_DIR:-/var/run/mpos-sync}"
DASHBOARD_SNAPSHOT_INTERVAL_S="${DASHBOARD_SNAPSHOT_INTERVAL_S:-60}"

# tmpfs chainstate (opt-in, EXPERIMENTAL). When MPOS_TMPFS_CHAINSTATE=1
# the bootstrap rotation mounts a tmpfs over each coin's chainstate
# directory before starting the daemon. The daemon's UTXO LevelDB ops
# stay in RAM during the heavy import + catch-up phase. A background
# checkpoint loop rsyncs the tmpfs to a disk shadow every
# TMPFS_CHECKPOINT_INTERVAL_S so a crash doesn't undo all progress.
# On stop the final flush copies tmpfs -> shadow -> real disk path and
# the tmpfs is unmounted; subsequent (steady-state) starts use plain
# disk paths.
MPOS_TMPFS_CHAINSTATE="${MPOS_TMPFS_CHAINSTATE:-0}"
TMPFS_SHADOW_ROOT="${TMPFS_SHADOW_ROOT:-/var/lib/mpos-tmpfs-shadow}"
TMPFS_CHECKPOINT_INTERVAL_S="${TMPFS_CHECKPOINT_INTERVAL_S:-300}"
TMPFS_CHAINSTATE_SIZE_MB="${TMPFS_CHAINSTATE_SIZE_MB:-6000}"
TMPFS_BLOCKS_INDEX_SIZE_MB="${TMPFS_BLOCKS_INDEX_SIZE_MB:-512}"

# write_status <coin> <STATE> [h] [t] [d]
# STATE one of: QUEUED, DOWNLOADING, DECOMPRESSING, STAGED, IMPORTING,
# SYNCING, FINISHED, FAILED.
# Atomic write via mv-from-tmp so the dashboard renderer never reads a
# partial line.
write_status() {
    local coin="$1" state="$2" h="${3:-}" t="${4:-}" d="${5:-}"
    mkdir -p "$DASHBOARD_STATUS_DIR" 2>/dev/null || true
    local tmp="${DASHBOARD_STATUS_DIR}/.${coin}.status.tmp"
    local final="${DASHBOARD_STATUS_DIR}/${coin}.status"
    printf '%s|%s|%s|%s\n' "$state" "$h" "$t" "$d" > "$tmp" 2>/dev/null \
        && mv -f "$tmp" "$final" 2>/dev/null || true
}

coin_image() {
    local coin="$1"
    printf '%s/%s:%s' "$MPOS_DOCKER_HUB" "${COIN_IMAGE_NAME[$coin]}" "$MPOS_IMAGE_TAG"
}

# ---- tmpfs chainstate helpers (only used when MPOS_TMPFS_CHAINSTATE=1) ----
#
# WARNING (Bitcoin Core 0.15.x): LevelDB chainstate is NOT crash-consistent
# across partial writes on this branch. If the host OOMs or the daemon
# segfaults mid-import, the tmpfs vanishes and the rsync shadow holds at
# most the last TMPFS_CHECKPOINT_INTERVAL_S of progress. On restart, the
# daemon's "load block index" phase will see a chainstate whose tip
# disagrees with blocks/blk*.dat on disk and force a FULL REINDEX — i.e.
# partial chainstate is WORSE than no chainstate. Mitigation: keep this
# feature default-off; only enable on hosts where the rotation can survive
# a one-off full reindex of a single coin. Bitcoin Core 24.0+ adds proper
# atomic flush + assumeutxo; revisit this whole feature when we rebase to
# 25.2.
tmpfs_setup() {
    # Mount tmpfs over <datadir>/chainstate + <datadir>/blocks/index
    # BEFORE the daemon container starts. Docker's bind-mount sees
    # the tmpfs because mounts inside the bind are transparent when
    # the bind is set up afterwards (and the daemon's `-v` mount is
    # done by start_one *after* this returns).
    [ "$MPOS_TMPFS_CHAINSTATE" = "1" ] || return 0
    local coin="$1" datadir="${COIN_DATADIR[$coin]}"
    local cs="${datadir}/chainstate"
    local idx="${datadir}/blocks/index"
    local shadow="${TMPFS_SHADOW_ROOT}/${coin}"
    mkdir -p "$cs" "$idx" "${shadow}/chainstate" "${shadow}/blocks/index"
    if ! mountpoint -q "$cs"; then
        say "  [tmpfs] mounting tmpfs (${TMPFS_CHAINSTATE_SIZE_MB}M) -> ${cs}"
        mount -t tmpfs -o "size=${TMPFS_CHAINSTATE_SIZE_MB}M" tmpfs "$cs"
    fi
    if ! mountpoint -q "$idx"; then
        mount -t tmpfs -o "size=${TMPFS_BLOCKS_INDEX_SIZE_MB}M" tmpfs "$idx"
    fi
    # Restore from disk shadow if present (crash recovery)
    if [ -n "$(ls -A "${shadow}/chainstate" 2>/dev/null)" ]; then
        say "  [tmpfs] restoring chainstate from shadow"
        rsync -a "${shadow}/chainstate/" "${cs}/"
    fi
    if [ -n "$(ls -A "${shadow}/blocks/index" 2>/dev/null)" ]; then
        rsync -a "${shadow}/blocks/index/" "${idx}/"
    fi
}

tmpfs_checkpoint() {
    [ "$MPOS_TMPFS_CHAINSTATE" = "1" ] || return 0
    local coin="$1" datadir="${COIN_DATADIR[$coin]}"
    local shadow="${TMPFS_SHADOW_ROOT}/${coin}"
    rsync -a --delete "${datadir}/chainstate/"  "${shadow}/chainstate/"  2>/dev/null || true
    rsync -a --delete "${datadir}/blocks/index/" "${shadow}/blocks/index/" 2>/dev/null || true
}

tmpfs_finalize() {
    # Daemon must already be stopped before this runs. Copies tmpfs ->
    # shadow -> real disk, then unmounts.
    [ "$MPOS_TMPFS_CHAINSTATE" = "1" ] || return 0
    local coin="$1" datadir="${COIN_DATADIR[$coin]}"
    local cs="${datadir}/chainstate"
    local idx="${datadir}/blocks/index"
    local shadow="${TMPFS_SHADOW_ROOT}/${coin}"
    say "  [tmpfs] final checkpoint + unmount for ${coin}"
    tmpfs_checkpoint "$coin"
    if mountpoint -q "$cs";  then umount "$cs";  fi
    if mountpoint -q "$idx"; then umount "$idx"; fi
    # Restore shadow contents -> real disk path so the next start uses disk
    mkdir -p "$cs" "$idx"
    rsync -a --delete "${shadow}/chainstate/"  "${cs}/"
    rsync -a --delete "${shadow}/blocks/index/" "${idx}/"
}

# ---- helpers ----------------------------------------------------------------
ensure_caps() {
    # Always SET dbcache/maxmempool to the currently-effective values.
    # Old behaviour was append-if-missing only — now we update existing
    # lines too, so bootstrap_one can flip dbcache between a boosted
    # value for fresh-import (4000) and steady-state (400).
    local conf="$1"
    if grep -q "^dbcache=" "$conf"; then
        sed -i "s/^dbcache=.*/dbcache=${DBCACHE_MB}/" "$conf"
    else
        echo "dbcache=${DBCACHE_MB}" >> "$conf"
    fi
    if grep -q "^maxmempool=" "$conf"; then
        sed -i "s/^maxmempool=.*/maxmempool=${MAXMEMPOOL_MB}/" "$conf"
    else
        echo "maxmempool=${MAXMEMPOOL_MB}" >> "$conf"
    fi
}

set_peers() {
    # set_peers <conf> <on|off>
    local conf="$1" mode="$2"
    if [ "$mode" = "off" ]; then
        sed -i 's/^listen=.*/listen=0/'         "$conf" || true
        sed -i 's/^maxconnections=.*/maxconnections=0/' "$conf" || true
        grep -q "^listen=" "$conf"        || echo "listen=0" >> "$conf"
        grep -q "^maxconnections=" "$conf" || echo "maxconnections=0" >> "$conf"
    else
        sed -i 's/^listen=.*/listen=1/'         "$conf" || true
        sed -i "s/^maxconnections=.*/maxconnections=${PEERS_ON_MAXCONN}/" "$conf" || true
        grep -q "^listen=" "$conf"        || echo "listen=1" >> "$conf"
        grep -q "^maxconnections=" "$conf" || echo "maxconnections=${PEERS_ON_MAXCONN}" >> "$conf"
    fi
}

stop_all() {
    # One-shot re-run safety sweep at the top of the rotation: clears any
    # daemon a previous interrupted deploy may have left running. Quiet
    # by default since the rotation itself only ever runs one coin at a
    # time — per-coin stops use stop_one with a coin-named message.
    say "sweeping any leftover daemon containers (re-run safety)"
    for c in blc pho bbtc elt umo lit; do
        docker stop "$c" >/dev/null 2>&1 || true
        docker rm   "$c" >/dev/null 2>&1 || true
    done
}

stop_one() {
    # Graceful stop: SIGTERM via `docker stop` (not `rm -f`) so the
    # daemon's shutdown handler runs FlushStateToDisk(FLUSH_STATE_ALWAYS)
    # before exit. With --stop-timeout 300 the container has 5 min to
    # finish flushing. After it exits cleanly, remove the container.
    # `docker rm -f` here is unsafe because it can SIGKILL mid-flush
    # and leave chainstate behind by 100k+ blocks; we observed PHO and
    # BBTC rollback to chainstate flush points months in the past
    # because of this on 2026-04-27.
    say "stopping ${1} container gracefully"
    docker stop "$1" >/dev/null 2>&1 || true
    docker rm   "$1" >/dev/null 2>&1 || true
}

mark_bootstrap_consumed() {
    local coin="$1"
    local bootstrap_file="${COIN_DATADIR[$coin]}/bootstrap.dat"
    if [ -f "$bootstrap_file" ]; then
        mv -f "$bootstrap_file" "${bootstrap_file}.old"
        if [ -f "${bootstrap_file}.height" ]; then
            mv -f "${bootstrap_file}.height" "${bootstrap_file}.old.height"
        fi
        ok "  ${coin}: bootstrap.dat moved to bootstrap.dat.old after -loadblock import"
    fi
}

bootstrap_base_for_host() {
    printf 'https://%s/%s' "$1" "$BOOTSTRAP_SERIES"
}

bootstrap_base_from_url() {
    local url="${1%/}"
    case "$url" in
        */"$BOOTSTRAP_SERIES") printf '%s' "$url" ;;
        *) printf '%s/%s' "$url" "$BOOTSTRAP_SERIES" ;;
    esac
}

pick_25_2_mirror() {
    local fallback="$BOOTSTRAP_CANONICAL_HOST"
    local registry_url
    registry_url="$(bootstrap_base_for_host "$fallback")/mirrors.json"

    if [ -n "$BOOTSTRAP_MIRROR_HOST" ]; then
        echo "$BOOTSTRAP_MIRROR_HOST"
        return 0
    fi
    if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
        echo "$fallback"
        return 0
    fi

    local registry
    registry=$(curl -fsS --max-time 3 "$registry_url" 2>/dev/null) || {
        echo "$fallback"
        return 0
    }

    local load_penalty probe_timeout_ms probe_timeout_s
    load_penalty=$(printf '%s' "$registry" | jq -r '.load_penalty_ms // 800' 2>/dev/null) || {
        echo "$fallback"
        return 0
    }
    probe_timeout_ms=$(printf '%s' "$registry" | jq -r '.probe_timeout_ms // 1500' 2>/dev/null || echo 1500)
    [[ "$load_penalty" =~ ^[0-9]+$ ]] || load_penalty=800
    [[ "$probe_timeout_ms" =~ ^[0-9]+$ ]] || probe_timeout_ms=1500
    probe_timeout_s=$(awk -v ms="$probe_timeout_ms" 'BEGIN { printf "%.3f", ms / 1000 }')

    local tmpdir
    tmpdir=$(mktemp -d)
    local hosts=()
    mapfile -t hosts < <(printf '%s' "$registry" | jq -r '.mirrors[].host' 2>/dev/null || true)
    if [ "${#hosts[@]}" -eq 0 ]; then
        rm -rf "$tmpdir"
        echo "$fallback"
        return 0
    fi

    local pids=() host
    for host in "${hosts[@]}"; do
        [[ "$host" =~ ^[A-Za-z0-9.-]+$ ]] || continue
        (
            set +e
            start=$(date +%s%3N)
            probe=$(curl -fsS --max-time "$probe_timeout_s" "https://${host}/probe.json" 2>/dev/null) || exit 0
            end=$(date +%s%3N)
            rtt=$((end - start))
            active=$(printf '%s' "$probe" | jq -r '.active // 0' 2>/dev/null) || exit 0
            limit=$(printf '%s' "$probe" | jq -r '.limit // 20' 2>/dev/null) || exit 0
            [[ "$active" =~ ^[0-9]+$ ]] || active=0
            [[ "$limit" =~ ^[0-9]+$ ]] || limit=20
            [ "$limit" -gt 0 ] || limit=20
            sat_pct=$((active * 100 / limit))
            score=$((rtt + sat_pct * load_penalty / 100))
            safe_host=${host//[^A-Za-z0-9._-]/_}
            printf '%s\t%s\t%s\t%s\t%s\n' "$score" "$host" "$rtt" "$active" "$limit" > "${tmpdir}/${safe_host}.score"
        ) &
        pids+=($!)
    done
    local pid
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done

    local best
    best=$(cat "${tmpdir}"/*.score 2>/dev/null | sort -n -k1,1 | head -1 || true)
    rm -rf "$tmpdir"
    if [ -z "$best" ]; then
        echo "$fallback"
        return 0
    fi
    printf '%s\n' "$best" | awk -F '\t' '{print $2}'
}

fetch_bootstrap_index() {
    local base="$1"
    curl -fsS --max-time 10 "${base%/}/" 2>/dev/null
}

bootstrap_remote_file() {
    local coin="$1"
    local prefix="${BOOTSTRAP_PREFIX[$coin]}"
    printf '%s' "$BOOTSTRAP_INDEX_HTML" \
        | sed -nE "s/.*href=[\"'](${prefix}-bootstrap-[0-9]+\\.dat\\.xz)[\"'].*/\\1/p" \
        | sort -V \
        | tail -1
}

bootstrap_height_from_filename() {
    local remote_file="$1"
    sed -nE 's/.*-bootstrap-([0-9]+)\.dat\.xz$/\1/p' <<<"$remote_file"
}

bootstrap_height_file() {
    local coin="$1"
    printf '%s/bootstrap.dat.height' "${COIN_DATADIR[$coin]}"
}

record_bootstrap_height() {
    local coin="$1" remote_file="$2" height
    height="$(bootstrap_height_from_filename "$remote_file")"
    if [[ "$height" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$height" > "$(bootstrap_height_file "$coin")"
    fi
}

expected_bootstrap_height() {
    local coin="$1" file height
    file="$(bootstrap_height_file "$coin")"
    [ -f "$file" ] || return 0
    height="$(head -1 "$file" 2>/dev/null | tr -d '[:space:]' || true)"
    [[ "$height" =~ ^[0-9]+$ ]] && printf '%s\n' "$height"
}

init_bootstrap_source() {
    local default_url="https://${BOOTSTRAP_CANONICAL_HOST}"
    local base host index

    if [ "$BOOTSTRAP_MIRROR_DISCOVERY" = "1" ] && [ "${BOOTSTRAP_URL%/}" = "$default_url" ]; then
        host=$(pick_25_2_mirror)
        base="$(bootstrap_base_for_host "$host")"
        say "using ${BOOTSTRAP_SERIES} bootstrap mirror: ${host}"
    else
        base="$(bootstrap_base_from_url "$BOOTSTRAP_URL")"
        say "using ${BOOTSTRAP_SERIES} bootstrap base: ${base}"
    fi

    if ! index=$(fetch_bootstrap_index "$base"); then
        local fallback_base
        fallback_base="$(bootstrap_base_for_host "$BOOTSTRAP_CANONICAL_HOST")"
        warn "  bootstrap index failed at ${base}; falling back to ${fallback_base}"
        base="$fallback_base"
        index=$(fetch_bootstrap_index "$base") || {
            warn "  unable to fetch bootstrap index from ${base}"
            return 1
        }
    fi

    BOOTSTRAP_SELECTED_BASE="${base%/}"
    BOOTSTRAP_FALLBACK_BASE="$(bootstrap_base_for_host "$BOOTSTRAP_CANONICAL_HOST")"
    BOOTSTRAP_INDEX_HTML="$index"
    export BOOTSTRAP_SELECTED_BASE BOOTSTRAP_FALLBACK_BASE BOOTSTRAP_INDEX_HTML
}

remote_content_length() {
    local url="$1"
    wget --spider --server-response --tries=1 \
        --connect-timeout="$BOOTSTRAP_DOWNLOAD_CONNECT_TIMEOUT_S" \
        --read-timeout="$BOOTSTRAP_DOWNLOAD_READ_TIMEOUT_S" \
        "$url" 2>&1 \
        | awk '
            /^  HTTP\// { ok = ($2 ~ /^2/); next }
            ok && tolower($0) ~ /content-length:/ { print $2 }
        ' \
        | tr -d '\r' \
        | tail -1 \
        || true
}

download_verified_xz() {
    local coin="$1" base="$2" remote_file="$3"
    local datadir="${COIN_DATADIR[$coin]}"
    local xz_file="${datadir}/${remote_file}"
    local xz_tmp="${xz_file}.tmp"
    local sha_file="${xz_file}.sha256"
    local sha_tmp="${sha_file}.tmp"
    local file_url="${base%/}/${remote_file}"
    local sha_url="${file_url}.sha256"
    local expected_size actual_size attempt

    expected_size=$(remote_content_length "$file_url")
    if [[ "$expected_size" =~ ^[0-9]+$ ]]; then
        write_status "$coin" "DOWNLOADING" "0" "$expected_size" "--"
    fi

    for attempt in $(seq 1 "$BOOTSTRAP_DOWNLOAD_ATTEMPTS"); do
        if [ -f "$xz_tmp" ] && [[ "$expected_size" =~ ^[0-9]+$ ]]; then
            actual_size=$(stat -c '%s' "$xz_tmp" 2>/dev/null || echo 0)
            if [ "$actual_size" -gt "$expected_size" ]; then
                warn "  ${coin}: partial ${remote_file} is larger than expected; restarting download"
                rm -f "$xz_tmp"
            fi
        fi

        if wget --continue --tries=1 \
            --connect-timeout="$BOOTSTRAP_DOWNLOAD_CONNECT_TIMEOUT_S" \
            --read-timeout="$BOOTSTRAP_DOWNLOAD_READ_TIMEOUT_S" \
            --progress=bar:force \
            -O "$xz_tmp" "$file_url" \
            && wget --tries=1 \
                --connect-timeout="$BOOTSTRAP_DOWNLOAD_CONNECT_TIMEOUT_S" \
                --read-timeout="$BOOTSTRAP_DOWNLOAD_READ_TIMEOUT_S" \
                -O "$sha_tmp" "$sha_url"; then

            if [[ "$expected_size" =~ ^[0-9]+$ ]]; then
                actual_size=$(stat -c '%s' "$xz_tmp" 2>/dev/null || echo 0)
                if [ "$actual_size" != "$expected_size" ]; then
                    warn "  ${coin}: downloaded ${remote_file} is ${actual_size} bytes; expected ${expected_size}"
                    if [ "$attempt" -lt "$BOOTSTRAP_DOWNLOAD_ATTEMPTS" ]; then
                        sleep "$BOOTSTRAP_DOWNLOAD_RETRY_SLEEP_S"
                        continue
                    fi
                    return 1
                fi
            fi

            mv -f "$xz_tmp" "$xz_file"
            mv -f "$sha_tmp" "$sha_file"
            if ( cd "$datadir" && sha256sum -c "$(basename "$sha_file")" >/dev/null ); then
                ok "  ${coin}: verified ${remote_file}"
                return 0
            fi
            warn "  ${coin}: SHA256 mismatch on ${remote_file}"
            rm -f "$xz_file" "$sha_file"
            return 2
        fi

        if [ "$attempt" -lt "$BOOTSTRAP_DOWNLOAD_ATTEMPTS" ]; then
            warn "  ${coin}: bootstrap download attempt ${attempt}/${BOOTSTRAP_DOWNLOAD_ATTEMPTS} failed; retrying in ${BOOTSTRAP_DOWNLOAD_RETRY_SLEEP_S}s"
            sleep "$BOOTSTRAP_DOWNLOAD_RETRY_SLEEP_S"
        fi
    done

    return 1
}

decompress_bootstrap_xz() {
    local coin="$1" remote_file="$2"
    local datadir="${COIN_DATADIR[$coin]}"
    local xz_file="${datadir}/${remote_file}"
    local sha_file="${xz_file}.sha256"
    local bootstrap_file="${datadir}/bootstrap.dat"
    local bootstrap_tmp="${bootstrap_file}.tmp"

    say "  decompressing ${coin} ${remote_file} -> bootstrap.dat"
    write_status "$coin" "DECOMPRESSING" "0" "0" "0"
    rm -f "$bootstrap_tmp"
    if xz -dc "$xz_file" > "$bootstrap_tmp"; then
        mv -f "$bootstrap_tmp" "$bootstrap_file"
        record_bootstrap_height "$coin" "$remote_file"
        rm -f "$xz_file" "$sha_file"
        local sz_final
        sz_final=$(stat -c '%s' "$bootstrap_file" 2>/dev/null || echo 0)
        ok "  ${coin}: bootstrap.dat staged ($(du -h "$bootstrap_file" | cut -f1))"
        write_status "$coin" "STAGED" "$sz_final" "$sz_final" "0"
        return 0
    fi
    write_status "$coin" "FAILED" "0" "0" "0"
    rm -f "$bootstrap_tmp"
    warn "  ${coin}: xz decompression failed for ${remote_file}"
    return 1
}

download_bootstrap() {
    local coin="$1"
    local datadir="${COIN_DATADIR[$coin]}"
    local bootstrap_file="${datadir}/bootstrap.dat"
    local remote_file xz_file sha_file
    write_status "$coin" "DOWNLOADING" "0" "0" "--"

    if [ ! -f "$bootstrap_file" ] && [ -f "${bootstrap_file}.old" ]; then
        ok "  ${coin}: bootstrap.dat already consumed as bootstrap.dat.old ($(du -h "${bootstrap_file}.old" | cut -f1))"
        local sz_old
        sz_old=$(stat -c '%s' "${bootstrap_file}.old" 2>/dev/null || echo 0)
        write_status "$coin" "STAGED" "$sz_old" "$sz_old" "0"
        return 0
    fi

    if [ -f "$bootstrap_file" ]; then
        ok "  ${coin}: bootstrap.dat already present ($(du -h "$bootstrap_file" | cut -f1))"
        local sz_existing
        sz_existing=$(stat -c '%s' "$bootstrap_file" 2>/dev/null || echo 0)
        write_status "$coin" "STAGED" "$sz_existing" "$sz_existing" "0"
        return 0
    fi

    remote_file=$(bootstrap_remote_file "$coin")
    if [ -z "$remote_file" ]; then
        warn "  ${coin}: no ${BOOTSTRAP_PREFIX[$coin]} bootstrap found in ${BOOTSTRAP_SELECTED_BASE}/"
        write_status "$coin" "FAILED" "0" "0" "0"
        return 1
    fi
    xz_file="${datadir}/${remote_file}"
    sha_file="${xz_file}.sha256"

    if [ -f "$xz_file" ] && [ -f "$sha_file" ]; then
        if ( cd "$datadir" && sha256sum -c "$(basename "$sha_file")" >/dev/null ); then
            ok "  ${coin}: ${remote_file} already present and verified"
            decompress_bootstrap_xz "$coin" "$remote_file"
            return $?
        fi
        warn "  ${coin}: cached ${remote_file} failed SHA256; redownloading"
        rm -f "$xz_file" "$sha_file"
    fi

    say "  downloading ${coin} ${remote_file} from ${BOOTSTRAP_SELECTED_BASE}"
    if ! download_verified_xz "$coin" "$BOOTSTRAP_SELECTED_BASE" "$remote_file"; then
        if [ "$BOOTSTRAP_SELECTED_BASE" != "$BOOTSTRAP_FALLBACK_BASE" ]; then
            warn "  ${coin}: retrying ${remote_file} on canonical fallback ${BOOTSTRAP_FALLBACK_BASE}"
            rm -f "$xz_file" "$xz_file.tmp" "$sha_file" "$sha_file.tmp"
            download_verified_xz "$coin" "$BOOTSTRAP_FALLBACK_BASE" "$remote_file" || {
                warn "  ${coin}: fallback download failed"
                write_status "$coin" "FAILED" "0" "0" "0"
                return 1
            }
        else
            warn "  ${coin}: bootstrap download failed"
            write_status "$coin" "FAILED" "0" "0" "0"
            return 1
        fi
    fi

    decompress_bootstrap_xz "$coin" "$remote_file"
}

start_one() {
    local coin="$1"
    local loadblock="${2:-0}"
    local datadir="${COIN_DATADIR[$coin]}"
    local daemon="${COIN_DAEMON[$coin]}"
    local bootstrap_file="${datadir}/bootstrap.dat"
    local loadblock_arg=""
    local image
    image="$(coin_image "$coin")"
    if [ "$loadblock" = "1" ]; then
        [ -f "$bootstrap_file" ] || {
            warn "  ${coin}: missing ${bootstrap_file}; cannot start with -loadblock"
            return 1
        }
        loadblock_arg=" -loadblock=${bootstrap_file}"
    fi
    docker run -d \
        --name "$coin" \
        --user 0:0 \
        --net=host \
        --restart=unless-stopped \
        --stop-timeout 300 \
        --entrypoint /bin/sh \
        -v "${datadir}:${datadir}" \
        "$image" \
        -lc "mkdir -p ${datadir} && touch ${datadir}/debug.log && chmod 644 ${datadir}/debug.log && exec /usr/local/bin/${daemon} -datadir=${datadir}${loadblock_arg}" \
        >/dev/null
}

current_height() {
    local datadir="$1"
    grep "UpdateTip" "${datadir}/debug.log" 2>/dev/null \
        | tail -1 \
        | grep -oE "height=[0-9]+" \
        | head -1 \
        | cut -d= -f2 \
        || true
}

bootstrap_import_height() {
    local datadir="$1"
    grep "Leaving block file" "${datadir}/debug.log" 2>/dev/null \
        | tail -1 \
        | sed -n 's/.*heights=[0-9][0-9]*\.\.\.\([0-9][0-9]*\).*/\1/p' \
        || true
}

peer_chain_tip() {
    local datadir="$1"
    grep -oE "blocks=[0-9]+" "${datadir}/debug.log" 2>/dev/null \
        | sort -t= -k2 -n \
        | tail -1 \
        | cut -d= -f2 \
        || true
}

rpc_height() {
    local coin="$1" datadir="$2"
    local cli="${COIN_CLI[$coin]}"
    docker exec "$coin" "/usr/local/bin/${cli}" -datadir="$datadir" getblockcount 2>/dev/null \
        | tail -1 \
        | tr -cd '0-9' \
        || true
}

rpc_peer_tip() {
    local coin="$1" datadir="$2"
    local cli="${COIN_CLI[$coin]}"
    docker exec "$coin" "/usr/local/bin/${cli}" -datadir="$datadir" getpeerinfo 2>/dev/null \
        | sed -n 's/.*"\(startingheight\|synced_headers\|synced_blocks\)"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\2/p' \
        | sort -n \
        | tail -1 \
        || true
}

verify_bootstrap_import_height() {
    local coin="$1" datadir="$2" expected deadline h now last_h last_progress_ts stalled last_log_ts
    expected="$(expected_bootstrap_height "$coin")"
    if [ -z "$expected" ]; then
        warn "  ${coin}: no bootstrap height metadata found; skipping post-import height check"
        return 0
    fi

    deadline=$(( $(date +%s) + BOOTSTRAP_POST_IMPORT_CHECK_TIMEOUT_S ))
    h=0
    last_h=0
    last_progress_ts=$(date +%s)
    last_log_ts=0
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if ! docker ps --filter "name=^${coin}$" --format '{{.Status}}' | grep -q '^Up'; then
            warn "  ${coin}: container exited before post-import height check completed"
            docker logs "$coin" --tail 50 2>&1 || true
            return 1
        fi

        h=$(rpc_height "$coin" "$datadir")
        [ -n "$h" ] || h=$(current_height "$datadir")
        h="${h:-0}"
        now=$(date +%s)
        if [[ "$h" =~ ^[0-9]+$ ]] && [ "$h" -gt "$last_h" ]; then
            last_h="$h"
            last_progress_ts="$now"
        fi
        write_status "$coin" "IMPORTING" "$h" "$expected" "0"
        if [[ "$h" =~ ^[0-9]+$ ]] && [ "$h" -ge "$expected" ]; then
            ok "  ${coin}: bootstrap height check passed (height=${h}, expected>=${expected})"
            return 0
        fi

        stalled=$(( now - last_progress_ts ))
        if [ "$stalled" -ge "$BOOTSTRAP_POST_IMPORT_STALL_TIMEOUT_S" ]; then
            warn "  ${coin}: post-import height stalled at ${h} for ${stalled}s (expected>=${expected})"
            return 1
        fi

        if [ "$last_log_ts" -eq 0 ] || [ $(( now - last_log_ts )) -ge "$DASHBOARD_SNAPSHOT_INTERVAL_S" ]; then
            if [ "$stalled" -gt 0 ]; then
                printf '   [%s] %-5s importing bootstrap height=%s/%s (no height change for %ss)\n' \
                    "$(date +%H:%M:%S)" "${coin}:" "$h" "$expected" "$stalled"
            else
                printf '   [%s] %-5s importing bootstrap height=%s/%s\n' \
                    "$(date +%H:%M:%S)" "${coin}:" "$h" "$expected"
            fi
            last_log_ts="$now"
        fi
        sleep 10
    done

    warn "  ${coin}: post-import height ${h:-0} stayed below bootstrap height ${expected} after ${BOOTSTRAP_POST_IMPORT_CHECK_TIMEOUT_S}s"
    return 1
}

wait_bootstrap_import_done() {
    # Wait for the daemon to finish LoadExternalBlockFile bootstrap.dat
    # import. Do not infer this from UpdateTip height stability: while
    # bootstrap.dat is being read, debug.log may show "Leaving block
    # file ... heights=A...B" progress for millions of blocks while the
    # last UpdateTip line remains unchanged.
    local coin="$1" datadir="$2"
    local debug_log="${datadir}/debug.log"
    local deadline=$(( $(date +%s) + BOOTSTRAP_IMPORT_TIMEOUT_S ))
    local saw_import=0

    while [ "$(date +%s)" -lt "$deadline" ]; do
        if grep -Eq "Importing (bootstrap.dat|blocks file .*bootstrap.dat)" "$debug_log" 2>/dev/null; then
            saw_import=1
        fi
        if grep -Eq "Loaded [0-9]+ blocks from external file" "$debug_log" 2>/dev/null; then
            return 0
        fi
        if [ "$saw_import" = "1" ] \
                && [ ! -f "${datadir}/bootstrap.dat" ] \
                && [ -f "${datadir}/bootstrap.dat.old" ]; then
            return 0
        fi
        if ! docker ps --filter "name=^${coin}$" --format '{{.Status}}' \
                | grep -q '^Up'; then
            warn "  ${coin}: container exited before bootstrap import completed"
            docker logs "$coin" --tail 50 2>&1 || true
            return 1
        fi

        local h import_h last_line
        h=$(current_height "$datadir"); h="${h:-0}"
        import_h=$(bootstrap_import_height "$datadir"); import_h="${import_h:-0}"
        last_line=$(tail -1 "$debug_log" 2>/dev/null | cut -c1-120 || true)
        printf '   [%s] chain_height=%s  imported_to=%s  %s\n' \
            "$(date +%H:%M:%S)" "$h" "$import_h" "${last_line:-waiting for debug.log}"
        sleep "$BOOTSTRAP_IMPORT_SLEEP_S"
    done

    warn "  ${coin}: bootstrap.dat import timed out after ${BOOTSTRAP_IMPORT_TIMEOUT_S}s"
    return 1
}

wait_at_tip() {
    # Returns only when local height is within TIP_CATCH_LAG blocks of the
    # peer-reported tip. A peer tip a few blocks lower than local can happen
    # while new blocks arrive, but a stale peer tip far below local height is
    # not proof that the daemon is synced.
    local coin="$1" datadir="$2"
    local deadline=$(( $(date +%s) + TIP_CATCH_TIMEOUT_S ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        sleep 30
        local h tip delta abs_delta
        h=$(rpc_height "$coin" "$datadir")
        [ -n "$h" ] || h=$(current_height "$datadir")
        h="${h:-0}"
        tip=$(rpc_peer_tip "$coin" "$datadir")
        [ -n "$tip" ] || tip=$(peer_chain_tip "$datadir")
        tip="${tip:-0}"
        delta=$((tip - h))
        abs_delta="${delta#-}"
        printf '   [%s] %-5s height=%-12s peer_tip=%-12s delta=%s\n' \
            "$(date +%H:%M:%S)" "${coin}:" "$h" "$tip" "$delta"
        write_status "$coin" "SYNCING" "$h" "$tip" "$delta"
        if [ "$h" -gt 0 ] \
                && [ "$tip" -gt 0 ] \
                && [ "$abs_delta" -le "$TIP_CATCH_LAG" ]; then
            write_status "$coin" "FINISHED" "$h" "$tip" "0"
            return 0
        fi
    done
    write_status "$coin" "FAILED" "${h:-0}" "${tip:-0}" "${delta:-0}"
    warn "  tip catch-up timed out after ${TIP_CATCH_TIMEOUT_S}s"
    return 1
}

bootstrap_group() {
    # Sync a group of coins concurrently — start all, wait for all to
    # reach tip, then either stop+flush+drop-dbcache (fresh import) or
    # leave running (resumed from .old). Single-coin group is the same
    # path as the historical bootstrap_one, just generalised.
    local coins=("$@")
    [ ${#coins[@]} -eq 0 ] && return 0

    say "===== group: ${coins[*]} ====="

    local -A CONSUMED
    local coin datadir conf bootstrap_file
    for coin in "${coins[@]}"; do
        datadir="${COIN_DATADIR[$coin]}"
        conf="${datadir}/${COIN_CONF[$coin]}"
        bootstrap_file="${datadir}/bootstrap.dat"
        [ -f "$conf" ] || { warn "missing $conf — skip ${coin}"; continue; }

        CONSUMED[$coin]=0
        if [ ! -f "$bootstrap_file" ] && [ -f "${bootstrap_file}.old" ]; then
            CONSUMED[$coin]=1
        fi

        if [ "${CONSUMED[$coin]}" = "1" ]; then
            DBCACHE_MB="${STEADY_DBCACHE_MB}" ensure_caps "$conf"
        else
            DBCACHE_MB="${BOOTSTRAP_DBCACHE_MB}" ensure_caps "$conf"
            say "  using dbcache=${BOOTSTRAP_DBCACHE_MB}MB for fresh bootstrap import of ${coin}"
        fi
        set_peers "$conf" on
    done

    # tmpfs chainstate: opt-in, only meaningful for fresh imports (the
    # heavy validation phase). Resumed coins use disk-backed chainstate
    # as usual to avoid unmount/restore overhead.
    local -A TMPFS_CHECKPOINT_PID=()
    for coin in "${coins[@]}"; do
        [ -z "${CONSUMED[$coin]:-}" ] && continue
        if [ "${CONSUMED[$coin]}" = "0" ] && [ "$MPOS_TMPFS_CHAINSTATE" = "1" ]; then
            tmpfs_setup "$coin"
            # Background checkpoint loop for this coin
            (
                trap - EXIT
                set +e
                while sleep "$TMPFS_CHECKPOINT_INTERVAL_S"; do
                    tmpfs_checkpoint "$coin"
                done
            ) &
            TMPFS_CHECKPOINT_PID[$coin]=$!
        fi
    done

    # Start every coin in the group concurrently.
    for coin in "${coins[@]}"; do
        [ -z "${CONSUMED[$coin]:-}" ] && continue
        if [ "${CONSUMED[$coin]}" = "1" ]; then
            start_one "$coin"
        else
            start_one "$coin" 1
        fi
        if [ "${CONSUMED[$coin]}" = "1" ]; then
            say "  started ${coin}; bootstrap.dat already consumed (resuming existing chainstate)"
        else
            say "  started ${coin}; daemon imports ${COIN_DATADIR[$coin]}/bootstrap.dat with -loadblock"
        fi
    done

    # Wait for each coin to reach tip. wait_at_tip blocks; coins ahead
    # of the current one simply finish earlier.
    for coin in "${coins[@]}"; do
        [ -z "${CONSUMED[$coin]:-}" ] && continue
        datadir="${COIN_DATADIR[$coin]}"
        if [ "${CONSUMED[$coin]}" = "0" ]; then
            wait_bootstrap_import_done "$coin" "$datadir"
            verify_bootstrap_import_height "$coin" "$datadir"
        fi
        wait_at_tip "$coin" "$datadir"
        local final_tip
        final_tip=$(current_height "$datadir")
        ok "  ${coin} reached height=${final_tip:-0}"
    done

    # Coins on a fresh import need a clean flush+stop. Coins resuming
    # from .old can stay running for the next group / Phase C.
    local need_stop=() coin_stop
    for coin_stop in "${coins[@]}"; do
        [ "${CONSUMED[$coin_stop]:-1}" = "0" ] && need_stop+=("$coin_stop")
    done
    if [ ${#need_stop[@]} -gt 0 ]; then
        say "  letting ${need_stop[*]} flush chainstate (60s) before stopping"
        sleep 60
        for coin_stop in "${need_stop[@]}"; do
            stop_one "$coin_stop"
            mark_bootstrap_consumed "$coin_stop"
            # If tmpfs chainstate was used for this coin, kill the
            # checkpoint loop, then move tmpfs contents -> real disk
            # path and unmount before the dbcache flip / next start.
            if [ -n "${TMPFS_CHECKPOINT_PID[$coin_stop]:-}" ]; then
                kill "${TMPFS_CHECKPOINT_PID[$coin_stop]}" 2>/dev/null || true
                unset 'TMPFS_CHECKPOINT_PID[$coin_stop]'
                tmpfs_finalize "$coin_stop"
            fi
            DBCACHE_MB="${STEADY_DBCACHE_MB}" ensure_caps \
                "${COIN_DATADIR[$coin_stop]}/${COIN_CONF[$coin_stop]}"
            ok "  ${coin_stop} stopped — dbcache dropped to ${STEADY_DBCACHE_MB}MB for steady state"
        done
    fi
    for coin in "${coins[@]}"; do
        if [ "${CONSUMED[$coin]:-0}" = "1" ]; then
            ok "  ${coin} stays running"
        fi
    done
}

# ---- main -------------------------------------------------------------------
PREFETCH_ONLY=0
case "${1:-}" in
    --prefetch|--download-only) PREFETCH_ONLY=1; shift ;;
esac

ROTATION=("$@")
[ ${#ROTATION[@]} -eq 0 ] && ROTATION=("${DEFAULT_ORDER[@]}")

if [ "$PREFETCH_ONLY" = "1" ]; then
    say "bootstrap prefetch (Phase A only): ${ROTATION[*]}"
else
    say "bootstrap rotation: ${ROTATION[*]}"
fi

# Resolve BOOTSTRAP_DBCACHE_MB. If unset and MPOS_ADAPTIVE_DBCACHE=1,
# size it from MemAvailable / SYNC_CONCURRENCY so smaller hosts shrink
# the cache automatically and bigger hosts get more.
SYNC_CONCURRENCY="${SYNC_CONCURRENCY:-2}"
if [ -z "${BOOTSTRAP_DBCACHE_MB:-}" ]; then
    if [ "$MPOS_ADAPTIVE_DBCACHE" = "1" ]; then
        mem_avail_mb=$(awk '/^MemAvailable:/ {print int($2/1024)}' /proc/meminfo)
        per_coin=$(( (mem_avail_mb - OS_HEADROOM_MB) / SYNC_CONCURRENCY ))
        [ "$per_coin" -lt "$BOOTSTRAP_DBCACHE_MIN_MB" ] && per_coin=$BOOTSTRAP_DBCACHE_MIN_MB
        [ "$per_coin" -gt "$BOOTSTRAP_DBCACHE_MAX_MB" ] && per_coin=$BOOTSTRAP_DBCACHE_MAX_MB
        BOOTSTRAP_DBCACHE_MB=$per_coin
        say "[dbcache] adaptive sizing: MemAvailable=${mem_avail_mb}MB, OS reserve=${OS_HEADROOM_MB}MB, pool=${SYNC_CONCURRENCY}, per-coin bootstrap dbcache=${BOOTSTRAP_DBCACHE_MB}MB (steady=${STEADY_DBCACHE_MB}MB)"
    else
        BOOTSTRAP_DBCACHE_MB=4000
        say "[dbcache] static fallback: bootstrap=${BOOTSTRAP_DBCACHE_MB}MB, steady=${STEADY_DBCACHE_MB}MB"
    fi
fi

# Dashboard: seed status files for every coin so the live-view tool
# can render rows even before Phase A touches them. Then launch a
# background "compact snapshot" loop that emits a 6-line summary block
# to the main log every DASHBOARD_SNAPSHOT_INTERVAL_S (default 60s).
# Operators get the snappy live dashboard via mpos-watch-sync.sh in a
# second SSH session; this loop keeps the deploy log informative.
mkdir -p "$DASHBOARD_STATUS_DIR" 2>/dev/null || true
for c in "${DEFAULT_ORDER[@]}"; do
    write_status "$c" "QUEUED"
done

emit_dashboard_snapshot() {
    local now
    now=$(date -u +%H:%M:%S)
    say "[dashboard ${now}] status"
    for c in elt umo pho lit bbtc blc; do
        local s state h t d
        s=$(cat "${DASHBOARD_STATUS_DIR}/${c}.status" 2>/dev/null || echo "QUEUED|||")
        IFS='|' read -r state h t d <<<"$s"
        case "$state" in
            DOWNLOADING)
                local cur tmp_path
                tmp_path=$(find "${COIN_DATADIR[$c]}" -maxdepth 1 -name '*-bootstrap-*.dat.xz.tmp' -print -quit 2>/dev/null || true)
                cur=$(stat -c '%s' "$tmp_path" 2>/dev/null || echo "${h:-0}")
                local pct=0
                [ "${t:-0}" -gt 0 ] && pct=$(( cur * 100 / t ))
                [ "$pct" -gt 100 ] && pct=100
                printf '   %-5s [DL]    %s / %s (%d%%)\n' "${c}:" \
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
                local pct=0
                [ "${t:-0}" -gt 0 ] && pct=$(( h * 100 / t ))
                [ "$pct" -gt 100 ] && pct=100
                printf '   %-5s [IMPORT] h=%-12s target=%-12s (%d%%)\n' "${c}:" "$h" "$t" "$pct"
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
}

SNAPSHOT_PIDFILE="${DASHBOARD_STATUS_DIR}/snapshot.pid"
# Reap a stale snapshot loop left behind by an earlier SIGKILL'd run
# (where EXIT trap couldn't fire). Without this the previous loop keeps
# writing to a now-orphaned log fd and can re-parent to PID 1.
if [ -f "$SNAPSHOT_PIDFILE" ]; then
    stale_pid=$(cat "$SNAPSHOT_PIDFILE" 2>/dev/null || echo "")
    if [ -n "$stale_pid" ] && kill -0 "$stale_pid" 2>/dev/null; then
        kill "$stale_pid" 2>/dev/null || true
    fi
    rm -f "$SNAPSHOT_PIDFILE"
fi
(
    # Reset parent's traps in the subshell so we don't fire cleanup
    # twice. The dashboard snapshot loop is best-effort — if it errors
    # we don't want to abort the deploy.
    trap - EXIT
    set +e
    while true; do
        sleep "$DASHBOARD_SNAPSHOT_INTERVAL_S"
        emit_dashboard_snapshot
    done
) &
DASHBOARD_PID=$!
echo "$DASHBOARD_PID" > "$SNAPSHOT_PIDFILE"
trap 'kill "$DASHBOARD_PID" 2>/dev/null || true; rm -f "$SNAPSHOT_PIDFILE"' EXIT INT TERM

# Phase A: download every coin's bootstrap.dat upfront in a ROLLING
# pool of DOWNLOAD_CONCURRENCY (default 3). As one wget finishes the
# next coin's download starts — never wait for a "batch" to complete.
# Pre-staging all files into their datadirs lets the per-coin solo daemon
# import run with -loadblock=<datadir>/bootstrap.dat and no start → stop →
# solo-restart dance.
say "downloading all bootstraps before any daemon starts (rolling pool of ${DOWNLOAD_CONCURRENCY})"
valid_for_download=()
init_bootstrap_source || {
    warn "  bootstrap mirror/index discovery failed; aborting rotation"
    exit 1
}
for coin in "${ROTATION[@]}"; do
    case "$coin" in
        blc|pho|bbtc|elt|umo|lit)
            datadir="${COIN_DATADIR[$coin]}"
            [ -d "$datadir" ] || mkdir -p "$datadir"
            valid_for_download+=("$coin")
            ;;
        *) warn "unknown coin '$coin' — skip" ;;
    esac
done

DOWNLOAD_FAIL=0
DL_PIDS=()
for coin in "${valid_for_download[@]}"; do
    while [ "${#DL_PIDS[@]}" -ge "$DOWNLOAD_CONCURRENCY" ]; do
        wait -n 2>/dev/null || DOWNLOAD_FAIL=1
        survivors=()
        for p in "${DL_PIDS[@]}"; do
            kill -0 "$p" 2>/dev/null && survivors+=("$p")
        done
        DL_PIDS=("${survivors[@]}")
    done
    download_bootstrap "$coin" &
    DL_PIDS+=($!)
done
# Drain remaining
for p in "${DL_PIDS[@]}"; do
    wait "$p" || DOWNLOAD_FAIL=1
done
if [ "$DOWNLOAD_FAIL" = "1" ]; then
    warn "  one or more bootstrap downloads failed; aborting rotation (set SKIP_BOOTSTRAP=1 to rely on p2p sync)"
    exit 1
fi

if [ "$PREFETCH_ONLY" = "1" ]; then
    ok "prefetch complete — all bootstrap.dat files staged"
    exit 0
fi

# Phase B: rolling pool of SYNC_CONCURRENCY (default 2) coins. As a
# coin reaches tip, the next eligible coin starts. ELT and UMO are
# mutually exclusive — never run concurrently because both peak above
# 8 GB RSS during their import + catch-up phase, which on a 15 GB host
# leaves no headroom for the other slot.
SYNC_CONCURRENCY="${SYNC_CONCURRENCY:-2}"
say "starting rolling-pool sync (concurrency=${SYNC_CONCURRENCY}, ELT/UMO mutually exclusive)"
stop_all

# Queue order: ELT first (biggest, longest), then UMO, then the four
# smaller chains. The scheduler skips a queued coin if starting it
# would violate the ELT/UMO constraint and tries the next one.
QUEUE=("${ROTATION[@]}")
declare -A PID_FOR_COIN=()
POOL_COUNT=0  # tracked separately to dodge bash 5.x set -u quirks on empty associative arrays

coin_in_pool() {
    [ -n "${PID_FOR_COIN[$1]:-}" ]
}

while [ ${#QUEUE[@]} -gt 0 ] || [ "$POOL_COUNT" -gt 0 ]; do
    # Fill pool, respecting ELT/UMO mutex
    while [ "$POOL_COUNT" -lt "$SYNC_CONCURRENCY" ] && [ ${#QUEUE[@]} -gt 0 ]; do
        picked_idx=-1
        for i in "${!QUEUE[@]}"; do
            c="${QUEUE[$i]}"
            if [ "$c" = "elt" ] && coin_in_pool umo; then continue; fi
            if [ "$c" = "umo" ] && coin_in_pool elt; then continue; fi
            picked_idx=$i
            break
        done
        if [ "$picked_idx" -lt 0 ]; then
            # Nothing eligible right now (e.g. only UMO left and ELT
            # is still running). Stop filling; wait for a slot to free.
            break
        fi
        picked="${QUEUE[$picked_idx]}"
        unset "QUEUE[$picked_idx]"
        QUEUE=("${QUEUE[@]}")
        say "[scheduler] launching ${picked} (pool: ${POOL_COUNT}/${SYNC_CONCURRENCY} before launch; remaining queue: ${#QUEUE[@]})"
        ( bootstrap_group "$picked" ) &
        PID_FOR_COIN[$picked]=$!
        POOL_COUNT=$((POOL_COUNT + 1))
    done

    [ "$POOL_COUNT" -eq 0 ] && break  # queue exhausted

    # Wait for any one running coin to finish; identify which one
    finished_pid=""
    finished_status=0
    if wait -n -p finished_pid 2>/dev/null; then
        finished_status=0
    else
        finished_status=$?
    fi
    if [ -z "${finished_pid:-}" ]; then
        # Fallback: poll for dead pids
        for c in "${!PID_FOR_COIN[@]}"; do
            if ! kill -0 "${PID_FOR_COIN[$c]:-1}" 2>/dev/null; then
                finished_pid="${PID_FOR_COIN[$c]}"
                wait "$finished_pid" 2>/dev/null || finished_status=$?
                break
            fi
        done
    fi
    finished_coin=""
    for c in "${!PID_FOR_COIN[@]}"; do
        if [ "${PID_FOR_COIN[$c]:-}" = "${finished_pid:-}" ]; then
            finished_coin="$c"
            unset "PID_FOR_COIN[$c]"
            POOL_COUNT=$((POOL_COUNT - 1))
            say "[scheduler] ${c} finished; slot freed"
            break
        fi
    done
    if [ "$finished_status" -ne 0 ]; then
        warn "[scheduler] ${finished_coin:-worker} failed with exit ${finished_status}; stopping bootstrap rotation"
        exit "$finished_status"
    fi
done

if [ "$START_AFTER" = "1" ]; then
    say "rotation done — ensuring all 6 daemons are running"
    for coin in "${DEFAULT_ORDER[@]}"; do
        if docker ps --format '{{.Names}}' | grep -qx "$coin"; then
            ok "  ${coin}: already up ($(docker ps --filter "name=^${coin}\$" --format '{{.Status}}'))"
        else
            say "  starting ${coin}"
            start_one "$coin"
            sleep 8
            if docker ps --filter name="^${coin}\$" --format '{{.Status}}' | grep -q '^Up'; then
                ok "  ${coin}: $(docker ps --filter "name=^${coin}\$" --format '{{.Status}}')"
            else
                warn "  ${coin}: not running — check 'docker logs ${coin}'"
            fi
        fi
        free -h | awk '/^Mem:/ {printf "    host avail=%s  ", $7} /^Swap:/ {printf "swap used=%s\n", $3}'
    done
fi

ok "21-bootstrap-coins.sh complete"
