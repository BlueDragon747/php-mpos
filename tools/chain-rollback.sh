#!/usr/bin/env bash
# Manual chain-tip rollback planner/apply tool for BlakeStream daemon nodes.
#
# This tool does not edit blk*.dat, rev*.dat, chainstate, or wallet files.
# It creates a JSON rollback plan with exact target heights and block hashes,
# then applies that same plan with daemon RPC invalidateblock. Copy the plan to
# each node and apply it there so every node rolls back the same chains to the
# same heights.
set -euo pipefail

say() { printf '\033[1;33m   %s\033[0m\n' "$*"; }
warn() { printf '\033[1;31m   warning: %s\033[0m\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

clear_tool_screen() {
  [ "${BLAKESTREAM_TOOL_CLEAR:-1}" = "1" ] || return 1
  if [ -t 2 ]; then
    clear >&2 2>/dev/null || printf '\033[H\033[J' >&2
    return 0
  fi
  if [ -t 1 ]; then
    clear 2>/dev/null || printf '\033[H\033[J'
    return 0
  fi
  return 1
}

ACTION="plan"
MODE="regtest"
PLAN_FILE=""
OUT_FILE=""
ASSUME_YES=false
STOP_POOL=1
START_POOL_PROMPT=1
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DEFAULT_MPOS_LOG_ROOT="${SCRIPT_DIR}/logs"
CALLER_MPOS_LOG_ROOT="${MPOS_LOG_ROOT:-}"
REGTEST_MINER_SCRIPT="${SCRIPT_DIR}/mine-regtest-coins.sh"

if [ -r "${SCRIPT_DIR}/lib/tool-banner.sh" ]; then
  # shellcheck disable=SC1091
  . "${SCRIPT_DIR}/lib/tool-banner.sh"
fi

print_tool_banner() {
  local force="${1:-}"
  local previous_printed="${BLAKESTREAM_TOOL_BANNER_PRINTED:-0}"
  if [ "$force" = "force" ]; then
    export BLAKESTREAM_TOOL_BANNER_PRINTED=0
  fi
  if declare -F print_blakestream_banner >/dev/null; then
    print_blakestream_banner
  fi
  if [ "$force" = "force" ]; then
    export BLAKESTREAM_TOOL_BANNER_PRINTED="$previous_printed"
  fi
}

clear_tool_screen || true
print_tool_banner

usage() {
  cat <<'EOF'
Usage:
  sudo tools/chain-rollback.sh
  sudo tools/chain-rollback.sh --main plan
  sudo tools/chain-rollback.sh --main apply --plan chain-rollback-plan.json
  sudo tools/chain-rollback.sh --main status --plan chain-rollback-plan.json

Actions:
  default    Run a disposable regtest smoke test against temporary containers.
  plan       With --main, write a reusable rollback plan for live daemon nodes.
  apply      With --main, apply a JSON rollback plan with invalidateblock.
  status     With --main, compare current chain tips to a JSON rollback plan.

Options:
  --main           Enable live-node rollback mode.
  --plan FILE       Plan JSON to apply or inspect.
  --out FILE        Output path for plan mode.
  --yes             Skip the apply confirmation prompt.
  --no-stop-pool    Do not stop Stratum/proxy services before apply.
  --no-start-prompt Do not ask whether to restart pool services after apply.

Workflow:
  1. Run plan once on a synced node:
       sudo tools/chain-rollback.sh --main plan

  2. Copy the generated JSON plan to every pool/node that must roll back.

  3. On each node, run:
       sudo tools/chain-rollback.sh --main apply --plan chain-rollback-plan.json

This keeps selected chains, rollback heights, and invalidate hashes identical
across nodes. Wallet backups are written before apply unless disabled with:
  MPOS_ROLLBACK_REQUIRE_WALLET_BACKUP=0

Plans and apply manifests are written to a logs directory beside this script
unless MPOS_LOG_ROOT is explicitly set by the operator. When run through sudo
by a normal user, those operator-facing files are chowned back to that user
with mode 600 so they remain private but readable over SFTP/WinSCP.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --main) MODE="main"; shift ;;
    plan|create-plan|apply|status) ACTION="$1"; shift ;;
    --plan) PLAN_FILE="$2"; shift 2 ;;
    --out) OUT_FILE="$2"; shift 2 ;;
    --yes) ASSUME_YES=true; shift ;;
    --no-stop-pool) STOP_POOL=0; shift ;;
    --no-start-prompt) START_POOL_PROMPT=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

if [[ "$ACTION" == "create-plan" ]]; then ACTION="plan"; fi

[ "$(id -u)" = "0" ] || die "run as root"

if [ -f /root/.mpos-deploy.env ]; then
  # shellcheck disable=SC1091
  . /root/.mpos-deploy.env
fi

export MPOS_LOG_ROOT="${CALLER_MPOS_LOG_ROOT:-$DEFAULT_MPOS_LOG_ROOT}"
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
declare -A CONFIG_FILE=(
  [blc]="blakecoin.conf"
  [pho]="photon.conf"
  [bbtc]="blakebitcoin.conf"
  [elt]="electron.conf"
  [lit]="lithium.conf"
  [umo]="universalmolecule.conf"
)
MPOS_REGTEST_CONTAINER_PREFIX="${MPOS_REGTEST_CONTAINER_PREFIX:-mpos-regtest-}"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

read_user_line() {
  local var_name="$1"
  if [ -t 0 ] && [ -r /dev/tty ]; then
    IFS= read -r "$var_name" < /dev/tty
  else
    IFS= read -r "$var_name"
  fi
}

print_selection_intro() {
  if [ "$MODE" = "regtest" ]; then
    say "REGTEST SMOKE TEST MODE" >&2
    say "This default run only tests disposable regtest containers." >&2
    say "For live/mainnet rollback, do not use smoke mode; run: sudo ./chain-rollback.sh --main plan" >&2
  else
    say "LIVE MAINNET ROLLBACK MODE" >&2
    say "This mode creates or applies rollback plans for existing daemon containers." >&2
    say "Copy the generated plan to every node that must roll back to the same chain heights." >&2
  fi
}

redraw_coin_selection_screen() {
  clear_tool_screen || return 1
  print_tool_banner force >&2
  print_selection_intro
  return 0
}

unit_exists() {
  systemctl cat "$1" >/dev/null 2>&1
}

stop_pool_services() {
  [ "$STOP_POOL" = "1" ] || return 0
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

parse_coin_tokens() {
  local raw="$1" item coin index selected=()
  if [ "$raw" = "all" ] || [ "$raw" = "0" ]; then
    printf '%s\n' "${COINS[@]}"
    return 0
  fi

  for item in $raw; do
    item="${item,,}"
    if [[ "$item" =~ ^[1-6]$ ]]; then
      index=$((item - 1))
      selected+=("${COINS[$index]}")
      continue
    fi
    is_known_coin "$item" || die "unknown chain: ${item}"
    selected+=("$item")
  done

  [ "${#selected[@]}" -gt 0 ] || die "no chains selected"
  for coin in "${COINS[@]}"; do
    for item in "${selected[@]}"; do
      [ "$coin" = "$item" ] && { printf '%s\n' "$coin"; break; }
    done
  done
}

coin_upper() {
  printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

env_value() {
  local name="$1"
  printf '%s' "${!name:-}"
}

regtest_container_name() {
  printf '%s%s' "$MPOS_REGTEST_CONTAINER_PREFIX" "$1"
}

live_container_name() {
  local coin="$1" upper value
  upper="$(coin_upper "$coin")"
  value="$(env_value "MPOS_CONTAINER_${upper}")"
  [ -n "$value" ] || value="$(env_value "MPOS_DAEMON_CONTAINER_${upper}")"
  [ -n "$value" ] || value="$coin"
  printf '%s' "$value"
}

coin_container_name() {
  if [ "$MODE" = "regtest" ]; then
    regtest_container_name "$1"
  else
    live_container_name "$1"
  fi
}

docker_cli() {
  local coin="$1" container
  shift
  container="$(coin_container_name "$coin")"
  docker exec "$container" "/usr/local/bin/${CLI_NAME[$coin]}" "-datadir=/root/${CONFIG_DIR[$coin]}" "$@"
}

coin_rpc() {
  local coin="$1"
  shift
  docker_cli "$coin" "$@" | tr -d '\r'
}

require_container_running() {
  local coin="$1" container
  container="$(coin_container_name "$coin")"
  if ! docker ps --format '{{.Names}}' | grep -qx "$container"; then
    die "${coin} container is not running (${container}); start the daemon before using RPC rollback"
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
  local raw coin index item notice
  local -A selected=()
  notice=""

  if [ ! -t 0 ]; then
    read_user_line raw
    parse_coin_tokens "$raw"
    return
  fi

  while :; do
    if ! redraw_coin_selection_screen; then
      printf '\n' >&2
    fi
    printf '\nSelect chains to roll back:\n' >&2
    index=1
    for coin in "${COINS[@]}"; do
      if [ "${selected[$coin]:-0}" = "1" ]; then
        printf '  %d) [*] %-5s %s\n' "$index" "$coin" "${COIN_LABEL[$coin]}" >&2
      else
        printf '  %d) [ ] %-5s %s\n' "$index" "$coin" "${COIN_LABEL[$coin]}" >&2
      fi
      index=$((index + 1))
    done
    printf '  0) toggle all\n' >&2
    if [ -n "$notice" ]; then
      warn "$notice"
      notice=""
    fi
    printf 'Type a number and press Enter to toggle, 0 for all, or press Enter when done: ' >&2
    read_user_line raw
    if [ -z "$raw" ]; then
      item=0
      for coin in "${COINS[@]}"; do
        [ "${selected[$coin]:-0}" = "1" ] && { printf '%s\n' "$coin"; item=1; }
      done
      [ "$item" = "1" ] && return
      notice="select at least one chain"
      continue
    fi

    if [ "$raw" = "0" ] || [ "${raw,,}" = "all" ]; then
      item=0
      for coin in "${COINS[@]}"; do
        [ "${selected[$coin]:-0}" != "1" ] && item=1
      done
      for coin in "${COINS[@]}"; do
        selected[$coin]="$item"
      done
      continue
    fi

    if [[ "$raw" =~ ^[1-6]$ ]]; then
      index=$((raw - 1))
      coin="${COINS[$index]}"
      if [ "${selected[$coin]:-0}" = "1" ]; then
        selected[$coin]=0
      else
        selected[$coin]=1
      fi
      continue
    fi

    notice="enter a number from 0 to 6"
  done
}

collect_coin_selection() {
  local -n target_ref="$1"
  local default_all="${2:-0}"
  local selection_file
  if [ "$default_all" = "1" ] && [ ! -t 0 ]; then
    target_ref=("${COINS[@]}")
    return
  fi
  selection_file="$(mktemp)"
  read_coin_selection > "$selection_file"
  mapfile -t target_ref < "$selection_file"
  rm -f "$selection_file"
}

read_target_height() {
  local coin="$1"
  local current="$2"
  local target

  while :; do
    printf "Target height for %s (%s), current %s: " "$coin" "${COIN_LABEL[$coin]}" "$current" >&2
    read_user_line target
    if [[ "$target" =~ ^[0-9]+$ ]] && [ "$target" -lt "$current" ]; then
      printf '%s\n' "$target"
      return
    fi
    warn "enter a numeric height lower than current height ${current}"
  done
}

confirm_apply() {
  local reply
  $ASSUME_YES && return 0
  printf '\nType APPLY-ROLLBACK to stop pool services and apply this plan on this node: '
  read_user_line reply
  [ "$reply" = "APPLY-ROLLBACK" ] || die "aborted"
}

operator_owner_spec() {
  if [ -n "${SUDO_UID:-}" ] && [ -n "${SUDO_GID:-}" ] && [ "${SUDO_UID}" != "0" ]; then
    printf '%s:%s\n' "$SUDO_UID" "$SUDO_GID"
    return 0
  fi
  return 1
}

protect_operator_file() {
  local path="$1"
  local owner=""
  [ -e "$path" ] || return 0
  chmod 600 "$path"
  if owner="$(operator_owner_spec)"; then
    chown "$owner" "$path" || warn "could not chown ${path} to sudo user ${owner}"
  fi
}

ensure_log_root() {
  local owner=""
  mkdir -p "$MPOS_LOG_ROOT"
  [ "$MPOS_LOG_ROOT" = "$DEFAULT_MPOS_LOG_ROOT" ] || return 0
  chmod 700 "$MPOS_LOG_ROOT"
  if owner="$(operator_owner_spec)"; then
    chown "$owner" "$MPOS_LOG_ROOT" || warn "could not chown ${MPOS_LOG_ROOT} to sudo user ${owner}"
  fi
}

plan_output_path() {
  local stamp="$1"
  if [ -n "$OUT_FILE" ]; then
    printf '%s\n' "$OUT_FILE"
  else
    ensure_log_root
    printf '%s/chain-rollback-plan-%s.json\n' "$MPOS_LOG_ROOT" "$stamp"
  fi
}

create_plan() {
  local selected=()
  local coin current target invalidate_height invalidate_hash target_hash tip_hash
  local stamp host chains_json item out

  need_cmd docker
  need_cmd jq
  collect_coin_selection selected
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  host="$(hostname -f 2>/dev/null || hostname)"
  chains_json='[]'

  say "collecting current chain tips and rollback hashes"
  for coin in "${selected[@]}"; do
    require_container_running "$coin"
    current="$(coin_rpc "$coin" getblockcount)"
    tip_hash="$(coin_rpc "$coin" getbestblockhash)"
    target="$(read_target_height "$coin" "$current")"
    invalidate_height=$((target + 1))
    invalidate_hash="$(coin_rpc "$coin" getblockhash "$invalidate_height")"
    target_hash="$(coin_rpc "$coin" getblockhash "$target")"

    item="$(jq -nc \
      --arg coin "$coin" \
      --arg label "${COIN_LABEL[$coin]}" \
      --argjson current_height "$current" \
      --arg old_tip_hash "$tip_hash" \
      --argjson target_height "$target" \
      --arg target_hash "$target_hash" \
      --argjson invalidate_height "$invalidate_height" \
      --arg invalidate_hash "$invalidate_hash" \
      '{coin:$coin,label:$label,current_height:$current_height,old_tip_hash:$old_tip_hash,target_height:$target_height,target_hash:$target_hash,invalidate_height:$invalidate_height,invalidate_hash:$invalidate_hash}')"
    chains_json="$(jq -c --argjson item "$item" '. + [$item]' <<<"$chains_json")"
  done

  out="$(plan_output_path "$stamp")"
  mkdir -p "$(dirname "$out")"
  jq -n \
    --arg schema "chain-rollback-plan-v1" \
    --arg created_utc "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg created_by "${SUDO_USER:-root}" \
    --arg source_host "$host" \
    --arg note "Apply this exact plan on every node that must roll back to the same selected chain heights." \
    --argjson chains "$chains_json" \
    '{schema:$schema,created_utc:$created_utc,created_by:$created_by,source_host:$source_host,note:$note,chains:$chains}' \
    > "$out"
  protect_operator_file "$out"

  printf '\nRollback plan written:\n  %s\n\n' "$out"
  jq -r '.chains[] | "  \(.coin) current=\(.current_height) target=\(.target_height) invalidate_height=\(.invalidate_height) hash=\(.invalidate_hash[0:16])..."' "$out"
  cat <<EOF

Copy this JSON file to each node that should roll back, then run:

  sudo tools/chain-rollback.sh apply --plan $(basename "$out")

The apply step verifies the planned invalidate hash on each node before calling
invalidateblock. Use the same plan file everywhere to keep rollback heights
consistent across all nodes.
EOF
}

plan_chains() {
  local plan="$1"
  jq -c '.chains[]' "$plan"
}

validate_plan_file() {
  local plan="$1"
  [ -n "$plan" ] || die "--plan FILE is required"
  [ -f "$plan" ] || die "plan file not found: $plan"
  jq -e '(.schema == "chain-rollback-plan-v1" or .schema == "blakestream-chain-rollback-plan-v1") and (.chains | type == "array") and (.chains | length > 0)' "$plan" >/dev/null \
    || die "invalid rollback plan: $plan"
}

status_plan() {
  local row coin current target invalidate_height invalidate_hash local_hash

  need_cmd docker
  need_cmd jq
  validate_plan_file "$PLAN_FILE"

  printf '%-5s %12s %12s %-8s %s\n' "COIN" "CURRENT" "TARGET" "MATCH" "DETAIL"
  while IFS= read -r row; do
    coin="$(jq -r '.coin' <<<"$row")"
    target="$(jq -r '.target_height' <<<"$row")"
    invalidate_height="$(jq -r '.invalidate_height' <<<"$row")"
    invalidate_hash="$(jq -r '.invalidate_hash' <<<"$row")"
    require_container_running "$coin"
    current="$(coin_rpc "$coin" getblockcount)"
    local_hash="$(coin_rpc "$coin" getblockhash "$invalidate_height" 2>/dev/null || true)"
    if [ "$local_hash" = "$invalidate_hash" ]; then
      printf '%-5s %12s %12s %-8s %s\n' "$coin" "$current" "$target" "yes" "invalidate hash matches"
    else
      printf '%-5s %12s %12s %-8s %s\n' "$coin" "$current" "$target" "no" "planned hash differs or unavailable"
    fi
  done < <(plan_chains "$PLAN_FILE")
}

apply_plan() {
  local row coin target invalidate_height invalidate_hash current local_hash stamp manifest restart_reply after

  need_cmd docker
  need_cmd jq
  validate_plan_file "$PLAN_FILE"
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  ensure_log_root
  manifest="${MPOS_LOG_ROOT}/chain-rollback-apply-${stamp}.log"

  printf '\nPlan summary:\n'
  jq -r '.chains[] | "  \(.coin) -> target \(.target_height), invalidate height \(.invalidate_height)"' "$PLAN_FILE"
  printf '\nThis marks each planned block at target+1 and descendants invalid on this node.\n'
  printf 'It does not delete block files. Use reconsiderblock with the logged hash to undo.\n'
  confirm_apply

  {
    printf 'chain rollback apply %s\n' "$stamp"
    printf 'plan=%s\n' "$PLAN_FILE"
    printf 'operator=%s host=%s\n' "${SUDO_USER:-root}" "$(hostname -f 2>/dev/null || hostname)"
  } >"$manifest"
  protect_operator_file "$manifest"

  stop_pool_services

  while IFS= read -r row; do
    coin="$(jq -r '.coin' <<<"$row")"
    target="$(jq -r '.target_height' <<<"$row")"
    invalidate_height="$(jq -r '.invalidate_height' <<<"$row")"
    invalidate_hash="$(jq -r '.invalidate_hash' <<<"$row")"
    require_container_running "$coin"
    current="$(coin_rpc "$coin" getblockcount)"

    if [ "$current" -le "$target" ]; then
      warn "${coin} current height ${current} is already at/below target ${target}; skipping"
      continue
    fi

    local_hash="$(coin_rpc "$coin" getblockhash "$invalidate_height" 2>/dev/null || true)"
    if [ "$local_hash" != "$invalidate_hash" ]; then
      die "${coin} planned invalidate hash does not match this node at height ${invalidate_height}; refusing to roll back"
    fi

    backup_wallet "$coin" "$stamp"
    say "rolling back ${coin}: ${current} -> ${target} (invalidate height ${invalidate_height})"
    coin_rpc "$coin" invalidateblock "$invalidate_hash" >/dev/null
    after="$(coin_rpc "$coin" getblockcount)"
    {
      printf '\n[%s]\n' "$coin"
      printf 'label=%s\n' "$(jq -r '.label' <<<"$row")"
      printf 'height_before=%s\n' "$current"
      printf 'target_height=%s\n' "$target"
      printf 'invalidated_height=%s\n' "$invalidate_height"
      printf 'invalidated_hash=%s\n' "$invalidate_hash"
      printf 'height_after=%s\n' "$after"
      printf 'undo_rpc=docker exec %s /usr/local/bin/%s -datadir=/root/%s reconsiderblock %s\n' \
        "$(coin_container_name "$coin")" "${CLI_NAME[$coin]}" "${CONFIG_DIR[$coin]}" "$invalidate_hash"
    } >>"$manifest"
    say "${coin} done: height ${after}"
    if [ "$after" != "$target" ]; then
      warn "${coin} height after rollback is ${after}, expected ${target}; review ${manifest} before restarting pool services"
    fi
  done < <(plan_chains "$PLAN_FILE")

  say "rollback apply manifest written to ${manifest}"
  if [ "$START_POOL_PROMPT" = "1" ]; then
    printf '\nRestart pool services now? Only do this if the selected daemon tips are intentional. [y/N]: '
    read_user_line restart_reply
    if [[ "$restart_reply" =~ ^[Yy]$ ]]; then
      start_pool_services
    else
      say "pool services left stopped; start them manually after verification"
    fi
  fi
}

smoke_cleanup_containers() {
  [ "${SMOKE_KEEP_CONTAINERS:-0}" = "0" ] || return 0
  local coin container
  for coin in "${COINS[@]}"; do
    container="$(regtest_container_name "$coin")"
    if docker ps -a --format '{{.Names}}' | grep -qx "$container"; then
      if [ "$(docker inspect -f '{{ index .Config.Labels "blakestream.rollback-smoke" }}' "$container" 2>/dev/null || true)" = "1" ]; then
        docker rm -f "$container" >/dev/null 2>&1 || true
      fi
    fi
  done
}

smoke_copy_results() {
  mkdir -p "$SMOKE_WORK_DIR"
  local file
  for file in "$SMOKE_PLAN_FULL" "$SMOKE_PLAN_PARTIAL"; do
    [ -f "$file" ] || continue
    cp -p "$file" "${SMOKE_WORK_DIR}/$(basename "$file")"
  done
}

smoke_on_exit() {
  local status="$?"
  smoke_copy_results >/dev/null 2>&1 || true
  if [ "$status" -eq 0 ]; then
    smoke_cleanup_containers
  else
    say "smoke test failed; temporary containers and data were left for inspection under ${SMOKE_WORK_DIR}"
  fi
}

smoke_wait_rpc() {
  local coin="$1" ready=0
  for _ in $(seq 1 120); do
    if coin_rpc "$coin" getblockcount >/dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 1
  done
  [ "$ready" = "1" ] || {
    docker logs --tail 120 "$(regtest_container_name "$coin")" > "${SMOKE_LOG_DIR}/${coin}-rpc-failure.log" 2>&1 || true
    die "${coin} RPC did not become ready; see ${SMOKE_LOG_DIR}/${coin}-rpc-failure.log"
  }
}

smoke_mining_address() {
  local coin="$1" addr
  if addr="$(coin_rpc "$coin" getnewaddress 2>/dev/null)"; then
    printf '%s\n' "$addr"
    return 0
  fi
  if docker_cli "$coin" createwallet rollback >/dev/null 2>&1; then
    docker_cli "$coin" -rpcwallet=rollback getnewaddress
    return 0
  fi
  if docker_cli "$coin" loadwallet rollback >/dev/null 2>&1; then
    docker_cli "$coin" -rpcwallet=rollback getnewaddress
    return 0
  fi
  return 1
}

smoke_mine_blocks() {
  local coin="$1" blocks="$2" addr before after
  before="$(coin_rpc "$coin" getblockcount)"
  addr="$(smoke_mining_address "$coin")" || die "failed to get mining address for ${coin}"
  say "mining ${blocks} ${coin} regtest blocks from height ${before}"
  docker_cli "$coin" generatetoaddress "$blocks" "$addr" > "${SMOKE_LOG_DIR}/${coin}-generated-${before}.txt"
  after="$(coin_rpc "$coin" getblockcount)"
  printf '%s mined before=%s after=%s\n' "$coin" "$before" "$after" | tee -a "$SMOKE_RUN_LOG"
}

smoke_create_plan() {
  local out="$1" target="$2" prompt_targets="${3:-0}"
  shift 3
  local selected=("$@")
  local coin current rollback_target invalidate_height invalidate_hash target_hash tip_hash
  local stamp host chains_json item

  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  host="$(hostname -f 2>/dev/null || hostname)"
  chains_json='[]'

  say "collecting regtest chain heights for $(basename "$out")"
  for coin in "${selected[@]}"; do
    require_container_running "$coin"
    current="$(coin_rpc "$coin" getblockcount)"
    tip_hash="$(coin_rpc "$coin" getbestblockhash)"
    if [ "$prompt_targets" = "1" ]; then
      rollback_target="$(read_target_height "$coin" "$current")"
    else
      rollback_target="$target"
      if [ "$rollback_target" -ge "$current" ]; then
        die "${coin} default rollback target ${rollback_target} is not below current height ${current}"
      fi
      printf 'Target height for %s (%s), current %s: %s\n' "$coin" "${COIN_LABEL[$coin]}" "$current" "$rollback_target" | tee -a "$SMOKE_RUN_LOG"
    fi
    invalidate_height=$((rollback_target + 1))
    invalidate_hash="$(coin_rpc "$coin" getblockhash "$invalidate_height")"
    target_hash="$(coin_rpc "$coin" getblockhash "$rollback_target")"
    item="$(jq -nc \
      --arg coin "$coin" \
      --arg label "${COIN_LABEL[$coin]}" \
      --argjson current_height "$current" \
      --arg old_tip_hash "$tip_hash" \
      --argjson target_height "$rollback_target" \
      --arg target_hash "$target_hash" \
      --argjson invalidate_height "$invalidate_height" \
      --arg invalidate_hash "$invalidate_hash" \
      '{coin:$coin,label:$label,current_height:$current_height,old_tip_hash:$old_tip_hash,target_height:$target_height,target_hash:$target_hash,invalidate_height:$invalidate_height,invalidate_hash:$invalidate_hash}')"
    chains_json="$(jq -c --argjson item "$item" '. + [$item]' <<<"$chains_json")"
  done

  jq -n \
    --arg schema "chain-rollback-plan-v1" \
    --arg created_utc "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg created_by "${SUDO_USER:-root}" \
    --arg source_host "$host" \
    --arg note "Regtest rollback smoke plan. Apply this exact plan only to the matching rollback-smoke fixture." \
    --argjson chains "$chains_json" \
    '{schema:$schema,created_utc:$created_utc,created_by:$created_by,source_host:$source_host,note:$note,chains:$chains}' \
    > "$out"
  protect_operator_file "$out"
  jq -r '.chains[] | "  \(.coin) current=\(.current_height) target=\(.target_height) invalidate_height=\(.invalidate_height)"' "$out" | tee -a "$SMOKE_RUN_LOG"
  say "created rollback plan $(basename "$out")"
}

smoke_apply_plan() {
  local plan="$1"
  local old_plan="$PLAN_FILE" old_yes="$ASSUME_YES" old_stop="$STOP_POOL" old_prompt="$START_POOL_PROMPT"
  PLAN_FILE="$plan"
  status_plan | tee -a "$SMOKE_RUN_LOG"
  ASSUME_YES=true
  STOP_POOL=0
  START_POOL_PROMPT=0
  apply_plan | tee -a "$SMOKE_RUN_LOG"
  PLAN_FILE="$old_plan"
  ASSUME_YES="$old_yes"
  STOP_POOL="$old_stop"
  START_POOL_PROMPT="$old_prompt"
}

smoke_verify_coin_at_target() {
  local coin="$1" plan="$2" current target target_hash best invalidate_height next_hash backups=()
  current="$(coin_rpc "$coin" getblockcount)"
  target="$(jq -r --arg coin "$coin" '.chains[] | select(.coin == $coin) | .target_height' "$plan")"
  target_hash="$(jq -r --arg coin "$coin" '.chains[] | select(.coin == $coin) | .target_hash' "$plan")"
  invalidate_height="$(jq -r --arg coin "$coin" '.chains[] | select(.coin == $coin) | .invalidate_height' "$plan")"
  best="$(coin_rpc "$coin" getbestblockhash)"
  next_hash="$(coin_rpc "$coin" getblockhash "$invalidate_height" 2>/dev/null || true)"
  shopt -s nullglob
  backups=("${SMOKE_DATA_DIR}/${coin}"/rollback-wallet-*.dat)
  shopt -u nullglob
  if [ "$current" = "$target" ] && [ "$best" = "$target_hash" ] && [ -z "$next_hash" ] && [ "${#backups[@]}" -gt 0 ]; then
    printf '%s PASS current=%s target=%s wallet_backups=%s\n' "$coin" "$current" "$target" "${#backups[@]}" | tee -a "$SMOKE_VERIFY_LOG"
  else
    printf '%s FAIL current=%s target=%s best=%s target_hash=%s next_hash=%s wallet_backups=%s\n' \
      "$coin" "$current" "$target" "$best" "$target_hash" "${next_hash:-unavailable}" "${#backups[@]}" | tee -a "$SMOKE_VERIFY_LOG"
    return 1
  fi
}

smoke_verify_coin_unchanged() {
  local coin="$1" expected="$2" current
  current="$(coin_rpc "$coin" getblockcount)"
  if [ "$current" = "$expected" ]; then
    printf '%s PASS unchanged_height=%s\n' "$coin" "$current" | tee -a "$SMOKE_VERIFY_LOG"
  else
    printf '%s FAIL expected_unchanged_height=%s current=%s\n' "$coin" "$expected" "$current" | tee -a "$SMOKE_VERIFY_LOG"
    return 1
  fi
}

smoke_select_chains() {
  if [ -t 0 ]; then
    say "select regtest chains for this smoke test"
    read_coin_selection
    return
  fi
  printf '%s\n' "${COINS[@]}"
}

contains_coin() {
  local needle="$1" coin
  shift
  for coin in "$@"; do
    [ "$coin" = "$needle" ] && return 0
  done
  return 1
}

run_regtest_smoke() {
  need_cmd docker
  need_cmd jq

  local test_id mine_blocks target_height partial_target_height partial_extra_blocks
  local coin full_ok partial_ok
  local smoke_coins=() partial_coins=()
  local miner_args=()
  local prompt_full_targets prompt_partial_targets

  SMOKE_RUN_DIR="$(pwd -P)"
  test_id="${ROLLBACK_TEST_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
  SMOKE_WORK_DIR="${ROLLBACK_TEST_WORK_DIR:-${SMOKE_RUN_DIR}/chainrollback-regtest-${test_id}}"
  SMOKE_DATA_DIR="${SMOKE_WORK_DIR}/datadirs"
  SMOKE_LOG_DIR="${SMOKE_WORK_DIR}/logs"
  mine_blocks="${ROLLBACK_TEST_MINE_BLOCKS:-1105}"
  target_height="${ROLLBACK_TEST_TARGET_HEIGHT:-1000}"
  partial_target_height="${ROLLBACK_TEST_PARTIAL_TARGET_HEIGHT:-1010}"
  partial_extra_blocks="${ROLLBACK_TEST_PARTIAL_EXTRA_BLOCKS:-30}"
  prompt_full_targets="${ROLLBACK_TEST_PROMPT_TARGETS:-}"
  prompt_partial_targets="${ROLLBACK_TEST_PROMPT_PARTIAL_TARGETS:-0}"
  if [ -z "$prompt_full_targets" ]; then
    if [ -t 0 ]; then
      prompt_full_targets=1
    else
      prompt_full_targets=0
    fi
  fi
  SMOKE_KEEP_CONTAINERS="${KEEP_ROLLBACK_TEST_CONTAINERS:-1}"
  SMOKE_PLAN_FULL="${SMOKE_RUN_DIR}/chain-rollback-regtest-full-${test_id}.json"
  SMOKE_PLAN_PARTIAL="${SMOKE_RUN_DIR}/chain-rollback-regtest-partial-${test_id}.json"
  SMOKE_VERIFY_LOG="${SMOKE_LOG_DIR}/chain-rollback-regtest-verify-${test_id}.txt"
  SMOKE_RUN_LOG="${SMOKE_LOG_DIR}/chain-rollback-regtest-run-${test_id}.log"
  MPOS_LOG_ROOT="$SMOKE_LOG_DIR"

  trap smoke_on_exit EXIT
  mkdir -p "$SMOKE_DATA_DIR" "$SMOKE_LOG_DIR"
  : > "$SMOKE_RUN_LOG"
  : > "$SMOKE_VERIFY_LOG"

  say "REGTEST SMOKE TEST MODE"
  say "This default run only tests disposable regtest containers."
  say "For live/mainnet rollback, do not use smoke mode; run: sudo ./chain-rollback.sh --main plan"
  collect_coin_selection smoke_coins 1
  [ "${#smoke_coins[@]}" -gt 0 ] || die "no chains selected for regtest smoke test"
  partial_coins=("${smoke_coins[@]:0:2}")
  say "selected regtest chains: ${smoke_coins[*]}"
  say "writing smoke-test results in ${SMOKE_RUN_DIR}"
  say "using temporary data under ${SMOKE_WORK_DIR}"

  [ -x "$REGTEST_MINER_SCRIPT" ] || die "missing executable regtest miner helper: ${REGTEST_MINER_SCRIPT}"
  miner_args=(--work-dir "$SMOKE_WORK_DIR" --blocks "$mine_blocks" --reset)
  for coin in "${smoke_coins[@]}"; do
    miner_args+=(--coin "$coin")
  done
  say "preparing shared regtest fixture"
  BLAKESTREAM_TOOL_CLEAR=0 BLAKESTREAM_TOOL_BANNER=0 "$REGTEST_MINER_SCRIPT" "${miner_args[@]}" | tee -a "$SMOKE_RUN_LOG"

  for coin in "${smoke_coins[@]}"; do
    smoke_wait_rpc "$coin"
    printf '%s rpc_ready height=%s\n' "$coin" "$(coin_rpc "$coin" getblockcount)" | tee -a "$SMOKE_RUN_LOG"
  done

  smoke_create_plan "$SMOKE_PLAN_FULL" "$target_height" "$prompt_full_targets" "${smoke_coins[@]}"
  smoke_apply_plan "$SMOKE_PLAN_FULL"

  full_ok=1
  for coin in "${smoke_coins[@]}"; do
    smoke_verify_coin_at_target "$coin" "$SMOKE_PLAN_FULL" || full_ok=0
  done
  [ "$full_ok" = "1" ] || die "full rollback verification failed"

  for coin in "${partial_coins[@]}"; do
    smoke_mine_blocks "$coin" "$partial_extra_blocks"
  done

  smoke_create_plan "$SMOKE_PLAN_PARTIAL" "$partial_target_height" "$prompt_partial_targets" "${partial_coins[@]}"
  smoke_apply_plan "$SMOKE_PLAN_PARTIAL"

  partial_ok=1
  for coin in "${partial_coins[@]}"; do
    smoke_verify_coin_at_target "$coin" "$SMOKE_PLAN_PARTIAL" || partial_ok=0
  done
  for coin in "${smoke_coins[@]}"; do
    contains_coin "$coin" "${partial_coins[@]}" && continue
    smoke_verify_coin_unchanged "$coin" "$target_height" || partial_ok=0
  done
  [ "$partial_ok" = "1" ] || die "partial rollback verification failed"

  say "chain rollback smoke test passed"
  smoke_copy_results
  printf 'Run log: %s\nVerify log: %s\nFull plan: %s\nPartial plan: %s\nResult folder: %s\n' \
    "$SMOKE_RUN_LOG" "$SMOKE_VERIFY_LOG" "$SMOKE_PLAN_FULL" "$SMOKE_PLAN_PARTIAL" "$SMOKE_WORK_DIR"
}

case "$ACTION" in
  plan) [ "$MODE" = "main" ] && create_plan || run_regtest_smoke ;;
  apply) [ "$MODE" = "main" ] && apply_plan || run_regtest_smoke ;;
  status) [ "$MODE" = "main" ] && status_plan || run_regtest_smoke ;;
  *) die "unsupported action: $ACTION" ;;
esac
