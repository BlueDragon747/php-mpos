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
  sudo bash deploy-bundle/update-mainnet.sh --all

Options:
  --mpos       Update MPOS web files, DB migrations, cronjobs-py, SSE,
               share-log importer, System Status collector, and backup timer.
  --eloipool   Update Go Eloipool and merged-mining proxy services.
  --daemons    Update wallet daemon images/containers without bootstrap replay.
               Set MPOS_PULL_DAEMON_IMAGES=0 to rebuild daemon images locally.
  --wallets    Alias for --daemons.
  --all        Run --daemons, --eloipool, then --mpos.

The updater reads /root/.mpos-deploy.env when present, then applies any
environment overrides supplied on this command.
EOF
}

say() { printf '\033[1;33m   %s\033[0m\n' "$*"; }
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

update_daemons() {
    sync_mpos_repo
    if [ "$MPOS_PULL_DAEMON_IMAGES" = "0" ] && [ "$SKIP_DAEMON_IMAGE_BUILD" != "1" ]; then
        bash "${MAINNET_SCRIPTS}/19-build-daemon-images.sh"
    fi
    bash "${MAINNET_SCRIPTS}/20-deploy-daemons.sh"
    bash "${MAINNET_SCRIPTS}/30-wait-rpc.sh"
}

update_eloipool() {
    sync_mpos_repo
    sync_eloipool_repo
    bash "${MAINNET_SCRIPTS}/40-install-pool.sh"
}

update_mpos() {
    sync_mpos_repo
    bash "${MAINNET_SCRIPTS}/50-install-mpos.sh"
    bash "${MAINNET_SCRIPTS}/60-install-php-cron.sh"
    bash "${MAINNET_SCRIPTS}/70-install-cronjobs-py.sh"
    bash "${MAINNET_SCRIPTS}/75-install-sse.sh"
    bash "${MAINNET_SCRIPTS}/76-install-sharelog-importer.sh"
    bash "${SCRIPT_DIR}/scripts/77-install-system-status-cache.sh"
    bash "${MAINNET_SCRIPTS}/85-install-logrotate.sh"
    bash "${MAINNET_SCRIPTS}/90-install-backup.sh"
}

run_mpos=0
run_eloipool=0
run_daemons=0

for arg in "$@"; do
    case "$arg" in
        --mpos|-mpos) run_mpos=1 ;;
        --eloipool|--eloi|-eloipool|-eloi) run_eloipool=1 ;;
        --daemons|--daemon|--wallets|--wallet|-daemons|-daemon|-wallets|-wallet) run_daemons=1 ;;
        --all|-all) run_daemons=1; run_eloipool=1; run_mpos=1 ;;
        *) die "unknown option: $arg" ;;
    esac
done

if [ "$run_mpos$run_eloipool$run_daemons" = "000" ]; then
    usage
    exit 1
fi

if [ "$run_daemons" = "1" ]; then update_daemons; fi
if [ "$run_eloipool" = "1" ]; then update_eloipool; fi
if [ "$run_mpos" = "1" ]; then update_mpos; fi

say "update complete"
