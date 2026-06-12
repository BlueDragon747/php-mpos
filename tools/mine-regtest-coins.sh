#!/usr/bin/env bash
set -euo pipefail

# Shared regtest fixture builder for the operator tools.
# It starts rollback-smoke daemon containers and mines spendable test outputs so
# chain rollback and wallet UTXO maintenance can use the same datadirs/wallets.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [ -r "${SCRIPT_DIR}/lib/tool-banner.sh" ]; then
  # shellcheck disable=SC1091
  . "${SCRIPT_DIR}/lib/tool-banner.sh"
fi

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

print_tool_banner() {
  if declare -F print_blakestream_banner >/dev/null; then
    print_blakestream_banner
  fi
}

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
declare -A DAEMON_NAME=(
  [blc]="blakecoind"
  [pho]="photond"
  [bbtc]="blakebitcoind"
  [elt]="electrond"
  [lit]="lithiumd"
  [umo]="universalmoleculed"
)
declare -A COIN_IMAGE_NAME=(
  [blc]="blakecoin"
  [pho]="photon"
  [bbtc]="blakebitcoin"
  [elt]="electron"
  [lit]="lithium"
  [umo]="universalmolecule"
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

RUN_DIR="$(pwd -P)"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
WORK_DIR="${MPOS_REGTEST_WORK_DIR:-}"
if [ "${MPOS_REGTEST_MINE_BLOCKS+x}" = "x" ]; then
  BLOCKS="$MPOS_REGTEST_MINE_BLOCKS"
  BLOCKS_FROM_ENV=1
else
  BLOCKS=2000
  BLOCKS_FROM_ENV=0
fi
BLOCKS_FROM_ARG=0
ENSURE_UTXOS="${MPOS_REGTEST_ENSURE_UTXOS:-0}"
RESET=false
SELECTED=()
RUN_LOG=""
RUN_JSON=""
MPOS_DOCKER_HUB="${MPOS_DOCKER_HUB:-sidgrip}"
MPOS_IMAGE_TAG="${MPOS_IMAGE_TAG:-25.2}"
MPOS_REGTEST_CONTAINER_PREFIX="${MPOS_REGTEST_CONTAINER_PREFIX:-mpos-regtest-}"

say() { printf '\033[1;33m   %s\033[0m\n' "$*"; }
ok() { printf '\033[0;32m[OK]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;31m   warning: %s\033[0m\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage:
  sudo ./mine-regtest-coins.sh
  sudo ./mine-regtest-coins.sh --coin blc --blocks 2000
  sudo ./mine-regtest-coins.sh --work-dir ./chainrollback-regtest-test --ensure-utxos 5

Options:
  --coin COIN          Add one coin: blc, pho, bbtc, elt, lit, umo
  --coins LIST         Comma or space separated coin list
  --all                Mine all six coins
  --blocks N           Blocks to mine when mining is needed
  --ensure-utxos N     Only mine coins with fewer than N spendable UTXOs
  --work-dir DIR       Shared regtest work folder
  --reset              Remove existing rollback-smoke containers and datadirs first

The script only uses rollback-smoke regtest containers. It refuses to touch an
existing container with the same name unless that container is labeled as test
data. Logs and summaries are written in the directory where the script is run
and copied into the selected work folder.

Interactive terminal runs ask how many regtest blocks to mine per selected coin.
Scripted callers should pass --blocks. Set MPOS_REGTEST_PROMPT_BLOCKS=0 only
for a direct terminal run that must use the default without asking.

Images default to ${MPOS_DOCKER_HUB}/<coin>:${MPOS_IMAGE_TAG}. Per-coin image
overrides use MPOS_REGTEST_IMAGE_BLC, MPOS_REGTEST_IMAGE_PHO, etc. If no image
override is set, the tool can detect the image from an existing live container
named by MPOS_CONTAINER_BLC or MPOS_DAEMON_CONTAINER_BLC. Regtest containers are
separate and use MPOS_REGTEST_CONTAINER_PREFIX, default mpos-regtest-.
EOF
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

is_known_coin() {
  local candidate="$1" coin
  for coin in "${COINS[@]}"; do
    [ "$candidate" = "$coin" ] && return 0
  done
  return 1
}

add_coin() {
  local coin="$1" existing
  coin="${coin,,}"
  coin="${coin//[[:space:]]/}"
  [ -n "$coin" ] || return 0
  is_known_coin "$coin" || die "unknown coin: ${coin}"
  for existing in "${SELECTED[@]}"; do
    [ "$existing" = "$coin" ] && return 0
  done
  SELECTED+=("$coin")
}

add_coin_list() {
  local raw="$1" item
  raw="${raw//,/ }"
  for item in $raw; do
    add_coin "$item"
  done
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --coin) add_coin "$2"; shift 2 ;;
    --coins) add_coin_list "$2"; shift 2 ;;
    --all) SELECTED=("${COINS[@]}"); shift ;;
    --blocks) BLOCKS="$2"; BLOCKS_FROM_ARG=1; shift 2 ;;
    --ensure-utxos) ENSURE_UTXOS="$2"; shift 2 ;;
    --work-dir) WORK_DIR="$2"; shift 2 ;;
    --reset) RESET=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

if [ "${#SELECTED[@]}" -eq 0 ]; then
  SELECTED=("${COINS[@]}")
fi

[[ "$ENSURE_UTXOS" =~ ^[0-9]+$ ]] || die "--ensure-utxos must be zero or a positive integer"

should_prompt_blocks() {
  [ "${MPOS_REGTEST_PROMPT_BLOCKS:-1}" != "0" ] || return 1
  [ "$BLOCKS_FROM_ARG" = "0" ] || return 1
  [ -t 0 ] || return 1
  [ -t 1 ] || return 1
  return 0
}

prompt_blocks() {
  local answer
  should_prompt_blocks || return 0
  printf '\nHow many regtest blocks should be mined per selected coin? [%s] ' "$BLOCKS"
  read -r answer
  answer="${answer//[[:space:]]/}"
  [ -n "$answer" ] || return 0
  BLOCKS="$answer"
}

validate_numeric_settings() {
  [[ "$BLOCKS" =~ ^[0-9]+$ ]] && [ "$BLOCKS" -gt 0 ] || die "block count must be a positive integer"
  [[ "$ENSURE_UTXOS" =~ ^[0-9]+$ ]] || die "--ensure-utxos must be zero or a positive integer"
}

latest_regtest_work_dir() {
  local latest=""
  shopt -s nullglob
  local candidates=("${RUN_DIR}"/chainrollback-regtest-*)
  shopt -u nullglob
  if [ "${#candidates[@]}" -gt 0 ]; then
    latest="$(ls -dt -- "${candidates[@]}" 2>/dev/null | head -n 1 || true)"
  fi
  printf '%s\n' "$latest"
}

operator_owner_spec() {
  if [ -n "${SUDO_UID:-}" ] && [ -n "${SUDO_GID:-}" ] && [ "${SUDO_UID}" != "0" ]; then
    printf '%s:%s\n' "$SUDO_UID" "$SUDO_GID"
    return 0
  fi
  return 1
}

protect_operator_path() {
  local path="$1" owner=""
  [ -e "$path" ] || return 0
  if [ -d "$path" ]; then
    find "$path" -type d -exec chmod 755 {} +
    find "$path" -type f -exec chmod 600 {} +
  else
    chmod 600 "$path"
  fi
  if owner="$(operator_owner_spec)"; then
    chown -R "$owner" "$path" || warn "could not chown ${path} to sudo user ${owner}"
  fi
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

configured_live_container_name() {
  local coin="$1" upper value
  upper="$(coin_upper "$coin")"
  value="$(env_value "MPOS_CONTAINER_${upper}")"
  [ -n "$value" ] || value="$(env_value "MPOS_DAEMON_CONTAINER_${upper}")"
  [ -n "$value" ] || value="$coin"
  printf '%s' "$value"
}

docker_exists() {
  docker ps -a --format '{{.Names}}' | grep -qx "$1"
}

docker_running() {
  docker ps --format '{{.Names}}' | grep -qx "$1"
}

container_label() {
  local container="$1" label="$2"
  docker inspect -f "{{ index .Config.Labels \"${label}\" }}" "$container" 2>/dev/null || true
}

is_smoke_container() {
  [ "$(container_label "$1" blakestream.rollback-smoke)" = "1" ]
}

image_from_container() {
  local container="$1"
  [ -n "$container" ] || return 1
  docker_exists "$container" || return 1
  is_smoke_container "$container" && return 1
  docker inspect -f '{{.Config.Image}}' "$container" 2>/dev/null
}

detect_image_by_live_container() {
  local coin="$1" container image repo_tag name image_name
  container="$(configured_live_container_name "$coin")"
  if image="$(image_from_container "$container")" && [ -n "$image" ]; then
    printf '%s' "$image"
    return 0
  fi

  image_name="${COIN_IMAGE_NAME[$coin]}"
  while IFS= read -r repo_tag; do
    name="${repo_tag%%$'\t'*}"
    image="${repo_tag#*$'\t'}"
    [ "$name" != "$image" ] || continue
    [ "$image" != "<no image>" ] || continue
    case "$image" in
      "$image_name:"*|*/"$image_name:"*)
        if ! is_smoke_container "$name"; then
          printf '%s' "$image"
          return 0
        fi
        ;;
    esac
  done < <(docker ps -a --format '{{.Names}}\t{{.Image}}')
  return 1
}

coin_image() {
  local coin="$1" upper image
  upper="$(coin_upper "$coin")"
  image="$(env_value "MPOS_REGTEST_IMAGE_${upper}")"
  [ -n "$image" ] || image="$(env_value "MPOS_DAEMON_IMAGE_${upper}")"
  [ -n "$image" ] || image="$(env_value "MPOS_IMAGE_${upper}")"
  if [ -z "$image" ]; then
    image="$(detect_image_by_live_container "$coin" || true)"
  fi
  [ -n "$image" ] || image="${MPOS_DOCKER_HUB}/${COIN_IMAGE_NAME[$coin]}:${MPOS_IMAGE_TAG}"
  printf '%s' "$image"
}

remove_smoke_container() {
  local coin="$1" container
  container="$(regtest_container_name "$coin")"
  if docker_exists "$container"; then
    is_smoke_container "$container" || die "container ${container} already exists and is not rollback-smoke test data"
    docker rm -f "$container" >/dev/null
  fi
}

write_config() {
  local coin="$1" hostdir="$2"
  mkdir -p "$hostdir"
  cat > "${hostdir}/${CONFIG_FILE[$coin]}" <<EOF
regtest=1
server=1
txindex=1
listen=0
dnsseed=0
discover=0
fallbackfee=0.00010000
rpcuser=rollback
rpcpassword=rollback
EOF
}

start_container() {
  local coin="$1" hostdir="$2" current_mount container image
  container="$(regtest_container_name "$coin")"
  image="$(coin_image "$coin")"
  say "${coin}: checking regtest container"
  if docker_running "$container"; then
    is_smoke_container "$container" || die "container ${container} is running and is not rollback-smoke test data"
    current_mount="$(docker inspect -f "{{range .Mounts}}{{if eq .Destination \"/root/${CONFIG_DIR[$coin]}\"}}{{.Source}}{{end}}{{end}}" "$container" 2>/dev/null || true)"
    if [ "$current_mount" = "$hostdir" ]; then
      say "${coin}: using existing rollback-smoke container ${container}"
      return 0
    fi
    say "${coin}: existing smoke container uses a different fixture; recreating"
    remove_smoke_container "$coin"
  fi
  remove_smoke_container "$coin"
  write_config "$coin" "$hostdir"
  say "${coin}: starting ${container} from ${image}"
  docker run -d --rm --name "$container" --user 0:0 \
    --label blakestream.rollback-smoke=1 \
    --label "blakestream.rollback-smoke.coin=${coin}" \
    -v "${hostdir}:/root/${CONFIG_DIR[$coin]}" \
    --entrypoint "/usr/local/bin/${DAEMON_NAME[$coin]}" \
    "${image}" \
    "-datadir=/root/${CONFIG_DIR[$coin]}" -regtest -printtoconsole -server=1 \
    -rpcuser=rollback -rpcpassword=rollback -rpcallowip=127.0.0.1 \
    -fallbackfee=0.00010000 -txindex=1 -listen=0 -dnsseed=0 -discover=0 \
    > "${WORK_DIR}/logs/${coin}.container-id"
}

rpc() {
  local coin="$1" container
  shift
  container="$(regtest_container_name "$coin")"
  docker exec "$container" "/usr/local/bin/${CLI_NAME[$coin]}" "-datadir=/root/${CONFIG_DIR[$coin]}" "$@" | tr -d '\r'
}

wallet_rpc() {
  local coin="$1" container
  shift
  container="$(regtest_container_name "$coin")"
  docker exec "$container" "/usr/local/bin/${CLI_NAME[$coin]}" "-datadir=/root/${CONFIG_DIR[$coin]}" -rpcwallet=rollback "$@" | tr -d '\r'
}

wait_rpc() {
  local coin="$1" attempt
  say "${coin}: waiting for RPC"
  for attempt in $(seq 1 120); do
    if rpc "$coin" getblockcount >/dev/null 2>&1; then
      say "${coin}: RPC ready at height $(rpc "$coin" getblockcount)"
      return 0
    fi
    if [ $((attempt % 10)) -eq 0 ]; then
      say "${coin}: still waiting for RPC after ${attempt}s"
    fi
    sleep 1
  done
  docker logs --tail 120 "$(regtest_container_name "$coin")" > "${WORK_DIR}/logs/${coin}-rpc-failure.log" 2>&1 || true
  die "${coin} RPC did not become ready; see ${WORK_DIR}/logs/${coin}-rpc-failure.log"
}

mining_address() {
  local coin="$1" addr
  ensure_test_wallet_loaded "$coin"
  if addr="$(wallet_rpc "$coin" getnewaddress 2>/dev/null)"; then
    printf '%s\n' "$addr"
    return 0
  fi
  return 1
}

ensure_test_wallet_loaded() {
  local coin="$1"
  if wallet_rpc "$coin" getwalletinfo >/dev/null 2>&1; then
    return 0
  fi
  rpc "$coin" loadwallet rollback >/dev/null 2>&1 || rpc "$coin" createwallet rollback >/dev/null
  wallet_rpc "$coin" getwalletinfo >/dev/null 2>&1
}

spendable_utxos() {
  local coin="$1"
  ensure_test_wallet_loaded "$coin"
  wallet_rpc "$coin" listunspent 0 9999999 | jq '[.[] | select((.spendable // true) == true and (.safe // true) != false)] | length'
}

mine_coin_if_needed() {
  local coin="$1" hostdir="$2" before_height after_height before_utxos after_utxos mine_now=0 addr item
  printf '\n'
  say "${coin}: checking shared regtest fixture"
  start_container "$coin" "$hostdir"
  wait_rpc "$coin"
  before_height="$(rpc "$coin" getblockcount)"
  before_utxos="$(spendable_utxos "$coin")"
  say "${coin}: current height=${before_height}, spendable UTXOs=${before_utxos}"

  if [ "$ENSURE_UTXOS" -gt 0 ]; then
    [ "$before_utxos" -lt "$ENSURE_UTXOS" ] && mine_now=1
  else
    mine_now=1
  fi

  if [ "$mine_now" = "1" ]; then
    addr="$(mining_address "$coin")" || die "failed to get mining address for ${coin}"
    say "mining ${BLOCKS} ${coin} regtest blocks from height ${before_height}"
    rpc "$coin" generatetoaddress "$BLOCKS" "$addr" > "${WORK_DIR}/logs/${coin}-generated-${STAMP}.txt"
  else
    say "${coin}: spendable UTXOs ${before_utxos} >= ${ENSURE_UTXOS}; no mining needed"
  fi

  after_height="$(rpc "$coin" getblockcount)"
  after_utxos="$(spendable_utxos "$coin")"
  ok "${coin}: height ${before_height} -> ${after_height}, spendable UTXOs ${before_utxos} -> ${after_utxos}"
  printf '%s before_height=%s after_height=%s before_utxos=%s after_utxos=%s mined=%s\n' \
    "$coin" "$before_height" "$after_height" "$before_utxos" "$after_utxos" "$mine_now" | tee -a "$RUN_LOG"
  item="$(jq -nc \
    --arg coin "$coin" \
    --arg label "${COIN_LABEL[$coin]}" \
    --argjson before_height "$before_height" \
    --argjson after_height "$after_height" \
    --argjson before_utxos "$before_utxos" \
    --argjson after_utxos "$after_utxos" \
    --argjson mined "$mine_now" \
    '{coin:$coin,label:$label,before_height:$before_height,after_height:$after_height,before_utxos:$before_utxos,after_utxos:$after_utxos,mined:($mined == 1)}')"
  SUMMARY_JSON="$(jq -c --argjson item "$item" '. + [$item]' <<<"$SUMMARY_JSON")"
}

main() {
  [ "$(id -u)" = "0" ] || die "run as root"

  clear_tool_screen || true
  print_tool_banner
  say "REGTEST MINING FIXTURE"
  prompt_blocks
  validate_numeric_settings
  need_cmd docker
  need_cmd jq

  if [ -z "$WORK_DIR" ]; then
    WORK_DIR="$(latest_regtest_work_dir)"
    if [ -z "$WORK_DIR" ]; then
      WORK_DIR="${RUN_DIR}/chainrollback-regtest-${STAMP}"
    fi
  fi
  WORK_DIR="$(mkdir -p "$WORK_DIR" && cd "$WORK_DIR" && pwd -P)"
  RUN_LOG="${WORK_DIR}/logs/mine-regtest-coins-${STAMP}.log"
  RUN_JSON="${RUN_DIR}/mine-regtest-coins-${STAMP}.json"
  mkdir -p "${WORK_DIR}/datadirs" "${WORK_DIR}/logs"
  : > "$RUN_LOG"
  SUMMARY_JSON='[]'

  say "work folder: ${WORK_DIR}"
  say "selected coins: ${SELECTED[*]}"
  say "blocks per mined coin: ${BLOCKS}"

  if $RESET; then
    say "resetting selected rollback-smoke containers and datadirs"
    for coin in "${SELECTED[@]}"; do
      remove_smoke_container "$coin"
      rm -rf "${WORK_DIR}/datadirs/${coin}"
    done
  fi

  for coin in "${SELECTED[@]}"; do
    mine_coin_if_needed "$coin" "${WORK_DIR}/datadirs/${coin}"
  done

  jq -n \
    --arg schema "blakestream-regtest-mining-v1" \
    --arg created_utc "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg work_dir "$WORK_DIR" \
    --argjson blocks "$BLOCKS" \
    --argjson ensure_utxos "$ENSURE_UTXOS" \
    --argjson coins "$SUMMARY_JSON" \
    '{schema:$schema,created_utc:$created_utc,work_dir:$work_dir,blocks:$blocks,ensure_utxos:$ensure_utxos,coins:$coins}' \
    > "$RUN_JSON"
  cp -p "$RUN_JSON" "${WORK_DIR}/"
  protect_operator_path "$WORK_DIR"
  protect_operator_path "$RUN_LOG"
  protect_operator_path "$RUN_JSON"
  ok "regtest mining fixture ready: ${WORK_DIR}"
  ok "run log: ${RUN_LOG}"
}

main
