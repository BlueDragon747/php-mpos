#!/usr/bin/env bash
# Interactive chain-tip rollback for mainnet daemon containers.
#
# This tool does not edit blk*.dat, rev*.dat, chainstate, or wallet files.
# It uses the daemon RPC invalidateblock call to move a selected chain's
# active tip back to a target height. Use filesystem/provider snapshots for
# full datadir rollback.
set -euo pipefail

say() { printf '\033[1;33m   %s\033[0m\n' "$*"; }
warn() { printf '\033[1;31m   warning: %s\033[0m\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" = "0" ] || die "run as root"

if [ -f /root/.mpos-deploy.env ]; then
    # shellcheck disable=SC1091
    . /root/.mpos-deploy.env
fi

export MPOS_NODE_RPC_USER="${MPOS_NODE_RPC_USER:?MPOS_NODE_RPC_USER is required}"
export MPOS_NODE_RPC_PASS="${MPOS_NODE_RPC_PASS:?MPOS_NODE_RPC_PASS is required}"
export MPOS_LOG_ROOT="${MPOS_LOG_ROOT:-/var/log/blakestream-mpos}"
export MPOS_ROLLBACK_REQUIRE_WALLET_BACKUP="${MPOS_ROLLBACK_REQUIRE_WALLET_BACKUP:-1}"

COINS=(blc pho bbtc elt lit umo)
declare -A COIN_LABEL=(
    [blc]="Blakecoin"
    [pho]="Photon"
    [bbtc]="BlakeBitcoin"
    [elt]="Electron"
    [lit]="Lithium"
    [umo]="UniversalMolecule"
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

unit_exists() {
    systemctl cat "$1" >/dev/null 2>&1
}

stop_pool_services() {
    say "stopping Stratum server before chain rollback"
    if unit_exists blakestream-mpos-eloipool.service; then
        systemctl stop blakestream-mpos-eloipool.service
    else
        say "Stratum service not installed; skipping"
    fi

    say "stopping merged-mine proxy before chain rollback"
    if unit_exists blakestream-mpos-mergeminer.service; then
        systemctl stop blakestream-mpos-mergeminer.service
    else
        say "merged-mine proxy service not installed; skipping"
    fi
}

start_pool_services() {
    say "starting Stratum server after chain rollback"
    if unit_exists blakestream-mpos-eloipool.service; then
        systemctl start blakestream-mpos-eloipool.service
    fi

    say "starting merged-mine proxy after chain rollback"
    if unit_exists blakestream-mpos-mergeminer.service; then
        systemctl start blakestream-mpos-mergeminer.service
    fi
}

is_known_coin() {
    local candidate="$1" coin
    for coin in "${COINS[@]}"; do
        [ "$candidate" = "$coin" ] && return 0
    done
    return 1
}

docker_cli() {
    local coin="$1"
    shift
    docker exec "$coin" "/usr/local/bin/${CLI_NAME[$coin]}" "-datadir=/root/${CONFIG_DIR[$coin]}" "$@"
}

coin_rpc() {
    local coin="$1"
    shift
    docker_cli "$coin" "$@" | tr -d '\r'
}

require_container_running() {
    local coin="$1"
    if ! docker ps --format '{{.Names}}' | grep -qx "$coin"; then
        die "${coin} container is not running; start the daemon before using RPC rollback"
    fi
}

backup_wallet() {
    local coin="$1"
    local stamp="$2"
    local datadir="/root/${CONFIG_DIR[$coin]}"
    local destination="${datadir}/rollback-wallet-${stamp}.dat"

    say "backing up ${coin} wallet to ${destination}"
    if docker_cli "$coin" backupwallet "$destination" >/dev/null 2>&1; then
        return 0
    fi

    if [ "$MPOS_ROLLBACK_REQUIRE_WALLET_BACKUP" = "1" ]; then
        die "${coin} wallet backup failed; set MPOS_ROLLBACK_REQUIRE_WALLET_BACKUP=0 only if you understand the risk"
    fi
    warn "${coin} wallet backup failed; continuing because MPOS_ROLLBACK_REQUIRE_WALLET_BACKUP=0"
}

read_coin_selection() {
    local raw item selected=()

    printf '\nAvailable chains:\n' >&2
    printf '  %s\n' "${COINS[*]}" >&2
    printf "Enter chains to roll back, separated by spaces, or 'all': " >&2
    read -r raw

    if [ "$raw" = "all" ]; then
        selected=("${COINS[@]}")
    else
        for item in $raw; do
            item="${item,,}"
            is_known_coin "$item" || die "unknown chain: ${item}"
            selected+=("$item")
        done
    fi

    [ "${#selected[@]}" -gt 0 ] || die "no chains selected"
    printf '%s\n' "${selected[@]}"
}

read_target_height() {
    local coin="$1"
    local current="$2"
    local target

    while :; do
        printf "Target height for %s (%s), current %s: " "$coin" "${COIN_LABEL[$coin]}" "$current" >&2
        read -r target
        if [[ "$target" =~ ^[0-9]+$ ]] && [ "$target" -lt "$current" ]; then
            printf '%s\n' "$target"
            return
        fi
        warn "enter a numeric height lower than current height ${current}"
    done
}

confirm_plan() {
    local reply
    printf '\nType ROLLBACK to stop pool services and apply this plan: '
    read -r reply
    [ "$reply" = "ROLLBACK" ] || die "aborted"
}

main() {
    local selected=()
    local coin current target invalidate_height invalidate_hash target_hash tip_hash
    local stamp manifest restart_reply
    declare -A CURRENT_HEIGHT=()
    declare -A TARGET_HEIGHT=()
    declare -A INVALIDATE_HEIGHT=()
    declare -A INVALIDATE_HASH=()
    declare -A TARGET_HASH=()
    declare -A TIP_HASH=()

    command -v docker >/dev/null 2>&1 || die "docker is required"

    mapfile -t selected < <(read_coin_selection)
    stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    manifest="${MPOS_LOG_ROOT}/chain-rollback-${stamp}.log"
    mkdir -p "$MPOS_LOG_ROOT"

    say "collecting current chain tips"
    for coin in "${selected[@]}"; do
        require_container_running "$coin"
        current="$(coin_rpc "$coin" getblockcount)"
        tip_hash="$(coin_rpc "$coin" getbestblockhash)"
        target="$(read_target_height "$coin" "$current")"
        invalidate_height=$((target + 1))
        invalidate_hash="$(coin_rpc "$coin" getblockhash "$invalidate_height")"
        target_hash="$(coin_rpc "$coin" getblockhash "$target")"

        CURRENT_HEIGHT[$coin]="$current"
        TARGET_HEIGHT[$coin]="$target"
        INVALIDATE_HEIGHT[$coin]="$invalidate_height"
        INVALIDATE_HASH[$coin]="$invalidate_hash"
        TARGET_HASH[$coin]="$target_hash"
        TIP_HASH[$coin]="$tip_hash"
    done

    printf '\nRollback plan:\n'
    for coin in "${selected[@]}"; do
        printf '  %-5s current=%s target=%s invalidate_height=%s invalidate_hash=%s\n' \
            "$coin" "${CURRENT_HEIGHT[$coin]}" "${TARGET_HEIGHT[$coin]}" \
            "${INVALIDATE_HEIGHT[$coin]}" "${INVALIDATE_HASH[$coin]}"
    done
    printf '\nThis marks block target+1 and descendants invalid. It does not delete block files.\n'
    printf 'Use reconsiderblock with the logged invalidate hash to undo this RPC rollback.\n'
    confirm_plan

    {
        printf 'chain rollback manifest %s\n' "$stamp"
        printf 'operator=%s host=%s\n' "${SUDO_USER:-root}" "$(hostname -f 2>/dev/null || hostname)"
    } >"$manifest"

    stop_pool_services

    for coin in "${selected[@]}"; do
        backup_wallet "$coin" "$stamp"
        say "rolling back ${coin}: invalidate block ${INVALIDATE_HASH[$coin]} at height ${INVALIDATE_HEIGHT[$coin]}"
        coin_rpc "$coin" invalidateblock "${INVALIDATE_HASH[$coin]}" >/dev/null
        current="$(coin_rpc "$coin" getblockcount)"
        {
            printf '\n[%s]\n' "$coin"
            printf 'label=%s\n' "${COIN_LABEL[$coin]}"
            printf 'old_tip_height=%s\n' "${CURRENT_HEIGHT[$coin]}"
            printf 'old_tip_hash=%s\n' "${TIP_HASH[$coin]}"
            printf 'target_height=%s\n' "${TARGET_HEIGHT[$coin]}"
            printf 'target_hash=%s\n' "${TARGET_HASH[$coin]}"
            printf 'invalidated_height=%s\n' "${INVALIDATE_HEIGHT[$coin]}"
            printf 'invalidated_hash=%s\n' "${INVALIDATE_HASH[$coin]}"
            printf 'height_after=%s\n' "$current"
            printf 'undo_rpc=docker exec %s /usr/local/bin/%s -datadir=/root/%s reconsiderblock %s\n' \
                "$coin" "${CLI_NAME[$coin]}" "${CONFIG_DIR[$coin]}" "${INVALIDATE_HASH[$coin]}"
        } >>"$manifest"
        say "${coin} height after rollback: ${current}"
        if [ "$current" != "${TARGET_HEIGHT[$coin]}" ]; then
            warn "${coin} height after rollback is ${current}, expected ${TARGET_HEIGHT[$coin]}; review ${manifest} before restarting pool services"
        fi
    done

    say "rollback manifest written to ${manifest}"
    printf '\nRestart pool services now? Only do this if the selected daemon tips are intentional. [y/N]: '
    read -r restart_reply
    if [[ "$restart_reply" =~ ^[Yy]$ ]]; then
        start_pool_services
    else
        say "pool services left stopped; start them manually after verification"
    fi
}

main "$@"
