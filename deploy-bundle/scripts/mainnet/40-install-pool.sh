#!/usr/bin/env bash
# 40-install-pool.sh — install eloipool stratum + merged-mine-proxy
# pointed at the mainnet daemons (started in step 20).
set -euo pipefail
say() { printf '\033[1;33m   %s\033[0m\n' "$*"; }

INSTALL_ROOT=/opt/blakestream-mpos
LOG_ROOT=/var/log/blakestream-mpos
WEB_ROOT=/var/www/blakestream-mpos
MPOS_REPO=/root/Blakestream-MPOS
ELOIPOOL_TREE=/root/Blakestream-Eliopool
ELOIPOOL_SRC="${ELOIPOOL_TREE}"

[ -d "$ELOIPOOL_SRC" ] || { echo "missing $ELOIPOOL_SRC" >&2; exit 1; }
[ -d "$MPOS_REPO" ] || { echo "missing $MPOS_REPO" >&2; exit 1; }

# Service user.
if ! id blakestream-mpos >/dev/null 2>&1; then
    say "creating blakestream-mpos system user"
    useradd --system --no-create-home --shell /usr/sbin/nologin blakestream-mpos
fi

POOL_ROOT="${INSTALL_ROOT}/eloipool"
VENV="${INSTALL_ROOT}/venv"
LOG_POOL="${LOG_ROOT}/pool"
CONFIG_DIR="${INSTALL_ROOT}/config"
GO_SHARE_LOG_PATH="${GO_SHARE_LOG_PATH:-/var/log/blakestream-eliopool-25.2-go/shares.log}"
mkdir -p "$LOG_POOL" "${INSTALL_ROOT}/bin" "$CONFIG_DIR"
chown -R blakestream-mpos:blakestream-mpos "$LOG_POOL"
chown root:blakestream-mpos "$CONFIG_DIR"
chmod 750 "$CONFIG_DIR"

say "syncing eloipool tree → ${POOL_ROOT}"
mkdir -p "$POOL_ROOT"
rsync -a --delete --exclude='__pycache__' --exclude='*.pyc' \
    "${ELOIPOOL_SRC}/" "${POOL_ROOT}/"

# Apply MPOS-side overlays AFTER the rsync. See
# ops/eloipool-overrides/README.md for what's in this directory and
# why we vendor-overlay instead of upstreaming.
OVERRIDES_DIR="${MPOS_REPO}/ops/eloipool-overrides"
if [ -d "${OVERRIDES_DIR}" ]; then
    say "applying eloipool overlays from ${OVERRIDES_DIR}"
    for f in merged-mine-proxy.py3; do
        if [ -f "${OVERRIDES_DIR}/$f" ]; then
            install -m 644 "${OVERRIDES_DIR}/$f" "${POOL_ROOT}/$f"
            say "  overlaid ${POOL_ROOT}/$f"
        fi
    done
fi

say "installing MPOS auth backend"
mkdir -p "${POOL_ROOT}/authentication"
touch "${POOL_ROOT}/authentication/__init__.py"
install -m 644 "${MPOS_REPO}/ops/eloipool-authentication-mpos.py" \
    "${POOL_ROOT}/authentication/mpos.py"

say "preparing python venv"
[ -d "$VENV" ] || python3 -m venv "$VENV"
"${VENV}/bin/pip" install -q --upgrade pip
"${VENV}/bin/pip" install -q \
    cymysql PyMySQL base58 twisted setproctitle pyasynchat pyasyncore

find_go_source() {
    if [ -d "${POOL_ROOT}/merged-mine-proxy-go" ]; then
        printf '%s\n' "${POOL_ROOT}/merged-mine-proxy-go"
    elif [ -f "${POOL_ROOT}/go.mod" ] && [ -d "${POOL_ROOT}/cmd/merged-mine-proxy" ]; then
        printf '%s\n' "${POOL_ROOT}"
    fi
}

GO_POOL_SRC="$(find_go_source)"

if [ -n "${MMP_GO_PREBUILT_BIN:-}" ]; then
    say "installing prebuilt Go merged-mine-proxy from ${MMP_GO_PREBUILT_BIN}"
    install -m 755 "${MMP_GO_PREBUILT_BIN}" "${INSTALL_ROOT}/bin/merged-mine-proxy-go"
else
    say "building Go merged-mine-proxy"
    if ! command -v go >/dev/null 2>&1; then
        if [ "${ALLOW_TARGET_GO_BUILD:-1}" != "1" ]; then
            echo "go toolchain is required unless MMP_GO_PREBUILT_BIN is set" >&2
            exit 1
        fi
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update -qq
            DEBIAN_FRONTEND=noninteractive apt-get install -y golang-go >/dev/null
        else
            echo "go toolchain is required to build merged-mine-proxy-go" >&2
            exit 1
        fi
    fi
    [ -n "$GO_POOL_SRC" ] || {
        echo "merged-mine-proxy Go source not found under ${POOL_ROOT}" >&2
        exit 1
    }
    say "building Go merged-mine-proxy from ${GO_POOL_SRC}"
    (cd "$GO_POOL_SRC" && go test ./... && CGO_ENABLED=0 go build -trimpath -o "${INSTALL_ROOT}/bin/merged-mine-proxy-go" ./cmd/merged-mine-proxy)
fi
chmod 755 "${INSTALL_ROOT}/bin/merged-mine-proxy-go"

if [ -n "${ELIOPOOL_GO_PREBUILT_BIN:-}" ]; then
    say "installing prebuilt Go eloipool from ${ELIOPOOL_GO_PREBUILT_BIN}"
    install -m 755 "${ELIOPOOL_GO_PREBUILT_BIN}" "${INSTALL_ROOT}/bin/eloipool-go"
else
    [ -n "$GO_POOL_SRC" ] || {
        echo "Go eloipool source not found under ${POOL_ROOT}" >&2
        exit 1
    }
    say "building Go eloipool from ${GO_POOL_SRC}"
    (cd "$GO_POOL_SRC" && CGO_ENABLED=0 go build -trimpath -o "${INSTALL_ROOT}/bin/eloipool-go" ./cmd/eloipool)
fi
chmod 755 "${INSTALL_ROOT}/bin/eloipool-go"

MMP_READY_CHECK="${INSTALL_ROOT}/bin/check-mmp-ready.py"
cat > "$MMP_READY_CHECK" <<'PY'
#!/usr/bin/env python3
import json
import sys
import time
import urllib.request

port = sys.argv[1]
expected = int(sys.argv[2])
payload = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "getaux", "params": []}).encode()
req = urllib.request.Request(
    f"http://127.0.0.1:{port}/",
    data=payload,
    headers={"Content-Type": "application/json"},
)
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
            waiting = result.get("waiting_chains") or []
            names = [str(row.get("chain") or row.get("alias") or "?") for row in waiting]
            last = f"{ready}/{total} ready"
            if names:
                last += "; waiting on " + ", ".join(names)
    except Exception as exc:
        last = str(exc)
    time.sleep(1)
print(f"ERROR: merged-mining proxy not fully ready: {last}", file=sys.stderr)
sys.exit(1)
PY
chmod 755 "$MMP_READY_CHECK"

# Pool tracker = mainnet blc1... bech32 from blakecoind.
declare -A RPC_PORT=(
    [blc]=8772
    [pho]=8984
    [bbtc]=8243
    [elt]=6852
    [lit]=12000
    [umo]=5921
)

rpc_call() {
    local port="$1" rpc_user="$2" rpc_pass="$3" method="$4" params="${5:-[]}"
    curl -sS --max-time 10 -u "${rpc_user}:${rpc_pass}" \
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
    local port="$1" rpc_user="$2" rpc_pass="$3" resp

    resp=$(rpc_call "$port" "$rpc_user" "$rpc_pass" getwalletinfo '[]')
    if printf '%s' "$resp" | rpc_success; then
        return 0
    fi

    resp=$(rpc_call "$port" "$rpc_user" "$rpc_pass" loadwallet '[""]')
    if ! printf '%s' "$resp" | rpc_success; then
        resp=$(rpc_call "$port" "$rpc_user" "$rpc_pass" createwallet '[""]')
    fi
    if ! printf '%s' "$resp" | rpc_success; then
        echo "failed to load or create the default wallet on RPC port ${port}: ${resp}" >&2
        return 1
    fi

    resp=$(rpc_call "$port" "$rpc_user" "$rpc_pass" getwalletinfo '[]')
    if ! printf '%s' "$resp" | rpc_success; then
        echo "default wallet is not usable on RPC port ${port}: ${resp}" >&2
        return 1
    fi
}

# Helper: ask a daemon for a fresh address. Tries the requested address type
# first; on any error falls back to the daemon's default address type.
get_address() {
    local port="$1" label="$2" rpc_user="$3" rpc_pass="$4"
    local address_type="${5:-bech32}"
    local resp addr
    ensure_default_wallet_loaded "$port" "$rpc_user" "$rpc_pass" || return 1
    resp=$(rpc_call "$port" "$rpc_user" "$rpc_pass" getnewaddress "[\"${label}\",\"${address_type}\"]")
    addr=$(printf '%s' "$resp" | sed -n 's/.*"result":"\([^"]*\)".*/\1/p')
    if [ -n "$addr" ]; then
        printf '%s' "$addr"
        return 0
    fi
    # Fallback to default (legacy P2PKH).
    resp=$(rpc_call "$port" "$rpc_user" "$rpc_pass" getnewaddress "[\"${label}\"]")
    addr=$(printf '%s' "$resp" | sed -n 's/.*"result":"\([^"]*\)".*/\1/p')
    printf '%s' "$addr"
}

if [ -z "${MPOS_TRACKER_ADDR:-}" ]; then
    say "asking blakecoind (mainnet) for a fresh tracker address"
    MPOS_TRACKER_ADDR=$(get_address 8772 "pool-tracker" \
        "${MPOS_NODE_RPC_USER}" "${MPOS_NODE_RPC_PASS}")
    [ -n "$MPOS_TRACKER_ADDR" ] || { echo "failed to obtain mainnet tracker address" >&2; exit 1; }
fi
say "tracker = ${MPOS_TRACKER_ADDR}"

# Aux-chain payout addresses.
declare -A AUX_RPC_PORT=(
    [bbtc]=8243
    [elt]=6852
    [lit]=12000
    [pho]=8984
    [umo]=5921
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
        say "asking ${sym} daemon for a legacy aux payout address"
    else
        say "asking ${sym} daemon for an aux payout address"
    fi
    AUX_ADDR[$sym]=$(get_address "${AUX_RPC_PORT[$sym]}" "pool-aux" \
        "${MPOS_NODE_RPC_USER}" "${MPOS_NODE_RPC_PASS}" "${address_type}")
    [ -n "${AUX_ADDR[$sym]}" ] || { echo "failed to obtain ${sym} aux address" >&2; exit 1; }
done

# Coinbaser: send entire reward to tracker.
COINBASER="${INSTALL_ROOT}/bin/coinbaser-tracker.sh"
cat > "$COINBASER" <<'EOF'
#!/bin/bash
echo 0
EOF
chmod 755 "$COINBASER"

# Persist a stable MMP secret.
SECRET_FILE="${INSTALL_ROOT}/.mmp-secret"
if [ ! -s "$SECRET_FILE" ]; then
    head -c 16 /dev/urandom | xxd -p -c 256 | head -c 32 > "$SECRET_FILE"
    chmod 600 "$SECRET_FILE"
fi
MMP_SECRET=$(cat "$SECRET_FILE")

# Render eloipool config from the mainnet template.
say "rendering eloipool mainnet config"
TEMPLATE="${MPOS_REPO}/deploy-bundle/templates/eloipool-mainnet.config.py.template"
RENDERED="${POOL_ROOT}/config.py"
sed \
    -e "s|@@SERVER_NAME@@|Blakestream-MPOS Mainnet|g" \
    -e "s|@@POOL_TRACKER_ADDR@@|${MPOS_TRACKER_ADDR}|g" \
    -e "s|@@COINBASER_CMD@@|${COINBASER} %d %p|g" \
    -e "s|@@RPC_USER@@|${MPOS_NODE_RPC_USER}|g" \
    -e "s|@@RPC_PASS@@|${MPOS_NODE_RPC_PASS}|g" \
    -e "s|@@MPOS_DB_HOST@@|${MPOS_DB_HOST}|g" \
    -e "s|@@MPOS_DB_PORT@@|${MPOS_DB_PORT}|g" \
    -e "s|@@MPOS_DB_USER@@|${MPOS_DB_USER}|g" \
    -e "s|@@MPOS_DB_PASS@@|${MPOS_DB_PASS}|g" \
    -e "s|@@MPOS_DB_NAME@@|${MPOS_DB_NAME}|g" \
    -e "s|@@MMP_SECRET@@|${MMP_SECRET}|g" \
    -e "s|@@LOG_ROOT@@|${LOG_ROOT}|g" \
    -e "s|@@STRATUM_PORT@@|${MPOS_STRATUM_PORT}|g" \
    "$TEMPLATE" > "$RENDERED"
chmod 640 "$RENDERED"

LIST="${INSTALL_ROOT}/.aux-list"
{
    for sym in bbtc elt lit pho umo; do
        printf '%s|%s|%d\n' "$sym" "${AUX_ADDR[$sym]}" "${AUX_RPC_PORT[$sym]}"
    done
} > "$LIST"

MMP_CONFIG="${CONFIG_DIR}/merged-mine-proxy.json"
say "writing merged-mine-proxy config"
MMP_SECRET="$MMP_SECRET" \
MPOS_NODE_RPC_USER="$MPOS_NODE_RPC_USER" \
MPOS_NODE_RPC_PASS="$MPOS_NODE_RPC_PASS" \
LOG_POOL="$LOG_POOL" \
python3 - "$LIST" "$MMP_CONFIG" <<'PY'
import json
import os
import sys
from urllib.parse import quote

aux_urls = []
payouts = []
with open(sys.argv[1], "r", encoding="utf-8") as f:
    for line in f:
        sym, addr, port = line.strip().split("|")
        aux_urls.append("http://%s:%s@127.0.0.1:%s/" % (
            quote(os.environ["MPOS_NODE_RPC_USER"], safe=""),
            quote(os.environ["MPOS_NODE_RPC_PASS"], safe=""),
            port,
        ))
        payouts.append(addr)

cfg = {
    "worker_port": 19335,
    "parent_urls": ["http://auxpow:%s@127.0.0.1:19334/" % quote(os.environ["MMP_SECRET"], safe="")],
    "aux_urls": aux_urls,
    "aux_payout_addresses": payouts,
    "merkle_size": 16,
    "rewrite_target": 32,
    "log_file": os.path.join(os.environ["LOG_POOL"], "mmp.log"),
}
with open(sys.argv[2], "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2, sort_keys=True)
    f.write("\n")
PY
chown root:blakestream-mpos "$MMP_CONFIG"
chmod 640 "$MMP_CONFIG"

install -d -m 0755 -o blakestream-mpos -g blakestream-mpos "$(dirname "$GO_SHARE_LOG_PATH")"
touch "$GO_SHARE_LOG_PATH"
chown blakestream-mpos:blakestream-mpos "$GO_SHARE_LOG_PATH"

chown -R blakestream-mpos:blakestream-mpos "$POOL_ROOT" "$VENV" "${INSTALL_ROOT}/bin"

say "writing systemd units"
cat > /etc/systemd/system/blakestream-mpos-eloipool.service <<EOF
[Unit]
Description=Blakestream-MPOS eloipool stratum (mainnet)
After=network-online.target mariadb.service
Requires=mariadb.service
Wants=network-online.target

[Service]
Type=simple
User=blakestream-mpos
Group=blakestream-mpos
WorkingDirectory=${POOL_ROOT}
Environment=ELIOPOOL_PARENT_RPC_URL=http://${MPOS_NODE_RPC_USER}:${MPOS_NODE_RPC_PASS}@127.0.0.1:8772/
ExecStartPre=/bin/sh -c 'for i in \$(seq 1 30); do mysqladmin ping -h ${MPOS_DB_HOST} --silent && exit 0; sleep 1; done; echo "mariadb never came ready" >&2; exit 1'
ExecStart=${INSTALL_ROOT}/bin/eloipool-go -start-proxy=false -stratum 0.0.0.0:${MPOS_STRATUM_PORT} -rpc 127.0.0.1:19334 -proxy 127.0.0.1:19335 -tracker-address ${MPOS_TRACKER_ADDR} -share-log ${GO_SHARE_LOG_PATH} -pool-log ${LOG_POOL}/eloipool-go.log
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
Description=Blakestream-MPOS merged-mine-proxy (5 aux chains)
After=blakestream-mpos-eloipool.service
Wants=blakestream-mpos-eloipool.service

[Service]
Type=simple
User=blakestream-mpos
Group=blakestream-mpos
WorkingDirectory=${POOL_ROOT}
ExecStartPre=/bin/sh -c 'for i in \$(seq 1 60); do timeout 2 bash -c ":</dev/tcp/127.0.0.1/19334" 2>/dev/null && exit 0; sleep 1; done; echo "pool JSON-RPC did not become ready" >&2; exit 1'
ExecStart=${INSTALL_ROOT}/bin/merged-mine-proxy-go --config ${MMP_CONFIG}
ExecStartPost=${MMP_READY_CHECK} 19335 5
StandardOutput=append:${LOG_POOL}/mergeminer.stdout
StandardError=append:${LOG_POOL}/mergeminer.stderr
Restart=always
RestartSec=5
TimeoutStartSec=360
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
PrivateDevices=true
LockPersonality=true
CapabilityBoundingSet=
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
ReadWritePaths=${LOG_POOL}

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
say "starting eloipool"
systemctl enable --now blakestream-mpos-eloipool.service
sleep 1
say "starting merged-mine-proxy"
systemctl enable --now blakestream-mpos-mergeminer.service

say "step 40 done — stratum on :${MPOS_STRATUM_PORT}, mmproxy on :19335"
say "tracker_addr=${MPOS_TRACKER_ADDR}"
