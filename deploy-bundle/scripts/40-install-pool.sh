#!/usr/bin/env bash
# Install the eloipool stratum + merged-mine-proxy onto the MPOS install
# root. Uses the eloipool tree from $ELIOPOOL_TREE so we don't fork it.
# MPOS-specific bits we add on top:
#   - authentication/mpos.py (validates against pool_worker table)
#   - testnet-flavoured config rendered from templates/
#   - coinbaser shim (defaults to single-output to the pool tracker addr)
set -euo pipefail

say() { printf '\033[1;33m   %s\033[0m\n' "$*"; }
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib-apt.sh"

POOL_ROOT="${MPOS_INSTALL_ROOT}/eloipool"
VENV="${MPOS_INSTALL_ROOT}/venv"
LOG_POOL="${MPOS_LOG_ROOT}/pool"
CONFIG_DIR="${MPOS_INSTALL_ROOT}/config"
MPOS_STRATUM_PORT="${MPOS_STRATUM_PORT:-3334}"
GO_SHARE_LOG_PATH="${GO_SHARE_LOG_PATH:-${LOG_POOL}/shares.log}"
mkdir -p "$LOG_POOL" "${MPOS_INSTALL_ROOT}/bin" "$CONFIG_DIR"
chown -R blakestream-mpos:blakestream-mpos "$LOG_POOL"

if [ -f "${ELIOPOOL_TREE}/go.mod" ] && [ -d "${ELIOPOOL_TREE}/cmd/eloipool" ]; then
    say "detected Go eloipool tree at ${ELIOPOOL_TREE}"
    say "syncing Go eloipool tree to ${POOL_ROOT}"
    mkdir -p "$POOL_ROOT"
    rsync -a --delete --exclude='__pycache__' --exclude='*.pyc' \
        "${ELIOPOOL_TREE}/" "${POOL_ROOT}/"

    if ! command -v go >/dev/null 2>&1; then
        if command -v apt-get >/dev/null 2>&1; then
            wait_for_apt_locks
            apt-get update -qq
            wait_for_apt_locks
            DEBIAN_FRONTEND=noninteractive apt-get install -y golang-go >/dev/null
        else
            echo "go toolchain is required to build Go eloipool" >&2
            exit 1
        fi
    fi

    say "building Go eloipool and merged-mine-proxy"
    (cd "$POOL_ROOT" && go test ./... && CGO_ENABLED=0 go build -trimpath -o "${MPOS_INSTALL_ROOT}/bin/eloipool-go" ./cmd/eloipool)
    (cd "$POOL_ROOT" && CGO_ENABLED=0 go build -trimpath -o "${MPOS_INSTALL_ROOT}/bin/merged-mine-proxy-go" ./cmd/merged-mine-proxy)
    chmod 755 "${MPOS_INSTALL_ROOT}/bin/eloipool-go" "${MPOS_INSTALL_ROOT}/bin/merged-mine-proxy-go"

    NODE_RPC_USER="${MPOS_NODE_RPC_USER:-blakestream}"
    NODE_RPC_PASS="${MPOS_NODE_RPC_PASS:-blakestream-testnet}"

    rpc_call() {
        local port="$1" method="$2" params="${3:-[]}"
        curl -sS --max-time 10 -u "${NODE_RPC_USER}:${NODE_RPC_PASS}" \
            --data "{\"jsonrpc\":\"1.0\",\"id\":\"deploy\",\"method\":\"${method}\",\"params\":${params}}" \
            -H 'content-type: text/plain' \
            "http://127.0.0.1:${port}/" 2>/dev/null || true
    }

    rpc_success() {
        python3 -c 'import json,sys
try:
    data=json.load(sys.stdin)
except Exception:
    sys.exit(1)
sys.exit(0 if data.get("error") is None and data.get("result") is not None else 1)'
    }

    ensure_default_wallet_loaded() {
        local port="$1" resp
        resp=$(rpc_call "$port" getwalletinfo '[]')
        if printf '%s' "$resp" | rpc_success; then
            return 0
        fi
        resp=$(rpc_call "$port" loadwallet '[""]')
        if ! printf '%s' "$resp" | rpc_success; then
            resp=$(rpc_call "$port" createwallet '[""]')
        fi
        if ! printf '%s' "$resp" | rpc_success; then
            echo "failed to load or create the default wallet on RPC port ${port}: ${resp}" >&2
            return 1
        fi
    }

    get_address() {
        local port="$1" label="$2" address_type="${3:-bech32}"
        local resp addr
        ensure_default_wallet_loaded "$port" || return 1
        resp=$(rpc_call "$port" getnewaddress "[\"${label}\",\"${address_type}\"]")
        addr=$(printf '%s' "$resp" | sed -n 's/.*"result":"\([^"]*\)".*/\1/p')
        if [ -n "$addr" ]; then
            printf '%s' "$addr"
            return 0
        fi
        resp=$(rpc_call "$port" getnewaddress "[\"${label}\"]")
        addr=$(printf '%s' "$resp" | sed -n 's/.*"result":"\([^"]*\)".*/\1/p')
        printf '%s' "$addr"
    }

    if [ -z "${MPOS_TRACKER_ADDR:-}" ]; then
        say "asking blakecoind for a fresh testnet tracker address"
        MPOS_TRACKER_ADDR=$(get_address 29332 "pool-tracker" bech32)
        [ -n "$MPOS_TRACKER_ADDR" ] || { echo "failed to obtain tracker address" >&2; exit 1; }
    fi
    say "tracker = ${MPOS_TRACKER_ADDR}"

    declare -A AUX_RPC_PORT=(
        [bbtc]=29112
        [elt]=26852
        [lit]=32004
        [pho]=28998
        [umo]=29738
    )
    declare -A AUX_ADDR
    for sym in bbtc elt lit pho umo; do
        var="MPOS_AUX_ADDR_${sym^^}"
        if [ -n "${!var:-}" ]; then
            AUX_ADDR[$sym]="${!var}"
            continue
        fi
        address_type="bech32"
        if [ "$sym" = "bbtc" ]; then
            address_type="legacy"
        fi
        say "asking ${sym} daemon for an aux payout address"
        AUX_ADDR[$sym]=$(get_address "${AUX_RPC_PORT[$sym]}" "pool-aux" "${address_type}")
        [ -n "${AUX_ADDR[$sym]}" ] || { echo "failed to obtain ${sym} aux address" >&2; exit 1; }
    done

    SECRET_FILE="${MPOS_INSTALL_ROOT}/.mmp-secret"
    if [ ! -s "$SECRET_FILE" ]; then
        head -c 16 /dev/urandom | xxd -p -c 256 | head -c 32 > "$SECRET_FILE"
        chmod 600 "$SECRET_FILE"
    fi
    MMP_SECRET=$(cat "$SECRET_FILE")

    LIST="${MPOS_INSTALL_ROOT}/.aux-list"
    {
        for sym in bbtc elt lit pho umo; do
            printf '%s|%s|%d\n' "$sym" "${AUX_ADDR[$sym]}" "${AUX_RPC_PORT[$sym]}"
        done
    } > "$LIST"

    MMP_CONFIG="${CONFIG_DIR}/merged-mine-proxy.json"
    say "writing merged-mine-proxy config"
    MMP_SECRET="$MMP_SECRET" \
    NODE_RPC_USER="$NODE_RPC_USER" \
    NODE_RPC_PASS="$NODE_RPC_PASS" \
    LOG_POOL="$LOG_POOL" \
    python3 - "$LIST" "$MMP_CONFIG" <<'PY'
import json
import os
import sys
from urllib.parse import quote

aux_urls = []
payouts = []
names = []
for line in open(sys.argv[1], "r", encoding="utf-8"):
    sym, addr, port = line.strip().split("|")
    names.append(sym.upper())
    aux_urls.append("http://%s:%s@127.0.0.1:%s/" % (
        quote(os.environ["NODE_RPC_USER"], safe=""),
        quote(os.environ["NODE_RPC_PASS"], safe=""),
        port,
    ))
    payouts.append(addr)

cfg = {
    "worker_port": 19335,
    "parent_urls": ["http://auxpow:%s@127.0.0.1:19334/" % quote(os.environ["MMP_SECRET"], safe="")],
    "aux_urls": aux_urls,
    "aux_payout_addresses": payouts,
    "aux_chain_names": names,
    "merkle_size": 16,
    "rewrite_target": 32,
    "log_file": os.path.join(os.environ["LOG_POOL"], "mmp.log"),
}
with open(sys.argv[2], "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2, sort_keys=True)
    f.write("\n")
PY
    chown root:blakestream-mpos "$CONFIG_DIR" "$MMP_CONFIG"
    chmod 750 "$CONFIG_DIR"
    chmod 640 "$MMP_CONFIG"

    MMP_READY_CHECK="${MPOS_INSTALL_ROOT}/bin/check-mmp-ready.py"
    cat > "$MMP_READY_CHECK" <<'PY'
#!/usr/bin/env python3
import json
import sys
import time
import urllib.request

port = sys.argv[1]
expected = int(sys.argv[2])
payload = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "getaux", "params": []}).encode()
req = urllib.request.Request(f"http://127.0.0.1:{port}/", data=payload, headers={"Content-Type": "application/json"})
last = "no response"
for _ in range(300):
    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            body = json.loads(resp.read())
        result = body.get("result") if isinstance(body, dict) else None
        if isinstance(result, dict):
            ready = int(result.get("ready_count") or 0)
            total = int(result.get("total_chains") or 0)
            if ready == total == expected:
                print(f"proxy aux templates: {ready}/{total} ready")
                sys.exit(0)
            last = f"{ready}/{total} ready"
    except Exception as exc:
        last = str(exc)
    time.sleep(1)
print(f"ERROR: merged-mining proxy not fully ready: {last}", file=sys.stderr)
sys.exit(1)
PY
    chmod 755 "$MMP_READY_CHECK"

    install -d -m 0755 -o blakestream-mpos -g blakestream-mpos "$(dirname "$GO_SHARE_LOG_PATH")"
    touch "$GO_SHARE_LOG_PATH"
    chown blakestream-mpos:blakestream-mpos "$GO_SHARE_LOG_PATH"
    chown -R blakestream-mpos:blakestream-mpos "$POOL_ROOT" "${MPOS_INSTALL_ROOT}/bin"

    say "writing Go pool systemd units"
    cat > /etc/systemd/system/blakestream-mpos-eloipool.service <<EOF
[Unit]
Description=Blakestream-MPOS Go eloipool stratum (testnet)
After=network-online.target mariadb.service
Requires=mariadb.service
Wants=network-online.target

[Service]
Type=simple
User=blakestream-mpos
Group=blakestream-mpos
WorkingDirectory=${POOL_ROOT}
Environment=ELIOPOOL_PARENT_RPC_URL=http://${NODE_RPC_USER}:${NODE_RPC_PASS}@127.0.0.1:29332/
ExecStartPre=/bin/sh -c 'for i in \$(seq 1 30); do mysqladmin ping -h ${MPOS_DB_HOST:-127.0.0.1} --silent && exit 0; sleep 1; done; echo "mariadb never came ready" >&2; exit 1'
ExecStart=${MPOS_INSTALL_ROOT}/bin/eloipool-go -start-proxy=false -stratum 0.0.0.0:${MPOS_STRATUM_PORT} -rpc 127.0.0.1:19334 -proxy 127.0.0.1:19335 -tracker-address ${MPOS_TRACKER_ADDR} -share-log ${GO_SHARE_LOG_PATH} -pool-log ${LOG_POOL}/eloipool-go.log
StandardOutput=append:${LOG_POOL}/eloipool.stdout
StandardError=append:${LOG_POOL}/eloipool.stderr
Restart=always
RestartSec=5
LimitNOFILE=8192

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/blakestream-mpos-mergeminer.service <<EOF
[Unit]
Description=Blakestream-MPOS Go merged-mine-proxy (testnet)
After=blakestream-mpos-eloipool.service
Wants=blakestream-mpos-eloipool.service

[Service]
Type=simple
User=blakestream-mpos
Group=blakestream-mpos
WorkingDirectory=${POOL_ROOT}
ExecStartPre=/bin/sh -c 'for i in \$(seq 1 60); do timeout 2 bash -c ":</dev/tcp/127.0.0.1/19334" 2>/dev/null && exit 0; sleep 1; done; echo "pool JSON-RPC did not become ready" >&2; exit 1'
ExecStart=${MPOS_INSTALL_ROOT}/bin/merged-mine-proxy-go --config ${MMP_CONFIG}
ExecStartPost=${MMP_READY_CHECK} 19335 5
StandardOutput=append:${LOG_POOL}/mergeminer.stdout
StandardError=append:${LOG_POOL}/mergeminer.stderr
Restart=always
RestartSec=5
TimeoutStartSec=360

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    say "starting Go eloipool"
    systemctl enable --now blakestream-mpos-eloipool.service
    sleep 1
    say "starting Go merged-mine-proxy"
    systemctl enable --now blakestream-mpos-mergeminer.service

    say "Go pool layer up — stratum on :${MPOS_STRATUM_PORT}, mmproxy on :19335"
    exit 0
fi

ELOIPOOL_SRC="${ELIOPOOL_TREE}/deploy-bundle/eloipool"
[ -d "$ELOIPOOL_SRC" ] || { echo "missing $ELOIPOOL_SRC" >&2; exit 1; }

say "syncing eloipool tree to ${POOL_ROOT}"
mkdir -p "$POOL_ROOT"
rsync -a --delete --exclude='__pycache__' --exclude='*.pyc' \
    "${ELOIPOOL_SRC}/" "${POOL_ROOT}/"

say "installing MPOS auth backend"
mkdir -p "${POOL_ROOT}/authentication"
touch "${POOL_ROOT}/authentication/__init__.py"
install -m 644 "${MPOS_REPO_ROOT}/ops/eloipool-authentication-mpos.py" \
    "${POOL_ROOT}/authentication/mpos.py"

say "preparing python venv"
if [ ! -d "$VENV" ]; then
    python3 -m venv "$VENV"
fi
"${VENV}/bin/pip" install -q --upgrade pip
"${VENV}/bin/pip" install -q \
    cymysql \
    PyMySQL \
    base58 \
    twisted \
    setproctitle \
    pyasynchat \
    pyasyncore

say "building Go merged-mine-proxy"
if ! command -v go >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
        wait_for_apt_locks
        apt-get update -qq
        wait_for_apt_locks
        DEBIAN_FRONTEND=noninteractive apt-get install -y golang-go >/dev/null
    else
        echo "go toolchain is required to build merged-mine-proxy-go" >&2
        exit 1
    fi
fi
MMP_GO_SRC=
if [ -d "${POOL_ROOT}/merged-mine-proxy-go" ]; then
    MMP_GO_SRC="${POOL_ROOT}/merged-mine-proxy-go"
elif [ -f "${POOL_ROOT}/go.mod" ] && [ -d "${POOL_ROOT}/cmd/merged-mine-proxy" ]; then
    MMP_GO_SRC="${POOL_ROOT}"
fi
[ -n "$MMP_GO_SRC" ] || {
    echo "merged-mine-proxy Go source not found under ${POOL_ROOT}" >&2
    exit 1
}
say "building Go merged-mine-proxy from ${MMP_GO_SRC}"
(cd "$MMP_GO_SRC" && go test ./... && CGO_ENABLED=0 go build -trimpath -o "${MPOS_INSTALL_ROOT}/bin/merged-mine-proxy-go" ./cmd/merged-mine-proxy)
chmod 755 "${MPOS_INSTALL_ROOT}/bin/merged-mine-proxy-go"

# Generate a testnet pool tracker address from the running blakecoin
# daemon if the operator didn't pin one.
NODE_RPC_USER="${MPOS_NODE_RPC_USER:-blakestream}"
NODE_RPC_PASS="${MPOS_NODE_RPC_PASS:-blakestream-testnet}"

rpc_call() {
    local port="$1" method="$2" params="${3:-[]}"
    curl -sS --max-time 10 -u "${NODE_RPC_USER}:${NODE_RPC_PASS}" \
        --data "{\"jsonrpc\":\"1.0\",\"id\":\"deploy\",\"method\":\"${method}\",\"params\":${params}}" \
        -H 'content-type: text/plain' \
        "http://127.0.0.1:${port}/" 2>/dev/null || true
}

rpc_success() {
    python3 -c 'import json,sys
try:
    data=json.load(sys.stdin)
except Exception:
    sys.exit(1)
sys.exit(0 if data.get("error") is None and data.get("result") is not None else 1)'
}

ensure_default_wallet_loaded() {
    local port="$1" resp

    resp=$(rpc_call "$port" getwalletinfo '[]')
    if printf '%s' "$resp" | rpc_success; then
        return 0
    fi

    resp=$(rpc_call "$port" loadwallet '[""]')
    if ! printf '%s' "$resp" | rpc_success; then
        resp=$(rpc_call "$port" createwallet '[""]')
    fi
    if ! printf '%s' "$resp" | rpc_success; then
        echo "failed to load or create the default wallet on RPC port ${port}: ${resp}" >&2
        return 1
    fi

    resp=$(rpc_call "$port" getwalletinfo '[]')
    if ! printf '%s' "$resp" | rpc_success; then
        echo "default wallet is not usable on RPC port ${port}: ${resp}" >&2
        return 1
    fi
}

get_address() {
    local port="$1" label="$2" address_type="${3:-bech32}"
    local resp addr
    ensure_default_wallet_loaded "$port" || return 1
    resp=$(rpc_call "$port" getnewaddress "[\"${label}\",\"${address_type}\"]")
    addr=$(printf '%s' "$resp" | sed -n 's/.*"result":"\([^"]*\)".*/\1/p')
    if [ -n "$addr" ]; then
        printf '%s' "$addr"
        return 0
    fi
    resp=$(rpc_call "$port" getnewaddress "[\"${label}\"]")
    addr=$(printf '%s' "$resp" | sed -n 's/.*"result":"\([^"]*\)".*/\1/p')
    printf '%s' "$addr"
}

if [ -z "${MPOS_TRACKER_ADDR:-}" ]; then
    say "asking blakecoind for a fresh tracker address"
    MPOS_TRACKER_ADDR=$(get_address 29332 "pool-tracker" bech32)
    if [ -z "$MPOS_TRACKER_ADDR" ]; then
        echo "failed to obtain tracker address from daemon" >&2
        exit 1
    fi
    say "tracker = ${MPOS_TRACKER_ADDR}"
fi

# Aux chain payout addresses — same dance for the 5 aux chains.
declare -A AUX_RPC_PORT=(
    [bbtc]=29112
    [elt]=26852
    [lit]=32004
    [pho]=28998
    [umo]=29738
)
declare -A AUX_TBADDR
for sym in bbtc elt lit pho umo; do
    var="MPOS_AUX_ADDR_${sym^^}"
    if [ -n "${!var:-}" ]; then
        AUX_TBADDR[$sym]="${!var}"
        continue
    fi
    say "asking ${sym} daemon for an aux payout address"
    AUX_TBADDR[$sym]=$(get_address "${AUX_RPC_PORT[$sym]}" "pool-aux" bech32)
    [ -n "${AUX_TBADDR[$sym]}" ] || { echo "failed to obtain ${sym} aux address" >&2; exit 1; }
done

# No-op coinbaser. We want the entire coinbase reward to land in the
# pool tracker address. Eloipool's makeCoinbaseTxn always adds a final
# output for `coinbaseValue - coinbased` to TrackerAddr (eloipool.py
# line 141), so emitting zero outputs gets the full reward there with
# the simplest possible coinbaser. MPOS does PPLNS credit accounting
# on the share rows independently — the on-chain coinbase doesn't need
# to be split per-miner.
COINBASER="${MPOS_INSTALL_ROOT}/bin/coinbaser-tracker.sh"
cat > "$COINBASER" <<EOF
#!/bin/bash
# Eloipool protocol: line 1 = nout. Zero outputs means "send full reward
# to TrackerAddr" because eloipool adds that fallback output itself.
echo 0
EOF
chmod 755 "$COINBASER"

# Internal MMP secret — used both as eloipool SecretPass and on the
# MMP `-p` URL. Persist so a re-run uses the same value.
SECRET_FILE="${MPOS_INSTALL_ROOT}/.mmp-secret"
if [ ! -s "$SECRET_FILE" ]; then
    head -c 16 /dev/urandom | xxd -p -c 256 | head -c 32 > "$SECRET_FILE"
    chmod 600 "$SECRET_FILE"
fi
MMP_SECRET=$(cat "$SECRET_FILE")

# Render eloipool config
say "rendering eloipool testnet config"
TEMPLATE="${MPOS_DEPLOY_BUNDLE}/templates/eloipool-testnet.config.py.template"
RENDERED="${POOL_ROOT}/config.py"
sed \
    -e "s|@@SERVER_NAME@@|Blakestream-MPOS Testnet|g" \
    -e "s|@@POOL_TRACKER_ADDR@@|${MPOS_TRACKER_ADDR}|g" \
    -e "s|@@COINBASER_CMD@@|${COINBASER} %d %p|g" \
    -e "s|@@RPC_USER@@|${NODE_RPC_USER}|g" \
    -e "s|@@RPC_PASS@@|${NODE_RPC_PASS}|g" \
    -e "s|@@MPOS_DB_HOST@@|${MPOS_DB_HOST}|g" \
    -e "s|@@MPOS_DB_PORT@@|${MPOS_DB_PORT}|g" \
    -e "s|@@MPOS_DB_USER@@|${MPOS_DB_USER}|g" \
    -e "s|@@MPOS_DB_PASS@@|${MPOS_DB_PASS}|g" \
    -e "s|@@MPOS_DB_NAME@@|${MPOS_DB_NAME}|g" \
    -e "s|@@MMP_SECRET@@|${MMP_SECRET}|g" \
    -e "s|@@LOG_ROOT@@|${MPOS_LOG_ROOT}|g" \
    "$TEMPLATE" > "$RENDERED"
chmod 640 "$RENDERED"

# Save the auxlist for use by MMP launch
LIST="${MPOS_INSTALL_ROOT}/.aux-list"
{
    for sym in bbtc elt lit pho umo; do
        printf '%s|%s|%d\n' "$sym" "${AUX_TBADDR[$sym]}" "${AUX_RPC_PORT[$sym]}"
    done
} > "$LIST"

chown -R blakestream-mpos:blakestream-mpos "$POOL_ROOT" "$VENV" "${MPOS_INSTALL_ROOT}/bin"

say "writing systemd units"
cat > /etc/systemd/system/blakestream-mpos-eloipool.service <<EOF
[Unit]
Description=Blakestream-MPOS eloipool stratum
After=network-online.target mariadb.service
Requires=mariadb.service
Wants=network-online.target

[Service]
Type=simple
User=blakestream-mpos
Group=blakestream-mpos
WorkingDirectory=${POOL_ROOT}
Environment=PYTHONPATH=${POOL_ROOT}:${POOL_ROOT}/vendor
ExecStart=${VENV}/bin/python -u ${POOL_ROOT}/eloipool.py
StandardOutput=append:${LOG_POOL}/eloipool.stdout
StandardError=append:${LOG_POOL}/eloipool.stderr
Restart=always
RestartSec=5
LimitNOFILE=8192

[Install]
WantedBy=multi-user.target
EOF

# MMP — eloipool calls back into MMP via GotWorkURI to embed aux
# merkle roots into the coinbase. MMP -p must point at eloipool's
# JSON-RPC (where it polls for parent-chain solves), authenticated
# with the SecretUser/SecretPass we configured.
MMP_ARGS="-w 19335 -s 16 -r -l ${LOG_POOL}/mmp.log"
MMP_ARGS="${MMP_ARGS} -p http://auxpow:${MMP_SECRET}@127.0.0.1:19334/"
while IFS='|' read -r sym addr port; do
    MMP_ARGS="${MMP_ARGS} -x http://${NODE_RPC_USER}:${NODE_RPC_PASS}@127.0.0.1:${port}/ -a ${addr}"
done < "$LIST"

cat > /etc/systemd/system/blakestream-mpos-mergeminer.service <<EOF
[Unit]
Description=Blakestream-MPOS merged-mine-proxy (5 aux chains)
After=blakestream-mpos-eloipool.service
Wants=blakestream-mpos-eloipool.service

[Service]
Type=simple
User=blakestream-mpos
Group=blakestream-mpos
WorkingDirectory=${POOL_ROOT}
ExecStart=${MPOS_INSTALL_ROOT}/bin/merged-mine-proxy-go ${MMP_ARGS}
StandardOutput=append:${LOG_POOL}/mergeminer.stdout
StandardError=append:${LOG_POOL}/mergeminer.stderr
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
say "starting eloipool"
systemctl enable --now blakestream-mpos-eloipool.service || true
sleep 1
say "starting merged-mine-proxy"
systemctl enable --now blakestream-mpos-mergeminer.service || true

say "pool layer up — stratum on :3334, mmproxy on :19335"
