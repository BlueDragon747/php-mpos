#!/usr/bin/env bash
# Blakestream-MPOS mainnet deploy entry point.
#
# Pipeline (per the operator's spec, top-down):
#
#   1. Pull or reuse the six mainnet daemon Docker images.
#   2. Create data folders, render configs with active mainnet peer
#      addnodes (from explorer.blakestream.io), and stage daemon images.
#   3. If bootstrap is enabled, download each coin bootstrap and start
#      each 25.2 daemon with -loadblock=<datadir>/bootstrap.dat so ELT/UMO
#      do not OOM the host.
#   4. Wait for every daemon's RPC to respond.
#   5. Push the Blakestream-Eliopool tree (or its tarball) and stand up
#      eloipool stratum + merged-mine-proxy with MAINNET ports.
#   6. Push Blakestream-MPOS, install MariaDB schema, render
#      `global.inc.php` with mainnet wallet RPC ports + mainnet HRP
#      bech32 ('blc' etc.) + mainnet base58 prefixes.
#   7. Stage the PHP cronjobs/ tree under /opt/blakestream-mpos/
#      (for ad-hoc diagnostic invocations only — NOT scheduled).
#   8. Install + start cronjobs-py as the AUTHORITATIVE scheduler.
#      (Drift mode is documented in 70-install-cronjobs-py.sh and
#      can be enabled per-host for rebase soak windows.)
#   9. Install the share-log importer so Go Eloipool shares feed the MPOS
#      MariaDB `shares` table used by dashboard, statistics, and payouts.
#
# Usage:
#   sudo bash deploy-bundle/deploy-mainnet.sh
#   bash deploy-bundle/deploy-mainnet.sh <ssh-host>
#   bash deploy-bundle/deploy-mainnet.sh <your-host-alias>
#
# Pre-reqs (local mode, on the pool server):
#   - Run as root or through sudo
#   - Repo cloned locally
#   - rsync, curl, git, bun
#
# Pre-reqs (SSH mode, on this dev box, NOT the VPS):
#   - SSH key auth to <ssh-host> as root (use ssh-copy-id first)
#   - rsync, ssh, curl, git, bun
#
# Pre-reqs (SSH mode, on the VPS): nothing — this script installs everything.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

MPOS_REPO_URL="${MPOS_REPO_URL:-https://github.com/SidGrip/php-mpos.git}"
# Pre-live: use 25.2-GO until the Go Eloipool cutover is live, then switch
# ELIOPOOL_BRANCH to master once master carries these updates.
ELIOPOOL_REPO_URL="${ELIOPOOL_REPO_URL:-https://github.com/BlueDragon747/eloipool_Blakecoin.git}"
ELIOPOOL_BRANCH="${ELIOPOOL_BRANCH:-25.2-GO}"
ELIOPOOL_TMPROOT=""
ENVRC=""

cleanup() {
    # Preserve the script's incoming exit code so set -e failures
    # aren't masked by the trap. Previously `return 0` always reported
    # success to the SSH wrapper even when the deploy aborted mid-step.
    local rc=$?
    if [ -n "${ELIOPOOL_TMPROOT}" ]; then
        rm -rf "${ELIOPOOL_TMPROOT}"
    fi
    if [ -n "${ENVRC}" ]; then
        rm -f "${ENVRC}"
    fi
    return $rc
}
trap cleanup EXIT

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    cat <<EOF
Usage:
  $0              # local install on this server
  $0 <ssh-host>   # remote install over SSH

Deploy a mainnet Blakestream-MPOS pool.

  $0                   # run on the pool server from a local repo clone
  $0 <your-host-alias> # SSH alias from ~/.ssh/config
  $0 root@1.2.3.4      # raw user@host

Source repos:
  Run this script from a clone of:
    ${MPOS_REPO_URL}

  Eliopool is optional locally. If ELIOPOOL_TREE is unset, this script
  clones:

    ${ELIOPOOL_REPO_URL} branch ${ELIOPOOL_BRANCH}

Daemon images:
  The six coin daemons are pulled directly from Docker Hub by default:

    \${MPOS_DOCKER_HUB:-sidgrip}/<coin>:\${MPOS_IMAGE_TAG:-25.2}

  To clone the coin repos and build local runtime images on the target
  server instead of pulling daemon images:

    MPOS_PULL_DAEMON_IMAGES=0

Tunables (env):
  MPOS_DOCKER_HUB     Docker Hub org/user for coin daemon images
                       (default: sidgrip when pulling, local when building).
  MPOS_IMAGE_TAG      Docker image tag for all daemon images
                       (default: 25.2 when pulling, 25.2-local when building).
  MPOS_PULL_DAEMON_IMAGES
                       1 pulls daemon images; 0 clones coin repos and builds
                       local daemon images first (default: 1).
  MPOS_DAEMON_SOURCE_REF
                       Branch/tag used for source builds (default: 0.25.2).
                       Switch to master after live cutover.
  MPOS_DAEMON_BUILD_ROOT
                       Source-build working directory
                       (default: /root/blakestream-daemon-builds).
  MPOS_DAEMON_BUILD_JOBS
                       Parallel build jobs (default: CPU cores - 1).
  MPOS_DAEMON_BUILD_DOCKER_MODE
                       pull uses prebuilt native-base build image; build builds
                       the native-base image locally (default: pull).
  SKIP_DAEMON_IMAGE_BUILD
                       With MPOS_PULL_DAEMON_IMAGES=0, skip source builds and
                       use already-loaded local daemon images (default: 0).
  MPOS_EXPLORER_API_BASE
                       Explorer API used to fetch addnode peers
                       (default: https://explorer.blakestream.io/api).
  BOOTSTRAP_URL       Base URL for 25.2 bootstrap discovery
                       (default: https://bootstrap.blakestream.io).
  BOOTSTRAP_SERIES    Bootstrap series path (default: 25.2).
  BOOTSTRAP_MIRROR_DISCOVERY
                       1 queries mirrors.json and probes mirrors; 0 uses
                       BOOTSTRAP_URL directly (default: 1).
  BOOTSTRAP_MIRROR_HOST
                       Optional fixed mirror hostname override.
  ELIOPOOL_TREE        Local checkout of eloipool_Blakecoin
                       (optional; auto-cloned from \${ELIOPOOL_REPO_URL}
                       on branch \${ELIOPOOL_BRANCH} if unset).
  ELIOPOOL_REPO_URL    git URL to clone Eliopool from when ELIOPOOL_TREE
                       is unset (default: ${ELIOPOOL_REPO_URL}).
  ELIOPOOL_BRANCH      branch to clone (default: ${ELIOPOOL_BRANCH}).
  MPOS_DOMAIN          Public domain (default: _, catch-all)
  MPOS_HTTP_PORT       Web UI port (default: 80)
  MPOS_STRATUM_PORT    Stratum bind port (default: 3334)
  MPOS_SSH_PORT        SSH port to keep open in UFW
                       (default: 22 in local mode; ssh -G in SSH mode)
  MPOS_DB_PASS         DB password (default: random 32 hex)
  MPOS_ADMIN_USER      Admin login (default: admin)
  MPOS_ADMIN_PASS      Admin password (default: random 32 hex)
  MPOS_NODE_RPC_USER   Pool's RPC user across daemons (default: blakestream)
  MPOS_NODE_RPC_PASS   Pool's RPC pass (default: random)
  BOOTSTRAP_IMPORT_TIMEOUT_S
                       Max seconds per coin waiting for bootstrap.dat import
                       (default: 21600)
  BOOTSTRAP_IMPORT_SLEEP_S
                       Poll interval while bootstrap.dat imports (default: 60)
  BOOTSTRAP_DOWNLOAD_ATTEMPTS
                       Download attempts per bootstrap.dat file (default: 12)
  BOOTSTRAP_DOWNLOAD_RETRY_SLEEP_S
                       Seconds between bootstrap.dat download retries (default: 60)
  BOOTSTRAP_DOWNLOAD_CONNECT_TIMEOUT_S
                       wget connect timeout for bootstrap downloads (default: 30)
  BOOTSTRAP_DOWNLOAD_READ_TIMEOUT_S
                       wget read timeout for bootstrap downloads (default: 90)
  TIP_CATCH_TIMEOUT_S  Max seconds per coin waiting for p2p tip catch-up
                       (default: 7200)
  TIP_CATCH_LAG        Allowed blocks behind peer-reported tip (default: 5)
  SKIP_DAEMONS         Skip daemon image pull/config/start (already done)
  SKIP_BOOTSTRAP       Skip sequential bootstrap.dat replay (rely on p2p sync)

Daemon image examples:
  # Default: pull sidgrip/<coin>:25.2
  $0

  # Clone coin repos and build local/<coin>:25.2-local runtime images
  MPOS_PULL_DAEMON_IMAGES=0 $0

  # Use already-loaded custom images without pulling or building
  MPOS_DOCKER_HUB=local MPOS_IMAGE_TAG=25.2-test \\
  MPOS_PULL_DAEMON_IMAGES=0 SKIP_DAEMON_IMAGE_BUILD=1 $0

Source-build notes:
  - Requires Docker and enough disk for six source trees/build outputs.
  - Plan for about 15 GB free under MPOS_DAEMON_BUILD_ROOT.
  - SKIP_DAEMON_IMAGE_BUILD=1 assumes images are already tagged as:
    \${MPOS_DOCKER_HUB}/<coin>:\${MPOS_IMAGE_TAG}

Bootstrap examples:
  # Default public bootstrap pull
  $0

  # Local/private bootstrap mirror with /25.2/*.dat.xz and sidecars
  BOOTSTRAP_URL=http://127.0.0.1:8080 $0

  # Skip bootstrap replay and sync from peers
  SKIP_BOOTSTRAP=1 $0
EOF
    exit 0
fi

say() { printf '\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

LOCAL_DEPLOY=0
HOST="${1:-}"
case "${HOST}" in
    "")
        LOCAL_DEPLOY=1
        HOST="localhost"
        ;;
    --local|-local|local|localhost|127.0.0.1)
        LOCAL_DEPLOY=1
        HOST="localhost"
        ;;
esac

if [ "${LOCAL_DEPLOY}" = "1" ] && [ "$(id -u)" != "0" ]; then
    die "local install must be run as root (use sudo -E bash deploy-bundle/deploy-mainnet.sh)"
fi

# Eliopool: prefer a local checkout if ELIOPOOL_TREE is set; otherwise
# auto-clone the published repo into a temp dir so the deploy is
# self-contained for users who only have the MPOS repo.
if [ -z "${ELIOPOOL_TREE:-}" ]; then
    ELIOPOOL_TMPROOT="$(mktemp -d)"
    ELIOPOOL_TREE="${ELIOPOOL_TMPROOT}/eloipool"
    git clone --depth 1 -b "${ELIOPOOL_BRANCH}" "${ELIOPOOL_REPO_URL}" "${ELIOPOOL_TREE}"
fi

# Pre-flight: paths exist locally. SSH mode also verifies remote auth.
[ -d "${ELIOPOOL_TREE}" ] || die "eloipool_Blakecoin checkout not found at ${ELIOPOOL_TREE}"

host_run() {
    if [ "${LOCAL_DEPLOY}" = "1" ]; then
        bash -lc "$1"
    else
        ssh "${HOST}" "$1"
    fi
}

if [ "${LOCAL_DEPLOY}" = "1" ]; then
    say "local deploy mode on this server"
    export MPOS_SSH_PORT="${MPOS_SSH_PORT:-22}"
else
    say "checking SSH auth to ${HOST}"
    ssh -o BatchMode=yes -o ConnectTimeout=10 "${HOST}" 'echo ok' >/dev/null \
        || die "ssh to ${HOST} failed (need passwordless key auth - run ssh-copy-id first)"

    SSH_PORT_DETECTED="$(ssh -G "${HOST}" 2>/dev/null | awk '/^port / {print $2; exit}')"
    export MPOS_SSH_PORT="${MPOS_SSH_PORT:-${SSH_PORT_DETECTED:-22}}"
fi

# random_hex producing N hex characters (8 = 32 bits, 32 = 128 bits, ...)
random_hex() { head -c "$1" /dev/urandom | xxd -p -c 256 | head -c "$1"; }

# Reuse a previous deploy's tunables if /root/.mpos-deploy.env exists on
# the VPS. The DB password, RPC creds, salts, etc. get baked into the
# daemon configs and the DB on first run; regenerating them on a re-run
# would silently break things. We override only when the operator
# explicitly sets the matching env var on this run.
say "checking for prior deploy state on ${HOST}"
# Source-of-truth: the actual rpcuser/rpcpassword baked into the
# blakecoin daemon's config file. If a prior run's
# /root/.mpos-deploy.env got out of sync (deploy aborted between
# step 20 and step 99) the env's MPOS_NODE_RPC_PASS would not match
# what the daemons authenticate against; reading from the conf is
# always correct.
DAEMON_RPC_USER="$(host_run 'grep -m1 ^rpcuser= /root/.blakecoin/blakecoin.conf 2>/dev/null | cut -d= -f2' || true)"
DAEMON_RPC_PASS="$(host_run 'grep -m1 ^rpcpassword= /root/.blakecoin/blakecoin.conf 2>/dev/null | cut -d= -f2' || true)"
if [ -n "${DAEMON_RPC_USER}" ] && [ -n "${DAEMON_RPC_PASS}" ]; then
    say "adopting RPC creds from /root/.blakecoin/blakecoin.conf"
    : "${MPOS_NODE_RPC_USER:=${DAEMON_RPC_USER}}"
    : "${MPOS_NODE_RPC_PASS:=${DAEMON_RPC_PASS}}"
    export MPOS_NODE_RPC_USER MPOS_NODE_RPC_PASS
fi

LIVE_STRATUM_PORT="$(host_run "python3 - <<'PY' 2>/dev/null || true
import re
from pathlib import Path
cfg = Path('/opt/blakestream-mpos/eloipool/config.py')
if cfg.is_file():
    m = re.search(r'StratumAddresses\\s*=\\s*\\(\\(\\s*[\\\"\\'][^\\\"\\']*[\\\"\\']\\s*,\\s*(\\d{2,5})', cfg.read_text(errors='ignore'))
    if m:
        print(m.group(1))
PY
")"
if [ -z "${MPOS_STRATUM_PORT+x}" ] && [[ "${LIVE_STRATUM_PORT}" =~ ^[1-9][0-9]{0,4}$ ]]; then
    say "adopting stratum port ${LIVE_STRATUM_PORT} from live eloipool config"
    MPOS_STRATUM_PORT="${LIVE_STRATUM_PORT}"
    export MPOS_STRATUM_PORT
fi

PRIOR_ENV="$(host_run 'cat /root/.mpos-deploy.env 2>/dev/null' || true)"
if [ -n "${PRIOR_ENV}" ]; then
    say "found prior /root/.mpos-deploy.env - adopting non-RPC values "
    say "  for keys the operator hasn't overridden in this run"
    while IFS= read -r line; do
        # Skip blanks / comments / non-export lines.
        [[ "$line" =~ ^export[[:space:]]+([A-Z_][A-Z0-9_]*)=(.*)$ ]] || continue
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        # RPC creds we already pinned from the daemon conf above —
        # don't let the env override the source of truth.
        if [ "$key" = "MPOS_NODE_RPC_USER" ] || [ "$key" = "MPOS_NODE_RPC_PASS" ]; then
            continue
        fi
        # Bootstrap timing, stratum port, and skip flags are operational
        # tunables, not persistent secrets. Let current defaults, the
        # operator's current environment, or live config win so an old
        # /root/.mpos-deploy.env cannot pin stale release values.
        case "$key" in
            MPOS_STRATUM_PORT|BOOTSTRAP_URL|BOOTSTRAP_SERIES|BOOTSTRAP_MIRROR_DISCOVERY|BOOTSTRAP_MIRROR_HOST|BOOTSTRAP_IMPORT_TIMEOUT_S|BOOTSTRAP_IMPORT_SLEEP_S|BOOTSTRAP_DOWNLOAD_ATTEMPTS|BOOTSTRAP_DOWNLOAD_RETRY_SLEEP_S|BOOTSTRAP_DOWNLOAD_CONNECT_TIMEOUT_S|BOOTSTRAP_DOWNLOAD_READ_TIMEOUT_S|TIP_CATCH_TIMEOUT_S|TIP_CATCH_LAG|SKIP_DAEMONS|SKIP_BOOTSTRAP)
                continue
                ;;
        esac
        # This file is generated by this script with simple, validated
        # values. Do not eval prior remote content.
        [[ "$value" =~ ^[A-Za-z0-9_@%+=:,./*-]+$ ]] || continue
        # If the operator already set ${key} in this shell, leave it.
        if [ -n "${!key+x}" ]; then continue; fi
        printf -v "$key" '%s' "$value"
        export "${key?}"
    done <<< "${PRIOR_ENV}"
fi

# Generate / accept tunables.
export MPOS_INSTALL_ROOT="${MPOS_INSTALL_ROOT:-/opt/blakestream-mpos}"
export MPOS_WEB_ROOT="${MPOS_WEB_ROOT:-/var/www/blakestream-mpos}"
export MPOS_LOG_ROOT="${MPOS_LOG_ROOT:-/var/log/blakestream-mpos}"
export MPOS_DOMAIN="${MPOS_DOMAIN:-_}"
export MPOS_HTTP_PORT="${MPOS_HTTP_PORT:-80}"
export MPOS_STRATUM_PORT="${MPOS_STRATUM_PORT:-3334}"
export MPOS_DB_NAME="${MPOS_DB_NAME:-mpos}"
export MPOS_DB_USER="${MPOS_DB_USER:-mpos}"
export MPOS_DB_PASS="${MPOS_DB_PASS:-$(random_hex 32)}"
export MPOS_DB_HOST="${MPOS_DB_HOST:-127.0.0.1}"
export MPOS_DB_PORT="${MPOS_DB_PORT:-3306}"
export MPOS_ADMIN_USER="${MPOS_ADMIN_USER:-admin}"
export MPOS_ADMIN_PASS="${MPOS_ADMIN_PASS:-$(random_hex 32)}"
export MPOS_ADMIN_EMAIL="${MPOS_ADMIN_EMAIL:-admin@blakestream.local}"
export MPOS_SALT="${MPOS_SALT:-$(random_hex 32)}"
export MPOS_SALTY="${MPOS_SALTY:-$(random_hex 32)}"
export MPOS_API_TOKEN="${MPOS_API_TOKEN:-$(random_hex 16)}"
export MPOS_NODE_RPC_USER="${MPOS_NODE_RPC_USER:-blakestream}"
export MPOS_NODE_RPC_PASS="${MPOS_NODE_RPC_PASS:-$(random_hex 24)}"
export MPOS_PULL_DAEMON_IMAGES="${MPOS_PULL_DAEMON_IMAGES:-1}"
if [ "$MPOS_PULL_DAEMON_IMAGES" = "0" ]; then
    export MPOS_DOCKER_HUB="${MPOS_DOCKER_HUB:-local}"
    export MPOS_IMAGE_TAG="${MPOS_IMAGE_TAG:-25.2-local}"
else
    export MPOS_DOCKER_HUB="${MPOS_DOCKER_HUB:-sidgrip}"
    export MPOS_IMAGE_TAG="${MPOS_IMAGE_TAG:-25.2}"
fi
# Pre-live: source-build daemons from the 0.25.2 wallet branches. Change to
# master after live cutover once master carries the 25.2 wallet updates.
export MPOS_DAEMON_SOURCE_REF="${MPOS_DAEMON_SOURCE_REF:-0.25.2}"
export MPOS_DAEMON_BUILD_ROOT="${MPOS_DAEMON_BUILD_ROOT:-/root/blakestream-daemon-builds}"
export MPOS_DAEMON_BUILD_JOBS="${MPOS_DAEMON_BUILD_JOBS:-}"
export MPOS_DAEMON_BUILD_DOCKER_MODE="${MPOS_DAEMON_BUILD_DOCKER_MODE:-pull}"
export SKIP_DAEMON_IMAGE_BUILD="${SKIP_DAEMON_IMAGE_BUILD:-0}"
export MPOS_EXPLORER_API_BASE="${MPOS_EXPLORER_API_BASE:-https://explorer.blakestream.io/api}"
export BOOTSTRAP_URL="${BOOTSTRAP_URL:-https://bootstrap.blakestream.io}"
export BOOTSTRAP_SERIES="${BOOTSTRAP_SERIES:-25.2}"
export BOOTSTRAP_CANONICAL_HOST="${BOOTSTRAP_CANONICAL_HOST:-bootstrap.blakestream.io}"
export BOOTSTRAP_MIRROR_DISCOVERY="${BOOTSTRAP_MIRROR_DISCOVERY:-1}"
export BOOTSTRAP_MIRROR_HOST="${BOOTSTRAP_MIRROR_HOST:-}"
export BOOTSTRAP_IMPORT_TIMEOUT_S="${BOOTSTRAP_IMPORT_TIMEOUT_S:-21600}"
export BOOTSTRAP_IMPORT_SLEEP_S="${BOOTSTRAP_IMPORT_SLEEP_S:-60}"
export BOOTSTRAP_DOWNLOAD_ATTEMPTS="${BOOTSTRAP_DOWNLOAD_ATTEMPTS:-12}"
export BOOTSTRAP_DOWNLOAD_RETRY_SLEEP_S="${BOOTSTRAP_DOWNLOAD_RETRY_SLEEP_S:-60}"
export BOOTSTRAP_DOWNLOAD_CONNECT_TIMEOUT_S="${BOOTSTRAP_DOWNLOAD_CONNECT_TIMEOUT_S:-30}"
export BOOTSTRAP_DOWNLOAD_READ_TIMEOUT_S="${BOOTSTRAP_DOWNLOAD_READ_TIMEOUT_S:-90}"
export TIP_CATCH_TIMEOUT_S="${TIP_CATCH_TIMEOUT_S:-7200}"
export TIP_CATCH_LAG="${TIP_CATCH_LAG:-5}"
export MPOS_DAEMON_STOP_TIMEOUT_S="${MPOS_DAEMON_STOP_TIMEOUT_S:-900}"
export SKIP_DAEMONS="${SKIP_DAEMONS:-0}"
export SKIP_BOOTSTRAP="${SKIP_BOOTSTRAP:-0}"

require_pattern() {
    local name="$1" value="$2" pattern="$3" msg="${4:-}"
    if [[ ! "$value" =~ ^${pattern}$ ]]; then
        die "${name} has unsafe value '${value}'${msg:+ (${msg})}"
    fi
}

require_pattern MPOS_INSTALL_ROOT "${MPOS_INSTALL_ROOT}" '/[A-Za-z0-9._/-]+'
require_pattern MPOS_WEB_ROOT     "${MPOS_WEB_ROOT}"     '/[A-Za-z0-9._/-]+'
require_pattern MPOS_LOG_ROOT     "${MPOS_LOG_ROOT}"     '/[A-Za-z0-9._/-]+'
require_pattern MPOS_DOMAIN       "${MPOS_DOMAIN}"       '([A-Za-z0-9._*_-]{1,253}|_)'
require_pattern MPOS_HTTP_PORT    "${MPOS_HTTP_PORT}"    '[1-9][0-9]{0,4}'
require_pattern MPOS_STRATUM_PORT "${MPOS_STRATUM_PORT}" '[1-9][0-9]{0,4}'
require_pattern MPOS_SSH_PORT     "${MPOS_SSH_PORT}"     '[1-9][0-9]{0,4}'
require_pattern MPOS_DB_NAME      "${MPOS_DB_NAME}"      '[A-Za-z_][A-Za-z0-9_]{0,63}'
require_pattern MPOS_DB_USER      "${MPOS_DB_USER}"      '[A-Za-z_][A-Za-z0-9_]{0,31}'
require_pattern MPOS_DB_PASS      "${MPOS_DB_PASS}"      '[A-Za-z0-9_+=:,.@%/-]{8,128}'
require_pattern MPOS_DB_HOST      "${MPOS_DB_HOST}"      '[A-Za-z0-9._-]{1,253}'
require_pattern MPOS_DB_PORT      "${MPOS_DB_PORT}"      '[1-9][0-9]{0,4}'
require_pattern MPOS_ADMIN_USER   "${MPOS_ADMIN_USER}"   '[A-Za-z0-9_]{1,32}'
require_pattern MPOS_ADMIN_PASS   "${MPOS_ADMIN_PASS}"   '[A-Za-z0-9_+=:,.@%/-]{8,128}'
require_pattern MPOS_ADMIN_EMAIL  "${MPOS_ADMIN_EMAIL}"  '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+'
require_pattern MPOS_SALT         "${MPOS_SALT}"         '[A-Fa-f0-9]{8,128}'
require_pattern MPOS_SALTY        "${MPOS_SALTY}"        '[A-Fa-f0-9]{8,128}'
require_pattern MPOS_API_TOKEN    "${MPOS_API_TOKEN}"    '[A-Fa-f0-9]{8,128}'
require_pattern MPOS_NODE_RPC_USER "${MPOS_NODE_RPC_USER}" '[A-Za-z0-9_@%+=:,./-]{1,64}'
require_pattern MPOS_NODE_RPC_PASS "${MPOS_NODE_RPC_PASS}" '[A-Za-z0-9_@%+=:,./-]{16,128}'
require_pattern MPOS_DOCKER_HUB   "${MPOS_DOCKER_HUB}"   '[A-Za-z0-9._:/-]{1,253}'
require_pattern MPOS_IMAGE_TAG    "${MPOS_IMAGE_TAG}"    '[A-Za-z0-9._-]{1,128}'
require_pattern MPOS_PULL_DAEMON_IMAGES "${MPOS_PULL_DAEMON_IMAGES}" '[01]'
require_pattern MPOS_DAEMON_SOURCE_REF "${MPOS_DAEMON_SOURCE_REF}" '[A-Za-z0-9._/-]{1,128}'
require_pattern MPOS_DAEMON_BUILD_ROOT "${MPOS_DAEMON_BUILD_ROOT}" '/[A-Za-z0-9._/-]+'
if [ -n "$MPOS_DAEMON_BUILD_JOBS" ]; then
    require_pattern MPOS_DAEMON_BUILD_JOBS "${MPOS_DAEMON_BUILD_JOBS}" '[1-9][0-9]{0,2}'
fi
require_pattern MPOS_DAEMON_BUILD_DOCKER_MODE "${MPOS_DAEMON_BUILD_DOCKER_MODE}" '(pull|build)'
require_pattern SKIP_DAEMON_IMAGE_BUILD "${SKIP_DAEMON_IMAGE_BUILD}" '[01]'
require_pattern MPOS_EXPLORER_API_BASE "${MPOS_EXPLORER_API_BASE}" 'https?://[A-Za-z0-9._:/%-]+'
require_pattern BOOTSTRAP_URL     "${BOOTSTRAP_URL}"     'https?://[A-Za-z0-9._:/%-]+'
require_pattern BOOTSTRAP_SERIES  "${BOOTSTRAP_SERIES}"  '[A-Za-z0-9._-]{1,32}'
require_pattern BOOTSTRAP_CANONICAL_HOST "${BOOTSTRAP_CANONICAL_HOST}" '[A-Za-z0-9.-]{1,253}'
require_pattern BOOTSTRAP_MIRROR_DISCOVERY "${BOOTSTRAP_MIRROR_DISCOVERY}" '[01]'
if [ -n "$BOOTSTRAP_MIRROR_HOST" ]; then
    require_pattern BOOTSTRAP_MIRROR_HOST "${BOOTSTRAP_MIRROR_HOST}" '[A-Za-z0-9.-]{1,253}'
fi
require_pattern BOOTSTRAP_IMPORT_TIMEOUT_S "${BOOTSTRAP_IMPORT_TIMEOUT_S}" '[1-9][0-9]{0,5}'
require_pattern BOOTSTRAP_IMPORT_SLEEP_S "${BOOTSTRAP_IMPORT_SLEEP_S}" '[1-9][0-9]{0,4}'
require_pattern BOOTSTRAP_DOWNLOAD_ATTEMPTS "${BOOTSTRAP_DOWNLOAD_ATTEMPTS}" '[1-9][0-9]{0,3}'
require_pattern BOOTSTRAP_DOWNLOAD_RETRY_SLEEP_S "${BOOTSTRAP_DOWNLOAD_RETRY_SLEEP_S}" '[1-9][0-9]{0,4}'
require_pattern BOOTSTRAP_DOWNLOAD_CONNECT_TIMEOUT_S "${BOOTSTRAP_DOWNLOAD_CONNECT_TIMEOUT_S}" '[1-9][0-9]{0,4}'
require_pattern BOOTSTRAP_DOWNLOAD_READ_TIMEOUT_S "${BOOTSTRAP_DOWNLOAD_READ_TIMEOUT_S}" '[1-9][0-9]{0,4}'
require_pattern TIP_CATCH_TIMEOUT_S "${TIP_CATCH_TIMEOUT_S}" '[1-9][0-9]{0,5}'
require_pattern TIP_CATCH_LAG "${TIP_CATCH_LAG}" '[0-9]{1,5}'
require_pattern SKIP_DAEMONS      "${SKIP_DAEMONS}"      '[01]'
require_pattern SKIP_BOOTSTRAP    "${SKIP_BOOTSTRAP}"    '[01]'

# Persist env to a file we can scp to the VPS so each remote step
# inherits the same values without re-deriving them.
ENVRC=$(mktemp)
{
    echo "# generated by deploy-mainnet.sh on $(date -Iseconds)"
    for var in MPOS_INSTALL_ROOT MPOS_WEB_ROOT MPOS_LOG_ROOT \
               MPOS_DOMAIN MPOS_HTTP_PORT MPOS_STRATUM_PORT MPOS_SSH_PORT \
               MPOS_DB_NAME MPOS_DB_USER MPOS_DB_PASS MPOS_DB_HOST MPOS_DB_PORT \
               MPOS_ADMIN_USER MPOS_ADMIN_PASS MPOS_ADMIN_EMAIL \
               MPOS_SALT MPOS_SALTY MPOS_API_TOKEN \
               MPOS_NODE_RPC_USER MPOS_NODE_RPC_PASS \
               MPOS_DOCKER_HUB MPOS_IMAGE_TAG MPOS_PULL_DAEMON_IMAGES \
               MPOS_DAEMON_SOURCE_REF \
               MPOS_DAEMON_BUILD_ROOT MPOS_DAEMON_BUILD_JOBS \
               MPOS_DAEMON_BUILD_DOCKER_MODE SKIP_DAEMON_IMAGE_BUILD \
               MPOS_EXPLORER_API_BASE \
               BOOTSTRAP_URL BOOTSTRAP_SERIES BOOTSTRAP_CANONICAL_HOST \
               BOOTSTRAP_MIRROR_DISCOVERY BOOTSTRAP_MIRROR_HOST \
               BOOTSTRAP_IMPORT_TIMEOUT_S BOOTSTRAP_IMPORT_SLEEP_S \
               BOOTSTRAP_DOWNLOAD_ATTEMPTS BOOTSTRAP_DOWNLOAD_RETRY_SLEEP_S \
               BOOTSTRAP_DOWNLOAD_CONNECT_TIMEOUT_S BOOTSTRAP_DOWNLOAD_READ_TIMEOUT_S \
               TIP_CATCH_TIMEOUT_S TIP_CATCH_LAG MPOS_DAEMON_STOP_TIMEOUT_S \
               SKIP_DAEMONS SKIP_BOOTSTRAP; do
        printf 'export %s=%s\n' "$var" "${!var}"
    done
} > "$ENVRC"

say "deploy.env: ${ENVRC}"
if [ "${LOCAL_DEPLOY}" = "1" ]; then
    say "running mainnet deploy locally"
else
    say "running mainnet deploy against ${HOST}"
fi

# Helper: stage a local tree for the installer scripts.
push_tree() {
    local src="$1" dst="$2"
    local excludes=(
        --exclude='.venv' --exclude='__pycache__' --exclude='*.egg-info'
        --exclude='.venv-test' --exclude='node_modules' --exclude='.git'
    )
    if [ "${LOCAL_DEPLOY}" = "1" ]; then
        say "rsync ${src} -> ${dst}"
        mkdir -p "$dst"
        if [ "$(realpath "$src")" = "$(realpath -m "$dst")" ]; then
            say "source and destination are the same; skipping ${dst}"
            return 0
        fi
        rsync -a --delete "${excludes[@]}" "${src}/" "${dst}/"
    else
        say "rsync ${src} -> ${HOST}:${dst}"
        rsync -a --delete "${excludes[@]}" "${src}/" "${HOST}:${dst}/"
    fi
}

# Per-section timing — every deploy_step + a few inline blocks log
# their start + end to SECTION_TIMING_LOG so we can render a summary
# table at the end of the deploy and see where wall time goes.
SECTION_TIMING_LOG="${SECTION_TIMING_LOG:-/tmp/mpos-section-timings.log}"
: > "$SECTION_TIMING_LOG"
DEPLOY_OVERALL_START=$(date +%s)

section_run() {
    # section_run "<label>" <command...>
    local label="$1"; shift
    local start end elapsed
    start=$(date +%s)
    say "[timing] starting ${label} at $(date -u +%H:%M:%S)"
    "$@"
    end=$(date +%s)
    elapsed=$((end - start))
    say "[timing] finished ${label} in $((elapsed/60))m $((elapsed%60))s"
    printf '%s\t%d\n' "$label" "$elapsed" >> "$SECTION_TIMING_LOG"
}

# Helper: run a deploy step with the generated env. Any args after the
# script path are forwarded to the step script verbatim (e.g. --prefetch).
deploy_step() {
    local script="$1"
    shift
    local name; name=$(basename "$script")
    local args="$*"
    local args_display="${args:+ ${args}}"
    if [ "${LOCAL_DEPLOY}" = "1" ]; then
        say "local: ${name}${args_display}"
        install -o root -g root -m 0600 "$ENVRC" /root/.mpos-deploy.env
        ( set -e; source /root/.mpos-deploy.env; bash "$script" $args )
    else
        say "remote: ${name}${args_display}"
        scp -q "$ENVRC" "${HOST}:/root/.mpos-deploy.env"
        scp -q "$script" "${HOST}:/tmp/${name}"
        # shellcheck disable=SC2029
        ssh "${HOST}" "set -e; source /root/.mpos-deploy.env; bash /tmp/${name} ${args}"
    fi
}

# Wrap deploy_step so each step lands in the timing log.
deploy_step_timed() {
    local script="$1"
    shift
    local name; name=$(basename "$script" .sh)
    section_run "${name}" deploy_step "$script" "$@"
}

# ---------------------------------------------------------------
# Step 1: VPS system deps — Docker + LAMP + memcached
# ---------------------------------------------------------------
deploy_step_timed "${SCRIPT_DIR}/scripts/mainnet/10-vps-system-deps.sh"

# ---------------------------------------------------------------
# Step 2: Pull or build daemon images, then start containers
#
# When source-building daemons (MPOS_PULL_DAEMON_IMAGES=0), the
# bootstrap downloads run in the background concurrently with the
# 30-60 min compile phase, saving wall time. The prefetch is
# idempotent — Phase A in the regular step 21 invocation re-verifies
# size and re-fetches anything missing.
# ---------------------------------------------------------------
PREFETCH_PID=""
PREFETCH_LOG=""
if [ "${SKIP_DAEMONS}" != "1" ]; then
    if [ "${MPOS_PULL_DAEMON_IMAGES}" = "0" ] && [ "${SKIP_DAEMON_IMAGE_BUILD}" != "1" ]; then
        if [ "${SKIP_BOOTSTRAP}" != "1" ]; then
            PREFETCH_LOG="/tmp/bootstrap-prefetch.log"
            say "starting bootstrap prefetch in background (parallel with image build); log: ${PREFETCH_LOG}"
            (
                # Reset the parent's EXIT trap — otherwise the subshell's
                # exit fires cleanup() and removes $ENVRC mid-deploy when
                # prefetch finishes fast (e.g. bootstraps already cached).
                trap - EXIT
                deploy_step "${SCRIPT_DIR}/scripts/mainnet/21-bootstrap-coins.sh" --prefetch
            ) >"$PREFETCH_LOG" 2>&1 &
            PREFETCH_PID=$!
        fi
        deploy_step_timed "${SCRIPT_DIR}/scripts/mainnet/19-build-daemon-images.sh"
        if [ -n "$PREFETCH_PID" ]; then
            say "image build done; bootstrap prefetch still running (pid ${PREFETCH_PID})"
            # Mirror prefetch headline lines and a 30s per-coin size
            # heartbeat into the main log so the user sees progress
            # instead of a silent wait while the 13G+ of bootstraps
            # download.
            prev_lines=0
            prev_announce=$(date +%s)
            while kill -0 "$PREFETCH_PID" 2>/dev/null; do
                if [ -f "$PREFETCH_LOG" ]; then
                    cur_lines=$(wc -l < "$PREFETCH_LOG" 2>/dev/null || echo 0)
                    if [ "$cur_lines" -gt "$prev_lines" ]; then
                        # `|| true` — grep returns 1 when no matches in the
                        # range (wget chatter only); combined with the
                        # script's `set -e` + `pipefail`, that would abort
                        # the whole deploy.
                        sed -n "$((prev_lines+1)),${cur_lines}p" "$PREFETCH_LOG" 2>/dev/null \
                            | sed 's/\x1b\[[0-9;]*m//g' \
                            | grep -E '^(==>|✓|!!)' \
                            | sed 's/^/   [prefetch] /' \
                            || true
                        prev_lines=$cur_lines
                    fi
                fi
                now=$(date +%s)
                if [ "$((now - prev_announce))" -ge 30 ]; then
                    for d in /root/.blakecoin /root/.photon /root/.blakebitcoin \
                             /root/.electron /root/.lithium /root/.universalmolecule; do
                        if [ -f "$d/bootstrap.dat.tmp" ]; then
                            size=$(du -h "$d/bootstrap.dat.tmp" 2>/dev/null | cut -f1)
                            coin=${d#/root/.}
                            printf '   [prefetch] downloading %-20s %s\n' "${coin}" "${size}"
                        fi
                    done
                    prev_announce=$now
                fi
                sleep 5
            done
            if wait "$PREFETCH_PID"; then
                say "bootstrap prefetch finished cleanly"
            else
                say "bootstrap prefetch failed; step 21 Phase A will retry sequentially"
            fi
            PREFETCH_PID=""
        fi
    elif [ "${MPOS_PULL_DAEMON_IMAGES}" = "0" ]; then
        say "SKIP_DAEMON_IMAGE_BUILD=1 - using already-loaded daemon images"
    fi
    deploy_step_timed "${SCRIPT_DIR}/scripts/mainnet/20-deploy-daemons.sh"
    if [ "${SKIP_BOOTSTRAP}" != "1" ]; then
        deploy_step_timed "${SCRIPT_DIR}/scripts/mainnet/21-bootstrap-coins.sh"
    else
        say "SKIP_BOOTSTRAP=1 - skipping sequential daemon bootstrap"
    fi
else
    say "SKIP_DAEMONS=1 - skipping daemon stack (assuming containers already up)"
fi

# ---------------------------------------------------------------
# Step 3: Wait for every daemon's mainnet RPC to respond
# ---------------------------------------------------------------
deploy_step_timed "${SCRIPT_DIR}/scripts/mainnet/30-wait-rpc.sh"

# ---------------------------------------------------------------
# Step 4: Push both MPOS and Eliopool trees BEFORE the pool install
# step (40-install-pool.sh references the mainnet eloipool config
# template that lives in MPOS's deploy-bundle/templates/).
# ---------------------------------------------------------------
# Build Vue v2 frontend on the dev box so public/v2/dist/ ships with
# the rsync below. Without this, the MPOS dashboard renders the
# "v2 build not deployed" message.
if [ -f "${REPO_ROOT}/frontend/package.json" ]; then
    if ! command -v bun >/dev/null 2>&1; then
        if [ "${LOCAL_DEPLOY}" = "1" ]; then
            die "bun missing on this server — step 10 should have installed it; check /tmp/bun-install.log"
        else
            die "bun not found on dev box — install bun (https://bun.sh) before running deploy"
        fi
    fi
    say "building Vue v2 frontend"
    # build:fast skips the vue-tsc type check (a Node binary). We run
    # the deploy with bun only; the typecheck is available to developers
    # locally via `bun run typecheck`.
    ( cd "${REPO_ROOT}/frontend" && bun install --silent && bun run build:fast )
fi

push_tree "${REPO_ROOT}" "/root/Blakestream-MPOS"
push_tree "${ELIOPOOL_TREE}" "/root/Blakestream-Eliopool"
deploy_step_timed "${SCRIPT_DIR}/scripts/mainnet/40-install-pool.sh"

# ---------------------------------------------------------------
# Step 5: Install MPOS web stack (tree already pushed above).
# ---------------------------------------------------------------
deploy_step_timed "${SCRIPT_DIR}/scripts/mainnet/50-install-mpos.sh"

# ---------------------------------------------------------------
# Step 6: Stage PHP cron tree for ad-hoc diagnostics only
# ---------------------------------------------------------------
deploy_step_timed "${SCRIPT_DIR}/scripts/mainnet/60-install-php-cron.sh"

# ---------------------------------------------------------------
# Step 7: Install cronjobs-py as authoritative scheduler
# ---------------------------------------------------------------
deploy_step_timed "${SCRIPT_DIR}/scripts/mainnet/70-install-cronjobs-py.sh"

# ---------------------------------------------------------------
# Step 7.5: Install the SSE dashboard side-car
# ---------------------------------------------------------------
deploy_step_timed "${SCRIPT_DIR}/scripts/mainnet/75-install-sse.sh"

# ---------------------------------------------------------------
# Step 7.6: Import Go Eloipool accepted shares into MPOS MariaDB
# ---------------------------------------------------------------
deploy_step_timed "${SCRIPT_DIR}/scripts/mainnet/76-install-sharelog-importer.sh"

# ---------------------------------------------------------------
# Step 8: Open firewall, install logrotate, install daily backup,
#          run final verify pass.
# ---------------------------------------------------------------
deploy_step_timed "${SCRIPT_DIR}/scripts/mainnet/80-firewall.sh"
deploy_step_timed "${SCRIPT_DIR}/scripts/mainnet/85-install-logrotate.sh"
deploy_step_timed "${SCRIPT_DIR}/scripts/mainnet/90-install-backup.sh"
deploy_step_timed "${SCRIPT_DIR}/scripts/mainnet/99-verify.sh"

VPS_IP=$(host_run 'hostname -I | awk "{print \$1}"')

# Section timing summary table (printed before the deploy-complete banner).
DEPLOY_OVERALL_END=$(date +%s)
DEPLOY_OVERALL_ELAPSED=$((DEPLOY_OVERALL_END - DEPLOY_OVERALL_START))
say "=== section timing summary ==="
printf '   %-32s %s\n' "section" "elapsed"
printf '   %-32s %s\n' "--------------------------------" "----------"
while IFS=$'\t' read -r section_name section_elapsed; do
    [ -z "${section_name}" ] && continue
    printf '   %-32s %3dm %02ds\n' \
        "${section_name}" \
        $((section_elapsed/60)) $((section_elapsed%60))
done < "${SECTION_TIMING_LOG}"
printf '   %-32s %s\n' "--------------------------------" "----------"
printf '   %-32s %dh %02dm %02ds\n' "TOTAL" \
    $((DEPLOY_OVERALL_ELAPSED/3600)) \
    $(((DEPLOY_OVERALL_ELAPSED%3600)/60)) \
    $((DEPLOY_OVERALL_ELAPSED%60))

say "deploy complete"
echo
echo "  Web UI:        http://${VPS_IP}:${MPOS_HTTP_PORT}/"
echo "  Stratum:       stratum+tcp://${VPS_IP}:${MPOS_STRATUM_PORT}"
echo "  Admin user:    ${MPOS_ADMIN_USER}"
echo "  Admin email:   ${MPOS_ADMIN_EMAIL}"
echo "  Saved env:     /root/.mpos-deploy.env"
if [ "${LOCAL_DEPLOY}" = "1" ]; then
    echo "  Secrets:       sudo sed -n \"1,80p\" /root/.mpos-deploy.env"
else
    echo "  Secrets:       ssh ${HOST} 'sed -n \"1,80p\" /root/.mpos-deploy.env'"
fi
echo
echo "  Logs:"
if [ "${LOCAL_DEPLOY}" = "1" ]; then
    echo "    daemons:     docker ps; docker logs blc --tail 30"
    echo "    eloipool:    journalctl -u blakestream-mpos-eloipool -fn 50"
    echo "    cronjobs-py: tail -f /var/log/blakestream-mpos/cronjobs.stdout"
    echo "    shares:      tail -f /var/log/blakestream-mpos/sharelog-importer.stdout"
    echo "    PHP ad-hoc:  ls /opt/blakestream-mpos/cronjobs/logs 2>/dev/null || true"
else
    echo "    daemons:     ssh ${HOST} 'docker ps; docker logs blc --tail 30'"
    echo "    eloipool:    ssh ${HOST} 'journalctl -u blakestream-mpos-eloipool -fn 50'"
    echo "    cronjobs-py: ssh ${HOST} 'tail -f /var/log/blakestream-mpos/cronjobs.stdout'"
    echo "    shares:      ssh ${HOST} 'tail -f /var/log/blakestream-mpos/sharelog-importer.stdout'"
    echo "    PHP ad-hoc:  ssh ${HOST} 'ls /opt/blakestream-mpos/cronjobs/logs 2>/dev/null || true'"
fi
