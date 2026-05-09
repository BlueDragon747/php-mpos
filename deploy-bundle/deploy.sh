#!/usr/bin/env bash
# Blakestream-MPOS deploy entry point.
#
# Layered on top of the canonical eloipool_Blakecoin testnet
# stack: this script brings up the same six daemons + eloipool + MMP +
# dashboard + miner, then adds the LAMP + MPOS web UI + cronjobs-py
# scheduler on top.
#
# Default mode is `testnet -local` against the operator's own host.
# Mainnet support TBD — testnet is the only target proven end-to-end.
#
# Usage:
#   sudo bash deploy-bundle/deploy.sh -local                  # all-in-one
#   sudo bash deploy-bundle/deploy.sh <host> [user] [pass]    # SSH-driven
#   sudo bash deploy-bundle/deploy.sh -local --skip-pool      # skip Eliopool layer (already deployed)
#   sudo bash deploy-bundle/deploy.sh -local --wipe           # purge prior install before deploy

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Flags
RUN_LOCAL=0
SKIP_POOL=0
WIPE=0
HOST=""
USER_ARG="root"
PASS=""

usage() {
    cat <<'EOF'
Blakestream-MPOS deploy

Modes:
  -local              run against this machine
  <host> [user] [pw]  run against a remote host via SSH

Flags:
  --skip-pool   reuse an existing Eliopool testnet stack (e.g. left from
                a prior `deploy-full-testnet-stack.sh -local` run)
  --wipe        remove prior MPOS install/data before deploying

Required tooling on the target host: bash, sudo, apt, systemd, docker,
git. Everything else is installed by the deploy.

Tunable via env vars:
  ELIOPOOL_TREE        path to a local checkout of eloipool_Blakecoin
                       (optional; auto-cloned from \$ELIOPOOL_REPO_URL on
                       branch \$ELIOPOOL_BRANCH if unset)
  ELIOPOOL_REPO_URL    git URL to clone Eliopool from when ELIOPOOL_TREE is unset
                       (default: https://github.com/SidGrip/eloipool_Blakecoin.git)
  ELIOPOOL_BRANCH      branch to clone (default: master)
  MPOS_DB_NAME         default: mpos
  MPOS_DB_USER         default: mpos
  MPOS_DB_PASS         default: random 32 hex
  MPOS_WEB_ROOT        default: /var/www/blakestream-mpos
  MPOS_DOMAIN          server_name in the nginx vhost (default: _ , i.e. catch-all)
  MPOS_HTTP_PORT       default: 80
  MPOS_ADMIN_USER      seeded admin account (default: admin)
  MPOS_ADMIN_PASS      seeded admin password (default: random 32 hex)
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -local|--local)  RUN_LOCAL=1; shift ;;
        --skip-pool)     SKIP_POOL=1; shift ;;
        --wipe)          WIPE=1; shift ;;
        -h|--help)       usage; exit 0 ;;
        -*)              echo "unknown flag: $1" >&2; usage >&2; exit 2 ;;
        *)
            if [ -z "$HOST" ]; then HOST="$1"
            elif [ "$USER_ARG" = "root" ]; then USER_ARG="$1"
            elif [ -z "$PASS" ]; then PASS="$1"
            else echo "unexpected arg: $1" >&2; exit 2; fi
            shift ;;
    esac
done

if [ "$RUN_LOCAL" = "0" ] && [ -z "$HOST" ]; then
    usage >&2
    exit 2
fi

# Defaults exported to sub-scripts
# Eliopool: prefer a caller-supplied local checkout; otherwise auto-clone
# the published repo into a temp dir and clean it up on exit.
ELIOPOOL_REPO_URL="${ELIOPOOL_REPO_URL:-https://github.com/SidGrip/eloipool_Blakecoin.git}"
ELIOPOOL_BRANCH="${ELIOPOOL_BRANCH:-master}"
ELIOPOOL_TMPROOT=""
if [ -z "${ELIOPOOL_TREE:-}" ]; then
    ELIOPOOL_TMPROOT="$(mktemp -d)"
    ELIOPOOL_TREE="${ELIOPOOL_TMPROOT}/eloipool"
    git clone --depth 1 -b "${ELIOPOOL_BRANCH}" "${ELIOPOOL_REPO_URL}" "${ELIOPOOL_TREE}"
    trap '[ -n "${ELIOPOOL_TMPROOT}" ] && rm -rf "${ELIOPOOL_TMPROOT}"' EXIT
fi
export ELIOPOOL_TREE
export MPOS_REPO_ROOT="${MPOS_REPO_ROOT:-${REPO_ROOT}}"
export MPOS_DEPLOY_BUNDLE="${SCRIPT_DIR}"

export MPOS_INSTALL_ROOT="${MPOS_INSTALL_ROOT:-/opt/blakestream-mpos}"
export MPOS_WEB_ROOT="${MPOS_WEB_ROOT:-/var/www/blakestream-mpos}"
export MPOS_LOG_ROOT="${MPOS_LOG_ROOT:-/var/log/blakestream-mpos}"
export MPOS_DOMAIN="${MPOS_DOMAIN:-_}"
export MPOS_HTTP_PORT="${MPOS_HTTP_PORT:-80}"

export MPOS_DB_NAME="${MPOS_DB_NAME:-mpos}"
export MPOS_DB_USER="${MPOS_DB_USER:-mpos}"
export MPOS_DB_HOST="${MPOS_DB_HOST:-127.0.0.1}"
export MPOS_DB_PORT="${MPOS_DB_PORT:-3306}"

export MPOS_ADMIN_USER="${MPOS_ADMIN_USER:-admin}"
export MPOS_RUN_USER="${MPOS_RUN_USER:-www-data}"
export MPOS_RUN_GROUP="${MPOS_RUN_GROUP:-www-data}"

# Generate stable secrets if the operator didn't pin them. We avoid
# `tr` over /dev/urandom because some sandbox layers swap charsets.
random_hex() { head -c "$1" /dev/urandom | xxd -p -c 256 | head -c "$1"; }
export MPOS_DB_PASS="${MPOS_DB_PASS:-$(random_hex 32)}"
export MPOS_ADMIN_PASS="${MPOS_ADMIN_PASS:-$(random_hex 32)}"
export MPOS_SALT="${MPOS_SALT:-$(random_hex 8)}"
export MPOS_SALTY="${MPOS_SALTY:-$(random_hex 8)}"
export MPOS_API_TOKEN="${MPOS_API_TOKEN:-$(random_hex 16)}"

export MPOS_SKIP_POOL="$SKIP_POOL"
export MPOS_WIPE="$WIPE"

say() { printf '\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# Wave 3: input validation. Any value that ends up in a sed replacement,
# nginx config, or a SQL identifier MUST pass an allow-list. The
# defaults are random hex / safe identifiers, but operator overrides
# could include `'`, `&`, `/`, etc. — which would either silently
# corrupt the rendered configs or open SQL injection on
# `CREATE USER ... IDENTIFIED BY '...'` (the heredoc in
# 50-install-mpos.sh isn't using bound parameters; can't, with the
# mariadb CLI). Better to reject early.
require_pattern() {
    local name="$1" value="$2" pattern="$3" hint="${4:-}"
    if ! [[ "$value" =~ ^${pattern}$ ]]; then
        die "${name}=${value:-(unset)} fails allow-list /^${pattern}\$/${hint:+ — ${hint}}"
    fi
}

# DB identifiers — MariaDB's quoted-identifier rules accept more, but
# we constrain to the safe subset that doesn't need backtick escaping
# in the shared SQL paths.
require_pattern MPOS_DB_NAME "${MPOS_DB_NAME}" '[A-Za-z_][A-Za-z0-9_]{0,63}'
require_pattern MPOS_DB_USER "${MPOS_DB_USER}" '[A-Za-z_][A-Za-z0-9_]{0,31}'
# DB password — no quotes or backslash (would break SQL heredoc).
# Allow common shell-safe punctuation.
require_pattern MPOS_DB_PASS "${MPOS_DB_PASS}" '[A-Za-z0-9_\-]{8,128}' \
    "regenerate via 'export MPOS_DB_PASS=\$(head -c 32 /dev/urandom | xxd -p -c 256 | head -c 32)'"
require_pattern MPOS_DB_HOST "${MPOS_DB_HOST}" '[A-Za-z0-9._\-]{1,253}'
require_pattern MPOS_DB_PORT "${MPOS_DB_PORT}" '[1-9][0-9]{0,4}'

# Salts are sed-substituted into PHP single-quoted strings.
# Hex-only is the simplest safe alphabet.
require_pattern MPOS_SALT  "${MPOS_SALT}"  '[A-Fa-f0-9]{4,64}'
require_pattern MPOS_SALTY "${MPOS_SALTY}" '[A-Fa-f0-9]{4,64}'
require_pattern MPOS_API_TOKEN "${MPOS_API_TOKEN}" '[A-Fa-f0-9]{8,128}'

# Admin creds go into a SQL heredoc and a PHP password hash. Same
# constraint as DB pass.
require_pattern MPOS_ADMIN_USER "${MPOS_ADMIN_USER}" '[A-Za-z0-9_]{1,32}'
require_pattern MPOS_ADMIN_PASS "${MPOS_ADMIN_PASS}" '[A-Za-z0-9_\-]{8,128}'

# nginx config. server_name accepts wildcards but not `;` `"` etc.
require_pattern MPOS_DOMAIN    "${MPOS_DOMAIN}"    '[A-Za-z0-9._\-\*_]{1,253}|_'
require_pattern MPOS_HTTP_PORT "${MPOS_HTTP_PORT}" '[1-9][0-9]{0,4}'

# Filesystem roots — disallow whitespace and shell metas.
require_pattern MPOS_INSTALL_ROOT "${MPOS_INSTALL_ROOT}" '/[A-Za-z0-9._\-/]+'
require_pattern MPOS_WEB_ROOT     "${MPOS_WEB_ROOT}"     '/[A-Za-z0-9._\-/]+'
require_pattern MPOS_LOG_ROOT     "${MPOS_LOG_ROOT}"     '/[A-Za-z0-9._\-/]+'

# System users (passed to chown / usermod -G).
require_pattern MPOS_RUN_USER  "${MPOS_RUN_USER}"  '[a-z_][a-z0-9_\-]{0,31}'
require_pattern MPOS_RUN_GROUP "${MPOS_RUN_GROUP}" '[a-z_][a-z0-9_\-]{0,31}'

[ "$(id -u)" -eq 0 ] || die "must run as root (re-run with sudo)"

if [ "$RUN_LOCAL" = "0" ]; then
    die "remote SSH mode is not yet implemented; pass -local for now"
fi

if [ -d "$ELIOPOOL_TREE" ]; then
    say "using Eliopool tree at $ELIOPOOL_TREE"
else
    die "Eliopool tree not found at $ELIOPOOL_TREE - set ELIOPOOL_TREE or clone eloipool_Blakecoin there"
fi

run_step() {
    local script="$1"
    say "running $(basename "$script")"
    bash "$script"
}

if [ "$WIPE" = "1" ]; then
    run_step "${SCRIPT_DIR}/scripts/05-wipe.sh"
fi

# Persist the rendered envrc AFTER the optional wipe step so individual
# sub-scripts (and the operator, post-deploy) can re-run any step
# without re-deriving these values.
mkdir -p "$MPOS_INSTALL_ROOT"
ENVRC="${MPOS_INSTALL_ROOT}/.deploy.env"
{
    echo "# generated by deploy.sh on $(date -Iseconds)"
    for var in ELIOPOOL_TREE MPOS_REPO_ROOT MPOS_DEPLOY_BUNDLE \
               MPOS_INSTALL_ROOT MPOS_WEB_ROOT MPOS_LOG_ROOT \
               MPOS_DOMAIN MPOS_HTTP_PORT \
               MPOS_DB_NAME MPOS_DB_USER MPOS_DB_HOST MPOS_DB_PORT MPOS_DB_PASS \
               MPOS_ADMIN_USER MPOS_ADMIN_PASS \
               MPOS_RUN_USER MPOS_RUN_GROUP \
               MPOS_SALT MPOS_SALTY MPOS_API_TOKEN \
               MPOS_SKIP_POOL MPOS_WIPE; do
        printf 'export %s=%q\n' "$var" "${!var}"
    done
} > "$ENVRC"
chmod 600 "$ENVRC"

run_step "${SCRIPT_DIR}/scripts/10-system-deps.sh"

if [ "$SKIP_POOL" = "0" ]; then
    run_step "${SCRIPT_DIR}/scripts/20-pull-daemons.sh"
    run_step "${SCRIPT_DIR}/scripts/30-init-daemons.sh"
    run_step "${SCRIPT_DIR}/scripts/40-install-pool.sh"
else
    say "--skip-pool: assuming Eliopool stack is already up"
fi

run_step "${SCRIPT_DIR}/scripts/50-install-mpos.sh"
run_step "${SCRIPT_DIR}/scripts/60-install-cronjobs-py.sh"
run_step "${SCRIPT_DIR}/scripts/99-verify.sh"

say "deploy complete"
echo
echo "  MPOS UI:        http://$(hostname -I | awk '{print $1}'):${MPOS_HTTP_PORT}/"
echo "  Stratum:        stratum+tcp://$(hostname -I | awk '{print $1}'):3334"
echo "  DB password:    ${MPOS_DB_PASS}  (also stored in ${ENVRC})"
echo "  Admin user:     ${MPOS_ADMIN_USER}"
echo "  Admin password: ${MPOS_ADMIN_PASS}"
