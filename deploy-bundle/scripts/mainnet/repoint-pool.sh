#!/usr/bin/env bash
# repoint-pool.sh — point the pool's per-coin coinbase/tracker addresses at new
# (swept-wallet) addresses by re-running 40-install-pool.sh with the override env
# it already understands (MPOS_TRACKER_ADDR / MPOS_AUX_ADDR_*).
#
# All address-placement logic (eloipool config.py, the eloipool systemd unit, and
# merged-mine-proxy.json) stays inside 40-install-pool.sh — this wrapper only:
#   * supplies the per-coin address overrides,
#   * sources the deploy env for the node RPC creds, and
#   * feeds the already-installed Go binaries back as *_GO_PREBUILT_BIN so 40
#     installs them instead of rebuilding from source (which runs `go test`).
# 40 then re-renders the config + restarts eloipool + mergeminer.
#
# Dry-run by default; pass --apply to actually re-render + restart.
set -euo pipefail

REPO="${MPOS_REPO_DIR:-/root/Blakestream-MPOS-25.2-GO}"
DEPLOY_ENV="${MPOS_DEPLOY_ENV:-/root/.mpos-deploy.env}"
INSTALL_ROOT="${MPOS_INSTALL_ROOT:-/opt/blakestream-mpos}"
APPLY=0
declare -A ADDR=()

ts()  { date -u +%Y-%m-%dT%H:%M:%SZ; }
die() { printf 'repoint-pool: %s\n' "$*" >&2; exit 1; }
log() { printf '%s\n' "$*"; }

usage() {
  cat <<USAGE
Usage: repoint-pool.sh [--apply] --blc <addr> [--pho <addr>] [--bbtc <addr>] [--elt <addr>] [--lit <addr>] [--umo <addr>]

Repoints the pool coinbase/tracker address for each given coin to <addr> by
re-running 40-install-pool.sh with the matching override env var. Coins you omit
keep their current address (40 tier-2 reuse). Dry-run unless --apply is given.

  --apply        actually re-render config + restart eloipool/mergeminer
  --blc <addr>   new parent (BLC) tracker address   -> MPOS_TRACKER_ADDR
  --pho|--bbtc|--elt|--lit|--umo <addr>
                 new aux payout address             -> MPOS_AUX_ADDR_<SYM>
  --repo <dir>   deploy repo dir   (default: ${REPO})
  --env  <file>  deploy env file   (default: ${DEPLOY_ENV})
  -h, --help     show this help
USAGE
}

# coin -> the override env var 40 reads.
declare -A ENVVAR=(
  [blc]=MPOS_TRACKER_ADDR
  [pho]=MPOS_AUX_ADDR_PHO  [bbtc]=MPOS_AUX_ADDR_BBTC  [elt]=MPOS_AUX_ADDR_ELT
  [lit]=MPOS_AUX_ADDR_LIT  [umo]=MPOS_AUX_ADDR_UMO
)

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --blc|--pho|--bbtc|--elt|--lit|--umo)
      c="${1#--}"; shift; [ $# -gt 0 ] || die "--$c needs an address"; ADDR[$c]="$1" ;;
    --repo) shift; [ $# -gt 0 ] || die "--repo needs a dir"; REPO="$1" ;;
    --env)  shift; [ $# -gt 0 ] || die "--env needs a file"; DEPLOY_ENV="$1" ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown arg: $1 (see --help)" ;;
  esac
  shift
done

[ "${#ADDR[@]}" -gt 0 ] || { usage >&2; die "no addresses given"; }

INSTALL40="${REPO}/deploy-bundle/scripts/mainnet/40-install-pool.sh"
[ -f "$INSTALL40" ] || die "missing $INSTALL40 (wrong --repo?)"

overrides=()
for c in blc pho bbtc elt lit umo; do
  [ -n "${ADDR[$c]:-}" ] && overrides+=("${ENVVAR[$c]}=${ADDR[$c]}")
done

log "Repoint plan @ $(ts)"
log "  runs:  $INSTALL40 (re-renders config + restarts eloipool/mergeminer)"
log "  overrides:"
for o in "${overrides[@]}"; do log "    $o"; done
log "  reuse installed binaries (no source rebuild):"
log "    ELIOPOOL_GO_PREBUILT_BIN <- ${INSTALL_ROOT}/bin/eloipool-go"
log "    MMP_GO_PREBUILT_BIN      <- ${INSTALL_ROOT}/bin/merged-mine-proxy-go"

if [ "$APPLY" != "1" ]; then
  log ""
  log "DRY RUN — nothing changed. Re-run with --apply to repoint + restart the pool."
  exit 0
fi

# ---- apply ----
[ -f "$DEPLOY_ENV" ] || die "missing deploy env $DEPLOY_ENV (node RPC creds); pass --env"
[ -x "${INSTALL_ROOT}/bin/eloipool-go" ]         || die "missing ${INSTALL_ROOT}/bin/eloipool-go"
[ -x "${INSTALL_ROOT}/bin/merged-mine-proxy-go" ] || die "missing ${INSTALL_ROOT}/bin/merged-mine-proxy-go"

printf '\nType YES to repoint the pool and restart eloipool/mergeminer: '
read -r ans
[ "$ans" = "YES" ] || die "aborted; nothing changed"

# Hand 40 the installed binaries as "prebuilt" so it copies them instead of
# rebuilding. Copy to a temp file first — install(1) errors on same src/dest.
TMPBIN="$(mktemp -d)"
trap 'rm -rf "$TMPBIN"' EXIT
cp -f "${INSTALL_ROOT}/bin/eloipool-go"          "${TMPBIN}/eloipool-go"
cp -f "${INSTALL_ROOT}/bin/merged-mine-proxy-go" "${TMPBIN}/merged-mine-proxy-go"

log "running 40-install-pool.sh @ $(ts) ..."
set -a
# shellcheck disable=SC1090
. "$DEPLOY_ENV"
ELIOPOOL_GO_PREBUILT_BIN="${TMPBIN}/eloipool-go"
MMP_GO_PREBUILT_BIN="${TMPBIN}/merged-mine-proxy-go"
[ -n "${ADDR[blc]:-}" ]  && MPOS_TRACKER_ADDR="${ADDR[blc]}"
[ -n "${ADDR[pho]:-}" ]  && MPOS_AUX_ADDR_PHO="${ADDR[pho]}"
[ -n "${ADDR[bbtc]:-}" ] && MPOS_AUX_ADDR_BBTC="${ADDR[bbtc]}"
[ -n "${ADDR[elt]:-}" ]  && MPOS_AUX_ADDR_ELT="${ADDR[elt]}"
[ -n "${ADDR[lit]:-}" ]  && MPOS_AUX_ADDR_LIT="${ADDR[lit]}"
[ -n "${ADDR[umo]:-}" ]  && MPOS_AUX_ADDR_UMO="${ADDR[umo]}"
set +a

bash "$INSTALL40"
log "repoint complete @ $(ts)."
