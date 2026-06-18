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
# Two display modes (auto-selected):
# - Interactive (stdout is a terminal): a LIVE in-place dashboard of tables that
#   refresh in place every REFRESH_SECONDS (default 5). Ctrl-C to quit.
# - Redirected/background (not a terminal): the original append-only text sample
#   every INTERVAL_SECONDS (default 300), for a 24h log. Force this on a terminal
#   with WATCH_TABLE=0.
#
# Usage:
#   chmod +x ./resource-io-watch.sh
#   ./resource-io-watch.sh                      # live table (REFRESH_SECONDS=5)
#   REFRESH_SECONDS=2 ./resource-io-watch.sh    # faster live refresh
#
# Optional miner-side context can be added without editing this file:
#   BAIKAL=miner-lan-ip ./resource-io-watch.sh
#
# For a 24-hour background run (append-only log, no escape codes):
#   timeout 24h env INTERVAL_SECONDS=300 ./resource-io-watch.sh \
#     >> /tmp/resource-io-watch.log 2>&1 &
#
# Run this directly on the pool server where MPOS, Eloipool, MariaDB, and the
# merged-mining proxy are hosted. It reads local localhost RPC ports and local
# MariaDB tables; it does not SSH to another server.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HAVE_BANNER=0
if [ -r "${SCRIPT_DIR}/lib/tool-banner.sh" ]; then
  # shellcheck disable=SC1091
  . "${SCRIPT_DIR}/lib/tool-banner.sh"
  HAVE_BANNER=1
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
REFRESH_SECONDS=${REFRESH_SECONDS:-5}
POOL_PORT="${POOL_PORT:-19334}"
PROXY_PORT="${PROXY_PORT:-19335}"

# Services shown in the dashboard / probed for health.
SERVICES=(
  blakestream-mpos-system-status-cache.service
  blakestream-mpos-eloipool.service
  blakestream-mpos-mergeminer.service
  blakestream-mpos-sharelog-importer.service
  blakestream-mpos-cronjobs.service
  blakestream-mpos-blakecoin.service
  blakestream-mpos-blakebitcoin.service
  blakestream-mpos-electron.service
  blakestream-mpos-lithium.service
  blakestream-mpos-photon.service
  blakestream-mpos-universalmolecule.service
  mariadb.service
)
PROC_RE='eloipool-go|merged-mine-proxy-go|mariadbd|blakecoind|blakebitcoind|electrond|lithiumd|photond|universalmoleculed'
DISK_PATHS=(/ /var/lib/mysql /var/log/blakestream-mpos /opt/blakestream-mpos)

# ---------------------------------------------------------------------------
# Collectors (used by both modes)
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Live dashboard
# ---------------------------------------------------------------------------
W=64                                   # inner content width shared by all tables

setup_colors() {
  if [ -t 1 ]; then
    blue=$'\033[0;34m'; cyan=$'\033[0;36m'; green=$'\033[0;32m'
    red=$'\033[0;31m'; yellow=$'\033[1;33m'; orange=$'\033[38;5;208m'; nc=$'\033[0m'
  else
    blue=; cyan=; green=; red=; yellow=; orange=; nc=
  fi
}

boxrule()  { local r; printf -v r '%*s' "$((W+4))" ''; printf '%s%s%s\n' "$blue" "${r// /=}" "$nc"; }
boxtitle() { # centered title as the top border
  local t="$1" tot=$((W+4)) tl tr L R
  tl=$(( (tot-${#t}-2)/2 )); tr=$(( tot-${#t}-2-tl ))
  printf -v L '%*s' "$tl" ''; printf -v R '%*s' "$tr" ''
  printf '%s%s %s%s%s %s%s\n' "$blue" "${L// /=}" "$cyan" "$t" "$blue" "${R// /=}" "$nc"
}
boxline()  { printf '%s=%s %s %s=%s\n' "$blue" "$nc" "$1" "$blue" "$nc"; }   # $1 = content of visible width W

state_color() {
  case "$1" in
    active|running)                 printf '%s' "$green" ;;
    failed|dead|inactive|n/a|down)  printf '%s' "$red" ;;
    activating|reloading|deactivating) printf '%s' "$yellow" ;;
    *)                              printf '%s' "$nc" ;;
  esac
}
pct_color() { local p="${1:-0}"; if [ "$p" -ge 90 ] 2>/dev/null; then printf '%s' "$red"; elif [ "$p" -ge 75 ] 2>/dev/null; then printf '%s' "$yellow"; else printf '%s' "$green"; fi; }

human_kb() { awk -v k="${1:-0}" 'BEGIN{ if(k>=1048576) printf "%.1fG",k/1048576; else if(k>=1024) printf "%.0fM",k/1024; else printf "%dK",k }'; }
human_et() { awk -v s="${1:-0}" 'BEGIN{ d=int(s/86400);s%=86400;h=int(s/3600);s%=3600;m=int(s/60); if(d>0)printf "%dd%dh",d,h; else if(h>0)printf "%dh%dm",h,m; else printf "%dm",m }'; }

# two-column key/value row; $5 (optional) colors the value cell.
row2() {
  local wm="$1" wv="$2" k v
  printf -v k '%-*s' "$wm" "$3"; printf -v v '%-*s' "$wv" "$4"
  [ -n "${5:-}" ] && v="${5}${v}${nc}"
  boxline "${k} ${blue}|${nc} ${v}"
}
hdr2() {
  local wm="$1" wv="$2" k v
  printf -v k '%-*s' "$wm" "$3"; printf -v v '%-*s' "$wv" "$4"
  boxline "${cyan}${k}${nc} ${blue}|${nc} ${cyan}${v}${nc}"
}

render_header() {
  local ts host load
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  host="$(hostname -s 2>/dev/null || hostname)"
  load="$(cut -d' ' -f1-3 /proc/loadavg)"
  printf '%sBlakeStream resource & I/O watch%s  %s%s%s\n' "$orange" "$nc" "$cyan" "$host" "$nc"
  printf '%supdated%s %s   %srefresh%s %ss   %sload%s %s/%scpu   %squit%s Ctrl-C\n' \
    "$cyan" "$nc" "$ts" "$cyan" "$nc" "$REFRESH_SECONDS" "$cyan" "$nc" "$load" "$(nproc)" "$cyan" "$nc"
}

render_services() {
  local wn=22 ws svc disp state col
  ws=$(( W - wn - 3 ))
  boxtitle "SERVICES"
  hdr2 "$wn" "$ws" "SERVICE" "STATE"
  for svc in "${SERVICES[@]}"; do
    disp="${svc#blakestream-mpos-}"; disp="${disp%.service}"
    # is-active prints the state AND exits non-zero when not active, so capture
    # its output regardless of exit and only default when it printed nothing.
    state="$(timeout 3 systemctl is-active "$svc" 2>/dev/null)"
    state="${state%%$'\n'*}"; [ -n "$state" ] || state="n/a"
    col="$(state_color "$state")"
    row2 "$wn" "$ws" "$disp" "$state" "$col"
  done
  boxrule
}

render_processes() {
  local wn=18 wc=6 wm=6 wr=10 wu=12 name cpu mem rss et c1 c2 c3 c4 c5
  boxtitle "PROCESSES (by RSS)"
  printf -v c1 '%-*s' "$wn" "PROCESS"; printf -v c2 '%*s' "$wc" "CPU%"
  printf -v c3 '%*s' "$wm" "MEM%"; printf -v c4 '%*s' "$wr" "RSS"; printf -v c5 '%-*s' "$wu" "UPTIME"
  boxline "${cyan}${c1}${nc} ${blue}|${nc} ${cyan}${c2}${nc} ${blue}|${nc} ${cyan}${c3}${nc} ${blue}|${nc} ${cyan}${c4}${nc} ${blue}|${nc} ${cyan}${c5}${nc}"
  # Snapshot ps FIRST (alone), then filter the static text — otherwise the
  # filtering awk, carrying the regex in its own args, matches itself.
  local any=0 psout
  psout="$(ps -eo comm=,pcpu=,pmem=,rss=,etimes=,args= --sort=-rss 2>/dev/null)"
  while IFS=$'\t' read -r name cpu mem rss et; do
    [ -n "$name" ] || continue
    any=1
    printf -v c1 '%-*.*s' "$wn" "$wn" "$name"
    printf -v c2 '%*s' "$wc" "$cpu"
    printf -v c3 '%*s' "$wm" "$mem"
    printf -v c4 '%*s' "$wr" "$(human_kb "$rss")"
    printf -v c5 '%-*s' "$wu" "$(human_et "$et")"
    boxline "${c1} ${blue}|${nc} ${c2} ${blue}|${nc} ${c3} ${blue}|${nc} ${c4} ${blue}|${nc} ${c5}"
  done < <(printf '%s\n' "$psout" | awk -v re="$PROC_RE" '$0 ~ re {print $1"\t"$2"\t"$3"\t"$4"\t"$5}')
  [ "$any" = "1" ] || boxline "$(printf '%-*s' "$W" 'no matching processes running')"
  boxrule
}

render_system() {
  local wm=16 wv mt mu ma st su pct spct
  wv=$(( W - wm - 3 ))
  boxtitle "SYSTEM"
  hdr2 "$wm" "$wv" "METRIC" "VALUE"
  read -r mt mu ma < <(free -m 2>/dev/null | awk '/^Mem:/{print $2, $3, $7}')
  read -r st su < <(free -m 2>/dev/null | awk '/^Swap:/{print $2, $3}')
  : "${mt:=0}" "${mu:=0}" "${ma:=0}" "${st:=0}" "${su:=0}"
  pct=0;  [ "$mt" -gt 0 ] && pct=$(( mu*100/mt ))
  spct=0; [ "$st" -gt 0 ] && spct=$(( su*100/st ))
  row2 "$wm" "$wv" "load avg" "$(cut -d' ' -f1-3 /proc/loadavg)  ($(nproc) cpu)"
  row2 "$wm" "$wv" "memory" "$(printf '%s / %s MB (%s%%), %s MB free' "$mu" "$mt" "$pct" "$ma")" "$(pct_color "$pct")"
  row2 "$wm" "$wv" "swap" "$(printf '%s / %s MB (%s%%)' "$su" "$st" "$spct")" "$(pct_color "$spct")"
  boxrule
}

render_disk() {
  local wm=33 ws=8 wu=8 wp=6 mnt size used pct c1 c2 c3 c4
  boxtitle "DISK USAGE"
  printf -v c1 '%-*s' "$wm" "MOUNT"; printf -v c2 '%*s' "$ws" "SIZE"
  printf -v c3 '%*s' "$wu" "USED"; printf -v c4 '%*s' "$wp" "USE%"
  boxline "${cyan}${c1}${nc} ${blue}|${nc} ${cyan}${c2}${nc} ${blue}|${nc} ${cyan}${c3}${nc} ${blue}|${nc} ${cyan}${c4}${nc}"
  while IFS=$'\t' read -r mnt size used pct; do
    [ -n "$mnt" ] || continue
    printf -v c1 '%-*.*s' "$wm" "$wm" "$mnt"
    printf -v c2 '%*s' "$ws" "$size"; printf -v c3 '%*s' "$wu" "$used"
    printf -v c4 '%*s' "$wp" "$pct"
    boxline "${c1} ${blue}|${nc} ${c2} ${blue}|${nc} ${c3} ${blue}|${nc} $(pct_color "${pct%\%}")${c4}${nc}"
  done < <(df -h -P "${DISK_PATHS[@]}" 2>/dev/null | awk 'NR>1 && !seen[$6]++ {print $6"\t"$2"\t"$3"\t"$5}')
  boxrule
}

render_io() {
  local wd=27 w1=10 w2=10 w3=8 dev rs ws util c1 c2 c3 c4
  boxtitle "DISK I/O (1s)"
  printf -v c1 '%-*s' "$wd" "DEVICE"; printf -v c2 '%*s' "$w1" "r/s"
  printf -v c3 '%*s' "$w2" "w/s"; printf -v c4 '%*s' "$w3" "%util"
  boxline "${cyan}${c1}${nc} ${blue}|${nc} ${cyan}${c2}${nc} ${blue}|${nc} ${cyan}${c3}${nc} ${blue}|${nc} ${cyan}${c4}${nc}"
  if command -v iostat >/dev/null 2>&1; then
    local any=0
    while IFS=$'\t' read -r dev rs ws util; do
      [ -n "$dev" ] || continue
      any=1
      printf -v c1 '%-*.*s' "$wd" "$wd" "$dev"
      printf -v c2 '%*s' "$w1" "$rs"; printf -v c3 '%*s' "$w2" "$ws"
      printf -v c4 '%*s' "$w3" "$util"
      boxline "${c1} ${blue}|${nc} ${c2} ${blue}|${nc} ${c3} ${blue}|${nc} $(pct_color "${util%.*}")${c4}${nc}"
    done < <(iostat -xz 1 2 2>/dev/null | awk '
      /^Device/ { blk++; if(blk==2){ for(i=1;i<=NF;i++) idx[$i]=i; hdr=1 }; next }
      blk==2 && hdr && NF>0 { printf "%s\t%s\t%s\t%s\n", $1, $(idx["r/s"]), $(idx["w/s"]), $(idx["%util"]) }')
    [ "$any" = "1" ] || boxline "$(printf '%-*s' "$W" 'no active devices')"
  else
    boxline "$(printf '%-*s' "$W" 'iostat not installed (apt install sysstat)')"
  fi
  boxrule
}

rpc_state() {
  local port="$1"
  if timeout 4 curl -sS --max-time 3 -H 'Content-Type: application/json' \
       --data '{"method":"status","params":[],"id":1}' "http://127.0.0.1:${port}/" >/dev/null 2>&1; then
    printf 'OK'
  else
    printf 'down'
  fi
}

render_pool() {
  local wm=18 wv sh ad td last bj mhs acc rej stl q
  wv=$(( W - wm - 3 ))
  boxtitle "POOL"
  hdr2 "$wm" "$wv" "METRIC" "VALUE"
  q="SELECT COUNT(*),COALESCE(ROUND(AVG(difficulty),2),0),COALESCE(SUM(difficulty),0),IFNULL(MAX(time),'none') FROM (SELECT difficulty,time FROM ${POOL_DB}.shares UNION ALL SELECT difficulty,time FROM ${POOL_DB}.shares_archive) x WHERE time >= NOW() - INTERVAL 10 MINUTE;"
  IFS=$'\t' read -r sh ad td last < <(timeout 5 mysql -uroot -NBe "$q" 2>/dev/null)
  : "${sh:=?}" "${ad:=?}" "${td:=?}" "${last:=?}"
  row2 "$wm" "$wv" "shares (10m)" "$sh"
  row2 "$wm" "$wv" "avg diff" "$ad"
  row2 "$wm" "$wv" "total diff" "$td"
  row2 "$wm" "$wv" "last share" "$last"
  local ps pr
  ps="$(rpc_state "$POOL_PORT")"; pr="$(rpc_state "$PROXY_PORT")"
  row2 "$wm" "$wv" "pool rpc :$POOL_PORT" "$ps" "$(state_color "$ps")"
  row2 "$wm" "$wv" "proxy rpc :$PROXY_PORT" "$pr" "$(state_color "$pr")"
  if [ -n "${BAIKAL:-}" ]; then
    bj="$(sample_baikal)"
    if [ -n "$bj" ] && [ "$bj" != "{}" ]; then
      read -r mhs acc rej stl < <(jq -r '"\(.mhs5s) \(.accepted) \(.rejected) \(.stale)"' <<<"$bj" 2>/dev/null)
      row2 "$wm" "$wv" "baikal MHS 5s" "${mhs:-?}"
      row2 "$wm" "$wv" "baikal a/r/s" "$(printf '%s / %s / %s' "${acc:-?}" "${rej:-?}" "${stl:-?}")"
    else
      row2 "$wm" "$wv" "baikal" "unreachable ($BAIKAL)" "$red"
    fi
  fi
  boxrule
}

render_alerts() {
  local wm=40 wv ke pe
  wv=$(( W - wm - 3 ))
  boxtitle "ALERTS (last 15m)"
  hdr2 "$wm" "$wv" "SOURCE" "COUNT"
  ke="$(timeout 5 journalctl -k --since '15 minutes ago' --no-pager 2>/dev/null \
        | grep -Eic 'oom|out of memory|killed process|i/o error|blk_update_request' || true)"
  pe="$(timeout 6 journalctl \
          -u blakestream-mpos-eloipool.service -u blakestream-mpos-mergeminer.service \
          -u blakestream-mpos-sharelog-importer.service -u blakestream-mpos-cronjobs.service \
          -u mariadb.service --since '15 minutes ago' --no-pager 2>/dev/null \
        | grep -Eic 'stale|reject|error|failed|panic|oom' || true)"
  : "${ke:=0}" "${pe:=0}"
  row2 "$wm" "$wv" "kernel (oom/io)" "$ke" "$( [ "$ke" -gt 0 ] && printf '%s' "$red" || printf '%s' "$green")"
  row2 "$wm" "$wv" "pool/service (error/stale/reject)" "$pe" "$( [ "$pe" -gt 0 ] && printf '%s' "$red" || printf '%s' "$green")"
  boxrule
}

# Join two multi-line column strings side by side. Every box line is exactly W+4
# visible columns, so a blank/missing left line is replaced with that many spaces
# to keep the right column aligned; color codes occupy no visible width.
two_col() {
  local left="$1" right="$2" pad i n ll rr
  local -a L R
  mapfile -t L <<< "$left"
  mapfile -t R <<< "$right"
  n=${#L[@]}; [ "${#R[@]}" -gt "$n" ] && n=${#R[@]}
  printf -v pad '%*s' "$(( W + 4 ))" ''
  for (( i=0; i<n; i++ )); do
    ll="${L[i]-}"; rr="${R[i]-}"
    [ -n "$ll" ] || ll="$pad"
    printf '%s   %s\n' "$ll" "$rr"
  done
}

render_frame() {
  render_header; echo
  # Two columns when the terminal is wide enough for two boxes + a gap, else stack.
  if [ "${COLS:-80}" -ge "$(( 2*(W+4) + 3 ))" ]; then
    local LEFT RIGHT
    LEFT="$(render_services; echo; render_system; echo; render_io; echo; render_alerts)"
    RIGHT="$(render_processes; echo; render_disk; echo; render_pool)"
    two_col "$LEFT" "$RIGHT"
  else
    render_services;  echo
    render_processes; echo
    render_system;    echo
    render_disk;      echo
    render_io;        echo
    render_pool;      echo
    render_alerts
  fi
}

run_dashboard() {
  setup_colors
  trap 'printf "\033[?25h\n"; exit 0' INT TERM
  trap 'printf "\033[?25h"' EXIT
  printf '\033[?25l\033[2J'                       # hide cursor, clear once
  local frame
  while true; do
    COLS="$(tput cols 2>/dev/null || echo 80)"    # re-read each frame (handles resize)
    frame="$(render_frame)"                       # collect + format off-screen
    printf '\033[H%s\n\033[0J' "$frame"           # atomic repaint from home, clear below
    sleep "$REFRESH_SECONDS"
  done
}

run_logger() {
  [ "$HAVE_BANNER" = "1" ] && print_blakestream_banner
  local local_output local_rc
  while true; do
    echo "========== sample $(date -u +%Y-%m-%dT%H:%M:%SZ) =========="
    local_output=$(sample_local 2>&1); local_rc=$?
    printf '%s\n' "$local_output"
    echo "----- baikal summary -----"
    sample_baikal
    echo
    echo "sample_rc=$local_rc"
    sleep "$INTERVAL_SECONDS"
  done
}

if [ -t 1 ] && [ "${WATCH_TABLE:-1}" != "0" ]; then
  run_dashboard
else
  run_logger
fi
