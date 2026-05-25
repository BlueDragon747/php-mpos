#!/usr/bin/env bash
# 30-wait-rpc.sh — poll each mainnet daemon's RPC until it answers.
# Per-coin timeout is generous (15 min) since first start has to load
# blockindex, optionally replay bootstrap.dat from step 21, and
# synchronise headers. Fails hard if any daemon never comes up.
set -euo pipefail
say() { printf '\033[1;33m   %s\033[0m\n' "$*"; }

declare -A RPC_PORT=(
    [blc]=8772
    [pho]=8984
    [bbtc]=8243
    [elt]=6852
    [lit]=12000
    [umo]=5921
)

PER_COIN_DEADLINE=900  # 15 min

for coin in blc pho bbtc elt lit umo; do
    port="${RPC_PORT[$coin]}"
    say "waiting for ${coin} RPC on 127.0.0.1:${port}"
    end=$(( $(date +%s) + PER_COIN_DEADLINE ))
    last_msg=""
    while :; do
        if curl -fsSL --max-time 60 -u "${MPOS_NODE_RPC_USER}:${MPOS_NODE_RPC_PASS}" \
                --data '{"jsonrpc":"1.0","id":"deploy","method":"getblockcount"}' \
                -H 'content-type: text/plain' \
                "http://127.0.0.1:${port}/" >/tmp/rpc-resp 2>/dev/null; then
            height=$(sed -n 's/.*"result":\([0-9]*\).*/\1/p' /tmp/rpc-resp)
            say "${coin} RPC OK; height=${height:-?}"
            break
        fi
        if [ "$(date +%s)" -ge "$end" ]; then
            echo "ERROR: ${coin} never came up on 127.0.0.1:${port}" >&2
            echo "       last 30 lines of docker logs ${coin}:" >&2
            docker logs "${coin}" --tail 30 2>&1 | head -40 >&2 || true
            exit 1
        fi
        # Status report every 60s without spamming.
        msg="$(docker logs --tail 1 ${coin} 2>/dev/null | head -c 80)"
        if [ "${msg}" != "${last_msg}" ]; then
            last_msg="${msg}"
            say "  ${coin}: ${msg:-(no log yet)}"
        fi
        sleep 5
    done
done

rm -f /tmp/rpc-resp
say "step 30 done — all 6 daemons reachable"
