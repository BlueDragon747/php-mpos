#!/usr/bin/env bash
# 20-deploy-daemons.sh — stage data folders, configs, and daemon images.
#
# Flow (with bootstrap rotation enabled, the default):
#   1. Create /root/.<coin>/ datadirs for all six coins.
#   2. Render each <coin>.conf with peering OFF (listen=0, maxconnections=0)
#      so the rotation in step 21 controls when daemons see peers.
#   3. Pull (or confirm locally-built) daemon images.
#   4. Hand off to step 21 — which downloads all bootstraps one at a time,
#      then starts each daemon one at a time for solo import + p2p catch-up.
#
# Containers are NOT started here. Step 21 stages bootstrap.dat and starts
# each 25.2 daemon with -loadblock=<datadir>/bootstrap.dat for explicit import,
# avoiding the start → stop → solo-restart dance.
#
# SKIP_BOOTSTRAP=1 path: step 21 is skipped by deploy-mainnet.sh, so this
# script starts all six daemons here in steady state with peering ON.
set -euo pipefail

say()  { printf '\033[1;33m   %s\033[0m\n' "$*"; }
warn() { printf '\033[1;31m!! %s\033[0m\n' "$*" >&2; }

MPOS_DOCKER_HUB="${MPOS_DOCKER_HUB:-sidgrip}"
MPOS_IMAGE_TAG="${MPOS_IMAGE_TAG:-25.2}"
MPOS_PULL_DAEMON_IMAGES="${MPOS_PULL_DAEMON_IMAGES:-1}"
MPOS_EXPLORER_API_BASE="${MPOS_EXPLORER_API_BASE:-https://explorer.blakestream.io/api}"
MPOS_DAEMON_STOP_TIMEOUT_S="${MPOS_DAEMON_STOP_TIMEOUT_S:-900}"

COINS=(blc pho bbtc elt lit umo)

declare -A COIN_NAME=(
    [blc]="Blakecoin"
    [pho]="Photon"
    [bbtc]="BlakeBitcoin"
    [elt]="Electron"
    [lit]="Lithium"
    [umo]="Universal Molecule"
)
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
declare -A P2P_PORT=(
    [blc]="8773"
    [pho]="35556"
    [bbtc]="8356"
    [elt]="6853"
    [lit]="12007"
    [umo]="24785"
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

fetch_peers() {
    local coin="$1"
    local peers_json

    peers_json=$(curl -fsSL --connect-timeout 5 --max-time 15 \
        "${MPOS_EXPLORER_API_BASE%/}/${coin}/globe/peers" 2>/dev/null || true)

    if [ -n "$peers_json" ]; then
        printf '%s\n' "$peers_json" \
            | grep -oE '"addr"[[:space:]]*:[[:space:]]*"([0-9]{1,3}\.){3}[0-9]{1,3}(:[0-9]+)?"' \
            | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' \
            | awk -F. '
                $1 >= 0 && $1 <= 255 &&
                $2 >= 0 && $2 <= 255 &&
                $3 >= 0 && $3 <= 255 &&
                $4 >= 0 && $4 <= 255 &&
                $1 != 0 &&
                $1 != 10 &&
                $1 != 127 &&
                !($1 == 169 && $2 == 254) &&
                !($1 == 172 && $2 >= 16 && $2 <= 31) &&
                !($1 == 192 && $2 == 168) &&
                !($1 == 100 && $2 >= 64 && $2 <= 127) &&
                $1 < 224
            ' \
            | sort -u \
            | sed 's/^/addnode=/' \
            || true
    fi
}

pull_image() {
    local coin="$1"
    local image
    image="$(coin_image "$coin")"

    if [ "$MPOS_PULL_DAEMON_IMAGES" = "0" ]; then
        say "using local image ${image}"
        if docker image inspect "$image" >/dev/null 2>&1; then
            return 0
        fi
        warn "missing local Docker image ${image}"
        return 1
    fi

    say "pulling ${image}"
    if docker pull "$image"; then
        return 0
    fi

    if docker image inspect "$image" >/dev/null 2>&1; then
        warn "pull failed for ${image}; using cached local image"
        return 0
    fi

    warn "missing Docker image ${image}"
    return 1
}

write_config() {
    local coin="$1"
    local name="${COIN_NAME[$coin]}"
    local conf="${CONFIG_FILE[$coin]}"
    local datadir="/root/${CONFIG_DIR[$coin]}"
    local rpc_port="${RPC_PORT[$coin]}"
    local p2p_port="${P2P_PORT[$coin]}"
    local peers peer_count=0

    say "rendering ${name} config"
    # datadir is created in phase 2 above

    peers="$(fetch_peers "$coin")"
    [ -n "$peers" ] && peer_count=$(printf '%s\n' "$peers" | wc -l)
    say "  ${coin}: ${peer_count} explorer peers"

    # Default to peering OFF so step 21 controls when each daemon sees
    # peers (solo bootstrap import first, then peering ON for catch-up).
    # SKIP_BOOTSTRAP=1 toggles these to listen=1 / maxconnections=20 after
    # the config is rendered, below.
    cat > "${datadir}/${conf}" <<EOF
# ${name} configuration - generated by Blakestream-MPOS deploy-mainnet.sh
rpcuser=${MPOS_NODE_RPC_USER}
rpcpassword=${MPOS_NODE_RPC_PASS}
rpcport=${rpc_port}
rpcallowip=127.0.0.1
port=${p2p_port}
listen=0
server=1
daemon=0
# Pool-tuned config:
#   txindex=0       — MPOS only uses gettransaction (wallet), not getrawtransaction
#   prune=10000     — keep ~10 GB of recent blocks; saves ~50 GB/coin of disk
#                     (admin stats page may error on very old block clicks; pool ops unaffected)
#   maxorphantx=10  — pool doesn't need to track many orphans
#   maxreceivebuffer/maxsendbuffer — tighter per-peer buffers, more peers without RAM blow-up
txindex=0
prune=10000
maxconnections=0
dbcache=400
maxmempool=50
fallbackfee=0.0001
maxorphantx=10
maxreceivebuffer=2500
maxsendbuffer=500
${peers}
EOF
    if [ "${SKIP_BOOTSTRAP:-0}" = "1" ]; then
        sed -i 's/^listen=.*/listen=1/' "${datadir}/${conf}"
        sed -i 's/^maxconnections=.*/maxconnections=20/' "${datadir}/${conf}"
    fi
    chmod 600 "${datadir}/${conf}"
}

write_wrapper() {
    local coin="$1"
    local daemon="${DAEMON_NAME[$coin]}"
    local config_dir="${CONFIG_DIR[$coin]}"

    mkdir -p /root/.local/bin
    cat > "/root/.local/bin/${daemon}" <<WRAPPER
#!/usr/bin/env bash
CONTAINER='${coin}'
if ! docker ps --format '{{.Names}}' | grep -qx "\${CONTAINER}"; then
    docker start "\${CONTAINER}" >/dev/null 2>&1
fi
docker exec "\${CONTAINER}" /usr/local/bin/${daemon} -datadir=/root/${config_dir} "\$@"
WRAPPER
    chmod +x "/root/.local/bin/${daemon}"
}

stop_existing_container() {
    local coin="$1"
    local cli="${CLI_NAME[$coin]}"
    local config_dir="${CONFIG_DIR[$coin]}"

    if ! docker ps -a --format '{{.Names}}' | grep -qx "$coin"; then
        return 0
    fi

    say "stopping existing container ${coin}"
    docker update --restart=no "$coin" >/dev/null 2>&1 || true
    if docker ps --format '{{.Names}}' | grep -qx "$coin"; then
        docker exec "$coin" "/usr/local/bin/${cli}" "-datadir=/root/${config_dir}" stop >/dev/null 2>&1 || true
        local rpc_wait_iterations=$((MPOS_DAEMON_STOP_TIMEOUT_S / 5))
        [ "$rpc_wait_iterations" -ge 1 ] || rpc_wait_iterations=1
        for _ in $(seq 1 "$rpc_wait_iterations"); do
            if ! docker ps --format '{{.Names}}' | grep -qx "$coin"; then
                break
            fi
            sleep 5
        done
        docker stop -t "$MPOS_DAEMON_STOP_TIMEOUT_S" "$coin" >/dev/null 2>&1 || true
    fi
    docker rm -f "$coin" >/dev/null 2>&1 || true
}

launch_coin() {
    local coin="$1"
    local image daemon config_dir datadir
    image="$(coin_image "$coin")"
    daemon="${DAEMON_NAME[$coin]}"
    config_dir="${CONFIG_DIR[$coin]}"
    datadir="/root/${config_dir}"

    stop_existing_container "$coin"
    say "starting ${coin} from ${image}"
    docker run -d \
        --name "$coin" \
        --net=host \
        --restart=unless-stopped \
        --stop-timeout "$MPOS_DAEMON_STOP_TIMEOUT_S" \
        -v "${datadir}:${datadir}" \
        "$image" \
        /bin/sh -lc "mkdir -p ${datadir} && touch ${datadir}/debug.log && chmod 644 ${datadir}/debug.log && exec /usr/local/bin/${daemon} -datadir=${datadir}" \
        >/dev/null
}

# Phase 1: confirm daemon images for all six coins (or pull from the
# registry if MPOS_PULL_DAEMON_IMAGES=1; step 19 already built them when
# MPOS_PULL_DAEMON_IMAGES=0).
say "phase 1: images for all six coins"
for coin in "${COINS[@]}"; do
    pull_image "$coin"
done

# Phase 2: create every coin's data folder.
say "phase 2: data folders"
for coin in "${COINS[@]}"; do
    datadir="/root/${CONFIG_DIR[$coin]}"
    mkdir -p "$datadir"
    chmod 700 "$datadir"
    say "  ${coin}: ${datadir}"
done

# Phase 3: render every coin's config file inside its data folder.
# write_config no longer mkdir/chmods (phase 2 did that); it just renders
# the conf and chmod 600s it.
say "phase 3: config files"
for coin in "${COINS[@]}"; do
    write_config "$coin"
    write_wrapper "$coin"
done

if [ "${SKIP_BOOTSTRAP:-0}" = "1" ]; then
    say "SKIP_BOOTSTRAP=1 — launching all 6 daemons with peering ON now"
    for coin in "${COINS[@]}"; do
        launch_coin "$coin"
    done

    say "daemon container status"
    docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' | head -1
    for coin in "${COINS[@]}"; do
        docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' \
            | grep "^${coin} " || warn "${coin} container not running"
    done

    say "step 20 done — daemons starting (SKIP_BOOTSTRAP); step 30 will wait for RPC"
else
    say "step 20 done — datadirs + configs + images ready; step 21 will stage bootstraps and start daemons"
fi
