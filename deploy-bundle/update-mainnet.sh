#!/usr/bin/env bash
# Layered mainnet updater for long-running pools.
#
# Run from a fresh checkout on the pool host. The script refreshes only the
# selected layer and reuses the same install steps as deploy-mainnet.sh so
# update behavior stays aligned with full deploy behavior.
set -euo pipefail

usage() {
    cat <<EOF
Usage:
  sudo bash deploy-bundle/update-mainnet.sh --mpos
  sudo bash deploy-bundle/update-mainnet.sh --eloipool
  sudo bash deploy-bundle/update-mainnet.sh --daemons
  sudo bash deploy-bundle/update-mainnet.sh --daemons --build
  sudo bash deploy-bundle/update-mainnet.sh --all

Options:
  --mpos       Update MPOS web files, DB migrations, cronjobs-py, SSE,
               share-log importer, System Status collector, and backup timer.
  --eloipool   Update Go Eloipool and merged-mining proxy services.
  --daemons    Update wallet daemon images/containers without bootstrap replay.
               Set MPOS_PULL_DAEMON_IMAGES=0 to rebuild daemon images locally.
  --wallets    Alias for --daemons.
  --all        Run --daemons, --eloipool, then --mpos.
  --build      With --daemons, --wallets, or --all, build local daemon runtime
               images after stopping/removing daemon containers. Recreates
               containers on the existing data folders with no bootstrap replay.
               Defaults to local/<coin>:25.2-local unless MPOS_DOCKER_HUB or
               MPOS_IMAGE_TAG is set. Defaults to two concurrent daemon builds
               unless BUILD_CONCURRENCY is set.

The updater reads /root/.mpos-deploy.env when present, then applies any
environment overrides supplied on this command.
EOF
}

say() { printf '\033[1;33m   %s\033[0m\n' "$*"; }
warn() { printf '\033[1;31m   warning: %s\033[0m\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

[ "$(id -u)" = "0" ] || die "run as root"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MAINNET_SCRIPTS="${SCRIPT_DIR}/scripts/mainnet"
INSTALL_REPO="${MPOS_UPDATE_REPO_ROOT:-/root/Blakestream-MPOS}"
ELOIPOOL_TREE="${ELIOPOOL_TREE:-/root/Blakestream-Eliopool}"

if [ -f /root/.mpos-deploy.env ]; then
    # shellcheck disable=SC1091
    . /root/.mpos-deploy.env
fi

export MPOS_INSTALL_ROOT="${MPOS_INSTALL_ROOT:-/opt/blakestream-mpos}"
export MPOS_WEB_ROOT="${MPOS_WEB_ROOT:-/var/www/blakestream-mpos}"
export MPOS_LOG_ROOT="${MPOS_LOG_ROOT:-/var/log/blakestream-mpos}"
export MPOS_DB_NAME="${MPOS_DB_NAME:-mpos}"
export MPOS_DB_USER="${MPOS_DB_USER:-mpos}"
export MPOS_DB_PASS="${MPOS_DB_PASS:?MPOS_DB_PASS is required}"
export MPOS_DB_HOST="${MPOS_DB_HOST:-127.0.0.1}"
export MPOS_DB_PORT="${MPOS_DB_PORT:-3306}"
export MPOS_RUN_USER="${MPOS_RUN_USER:-www-data}"
export MPOS_RUN_GROUP="${MPOS_RUN_GROUP:-www-data}"
export MPOS_DOCKER_HUB="${MPOS_DOCKER_HUB:-sidgrip}"
export MPOS_IMAGE_TAG="${MPOS_IMAGE_TAG:-25.2}"
export MPOS_PULL_DAEMON_IMAGES="${MPOS_PULL_DAEMON_IMAGES:-1}"
export MPOS_DAEMON_SOURCE_REF="${MPOS_DAEMON_SOURCE_REF:-0.25.2}"
export MPOS_DAEMON_BUILD_ROOT="${MPOS_DAEMON_BUILD_ROOT:-/root/blakestream-daemon-builds}"
export MPOS_DAEMON_BUILD_DOCKER_MODE="${MPOS_DAEMON_BUILD_DOCKER_MODE:-pull}"
export SKIP_DAEMON_IMAGE_BUILD="${SKIP_DAEMON_IMAGE_BUILD:-0}"
export MPOS_BUILD_AFTER_STOP="${MPOS_BUILD_AFTER_STOP:-0}"
export SKIP_BOOTSTRAP=1
export MPOS_DAEMON_STOP_TIMEOUT_S="${MPOS_DAEMON_STOP_TIMEOUT_S:-900}"
export ELIOPOOL_REPO_URL="${ELIOPOOL_REPO_URL:-https://github.com/BlueDragon747/eloipool_Blakecoin.git}"
export ELIOPOOL_BRANCH="${ELIOPOOL_BRANCH:-25.2-GO}"

sync_mpos_repo() {
    if [ "$(readlink -f "$REPO_ROOT")" = "$(readlink -f "$INSTALL_REPO" 2>/dev/null || echo "$INSTALL_REPO")" ]; then
        return
    fi
    say "syncing MPOS checkout to ${INSTALL_REPO}"
    mkdir -p "$INSTALL_REPO"
    rsync -a --delete \
        --exclude='.git' --exclude='frontend/node_modules' --exclude='node_modules' \
        --exclude='templates_c' --exclude='public/templates/compile' \
        "${REPO_ROOT}/" "${INSTALL_REPO}/"
}

sync_eloipool_repo() {
    if [ -d "${ELOIPOOL_TREE}/.git" ]; then
        say "updating Eloipool checkout"
        git -C "$ELOIPOOL_TREE" fetch --prune origin "$ELIOPOOL_BRANCH"
        git -C "$ELOIPOOL_TREE" checkout "$ELIOPOOL_BRANCH"
        git -C "$ELOIPOOL_TREE" reset --hard "origin/${ELIOPOOL_BRANCH}"
    else
        say "cloning Eloipool checkout"
        rm -rf "$ELOIPOOL_TREE"
        git clone --branch "$ELIOPOOL_BRANCH" --single-branch \
            "$ELIOPOOL_REPO_URL" "$ELOIPOOL_TREE"
    fi
}

COINS=(blc pho bbtc elt lit umo)
declare -A DAEMON_NAME=(
    [blc]="blakecoind"
    [pho]="photond"
    [bbtc]="blakebitcoind"
    [elt]="electrond"
    [lit]="lithiumd"
    [umo]="universalmoleculed"
)
declare -A CLI_NAME=(
    [blc]="blakecoin-cli"
    [pho]="photon-cli"
    [bbtc]="blakebitcoin-cli"
    [elt]="electron-cli"
    [lit]="lithium-cli"
    [umo]="universalmolecule-cli"
)
declare -A CONFIG_DIR=(
    [blc]=".blakecoin"
    [pho]=".photon"
    [bbtc]=".blakebitcoin"
    [elt]=".electron"
    [lit]=".lithium"
    [umo]=".universalmolecule"
)
declare -A CONFIG_FILE=(
    [blc]="blakecoin.conf"
    [pho]="photon.conf"
    [bbtc]="blakebitcoin.conf"
    [elt]="electron.conf"
    [lit]="lithium.conf"
    [umo]="universalmolecule.conf"
)
declare -A RPC_PORT=(
    [blc]="8772"
    [pho]="8984"
    [bbtc]="8243"
    [elt]="6852"
    [lit]="12000"
    [umo]="5921"
)
declare -A COIN_IMAGE_NAME=(
    [blc]="blakecoin"
    [pho]="photon"
    [bbtc]="blakebitcoin"
    [elt]="electron"
    [lit]="lithium"
    [umo]="universalmolecule"
)

coin_image() {
    local coin="$1"
    printf '%s/%s:%s' "$MPOS_DOCKER_HUB" "${COIN_IMAGE_NAME[$coin]}" "$MPOS_IMAGE_TAG"
}

unit_exists() {
    systemctl cat "$1" >/dev/null 2>&1
}

stop_pool_for_daemon_update() {
    say "stopping Stratum server before daemon update"
    if unit_exists blakestream-mpos-eloipool.service; then
        systemctl stop blakestream-mpos-eloipool.service
        say "Stratum server stopped"
    else
        say "Stratum service not installed; skipping"
    fi
    say "stopping merged-mine proxy before daemon update"
    if unit_exists blakestream-mpos-mergeminer.service; then
        systemctl stop blakestream-mpos-mergeminer.service
        say "merged-mine proxy stopped"
    else
        say "merged-mine proxy service not installed; skipping"
    fi
}

wait_merged_mine_proxy_ready() {
    local attempt body
    for attempt in $(seq 1 60); do
        body="$(curl -fsS --max-time 3 \
            -H 'content-type: application/json' \
            --data '{"jsonrpc":"2.0","id":1,"method":"getaux","params":[]}' \
            http://127.0.0.1:19335/ 2>/dev/null || true)"
        if [ -n "$body" ] && python3 - "$body" <<'PY'
import json
import sys

try:
    result = json.loads(sys.argv[1]).get("result") or {}
except Exception:
    sys.exit(1)

ready = int(result.get("ready_count") or 0)
total = int(result.get("total_chains") or 0)
sys.exit(0 if total > 0 and ready == total else 1)
PY
        then
            return 0
        fi
        sleep 2
    done
    return 1
}

start_pool_after_daemon_update() {
    if [ "${MPOS_DEFER_POOL_START:-0}" = "1" ]; then
        say "full update selected; holding pool services down until all layers finish"
        return
    fi
    start_pool_services_after_update
}

start_pool_services_after_update() {
    say "starting Stratum server and parent RPC after update"
    if unit_exists blakestream-mpos-eloipool.service; then
        systemctl start blakestream-mpos-eloipool.service
        say "Stratum server started"
    else
        say "Stratum service not installed; skipping"
    fi
    say "starting merged-mine proxy after update"
    if unit_exists blakestream-mpos-mergeminer.service; then
        systemctl start blakestream-mpos-mergeminer.service
        say "waiting for merged-mine proxy aux readiness"
        wait_merged_mine_proxy_ready || die "merged-mine proxy did not become ready after update"
        say "merged-mine proxy ready"
    else
        say "merged-mine proxy service not installed; skipping"
    fi
}

pull_or_confirm_daemon_image() {
    local coin="$1"
    local image
    image="$(coin_image "$coin")"

    if [ "$MPOS_PULL_DAEMON_IMAGES" = "0" ]; then
        say "using local image ${image}"
        docker image inspect "$image" >/dev/null 2>&1 || die "missing local Docker image ${image}"
        return
    fi

    say "pulling ${image}"
    if docker pull "$image"; then
        return
    fi
    docker image inspect "$image" >/dev/null 2>&1 || die "missing Docker image ${image}"
    say "pull failed for ${image}; using cached local image"
}

wait_daemon_rpc() {
    local coin="$1"
    local port="${RPC_PORT[$coin]}"
    local deadline="${MPOS_DAEMON_RPC_TIMEOUT_S:-900}"
    local end height last_msg msg resp_file

    resp_file="$(mktemp)"
    end=$(( $(date +%s) + deadline ))
    last_msg=""
    say "waiting for ${coin} RPC on 127.0.0.1:${port}"
    while :; do
        if curl -fsSL --max-time 60 -u "${MPOS_NODE_RPC_USER}:${MPOS_NODE_RPC_PASS}" \
                --data '{"jsonrpc":"1.0","id":"update","method":"getblockcount"}' \
                -H 'content-type: text/plain' \
                "http://127.0.0.1:${port}/" >"$resp_file" 2>/dev/null; then
            height="$(sed -n 's/.*"result":\([0-9]*\).*/\1/p' "$resp_file")"
            rm -f "$resp_file"
            say "${coin} RPC OK; height=${height:-?}"
            return 0
        fi
        if [ "$(date +%s)" -ge "$end" ]; then
            rm -f "$resp_file"
            docker logs "$coin" --tail 30 >&2 2>/dev/null || true
            die "${coin} never came up on 127.0.0.1:${port}"
        fi
        msg="$(docker logs --tail 1 "$coin" 2>/dev/null | head -c 80)"
        if [ "$msg" != "$last_msg" ]; then
            last_msg="$msg"
            say "  ${coin}: ${msg:-(no log yet)}"
        fi
        sleep 5
    done
}

stop_daemon_container_gracefully() {
    local coin="$1"
    local cli="${CLI_NAME[$coin]}"
    local config_dir="${CONFIG_DIR[$coin]}"
    local wait_iterations

    if ! docker ps -a --format '{{.Names}}' | grep -qx "$coin"; then
        return
    fi

    say "stopping daemon container ${coin} cleanly"
    docker update --restart=no "$coin" >/dev/null 2>&1 || true
    if docker ps --format '{{.Names}}' | grep -qx "$coin"; then
        docker exec "$coin" "/usr/local/bin/${cli}" "-datadir=/root/${config_dir}" stop >/dev/null 2>&1 || true
        wait_iterations=$((MPOS_DAEMON_STOP_TIMEOUT_S / 5))
        [ "$wait_iterations" -ge 1 ] || wait_iterations=1
        for _ in $(seq 1 "$wait_iterations"); do
            if ! docker ps --format '{{.Names}}' | grep -qx "$coin"; then
                break
            fi
            sleep 5
        done
        if docker ps --format '{{.Names}}' | grep -qx "$coin"; then
            die "${coin} did not stop cleanly within ${MPOS_DAEMON_STOP_TIMEOUT_S}s; leaving it running"
        fi
    fi

    docker rm "$coin" >/dev/null 2>&1 || true
}

start_daemon_container() {
    local coin="$1"
    local image daemon config_dir datadir conf

    image="$(coin_image "$coin")"
    daemon="${DAEMON_NAME[$coin]}"
    config_dir="${CONFIG_DIR[$coin]}"
    datadir="/root/${config_dir}"
    conf="${datadir}/${CONFIG_FILE[$coin]}"

    [ -d "$datadir" ] || die "missing existing data folder ${datadir}; use deploy-mainnet.sh for first install"
    [ -f "$conf" ] || die "missing existing config ${conf}; use deploy-mainnet.sh for first install"

    say "starting ${coin} from ${image} with existing ${datadir}"
    docker run -d \
        --name "$coin" \
        --user 0:0 \
        --net=host \
        --restart=unless-stopped \
        --stop-timeout "$MPOS_DAEMON_STOP_TIMEOUT_S" \
        --entrypoint /bin/sh \
        -v "${datadir}:${datadir}" \
        "$image" \
        -lc "mkdir -p ${datadir} && touch ${datadir}/debug.log && chmod 644 ${datadir}/debug.log && exec /usr/local/bin/${daemon} -datadir=${datadir}" \
        >/dev/null
}

stop_daemon_container_batch() {
    local pids=()
    local labels=()
    local coin idx failed=0

    say "stopping daemon containers: $*"
    for coin in "$@"; do
        ( stop_daemon_container_gracefully "$coin" ) &
        pids+=("$!")
        labels+=("$coin")
    done
    for idx in "${!pids[@]}"; do
        if ! wait "${pids[$idx]}"; then
            warn "${labels[$idx]} did not stop cleanly"
            failed=1
        fi
    done
    [ "$failed" = "0" ] || die "one or more daemon containers failed to stop cleanly"
}

stop_daemon_containers() {
    local elt_pid umo_pid failed=0

    say "daemon stop plan: ELT first, then BLC/PHO, BBTC/LIT, then UMO with ELT if ELT is still stopping"
    # ELT usually has the slowest shutdown. Start that stop first, then stop
    # lighter daemons in pairs while ELT is winding down. If ELT is still
    # stopping after the light pairs, stop UMO in parallel with the remaining
    # ELT stop; otherwise stop UMO by itself.
    say "stopping daemon container: elt"
    ( stop_daemon_container_gracefully elt ) &
    elt_pid="$!"
    stop_daemon_container_batch blc pho
    stop_daemon_container_batch bbtc lit
    if kill -0 "$elt_pid" >/dev/null 2>&1; then
        say "ELT still stopping; stopping UMO in parallel"
        ( stop_daemon_container_gracefully umo ) &
        umo_pid="$!"
        wait "$elt_pid" || failed=1
        wait "$umo_pid" || failed=1
    else
        wait "$elt_pid" || failed=1
        say "ELT stopped before UMO; stopping UMO now"
        stop_daemon_container_gracefully umo || failed=1
    fi
    [ "$failed" = "0" ] || die "elt or umo did not stop cleanly"
    say "daemon containers stopped cleanly"
}

start_daemon_containers_staged() {
    say "daemon start plan: ELT first, rotate BLC/PHO/BBTC/LIT, then start UMO while ELT is the only heavy daemon left"
    # Start ELT first, then rotate in lighter daemons while ELT is loading. UMO
    # starts once only ELT remains, giving both heavy wallets enough resources.
    start_daemon_container elt
    say "rotating in BLC while ELT starts"
    start_daemon_container blc
    wait_daemon_rpc blc
    say "rotating in PHO"
    start_daemon_container pho
    wait_daemon_rpc pho
    say "rotating in BBTC"
    start_daemon_container bbtc
    wait_daemon_rpc bbtc
    say "rotating in LIT"
    start_daemon_container lit
    wait_daemon_rpc lit

    say "ELT is the only heavy daemon still loading; starting UMO"
    start_daemon_container umo
    wait_daemon_rpc elt
    wait_daemon_rpc umo
    say "staged daemon startup complete"
}

confirm_daemon_images() {
    local coin

    say "checking daemon images before container start"
    for coin in "${COINS[@]}"; do
        pull_or_confirm_daemon_image "$coin"
    done
}

update_daemon_containers() {
    confirm_daemon_images
    stop_daemon_containers
    start_daemon_containers_staged
}

update_daemons() {
    say "starting daemon update"
    sync_mpos_repo
    stop_pool_for_daemon_update
    if [ "$MPOS_BUILD_AFTER_STOP" = "1" ]; then
        say "build-after-stop selected; stopping/removing daemon containers before local image build"
        stop_daemon_containers
        say "building local daemon images"
        bash "${MAINNET_SCRIPTS}/19-build-daemon-images.sh"
        confirm_daemon_images
        start_daemon_containers_staged
    else
        if [ "$MPOS_PULL_DAEMON_IMAGES" = "0" ] && [ "$SKIP_DAEMON_IMAGE_BUILD" != "1" ]; then
            say "building local daemon images"
            bash "${MAINNET_SCRIPTS}/19-build-daemon-images.sh"
        fi
        update_daemon_containers
    fi
    say "running final daemon RPC verification"
    bash "${MAINNET_SCRIPTS}/30-wait-rpc.sh"
    start_pool_after_daemon_update
    say "daemon update finished"
}

update_eloipool() {
    say "starting Eloipool update"
    sync_mpos_repo
    sync_eloipool_repo
    if [ "${MPOS_DEFER_POOL_START:-0}" = "1" ]; then
        say "full update selected; Eloipool install will not start Stratum yet"
    fi
    bash "${MAINNET_SCRIPTS}/40-install-pool.sh"
    say "Eloipool update finished"
}

update_mpos() {
    say "starting MPOS web and service update"
    sync_mpos_repo
    say "updating MPOS web files and database migrations"
    bash "${MAINNET_SCRIPTS}/50-install-mpos.sh"
    say "updating PHP cron service"
    bash "${MAINNET_SCRIPTS}/60-install-php-cron.sh"
    say "updating Python cronjobs"
    bash "${MAINNET_SCRIPTS}/70-install-cronjobs-py.sh"
    say "updating dashboard event stream"
    bash "${MAINNET_SCRIPTS}/75-install-sse.sh"
    say "updating share-log importer"
    bash "${MAINNET_SCRIPTS}/76-install-sharelog-importer.sh"
    say "updating System Status collector"
    bash "${SCRIPT_DIR}/scripts/77-install-system-status-cache.sh"
    say "updating logrotate"
    bash "${MAINNET_SCRIPTS}/85-install-logrotate.sh"
    say "updating backup timer"
    bash "${MAINNET_SCRIPTS}/90-install-backup.sh"
    say "MPOS web and service update finished"
}

run_mpos=0
run_eloipool=0
run_daemons=0
final_start_pool=0
build_daemon_images=0

for arg in "$@"; do
    case "$arg" in
        --mpos|-mpos) run_mpos=1 ;;
        --eloipool|--eloi|-eloipool|-eloi) run_eloipool=1 ;;
        --daemons|--daemon|--wallets|--wallet|-daemons|-daemon|-wallets|-wallet) run_daemons=1 ;;
        --all|-all) run_daemons=1; run_eloipool=1; run_mpos=1 ;;
        --build|-build) build_daemon_images=1 ;;
        *) die "unknown option: $arg" ;;
    esac
done

if [ "$run_mpos$run_eloipool$run_daemons" = "000" ]; then
    usage
    exit 1
fi

if [ "$build_daemon_images" = "1" ]; then
    [ "$run_daemons" = "1" ] || die "--build requires --daemons, --wallets, or --all"
    export MPOS_PULL_DAEMON_IMAGES=0
    [ "$MPOS_DOCKER_HUB" != "sidgrip" ] || export MPOS_DOCKER_HUB=local
    [ "$MPOS_IMAGE_TAG" != "25.2" ] || export MPOS_IMAGE_TAG=25.2-local
    export SKIP_DAEMON_IMAGE_BUILD=0
    export MPOS_BUILD_AFTER_STOP=1
    export BUILD_CONCURRENCY="${BUILD_CONCURRENCY:-2}"
    say "daemon build mode selected; containers will stop before building ${MPOS_DOCKER_HUB}/<coin>:${MPOS_IMAGE_TAG} with concurrency ${BUILD_CONCURRENCY}"
fi

if [ "$run_mpos$run_eloipool$run_daemons" = "111" ]; then
    final_start_pool=1
    export MPOS_DEFER_POOL_START=1
    say "full update selected; Stratum will stay stopped until daemon, Eloipool, and MPOS updates finish"
fi

if [ "$run_daemons" = "1" ]; then update_daemons; fi
if [ "$run_eloipool" = "1" ]; then update_eloipool; fi
if [ "$run_mpos" = "1" ]; then update_mpos; fi
if [ "$final_start_pool" = "1" ]; then
    say "all update layers finished; starting pool services"
    MPOS_DEFER_POOL_START=0 start_pool_services_after_update
fi

say "update complete"
