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
declare -A BOOTSTRAP_NAME=(
    [blc]="Blakecoin"
    [pho]="Photon"
    [bbtc]="BlakeBitcoin"
    [elt]="Electron"
    [umo]="UniversalMolecule"
    [lit]="Lithium"
)

# Default rotation order: ELT first because it's the largest chain
# (and the one that historically OOM'd first with peers off). UMO
# next for the same reason. Then the smaller chains.
DEFAULT_ORDER=(elt umo pho lit bbtc blc)

# Tuning — dbcache flips between BOOTSTRAP_DBCACHE_MB during fresh-import
# (large in-memory UTXO buffer = fewer disk flushes during validation,
# faster catch-up) and STEADY_DBCACHE_MB once the chain is at tip and
# the daemon is running alongside its 5 peers.
BOOTSTRAP_DBCACHE_MB="${BOOTSTRAP_DBCACHE_MB:-4000}"
STEADY_DBCACHE_MB="${STEADY_DBCACHE_MB:-400}"
DBCACHE_MB="${DBCACHE_MB:-${STEADY_DBCACHE_MB}}"
MAXMEMPOOL_MB="${MAXMEMPOOL_MB:-50}"
PEERS_ON_MAXCONN="${PEERS_ON_MAXCONN:-20}"
BOOTSTRAP_IMPORT_TIMEOUT_S="${BOOTSTRAP_IMPORT_TIMEOUT_S:-21600}" # 6h max per coin
BOOTSTRAP_IMPORT_SLEEP_S="${BOOTSTRAP_IMPORT_SLEEP_S:-60}"
BOOTSTRAP_DOWNLOAD_ATTEMPTS="${BOOTSTRAP_DOWNLOAD_ATTEMPTS:-12}"
BOOTSTRAP_DOWNLOAD_RETRY_SLEEP_S="${BOOTSTRAP_DOWNLOAD_RETRY_SLEEP_S:-60}"
BOOTSTRAP_DOWNLOAD_CONNECT_TIMEOUT_S="${BOOTSTRAP_DOWNLOAD_CONNECT_TIMEOUT_S:-30}"
BOOTSTRAP_DOWNLOAD_READ_TIMEOUT_S="${BOOTSTRAP_DOWNLOAD_READ_TIMEOUT_S:-90}"
TIP_CATCH_TIMEOUT_S="${TIP_CATCH_TIMEOUT_S:-7200}"  # 2h max waiting for tip catch-up
TIP_CATCH_LAG="${TIP_CATCH_LAG:-5}"
START_AFTER="${START_AFTER:-1}"
MPOS_DOCKER_HUB="${MPOS_DOCKER_HUB:-sidgrip}"
MPOS_IMAGE_TAG="${MPOS_IMAGE_TAG:-latest}"
BOOTSTRAP_URL="${BOOTSTRAP_URL:-https://bootstrap.blakestream.io}"

coin_image() {
    local coin="$1"
    printf '%s/%s:%s' "$MPOS_DOCKER_HUB" "${COIN_IMAGE_NAME[$coin]}" "$MPOS_IMAGE_TAG"
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

download_bootstrap() {
    local coin="$1"
    local datadir="${COIN_DATADIR[$coin]}"
    local bootstrap_name="${BOOTSTRAP_NAME[$coin]}"
    local bootstrap_file="${datadir}/bootstrap.dat"
    local bootstrap_tmp="${bootstrap_file}.tmp"
    local bootstrap_url="${BOOTSTRAP_URL%/}/${bootstrap_name}/bootstrap.dat"
    local expected_size=""

    # --no-check-certificate: bootstrap.blakestream.io can be served
    # either through Cloudflare (publicly trusted cert) or directly
    # from the origin (Cloudflare-managed cert whose CN doesn't match
    # the hostname, so wget rejects it). Bootstrap data is public,
    # the download is size-verified against Content-Length below, and
    # every block is consensus-validated by the daemon — so skipping
    # TLS hostname verification doesn't compromise integrity here.
    expected_size=$(
        wget --spider --server-response --tries=1 --no-check-certificate \
            --connect-timeout="$BOOTSTRAP_DOWNLOAD_CONNECT_TIMEOUT_S" \
            --read-timeout="$BOOTSTRAP_DOWNLOAD_READ_TIMEOUT_S" \
            "$bootstrap_url" 2>&1 \
            | awk '
                /^  HTTP\// { ok = ($2 ~ /^2/); next }
                ok && tolower($0) ~ /content-length:/ { print $2 }
            ' \
            | tr -d '\r' \
            | tail -1 \
            || true
    )

    if [ ! -f "$bootstrap_file" ] && [ -f "${bootstrap_file}.old" ]; then
        ok "  ${coin}: bootstrap.dat already consumed as bootstrap.dat.old ($(du -h "${bootstrap_file}.old" | cut -f1))"
        return 0
    fi

    if [ -f "$bootstrap_file" ]; then
        if [[ "$expected_size" =~ ^[0-9]+$ ]]; then
            local actual_size
            actual_size=$(stat -c '%s' "$bootstrap_file" 2>/dev/null || echo 0)
            if [ "$actual_size" != "$expected_size" ]; then
                warn "  ${coin}: existing bootstrap.dat is ${actual_size} bytes; expected ${expected_size}; redownloading"
                rm -f "$bootstrap_file"
            else
                ok "  ${coin}: bootstrap.dat already present ($(du -h "$bootstrap_file" | cut -f1))"
                return 0
            fi
        else
            warn "  ${coin}: could not verify remote bootstrap.dat size; using existing file"
            ok "  ${coin}: bootstrap.dat already present ($(du -h "$bootstrap_file" | cut -f1))"
            return 0
        fi
    fi

    if [ -f "$bootstrap_tmp" ]; then
        warn "  ${coin}: resuming incomplete bootstrap download ${bootstrap_tmp} ($(du -h "$bootstrap_tmp" | cut -f1))"
    fi

    say "  downloading ${coin} bootstrap.dat from ${bootstrap_url}"
    local attempt actual_size
    for attempt in $(seq 1 "$BOOTSTRAP_DOWNLOAD_ATTEMPTS"); do
        if [ -f "$bootstrap_tmp" ] && [[ "$expected_size" =~ ^[0-9]+$ ]]; then
            actual_size=$(stat -c '%s' "$bootstrap_tmp" 2>/dev/null || echo 0)
            if [ "$actual_size" -gt "$expected_size" ]; then
                warn "  ${coin}: partial bootstrap is larger than expected; restarting download"
                rm -f "$bootstrap_tmp"
            fi
        fi

        if wget --continue --tries=1 --no-check-certificate \
            --connect-timeout="$BOOTSTRAP_DOWNLOAD_CONNECT_TIMEOUT_S" \
            --read-timeout="$BOOTSTRAP_DOWNLOAD_READ_TIMEOUT_S" \
            --progress=bar:force \
            -O "$bootstrap_tmp" "$bootstrap_url"; then
            if [[ "$expected_size" =~ ^[0-9]+$ ]]; then
                actual_size=$(stat -c '%s' "$bootstrap_tmp" 2>/dev/null || echo 0)
                if [ "$actual_size" != "$expected_size" ]; then
                    warn "  ${coin}: downloaded bootstrap.dat is ${actual_size} bytes; expected ${expected_size}"
                    if [ "$attempt" -lt "$BOOTSTRAP_DOWNLOAD_ATTEMPTS" ]; then
                        warn "  ${coin}: retrying download in ${BOOTSTRAP_DOWNLOAD_RETRY_SLEEP_S}s (attempt ${attempt}/${BOOTSTRAP_DOWNLOAD_ATTEMPTS})"
                        sleep "$BOOTSTRAP_DOWNLOAD_RETRY_SLEEP_S"
                        continue
                    fi
                    return 1
                fi
            fi
            mv -f "$bootstrap_tmp" "$bootstrap_file"
            ok "  ${coin}: bootstrap.dat downloaded ($(du -h "$bootstrap_file" | cut -f1))"
            return 0
        fi

        if [ "$attempt" -lt "$BOOTSTRAP_DOWNLOAD_ATTEMPTS" ]; then
            warn "  ${coin}: bootstrap download attempt ${attempt}/${BOOTSTRAP_DOWNLOAD_ATTEMPTS} failed; retrying in ${BOOTSTRAP_DOWNLOAD_RETRY_SLEEP_S}s"
            sleep "$BOOTSTRAP_DOWNLOAD_RETRY_SLEEP_S"
        fi
    done

    warn "  ${coin}: bootstrap download failed after ${BOOTSTRAP_DOWNLOAD_ATTEMPTS} attempts"
    return 1
}

start_one() {
    local coin="$1"
    local datadir="${COIN_DATADIR[$coin]}"
    local daemon="${COIN_DAEMON[$coin]}"
    local image
    image="$(coin_image "$coin")"
    docker run -d \
        --name "$coin" \
        --net=host \
        --restart=unless-stopped \
        --stop-timeout 300 \
        -v "${datadir}:${datadir}" \
        "$image" \
        /bin/sh -lc "mkdir -p ${datadir} && touch ${datadir}/debug.log && chmod 644 ${datadir}/debug.log && exec /usr/local/bin/${daemon} -datadir=${datadir}" \
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
        if grep -q "Importing bootstrap.dat" "$debug_log" 2>/dev/null; then
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
        printf '   [%s] height=%s  peer_tip=%s  delta=%s\n' \
            "$(date +%H:%M:%S)" "$h" "$tip" "$delta"
        if [ "$h" -gt 0 ] \
                && [ "$tip" -gt 0 ] \
                && [ "$abs_delta" -le "$TIP_CATCH_LAG" ]; then
            return 0
        fi
    done
    warn "  tip catch-up timed out after ${TIP_CATCH_TIMEOUT_S}s"
    return 1
}

bootstrap_one() {
    local coin="$1"
    local datadir="${COIN_DATADIR[$coin]}"
    local conf="${datadir}/${COIN_CONF[$coin]}"
    local bootstrap_file="${datadir}/bootstrap.dat"
    local bootstrap_already_consumed=0

    [ -f "$conf" ] || { warn "missing $conf — skip"; return; }

    say "===== ${coin} (${datadir}) ====="
    if [ ! -f "$bootstrap_file" ] && [ -f "${bootstrap_file}.old" ]; then
        bootstrap_already_consumed=1
    fi

    if [ "$bootstrap_already_consumed" = "1" ]; then
        # Resuming an already-bootstrapped chain: no heavy import, use
        # steady-state dbcache from the start.
        DBCACHE_MB="${STEADY_DBCACHE_MB}" ensure_caps "$conf"
    else
        # Fresh bootstrap import: boost dbcache so the in-memory UTXO
        # buffer is large, fewer disk flushes during validation.
        DBCACHE_MB="${BOOTSTRAP_DBCACHE_MB}" ensure_caps "$conf"
        say "  using dbcache=${BOOTSTRAP_DBCACHE_MB}MB for fresh bootstrap import"
    fi
    set_peers "$conf" on

    start_one "$coin"
    if [ "$bootstrap_already_consumed" = "1" ]; then
        say "  started ${coin}; bootstrap.dat already consumed (resuming existing chainstate)"
    else
        say "  started ${coin}; daemon auto-imports bootstrap.dat on first launch"
    fi

    wait_at_tip "$coin" "$datadir"
    local final_tip
    final_tip=$(current_height "$datadir")
    ok "  ${coin} reached height=${final_tip:-0}"

    if [ "$bootstrap_already_consumed" = "1" ]; then
        # Chain was bootstrapped on a prior deploy; the daemon is in
        # steady state and adds little RAM pressure. Leave it running so
        # the next coin can start alongside — no flush/stop dance needed.
        ok "  ${coin} stays running — moving to next coin"
    else
        # Fresh bootstrap import: chainstate flush isn't immediate after
        # reaching tip, and the next coin's import would push RAM/IO on
        # a 16G host. Stop cleanly so the flush completes before next.
        say "  letting ${coin} flush chainstate (60s) before stopping"
        sleep 60
        stop_one "$coin"
        # Drop dbcache to steady-state for Phase C / future starts.
        DBCACHE_MB="${STEADY_DBCACHE_MB}" ensure_caps "$conf"
        ok "  ${coin} stopped — dbcache dropped to ${STEADY_DBCACHE_MB}MB for steady state"
    fi
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

# Phase A: download every coin's bootstrap.dat upfront, one at a time, while
# no daemons are running. Pre-staging all files into their datadirs lets the
# per-coin solo daemon import on first launch with no start → stop → restart
# dance.
say "downloading all bootstraps before any daemon starts"
for coin in "${ROTATION[@]}"; do
    case "$coin" in
        blc|pho|bbtc|elt|umo|lit) ;;
        *) warn "unknown coin '$coin' — skip"; continue ;;
    esac
    datadir="${COIN_DATADIR[$coin]}"
    [ -d "$datadir" ] || mkdir -p "$datadir"
    download_bootstrap "$coin" || {
        warn "  ${coin}: bootstrap download failed; aborting rotation (set SKIP_BOOTSTRAP=1 to rely on p2p sync)"
        exit 1
    }
done

if [ "$PREFETCH_ONLY" = "1" ]; then
    ok "prefetch complete — all bootstrap.dat files staged"
    exit 0
fi

# Phase B: solo bootstrap + p2p catch-up for each coin in rotation order.
# Single stop_all here handles re-runs that may have left a daemon running;
# during the rotation itself only one daemon is up at a time, so
# bootstrap_one only stops THIS coin between phases.
say "starting solo bootstrap rotation"
stop_all
for coin in "${ROTATION[@]}"; do
    case "$coin" in
        blc|pho|bbtc|elt|umo|lit) bootstrap_one "$coin" ;;
        *) warn "unknown coin '$coin' — skip" ;;
    esac
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
