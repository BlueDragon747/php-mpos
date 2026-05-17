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
ELOIPOOL_SRC="${ELOIPOOL_TREE}/deploy-bundle/eloipool"

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
mkdir -p "$LOG_POOL" "${INSTALL_ROOT}/bin"
chown -R blakestream-mpos:blakestream-mpos "$LOG_POOL"

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
install -m 644 "${MPOS_REPO}/ops/eloipool-authentication-mpos.py" \
    "${POOL_ROOT}/authentication/mpos.py"

say "preparing python venv"
[ -d "$VENV" ] || python3 -m venv "$VENV"
"${VENV}/bin/pip" install -q --upgrade pip
"${VENV}/bin/pip" install -q \
    cymysql PyMySQL base58 twisted setproctitle pyasynchat pyasyncore

# Pool tracker = mainnet blc1... bech32 from blakecoind.
declare -A RPC_PORT=(
    [blc]=8772
    [pho]=8984
    [bbtc]=8243
    [elt]=6852
    [lit]=12345
    [umo]=19738
)

# Helper: ask a daemon for a fresh address. Tries bech32 first; on
# any error (e.g. Blakecoin 0.15.21 mainnet hasn't activated SegWit
# yet → -4 "Segregated witness not enabled on network") falls back
# to the daemon's default address type.
get_address() {
    local port="$1" label="$2" rpc_user="$3" rpc_pass="$4"
    local resp addr
    resp=$(curl -sS --max-time 5 -u "${rpc_user}:${rpc_pass}" \
        --data "{\"jsonrpc\":\"1.0\",\"id\":\"deploy\",\"method\":\"getnewaddress\",\"params\":[\"${label}\",\"bech32\"]}" \
        -H 'content-type: text/plain' \
        "http://127.0.0.1:${port}/" 2>/dev/null || true)
    addr=$(printf '%s' "$resp" | sed -n 's/.*"result":"\([^"]*\)".*/\1/p')
    if [ -n "$addr" ]; then
        printf '%s' "$addr"
        return 0
    fi
    # Fallback to default (legacy P2PKH).
    resp=$(curl -sS --max-time 5 -u "${rpc_user}:${rpc_pass}" \
        --data "{\"jsonrpc\":\"1.0\",\"id\":\"deploy\",\"method\":\"getnewaddress\",\"params\":[\"${label}\"]}" \
        -H 'content-type: text/plain' \
        "http://127.0.0.1:${port}/" 2>/dev/null || true)
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
    [lit]=12345
    [pho]=8984
    [umo]=19738
)
declare -A AUX_ADDR
for sym in bbtc elt lit pho umo; do
    var="MPOS_AUX_ADDR_${sym^^}"
    if [ -n "${!var:-}" ]; then
        AUX_ADDR[$sym]="${!var}"
        continue
    fi
    say "asking ${sym} daemon for an aux payout address"
    AUX_ADDR[$sym]=$(get_address "${AUX_RPC_PORT[$sym]}" "pool-aux" \
        "${MPOS_NODE_RPC_USER}" "${MPOS_NODE_RPC_PASS}")
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
Environment=PYTHONPATH=${POOL_ROOT}:${POOL_ROOT}/vendor
# Wait for MariaDB to be ACTUALLY ready before eloipool tries to
# initialise the MPOS auth module. systemd's After=mariadb.service
# only waits for the unit's exec to start; mariadb may still be
# loading databases when eloipool's authentication.mpos.connect()
# fires. A failed auth-module init is fatal: eloipool stays up but
# every mining.authorize is silently rejected.
ExecStartPre=/bin/sh -c 'for i in \$(seq 1 30); do mysqladmin ping -h ${MPOS_DB_HOST} --silent && exit 0; sleep 1; done; echo "mariadb never came ready" >&2; exit 1'
ExecStart=${VENV}/bin/python -u ${POOL_ROOT}/eloipool.py
StandardOutput=append:${LOG_POOL}/eloipool.stdout
StandardError=append:${LOG_POOL}/eloipool.stderr
Restart=always
RestartSec=5
LimitNOFILE=8192

[Install]
WantedBy=multi-user.target
EOF

MMP_ARGS="-w 19335 -s 16 -r -l ${LOG_POOL}/mmp.log"
MMP_ARGS="${MMP_ARGS} -p http://auxpow:${MMP_SECRET}@127.0.0.1:19334/"
while IFS='|' read -r sym addr port; do
    MMP_ARGS="${MMP_ARGS} -x http://${MPOS_NODE_RPC_USER}:${MPOS_NODE_RPC_PASS}@127.0.0.1:${port}/ -a ${addr}"
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
ExecStart=${VENV}/bin/python -u ${POOL_ROOT}/merged-mine-proxy.py3 ${MMP_ARGS}
StandardOutput=append:${LOG_POOL}/mergeminer.stdout
StandardError=append:${LOG_POOL}/mergeminer.stderr
Restart=always
RestartSec=5

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
