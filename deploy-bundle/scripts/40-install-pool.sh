#!/usr/bin/env bash
# Install the eloipool stratum + merged-mine-proxy onto the MPOS install
# root. Uses the eloipool tree from $ELIOPOOL_TREE so we don't fork it.
# MPOS-specific bits we add on top:
#   - authentication/mpos.py (validates against pool_worker table)
#   - testnet-flavoured config rendered from templates/
#   - coinbaser shim (defaults to single-output to the pool tracker addr)
set -euo pipefail

say() { printf '\033[1;33m   %s\033[0m\n' "$*"; }

ELOIPOOL_SRC="${ELIOPOOL_TREE}/deploy-bundle/eloipool"
[ -d "$ELOIPOOL_SRC" ] || { echo "missing $ELOIPOOL_SRC" >&2; exit 1; }

POOL_ROOT="${MPOS_INSTALL_ROOT}/eloipool"
VENV="${MPOS_INSTALL_ROOT}/venv"
LOG_POOL="${MPOS_LOG_ROOT}/pool"
mkdir -p "$LOG_POOL" "${MPOS_INSTALL_ROOT}/bin"
chown -R blakestream-mpos:blakestream-mpos "$LOG_POOL"

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
        apt-get update -qq
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
