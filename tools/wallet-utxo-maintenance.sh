#!/usr/bin/env bash
set -euo pipefail

# BlakeStream MPOS wallet UTXO maintenance helper.
#
# This tool is for pool operators running the 25.2 mainnet Docker daemon stack.
# It checks wallet fragmentation, prepares payout-address rotations, and can
# consolidate many wallet UTXOs into fewer outputs. Any operation that creates a
# replacement payout address or moves funds writes a root-only wallet backup,
# wallet key dump, and the replacement address private key before continuing.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [ -r "${SCRIPT_DIR}/lib/tool-banner.sh" ]; then
  # shellcheck disable=SC1091
  . "${SCRIPT_DIR}/lib/tool-banner.sh"
fi
REGTEST_MINER_SCRIPT="${SCRIPT_DIR}/mine-regtest-coins.sh"

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

COINS=(blc pho bbtc elt lit umo)

declare -A COIN_NAME=(
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
declare -A DATADIR=(
  [blc]="/root/.blakecoin"
  [pho]="/root/.photon"
  [bbtc]="/root/.blakebitcoin"
  [elt]="/root/.electron"
  [lit]="/root/.lithium"
  [umo]="/root/.universalmolecule"
)
declare -A ADDRESS_TYPE=(
  [blc]="bech32"
  [pho]="bech32"
  [bbtc]="bech32"
  [elt]="bech32"
  [lit]="bech32"
  [umo]="bech32"
)

MODE="regtest"
ACTION="status"
COIN_SELECT="all"
COIN_SELECT_EXPLICIT=0
FROM_ADDRESS=""
OLD_ADDRESS=""
TARGET_ADDRESS=""
BATCH_SIZE="${MPOS_UTXO_BATCH_SIZE:-100}"
MIN_CONFIRMS="${MPOS_UTXO_MIN_CONFIRMS:-6}"
MIN_AMOUNT="${MPOS_UTXO_MAX_INPUT_AMOUNT:-0}"
FEE_RATE="${MPOS_UTXO_FEE_RATE:-0.0001}"
MAX_MEMPOOL="${MPOS_UTXO_MAX_MEMPOOL:-6}"
MEMPOOL_RESUME="${MPOS_UTXO_MEMPOOL_RESUME:-2}"
POLL_INTERVAL="${MPOS_UTXO_POLL_INTERVAL:-30}"
KEY_DUMP_BASE="${MPOS_WALLET_KEY_DUMP_DIR:-/root/blakestream-wallet-key-dumps}"
SEND=false
ASSUME_YES=false
UTXO_REGTEST_RUN_DIR=""
REGTEST_BOOTSTRAP_BLOCKS="${MPOS_REGTEST_BOOTSTRAP_BLOCKS:-2000}"
REGTEST_MIN_UTXOS="${MPOS_REGTEST_MIN_UTXOS:-5}"
MPOS_REGTEST_CONTAINER_PREFIX="${MPOS_REGTEST_CONTAINER_PREFIX:-mpos-regtest-}"

# These thresholds are intentionally conservative. WARN means schedule
# consolidation; BAD means wallet sends may fail or become slow enough to affect
# payout operations. The same model can drive a dashboard UTXO health chip:
# green for OK, orange for WARN, red for BAD, with the chip using the worst coin.
WARN_UTXO_COUNT="${MPOS_UTXO_WARN_COUNT:-400}"
BAD_UTXO_COUNT="${MPOS_UTXO_BAD_COUNT:-800}"
SMALL_AMOUNT="${MPOS_UTXO_SMALL_AMOUNT:-0.0001}"
SMALL_WARN_COUNT="${MPOS_UTXO_SMALL_WARN_COUNT:-100}"
SMALL_BAD_COUNT="${MPOS_UTXO_SMALL_BAD_COUNT:-200}"

red=$'\033[0;31m'
green=$'\033[0;32m'
yellow=$'\033[1;33m'
blue=$'\033[0;34m'
cyan=$'\033[0;36m'
nc=$'\033[0m'

say() { printf '%s[INFO]%s %s\n' "$blue" "$nc" "$*"; }
ok() { printf '%s[OK]%s %s\n' "$green" "$nc" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$yellow" "$nc" "$*" >&2; }
die() { printf '%s[ERROR]%s %s\n' "$red" "$nc" "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage:
  wallet-utxo-maintenance.sh [OPTIONS]
  wallet-utxo-maintenance.sh --main ACTION [OPTIONS]

Actions:
  default       Run a disposable/regtest UTXO consolidation smoke test.
  status        Show UTXO health for one coin or all coins.
  dump-keys     Create a new receive address and dump wallet/key material.
  rotate        Prepare a new pool payout address; does not edit pool config.
  consolidate   Merge many UTXOs into larger outputs. Dry-run unless --send.

Common options:
  --main                   Enable live pool wallet mode.
  --coin COIN              blc, pho, bbtc, elt, lit, umo, or comma list
  --all                    Run against all six coins
  --old-address ADDR       Current pool payout address; key is dumped if owned
  --key-dir DIR            Root-only output base for key material

Consolidation options:
  --from-address ADDR      Only spend UTXOs from this address
  --to-address ADDR        Consolidation target; must be wallet-owned
  --batch-size N           Inputs per transaction (default: 100)
  --min-confirms N         Minimum confirmations (default: 6)
  --min-amount N           Only include UTXOs <= N coins (default: all)
  --fee-rate N             Fee per KB in coins (default: 0.0001)
  --max-mempool N          Pause when mempool reaches N txs (default: 6)
  --mempool-resume N       Resume when mempool drains to N txs (default: 2)
  --poll-interval N        Seconds between mempool checks (default: 30)
  --send                   Broadcast consolidation transactions
  --yes                    Skip interactive confirmation

Health thresholds:
  MPOS_UTXO_WARN_COUNT=400
  MPOS_UTXO_BAD_COUNT=800
  MPOS_UTXO_SMALL_AMOUNT=0.0001
  MPOS_UTXO_SMALL_WARN_COUNT=100
  MPOS_UTXO_SMALL_BAD_COUNT=200

Examples:
  sudo tools/wallet-utxo-maintenance.sh
  sudo tools/wallet-utxo-maintenance.sh --main status --all
  sudo tools/wallet-utxo-maintenance.sh --main rotate --coin blc --old-address B...
  sudo tools/wallet-utxo-maintenance.sh --main consolidate --coin blc --dry-run
  sudo tools/wallet-utxo-maintenance.sh --main consolidate --coin blc --send --batch-size 75

The default smoke test auto-starts or tops up the shared regtest fixture with
tools/mine-regtest-coins.sh when test containers are missing or too low on
spendable UTXOs. Set MPOS_REGTEST_WORK_DIR to force a specific fixture folder.

Private keys are never printed to stdout. They are written under:
  /root/blakestream-wallet-key-dumps/
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --main) MODE="main"; shift ;;
    status|dump-keys|rotate|consolidate) ACTION="$1"; shift ;;
    --coin) COIN_SELECT="$2"; COIN_SELECT_EXPLICIT=1; shift 2 ;;
    --all) COIN_SELECT="all"; COIN_SELECT_EXPLICIT=1; shift ;;
    --old-address) OLD_ADDRESS="$2"; shift 2 ;;
    --from-address) FROM_ADDRESS="$2"; shift 2 ;;
    --to-address) TARGET_ADDRESS="$2"; shift 2 ;;
    --batch-size) BATCH_SIZE="$2"; shift 2 ;;
    --min-confirms) MIN_CONFIRMS="$2"; shift 2 ;;
    --min-amount) MIN_AMOUNT="$2"; shift 2 ;;
    --fee-rate) FEE_RATE="$2"; shift 2 ;;
    --max-mempool) MAX_MEMPOOL="$2"; shift 2 ;;
    --mempool-resume) MEMPOOL_RESUME="$2"; shift 2 ;;
    --poll-interval) POLL_INTERVAL="$2"; shift 2 ;;
    --key-dir) KEY_DUMP_BASE="$2"; shift 2 ;;
    --send) SEND=true; shift ;;
    --dry-run) SEND=false; shift ;;
    --yes) ASSUME_YES=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

require_deps() {
  need_cmd docker
  need_cmd jq
  if [[ "$ACTION" == "consolidate" ]]; then
    need_cmd bc
  fi
}

is_known_coin() {
  local coin="$1"
  for c in "${COINS[@]}"; do
    [[ "$c" == "$coin" ]] && return 0
  done
  return 1
}

selected_coins() {
  local c
  if [[ "$COIN_SELECT" == "all" ]]; then
    printf '%s\n' "${COINS[@]}"
    return
  fi
  IFS=',' read -ra parts <<<"$COIN_SELECT"
  for c in "${parts[@]}"; do
    c="${c//[[:space:]]/}"
    is_known_coin "$c" || die "Unknown coin: $c"
    printf '%s\n' "$c"
  done
}

read_user_line() {
  local var_name="$1"
  if [ -t 0 ] && [ -r /dev/tty ]; then
    IFS= read -r "$var_name" < /dev/tty
  else
    IFS= read -r "$var_name"
  fi
}

require_root_for_key_ops() {
  if [[ "$ACTION" != "status" && "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "Run ${ACTION} with sudo/root so key dumps are written root-only."
  fi
}

operator_owner_spec() {
  if [[ -n "${SUDO_UID:-}" && -n "${SUDO_GID:-}" && "${SUDO_UID}" != "0" ]]; then
    printf '%s:%s\n' "$SUDO_UID" "$SUDO_GID"
    return 0
  fi
  return 1
}

make_operator_readable_dir() {
  local path="$1" owner=""
  [[ -d "$path" ]] || return 0
  chmod 750 "$path"
  if owner="$(operator_owner_spec)"; then
    chown "$owner" "$path" || warn "could not chown ${path} to sudo user ${owner}"
  fi
}

make_operator_readable_tree() {
  local path="$1" owner=""
  [[ -d "$path" ]] || return 0
  find "$path" -type d -exec chmod 750 {} +
  find "$path" -type f -exec chmod 600 {} +
  if owner="$(operator_owner_spec)"; then
    chown -R "$owner" "$path" || warn "could not chown ${path} to sudo user ${owner}"
  fi
}

cleanup_regtest_permissions() {
  [[ -n "$UTXO_REGTEST_RUN_DIR" ]] || return 0
  make_operator_readable_tree "$UTXO_REGTEST_RUN_DIR" >/dev/null 2>&1 || true
}

docker_running() {
  docker ps --format '{{.Names}}' | grep -qx "$1"
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
  [[ -n "$value" ]] || value="$(env_value "MPOS_DAEMON_CONTAINER_${upper}")"
  [[ -n "$value" ]] || value="$coin"
  printf '%s' "$value"
}

coin_container_name() {
  if [[ "$MODE" == "regtest" ]]; then
    regtest_container_name "$1"
  else
    live_container_name "$1"
  fi
}

container_label() {
  local container="$1" label="$2"
  docker inspect -f "{{ index .Config.Labels \"${label}\" }}" "$container" 2>/dev/null || true
}

is_rollback_smoke_container() {
  [[ "$(container_label "$1" blakestream.rollback-smoke)" == "1" ]]
}

require_regtest_container() {
  local coin="$1" container
  container="$(regtest_container_name "$coin")"
  docker_running "$container" || die "Regtest container is not running: ${container}"
  is_rollback_smoke_container "$container" || die "${container} is not a rollback-smoke regtest container; use --main only for live pool wallets"
}

refuse_regtest_container_in_main() {
  local coin="$1" container
  container="$(live_container_name "$coin")"
  if docker_running "$container" && is_rollback_smoke_container "$container"; then
    die "${container} is a rollback-smoke regtest container. Refusing live --main wallet maintenance on test data."
  fi
}

guard_main_containers() {
  local coin
  while IFS= read -r coin; do
    refuse_regtest_container_in_main "$coin"
  done < <(selected_coins)
}

rpc() {
  local coin="$1" container; shift
  container="$(coin_container_name "$coin")"
  docker_running "$container" || die "Container is not running: $container"
  [[ "$MODE" != "main" ]] || refuse_regtest_container_in_main "$coin"
  docker exec "$container" "${CLI_NAME[$coin]}" -datadir="${DATADIR[$coin]}" "$@"
}

try_rpc() {
  local coin="$1" container; shift
  container="$(coin_container_name "$coin")"
  docker_running "$container" || return 1
  [[ "$MODE" != "main" ]] || refuse_regtest_container_in_main "$coin"
  docker exec "$container" "${CLI_NAME[$coin]}" -datadir="${DATADIR[$coin]}" "$@" 2>/dev/null
}

coin_label() {
  printf '%s' "${COIN_NAME[$1]}"
}

list_utxos() {
  local coin="$1"
  local utxos
  if [[ -n "$FROM_ADDRESS" ]]; then
    utxos=$(rpc "$coin" listunspent "$MIN_CONFIRMS" 9999999 "[\"$FROM_ADDRESS\"]")
  else
    utxos=$(rpc "$coin" listunspent "$MIN_CONFIRMS" 9999999)
  fi
  utxos=$(jq '[.[] | select((.spendable // true) == true and (.safe // true) != false)]' <<<"$utxos")
  if [[ "$MIN_AMOUNT" != "0" ]]; then
    utxos=$(jq --argjson max "$MIN_AMOUNT" '[.[] | select(.amount <= $max)]' <<<"$utxos")
  fi
  printf '%s\n' "$utxos"
}

state_rank() {
  case "$1" in
    BAD) printf '2' ;;
    WARN) printf '1' ;;
    *) printf '0' ;;
  esac
}

state_from_utxos() {
  local count="$1" small_count="$2"
  if [[ "$count" -ge "$BAD_UTXO_COUNT" || "$small_count" -ge "$SMALL_BAD_COUNT" ]]; then
    printf 'BAD'
  elif [[ "$count" -ge "$WARN_UTXO_COUNT" || "$small_count" -ge "$SMALL_WARN_COUNT" ]]; then
    printf 'WARN'
  else
    printf 'OK'
  fi
}

amount8() {
  local value
  value="$(echo "scale=8; ($1) / 1" | bc)"
  [[ "$value" == .* ]] && value="0${value}"
  [[ "$value" == -.* ]] && value="-0${value#-}"
  printf '%s\n' "$value"
}

status_coin() {
  local coin="$1" container utxos count total small_count small_total avg max_addr state label
  label="$(coin_label "$coin")"
  container="$(coin_container_name "$coin")"
  if ! docker_running "$container"; then
    printf '%-5s %-18s %-5s %10s %18s %10s %9s %18s\n' \
      "$coin" "$label" "BAD" "-" "-" "-" "-" "container down"
    return
  fi

  utxos=$(list_utxos "$coin")
  count=$(jq 'length' <<<"$utxos")
  total=$(jq -r '[.[].amount] | add // 0' <<<"$utxos")
  small_count=$(jq --argjson t "$SMALL_AMOUNT" '[.[] | select(.amount <= $t)] | length' <<<"$utxos")
  small_total=$(jq --argjson t "$SMALL_AMOUNT" -r '[.[] | select(.amount <= $t) | .amount] | add // 0' <<<"$utxos")
  avg=$(jq -r 'if length > 0 then (([.[].amount] | add) / length) else 0 end' <<<"$utxos")
  max_addr=$(jq -r 'if length > 0 then (sort_by(.address) | group_by(.address) | map(length) | max) else 0 end' <<<"$utxos")
  state=$(state_from_utxos "$count" "$small_count")

  printf '%-5s %-18s %-5s %10s %18s %10s %9s %18s\n' \
    "$coin" "$label" "$state" "$count" "$total" "$small_count" "$max_addr" "avg=${avg} small=${small_total}"
}

status_coin_fields() {
  local coin="$1" line id wallet state utxos balance small maxaddr detail
  if line="$(status_coin "$coin")"; then
    read -r id wallet state utxos balance small maxaddr detail <<<"$line"
  else
    id="$coin"
    wallet="$(coin_label "$coin")"
    state="BAD"
    utxos="-"
    balance="-"
    small="-"
    maxaddr="-"
    detail="status unavailable"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$wallet" "$state" "$utxos" "$balance" "$small" "$maxaddr" "$detail"
}

print_wallet_selection_intro() {
  if [[ "$MODE" == "main" ]]; then
    say "LIVE WALLET MAINTENANCE MODE" >&2
    say "Use --main only for live pool wallet inspection or consolidation." >&2
  else
    say "REGTEST UTXO CONSOLIDATION TEST MODE" >&2
    say "This default run only uses rollback-smoke regtest containers." >&2
    say "For live/mainnet wallets, run with --main." >&2
  fi
}

interactive_coin_selection() {
  local title="${1:-wallet maintenance}" raw coin index item notice
  local id wallet state utxos balance small maxaddr detail mark
  local -A selected=()
  notice=""

  while :; do
    clear_tool_screen || true
    print_tool_banner force >&2
    print_wallet_selection_intro
    printf '\nSelect coin(s) for %s:\n' "$title" >&2
    printf '     %-3s %-5s %-18s %-5s %10s %18s %10s %8s\n' \
      "SEL" "COIN" "WALLET" "STATE" "UTXOS" "BALANCE" "SMALL" "MAXADDR" >&2
    index=1
    for coin in "${COINS[@]}"; do
      IFS=$'\t' read -r id wallet state utxos balance small maxaddr detail < <(status_coin_fields "$coin")
      mark=" "
      [[ "${selected[$coin]:-0}" == "1" ]] && mark="*"
      printf '  %d) [%s] %-5s %-18s %-5s %10s %18s %10s %8s\n' \
        "$index" "$mark" "$id" "$wallet" "$state" "$utxos" "$balance" "$small" "$maxaddr" >&2
      index=$((index + 1))
    done
    printf '  0) toggle all\n' >&2
    if [[ -n "$notice" ]]; then
      warn "$notice"
      notice=""
    fi
    printf 'Type a number and press Enter to toggle, 0 for all, or press Enter when done: ' >&2
    read_user_line raw
    if [[ -z "$raw" ]]; then
      item=0
      for coin in "${COINS[@]}"; do
        [[ "${selected[$coin]:-0}" == "1" ]] && { printf '%s\n' "$coin"; item=1; }
      done
      [[ "$item" == "1" ]] && return
      notice="select at least one coin"
      continue
    fi

    if [[ "$raw" == "0" || "${raw,,}" == "all" ]]; then
      item=0
      for coin in "${COINS[@]}"; do
        [[ "${selected[$coin]:-0}" != "1" ]] && item=1
      done
      for coin in "${COINS[@]}"; do
        selected[$coin]="$item"
      done
      continue
    fi

    if [[ "$raw" =~ ^[1-6]$ ]]; then
      index=$((raw - 1))
      coin="${COINS[$index]}"
      if [[ "${selected[$coin]:-0}" == "1" ]]; then
        selected[$coin]=0
      else
        selected[$coin]=1
      fi
      continue
    fi

    notice="enter a number from 0 to 6"
  done
}

select_coins_for_action() {
  local title="${1:-wallet maintenance}"
  if [[ "$COIN_SELECT_EXPLICIT" == "1" || ! -t 0 ]]; then
    selected_coins
    return
  fi
  interactive_coin_selection "$title"
}

status_all() {
  local coin state line worst="OK"
  printf '%-5s %-18s %-5s %10s %18s %10s %9s %18s\n' \
    "COIN" "WALLET" "STATE" "UTXOS" "BALANCE" "SMALL" "MAXADDR" "DETAIL"
  printf '%-5s %-18s %-5s %10s %18s %10s %9s %18s\n' \
    "-----" "------------------" "-----" "----------" "------------------" "----------" "---------" "------------------"
  while IFS= read -r coin; do
    line=$(status_coin "$coin")
    printf '%s\n' "$line"
    state=$(awk '{print $3}' <<<"$line")
    if [[ "$(state_rank "$state")" -gt "$(state_rank "$worst")" ]]; then
      worst="$state"
    fi
  done < <(selected_coins)
  printf '\nOverall wallet UTXO health: %s\n' "$worst"
}

new_address() {
  local coin="$1" label addr_type addr
  label="pool-rotation-$(date -u +%Y%m%dT%H%M%SZ)"
  addr_type="${ADDRESS_TYPE[$coin]}"
  addr=$(try_rpc "$coin" getnewaddress "$label" "$addr_type" || true)
  if [[ -z "$addr" ]]; then
    addr=$(rpc "$coin" getnewaddress "$label")
  fi
  printf '%s' "$addr"
}

key_output_dir() {
  local coin="$1" action="$2" stamp out
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  out="${KEY_DUMP_BASE}/${stamp}-${coin}-${action}"
  mkdir -p "$out"
  chmod 700 "$KEY_DUMP_BASE" "$out"
  printf '%s' "$out"
}

copy_from_container() {
  local coin="$1" inner="$2" outer="$3" container
  container="$(coin_container_name "$coin")"
  docker cp "${container}:${inner}" "$outer" >/dev/null
  chmod 600 "$outer"
  docker exec "$container" rm -f "$inner" >/dev/null 2>&1 || true
}

dump_wallet_material() {
  local coin="$1" action="$2" new_addr="$3" old_addr="${4:-}"
  local out inner_backup inner_dump new_key old_key manifest stamp descriptors
  local wallet_dump_path new_key_path old_key_path private_desc public_desc
  out="$(key_output_dir "$coin" "$action")"
  stamp="$(basename "$out" | cut -d- -f1)"
  inner_backup="${DATADIR[$coin]}/${coin}-wallet-backup-${stamp}.dat"
  inner_dump="${DATADIR[$coin]}/${coin}-wallet-dump-${stamp}.txt"

  say "writing wallet backup and key dump for ${coin} to ${out}"
  rpc "$coin" backupwallet "$inner_backup" >/dev/null
  copy_from_container "$coin" "$inner_backup" "${out}/${coin}-wallet-backup.dat"

  descriptors="$(try_rpc "$coin" getwalletinfo | jq -r '.descriptors // false')"
  if [[ "$descriptors" == "true" ]]; then
    private_desc="${out}/${coin}-wallet-descriptors-private.json"
    public_desc="${out}/${coin}-wallet-descriptors-public.json"
    if ! try_rpc "$coin" listdescriptors true > "$private_desc"; then
      die "${coin} listdescriptors true failed. Unlock the wallet if it is encrypted; no funds were moved."
    fi
    chmod 600 "$private_desc"
    try_rpc "$coin" listdescriptors false > "$public_desc" || true
    chmod 600 "$public_desc" 2>/dev/null || true
    try_rpc "$coin" getaddressinfo "$new_addr" > "${out}/${coin}-new-address-info.json" || true
    chmod 600 "${out}/${coin}-new-address-info.json" 2>/dev/null || true
    if [[ -n "$old_addr" ]]; then
      try_rpc "$coin" getaddressinfo "$old_addr" > "${out}/${coin}-old-address-info.json" || true
      chmod 600 "${out}/${coin}-old-address-info.json" 2>/dev/null || true
    fi
    wallet_dump_path="$private_desc"
    new_key_path="$private_desc"
    old_key_path="${old_addr:+$private_desc}"
  else
    if ! rpc "$coin" dumpwallet "$inner_dump" >/dev/null 2>&1; then
      die "${coin} dumpwallet failed. Unlock the wallet if it is encrypted; no funds were moved."
    fi
    copy_from_container "$coin" "$inner_dump" "${out}/${coin}-wallet-dump.txt"
    wallet_dump_path="${out}/${coin}-wallet-dump.txt"

    new_key=$(try_rpc "$coin" dumpprivkey "$new_addr" || true)
    if [[ -z "$new_key" ]]; then
      die "${coin} could not dump the replacement address key. Target must be wallet-owned."
    fi
    {
      printf 'coin=%s\n' "$coin"
      printf 'address=%s\n' "$new_addr"
      printf 'private_key=%s\n' "$new_key"
    } > "${out}/${coin}-new-address-privkey.txt"
    chmod 600 "${out}/${coin}-new-address-privkey.txt"
    new_key_path="${out}/${coin}-new-address-privkey.txt"

    if [[ -n "$old_addr" ]]; then
      old_key=$(try_rpc "$coin" dumpprivkey "$old_addr" || true)
      if [[ -z "$old_key" ]]; then
        die "${coin} could not dump old address key for ${old_addr}. Check the address belongs to this wallet."
      fi
      {
        printf 'coin=%s\n' "$coin"
        printf 'address=%s\n' "$old_addr"
        printf 'private_key=%s\n' "$old_key"
      } > "${out}/${coin}-old-address-privkey.txt"
      chmod 600 "${out}/${coin}-old-address-privkey.txt"
      old_key_path="${out}/${coin}-old-address-privkey.txt"
    fi
  fi

  manifest="${out}/manifest.txt"
  {
    printf 'created_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'coin=%s\n' "$coin"
    printf 'coin_name=%s\n' "$(coin_label "$coin")"
    printf 'action=%s\n' "$action"
    printf 'new_address=%s\n' "$new_addr"
    printf 'old_address=%s\n' "${old_addr:-not-supplied}"
    printf 'wallet_descriptors=%s\n' "$descriptors"
    printf 'wallet_backup=%s\n' "${out}/${coin}-wallet-backup.dat"
    printf 'wallet_key_material=%s\n' "$wallet_dump_path"
    printf 'new_address_key_material=%s\n' "$new_key_path"
    if [[ -n "$old_addr" ]]; then
      printf 'old_address_key_material=%s\n' "$old_key_path"
    fi
  } > "$manifest"
  chmod 600 "$manifest"

  ok "key material written under ${out}"
}

confirm_send() {
  local coin="$1"
  if $ASSUME_YES; then
    return
  fi
  printf '%sType CONSOLIDATE-%s to broadcast transactions: %s' "$yellow" "$coin" "$nc"
  local answer
  read -r answer
  [[ "$answer" == "CONSOLIDATE-${coin}" ]] || die "Aborted."
}

get_mempool_count() {
  local coin="$1" raw
  raw=$(try_rpc "$coin" getrawmempool || true)
  if [[ -z "$raw" ]]; then
    printf '0'
  else
    jq 'length' <<<"$raw" 2>/dev/null || printf '0'
  fi
}

wait_for_mempool() {
  local coin="$1" current="$2"
  while [[ "$current" -gt "$MEMPOOL_RESUME" ]]; do
    printf '\r  %s[WAIT]%s %s mempool=%s, waiting for <=%s   ' \
      "$yellow" "$nc" "$coin" "$current" "$MEMPOOL_RESUME" >&2
    sleep "$POLL_INTERVAL"
    current="$(get_mempool_count "$coin")"
  done
  printf '\r%80s\r' '' >&2
}

sign_raw_transaction() {
  local coin="$1" raw="$2" signed
  signed=$(try_rpc "$coin" signrawtransactionwithwallet "$raw" || true)
  if [[ -z "$signed" ]]; then
    signed=$(rpc "$coin" signrawtransaction "$raw")
  fi
  printf '%s' "$signed"
}

plan_consolidation() {
  local coin="$1" utxos="$2" total count batches value est_fee
  count=$(jq 'length' <<<"$utxos")
  value=$(jq -r '[.[].amount] | add // 0' <<<"$utxos")
  batches=$(( (count + BATCH_SIZE - 1) / BATCH_SIZE ))
  est_fee="$(amount8 "(($count * 148 + $batches * 44) / 1000 + $batches) * $FEE_RATE")"
  printf '\n%sConsolidation plan for %s%s\n' "$cyan" "$coin" "$nc"
  printf '  UTXOs:        %s\n' "$count"
  printf '  Value:        %s\n' "$value"
  printf '  Batch size:   %s\n' "$BATCH_SIZE"
  printf '  Batches:      %s\n' "$batches"
  printf '  Est. fees:    ~%s\n' "$est_fee"
  if [[ -n "$FROM_ADDRESS" ]]; then
    printf '  From address: %s\n' "$FROM_ADDRESS"
  fi
  if [[ "$MIN_AMOUNT" != "0" ]]; then
    printf '  Max UTXO:     %s\n' "$MIN_AMOUNT"
  fi
  printf '\n'
}

consolidate_coin() {
  local coin="$1" utxos count target tmp offsets offset slice inputs input_total est_bytes fee output outputs raw signed complete txid done_count failed_count
  say "fetching ${coin} UTXOs"
  utxos=$(list_utxos "$coin" | jq 'sort_by(.amount)')
  count=$(jq 'length' <<<"$utxos")
  if [[ "$count" -le 1 ]]; then
    ok "${coin}: only ${count} matching UTXO(s); nothing to consolidate"
    return
  fi

  plan_consolidation "$coin" "$utxos"

  if ! $SEND; then
    warn "dry-run only; no address was generated, no keys were dumped, and no funds moved"
    return
  fi

  target="$TARGET_ADDRESS"
  if [[ -z "$target" ]]; then
    target="$(new_address "$coin")"
    ok "${coin}: generated consolidation target ${target}"
  else
    ok "${coin}: using supplied wallet-owned target ${target}"
  fi

  dump_wallet_material "$coin" "consolidate" "$target" "${OLD_ADDRESS:-$FROM_ADDRESS}"
  confirm_send "$coin"

  tmp="$(mktemp)"
  trap 'rm -f "${tmp:-}"; trap - RETURN' RETURN
  printf '%s\n' "$utxos" > "$tmp"
  offsets=$(jq --argjson bs "$BATCH_SIZE" -r 'range(0; length; $bs)' "$tmp")
  done_count=0
  failed_count=0

  for offset in $offsets; do
    slice=$(jq -c --argjson off "$offset" --argjson bs "$BATCH_SIZE" '.[$off:$off+$bs]' "$tmp")
    count=$(jq 'length' <<<"$slice")
    [[ "$count" -gt 1 ]] || continue

    if [[ "$MAX_MEMPOOL" -gt 0 ]]; then
      local mp
      mp="$(get_mempool_count "$coin")"
      if [[ "$mp" -ge "$MAX_MEMPOOL" ]]; then
        say "${coin}: mempool at ${mp}; waiting before next batch"
        wait_for_mempool "$coin" "$mp"
      fi
    fi

    inputs=$(jq -c '[.[] | {txid: .txid, vout: .vout}]' <<<"$slice")
    input_total=$(jq -r '[.[].amount] | add' <<<"$slice")
    est_bytes=$(( count * 148 + 34 + 10 ))
    fee="$(amount8 "(($est_bytes / 1000) + 1) * $FEE_RATE")"
    output="$(amount8 "$input_total - $fee")"
    if [[ "$(echo "$output <= 0" | bc)" -eq 1 ]]; then
      warn "${coin}: skipping batch with non-positive output after fee"
      failed_count=$((failed_count + 1))
      continue
    fi

    outputs=$(jq -nc --arg addr "$target" --arg amount "$output" '{($addr): ($amount | tonumber)}')
    raw=$(rpc "$coin" createrawtransaction "$inputs" "$outputs")
    signed=$(sign_raw_transaction "$coin" "$raw")
    complete=$(jq -r '.complete // false' <<<"$signed")
    if [[ "$complete" != "true" ]]; then
      die "${coin}: signing incomplete. Wallet may be locked."
    fi
    txid=$(rpc "$coin" sendrawtransaction "$(jq -r '.hex' <<<"$signed")") || {
      warn "${coin}: sendrawtransaction failed for a batch"
      failed_count=$((failed_count + 1))
      continue
    }
    done_count=$((done_count + 1))
    ok "${coin}: batch ${done_count} sent (${count} inputs -> ${output}, fee ${fee}) txid=${txid}"
  done

  ok "${coin}: consolidation complete, sent=${done_count}, failed=${failed_count}, target=${target}"
}

dump_or_rotate_coin() {
  local coin="$1" action="$2" address
  address="$(new_address "$coin")"
  ok "${coin}: generated replacement payout address ${address}"
  dump_wallet_material "$coin" "$action" "$address" "$OLD_ADDRESS"
  printf '\n%sNext operator step for %s:%s\n' "$cyan" "$coin" "$nc"
  printf '  1. Store the key-dump folder offline.\n'
  printf '  2. Update the pool payout address to: %s\n' "$address"
  printf '  3. Restart the pool only after confirming the address is correct.\n\n'
}

smoke_mining_address() {
  local coin="$1" addr
  if addr="$(try_rpc "$coin" getnewaddress 2>/dev/null)"; then
    printf '%s\n' "$addr"
    return 0
  fi
  return 1
}

smoke_mine_block() {
  local coin="$1" addr
  addr="$(smoke_mining_address "$coin")" || {
    warn "${coin}: could not get mining address; leaving consolidation txs unconfirmed"
    return 0
  }
  try_rpc "$coin" generatetoaddress 1 "$addr" >/dev/null || warn "${coin}: could not mine a confirmation block"
}

ensure_regtest_fixture() {
  local args=() coin
  [ -x "$REGTEST_MINER_SCRIPT" ] || die "missing executable regtest miner helper: ${REGTEST_MINER_SCRIPT}"
  [[ "$REGTEST_BOOTSTRAP_BLOCKS" =~ ^[0-9]+$ ]] && [[ "$REGTEST_BOOTSTRAP_BLOCKS" -gt 0 ]] \
    || die "MPOS_REGTEST_BOOTSTRAP_BLOCKS must be a positive integer"
  [[ "$REGTEST_MIN_UTXOS" =~ ^[0-9]+$ ]] || die "MPOS_REGTEST_MIN_UTXOS must be zero or a positive integer"

  args=(--blocks "$REGTEST_BOOTSTRAP_BLOCKS" --ensure-utxos "$REGTEST_MIN_UTXOS")
  if [[ -n "${MPOS_REGTEST_WORK_DIR:-}" ]]; then
    args+=(--work-dir "$MPOS_REGTEST_WORK_DIR")
  fi
  for coin in "$@"; do
    args+=(--coin "$coin")
  done

  say "checking shared regtest fixture"
  BLAKESTREAM_TOOL_CLEAR=0 BLAKESTREAM_TOOL_BANNER=0 "$REGTEST_MINER_SCRIPT" "${args[@]}"
}

run_regtest_smoke() {
  local stamp run_dir old_key_dir old_send old_yes old_min_conf old_max_mempool old_batch
  local coin before after_send after_confirm failures=0
  local fixture_coins=()

  require_deps
  need_cmd bc
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Run regtest smoke mode with sudo/root so wallet backups and dumps are readable only by root."

  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  run_dir="${MPOS_UTXO_REGTEST_DIR:-${PWD}/wallet-utxo-regtest-${stamp}}"
  UTXO_REGTEST_RUN_DIR="$run_dir"
  trap cleanup_regtest_permissions EXIT
  mkdir -p "$run_dir"
  make_operator_readable_dir "$run_dir"

  say "REGTEST UTXO CONSOLIDATION TEST MODE"
  say "This default run only uses rollback-smoke regtest containers."
  say "For live/mainnet wallets, run with --main."
  say "writing regtest key dumps under ${run_dir}"
  if [[ "$COIN_SELECT_EXPLICIT" == "1" || ! -t 0 ]]; then
    mapfile -t fixture_coins < <(selected_coins)
  else
    fixture_coins=("${COINS[@]}")
  fi
  ensure_regtest_fixture "${fixture_coins[@]}"

  old_key_dir="$KEY_DUMP_BASE"
  old_send="$SEND"
  old_yes="$ASSUME_YES"
  old_min_conf="$MIN_CONFIRMS"
  old_max_mempool="$MAX_MEMPOOL"
  old_batch="$BATCH_SIZE"

  KEY_DUMP_BASE="${run_dir}/key-dumps"
  SEND=true
  ASSUME_YES=true
  MIN_CONFIRMS=0
  MAX_MEMPOOL=0

  while IFS= read -r coin; do
    require_regtest_container "$coin"
    before="$(list_utxos "$coin" | jq 'length')"
    if [[ "$before" -le 1 ]]; then
      warn "${coin}: only ${before} spendable UTXO(s); skipping consolidation smoke for this coin"
      continue
    fi

    say "${coin}: regtest consolidation before=${before} batch_size=${BATCH_SIZE}"
    if consolidate_coin "$coin"; then
      after_send="$(list_utxos "$coin" | jq 'length')"
      smoke_mine_block "$coin"
      after_confirm="$(list_utxos "$coin" | jq 'length')"
      if [[ "$after_send" -lt "$before" ]]; then
        ok "${coin}: regtest consolidation reduced UTXOs ${before} -> ${after_send} before confirmation; confirmed count ${after_confirm}"
      else
        warn "${coin}: UTXO count did not reduce before confirmation (${before} -> ${after_send}; confirmed ${after_confirm})"
        failures=$((failures + 1))
      fi
    else
      warn "${coin}: regtest consolidation failed"
      failures=$((failures + 1))
    fi
  done < <(select_coins_for_action "regtest consolidation")

  KEY_DUMP_BASE="$old_key_dir"
  SEND="$old_send"
  ASSUME_YES="$old_yes"
  MIN_CONFIRMS="$old_min_conf"
  MAX_MEMPOOL="$old_max_mempool"
  BATCH_SIZE="$old_batch"

  [[ "$failures" -eq 0 ]] || die "regtest UTXO consolidation smoke had ${failures} failure(s)"
  make_operator_readable_tree "$run_dir"
  ok "regtest UTXO consolidation smoke passed"
}

main() {
  if [[ "$MODE" != "main" ]]; then
    run_regtest_smoke
    return
  fi

  require_deps
  require_root_for_key_ops
  guard_main_containers

  case "$ACTION" in
    status)
      status_all
      ;;
    dump-keys|rotate)
      while IFS= read -r coin; do
        dump_or_rotate_coin "$coin" "$ACTION"
      done < <(select_coins_for_action "$ACTION")
      ;;
    consolidate)
      while IFS= read -r coin; do
        consolidate_coin "$coin"
      done < <(select_coins_for_action "consolidation")
      ;;
    *)
      die "Unsupported action: $ACTION"
      ;;
  esac
}

main
