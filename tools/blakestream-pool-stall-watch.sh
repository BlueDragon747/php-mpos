#!/usr/bin/env bash
set -u

# BlakeStream MPOS/Eloipool pool stall watcher.
#
# Purpose:
# - Observe whether the Go Eloipool + merged-mining proxy keep making progress
#   while miners remain connected.
# - Detect the "live process, stale work" failure mode without using scheduled
#   restarts that would hide the evidence.
# - Log status only. This script does not restart services or change miner/pool
#   configuration.
#
# Expected healthy behavior with miners connected:
# - pool.accepted and pool.gotwork_sent continue increasing.
# - proxy.templates.builds continues increasing.
# - pool.aux_age stays low, normally below the proxy refresh interval plus a
#   small margin.
# - proxy.ready equals proxy.total.
# - proxy.sub.failed stays at zero.
# - proxy.sub.not_accepted may rise when a share misses an aux chain target; it
#   is recorded for context but is not a stall signal by itself.
# - submit_stale may rise on low-difficulty testnet and is not treated as a
#   stall by itself.
#
# Usage:
#   1. Make the script executable:
#
#        chmod +x ./blakestream-pool-stall-watch.sh
#
#   2. Run it in the foreground against the default pool:
#
#        INTERVAL_SECONDS=300 ./blakestream-pool-stall-watch.sh
#
#   3. Optional miner-side context can be added without editing this file:
#
#        BAIKAL=miner-lan-ip INTERVAL_SECONDS=300 ./blakestream-pool-stall-watch.sh
#
#   4. Or run it in the background and keep a log:
#
#        INTERVAL_SECONDS=300 nohup ./blakestream-pool-stall-watch.sh \
#          >> /tmp/blakestream-pool-stall-watch.log 2>&1 &
#
#   5. Watch the log:
#
#        tail -f /tmp/blakestream-pool-stall-watch.log
#
#   6. Stop a background copy:
#
#        pkill -f blakestream-pool-stall-watch.sh
#
# Network notes:
# - Run this directly on the pool server where MPOS, Eloipool, MariaDB, and the
#   merged-mining proxy are hosted.
# - BAIKAL is optional miner context and requires TCP access to the miner
#   sgminer API on BAIKAL:4028.
#
# Mainnet vs testnet:
# - The stale-detection logic is network-agnostic. It only reads the Go pool
#   RPC, the merged-mining proxy RPC, MPOS share tables, process RSS, OOM logs,
#   and the miner API.
# - It can be used on mainnet or testnet as long as the service names, RPC
#   ports, and database name match the target server.
# - POOL_DB and BAIKAL are environment-configurable. The script reads local
#   localhost RPC ports and local MariaDB tables; it does not SSH to another
#   server.
# - Worker names are not required for stall detection. The SQL query counts all
#   pool shares from the last 10 minutes, so no miner username setup is needed.
#
# The output is line-oriented so it can be tailed, archived, or parsed later.

POOL_DB="${POOL_DB:-mpos}"
case "$POOL_DB" in
  ''|*[!A-Za-z0-9_]*)
    printf 'Invalid POOL_DB value: %s\n' "$POOL_DB" >&2
    exit 1
    ;;
esac

# BAIKAL is optional miner-side context. If the script runs on a VPS that cannot
# reach the miner's LAN IP, sample_baikal() will return "{}" but pool/proxy
# stall detection still works. Set BAIKAL= to disable miner polling.
BAIKAL="${BAIKAL-}"
INTERVAL_SECONDS=${INTERVAL_SECONDS:-300}

# Previous counter values are used to determine whether the pool is progressing.
prev_accepted=
prev_gotwork=
prev_templates=
stalled_samples=0

sample_local() {
  # Collect all local VPS-side signals in one call so each sample is internally
  # consistent. The timeout prevents a hung API call from wedging the watcher.
  timeout 25 env POOL_DB="$POOL_DB" bash -s <<'LOCAL'
set -u
pool=$(curl -sS --max-time 3 -H 'Content-Type: application/json' --data '{"method":"status","params":[],"id":1}' http://127.0.0.1:19334/ | jq -c '.result')
proxy=$(curl -sS --max-time 3 -H 'Content-Type: application/json' --data '{"method":"status","params":[],"id":1}' http://127.0.0.1:19335/ | jq -c '{ready:.result.ready_count,total:.result.total_chains,sub:.result.submissions,templates:.result.templates,cache:.result.cache}')
sessions=$(ss -tn state established sport = :3334 | tail -n +2 | wc -l)
db=$(mysql -uroot -NBe "SELECT COUNT(*),COALESCE(SUM(difficulty),0),COALESCE(ROUND(AVG(difficulty),2),0),IFNULL(MIN(time),'none'),IFNULL(MAX(time),'none') FROM (SELECT difficulty,time FROM ${POOL_DB}.shares UNION ALL SELECT difficulty,time FROM ${POOL_DB}.shares_archive) x WHERE time >= NOW() - INTERVAL 10 MINUTE;")
rss=$(ps -o comm=,rss= -C eloipool-go -C merged-mine-proxy-go -C mariadbd | awk '{printf "%s:%s ", $1, $2}')
oom=$(journalctl -k --since "15 minutes ago" --no-pager | grep -Eic 'oom|out of memory|killed process' || true)
jq -nc --argjson pool "$pool" --argjson proxy "$proxy" --arg sessions "$sessions" --arg db "$db" --arg rss "$rss" --arg oom "$oom" '{sessions:($sessions|tonumber),pool:$pool,proxy:$proxy,db_last_10m:$db,rss_kib:$rss,oom_recent:($oom|tonumber)}'
LOCAL
}

sample_baikal() {
  # Miner-side health. A pool-side stall should eventually show up as missing
  # last-share progress, rising get failures, or stale/rejected shares.
  if [ -z "${BAIKAL:-}" ]; then
    printf '{}'
    return
  fi
  timeout 10 bash -c "printf '{\"command\":\"summary\"}\n' | nc -w 5 '$BAIKAL' 4028 | tr '\0' '\n' | jq -c '.SUMMARY[0] | {accepted:.Accepted,rejected:.Rejected,stale:.Stale,mhs5s:.\"MHS 5s\",getfail:.\"Get Failures\",remotefail:.\"Remote Failures\"}'" 2>/dev/null || printf '{}'
}

while true; do
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local_sample=$(sample_local 2>&1)
  local_rc=$?
  baikal=$(sample_baikal)
  if [ "$local_rc" -ne 0 ]; then
    printf '%s local_error rc=%s output=%q baikal=%s\n' "$ts" "$local_rc" "$local_sample" "$baikal"
    sleep "$INTERVAL_SECONDS"
    continue
  fi

  # Core progress counters from the Go pool and merged-mining proxy.
  accepted=$(jq -r '.pool.accepted // 0' <<<"$local_sample")
  gotwork=$(jq -r '.pool.gotwork_sent // 0' <<<"$local_sample")
  miners=$(jq -r '.pool.miners // 0' <<<"$local_sample")
  aux_age=$(jq -r '.pool.aux_age // 0' <<<"$local_sample")
  templates=$(jq -r '.proxy.templates.builds // 0' <<<"$local_sample")
  ready=$(jq -r '.proxy.ready // 0' <<<"$local_sample")
  total=$(jq -r '.proxy.total // 0' <<<"$local_sample")
  failed=$(jq -r '.proxy.sub.failed // 0' <<<"$local_sample")
  not_accepted=$(jq -r '.proxy.sub.not_accepted // 0' <<<"$local_sample")

  progress_ok=1
  if [ -n "$prev_accepted" ] && [ -n "$prev_gotwork" ] && [ -n "$prev_templates" ]; then
    # A possible stall is when all three independent progress signals stop:
    # accepted shares, gotwork submissions, and proxy template builds.
    if [ "$accepted" -le "$prev_accepted" ] && [ "$gotwork" -le "$prev_gotwork" ] && [ "$templates" -le "$prev_templates" ]; then
      progress_ok=0
    fi
  fi

  alert=""
  # Do not alert just because there are no miners. The failure mode we care
  # about is miners connected but work/template progress has stopped.
  if [ "$miners" -gt 0 ] && [ "$progress_ok" -eq 0 ] && { [ "$aux_age" -gt 30 ] || [ "$templates" -le "${prev_templates:-0}" ]; }; then
    stalled_samples=$((stalled_samples + 1))
    alert="stall_candidate_${stalled_samples}"
  else
    stalled_samples=0
  fi

  # Proxy health alerts are separate from stall candidates. A chain readiness
  # drop or submit failure is actionable even if shares are still moving.
  if [ "$ready" -ne "$total" ] || [ "$failed" -gt 0 ]; then
    alert="${alert:+$alert,}proxy_health"
  fi

  printf '%s local=%s baikal=%s alert=%s\n' "$ts" "$local_sample" "$baikal" "${alert:-none}"
  prev_accepted=$accepted
  prev_gotwork=$gotwork
  prev_templates=$templates
  sleep "$INTERVAL_SECONDS"
done
