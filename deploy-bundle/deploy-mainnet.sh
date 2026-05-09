#!/usr/bin/env bash
# Blakestream-MPOS mainnet deploy entry point.
#
# Pipeline (per the operator's spec, top-down):
#
#   1. Pull the six mainnet daemon images from Docker Hub.
#   2. Create data folders, render configs with active mainnet peer
#      addnodes (from explorer.blakestream.io), and start the 6 daemons.
#   3. If bootstrap is enabled, replay each coin's bootstrap.dat
#      sequentially so ELT/UMO do not OOM the host.
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
#
# Usage:
#   bash deploy-bundle/deploy-mainnet.sh <ssh-host>
#   bash deploy-bundle/deploy-mainnet.sh <your-host-alias>
#
# Pre-reqs (on this dev box, NOT the VPS):
#   - SSH key auth to <ssh-host> as root (use ssh-copy-id first)
#   - rsync, ssh, curl, git
#
# Pre-reqs (on the VPS): nothing — this script installs everything.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

MPOS_REPO_URL="${MPOS_REPO_URL:-https://github.com/SidGrip/php-mpos.git}"
ELIOPOOL_REPO_URL="${ELIOPOOL_REPO_URL:-https://github.com/SidGrip/eloipool_Blakecoin.git}"
ELIOPOOL_BRANCH="${ELIOPOOL_BRANCH:-master}"
ELIOPOOL_TMPROOT=""
ENVRC=""

cleanup() {
    [ -n "${ELIOPOOL_TMPROOT}" ] && rm -rf "${ELIOPOOL_TMPROOT}"
    [ -n "${ENVRC}" ] && rm -f "${ENVRC}"
}
trap cleanup EXIT

if [ "${1:-}" = "" ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    cat <<EOF
Usage: $0 <ssh-host>

Deploy a mainnet Blakestream-MPOS pool to <ssh-host> via SSH.

  $0 <your-host-alias> # SSH alias from ~/.ssh/config
  $0 root@1.2.3.4      # raw user@host

Source repos:
  Run this script from a clone of:
    ${MPOS_REPO_URL}

  Eliopool is optional locally. If ELIOPOOL_TREE is unset, this script
  clones:

    ${ELIOPOOL_REPO_URL} branch ${ELIOPOOL_BRANCH}

Daemon images:
  The six coin daemons are pulled directly from Docker Hub:

    \${MPOS_DOCKER_HUB:-sidgrip}/<coin>:\${MPOS_IMAGE_TAG:-latest}

Tunables (env):
  MPOS_DOCKER_HUB     Docker Hub org/user for coin daemon images
                       (default: sidgrip).
  MPOS_IMAGE_TAG      Docker image tag for all daemon images
                       (default: latest).
  MPOS_EXPLORER_API_BASE
                       Explorer API used to fetch addnode peers
                       (default: https://explorer.blakestream.io/api).
  BOOTSTRAP_URL       Base URL for bootstrap.dat files
                       (default: https://bootstrap.blakestream.io).
  ELIOPOOL_TREE        Local checkout of eloipool_Blakecoin
                       (optional; auto-cloned from \${ELIOPOOL_REPO_URL}
                       on branch \${ELIOPOOL_BRANCH} if unset).
  ELIOPOOL_REPO_URL    git URL to clone Eliopool from when ELIOPOOL_TREE
                       is unset (default: ${ELIOPOOL_REPO_URL}).
  ELIOPOOL_BRANCH      branch to clone (default: ${ELIOPOOL_BRANCH}).
  MPOS_DOMAIN          Public domain (default: _, catch-all)
  MPOS_HTTP_PORT       Web UI port (default: 80)
  MPOS_STRATUM_PORT    Stratum bind port (default: 3334)
  MPOS_SSH_PORT        SSH port to keep open in UFW (default: ssh -G)
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
EOF
    exit 0
fi

say() { printf '\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# Eliopool: prefer a local checkout if ELIOPOOL_TREE is set; otherwise
# auto-clone the published repo into a temp dir so the deploy is
# self-contained for users who only have the MPOS repo.
if [ -z "${ELIOPOOL_TREE:-}" ]; then
    ELIOPOOL_TMPROOT="$(mktemp -d)"
    ELIOPOOL_TREE="${ELIOPOOL_TMPROOT}/eloipool"
    git clone --depth 1 -b "${ELIOPOOL_BRANCH}" "${ELIOPOOL_REPO_URL}" "${ELIOPOOL_TREE}"
fi

HOST="$1"

# Pre-flight: paths exist locally, ssh works, sudo works on remote.
[ -d "${ELIOPOOL_TREE}" ] || die "eloipool_Blakecoin checkout not found at ${ELIOPOOL_TREE}"

say "checking SSH auth to ${HOST}"
ssh -o BatchMode=yes -o ConnectTimeout=10 "${HOST}" 'echo ok' >/dev/null \
    || die "ssh to ${HOST} failed (need passwordless key auth - run ssh-copy-id first)"

SSH_PORT_DETECTED="$(ssh -G "${HOST}" 2>/dev/null | awk '/^port / {print $2; exit}')"
export MPOS_SSH_PORT="${MPOS_SSH_PORT:-${SSH_PORT_DETECTED:-22}}"

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
DAEMON_RPC_USER="$(ssh "${HOST}" 'grep -m1 ^rpcuser= /root/.blakecoin/blakecoin.conf 2>/dev/null | cut -d= -f2' || true)"
DAEMON_RPC_PASS="$(ssh "${HOST}" 'grep -m1 ^rpcpassword= /root/.blakecoin/blakecoin.conf 2>/dev/null | cut -d= -f2' || true)"
if [ -n "${DAEMON_RPC_USER}" ] && [ -n "${DAEMON_RPC_PASS}" ]; then
    say "adopting RPC creds from /root/.blakecoin/blakecoin.conf"
    : "${MPOS_NODE_RPC_USER:=${DAEMON_RPC_USER}}"
    : "${MPOS_NODE_RPC_PASS:=${DAEMON_RPC_PASS}}"
    export MPOS_NODE_RPC_USER MPOS_NODE_RPC_PASS
fi

PRIOR_ENV="$(ssh "${HOST}" 'cat /root/.mpos-deploy.env 2>/dev/null' || true)"
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
        # Bootstrap timing values are operational tunables, not persistent
        # secrets. Let the current script defaults or the operator's current
        # environment win so an old /root/.mpos-deploy.env cannot pin unsafe
        # timing from a previous release.
        case "$key" in
            BOOTSTRAP_IMPORT_TIMEOUT_S|BOOTSTRAP_IMPORT_SLEEP_S|BOOTSTRAP_DOWNLOAD_ATTEMPTS|BOOTSTRAP_DOWNLOAD_RETRY_SLEEP_S|BOOTSTRAP_DOWNLOAD_CONNECT_TIMEOUT_S|BOOTSTRAP_DOWNLOAD_READ_TIMEOUT_S|TIP_CATCH_TIMEOUT_S|TIP_CATCH_LAG)
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
export MPOS_DOCKER_HUB="${MPOS_DOCKER_HUB:-sidgrip}"
export MPOS_IMAGE_TAG="${MPOS_IMAGE_TAG:-latest}"
export MPOS_EXPLORER_API_BASE="${MPOS_EXPLORER_API_BASE:-https://explorer.blakestream.io/api}"
export BOOTSTRAP_URL="${BOOTSTRAP_URL:-https://bootstrap.blakestream.io}"
export BOOTSTRAP_IMPORT_TIMEOUT_S="${BOOTSTRAP_IMPORT_TIMEOUT_S:-21600}"
export BOOTSTRAP_IMPORT_SLEEP_S="${BOOTSTRAP_IMPORT_SLEEP_S:-60}"
export BOOTSTRAP_DOWNLOAD_ATTEMPTS="${BOOTSTRAP_DOWNLOAD_ATTEMPTS:-12}"
export BOOTSTRAP_DOWNLOAD_RETRY_SLEEP_S="${BOOTSTRAP_DOWNLOAD_RETRY_SLEEP_S:-60}"
export BOOTSTRAP_DOWNLOAD_CONNECT_TIMEOUT_S="${BOOTSTRAP_DOWNLOAD_CONNECT_TIMEOUT_S:-30}"
export BOOTSTRAP_DOWNLOAD_READ_TIMEOUT_S="${BOOTSTRAP_DOWNLOAD_READ_TIMEOUT_S:-90}"
export TIP_CATCH_TIMEOUT_S="${TIP_CATCH_TIMEOUT_S:-7200}"
export TIP_CATCH_LAG="${TIP_CATCH_LAG:-5}"
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
require_pattern MPOS_SALT         "${MPOS_SALT}"         '[A-Fa-f0-9]{32,128}'
require_pattern MPOS_SALTY        "${MPOS_SALTY}"        '[A-Fa-f0-9]{32,128}'
require_pattern MPOS_API_TOKEN    "${MPOS_API_TOKEN}"    '[A-Fa-f0-9]{8,128}'
require_pattern MPOS_NODE_RPC_USER "${MPOS_NODE_RPC_USER}" '[A-Za-z0-9_@%+=:,./-]{1,64}'
require_pattern MPOS_NODE_RPC_PASS "${MPOS_NODE_RPC_PASS}" '[A-Za-z0-9_@%+=:,./-]{16,128}'
require_pattern MPOS_DOCKER_HUB   "${MPOS_DOCKER_HUB}"   '[A-Za-z0-9._:/-]{1,253}'
require_pattern MPOS_IMAGE_TAG    "${MPOS_IMAGE_TAG}"    '[A-Za-z0-9._-]{1,128}'
require_pattern MPOS_EXPLORER_API_BASE "${MPOS_EXPLORER_API_BASE}" 'https?://[A-Za-z0-9._:/%-]+'
require_pattern BOOTSTRAP_URL     "${BOOTSTRAP_URL}"     'https?://[A-Za-z0-9._:/%-]+'
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
               MPOS_DOCKER_HUB MPOS_IMAGE_TAG MPOS_EXPLORER_API_BASE \
               BOOTSTRAP_URL \
               BOOTSTRAP_IMPORT_TIMEOUT_S BOOTSTRAP_IMPORT_SLEEP_S \
               BOOTSTRAP_DOWNLOAD_ATTEMPTS BOOTSTRAP_DOWNLOAD_RETRY_SLEEP_S \
               BOOTSTRAP_DOWNLOAD_CONNECT_TIMEOUT_S BOOTSTRAP_DOWNLOAD_READ_TIMEOUT_S \
               TIP_CATCH_TIMEOUT_S TIP_CATCH_LAG \
               SKIP_DAEMONS SKIP_BOOTSTRAP; do
        printf 'export %s=%s\n' "$var" "${!var}"
    done
} > "$ENVRC"

say "deploy.env: ${ENVRC}"
say "running mainnet deploy against ${HOST}"

# Helper: rsync a local tree to the VPS.
push_tree() {
    local src="$1" dst="$2"
    say "rsync ${src} -> ${HOST}:${dst}"
    rsync -a --delete \
        --exclude='.venv' --exclude='__pycache__' --exclude='*.egg-info' \
        --exclude='.venv-test' --exclude='node_modules' --exclude='.git' \
        "${src}/" "${HOST}:${dst}/"
}

# Helper: run a remote step with the env.
remote_step() {
    local script="$1"
    local name; name=$(basename "$script")
    say "remote: ${name}"
    scp -q "$ENVRC" "${HOST}:/root/.mpos-deploy.env"
    scp -q "$script" "${HOST}:/tmp/${name}"
    # shellcheck disable=SC2029
    ssh "${HOST}" "set -e; source /root/.mpos-deploy.env; bash /tmp/${name}"
}

# ---------------------------------------------------------------
# Step 1: VPS system deps — Docker + LAMP + memcached
# ---------------------------------------------------------------
remote_step "${SCRIPT_DIR}/scripts/mainnet/10-vps-system-deps.sh"

# ---------------------------------------------------------------
# Step 2: Pull Docker Hub daemon images and start containers
# ---------------------------------------------------------------
if [ "${SKIP_DAEMONS}" != "1" ]; then
    remote_step "${SCRIPT_DIR}/scripts/mainnet/20-deploy-daemons.sh"
    if [ "${SKIP_BOOTSTRAP}" != "1" ]; then
        remote_step "${SCRIPT_DIR}/scripts/mainnet/21-bootstrap-coins.sh"
    else
        say "SKIP_BOOTSTRAP=1 - skipping sequential daemon bootstrap"
    fi
else
    say "SKIP_DAEMONS=1 - skipping daemon stack (assuming containers already up)"
fi

# ---------------------------------------------------------------
# Step 3: Wait for every daemon's mainnet RPC to respond
# ---------------------------------------------------------------
remote_step "${SCRIPT_DIR}/scripts/mainnet/30-wait-rpc.sh"

# ---------------------------------------------------------------
# Step 4: Push both MPOS and Eliopool trees BEFORE the pool install
# step (40-install-pool.sh references the mainnet eloipool config
# template that lives in MPOS's deploy-bundle/templates/).
# ---------------------------------------------------------------
push_tree "${REPO_ROOT}" "/root/Blakestream-MPOS"
push_tree "${ELIOPOOL_TREE}" "/root/Blakestream-Eliopool"
remote_step "${SCRIPT_DIR}/scripts/mainnet/40-install-pool.sh"

# ---------------------------------------------------------------
# Step 5: Install MPOS web stack (tree already pushed above).
# ---------------------------------------------------------------
remote_step "${SCRIPT_DIR}/scripts/mainnet/50-install-mpos.sh"

# ---------------------------------------------------------------
# Step 6: Stage PHP cron tree for ad-hoc diagnostics only
# ---------------------------------------------------------------
remote_step "${SCRIPT_DIR}/scripts/mainnet/60-install-php-cron.sh"

# ---------------------------------------------------------------
# Step 7: Install cronjobs-py as authoritative scheduler
# ---------------------------------------------------------------
remote_step "${SCRIPT_DIR}/scripts/mainnet/70-install-cronjobs-py.sh"

# ---------------------------------------------------------------
# Step 7.5: Install the SSE dashboard side-car
# ---------------------------------------------------------------
remote_step "${SCRIPT_DIR}/scripts/mainnet/75-install-sse.sh"

# ---------------------------------------------------------------
# Step 8: Open firewall, install logrotate, install daily backup,
#          run final verify pass.
# ---------------------------------------------------------------
remote_step "${SCRIPT_DIR}/scripts/mainnet/80-firewall.sh"
remote_step "${SCRIPT_DIR}/scripts/mainnet/85-install-logrotate.sh"
remote_step "${SCRIPT_DIR}/scripts/mainnet/90-install-backup.sh"
remote_step "${SCRIPT_DIR}/scripts/mainnet/99-verify.sh"

VPS_IP=$(ssh "${HOST}" 'hostname -I | awk "{print \$1}"')
say "deploy complete"
echo
echo "  Web UI:        http://${VPS_IP}:${MPOS_HTTP_PORT}/"
echo "  Stratum:       stratum+tcp://${VPS_IP}:${MPOS_STRATUM_PORT}"
echo "  Admin user:    ${MPOS_ADMIN_USER}"
echo "  Admin email:   ${MPOS_ADMIN_EMAIL}"
echo "  Saved on VPS:  /root/.mpos-deploy.env"
echo "  Secrets:       ssh ${HOST} 'sed -n \"1,80p\" /root/.mpos-deploy.env'"
echo
echo "  Logs:"
echo "    daemons:     ssh ${HOST} 'docker ps; docker logs blc --tail 30'"
echo "    eloipool:    ssh ${HOST} 'journalctl -u blakestream-mpos-eloipool -fn 50'"
echo "    cronjobs-py: ssh ${HOST} 'tail -f /var/log/blakestream-mpos/cronjobs.stdout'"
echo "    PHP ad-hoc:  ssh ${HOST} 'ls /opt/blakestream-mpos/cronjobs/logs 2>/dev/null || true'"
