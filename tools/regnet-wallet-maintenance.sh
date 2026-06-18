#!/usr/bin/env bash
set -euo pipefail

# Read the whole script into memory before executing any of it. Bash otherwise
# reads a script incrementally by file offset, so replacing this file while a
# session is open (e.g. a redeploy with the menu running) corrupts parsing and
# fails on the next read. This brace group is closed by the matching '}' on the
# final line; the 'exit' just before it keeps bash from reading past the group.
{

# BlakeStream MPOS pool wallet rotation tool (25.2 mainnet Docker daemon stack).
#
# The pool's operational wallet is the "" (default) wallet on each daemon:
# coinbase lands on a fixed eloipool tracker address that is ismine on "", and
# MPOS pays out through the /wallet/ endpoint = "". So "" carries every coinbase
# and payout forever and its wallet.dat only grows — Bitcoin Core has no compact
# RPC and coin selection is not FIFO, so payouts never drain it in order.
#
# A rotation resets "" to a fresh, small wallet.dat WITHOUT changing the keychain:
#   1. sweep "" 's spendable funds to a temp wallet (this also consolidates them),
#   2. swap the wallet file: unload "", move its wallet.dat aside, create a fresh
#      blank "", and re-import the saved descriptors with a SCOPED rescan so the
#      fresh "" re-derives the SAME addresses (incl. the tracker) and recovers the
#      still-immature coinbase, without re-importing spent coinbase history,
#   3. sweep the funds back into the fresh "".
# The tracker address stays ismine on "" and MPOS keeps paying from /wallet/ = "".
# eloipool and MPOS need zero changes: no tracker repoint, no config edit. The one
# operation replaces both a standalone consolidate (it consolidates the UTXO set)
# and a standalone sweep (it shrinks wallet.dat). See tools/sweep.md.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [ -r "${SCRIPT_DIR}/lib/tool-banner.sh" ]; then
  # shellcheck disable=SC1091
  . "${SCRIPT_DIR}/lib/tool-banner.sh"
fi
# This is the MAINNET (live pool) tool. The separate regtest validator is
# tools/regnet-wallet-maintenance.sh (isolated regtest daemons).

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
# Daemon binary names — used to locate a native (non-Docker) daemon process and
# its host cli/datadir when a coin is run natively instead of in a container.
declare -A DAEMON_NAME=(
  [blc]="blakecoind"
  [pho]="photond"
  [bbtc]="blakebitcoind"
  [elt]="electrond"
  [lit]="lithiumd"
  [umo]="universalmoleculed"
)
# Per-coin daemon access, resolved once by resolve_coin_access(): mode
# ("docker"|"native"), the cli to run, the daemon datadir, the container name
# (docker), the host path of the datadir (for the wallet.dat swap), and the
# network subdir under the datadir ("" mainnet, "testnet3" etc.).
declare -A COIN_MODE=()
declare -A COIN_CLIBIN=()
declare -A COIN_DATADIR=()
declare -A COIN_CONTAINER=()
declare -A COIN_HOSTDIR=()
declare -A COIN_NET=()
declare -A ADDRESS_TYPE=(
  [blc]="bech32"
  [pho]="bech32"
  [bbtc]="bech32"
  [elt]="bech32"
  [lit]="bech32"
  [umo]="bech32"
)

# Mainnet only; kept as a constant so the container/log helpers stay shared with
# the regtest validator's lineage. `--main` is accepted as a harmless no-op.
MODE="main"
# Default action. A bare run in a terminal opens the coin + options picker (rotate).
ACTION="rotate"
ACTION_EXPLICIT=0
COIN_SELECT="all"
COIN_SELECT_EXPLICIT=0
BATCH_SIZE="${MPOS_UTXO_BATCH_SIZE:-100}"
MIN_CONFIRMS="${MPOS_UTXO_MIN_CONFIRMS:-6}"
FEE_RATE="${MPOS_UTXO_FEE_RATE:-0.0001}"
MAX_MEMPOOL="${MPOS_UTXO_MAX_MEMPOOL:-10}"
MEMPOOL_RESUME="${MPOS_UTXO_MEMPOOL_RESUME:-5}"
POLL_INTERVAL="${MPOS_UTXO_POLL_INTERVAL:-30}"
KEY_DUMP_BASE="${MPOS_WALLET_KEY_DUMP_DIR:-/root/blakestream-wallet-key-dumps}"
# A rotation broadcasts by default (gated by a typed YES). --dry-run previews
# the plan only and moves/swaps nothing.
SEND=true
ASSUME_YES=false

# Per-coin rotation state.
declare -A ROTATE_TEMP=()      # coin -> temp wallet name (holds funds across the swap)
declare -A ROTATE_DESCFILE=()  # coin -> host path of captured private descriptors (0600)
declare -A ROTATE_PREBAL=()    # coin -> pre-rotation total balance (trusted+pending+immature)
declare -A ROTATE_REFADDR=()   # coin -> a "" address re-checked ismine after the swap
declare -A ROTATE_FAIL=()      # coin -> 1 if a phase failed (skip its later phases)
declare -A ROTATE_PRESIZE=()   # coin -> "" wallet.dat size (bytes) before the rotation
declare -A ROTATE_POSTBAL=()   # coin -> "" total balance after
declare -A ROTATE_ISMINE=()    # coin -> tracker-keychain ismine after
declare -A ROTATE_POSTSIZE=()  # coin -> "" wallet.dat size (bytes) after
declare -A ROTATE_TRACKER=()       # coin -> coinbase tracker address (most-UTXO addr), captured pre-swap
declare -A ROTATE_TRACKER_AFTER=() # coin -> tracker ismine on the fresh "" after the swap (true/false)
ROTATE_TEMP_NAME=""            # --temp-wallet override (default rotate-temp-<coin>-<ts>)
# Rotation-plan row cache (computed per coin, then rendered as one aligned box).
declare -A PLAN_OK=() PLAN_SP=() PLAN_UTXOS=() PLAN_TXNS=() PLAN_FEE=() PLAN_HISTTX=() PLAN_WDAT=() PLAN_RESCAN=()
ROTATION_RAN=0                 # set when a live (non-dry) rotation actually executes
MOVED_TXS=0; MOVED_INPUTS=0; MOVED_VALUE=0   # last move_utxos_to_address summary
ROTATE_PLAN_HDR=0
# Coinbase maturity per coin. The scoped rescan goes back maturity + margin so the
# fresh "" recovers every still-immature coinbase without re-importing already
# spent coinbase history (which would re-bloat wallet.dat). ELT is the long one.
declare -A COINBASE_MATURITY=(
  [blc]=100 [pho]=100 [bbtc]=100 [elt]=460 [lit]=100 [umo]=100
)
RESCAN_MARGIN="${MPOS_ROTATE_RESCAN_MARGIN:-100}"
RESCAN_DEPTH_OVERRIDE="${MPOS_ROTATE_RESCAN_DEPTH:-}"
# Mining services paused for the wallet-file swap window (one window per batch).
# eloipool drives the parent stratum + merged aux, so stopping it pauses all six.
MINING_UNITS="${MPOS_MINING_UNITS:-blakestream-mpos-eloipool blakestream-mpos-mergeminer}"
PAUSE_MINING=true              # menu toggle: pause mining for the swap (clean choice)

# Health thresholds for the status table / menu health chips.
WARN_UTXO_COUNT="${MPOS_UTXO_WARN_COUNT:-400}"
BAD_UTXO_COUNT="${MPOS_UTXO_BAD_COUNT:-800}"
SMALL_AMOUNT="${MPOS_UTXO_SMALL_AMOUNT:-0.0001}"
SMALL_WARN_COUNT="${MPOS_UTXO_SMALL_WARN_COUNT:-100}"
SMALL_BAD_COUNT="${MPOS_UTXO_SMALL_BAD_COUNT:-200}"

red=$'\033[0;31m'
green=$'\033[0;32m'
yellow=$'\033[1;33m'
blue=$'\033[38;5;39m'
cyan=$'\033[0;36m'
orange=$'\033[38;5;208m'
white=$'\033[1;37m'
nc=$'\033[0m'

say() { printf '%s[INFO]%s %s\n' "$blue" "$nc" "$*"; }
ok() { printf '%s[OK]%s %s\n' "$green" "$nc" "$*"; }
warn() { printf '%s[WARN]%s %s%s%s\n' "$yellow" "$nc" "$white" "$*" "$nc" >&2; }
die() { printf '%s[ERROR]%s %s\n' "$red" "$nc" "$*" >&2; exit 1; }

# Append a timestamped line to the run log so every live rotation — the coins,
# sweeps, txids, the swap and the scoped rescan — is recorded as a replayable
# audit trail. Override with MPOS_WALLET_UTXO_LOG (default:
# <key-dump dir>/wallet-maintenance.log).
LOG_FILE=""
logmsg() {
  LOG_FILE="${MPOS_WALLET_UTXO_LOG:-${KEY_DUMP_BASE}/wallet-maintenance.log}"
  mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
  printf '%s  %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$LOG_FILE" 2>/dev/null || true
  chmod 600 "$LOG_FILE" 2>/dev/null || true
}

usage() {
  cat <<'EOF'
Usage (MAINNET / live pool — regtest is the separate tools/regnet-wallet-maintenance.sh):
  wallet-maintenance.sh                        # live menu: pick coins + operation
  wallet-maintenance.sh status [--all]         # show wallet UTXO health
  wallet-maintenance.sh rotate  --coin blc [--dry-run] [--no-pause]
  wallet-maintenance.sh combine --coin blc [--dry-run]

Two operations on the live "" wallet:
  rotate   Reset wallet.dat to a fresh, small file while keeping the same keychain
           — the eloipool tracker stays ismine on "" and MPOS keeps paying from
           /wallet/ = "". Shrinks the file (and consolidates); eloipool/MPOS need
           no changes.
  combine  Merge many of "" 's UTXOs into fewer outputs, in place — defragments so
           sends stay fast; the funds and the wallet's history stay put.
Both broadcast after a typed YES; --dry-run previews the plan only.

Options:
  --coin COIN              blc, pho, bbtc, elt, lit, umo, or a comma list
  --all                    All six coins
  --dry-run, --dry         Preview the plan only; move/swap nothing
  --no-pause               Do NOT pause mining for the swap (scoped rescan still
                           covers the window; pausing is the clean default)
  --temp-wallet NAME       Temp wallet name (default: rotate-temp-<coin>-<ts>)
  --rescan-depth N         Override rescan depth (default: coinbase maturity + 100)
  --batch-size N           Inputs per sweep transaction (default: 100)
  --min-confirms N         Minimum confirmations to sweep from "" (default: 6)
  --fee-rate N             Fee per KB in coins (default: 0.0001)
  --max-mempool N          Pause sweeping when mempool reaches N txs (default: 10)
  --mempool-resume N       Resume sweeping when mempool drains to N (default: 5)
  --poll-interval N        Seconds between mempool checks (default: 30)
  --key-dir DIR            Root-only base for captured descriptors (default below)
  --yes                    Skip the typed YES confirmation

Tuning env:
  MPOS_ROTATE_RESCAN_MARGIN=100      blocks added past coinbase maturity
  MPOS_ROTATE_RESCAN_DEPTH=          force an exact rescan depth (overrides above)
  MPOS_MINING_UNITS="eloipool merge" systemd units paused for the swap window

Examples:
  sudo tools/wallet-maintenance.sh                          # live menu
  sudo tools/wallet-maintenance.sh status --all             # wallet UTXO health
  sudo tools/wallet-maintenance.sh rotate --coin blc --dry-run   # preview, move nothing
  sudo tools/wallet-maintenance.sh rotate --coin blc        # broadcasts (after YES)

Regtest validation of the rotation mechanic is the separate, isolated:
  sudo tools/regnet-wallet-maintenance.sh blc

Captured private descriptors (the keychain re-imported into the fresh "") are
written root-only under:
  /root/blakestream-wallet-key-dumps/
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --main) shift ;;   # accepted as a no-op: this tool is mainnet-only
    status|rotate|combine|rescan|mine) ACTION="$1"; ACTION_EXPLICIT=1; shift ;;
    --coin) COIN_SELECT="$2"; COIN_SELECT_EXPLICIT=1; shift 2 ;;
    --all) COIN_SELECT="all"; COIN_SELECT_EXPLICIT=1; shift ;;
    --temp-wallet) ROTATE_TEMP_NAME="$2"; shift 2 ;;
    --rescan-depth) RESCAN_DEPTH_OVERRIDE="$2"; shift 2 ;;
    --batch-size) BATCH_SIZE="$2"; shift 2 ;;
    --min-confirms) MIN_CONFIRMS="$2"; shift 2 ;;
    --fee-rate) FEE_RATE="$2"; shift 2 ;;
    --max-mempool) MAX_MEMPOOL="$2"; shift 2 ;;
    --mempool-resume) MEMPOOL_RESUME="$2"; shift 2 ;;
    --poll-interval) POLL_INTERVAL="$2"; shift 2 ;;
    --key-dir) KEY_DUMP_BASE="$2"; shift 2 ;;
    --dry|--dry-run) SEND=false; shift ;;
    --no-pause) PAUSE_MINING=false; shift ;;
    --send) SEND=true; shift ;;
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
  need_cmd bc
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
  # Prefer the controlling terminal when one is attached: confirm/menu prompts run
  # inside `while ... done < <(...)` loops where fd 0 is the process-substitution
  # pipe, not the tty; gating on `[ -t 0 ]` there reads the pipe and swallows the
  # operator's typed input. Read /dev/tty directly instead.
  if [ -r /dev/tty ]; then
    IFS= read -r "$var_name" < /dev/tty
  else
    IFS= read -r "$var_name"
  fi
}

# Single-keypress read (no Enter needed). The menu uses this so a coin/option
# toggles the moment its key is pressed; a bare Enter reads as an empty value to
# confirm. Returns non-zero on EOF so callers don't loop forever.
read_user_key() {
  local var_name="$1"
  if [ -r /dev/tty ]; then
    IFS= read -rsn1 "$var_name" < /dev/tty
  else
    IFS= read -rsn1 "$var_name"
  fi
}

require_root_for_key_ops() {
  if [[ "$ACTION" != "status" && "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "Run ${ACTION} with sudo/root so captured descriptors are written root-only."
  fi
}

operator_owner_spec() {
  if [[ -n "${SUDO_UID:-}" && -n "${SUDO_GID:-}" && "${SUDO_UID}" != "0" ]]; then
    printf '%s:%s\n' "$SUDO_UID" "$SUDO_GID"
    return 0
  fi
  return 1
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

live_container_name() {
  local coin="$1" upper value
  upper="$(coin_upper "$coin")"
  value="$(env_value "MPOS_CONTAINER_${upper}")"
  [[ -n "$value" ]] || value="$(env_value "MPOS_DAEMON_CONTAINER_${upper}")"
  [[ -n "$value" ]] || value="$coin"
  printf '%s' "$value"
}

coin_container_name() {
  live_container_name "$1"
}

container_label() {
  local container="$1" label="$2"
  docker inspect -f "{{ index .Config.Labels \"${label}\" }}" "$container" 2>/dev/null || true
}

is_rollback_smoke_container() {
  [[ "$(container_label "$1" blakestream.rollback-smoke)" == "1" ]]
}

refuse_regtest_container_in_main() {
  local coin="$1" container
  container="$(live_container_name "$coin")"
  if docker_running "$container" && is_rollback_smoke_container "$container"; then
    die "${container} is a rollback-smoke regtest container. Refusing rotation on test data (use tools/regnet-wallet-maintenance.sh for regtest)."
  fi
}

guard_main_containers() {
  local coin
  while IFS= read -r coin; do
    refuse_regtest_container_in_main "$coin"
  done < <(selected_coins)
}

# The full arg line of a coin's running native (non-peer) daemon, else empty.
# The pool runs a primary + a "-peer" instance per coin; we want the primary.
native_daemon_argline() {
  local d="${DAEMON_NAME[$1]:-}"
  [[ -n "$d" ]] || return 0
  ps -eo args 2>/dev/null | grep -F "/${d} " | grep -v -- '-peer' | head -n1
}

# Path to a coin's native cli — alongside the running daemon binary, else on PATH.
# Empty if neither is found. Override per coin with MPOS_NATIVE_CLI_<SYM>.
native_cli_path() {
  local coin="$1" line dbin dir
  line="$(native_daemon_argline "$coin")"
  dbin="$(awk '{print $1}' <<<"$line")"
  if [[ -n "$dbin" ]]; then
    dir="$(dirname "$dbin")"
    [[ -x "${dir}/${CLI_NAME[$coin]}" ]] && { printf '%s' "${dir}/${CLI_NAME[$coin]}"; return; }
  fi
  command -v "${CLI_NAME[$coin]}" 2>/dev/null || true
}

# A coin's native datadir (the running primary daemon's -datadir), else empty.
# Override per coin with MPOS_NATIVE_DATADIR_<SYM>.
native_datadir() {
  native_daemon_argline "$1" | grep -oE -- '-datadir=[^ ]+' | head -n1 | cut -d'=' -f2-
}

# Decide how to reach a coin's daemon and cache it: a running Docker container if
# one is present, else a native host daemon process. Sets COIN_MODE and the
# cli/datadir/host-path used by rpc() and the wallet.dat swap. Returns non-zero
# if neither a container nor a native daemon is found.
resolve_coin_access() {
  local coin="$1" container bin dd upper
  [[ -n "${COIN_MODE[$coin]:-}" ]] && return 0
  container="$(coin_container_name "$coin")"
  if docker_running "$container"; then
    refuse_regtest_container_in_main "$coin"   # never operate on a rollback-smoke test container
    COIN_MODE[$coin]="docker"
    COIN_CONTAINER[$coin]="$container"
    COIN_CLIBIN[$coin]="${CLI_NAME[$coin]}"
    COIN_DATADIR[$coin]="${DATADIR[$coin]}"
    COIN_HOSTDIR[$coin]="$(host_datadir "$coin")"
    return 0
  fi
  upper="$(coin_upper "$coin")"
  bin="$(env_value "MPOS_NATIVE_CLI_${upper}")"
  [[ -n "$bin" ]] || bin="$(native_cli_path "$coin")"
  dd="$(env_value "MPOS_NATIVE_DATADIR_${upper}")"
  [[ -n "$dd" ]] || dd="$(native_datadir "$coin")"
  if [[ -n "$bin" && -n "$dd" ]]; then
    COIN_MODE[$coin]="native"
    COIN_CLIBIN[$coin]="$bin"
    COIN_DATADIR[$coin]="$dd"
    COIN_HOSTDIR[$coin]="$dd"          # native datadir is already a host path
    return 0
  fi
  return 1
}

rpc() {
  local coin="$1"; shift
  resolve_coin_access "$coin" \
    || die "no daemon found for ${coin}: no running container '$(coin_container_name "$coin")' and no native ${DAEMON_NAME[$coin]:-daemon} process"
  if [[ "${COIN_MODE[$coin]}" == "docker" ]]; then
    docker exec "${COIN_CONTAINER[$coin]}" "${COIN_CLIBIN[$coin]}" -datadir="${COIN_DATADIR[$coin]}" "$@"
  else
    "${COIN_CLIBIN[$coin]}" -datadir="${COIN_DATADIR[$coin]}" "$@"
  fi
}

# Network subdirectory under the datadir for the daemon's chain: "" on mainnet,
# "testnet3"/"testnet4"/"signet"/"regtest" otherwise. The "" wallet.dat lives
# under it (e.g. <datadir>/testnet3/wallets/wallet.dat on testnet).
net_subdir() {
  local coin="$1" chain
  [[ -v "COIN_NET[$coin]" ]] && { printf '%s' "${COIN_NET[$coin]}"; return; }
  chain="$(rpc "$coin" getblockchaininfo 2>/dev/null | jq -r '.chain // "main"' 2>/dev/null || true)"
  case "$chain" in
    test)     COIN_NET[$coin]="testnet3" ;;
    testnet4) COIN_NET[$coin]="testnet4" ;;
    signet)   COIN_NET[$coin]="signet" ;;
    regtest)  COIN_NET[$coin]="regtest" ;;
    *)        COIN_NET[$coin]="" ;;
  esac
  printf '%s' "${COIN_NET[$coin]}"
}

# RPC against a specific named wallet. Once a daemon has more than one wallet
# loaded, bare wallet RPCs error with "Wallet file not specified".
wallet_rpc() {
  local coin="$1" wallet="$2"; shift 2
  rpc "$coin" -rpcwallet="$wallet" "$@"
}

# Run a shell command inside a coin's daemon container (for the wallet.dat swap
# and size checks). Runs as the container's default user, which owns the datadir.
container_sh() {
  local coin="$1"; shift
  docker exec "$(coin_container_name "$coin")" sh -c "$*"
}

coin_label() {
  printf '%s' "${COIN_NAME[$1]}"
}

# The wallet the tool should act on for a coin: the only loaded wallet, or the
# highest-balance one when several are loaded (e.g. a rotation left the temp
# wallet beside ""). Bare wallet RPCs fail with more than one wallet loaded.
active_wallet() {
  local coin="$1" wallets n w bal best="" bestbal=""
  wallets="$(rpc "$coin" listwallets 2>/dev/null || printf '[]')"
  n="$(jq 'length' <<<"$wallets" 2>/dev/null || printf 0)"
  if [[ "${n:-0}" -le 1 ]]; then
    jq -r '.[0] // ""' <<<"$wallets"
    return
  fi
  while IFS= read -r w; do
    bal="$(rpc "$coin" -rpcwallet="$w" getbalances 2>/dev/null | jq -r '((.mine.trusted//0)+(.mine.untrusted_pending//0)+(.mine.immature//0))' 2>/dev/null)"
    [[ -n "$bal" ]] || bal=0
    if [[ -z "$bestbal" ]] || jq -ne --argjson a "$bal" --argjson b "$bestbal" '$a > $b' >/dev/null 2>&1; then
      best="$w"; bestbal="$bal"
    fi
  done < <(jq -r '.[]' <<<"$wallets")
  printf '%s' "$best"
}

list_utxos() {
  local coin="$1" w
  w="$(active_wallet "$coin")"
  rpc "$coin" -rpcwallet="$w" listunspent "$MIN_CONFIRMS" 9999999 \
    | jq '[.[] | select((.spendable // true) == true and (.safe // true) != false)]'
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
  local coin="$1" utxos count total small_count avg max_addr state label
  label="$(coin_label "$coin")"
  if ! resolve_coin_access "$coin"; then
    printf '%-5s %-18s %-5s %10s %18s %10s %9s %18s\n' \
      "${coin^^}" "$label" "BAD" "-" "-" "-" "-" "down"
    return
  fi

  utxos=$(list_utxos "$coin")
  count=$(jq 'length' <<<"$utxos")
  # BALANCE is the wallet's real holdings (trusted + pending + immature), not just
  # the confirmed-spendable UTXO sum — so right after a rotation, when the swept-back
  # funds are still unconfirmed and the recovered coinbase is immature, the refresh
  # shows the balance instead of a misleading 0.
  total=$(rpc "$coin" -rpcwallet="$(active_wallet "$coin")" getbalances 2>/dev/null \
    | jq -r '((.mine.trusted//0)+(.mine.untrusted_pending//0)+(.mine.immature//0)) | (. * 1e8 | round) / 1e8' 2>/dev/null)
  [[ -n "$total" ]] || total=0
  small_count=$(jq --argjson t "$SMALL_AMOUNT" '[.[] | select(.amount <= $t)] | length' <<<"$utxos")
  avg=$(jq -r 'if length > 0 then (([.[].amount] | add) / length) else 0 end | (. * 1e8 | round) / 1e8' <<<"$utxos")
  max_addr=$(jq -r 'if length > 0 then (sort_by(.address) | group_by(.address) | map(length) | max) else 0 end' <<<"$utxos")
  state=$(state_from_utxos "$count" "$small_count")

  printf '%-5s %-18s %-5s %10s %18s %10s %9s %18s\n' \
    "${coin^^}" "$label" "$state" "$count" "$total" "$small_count" "$max_addr" "$avg"
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

status_all() {
  local coin state line worst="OK"
  printf '%-5s %-18s %-5s %10s %18s %10s %9s %18s\n' \
    "COIN" "WALLET" "STATE" "UTXOS" "BALANCE" "SMALL" "MAXADDR" "AVG"
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

# Print one framed (boxed) content line: blue '=' on the left and right, the
# rendered content (which may contain colour codes), and trailing padding so
# every row's right border lines up. $1 = inner content width, $2 = rendered
# content, $3 = the content's *visible* width (excludes colour codes).
_box_line() {
  local pad=$(( $1 - $3 ))
  (( pad < 0 )) && pad=0
  printf '%s=%s %s%*s %s=%s\n' "$blue" "$nc" "$2" "$pad" "" "$blue" "$nc" >&2
}

# Same blue-bordered box line as _box_line, but to stdout — for the rotation plan
# and summary report tables (the menu's box stays on stderr via _box_line).
_boxln_out() {
  local pad=$(( $1 - $3 ))
  (( pad < 0 )) && pad=0
  printf '%s=%s %s%*s %s=%s\n' "$blue" "$nc" "$2" "$pad" "" "$blue" "$nc"
}

# Render the coin-selection panel: a blue box bordered on all four sides, then a
# table with dynamic column widths and — for a selected row — a green ticker with
# an orange '*'. $1 = name of the per-coin selection array (coin -> 0/1); $2 =
# name of the coin->fields cache.
render_coin_table() {
  local -n _sel="$1" _cache="$2"
  local coin id wallet state utxos balance small maxaddr detail
  local w_coin=4 w_wallet=6 w_state=5 w_utxos=5 w_balance=7 w_small=5 w_maxaddr=7
  for coin in "${COINS[@]}"; do
    IFS=$'\t' read -r id wallet state utxos balance small maxaddr detail <<<"${_cache[$coin]}"
    id="${id^^}"
    (( ${#id}      > w_coin ))    && w_coin=${#id}
    (( ${#wallet}  > w_wallet ))  && w_wallet=${#wallet}
    (( ${#state}   > w_state ))   && w_state=${#state}
    (( ${#utxos}   > w_utxos ))   && w_utxos=${#utxos}
    (( ${#balance} > w_balance )) && w_balance=${#balance}
    (( ${#small}   > w_small ))   && w_small=${#small}
    (( ${#maxaddr} > w_maxaddr )) && w_maxaddr=${#maxaddr}
  done
  # Blue ' | ' column separators, 3 visible columns each (space, pipe, space).
  # The 5-wide SEL cell + 7 separators (7x3) account for the constant 26 below.
  local sep=" ${blue}|${nc} "
  local total=$(( 26 + w_coin + w_wallet + w_state + w_utxos + w_balance + w_small + w_maxaddr ))
  local boxw=$(( total + 4 )) rule
  printf -v rule '%*s' "$boxw" ''; rule=${rule// /=}

  printf '%s%s%s\n' "$blue" "$rule" "$nc" >&2
  local hdr
  printf -v hdr "%-5s${sep}%-${w_coin}s${sep}%-${w_wallet}s${sep}%-${w_state}s${sep}%${w_utxos}s${sep}%${w_balance}s${sep}%${w_small}s${sep}%${w_maxaddr}s" \
    "SEL" "COIN" "WALLET" "STATE" "UTXOS" "BALANCE" "SMALL" "MAXADDR"
  _box_line "$total" "$hdr" "$total"
  local idx=1 row
  for coin in "${COINS[@]}"; do
    IFS=$'\t' read -r id wallet state utxos balance small maxaddr detail <<<"${_cache[$coin]}"
    if [[ "${_sel[$coin]:-0}" == "1" ]]; then
      printf -v row "%d)[%s*%s]${sep}${green}%-${w_coin}s${nc}${sep}%-${w_wallet}s${sep}%-${w_state}s${sep}%${w_utxos}s${sep}%${w_balance}s${sep}%${w_small}s${sep}%${w_maxaddr}s" \
        "$idx" "$orange" "$nc" "${id^^}" "$wallet" "$state" "$utxos" "$balance" "$small" "$maxaddr"
    else
      printf -v row "%d)[ ]${sep}%-${w_coin}s${sep}%-${w_wallet}s${sep}%-${w_state}s${sep}%${w_utxos}s${sep}%${w_balance}s${sep}%${w_small}s${sep}%${w_maxaddr}s" \
        "$idx" "${id^^}" "$wallet" "$state" "$utxos" "$balance" "$small" "$maxaddr"
    fi
    _box_line "$total" "$row" "$total"
    idx=$((idx + 1))
  done
  local sa="0) Select All"
  _box_line "$total" "$sa" "${#sa}"
  printf '%s%s%s\n' "$blue" "$rule" "$nc" >&2
}

key_output_dir() {
  local coin="$1" action="$2" stamp out
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  out="${KEY_DUMP_BASE}/${stamp}-${coin}-${action}"
  mkdir -p "$out"
  chmod 700 "$KEY_DUMP_BASE" "$out"
  printf '%s' "$out"
}

# Save a wallet's private descriptors (the keychain re-imported into the fresh
# "") to a root-only host file; echo the path. Treat as secret — private keys.
capture_descriptors() {
  local coin="$1" wallet="$2" out f
  out="$(key_output_dir "$coin" "rotate")"
  f="${out}/${coin}-${wallet:-default}-descriptors-private.json"
  if ! rpc "$coin" -rpcwallet="$wallet" listdescriptors true > "$f" 2>/dev/null; then
    die "${coin}: listdescriptors on '${wallet:-(default)}' failed (wallet encrypted/locked?). No funds moved."
  fi
  chmod 600 "$f"
  printf '%s' "$f"
}

# One confirmation covering every coin selected in the menu, so the operator
# types YES once. Returns non-zero (without exiting) when declined.
confirm_batch() {
  local op="$1"; shift
  local n="$#"
  $ASSUME_YES && return 0
  printf '%sType YES to %s %s selected coin(s): %s' "$yellow" "$op" "$n" "$green"
  local answer
  read_user_line answer
  printf '%s' "$nc"
  [[ "${answer^^}" == "YES" ]]
}

# Live per-coin sweep progress. move_utxos_to_address / wait_for_mempool write a
# one-line status ("state total done txs mempool") to PARALLEL_STATUS_FILE when the
# parallel runner sets it (atomic .tmp->mv); a no-op otherwise, so direct/sequential
# calls are unaffected and a status-write failure can never break the sweep.
SWEEP_TOTAL=0
sweep_status() {
  [[ -n "${PARALLEL_STATUS_FILE:-}" ]] || return 0
  printf '%s %s %s %s %s\n' "$1" "$2" "$3" "$4" "$5" > "${PARALLEL_STATUS_FILE}.tmp" 2>/dev/null \
    && mv -f "${PARALLEL_STATUS_FILE}.tmp" "${PARALLEL_STATUS_FILE}" 2>/dev/null || true
}

get_mempool_count() {
  local coin="$1" raw
  raw=$(rpc "$coin" getrawmempool 2>/dev/null || true)
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
    sweep_status "waiting" "$SWEEP_TOTAL" "$MOVED_INPUTS" "$MOVED_TXS" "$current"
    sleep "$POLL_INTERVAL"
    current="$(get_mempool_count "$coin")"
  done
  printf '\r%80s\r' '' >&2
}

# ---------------------------------------------------------------------------
# Rotation helpers
# ---------------------------------------------------------------------------

rescan_depth() {
  local coin="$1"
  if [[ -n "$RESCAN_DEPTH_OVERRIDE" ]]; then
    printf '%s' "$RESCAN_DEPTH_OVERRIDE"
    return
  fi
  printf '%s' "$(( ${COINBASE_MATURITY[$coin]:-100} + RESCAN_MARGIN ))"
}

# Host path of a coin's datadir — the bind-mount Source whose Destination is the
# container datadir. The live pool bind-mounts each datadir, so the wallet files
# live in this host data folder; we operate on them there directly. Empty when
# the datadir is not bind-mounted (caller then falls back to in-container ops).
host_datadir() {
  local coin="$1" container
  container="$(coin_container_name "$coin")"
  docker inspect "$container" \
    --format "{{range .Mounts}}{{if eq .Destination \"${DATADIR[$coin]}\"}}{{.Source}}{{end}}{{end}}" 2>/dev/null || true
}

# Locate the "" wallet's wallet.dat. The wallet directory is <root>/wallets when
# that exists (modern layout) else <root> itself (legacy layout — the live 25.2
# daemons use this); the "" wallet's file is wallet.dat directly in it, while
# named wallets live in <root>/<name>/. Echoes "<loc> <path>" where <loc> is
# "host" (operate in the host data folder) or "container" (fallback); empty if
# not found.
default_walletdat() {
  local coin="$1" hd dd net base p
  resolve_coin_access "$coin" || return
  net="$(net_subdir "$coin")"
  hd="${COIN_HOSTDIR[$coin]}"
  if [[ -n "$hd" ]]; then
    base="$hd"; [[ -n "$net" ]] && base="$hd/$net"
    [[ -f "$base/wallets/wallet.dat" ]] && { printf 'host %s' "$base/wallets/wallet.dat"; return; }
    [[ -f "$base/wallet.dat" ]]         && { printf 'host %s' "$base/wallet.dat"; return; }
  fi
  if [[ "${COIN_MODE[$coin]}" == "docker" ]]; then
    dd="${COIN_DATADIR[$coin]}"; base="$dd"; [[ -n "$net" ]] && base="$dd/$net"
    p="$(container_sh "$coin" "if [ -f '${base}/wallets/wallet.dat' ]; then echo '${base}/wallets/wallet.dat'; elif [ -f '${base}/wallet.dat' ]; then echo '${base}/wallet.dat'; fi")"
    [[ -n "$p" ]] && printf 'container %s' "$p"
  fi
}

# Size in bytes of a located wallet.dat ("$loc" "$path").
walletdat_size() {
  local coin="$1" loc="$2" p="$3"
  [[ -n "$p" ]] || { printf '0'; return; }
  if [[ "$loc" == "host" ]]; then
    stat -c %s "$p" 2>/dev/null || printf '0'
  else
    container_sh "$coin" "stat -c %s '$p' 2>/dev/null || echo 0"
  fi
}

# Move a located wallet.dat into a sibling _rotated-<stamp>/ backup dir, in the
# host data folder when bind-mounted, else inside the container.
walletdat_move_aside() {
  local coin="$1" loc="$2" p="$3" stamp="$4" wdir
  wdir="$(dirname "$p")"
  if [[ "$loc" == "host" ]]; then
    mkdir -p "${wdir}/_rotated-${stamp}" && mv "$p" "${wdir}/_rotated-${stamp}/"
  else
    container_sh "$coin" "mkdir -p '${wdir}/_rotated-${stamp}' && mv '$p' '${wdir}/_rotated-${stamp}/'"
  fi
}

pause_mining() {
  command -v systemctl >/dev/null 2>&1 || {
    warn "systemctl not found; cannot pause mining — relying on the scoped rescan to cover the swap window"
    return 0
  }
  say "     mining paused for the swap"
  # shellcheck disable=SC2086
  systemctl stop ${MINING_UNITS} 2>/dev/null \
    || warn "could not stop ${MINING_UNITS} (continuing; the scoped rescan covers the window)"
  logmsg "mining paused: ${MINING_UNITS}"
}

resume_mining() {
  command -v systemctl >/dev/null 2>&1 || return 0
  say "     mining resumed"
  # shellcheck disable=SC2086
  systemctl start ${MINING_UNITS} 2>/dev/null \
    || warn "could not start ${MINING_UNITS} — start it manually: systemctl start ${MINING_UNITS}"
  logmsg "mining resumed: ${MINING_UNITS}"
}

# Auto-mine hooks around the throttled sweeps. On mainnet the pool's real miners
# confirm the batches and drain the mempool, so these are no-ops. The regtest twin
# overrides them to mine blocks itself (nothing else mines a throwaway regtest
# chain), so wait_for_mempool drains and the combine/rotate batches confirm.
auto_mine_start() { :; }
auto_mine_stop()  { :; }

# Sweep all of a wallet's spendable UTXOs (>= minconf) to one address, batched at
# BATCH_SIZE inputs per tx. The 'safe' flag is intentionally not required so a
# chained, still-unconfirmed temp output (rotation phase 3) can be swept back.
# Sets MOVED_TXS / MOVED_INPUTS / MOVED_VALUE.
move_utxos_to_address() {
  local coin="$1" src="$2" dest="$3" minconf="$4"
  local utxos count tmp offsets offset slice bcount inputs input_total est_bytes fee output outputs raw signed txid mp
  MOVED_TXS=0; MOVED_INPUTS=0; MOVED_VALUE=0
  utxos="$(wallet_rpc "$coin" "$src" listunspent "$minconf" 9999999)"
  utxos="$(jq '[.[] | select((.spendable // true) == true)] | sort_by(.amount)' <<<"$utxos")"
  count="$(jq 'length' <<<"$utxos")"
  [[ "$count" -ge 1 ]] || return 0
  SWEEP_TOTAL="$count"
  MOVED_VALUE="$(jq -r '([.[].amount] | add // 0) | (. * 1e8 | round) / 1e8' <<<"$utxos")"
  sweep_status "combining" "$count" 0 0 0
  tmp="$(mktemp)"
  trap 'rm -f "${tmp:-}"; trap - RETURN' RETURN
  printf '%s\n' "$utxos" > "$tmp"
  offsets="$(jq --argjson bs "$BATCH_SIZE" -r 'range(0; length; $bs)' "$tmp")"
  for offset in $offsets; do
    slice="$(jq -c --argjson off "$offset" --argjson bs "$BATCH_SIZE" '.[$off:$off+$bs]' "$tmp")"
    bcount="$(jq 'length' <<<"$slice")"
    [[ "$bcount" -ge 1 ]] || continue

    mp="$(get_mempool_count "$coin")"
    sweep_status "combining" "$count" "$MOVED_INPUTS" "$MOVED_TXS" "$mp"
    if [[ "$MAX_MEMPOOL" -gt 0 && "$mp" -ge "$MAX_MEMPOOL" ]]; then
      say "${coin}: mempool at ${mp}; waiting before next batch"
      sweep_status "waiting" "$count" "$MOVED_INPUTS" "$MOVED_TXS" "$mp"
      wait_for_mempool "$coin" "$mp"
      mp="$(get_mempool_count "$coin")"
    fi

    inputs="$(jq -c '[.[] | {txid: .txid, vout: .vout}]' <<<"$slice")"
    input_total="$(jq -r '[.[].amount] | add' <<<"$slice")"
    est_bytes=$(( bcount * 148 + 34 + 10 ))
    fee="$(amount8 "(($est_bytes / 1000) + 1) * $FEE_RATE")"
    output="$(amount8 "$input_total - $fee")"
    if [[ "$(echo "$output <= 0" | bc)" -eq 1 ]]; then
      warn "${coin}: batch output non-positive after fee; skipping"
      continue
    fi

    outputs="$(jq -nc --arg a "$dest" --arg m "$output" '{($a): ($m | tonumber)}')"
    raw="$(rpc "$coin" createrawtransaction "$inputs" "$outputs")"
    signed="$(wallet_rpc "$coin" "$src" signrawtransactionwithwallet "$raw")"
    if [[ "$(jq -r '.complete // false' <<<"$signed")" != "true" ]]; then
      rm -f "$tmp"; trap - RETURN
      die "${coin}: signing incomplete on '${src:-(default)}' (wallet locked?)."
    fi
    txid="$(rpc "$coin" sendrawtransaction "$(jq -r '.hex' <<<"$signed")")" || {
      warn "${coin}: sendrawtransaction failed for a batch"
      continue
    }
    MOVED_TXS=$((MOVED_TXS + 1)); MOVED_INPUTS=$((MOVED_INPUTS + bcount))
    sweep_status "combining" "$count" "$MOVED_INPUTS" "$MOVED_TXS" "$mp"
    logmsg "rotate move ${coin} ${src:-default}->${dest} txid ${txid} ${bcount} in -> ${output}"
  done
  rm -f "$tmp"; trap - RETURN
  sweep_status "done" "$count" "$MOVED_INPUTS" "$MOVED_TXS" "${mp:-0}"
  return 0
}

# Dry-run plan row: what a rotation would do to "" on this coin. No side effects.
rotate_plan_coin() {
  local coin="$1" bal sp cnt txc wloc wdat sz depth b1 b3 txns est_fee
  PLAN_OK[$coin]=0
  if ! resolve_coin_access "$coin"; then
    warn "${coin}: daemon not running; cannot plan"
    return 0
  fi
  bal="$(rpc "$coin" -rpcwallet="" getbalances 2>/dev/null || printf '{}')"
  sp="$(jq -r '((.mine.trusted//0)+(.mine.untrusted_pending//0)) | (. * 1e8 | round) / 1e8' <<<"$bal")"
  cnt="$(rpc "$coin" -rpcwallet="" listunspent "$MIN_CONFIRMS" 9999999 2>/dev/null | jq '[.[] | select((.spendable // true) == true)] | length' 2>/dev/null || printf 0)"
  txc="$(rpc "$coin" -rpcwallet="" getwalletinfo 2>/dev/null | jq -r '.txcount // 0' 2>/dev/null || printf 0)"
  read -r wloc wdat <<<"$(default_walletdat "$coin")" || true
  sz="$(walletdat_size "$coin" "$wloc" "$wdat")"
  depth="$(rescan_depth "$coin")"
  # Transactions the rotation will broadcast: phase-1 sweeps "" 's spendable UTXOs
  # into the temp wallet (one tx per BATCH_SIZE inputs), phase-3 sweeps the temp's
  # outputs back into the fresh "" (one tx per BATCH_SIZE of those). Immature
  # coinbase isn't moved (the scoped rescan recovers it), so it adds no tx.
  b1=$(( (cnt + BATCH_SIZE - 1) / BATCH_SIZE )); (( cnt > 0 )) || b1=0
  b3=$(( (b1 + BATCH_SIZE - 1) / BATCH_SIZE )); (( b1 > 0 )) || b3=0
  txns=$(( b1 + b3 ))
  # Estimated fee = phase-1 sweep ("" 's cnt inputs -> b1 temp outputs) + phase-3
  # sweep-back (b1 inputs -> b3 outputs), using the same per-batch byte sizing the
  # sweep itself uses. Immature coinbase isn't moved, so it adds no fee.
  est_fee="$(amount8 "((($cnt * 148 + $b1 * 44) / 1000 + $b1) + (($b1 * 148 + $b3 * 44) / 1000 + $b3)) * $FEE_RATE")"
  PLAN_OK[$coin]=1
  PLAN_SP[$coin]="$sp";         PLAN_UTXOS[$coin]="$cnt";      PLAN_TXNS[$coin]="$txns"
  PLAN_FEE[$coin]="~${est_fee}"; PLAN_HISTTX[$coin]="$txc"
  PLAN_WDAT[$coin]="${sz} B";   PLAN_RESCAN[$coin]="$depth"
}

# Render the cached rotation-plan rows as one blue-bordered, dynamically-aligned
# box (same look as the coin selector), so wide balances (e.g. PHO) never push the
# other columns out of line.
render_rotation_plan() {
  local coin sep total boxw rule hdr row v
  local w_coin=4 w_sp=9 w_utxos=5 w_txns=4 w_fee=7 w_histtx=7 w_wdat=10 w_rescan=6
  local planned=()
  for coin in "$@"; do
    [[ "${PLAN_OK[$coin]:-0}" == "1" ]] || continue
    planned+=("$coin")
    (( ${#coin} > w_coin )) && w_coin=${#coin}
    v="${PLAN_SP[$coin]}";     (( ${#v} > w_sp ))     && w_sp=${#v}
    v="${PLAN_UTXOS[$coin]}";  (( ${#v} > w_utxos ))  && w_utxos=${#v}
    v="${PLAN_TXNS[$coin]}";   (( ${#v} > w_txns ))   && w_txns=${#v}
    v="${PLAN_FEE[$coin]}";    (( ${#v} > w_fee ))    && w_fee=${#v}
    v="${PLAN_HISTTX[$coin]}"; (( ${#v} > w_histtx )) && w_histtx=${#v}
    v="${PLAN_WDAT[$coin]}";   (( ${#v} > w_wdat ))   && w_wdat=${#v}
    v="${PLAN_RESCAN[$coin]}"; (( ${#v} > w_rescan )) && w_rescan=${#v}
  done
  [[ "${#planned[@]}" -ge 1 ]] || return 0
  if $SEND; then printf '\n%sRotation plan%s\n' "$cyan" "$nc"
  else printf '\n%sRotation plan%s %s- Dry Run%s\n' "$cyan" "$nc" "$yellow" "$nc"; fi
  sep=" ${blue}|${nc} "
  total=$(( 21 + w_coin + w_sp + w_utxos + w_txns + w_fee + w_histtx + w_wdat + w_rescan ))
  boxw=$(( total + 4 )); printf -v rule '%*s' "$boxw" ''; rule=${rule// /=}
  printf '%s%s%s\n' "$blue" "$rule" "$nc"
  printf -v hdr "%-${w_coin}s${sep}%${w_sp}s${sep}%${w_utxos}s${sep}%${w_txns}s${sep}%${w_fee}s${sep}%${w_histtx}s${sep}%${w_wdat}s${sep}%${w_rescan}s" \
    "COIN" "SPENDABLE" "UTXOS" "TXNS" "EST.FEE" "HIST.TX" "WALLET.DAT" "RESCAN"
  _boxln_out "$total" "$hdr" "$total"
  for coin in "${planned[@]}"; do
    printf -v row "%-${w_coin}s${sep}%${w_sp}s${sep}%${w_utxos}s${sep}%${w_txns}s${sep}%${w_fee}s${sep}%${w_histtx}s${sep}%${w_wdat}s${sep}%${w_rescan}s" \
      "${coin^^}" "${PLAN_SP[$coin]}" "${PLAN_UTXOS[$coin]}" "${PLAN_TXNS[$coin]}" "${PLAN_FEE[$coin]}" "${PLAN_HISTTX[$coin]}" "${PLAN_WDAT[$coin]}" "${PLAN_RESCAN[$coin]}"
    _boxln_out "$total" "$row" "$total"
  done
  printf '%s%s%s\n' "$blue" "$rule" "$nc"
}

# Phase 1 (mining running): capture "" 's keychain + sweep its spendable funds to
# a fresh temp wallet. This also consolidates them (one output per batch).
rotate_phase1_coin() {
  local coin="$1" loaded temp tdest pre pwl pwd
  ROTATE_FAIL[$coin]=0
  loaded="$(rpc "$coin" listwallets | jq -r 'index("") // empty' 2>/dev/null || true)"
  if [[ -z "$loaded" ]]; then
    rpc "$coin" loadwallet "" >/dev/null 2>&1 || {
      warn "${coin}: default '' wallet is not loaded and could not be loaded; skipping"
      ROTATE_FAIL[$coin]=1; return 0
    }
  fi
  pre="$(rpc "$coin" -rpcwallet="" getbalances | jq -r '((.mine.trusted//0)+(.mine.untrusted_pending//0)+(.mine.immature//0))')"
  ROTATE_PREBAL[$coin]="$pre"
  read -r pwl pwd <<<"$(default_walletdat "$coin")" || true
  ROTATE_PRESIZE[$coin]="$(walletdat_size "$coin" "$pwl" "$pwd")"
  ROTATE_REFADDR[$coin]="$(rpc "$coin" -rpcwallet="" getnewaddress rotate-ref "${ADDRESS_TYPE[$coin]}")"
  # Coinbase tracker = the "" address holding the most UTXOs (where coinbase lands).
  # Captured before the swap so phase 3 can confirm the SAME address is still ismine.
  ROTATE_TRACKER[$coin]="$(rpc "$coin" -rpcwallet="" listunspent 1 9999999 2>/dev/null | jq -r 'if length>0 then (group_by(.address)|max_by(length)|.[0].address) else empty end' 2>/dev/null || true)"
  [[ -n "${ROTATE_TRACKER[$coin]:-}" ]] || ROTATE_TRACKER[$coin]="${ROTATE_REFADDR[$coin]}"
  ROTATE_DESCFILE[$coin]="$(capture_descriptors "$coin" "")"
  temp="${ROTATE_TEMP_NAME:-rotate-temp-${coin}-$(date -u +%Y%m%dT%H%M%SZ)}"
  ROTATE_TEMP[$coin]="$temp"
  rpc "$coin" createwallet "$temp" false false "" false true true >/dev/null || {
    warn "${coin}: createwallet temp '${temp}' failed"
    ROTATE_FAIL[$coin]=1; return 0
  }
  tdest="$(wallet_rpc "$coin" "$temp" getnewaddress rotate-temp "${ADDRESS_TYPE[$coin]}")"
  capture_descriptors "$coin" "$temp" >/dev/null   # back up the temp wallet's keys too
  move_utxos_to_address "$coin" "" "$tdest" "$MIN_CONFIRMS"
  logmsg "rotate ${coin} phase1 (combine): '' -> ${temp}; ${MOVED_TXS} tx / ${MOVED_INPUTS} inputs (~${MOVED_VALUE}); prebal ${pre}; pre wallet.dat ${ROTATE_PRESIZE[$coin]} B; desc ${ROTATE_DESCFILE[$coin]}"
}

# Phase 2 (swap window, optionally mining-paused): unload "", move its wallet.dat
# aside, create a fresh blank "", re-import the keychain with a scoped rescan.
rotate_phase2_coin() {
  local coin="$1" depth tip h ts wloc wdat wdir stamp import res
  [[ "${ROTATE_FAIL[$coin]:-0}" == "1" ]] && return 0
  depth="$(rescan_depth "$coin")"
  tip="$(rpc "$coin" getblockcount)" || { warn "${coin}: getblockcount failed; skipping swap (funds untouched in '')"; ROTATE_FAIL[$coin]=1; return 0; }
  h=$(( tip - depth )); (( h < 0 )) && h=0
  ts="$(rpc "$coin" getblockheader "$(rpc "$coin" getblockhash "$h")" | jq -r '.time')" || { warn "${coin}: could not read rescan timestamp; skipping swap (funds untouched in '')"; ROTATE_FAIL[$coin]=1; return 0; }
  read -r wloc wdat <<<"$(default_walletdat "$coin")" || true
  if [[ -z "$wdat" ]]; then
    warn "${coin}: could not locate '' wallet.dat; skipping swap (funds safe in temp '${ROTATE_TEMP[$coin]}')"
    ROTATE_FAIL[$coin]=1; return 0
  fi
  # Don't begin the destructive swap unless the captured keychain is readable — a
  # missing/empty descriptor backup must abort with '' still intact, not blanked.
  if [[ ! -r "${ROTATE_DESCFILE[$coin]:-/nonexistent}" ]]; then
    warn "${coin}: keychain backup (private descriptors) missing/unreadable; skipping swap (funds untouched in '')"
    ROTATE_FAIL[$coin]=1; return 0
  fi
  wdir="$(dirname "$wdat")"
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  rpc "$coin" unloadwallet "" >/dev/null || {
    warn "${coin}: unloadwallet '' failed; aborting swap (funds safe in temp)"
    ROTATE_FAIL[$coin]=1; return 0
  }
  walletdat_move_aside "$coin" "$wloc" "$wdat" "$stamp" || {
    warn "${coin}: moving wallet.dat aside failed; reloading the old ''"
    rpc "$coin" loadwallet "" >/dev/null 2>&1 || true
    ROTATE_FAIL[$coin]=1; return 0
  }
  rpc "$coin" createwallet "" false true "" false true true >/dev/null || {
    warn "${coin}: createwallet '' (blank) failed; the old wallet.dat is at ${wdir}/_rotated-${stamp}/"
    ROTATE_FAIL[$coin]=1; return 0
  }
  import="$(jq -c --argjson ts "$ts" \
    '[.descriptors[] | {desc:.desc, active:.active, internal:.internal, timestamp:$ts}
       + (if has("range") then {range:.range} else {} end)
       + (if has("next")  then {next_index:.next} else {} end)]' "${ROTATE_DESCFILE[$coin]}")" || {
    warn "${coin}: could not build the import from ${ROTATE_DESCFILE[$coin]:-?}; '' is blank — restore the old wallet.dat from ${wdir}/_rotated-${stamp}/ (funds also safe in temp '${ROTATE_TEMP[$coin]}')"
    ROTATE_FAIL[$coin]=1; return 0
  }
  res="$(rpc "$coin" -rpcwallet="" importdescriptors "$import")" || {
    warn "${coin}: importdescriptors RPC failed; '' is blank — restore the old wallet.dat from ${wdir}/_rotated-${stamp}/ (funds also safe in temp '${ROTATE_TEMP[$coin]}')"
    ROTATE_FAIL[$coin]=1; return 0
  }
  if ! echo "$res" | jq -e 'all(.[]; .success)' >/dev/null 2>&1; then
    ROTATE_FAIL[$coin]=1
    warn "${coin}: importdescriptors had errors:"
    echo "$res" | jq -c '.[] | select(.success | not)' >&2 || true
  elif [[ -n "${ROTATE_REFADDR[$coin]:-}" ]] \
       && ! rpc "$coin" -rpcwallet="" getaddressinfo "${ROTATE_REFADDR[$coin]}" 2>/dev/null | jq -e '.ismine' >/dev/null 2>&1; then
    # Import said success but the keychain didn't actually restore (a pre-swap ''
    # address is not ismine on the fresh '') — treat as failed, keep the backups.
    warn "${coin}: importdescriptors reported success but a pre-swap '' address is not ismine on the fresh '' — restore the old wallet.dat from ${wdir}/_rotated-${stamp}/ (funds safe in temp '${ROTATE_TEMP[$coin]}')"
    ROTATE_FAIL[$coin]=1
  else
    logmsg "rotate ${coin} phase2 (swap): ${wloc}:${wdat} -> ${wdir}/_rotated-${stamp}/; createwallet '' blank; reimport scoped depth ${depth} from block ${h}; keychain ismine verified = OK"
  fi
}

# Phase 3 (mining running): sweep the temp funds back into the fresh "", verify,
# and unload temp so the daemon returns to a single "" wallet.
rotate_phase3_coin() {
  local coin="$1" temp tbal newaddr post ismine na wloc wdat sz
  temp="${ROTATE_TEMP[$coin]:-}"
  if [[ "${ROTATE_FAIL[$coin]:-0}" == "1" ]]; then
    warn "${coin}: rotation did not complete; funds remain in temp '${temp}' and the old wallet.dat is kept under the datadir. Recover manually (see the run log)."
    return 0
  fi
  local moved=0
  if [[ -n "$temp" ]]; then
    tbal="$(wallet_rpc "$coin" "$temp" getbalances | jq -r '((.mine.trusted//0)+(.mine.untrusted_pending//0))')"
    if [[ "$(echo "$tbal > 0" | bc)" -eq 1 ]]; then
      newaddr="$(rpc "$coin" -rpcwallet="" getnewaddress rotate-back "${ADDRESS_TYPE[$coin]}")"
      move_utxos_to_address "$coin" "$temp" "$newaddr" 0
      moved="$MOVED_TXS"
    fi
  fi
  post="$(rpc "$coin" -rpcwallet="" getbalances | jq -r '((.mine.trusted//0)+(.mine.untrusted_pending//0)+(.mine.immature//0))')"
  ismine="n/a"
  [[ -n "${ROTATE_REFADDR[$coin]:-}" ]] && ismine="$(rpc "$coin" -rpcwallet="" getaddressinfo "${ROTATE_REFADDR[$coin]}" | jq -r '.ismine')"
  ROTATE_TRACKER_AFTER[$coin]="$(rpc "$coin" -rpcwallet="" getaddressinfo "${ROTATE_TRACKER[$coin]:-x}" 2>/dev/null | jq -r '.ismine // false' 2>/dev/null || echo false)"
  na="$(rpc "$coin" -rpcwallet="" getnewaddress rotate-check "${ADDRESS_TYPE[$coin]}" 2>/dev/null || true)"
  read -r wloc wdat <<<"$(default_walletdat "$coin")" || true
  sz="$(walletdat_size "$coin" "$wloc" "$wdat")"
  ROTATE_POSTBAL[$coin]="$post"
  ROTATE_ISMINE[$coin]="$ismine"
  ROTATE_POSTSIZE[$coin]="$sz"
  [[ -n "$na" ]] || ROTATE_FAIL[$coin]=1   # getnewaddress must work on the fresh ""
  logmsg "rotate ${coin} phase3 (restore): temp ${temp} -> '' (${moved} tx); total ${post} (was ${ROTATE_PREBAL[$coin]:-?}); ismine ${ismine}; getnewaddress $([[ -n "$na" ]] && echo ok || echo FAIL); wallet.dat ${sz} (was ${ROTATE_PRESIZE[$coin]:-?})"
  [[ -n "$temp" ]] && rpc "$coin" unloadwallet "$temp" >/dev/null 2>&1 || true
}

# Clean end-of-run summary table. The full per-coin / per-txid detail lives in the
# run log; the screen shows only balance preserved, tracker ismine, and the shrink.
# Compute a coin's display cells for the summary into the named vars; returns 1 for
# a failed coin (cells set to "-").
_summary_cells() {
  local coin="$1"
  if [[ "${ROTATE_FAIL[$coin]:-0}" == "1" ]]; then
    s_bal="-"; s_pre="-"; s_im="-"; s_sz="-"; s_presz="-"; return 1
  fi
  s_bal="$(LC_ALL=C printf '%.8f' "${ROTATE_POSTBAL[$coin]:-0}" 2>/dev/null)"; [[ -n "$s_bal" ]] || s_bal="${ROTATE_POSTBAL[$coin]:-?}"
  s_pre="$(LC_ALL=C printf '%.8f' "${ROTATE_PREBAL[$coin]:-0}" 2>/dev/null)"; [[ -n "$s_pre" ]] || s_pre="${ROTATE_PREBAL[$coin]:-?}"
  s_sz="${ROTATE_POSTSIZE[$coin]:-?}"; s_presz="${ROTATE_PRESIZE[$coin]:-?}"
  s_im="${ROTATE_ISMINE[$coin]:-?}"; [[ "$s_im" == "true" ]] && s_im="ismine"
  return 0
}

# Clean end-of-run summary as one blue-bordered, dynamically-aligned box (same look
# as the coin selector). Full per-coin / per-txid detail lives in the run log.
print_rotation_summary() {
  local coin log sep total boxw rule hdr row s_bal s_pre s_im s_sz s_presz
  local w_coin=4 w_bal=7 w_was=5 w_trk=7 w_wdat=10 w_was2=5 w_st=6
  for coin in "$@"; do
    (( ${#coin} > w_coin )) && w_coin=${#coin}
    _summary_cells "$coin" || continue
    (( ${#s_bal}   > w_bal ))  && w_bal=${#s_bal}
    (( ${#s_pre}   > w_was ))  && w_was=${#s_pre}
    (( ${#s_im}    > w_trk ))  && w_trk=${#s_im}
    (( ${#s_sz}    > w_wdat )) && w_wdat=${#s_sz}
    (( ${#s_presz} > w_was2 )) && w_was2=${#s_presz}
  done
  log="${MPOS_WALLET_UTXO_LOG:-${KEY_DUMP_BASE}/wallet-maintenance.log}"
  printf '\n%sRotation summary%s\n' "$cyan" "$nc"
  sep=" ${blue}|${nc} "
  total=$(( 18 + w_coin + w_bal + w_was + w_trk + w_wdat + w_was2 + w_st ))
  boxw=$(( total + 4 )); printf -v rule '%*s' "$boxw" ''; rule=${rule// /=}
  printf '%s%s%s\n' "$blue" "$rule" "$nc"
  printf -v hdr "%-${w_coin}s${sep}%${w_bal}s${sep}%${w_was}s${sep}%-${w_trk}s${sep}%${w_wdat}s${sep}%${w_was2}s${sep}%-${w_st}s" \
    "COIN" "BALANCE" "(was)" "TRACKER" "WALLET.DAT" "(was)" "STATUS"
  _boxln_out "$total" "$hdr" "$total"
  for coin in "$@"; do
    if _summary_cells "$coin"; then
      printf -v row "%-${w_coin}s${sep}%${w_bal}s${sep}%${w_was}s${sep}%-${w_trk}s${sep}%${w_wdat}s${sep}%${w_was2}s${sep}${green}%-${w_st}s${nc}" \
        "${coin^^}" "$s_bal" "$s_pre" "$s_im" "$s_sz" "$s_presz" "OK"
    else
      printf -v row "%-${w_coin}s${sep}%${w_bal}s${sep}%${w_was}s${sep}%-${w_trk}s${sep}%${w_wdat}s${sep}%${w_was2}s${sep}${red}%-${w_st}s${nc}" \
        "${coin^^}" "-" "-" "-" "-" "-" "FAILED"
    fi
    _boxln_out "$total" "$row" "$total"
  done
  printf '%s%s%s\n' "$blue" "$rule" "$nc"
  printf '\n%sDetails (txids, per-phase):%s %s\n' "$cyan" "$nc" "$log"
  printf '%sBackups kept%s — each datadir'\''s _rotated-* (old wallet.dat) + the rotate-temp-* wallets. Delete both once the pool has paid out cleanly from the fresh "".\n' "$cyan" "$nc"
}

# Result emitters: a coin's phase runs in a subshell (so coins go concurrently),
# and a subshell cannot mutate the parent's arrays. Each emitter prints the coin's
# result vars (quoted) for the parent to source back after all coins finish.
emit_rotate_phase1() {
  local coin="$1"
  printf 'ROTATE_FAIL[%s]=%q\n'     "$coin" "${ROTATE_FAIL[$coin]:-0}"
  printf 'ROTATE_PREBAL[%s]=%q\n'   "$coin" "${ROTATE_PREBAL[$coin]:-}"
  printf 'ROTATE_PRESIZE[%s]=%q\n'  "$coin" "${ROTATE_PRESIZE[$coin]:-}"
  printf 'ROTATE_REFADDR[%s]=%q\n'  "$coin" "${ROTATE_REFADDR[$coin]:-}"
  printf 'ROTATE_DESCFILE[%s]=%q\n' "$coin" "${ROTATE_DESCFILE[$coin]:-}"
  printf 'ROTATE_TEMP[%s]=%q\n'     "$coin" "${ROTATE_TEMP[$coin]:-}"
  printf 'ROTATE_TRACKER[%s]=%q\n'  "$coin" "${ROTATE_TRACKER[$coin]:-}"
}
emit_rotate_phase3() {
  local coin="$1"
  printf 'ROTATE_FAIL[%s]=%q\n'     "$coin" "${ROTATE_FAIL[$coin]:-0}"
  printf 'ROTATE_POSTBAL[%s]=%q\n'  "$coin" "${ROTATE_POSTBAL[$coin]:-}"
  printf 'ROTATE_ISMINE[%s]=%q\n'   "$coin" "${ROTATE_ISMINE[$coin]:-}"
  printf 'ROTATE_POSTSIZE[%s]=%q\n' "$coin" "${ROTATE_POSTSIZE[$coin]:-}"
  printf 'ROTATE_TRACKER_AFTER[%s]=%q\n' "$coin" "${ROTATE_TRACKER_AFTER[$coin]:-}"
}
emit_combine() {
  local coin="$1"
  printf 'COMBINE_IN[%s]=%q\n'  "$coin" "${COMBINE_IN[$coin]:-0}"
  printf 'COMBINE_OUT[%s]=%q\n' "$coin" "${COMBINE_OUT[$coin]:-0}"
  printf 'ROTATE_FAIL[%s]=%q\n' "$coin" "${ROTATE_FAIL[$coin]:-0}"
}

# Run a per-coin function across coins CONCURRENTLY. Each coin is its own chain
# with its own mempool, so they must not wait on each other — one slow chain
# should never block the rest. Each coin runs in a backgrounded subshell (its
# per-batch output captured to a log file); the emitter writes that coin's result
# vars to a file the parent sources back once all finish. $1 = per-coin function,
# $2 = result emitter, rest = coins.
PARALLEL_WORKDIR=""
# Live per-coin sweep table (UTXOs total, left, txs sent, mempool, state), rendered
# in place to stderr from the workers' status files. Fixed column widths so the box
# width stays constant across repaints (cursor-up redraw). Sets SWEEP_TABLE_LINES.
SWEEP_TABLE_LINES=0
render_sweep_table() {
  local coin st total dn tx mp left stc row hdr rule
  local w_coin=4 w_tot=6 w_left=6 w_tx=4 w_mp=5 w_st=9
  local sep=" ${blue}|${nc} "
  local tot=$(( 15 + w_coin + w_tot + w_left + w_tx + w_mp + w_st ))
  printf -v rule '%*s' "$(( tot + 4 ))" ''; rule=${rule// /=}
  printf '%s%s%s\n' "$blue" "$rule" "$nc" >&2
  printf -v hdr "%-${w_coin}s${sep}%${w_tot}s${sep}%${w_left}s${sep}%${w_tx}s${sep}%${w_mp}s${sep}%-${w_st}s" \
    "COIN" "UTXOS" "LEFT" "TXS" "MEMP" "STATE"
  _box_line "$tot" "$hdr" "$tot"
  for coin in "$@"; do
    if [[ -s "${PARALLEL_WORKDIR}/${coin}.res" ]]; then
      if [[ -r "${PARALLEL_WORKDIR}/${coin}.status" ]]; then
        IFS=' ' read -r st total dn tx mp 2>/dev/null < "${PARALLEL_WORKDIR}/${coin}.status" || { total="-"; dn="-"; tx="-"; mp="-"; }
      else
        total="-"; dn="-"; tx="-"; mp="-"
      fi
      st="done"
    elif [[ -r "${PARALLEL_WORKDIR}/${coin}.status" ]]; then
      IFS=' ' read -r st total dn tx mp 2>/dev/null < "${PARALLEL_WORKDIR}/${coin}.status" || { st="?"; total="-"; dn="-"; tx="-"; mp="-"; }
    else
      st="queued"; total="-"; dn="-"; tx="-"; mp="-"
    fi
    if [[ "$total" =~ ^[0-9]+$ && "$dn" =~ ^[0-9]+$ ]]; then left=$(( total - dn )); else left="-"; fi
    case "$st" in
      done) stc="$green" ;; combining) stc="$cyan" ;; rescanning) stc="$cyan" ;; waiting) stc="$yellow" ;; *) stc="$nc" ;;
    esac
    printf -v row "%-${w_coin}s${sep}%${w_tot}s${sep}%${w_left}s${sep}%${w_tx}s${sep}%${w_mp}s${sep}${stc}%-${w_st}s${nc}" \
      "${coin^^}" "$total" "$left" "$tx" "$mp" "$st"
    _box_line "$tot" "$row" "$tot"
  done
  printf '%s%s%s\n' "$blue" "$rule" "$nc" >&2
  SWEEP_TABLE_LINES=$(( $# + 3 ))
}

run_coins_parallel() {
  local fn="$1" emit="$2"; shift 2
  local coins=("$@") coin start now elapsed total done line live_tty nlines first pids=() alive p
  PARALLEL_WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/wm-parallel-XXXXXX")"
  chmod 700 "$PARALLEL_WORKDIR" 2>/dev/null || true
  total="${#coins[@]}"
  for coin in "${coins[@]}"; do
    # Each coin runs in a backgrounded subshell. An EXIT trap makes the emitter
    # ALWAYS run (even if a transient RPC aborts the subshell under set -e) and
    # marks the coin failed on a non-zero exit, writing the result atomically so
    # the parent always sources a complete result file, never a missing one.
    (
      PARALLEL_STATUS_FILE="${PARALLEL_WORKDIR}/${coin}.status"
      trap 'wrc=$?; if [[ "$wrc" -ne 0 ]]; then ROTATE_FAIL[$coin]=1; fi; "$emit" "$coin" > "${PARALLEL_WORKDIR}/${coin}.res.part" && mv -f "${PARALLEL_WORKDIR}/${coin}.res.part" "${PARALLEL_WORKDIR}/${coin}.res"' EXIT
      "$fn" "$coin"
    ) > "${PARALLEL_WORKDIR}/${coin}.log" 2>&1 &
    pids+=("$!")
  done
  live_tty=0; [ -t 2 ] && live_tty=1
  nlines=0; first=1
  start="$(date +%s)"
  while :; do
    if [[ "$live_tty" == "1" ]]; then
      [[ "$first" == "0" ]] && printf '\033[%dA' "$nlines" >&2
      render_sweep_table "${coins[@]}"
      nlines="$SWEEP_TABLE_LINES"; first=0
    else
      done=0
      for coin in "${coins[@]}"; do [[ -s "${PARALLEL_WORKDIR}/${coin}.res" ]] && done=$(( done + 1 )); done
      now="$(date +%s)"; printf '       %s[%s/%s] %ss done%s\n' "$cyan" "$done" "$total" "$(( now - start ))" "$nc" >&2
    fi
    # Break when OUR workers are all done — ignore any unrelated background job
    # (e.g. the regtest auto-miner), which jobs -rp would otherwise keep us on.
    alive=0
    for p in "${pids[@]}"; do kill -0 "$p" 2>/dev/null && alive=1; done
    [[ "$alive" == "0" ]] && break
    sleep 1
  done
  # Final repaint so the table shows every coin's end state.
  if [[ "$live_tty" == "1" ]]; then
    [[ "$first" == "0" ]] && printf '\033[%dA' "$nlines" >&2
    render_sweep_table "${coins[@]}"
  fi
  wait "${pids[@]}" 2>/dev/null || true   # only our coin workers, not any auto-miner job
  local anyfail=0
  for coin in "${coins[@]}"; do
    if [[ -s "${PARALLEL_WORKDIR}/${coin}.res" ]]; then
      # shellcheck disable=SC1090
      . "${PARALLEL_WORKDIR}/${coin}.res"
    else
      ROTATE_FAIL[$coin]=1
      warn "${coin}: no result from the parallel run (detail: ${PARALLEL_WORKDIR}/${coin}.log)"
    fi
    [[ "${ROTATE_FAIL[$coin]:-0}" == "1" ]] && anyfail=1
  done
  # Clean the scratch dir on a fully clean run; keep it (per-coin logs) on failure.
  [[ "$anyfail" == "0" ]] && rm -rf "$PARALLEL_WORKDIR"
}

# Show each coin's coinbase tracker address and confirm the SAME address is still
# ismine on the fresh "" after the rotation — so the operator sees the tracker
# (where coinbase lands / MPOS pays from) is preserved across the swap.
render_tracker_table() {
  local coin sep total boxw rule hdr row addr aft
  local w_coin=4 w_addr=7 w_b=6 w_a=6 w_m=5
  for coin in "$@"; do
    addr="${ROTATE_TRACKER[$coin]:--}"
    (( ${#coin} > w_coin )) && w_coin=${#coin}
    (( ${#addr} > w_addr )) && w_addr=${#addr}
  done
  printf '\n%sTracker address — before vs after%s\n' "$cyan" "$nc"
  sep=" ${blue}|${nc} "
  total=$(( 12 + w_coin + w_addr + w_b + w_a + w_m ))
  boxw=$(( total + 4 )); printf -v rule '%*s' "$boxw" ''; rule=${rule// /=}
  printf '%s%s%s\n' "$blue" "$rule" "$nc"
  printf -v hdr "%-${w_coin}s${sep}%-${w_addr}s${sep}%-${w_b}s${sep}%-${w_a}s${sep}%-${w_m}s" "COIN" "TRACKER" "BEFORE" "AFTER" "MATCH"
  _boxln_out "$total" "$hdr" "$total"
  for coin in "$@"; do
    addr="${ROTATE_TRACKER[$coin]:--}"
    if [[ "${ROTATE_FAIL[$coin]:-0}" == "1" ]]; then
      printf -v row "%-${w_coin}s${sep}%-${w_addr}s${sep}%-${w_b}s${sep}%-${w_a}s${sep}${red}%-${w_m}s${nc}" "${coin^^}" "$addr" "ismine" "-" "FAIL"
    elif [[ "${ROTATE_TRACKER_AFTER[$coin]:-false}" == "true" ]]; then
      printf -v row "%-${w_coin}s${sep}%-${w_addr}s${sep}%-${w_b}s${sep}%-${w_a}s${sep}${green}%-${w_m}s${nc}" "${coin^^}" "$addr" "ismine" "ismine" "yes"
    else
      printf -v row "%-${w_coin}s${sep}%-${w_addr}s${sep}%-${w_b}s${sep}${red}%-${w_a}s${nc}${sep}${red}%-${w_m}s${nc}" "${coin^^}" "$addr" "ismine" "NO" "NO"
    fi
    _boxln_out "$total" "$row" "$total"
  done
  printf '%s%s%s\n' "$blue" "$rule" "$nc"
}

# Plan, confirm once, then run the three rotation phases across the coin set with
# a single mining-pause window (when PAUSE_MINING is on). Phases 1 and 3 (the
# long, mempool-throttled sweeps) run all coins concurrently; phase 2 (the swap)
# stays sequential inside the one pause window.
run_rotation() {
  local coins=("$@") coin _ay
  ROTATION_RAN=0
  PLAN_OK=(); PLAN_SP=(); PLAN_UTXOS=(); PLAN_TXNS=(); PLAN_FEE=(); PLAN_HISTTX=(); PLAN_WDAT=(); PLAN_RESCAN=()
  for coin in "${coins[@]}"; do rotate_plan_coin "$coin"; done
  render_rotation_plan "${coins[@]}"

  if ! $SEND; then
    printf '\n%sDry run — no funds moved, no wallet swapped.%s\n' "$yellow" "$nc"
    if $PAUSE_MINING; then
      printf '%sLive run would pause mining for the swap:%s systemctl stop %s\n' "$cyan" "$nc" "$MINING_UNITS"
    else
      printf '%sLive run would NOT pause mining%s (scoped rescan covers the swap window).\n' "$cyan" "$nc"
    fi
    return 0
  fi

  printf '\n'
  if ! confirm_batch "rotate" "${coins[@]}"; then
    warn "aborted; no funds moved"
    return 0
  fi

  _ay="$ASSUME_YES"; ASSUME_YES=true
  ROTATE_TEMP=(); ROTATE_DESCFILE=(); ROTATE_PREBAL=(); ROTATE_REFADDR=(); ROTATE_FAIL=(); ROTATE_TRACKER=(); ROTATE_TRACKER_AFTER=()

  say "rotating ${#coins[@]} coin(s): ${coins[*]}"
  auto_mine_start "${coins[@]}"
  say "1/3  combine funds into temp wallets (parallel — each coin on its own chain)"
  run_coins_parallel rotate_phase1_coin emit_rotate_phase1 "${coins[@]}"

  # The swap stays sequential inside one pause window. Resume mining via an EXIT
  # trap too, so an unexpected abort mid-swap can never leave mining stopped.
  if $PAUSE_MINING; then pause_mining; trap 'resume_mining || true' EXIT; fi
  say "2/3  swap wallet.dat + scoped re-import"
  for coin in "${coins[@]}"; do rotate_phase2_coin "$coin"; done
  if $PAUSE_MINING; then trap - EXIT; resume_mining; fi

  say "3/3  restore funds + verify (parallel)"
  run_coins_parallel rotate_phase3_coin emit_rotate_phase3 "${coins[@]}"
  auto_mine_stop

  print_rotation_summary "${coins[@]}"
  render_tracker_table "${coins[@]}"
  ASSUME_YES="$_ay"
  ROTATION_RAN=1
}

# ---------------------------------------------------------------------------
# Combine (consolidate): merge many of "" 's UTXOs into fewer outputs, in place.
# Defragments the wallet so sends stay fast; the funds stay in "" and the wallet
# file keeps its history — to actually shrink wallet.dat, use Rotate.
# ---------------------------------------------------------------------------

COMBINE_PLAN_HDR=0
declare -A COMBINE_IN=()   # coin -> spendable UTXO count before combine
declare -A COMBINE_OUT=()  # coin -> output count after combine
# Combine-plan row cache (rendered as one aligned box, like the rotation plan).
declare -A CPLAN_OK=() CPLAN_UTXOS=() CPLAN_VALUE=() CPLAN_TXNS=() CPLAN_FEE=()
combine_plan_coin() {
  local coin="$1" utxos count value batches est_fee
  CPLAN_OK[$coin]=0
  if ! resolve_coin_access "$coin"; then
    warn "${coin}: daemon not running; cannot plan"
    return 0
  fi
  utxos="$(rpc "$coin" -rpcwallet="" listunspent "$MIN_CONFIRMS" 9999999 2>/dev/null | jq '[.[] | select((.spendable // true) == true and (.safe // true) != false)]')"
  count="$(jq 'length' <<<"$utxos")"
  value="$(jq -r '([.[].amount] | add // 0) | (. * 1e8 | round) / 1e8' <<<"$utxos")"
  batches=$(( (count + BATCH_SIZE - 1) / BATCH_SIZE )); (( count > 0 )) || batches=0
  est_fee="$(amount8 "(($count * 148 + $batches * 44) / 1000 + $batches) * $FEE_RATE")"
  CPLAN_OK[$coin]=1
  CPLAN_UTXOS[$coin]="$count"; CPLAN_VALUE[$coin]="$value"
  if [[ "$count" -le 1 ]]; then
    CPLAN_TXNS[$coin]="0"; CPLAN_FEE[$coin]="~0"
  else
    CPLAN_TXNS[$coin]="$batches"; CPLAN_FEE[$coin]="~${est_fee}"
  fi
}

# Render the cached combine-plan rows as one blue-bordered, aligned box.
render_combine_plan() {
  local coin sep total boxw rule hdr row v
  local w_coin=4 w_utxos=5 w_value=5 w_txns=4 w_fee=7
  local planned=()
  for coin in "$@"; do
    [[ "${CPLAN_OK[$coin]:-0}" == "1" ]] || continue
    planned+=("$coin")
    (( ${#coin} > w_coin )) && w_coin=${#coin}
    v="${CPLAN_UTXOS[$coin]}"; (( ${#v} > w_utxos )) && w_utxos=${#v}
    v="${CPLAN_VALUE[$coin]}"; (( ${#v} > w_value )) && w_value=${#v}
    v="${CPLAN_TXNS[$coin]}";  (( ${#v} > w_txns ))  && w_txns=${#v}
    v="${CPLAN_FEE[$coin]}";   (( ${#v} > w_fee ))   && w_fee=${#v}
  done
  [[ "${#planned[@]}" -ge 1 ]] || return 0
  if $SEND; then printf '\n%sCombine plan%s\n' "$cyan" "$nc"
  else printf '\n%sCombine plan%s %s- Dry Run%s\n' "$cyan" "$nc" "$yellow" "$nc"; fi
  sep=" ${blue}|${nc} "
  total=$(( 12 + w_coin + w_utxos + w_value + w_txns + w_fee ))
  boxw=$(( total + 4 )); printf -v rule '%*s' "$boxw" ''; rule=${rule// /=}
  printf '%s%s%s\n' "$blue" "$rule" "$nc"
  printf -v hdr "%-${w_coin}s${sep}%${w_utxos}s${sep}%${w_value}s${sep}%${w_txns}s${sep}%${w_fee}s" \
    "COIN" "UTXOS" "VALUE" "TXNS" "EST.FEE"
  _boxln_out "$total" "$hdr" "$total"
  for coin in "${planned[@]}"; do
    printf -v row "%-${w_coin}s${sep}%${w_utxos}s${sep}%${w_value}s${sep}%${w_txns}s${sep}%${w_fee}s" \
      "${coin^^}" "${CPLAN_UTXOS[$coin]}" "${CPLAN_VALUE[$coin]}" "${CPLAN_TXNS[$coin]}" "${CPLAN_FEE[$coin]}"
    _boxln_out "$total" "$row" "$total"
  done
  printf '%s%s%s\n' "$blue" "$rule" "$nc"
}

combine_coin() {
  local coin="$1" utxos count target
  utxos="$(rpc "$coin" -rpcwallet="" listunspent "$MIN_CONFIRMS" 9999999 | jq '[.[] | select((.spendable // true) == true and (.safe // true) != false)]')"
  count="$(jq 'length' <<<"$utxos")"
  COMBINE_IN[$coin]="$count"; COMBINE_OUT[$coin]=0
  if [[ "$count" -le 1 ]]; then
    return 0
  fi
  target="$(rpc "$coin" -rpcwallet="" getnewaddress combine "${ADDRESS_TYPE[$coin]}")"
  capture_descriptors "$coin" "" >/dev/null   # back up the keychain before moving funds
  move_utxos_to_address "$coin" "" "$target" "$MIN_CONFIRMS"
  COMBINE_OUT[$coin]="$MOVED_TXS"
  logmsg "combine ${coin}: ${count} UTXO(s) (~${MOVED_VALUE}) -> ${target}; ${MOVED_TXS} output(s)"
}

# Clean end-of-run summary for combine (txids are in the run log).
print_combine_summary() {
  local coin cin cout st log sep total boxw rule hdr row
  local w_coin=4 w_utxos=5 w_out=7 w_st=6
  for coin in "$@"; do
    (( ${#coin} > w_coin )) && w_coin=${#coin}
    cin="${COMBINE_IN[$coin]:-0}"; cout="${COMBINE_OUT[$coin]:-0}"
    if [[ "${ROTATE_FAIL[$coin]:-0}" == "1" ]]; then st="FAILED"
    elif [[ "$cin" -le 1 ]]; then st="nothing to combine"; (( ${#cin} > w_utxos )) && w_utxos=${#cin}
    else st="OK"; (( ${#cin} > w_utxos )) && w_utxos=${#cin}; (( ${#cout} > w_out )) && w_out=${#cout}; fi
    (( ${#st} > w_st )) && w_st=${#st}
  done
  log="${MPOS_WALLET_UTXO_LOG:-${KEY_DUMP_BASE}/wallet-maintenance.log}"
  printf '\n%sCombine summary%s\n' "$cyan" "$nc"
  sep=" ${blue}|${nc} "
  total=$(( 9 + w_coin + w_utxos + w_out + w_st ))
  boxw=$(( total + 4 )); printf -v rule '%*s' "$boxw" ''; rule=${rule// /=}
  printf '%s%s%s\n' "$blue" "$rule" "$nc"
  printf -v hdr "%-${w_coin}s${sep}%${w_utxos}s${sep}%${w_out}s${sep}%-${w_st}s" "COIN" "UTXOS" "OUTPUTS" "STATUS"
  _boxln_out "$total" "$hdr" "$total"
  for coin in "$@"; do
    cin="${COMBINE_IN[$coin]:-0}"; cout="${COMBINE_OUT[$coin]:-0}"
    if [[ "${ROTATE_FAIL[$coin]:-0}" == "1" ]]; then
      printf -v row "%-${w_coin}s${sep}%${w_utxos}s${sep}%${w_out}s${sep}${red}%-${w_st}s${nc}" "${coin^^}" "-" "-" "FAILED"
    elif [[ "$cin" -le 1 ]]; then
      printf -v row "%-${w_coin}s${sep}%${w_utxos}s${sep}%${w_out}s${sep}%-${w_st}s" "${coin^^}" "$cin" "-" "nothing to combine"
    else
      printf -v row "%-${w_coin}s${sep}%${w_utxos}s${sep}%${w_out}s${sep}${green}%-${w_st}s${nc}" "${coin^^}" "$cin" "$cout" "OK"
    fi
    _boxln_out "$total" "$row" "$total"
  done
  printf '%s%s%s\n' "$blue" "$rule" "$nc"
  printf '\n%sDetails:%s %s\n' "$cyan" "$nc" "$log"
}

# Plan, confirm once, then combine each selected coin in place.
run_combine() {
  local coins=("$@") coin _ay
  ROTATION_RAN=0
  COMBINE_IN=(); COMBINE_OUT=(); ROTATE_FAIL=()
  CPLAN_OK=(); CPLAN_UTXOS=(); CPLAN_VALUE=(); CPLAN_TXNS=(); CPLAN_FEE=()
  for coin in "${coins[@]}"; do combine_plan_coin "$coin"; done
  render_combine_plan "${coins[@]}"
  if ! $SEND; then
    printf '\n%sDry run — no UTXOs combined.%s\n' "$yellow" "$nc"
    return 0
  fi
  printf '\n'
  if ! confirm_batch "combine" "${coins[@]}"; then
    warn "aborted; no funds moved"
    return 0
  fi
  _ay="$ASSUME_YES"; ASSUME_YES=true
  say "combining ${#coins[@]} coin(s) in parallel — each on its own chain"
  auto_mine_start "${coins[@]}"
  run_coins_parallel combine_coin emit_combine "${coins[@]}"
  auto_mine_stop
  print_combine_summary "${coins[@]}"
  ASSUME_YES="$_ay"
  ROTATION_RAN=1
}

# ---------------------------------------------------------------------------
# Rescan: re-scan the chain for each selected wallet (rescanblockchain). Moves no
# funds — refreshes the wallet's view of its balances/UTXOs. Runs all coins
# concurrently, each on its own chain.
# ---------------------------------------------------------------------------
declare -A RESCAN_TO=()   # coin -> stop height the rescan reached

rescan_coin() {
  local coin="$1" w res
  ROTATE_FAIL[$coin]=0
  w="$(active_wallet "$coin")"
  sweep_status "rescanning" "-" "-" "-" "-"
  res="$(rpc "$coin" -rpcwallet="$w" rescanblockchain 2>/dev/null)" || {
    warn "${coin}: rescanblockchain failed"; ROTATE_FAIL[$coin]=1; return 0
  }
  RESCAN_TO[$coin]="$(jq -r '.stop_height // "?"' <<<"$res" 2>/dev/null || echo '?')"
  logmsg "rescan ${coin}: rescanblockchain on '${w}' -> stop_height ${RESCAN_TO[$coin]:-?}"
}

emit_rescan() {
  local coin="$1"
  printf 'ROTATE_FAIL[%s]=%q\n' "$coin" "${ROTATE_FAIL[$coin]:-0}"
  printf 'RESCAN_TO[%s]=%q\n'   "$coin" "${RESCAN_TO[$coin]:-}"
}

print_rescan_summary() {
  local coin sep total boxw rule hdr row to w_coin=4 w_to=10 w_st=6
  for coin in "$@"; do (( ${#coin} > w_coin )) && w_coin=${#coin}; to="${RESCAN_TO[$coin]:--}"; (( ${#to} > w_to )) && w_to=${#to}; done
  printf '\n%sRescan summary%s\n' "$cyan" "$nc"
  sep=" ${blue}|${nc} "
  total=$(( 6 + w_coin + w_to + w_st ))
  boxw=$(( total + 4 )); printf -v rule '%*s' "$boxw" ''; rule=${rule// /=}
  printf '%s%s%s\n' "$blue" "$rule" "$nc"
  printf -v hdr "%-${w_coin}s${sep}%${w_to}s${sep}%-${w_st}s" "COIN" "SCANNED-TO" "STATUS"
  _boxln_out "$total" "$hdr" "$total"
  for coin in "$@"; do
    if [[ "${ROTATE_FAIL[$coin]:-0}" == "1" ]]; then
      printf -v row "%-${w_coin}s${sep}%${w_to}s${sep}${red}%-${w_st}s${nc}" "${coin^^}" "-" "FAILED"
    else
      printf -v row "%-${w_coin}s${sep}%${w_to}s${sep}${green}%-${w_st}s${nc}" "${coin^^}" "${RESCAN_TO[$coin]:--}" "OK"
    fi
    _boxln_out "$total" "$row" "$total"
  done
  printf '%s%s%s\n' "$blue" "$rule" "$nc"
}

# Rescan the selected coins' wallets concurrently. Read-only, so it ignores the
# Dry Run toggle (there is nothing to preview — it moves no funds).
run_rescan() {
  local coins=("$@")
  ROTATION_RAN=0
  ROTATE_FAIL=(); RESCAN_TO=()
  say "rescanning ${#coins[@]} wallet(s): ${coins[*]} — re-scan the chain (moves no funds)"
  run_coins_parallel rescan_coin emit_rescan "${coins[@]}"
  print_rescan_summary "${coins[@]}"
  ROTATION_RAN=1
}

declare -A ROW_CACHE=()

# Scan each "" wallet's UTXO health once into ROW_CACHE. The menu reuses this
# cache across keypresses; the caller re-scans only after a live rotation.
scan_wallets() {
  local coin
  ROW_CACHE=()
  printf 'Scanning wallets...\n' >&2
  for coin in "${COINS[@]}"; do
    ROW_CACHE[$coin]="$(status_coin_fields "$coin")"
  done
}

PICK_COINS=()
PICK_OP=""
PICK_DRY=1
PICK_OPERATION="rotate"   # "rotate" or "combine" (mutually exclusive)

# Bare-run picker (same box + Operation row as the old menu): pick which coins,
# toggle A) Dry Run (on by default), and choose the operation — B) Rotate (default)
# or C) Combine. A one-line description of the selected operation shows between the
# selection box and the Operation row. Coins toggle by number; Enter runs; q quits.
pick_coins_and_toggles() {
  local raw coin index notice="" eof any la lb lc ld le lf lg desc _val
  local -A selected=()

  while :; do
    clear_tool_screen || true
    print_tool_banner force >&2
    printf '%sREGNET WALLET MAINTENANCE for 25.2 Daemons%s\n' "$yellow" "$nc" >&2
    if [[ -n "$notice" ]]; then
      printf '\n%sSelect coin(s):%s   %s***%s %s%s%s %s***%s\n' "$white" "$nc" "$red" "$nc" "$yellow" "${notice^}" "$nc" "$red" "$nc" >&2
      notice=""
    else
      printf '\n%sSelect coin(s):%s\n' "$white" "$nc" >&2
    fi
    render_coin_table selected ROW_CACHE
    if [[ "$PICK_OPERATION" == "combine" ]]; then
      desc="Combine — merge many UTXOs into fewer outputs; defragments, but keeps the wallet's history."
    elif [[ "$PICK_OPERATION" == "rescan" ]]; then
      desc="Rescan — re-scan the chain for each selected wallet (refreshes balances/UTXOs; moves no funds)."
    elif [[ "$PICK_OPERATION" == "mine" ]]; then
      desc="Mine — mine ${MINE_BLOCKS} more blocks per coin onto its tracker (regtest only; adds coinbase to test with)."
    else
      desc="Rotate — combine, then reset to a fresh small wallet.dat (same keychain & tracker; shrinks the file)."
    fi
    printf '\n  %s%s%s\n' "$cyan" "$desc" "$nc" >&2
    [[ "$PICK_DRY" == "1" ]]              && la="A) [${orange}*${nc}] ${green}Dry Run${nc}" || la="A) [ ] Dry Run"
    [[ "$PICK_OPERATION" == "rotate" ]]  && lb="B) [${orange}*${nc}] ${green}Rotate${nc}"  || lb="B) [ ] Rotate"
    [[ "$PICK_OPERATION" == "combine" ]] && lc="C) [${orange}*${nc}] ${green}Combine${nc}" || lc="C) [ ] Combine"
    [[ "$PICK_OPERATION" == "rescan" ]]  && lf="F) [${orange}*${nc}] ${green}Rescan${nc}"  || lf="F) [ ] Rescan"
    ld="D) Mempool [${orange}${MAX_MEMPOOL}${nc}]"
    le="E) Refill [${orange}${MEMPOOL_RESUME}${nc}]"
    printf '%s---------------------- Operation ----------------------%s\n' "$cyan" "$nc" >&2
    printf '   %s     %s     %s\n' "$la" "$lb" "$lc" >&2
    printf '   %s    %s    %s\n' "$ld" "$le" "$lf" >&2
    printf '%s-------------------------------------------------------%s\n' "$cyan" "$nc" >&2
    regnet_options_box
    printf 'Enter = run | q = quit: ' >&2
    eof=0
    read_user_key raw || eof=1

    case "${raw,,}" in
      "")
        PICK_COINS=()
        for coin in "${COINS[@]}"; do
          [[ "${selected[$coin]:-0}" == "1" ]] && PICK_COINS+=("$coin")
        done
        if [[ "${#PICK_COINS[@]}" -lt 1 ]]; then
          [[ "$eof" == "1" ]] && { PICK_OP="quit"; return 0; }
          notice="select at least one coin"
        else
          PICK_OP="$PICK_OPERATION"; return 0
        fi
        ;;
      a) PICK_DRY=$(( 1 - PICK_DRY )) ;;
      b) PICK_OPERATION="rotate" ;;
      c) PICK_OPERATION="combine" ;;
      f) PICK_OPERATION="rescan" ;;
      g)
        printf '\n  %sBlocks to mine per coin%s [%s]: ' "$cyan" "$nc" "$MINE_BLOCKS" >&2
        read_user_line _val
        [[ "$_val" =~ ^[0-9]+$ ]] && MINE_BLOCKS="$_val"
        PICK_OPERATION="mine"
        ;;
      d)
        printf '\n  %sMempool cap — pause sending at this many txs%s [%s]: ' "$cyan" "$nc" "$MAX_MEMPOOL" >&2
        read_user_line _val
        if [[ "$_val" =~ ^[0-9]+$ ]]; then MAX_MEMPOOL="$_val"
        elif [[ -n "$_val" ]]; then notice="mempool cap must be a whole number"; fi
        ;;
      e)
        printf '\n  %sRefill — resume sending when it drains to%s [%s]: ' "$cyan" "$nc" "$MEMPOOL_RESUME" >&2
        read_user_line _val
        if [[ "$_val" =~ ^[0-9]+$ ]]; then
          if (( MAX_MEMPOOL > 0 && _val >= MAX_MEMPOOL )); then
            notice="refill (${_val}) must be below the mempool cap (${MAX_MEMPOOL})"
          else
            MEMPOOL_RESUME="$_val"
          fi
        elif [[ -n "$_val" ]]; then notice="refill must be a whole number"; fi
        ;;
      q) PICK_OP="quit"; return 0 ;;
      0|all)
        any=0
        for coin in "${COINS[@]}"; do [[ "${selected[$coin]:-0}" != "1" ]] && any=1; done
        for coin in "${COINS[@]}"; do selected[$coin]="$any"; done
        ;;
      [1-6])
        index=$((raw - 1))
        coin="${COINS[$index]}"
        if [[ "${selected[$coin]:-0}" == "1" ]]; then selected[$coin]=0; else selected[$coin]=1; fi
        ;;
      *)
        notice="enter 1-6, 0, A, B, C, D, E, F, G, or q"
        ;;
    esac
  done
}

main() {
  require_deps
  require_root_for_key_ops
  guard_main_containers

  if [[ "$ACTION" == "status" ]]; then
    status_all
    return
  fi

  # A bare run in a terminal (no --coin): the live coin + options menu, looped.
  if [[ "$COIN_SELECT_EXPLICIT" == "0" && -t 0 ]]; then
    local _dummy
    scan_wallets
    while :; do
      pick_coins_and_toggles
      [[ "$PICK_OP" == "quit" ]] && break
      if [[ "$PICK_DRY" == "1" ]]; then SEND=false; else SEND=true; fi
      if [[ "$PICK_OP" == "combine" ]]; then run_combine "${PICK_COINS[@]}"
      elif [[ "$PICK_OP" == "rescan" ]]; then run_rescan "${PICK_COINS[@]}"
      elif [[ "$PICK_OP" == "mine" ]]; then run_mine "${PICK_COINS[@]}"
      else run_rotation "${PICK_COINS[@]}"; fi
      printf '\n%sPress Enter to return to the menu, or q to quit...%s' "$cyan" "$nc" >&2
      _dummy=""
      read_user_key _dummy || true
      printf '\n' >&2
      [[ "${_dummy,,}" == "q" ]] && break
      [[ "$ROTATION_RAN" == "1" ]] && scan_wallets
    done
    return
  fi

  # Non-interactive: act on the selected coins. Require an explicit --coin/--all
  # here so a piped/cron run can never silently act on all six.
  [[ "$COIN_SELECT_EXPLICIT" == "1" ]] || die "${ACTION} needs --coin/--all, or run in a terminal for the menu"
  local _coins=()
  mapfile -t _coins < <(selected_coins)
  if [[ "$ACTION" == "combine" ]]; then run_combine "${_coins[@]}"
  elif [[ "$ACTION" == "rescan" ]]; then run_rescan "${_coins[@]}"
  elif [[ "$ACTION" == "mine" ]]; then run_mine "${_coins[@]}"
  else run_rotation "${_coins[@]}"; fi
}

# ====================== REGTEST OVERRIDES (regnet twin) ======================
# This is the REGTEST twin of wallet-maintenance.sh: the menu, boxes, tracker
# table, live sweep table, and rotate/combine/rescan mechanic above are identical.
# The only differences are below — it runs against throwaway -regtest daemons (one
# per coin, named rgw-<coin>) that it spins up and seeds with coinbase here, never
# the live pool. Redefining these functions after the originals makes them win.
RG_PREFIX="rgw"
REGTEST_IMAGE_HUB="${MPOS_DOCKER_HUB:-sidgrip}"
REGTEST_IMAGE_TAG="${MPOS_IMAGE_TAG:-latest}"
MINE_BLOCKS="${MPOS_REGTEST_MINE_BLOCKS:-50}"   # G) Mine Blocks default count
PAUSE_MINING=false   # regtest has no eloipool/mergeminer to pause (also keeps our EXIT teardown trap)

rpc() {
  local coin="$1"; shift
  docker exec --user 0:0 "${RG_PREFIX}-${coin}" "${CLI_NAME[$coin]}" -regtest -datadir=/rt -rpcuser=x -rpcpassword=x "$@"
}
container_sh() {
  local coin="$1"; shift
  docker exec --user 0:0 "${RG_PREFIX}-${coin}" sh -c "$*"
}
resolve_coin_access() {
  local coin="$1"
  [[ -n "${COIN_MODE[$coin]:-}" ]] && return 0
  docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "${RG_PREFIX}-${coin}" || return 1
  COIN_MODE[$coin]="docker"; COIN_CONTAINER[$coin]="${RG_PREFIX}-${coin}"
  COIN_CLIBIN[$coin]="${CLI_NAME[$coin]}"; COIN_DATADIR[$coin]="/rt"; COIN_HOSTDIR[$coin]=""
  return 0
}
refuse_regtest_container_in_main() { :; }   # this IS the regtest tool
pause_mining()  { :; }
resume_mining() { :; }

# --- single-core regtest auto-miner (drains the mempool so sweeps confirm) ----
# Nothing mines a throwaway regtest chain, so the throttled combine/rotate sweeps
# would wait forever for the mempool to drain (wait_for_mempool). While a sweep
# runs, this mines one block per coin whenever that coin's mempool is non-empty:
# one low-priority, round-robin process — a single core's worth of work — that
# keeps each chain moving. Coinbase goes to a throwaway 'rgmine' wallet so "" and
# the rotation temp wallet stay clean; mocktime advances per coin so block
# timestamps stay strictly increasing.
REGTEST_MINER_PID=""
REGTEST_MINER_STOP=""

regtest_miner_address() {
  local coin="$1" a
  rpc "$coin" loadwallet rgmine >/dev/null 2>&1 \
    || rpc "$coin" createwallet rgmine >/dev/null 2>&1 || true
  a="$(rpc "$coin" -rpcwallet=rgmine getnewaddress 2>/dev/null || true)"
  printf '%s' "$a"
}

regtest_miner_loop() {
  local coins=("$@") coin addr mp besthash t did draining=0
  local -A maddr=() mt=()
  renice -n 19 -p "$BASHPID" >/dev/null 2>&1 || true   # single, low-priority core
  for coin in "${coins[@]}"; do
    maddr[$coin]="$(regtest_miner_address "$coin")"
    besthash="$(rpc "$coin" getbestblockhash 2>/dev/null || true)"
    # Base mocktime on the tip's time so blocks stay > median-time-past. On a
    # failed read jq emits nothing (the '// N' default never fires on empty
    # stdin), so guard for a real number and fall back to wall-clock now — which
    # is always above the seeded chain time, never the epoch-0 that "" + 60 = 60
    # would wedge the miner at.
    t="$(rpc "$coin" getblockheader "$besthash" 2>/dev/null | jq -r '.time // empty' 2>/dev/null || true)"
    [[ "$t" =~ ^[0-9]+$ ]] || t="$(date +%s)"
    mt[$coin]=$(( t + 60 ))
  done
  # Mine on demand until signalled to stop, then drain whatever is left so every
  # combine/rotate tx confirms before we hand control back.
  while :; do
    [[ -f "$REGTEST_MINER_STOP" ]] && draining=1
    did=0
    for coin in "${coins[@]}"; do
      addr="${maddr[$coin]}"
      # Re-resolve if the one-shot fetch came back empty (transient RPC blip) so
      # a coin is never stranded unmined; getnewaddress on rgmine is idempotent.
      [[ -n "$addr" ]] || { addr="$(regtest_miner_address "$coin")"; maddr[$coin]="$addr"; }
      [[ -n "$addr" ]] || continue
      mp="$(get_mempool_count "$coin")"
      if [[ "$mp" -gt 0 ]]; then
        rpc "$coin" setmocktime "${mt[$coin]}" >/dev/null 2>&1 || true
        rpc "$coin" generatetoaddress 1 "$addr" >/dev/null 2>&1 || true
        mt[$coin]=$(( ${mt[$coin]} + 60 )); did=1
      fi
    done
    [[ "$draining" == "1" && "$did" == "0" ]] && break
    sleep 1
  done
}

auto_mine_start() {
  local coins=("$@")
  REGTEST_MINER_STOP="${TMPDIR:-/tmp}/wm-regtest-mine-stop.$$"
  rm -f "$REGTEST_MINER_STOP" 2>/dev/null || true
  say "regtest auto-miner on (single core) — mining to confirm batches as they send"
  ( regtest_miner_loop "${coins[@]}" ) >/dev/null 2>&1 &
  REGTEST_MINER_PID=$!
}

auto_mine_stop() {
  [[ -n "${REGTEST_MINER_PID:-}" ]] || return 0
  touch "$REGTEST_MINER_STOP" 2>/dev/null || true   # signal: drain the rest, then exit
  wait "$REGTEST_MINER_PID" 2>/dev/null || true
  rm -f "$REGTEST_MINER_STOP" 2>/dev/null || true
  REGTEST_MINER_PID=""
}

regtest_teardown() {
  local c
  auto_mine_stop 2>/dev/null || true
  for c in "${COINS[@]}"; do docker rm -f "${RG_PREFIX}-${c}" >/dev/null 2>&1 || true; done
}

# ---- shared block-progress live table (spin-up/seed AND G) Mine Blocks) ----
BLK_WORKDIR=""
BLK_TABLE_LINES=0

# A backgrounded per-coin job writes its progress here; the parent only reads it.
blk_status() {  # $1=state $2=target-blocks $3=mined-blocks
  [[ -n "${BLK_STATUS_FILE:-}" ]] || return 0
  printf '%s %s %s\n' "$1" "$2" "$3" > "${BLK_STATUS_FILE}.t" 2>/dev/null \
    && mv -f "${BLK_STATUS_FILE}.t" "${BLK_STATUS_FILE}" 2>/dev/null || true
}

render_block_table() {
  local coin sep total boxw rule hdr row st tgt mined stc blk
  local w_coin=4 w_blk=13 w_st=8
  sep=" ${blue}|${nc} "
  total=$(( 6 + w_coin + w_blk + w_st ))
  boxw=$(( total + 4 )); printf -v rule '%*s' "$boxw" ''; rule=${rule// /=}
  printf '%s%s%s\n' "$blue" "$rule" "$nc" >&2
  printf -v hdr "%-${w_coin}s${sep}%${w_blk}s${sep}%-${w_st}s" "COIN" "BLOCKS" "STATE"
  _box_line "$total" "$hdr" "$total"
  for coin in "$@"; do
    if [[ -r "${BLK_WORKDIR}/${coin}.st" ]]; then
      IFS=' ' read -r st tgt mined 2>/dev/null < "${BLK_WORKDIR}/${coin}.st" || { st="?"; tgt="-"; mined="-"; }
    else st="queued"; tgt="-"; mined="-"; fi
    if [[ "${mined:-}" =~ ^[0-9]+$ && "${tgt:-}" =~ ^[0-9]+$ ]]; then blk="${mined}/${tgt}"; else blk="-"; fi
    case "$st" in
      ready|done) stc="$green" ;; seeding|mining) stc="$cyan" ;; starting) stc="$yellow" ;; FAILED) stc="$red" ;; *) stc="$nc" ;;
    esac
    printf -v row "%-${w_coin}s${sep}%${w_blk}s${sep}${stc}%-${w_st}s${nc}" "${coin^^}" "$blk" "$st"
    _box_line "$total" "$row" "$total"
  done
  printf '%s%s%s\n' "$blue" "$rule" "$nc" >&2
  BLK_TABLE_LINES=$(( $# + 3 ))
}

# Run a per-coin block job concurrently with a live in-place table. Display-only —
# the daemons persist (docker -d), so there is no result to collect.
run_block_jobs() {
  local fn="$1"; shift
  local coins=("$@") c live_tty=0 first=1 nlines=0
  [ -t 2 ] && live_tty=1
  BLK_WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/wm-blk-XXXXXX")"
  for c in "${coins[@]}"; do
    ( BLK_STATUS_FILE="${BLK_WORKDIR}/${c}.st"; "$fn" "$c" ) > "${BLK_WORKDIR}/${c}.log" 2>&1 &
  done
  while :; do
    if [[ "$live_tty" == "1" ]]; then
      [[ "$first" == "0" ]] && printf '\033[%dA' "$nlines" >&2
      render_block_table "${coins[@]}"; nlines="$BLK_TABLE_LINES"; first=0
    else
      local rdy=0
      for c in "${coins[@]}"; do [[ -r "${BLK_WORKDIR}/${c}.st" ]] && grep -qE '^(ready|done)' "${BLK_WORKDIR}/${c}.st" 2>/dev/null && rdy=$(( rdy + 1 )); done
      printf '       %s[%s/%s] ready%s\n' "$cyan" "$rdy" "${#coins[@]}" "$nc" >&2
    fi
    [[ -z "$(jobs -rp)" ]] && break
    sleep 1
  done
  if [[ "$live_tty" == "1" && "$first" == "0" ]]; then printf '\033[%dA' "$nlines" >&2; render_block_table "${coins[@]}"; fi
  wait 2>/dev/null || true
  rm -rf "$BLK_WORKDIR"
}

# Spin up + seed one coin's regtest daemon (reports block progress to the table).
regtest_up_one() {
  local coin="$1" img track mt chunks i mined=0 tgt name="${RG_PREFIX}-$1"
  chunks=$(( (${COINBASE_MATURITY[$coin]:-100} + 60) / 50 + 1 )); tgt=$(( chunks * 50 ))
  blk_status "starting" "$tgt" 0
  img="${REGTEST_IMAGE_HUB}/${DAEMON_NAME[$coin]%d}:${REGTEST_IMAGE_TAG}"
  docker rm -f "$name" >/dev/null 2>&1 || true
  docker run -d --rm --name "$name" --user 0:0 --entrypoint sh "$img" \
    -c "mkdir -p /rt && exec /usr/local/bin/${DAEMON_NAME[$coin]} -regtest -datadir=/rt -rpcuser=x -rpcpassword=x -server -fallbackfee=0.0002 -printtoconsole=0 -rpcallowip=127.0.0.1" >/dev/null 2>&1 || {
      blk_status "FAILED" "$tgt" 0; warn "${coin}: could not start regtest daemon (image ${img})"; return 1; }
  for i in $(seq 1 40); do rpc "$coin" getblockcount >/dev/null 2>&1 && break; sleep 1; done
  rpc "$coin" getblockcount >/dev/null 2>&1 || { blk_status "FAILED" "$tgt" 0; warn "${coin}: regtest daemon did not come up"; return 1; }
  rpc "$coin" createwallet "" >/dev/null 2>&1 || rpc "$coin" loadwallet "" >/dev/null 2>&1 || true
  track="$(rpc "$coin" -rpcwallet="" getnewaddress tracker 2>/dev/null)"
  blk_status "seeding" "$tgt" 0
  mt=1600000000
  for i in $(seq 1 "$chunks"); do
    rpc "$coin" setmocktime "$mt" >/dev/null 2>&1
    rpc "$coin" generatetoaddress 50 "$track" >/dev/null 2>&1
    mined=$(( mined + 50 )); mt=$(( mt + 30000 ))
    blk_status "seeding" "$tgt" "$mined"
  done
  rpc "$coin" setmocktime "$mt" >/dev/null 2>&1
  blk_status "ready" "$tgt" "$mined"
  logmsg "regtest ${coin}: daemon up; seeded ${mined} coinbase blocks on tracker ${track}"
}
regtest_setup_all() {
  say "spinning up + seeding regtest daemons (one per coin) — live status below:"
  run_block_jobs regtest_up_one "${COINS[@]}"
  say "regtest daemons ready."
}

# G) Mine Blocks — mine MINE_BLOCKS more blocks per selected coin onto its coinbase
# tracker (regtest only), advancing mocktime so timestamps stay spread out.
mine_coin() {
  local coin="$1" w track tip mt mined=0 left chunk
  w="$(active_wallet "$coin")"
  track="$(rpc "$coin" -rpcwallet="$w" listunspent 1 9999999 2>/dev/null | jq -r 'if length>0 then (group_by(.address)|max_by(length)|.[0].address) else empty end' 2>/dev/null || true)"
  [[ -n "$track" ]] || track="$(rpc "$coin" -rpcwallet="$w" getnewaddress 2>/dev/null)"
  # On a failed tip read jq emits nothing (its '// N' default never fires on empty
  # stdin), so guard for a real number and fall back to wall-clock now rather than
  # the epoch-0 that an empty "" + 600 would collapse to.
  tip="$(rpc "$coin" getblockheader "$(rpc "$coin" getbestblockhash 2>/dev/null)" 2>/dev/null | jq -r '.time // empty' 2>/dev/null || true)"
  [[ "$tip" =~ ^[0-9]+$ ]] || tip="$(date +%s)"
  mt=$(( tip + 600 )); left="$MINE_BLOCKS"
  blk_status "mining" "$MINE_BLOCKS" 0
  while (( left > 0 )); do
    chunk=$(( left > 50 ? 50 : left ))
    rpc "$coin" setmocktime "$mt" >/dev/null 2>&1
    rpc "$coin" generatetoaddress "$chunk" "$track" >/dev/null 2>&1 || { blk_status "FAILED" "$MINE_BLOCKS" "$mined"; return 0; }
    mined=$(( mined + chunk )); left=$(( left - chunk )); mt=$(( mt + 60000 ))
    blk_status "mining" "$MINE_BLOCKS" "$mined"
  done
  blk_status "done" "$MINE_BLOCKS" "$mined"
  logmsg "mine ${coin}: +${mined} blocks to ${track}"
}
# REGNET-only options shown in their own orange-bordered box below the Operation
# block, with "REGNET" centered (like "Operation"). Currently: G) Mine Blocks.
regnet_options_box() {
  local total=55 title="REGNET" lg mvis pad tl tr ld rd bot
  if [[ "$PICK_OPERATION" == "mine" ]]; then
    lg="G) [${orange}*${nc}] ${green}Mine${nc} [${orange}${MINE_BLOCKS}${nc}]"
  else
    lg="G) [ ] Mine [${orange}${MINE_BLOCKS}${nc}]"
  fi
  mvis=$(( 14 + ${#MINE_BLOCKS} ))                          # visible width of "G) [x] Mine [N]"
  tl=$(( (total - ${#title} - 2) / 2 )); tr=$(( total - ${#title} - 2 - tl ))
  printf -v ld '%*s' "$tl" ''; ld="${ld// /=}"
  printf -v rd '%*s' "$tr" ''; rd="${rd// /=}"
  printf -v bot '%*s' "$total" ''; bot="${bot// /=}"
  printf '%s%s %s %s%s\n' "$orange" "$ld" "$title" "$rd" "$nc" >&2     # ===== REGNET =====
  pad=$(( total - 4 - mvis )); (( pad < 0 )) && pad=0
  printf '%s=%s %s%*s %s=%s\n' "$orange" "$nc" "$lg" "$pad" "" "$orange" "$nc" >&2
  printf '%s%s%s\n' "$orange" "$bot" "$nc" >&2
}

# G) Mine — mine MINE_BLOCKS more blocks per selected coin in the background and
# refresh the Select coins table live as the blocks land (no extra tables below).
run_mine() {
  local coins=("$@") c
  ROTATION_RAN=0
  local -A msel=(); for c in "${coins[@]}"; do msel[$c]=1; done
  for c in "${coins[@]}"; do ( mine_coin "$c" ) >/dev/null 2>&1 & done
  while :; do
    scan_wallets >/dev/null 2>&1
    clear_tool_screen || true
    print_tool_banner force >&2
    printf '%sREGNET WALLET MAINTENANCE for 25.2 Daemons%s\n' "$yellow" "$nc" >&2
    printf '\n%sMining %s block(s) per coin onto its tracker — live:%s\n\n' "$cyan" "$MINE_BLOCKS" "$nc" >&2
    render_coin_table msel ROW_CACHE
    [[ -z "$(jobs -rp)" ]] && break
    sleep 1
  done
  printf '\n%smined %s block(s) per coin.%s\n' "$green" "$MINE_BLOCKS" "$nc" >&2
  ROTATION_RAN=1
}

trap regtest_teardown EXIT
regtest_setup_all
main
exit "$?"
}
