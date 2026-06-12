#!/usr/bin/env bash
set -u

# BlakeStream MPOS/Eloipool resource and disk-I/O watcher.
#
# Purpose:
# - Record long-running system behavior while miners stay on the pool.
# - Correlate share intake with CPU, memory, process RSS, disk usage, disk I/O,
#   pool/proxy health, and recent kernel/service errors.
# - Log status only. This script does not restart services, edit configs, or
#   change miner/pool settings.
#
# Usage:
#   chmod +x ./resource-io-watch.sh
#   INTERVAL_SECONDS=300 ./resource-io-watch.sh
#
# Optional miner-side context can be added without editing this file:
#   BAIKAL=miner-lan-ip INTERVAL_SECONDS=300 ./resource-io-watch.sh
#
# For a 24-hour background run:
#   timeout 24h env INTERVAL_SECONDS=300 ./resource-io-watch.sh \
#     >> /tmp/resource-io-watch.log 2>&1 &
#
# Run this directly on the pool server where MPOS, Eloipool, MariaDB, and the
# merged-mining proxy are hosted. It reads local localhost RPC ports and local
# MariaDB tables; it does not SSH to another server.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [ -r "${SCRIPT_DIR}/lib/tool-banner.sh" ]; then
  # shellcheck disable=SC1091
  . "${SCRIPT_DIR}/lib/tool-banner.sh"
  print_blakestream_banner
fi

POOL_DB="${POOL_DB:-mpos}"
case "$POOL_DB" in
  ''|*[!A-Za-z0-9_]*)
    printf 'Invalid POOL_DB value: %s\n' "$POOL_DB" >&2
    exit 1
    ;;
esac

# BAIKAL is optional miner-side context. If unreachable from this machine, the
# miner sample returns "{}" and the VPS-side resource checks still work. Set
# BAIKAL= to disable miner polling.
BAIKAL="${BAIKAL-}"
INTERVAL_SECONDS=${INTERVAL_SECONDS:-300}

sample_local() {
  timeout 55 env POOL_DB="$POOL_DB" bash -s <<'LOCAL'
set -u
echo "----- local sample -----"
echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "host=$(hostname -f 2>/dev/null || hostname)"
echo "kernel=$(uname -srmo)"
echo "uptime=$(uptime -p 2>/dev/null || uptime)"
echo "load=$(cut -d' ' -f1-3 /proc/loadavg)"
echo "nproc=$(nproc)"

echo "----- service health -----"
systemctl is-active blakestream-mpos-system-status-cache.service blakestream-mpos-eloipool.service blakestream-mpos-mergeminer.service blakestream-mpos-sharelog-importer.service mariadb.service 2>/dev/null || true
systemctl list-units --type=service --state=running --no-pager --plain | grep -Ei 'blakestream|mpos|eloipool|mariadb' || true

echo "----- pool rpc -----"
curl -sS --max-time 3 -H 'Content-Type: application/json' --data '{"method":"status","params":[],"id":1}' http://127.0.0.1:19334/ || true
echo

echo "----- proxy rpc -----"
curl -sS --max-time 3 -H 'Content-Type: application/json' --data '{"method":"status","params":[],"id":1}' http://127.0.0.1:19335/ || true
echo

echo "----- mpos shares last 10m -----"
mysql -uroot -NBe "SELECT COUNT(*) AS shares,COALESCE(ROUND(AVG(difficulty),2),0) AS avg_diff,COALESCE(SUM(difficulty),0) AS total_diff,IFNULL(MIN(time),'none') AS first_share,IFNULL(MAX(time),'none') AS last_share FROM (SELECT difficulty,time FROM ${POOL_DB}.shares UNION ALL SELECT difficulty,time FROM ${POOL_DB}.shares_archive) x WHERE time >= NOW() - INTERVAL 10 MINUTE;" || true

echo "----- memory -----"
free -h

echo "----- process rss -----"
ps -eo pid,comm,pcpu,pmem,rss,vsz,etimes,args --sort=-rss | grep -E 'eloipool-go|merged-mine-proxy-go|mariadbd|blakecoind|blakebitcoind|electrond|lithiumd|photond|universalmoleculed' | grep -v grep || true

echo "----- disk usage -----"
df -hT / /var/lib/mysql /var/log/blakestream-mpos /opt/blakestream-mpos 2>/dev/null || df -hT /

echo "----- disk io -----"
if command -v iostat >/dev/null 2>&1; then
  iostat -xz 1 2
else
  cat /proc/diskstats
fi

echo "----- process io -----"
if command -v pidstat >/dev/null 2>&1; then
  pidstat -dru 1 1
else
  echo "pidstat not installed"
fi

echo "----- recent oom/kernel errors -----"
journalctl -k --since "15 minutes ago" --no-pager | grep -Ei 'oom|out of memory|killed process|i/o error|blk_update_request|ext4|xfs' || true

echo "----- recent pool/service errors -----"
journalctl \
  -u blakestream-mpos-eloipool.service \
  -u blakestream-mpos-mergeminer.service \
  -u blakestream-mpos-sharelog-importer.service \
  -u blakestream-mpos-cronjobs.service \
  -u blakestream-mpos-blakecoin.service \
  -u blakestream-mpos-blakebitcoin.service \
  -u blakestream-mpos-electron.service \
  -u blakestream-mpos-lithium.service \
  -u blakestream-mpos-photon.service \
  -u blakestream-mpos-universalmolecule.service \
  -u mariadb.service \
  --since "15 minutes ago" --no-pager \
  | grep -Ei 'stale|reject|error|failed|panic|oom|out of memory' \
  | tail -80 || true
LOCAL
}

sample_baikal() {
  if [ -z "${BAIKAL:-}" ]; then
    printf '{}'
    return
  fi
  timeout 10 bash -c "printf '{\"command\":\"summary\"}\n' | nc -w 5 '$BAIKAL' 4028 | tr '\0' '\n' | jq -c '.SUMMARY[0] | {accepted:.Accepted,rejected:.Rejected,stale:.Stale,mhs5s:.\"MHS 5s\",getfail:.\"Get Failures\",remotefail:.\"Remote Failures\"}'" 2>/dev/null || printf '{}'
}

while true; do
  echo "========== sample $(date -u +%Y-%m-%dT%H:%M:%SZ) =========="
  local_output=$(sample_local 2>&1)
  local_rc=$?
  printf '%s\n' "$local_output"
  echo "----- baikal summary -----"
  sample_baikal
  echo
  echo "sample_rc=$local_rc"
  sleep "$INTERVAL_SECONDS"
done
