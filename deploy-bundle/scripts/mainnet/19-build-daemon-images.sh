#!/usr/bin/env bash
# 19-build-daemon-images.sh — clone coin repos and build local daemon images.
#
# This is the source-build path used when MPOS_PULL_DAEMON_IMAGES=0. It builds
# daemon binaries through each coin repo's Docker-backed build.sh, then packages
# those binaries into the same runtime image shape used by the normal deploy.
set -euo pipefail

say()  { printf '\033[1;33m   %s\033[0m\n' "$*"; }
warn() { printf '\033[1;31m!! %s\033[0m\n' "$*" >&2; }

MPOS_DOCKER_HUB="${MPOS_DOCKER_HUB:-local}"
MPOS_IMAGE_TAG="${MPOS_IMAGE_TAG:-25.2-local}"
# Pre-live: source-build daemons from the 0.25.2 wallet branches. Change to
# master after live cutover once master carries the 25.2 wallet updates.
MPOS_DAEMON_SOURCE_REF="${MPOS_DAEMON_SOURCE_REF:-0.25.2}"
MPOS_DAEMON_BUILD_ROOT="${MPOS_DAEMON_BUILD_ROOT:-/root/blakestream-daemon-builds}"
MPOS_DAEMON_BUILD_JOBS="${MPOS_DAEMON_BUILD_JOBS:-}"
MPOS_DAEMON_BUILD_DOCKER_MODE="${MPOS_DAEMON_BUILD_DOCKER_MODE:-pull}"

if [ -z "$MPOS_DAEMON_BUILD_JOBS" ]; then
    cpu_count="$(nproc 2>/dev/null || echo 2)"
    MPOS_DAEMON_BUILD_JOBS=$((cpu_count > 1 ? cpu_count - 1 : 1))
fi

case "$MPOS_DAEMON_BUILD_DOCKER_MODE" in
    pull)  build_docker_arg="--pull-docker" ;;
    build) build_docker_arg="--build-docker" ;;
    *)     warn "MPOS_DAEMON_BUILD_DOCKER_MODE must be pull or build"; exit 1 ;;
esac

COINS=(blc pho bbtc elt lit umo)

# Wallet repos are pinned by MPOS_DAEMON_SOURCE_REF. Use 0.25.2 for pre-live
# 25.2 builds; change the source ref to master after live cutover.
declare -A COIN_REPO=(
    [blc]="https://github.com/BlueDragon747/Blakecoin.git"
    [pho]="https://github.com/BlueDragon747/photon.git"
    [bbtc]="https://github.com/BlakeBitcoin/BlakeBitcoin.git"
    [elt]="https://github.com/BlueDragon747/Electron-ELT.git"
    [lit]="https://github.com/BlueDragon747/lithium.git"
    [umo]="https://github.com/BlueDragon747/universalmol.git"
)
declare -A COIN_SOURCE_DIR=(
    [blc]="Blakecoin"
    [pho]="photon"
    [bbtc]="BlakeBitcoin"
    [elt]="Electron-ELT"
    [lit]="lithium"
    [umo]="universalmol"
)
declare -A COIN_IMAGE_NAME=(
    [blc]="blakecoin"
    [pho]="photon"
    [bbtc]="blakebitcoin"
    [elt]="electron"
    [lit]="lithium"
    [umo]="universalmolecule"
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
declare -A TX_NAME=(
    [blc]="blakecoin-tx"
    [pho]="photon-tx"
    [bbtc]="blakebitcoin-tx"
    [elt]="electron-tx"
    [lit]="lithium-tx"
    [umo]="universalmolecule-tx"
)

coin_image() {
    local coin="$1"
    printf '%s/%s:%s' "$MPOS_DOCKER_HUB" "${COIN_IMAGE_NAME[$coin]}" "$MPOS_IMAGE_TAG"
}

sync_repo() {
    local coin="$1"
    local repo="${COIN_REPO[$coin]}"
    local dir="$MPOS_DAEMON_BUILD_ROOT/${COIN_SOURCE_DIR[$coin]}"

    mkdir -p "$MPOS_DAEMON_BUILD_ROOT"
    if [ -d "$dir/.git" ]; then
        say "updating ${coin} source at ${dir}"
        git -C "$dir" fetch --depth 1 origin "$MPOS_DAEMON_SOURCE_REF"
        git -C "$dir" checkout -B "$MPOS_DAEMON_SOURCE_REF" FETCH_HEAD
        git -C "$dir" reset --hard FETCH_HEAD
    else
        say "cloning ${coin} source from ${repo}"
        rm -rf "$dir"
        git clone --depth 1 --branch "$MPOS_DAEMON_SOURCE_REF" "$repo" "$dir"
    fi
}

build_coin_binaries() {
    local coin="$1"
    local dir="$MPOS_DAEMON_BUILD_ROOT/${COIN_SOURCE_DIR[$coin]}"

    say "building ${coin} daemon binaries"
    chmod +x "$dir/build.sh"
    (
        cd "$dir"
        OUTPUT_BASE="$dir/outputs" ./build.sh --native --daemon "$build_docker_arg" --jobs "$MPOS_DAEMON_BUILD_JOBS"
    )
}

package_coin_image() {
    local coin="$1"
    local dir="$MPOS_DAEMON_BUILD_ROOT/${COIN_SOURCE_DIR[$coin]}"
    local output_dir="$dir/outputs/Ubuntu-24"
    local image daemon cli tx

    image="$(coin_image "$coin")"
    daemon="${DAEMON_NAME[$coin]}"
    cli="${CLI_NAME[$coin]}"
    tx="${TX_NAME[$coin]}"

    for bin in "$daemon" "$cli" "$tx"; do
        if [ ! -x "$output_dir/$bin" ]; then
            warn "missing expected ${coin} build output: $output_dir/$bin"
            exit 1
        fi
    done

    say "packaging ${coin} runtime image ${image}"
    # Keep this runtime base aligned with the Ubuntu-24 daemon outputs.
    docker build -t "$image" -f - "$output_dir" <<EOF
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qq \\
    && apt-get install -y -qq --no-install-recommends \\
        ca-certificates \\
        libboost-filesystem1.83.0 \\
        libboost-program-options1.83.0 \\
        libboost-thread1.83.0 \\
        libboost-chrono1.83.0 \\
        libevent-2.1-7 \\
        libevent-pthreads-2.1-7 \\
        libminiupnpc17 \\
        libsqlite3-0 \\
        libssl3 \\
        libstdc++6 \\
        libzmq5 \\
    && rm -rf /var/lib/apt/lists/*
COPY ${daemon} /usr/local/bin/${daemon}
COPY ${cli} /usr/local/bin/${cli}
COPY ${tx} /usr/local/bin/${tx}
RUN chmod 0755 /usr/local/bin/${daemon} /usr/local/bin/${cli} /usr/local/bin/${tx}
EOF

    docker run --rm --entrypoint /bin/sh "$image" -lc \
        "/usr/local/bin/${daemon} --version >/dev/null 2>&1 || /usr/local/bin/${daemon} -version >/dev/null"
}

say "daemon source ref: ${MPOS_DAEMON_SOURCE_REF}"
say "daemon image tag: ${MPOS_DOCKER_HUB}/<coin>:${MPOS_IMAGE_TAG}"

MPOS_FORCE_REBUILD="${MPOS_FORCE_REBUILD:-0}"
BUILD_CONCURRENCY="${BUILD_CONCURRENCY:-3}"
MPOS_LOG_ROOT="${MPOS_LOG_ROOT:-/var/log/blakestream-mpos}"
MONITOR_LOG="${MPOS_LOG_ROOT}/build-monitor.log"
mkdir -p "$MPOS_LOG_ROOT"
: > "$MONITOR_LOG"

# Background system-usage monitor. One 30 s snapshot per line so we can
# tell at the end whether building 3 coins concurrently strained the
# 15 GB / 4-vCPU host.
(
    while sleep 30; do
        ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        mem_used_pct=$(awk -v t=$(awk '/^MemTotal:/{print $2}' /proc/meminfo) \
                          -v a=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo) \
                          'BEGIN{printf "%.1f", (t-a)*100/t}')
        swap_mb=$(awk '/^SwapTotal:/{tot=$2} /^SwapFree:/{free=$2} END{print int((tot-free)/1024)}' /proc/meminfo)
        load1=$(awk '{print $1}' /proc/loadavg)
        containers=$(docker ps -q 2>/dev/null | wc -l)
        printf '%s mem_used_pct=%s swap_mb=%s load1=%s containers=%s\n' \
            "$ts" "$mem_used_pct" "$swap_mb" "$load1" "$containers"
    done
) >> "$MONITOR_LOG" 2>&1 &
MONITOR_PID=$!

cleanup_monitor() {
    [ -n "${MONITOR_PID:-}" ] && kill "$MONITOR_PID" 2>/dev/null || true
}
trap cleanup_monitor EXIT

build_one_coin() {
    local coin="$1"
    local image
    image="$(coin_image "$coin")"
    if [ "$MPOS_FORCE_REBUILD" != "1" ] && docker image inspect "$image" >/dev/null 2>&1; then
        say "skipping ${coin} build — image ${image} already present (MPOS_FORCE_REBUILD=1 to override)"
        return 0
    fi
    sync_repo "$coin"
    build_coin_binaries "$coin"
    package_coin_image "$coin"
}

say "building daemons with concurrency ${BUILD_CONCURRENCY} (monitor: ${MONITOR_LOG})"
PIDS=()
BUILD_FAIL=0
for coin in "${COINS[@]}"; do
    while [ "${#PIDS[@]}" -ge "$BUILD_CONCURRENCY" ]; do
        wait -n 2>/dev/null || BUILD_FAIL=1
        survivors=()
        for p in "${PIDS[@]}"; do
            kill -0 "$p" 2>/dev/null && survivors+=("$p")
        done
        PIDS=("${survivors[@]}")
    done
    say "  spawning build for ${coin}"
    ( build_one_coin "$coin" ) &
    PIDS+=($!)
done
# Drain remaining
for p in "${PIDS[@]}"; do
    wait "$p" || {
        warn "build pid $p exited non-zero"
        BUILD_FAIL=1
    }
done

if [ "$BUILD_FAIL" = "1" ]; then
    warn "one or more daemon image builds failed"
    exit 1
fi

cleanup_monitor

say "local daemon images built"
docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}' \
    | awk -v hub="$MPOS_DOCKER_HUB/" -v tag="$MPOS_IMAGE_TAG" '$1 ~ "^" hub && $2 == tag {print}'

say "build system-usage summary (from ${MONITOR_LOG}, 30 s snapshots):"
awk -F'[ =]' '
    /mem_used_pct=/ {
        samples++
        for (i=1; i<=NF; i++) {
            if ($i == "mem_used_pct" && $(i+1)+0 > max_mem) max_mem = $(i+1)+0
            if ($i == "swap_mb"      && $(i+1)+0 > max_swap) max_swap = $(i+1)+0
            if ($i == "load1"        && $(i+1)+0 > max_load) max_load = $(i+1)+0
            if ($i == "containers"   && $(i+1)+0 > max_cont) max_cont = $(i+1)+0
        }
    }
    END {
        if (samples == 0) { print "   (no monitor samples collected)"; exit }
        printf "   samples:        %d (30 s each, ~%d min covered)\n", samples, samples*30/60
        printf "   peak mem_used:  %.1f %%\n", max_mem
        printf "   peak swap:      %d MB\n",   max_swap
        printf "   peak load1:     %.2f\n",    max_load
        printf "   peak containers: %d\n",     max_cont
    }
' "$MONITOR_LOG"
