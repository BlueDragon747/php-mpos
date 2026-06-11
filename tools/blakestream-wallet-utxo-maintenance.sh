#!/usr/bin/env bash
set -euo pipefail

# BlakeStream MPOS wallet UTXO maintenance helper.
#
# This tool is for pool operators running the 25.2 mainnet Docker daemon stack.
# It checks wallet fragmentation, prepares payout-address rotations, and can
# consolidate many wallet UTXOs into fewer outputs. Any operation that creates a
# replacement payout address or moves funds writes a root-only wallet backup,
# wallet key dump, and the replacement address private key before continuing.

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

ACTION="status"
COIN_SELECT="all"
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
  blakestream-wallet-utxo-maintenance.sh ACTION [OPTIONS]

Actions:
  status        Show UTXO health for one coin or all coins.
  dump-keys     Create a new receive address and dump wallet/key material.
  rotate        Prepare a new pool payout address; does not edit pool config.
  consolidate   Merge many UTXOs into larger outputs. Dry-run unless --send.

Common options:
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
  sudo tools/blakestream-wallet-utxo-maintenance.sh status --all
  sudo tools/blakestream-wallet-utxo-maintenance.sh rotate --coin blc --old-address B...
  sudo tools/blakestream-wallet-utxo-maintenance.sh consolidate --coin blc --dry-run
  sudo tools/blakestream-wallet-utxo-maintenance.sh consolidate --coin blc --send --batch-size 75

Private keys are never printed to stdout. They are written under:
  /root/blakestream-wallet-key-dumps/
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    status|dump-keys|rotate|consolidate) ACTION="$1"; shift ;;
    --coin) COIN_SELECT="$2"; shift 2 ;;
    --all) COIN_SELECT="all"; shift ;;
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

require_root_for_key_ops() {
  if [[ "$ACTION" != "status" && "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "Run ${ACTION} with sudo/root so key dumps are written root-only."
  fi
}

docker_running() {
  docker ps --format '{{.Names}}' | grep -qx "$1"
}

rpc() {
  local coin="$1"; shift
  docker_running "$coin" || die "Container is not running: $coin"
  docker exec "$coin" "${CLI_NAME[$coin]}" -datadir="${DATADIR[$coin]}" "$@"
}

try_rpc() {
  local coin="$1"; shift
  docker_running "$coin" || return 1
  docker exec "$coin" "${CLI_NAME[$coin]}" -datadir="${DATADIR[$coin]}" "$@" 2>/dev/null
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

status_coin() {
  local coin="$1" utxos count total small_count small_total avg max_addr state label
  label="$(coin_label "$coin")"
  if ! docker_running "$coin"; then
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
  local coin="$1" inner="$2" outer="$3"
  docker cp "${coin}:${inner}" "$outer" >/dev/null
  chmod 600 "$outer"
  docker exec "$coin" rm -f "$inner" >/dev/null 2>&1 || true
}

dump_wallet_material() {
  local coin="$1" action="$2" new_addr="$3" old_addr="${4:-}"
  local out inner_backup inner_dump new_key old_key manifest stamp
  out="$(key_output_dir "$coin" "$action")"
  stamp="$(basename "$out" | cut -d- -f1)"
  inner_backup="${DATADIR[$coin]}/${coin}-wallet-backup-${stamp}.dat"
  inner_dump="${DATADIR[$coin]}/${coin}-wallet-dump-${stamp}.txt"

  say "writing wallet backup and key dump for ${coin} to ${out}"
  rpc "$coin" backupwallet "$inner_backup" >/dev/null
  copy_from_container "$coin" "$inner_backup" "${out}/${coin}-wallet-backup.dat"

  if ! rpc "$coin" dumpwallet "$inner_dump" >/dev/null 2>&1; then
    die "${coin} dumpwallet failed. Unlock the wallet if it is encrypted; no funds were moved."
  fi
  copy_from_container "$coin" "$inner_dump" "${out}/${coin}-wallet-dump.txt"

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
  fi

  manifest="${out}/manifest.txt"
  {
    printf 'created_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'coin=%s\n' "$coin"
    printf 'coin_name=%s\n' "$(coin_label "$coin")"
    printf 'action=%s\n' "$action"
    printf 'new_address=%s\n' "$new_addr"
    printf 'old_address=%s\n' "${old_addr:-not-supplied}"
    printf 'wallet_backup=%s\n' "${out}/${coin}-wallet-backup.dat"
    printf 'wallet_dump=%s\n' "${out}/${coin}-wallet-dump.txt"
    printf 'new_address_key=%s\n' "${out}/${coin}-new-address-privkey.txt"
    if [[ -n "$old_addr" ]]; then
      printf 'old_address_key=%s\n' "${out}/${coin}-old-address-privkey.txt"
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
  est_fee=$(echo "scale=8; (($count * 148 + $batches * 44) / 1000 + $batches) * $FEE_RATE" | bc)
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
  trap 'rm -f "$tmp"' RETURN
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
    fee=$(echo "scale=8; (($est_bytes / 1000) + 1) * $FEE_RATE" | bc)
    output=$(echo "scale=8; $input_total - $fee" | bc)
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

main() {
  require_deps
  require_root_for_key_ops

  case "$ACTION" in
    status)
      status_all
      ;;
    dump-keys|rotate)
      while IFS= read -r coin; do
        dump_or_rotate_coin "$coin" "$ACTION"
      done < <(selected_coins)
      ;;
    consolidate)
      while IFS= read -r coin; do
        consolidate_coin "$coin"
      done < <(selected_coins)
      ;;
    *)
      die "Unsupported action: $ACTION"
      ;;
  esac
}

main
