#!/usr/bin/env bash
set -u

# BlakeStream MPOS/Eloipool pool watch — a live dashboard that mirrors the pool's
# system-status pages: hashrate, workers, network height/difficulty, share rate,
# per-coin block finds (merged mining), proxy chain health, and a stall verdict.
#
# - Read-only. Does not restart services or change miner/pool configuration.
# - Reads the local Go pool RPC, the merged-mining proxy RPC, the MPOS MariaDB
#   tables, process stats, and OOM logs. Optional miner context via BAIKAL.
#
# Two display modes (auto-selected):
# - Interactive (stdout is a terminal): a LIVE in-place dashboard, two columns
#   when wide enough, refreshing every REFRESH_SECONDS (default 10). The stall
#   VERDICT is evaluated over the proper INTERVAL_SECONDS window. Ctrl-C to quit.
# - Redirected/background (not a terminal): one line-oriented sample every
#   INTERVAL_SECONDS for tailing/archiving. Force on a terminal with WATCH_TABLE=0.
#
# Usage:
#   chmod +x ./pool-watch.sh
#   ./pool-watch.sh                                   # live dashboard
#   REFRESH_SECONDS=5 ./pool-watch.sh
#   BAIKAL=miner-lan-ip ./pool-watch.sh              # add miner-side context
#   INTERVAL_SECONDS=300 nohup ./pool-watch.sh >> /tmp/pool-watch.log 2>&1 &
#
# Env: POOL_DB (mpos), POOL_PORT (19334), PROXY_PORT (19335), BAIKAL,
#      POOL_CHAINS ("COIN:blocks_table ..." parent first), HASH_WINDOW (600).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HAVE_BANNER=0
if [ -r "${SCRIPT_DIR}/lib/tool-banner.sh" ]; then
  # shellcheck disable=SC1091
  . "${SCRIPT_DIR}/lib/tool-banner.sh"
  HAVE_BANNER=1
fi

POOL_DB="${POOL_DB:-mpos}"
case "$POOL_DB" in
  ''|*[!A-Za-z0-9_]*) printf 'Invalid POOL_DB value: %s\n' "$POOL_DB" >&2; exit 1 ;;
esac

BAIKAL="${BAIKAL-}"
INTERVAL_SECONDS=${INTERVAL_SECONDS:-300}   # stall-evaluation window (and logger cadence)
REFRESH_SECONDS=${REFRESH_SECONDS:-10}      # live dashboard display refresh
HASH_WINDOW=${HASH_WINDOW:-600}             # seconds of shares used for the hashrate estimate
POOL_PORT="${POOL_PORT:-19334}"
PROXY_PORT="${PROXY_PORT:-19335}"
# Coin -> blocks table, parent first. Matches the merged-mine slot assignment
# (proxy: MM=BBTC, MM1=ELT, MM3=LIT, MM4=PHO, MM5=UMO; parent=BLC). Override if a
# deployment assigns slots differently.
POOL_CHAINS="${POOL_CHAINS:-BLC:blocks PHO:blocks_mm4 BBTC:blocks_mm ELT:blocks_mm1 LIT:blocks_mm3 UMO:blocks_mm5}"
PARENT_COIN="${POOL_CHAINS%%:*}"

# Build the per-coin block-finds query once (passed to the sampler via env).
build_blocks_sql() {
  local pair coin tbl sql=""
  for pair in $POOL_CHAINS; do
    coin="${pair%%:*}"; tbl="${pair##*:}"
    case "$tbl" in ''|*[!A-Za-z0-9_]*) continue ;; esac
    [ -n "$sql" ] && sql="$sql UNION ALL "
    sql="$sql SELECT '${coin}',COUNT(*),COALESCE(SUM(confirmations>0),0),COALESCE(SUM(accounted=0),0),IFNULL(MAX(time),0) FROM ${tbl}"
  done
  printf '%s' "$sql"
}
BLOCKS_SQL="$(build_blocks_sql)"

# ---------------------------------------------------------------------------
# Collectors
# ---------------------------------------------------------------------------
sample_local() {
  timeout 30 env POOL_DB="$POOL_DB" POOL_PORT="$POOL_PORT" PROXY_PORT="$PROXY_PORT" \
    HASH_WINDOW="$HASH_WINDOW" BLOCKS_SQL="$BLOCKS_SQL" bash -s <<'LOCAL'
set -u
pool=$(curl -sS --max-time 3 -H 'Content-Type: application/json' --data '{"method":"status","params":[],"id":1}' "http://127.0.0.1:${POOL_PORT}/" | jq -c '.result')
proxy=$(curl -sS --max-time 3 -H 'Content-Type: application/json' --data '{"method":"status","params":[],"id":1}' "http://127.0.0.1:${PROXY_PORT}/" | jq -c '{ready:.result.ready_count,total:.result.total_chains,sub:.result.submissions,templates:.result.templates,cache:.result.cache,waiting:.result.waiting_chains,ready_list:.result.ready_chains}')
sessions=$(ss -tn state established sport = :3334 | tail -n +2 | wc -l)
db=$(mysql -uroot -NBe "SELECT COUNT(*),COALESCE(SUM(difficulty),0),COALESCE(ROUND(AVG(difficulty),2),0),IFNULL(MIN(time),'none'),IFNULL(MAX(time),'none'),IFNULL(TIMESTAMPDIFF(SECOND,MAX(time),NOW()),-1) FROM (SELECT difficulty,time FROM ${POOL_DB}.shares UNION ALL SELECT difficulty,time FROM ${POOL_DB}.shares_archive) x WHERE time >= NOW() - INTERVAL 10 MINUTE;")
stats=$(mysql -uroot -NBe "SELECT COALESCE(SUM(valid_diff),0),COALESCE(SUM(valid_count),0),COALESCE(SUM(invalid_count),0),COUNT(DISTINCT username) FROM ${POOL_DB}.share_stats_recent WHERE bucket_ts >= UNIX_TIMESTAMP()-${HASH_WINDOW};")
netdiff=$(mysql -uroot -NBe "SELECT IFNULL((SELECT difficulty FROM ${POOL_DB}.blocks ORDER BY id DESC LIMIT 1),0);")
blocks=$(mysql -uroot -NBe "${BLOCKS_SQL};" "${POOL_DB}")
rss=$(ps -o comm=,pcpu=,rss= -C eloipool-go -C merged-mine-proxy-go -C mariadbd | awk '{printf "%s:%s:%s ", $1, $2, $3}')
oom=$(journalctl -k --since "15 minutes ago" --no-pager | grep -Eic 'oom|out of memory|killed process' || true)
jq -nc --argjson pool "$pool" --argjson proxy "$proxy" --arg sessions "$sessions" --arg db "$db" --arg stats "$stats" --arg netdiff "$netdiff" --arg blocks "$blocks" --arg rss "$rss" --arg oom "$oom" '{sessions:($sessions|tonumber),pool:$pool,proxy:$proxy,db_last_10m:$db,stats_window:$stats,net_difficulty:$netdiff,blocks:$blocks,rss_kib:$rss,oom_recent:($oom|tonumber)}'
LOCAL
}

sample_baikal() {
  if [ -z "${BAIKAL:-}" ]; then printf '{}'; return; fi
  timeout 10 bash -c "printf '{\"command\":\"summary\"}\n' | nc -w 5 '$BAIKAL' 4028 | tr '\0' '\n' | jq -c '.SUMMARY[0] | {accepted:.Accepted,rejected:.Rejected,stale:.Stale,mhs5s:.\"MHS 5s\",getfail:.\"Get Failures\",remotefail:.\"Remote Failures\"}'" 2>/dev/null || printf '{}'
}

# ---------------------------------------------------------------------------
# Box / table rendering
# ---------------------------------------------------------------------------
W=64

setup_colors() {
  if [ -t 1 ]; then
    blue=$'\033[0;34m'; cyan=$'\033[0;36m'; green=$'\033[0;32m'
    red=$'\033[0;31m'; yellow=$'\033[1;33m'; orange=$'\033[38;5;208m'; nc=$'\033[0m'
  else
    blue=; cyan=; green=; red=; yellow=; orange=; nc=
  fi
}

boxrule()  { local r; printf -v r '%*s' "$((W+4))" ''; printf '%s%s%s\n' "$blue" "${r// /=}" "$nc"; }
boxtitle() {
  local t="$1" tot=$((W+4)) tl tr L R
  tl=$(( (tot-${#t}-2)/2 )); tr=$(( tot-${#t}-2-tl ))
  printf -v L '%*s' "$tl" ''; printf -v R '%*s' "$tr" ''
  printf '%s%s %s%s%s %s%s\n' "$blue" "${L// /=}" "$cyan" "$t" "$blue" "${R// /=}" "$nc"
}
boxline()   { printf '%s=%s %s %s=%s\n' "$blue" "$nc" "$1" "$blue" "$nc"; }
boxcenter() {
  local t="$1" col="${2:-}" l r
  l=$(( (W-${#t})/2 )); [ "$l" -lt 0 ] && l=0; r=$(( W-${#t}-l )); [ "$r" -lt 0 ] && r=0
  printf -v t '%*s%s%*s' "$l" '' "$t" "$r" ''
  boxline "${col}${t}${nc}"
}

human_kb() { awk -v k="${1:-0}" 'BEGIN{ if(k>=1048576) printf "%.1fG",k/1048576; else if(k>=1024) printf "%.0fM",k/1024; else printf "%dK",k }'; }
human_age() { # seconds -> compact age
  awk -v s="${1:-0}" 'BEGIN{ if(s<0){print "never";exit} d=int(s/86400);s%=86400;h=int(s/3600);s%=3600;m=int(s/60);x=s%60;
    if(d>0)printf "%dd%dh",d,h; else if(h>0)printf "%dh%dm",h,m; else if(m>0)printf "%dm%ds",m,x; else printf "%ds",x }'; }
human_hs() { # work-difficulty over window -> hashrate string (diff*2^32/window)
  awk -v d="${1:-0}" -v w="${2:-600}" 'BEGIN{ if(w<=0){print "-";exit} h=d*4294967296/w;
    if(h>=1e18)printf "%.2f EH/s",h/1e18; else if(h>=1e15)printf "%.2f PH/s",h/1e15; else if(h>=1e12)printf "%.2f TH/s",h/1e12;
    else if(h>=1e9)printf "%.2f GH/s",h/1e9; else if(h>=1e6)printf "%.2f MH/s",h/1e6; else if(h>=1e3)printf "%.2f KH/s",h/1e3; else printf "%.0f H/s",h }'; }

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

# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------
parse_sample() {
  local s="$1"
  IFS=$'\t' read -r cur_accepted cur_gotwork cur_miners cur_aux cur_templates \
    cur_ready cur_total cur_failed cur_notacc cur_oom cur_sessions \
    cur_height cur_rejected cur_gwskip cur_stale cur_attempts cur_refresh cur_lastdur cur_buildwait cur_netdiff \
    < <(jq -r '[.pool.accepted//0,.pool.gotwork_sent//0,.pool.miners//0,.pool.aux_age//0,.proxy.templates.builds//0,.proxy.ready//0,.proxy.total//0,.proxy.sub.failed//0,.proxy.sub.not_accepted//0,.oom_recent//0,.sessions//0,.pool.height//0,.pool.rejected//0,.pool.gotwork_skipped//0,.proxy.sub.stale//0,.proxy.sub.attempts//0,.proxy.templates.refresh_interval_secs//0,.proxy.templates.last_duration_ms//0,.proxy.templates.last_build_wait_ms//0,(.net_difficulty//0)]|@tsv' <<<"$s" 2>/dev/null)
  : "${cur_accepted:=0}" "${cur_gotwork:=0}" "${cur_miners:=0}" "${cur_aux:=0}" "${cur_templates:=0}"
  : "${cur_ready:=0}" "${cur_total:=0}" "${cur_failed:=0}" "${cur_notacc:=0}" "${cur_oom:=0}" "${cur_sessions:=0}"
  : "${cur_height:=0}" "${cur_rejected:=0}" "${cur_gwskip:=0}" "${cur_stale:=0}" "${cur_attempts:=0}"
  : "${cur_refresh:=0}" "${cur_lastdur:=0}" "${cur_buildwait:=0}" "${cur_netdiff:=0}"
  IFS=$'\t' read -r st_diff st_valid st_invalid st_workers < <(printf '%s' "$(jq -r '.stats_window // ""' <<<"$s" 2>/dev/null)")
  : "${st_diff:=0}" "${st_valid:=0}" "${st_invalid:=0}" "${st_workers:=0}"
  cur_waiting="$(jq -r '(.proxy.waiting // []) | map(if type=="object" then (.chain // .alias // tostring) else tostring end) | join(",")' <<<"$s" 2>/dev/null)"
  cur_blocks="$(jq -r '.blocks // ""' <<<"$s" 2>/dev/null)"
  cur_rss="$(jq -r '.rss_kib // ""' <<<"$s" 2>/dev/null)"
  cur_db="$(jq -r '.db_last_10m // ""' <<<"$s" 2>/dev/null)"
}

moving_cell() { local d="$1"; if [ "$d" = "-" ]; then printf '%s\t%s' '-' "$nc"; elif [ "$d" -gt 0 ] 2>/dev/null; then printf '%s\t%s' 'yes' "$green"; else printf '%s\t%s' 'no' "$yellow"; fi; }

# ---------------------------------------------------------------------------
# Dashboard tables
# ---------------------------------------------------------------------------
render_header() {
  local host
  host="$(hostname -s 2>/dev/null || hostname)"
  printf '%sBlakeStream pool watch%s  %s%s%s  %sparent%s %s\n' "$orange" "$nc" "$cyan" "$host" "$nc" "$cyan" "$nc" "$PARENT_COIN"
  printf '%supdated%s %s   %srefresh%s %ss   %swindow%s %ss   %squit%s Ctrl-C\n' \
    "$cyan" "$nc" "$TS" "$cyan" "$nc" "$REFRESH_SECONDS" "$cyan" "$nc" "$INTERVAL_SECONDS" "$cyan" "$nc"
}

render_status() {
  boxtitle "STATUS"
  if [ "${LAST_OK:-0}" != "1" ]; then
    boxcenter "SAMPLE ERROR (rc=${LAST_RC:-?})" "$red"
    boxcenter "pool RPC / proxy / db unreachable — see the log" "$nc"
    boxrule; return
  fi
  boxcenter "$VERDICT" "$VC"
  boxcenter "miners ${cur_miners} | workers ${st_workers} | next check ${REMAINING}s" "$nc"
  boxrule
}

render_overview() {
  local wm=18 wv eff col cnt sum avg first last age
  wv=$(( W - wm - 3 ))
  IFS=$'\t' read -r cnt sum avg first last age <<<"${cur_db:-}"
  : "${age:=-1}"
  eff="-"
  if [ "$(( st_valid + st_invalid ))" -gt 0 ] 2>/dev/null; then
    eff="$(awk -v v="$st_valid" -v i="$st_invalid" 'BEGIN{printf "%.1f%%", 100*v/(v+i)}')"
  fi
  boxtitle "POOL OVERVIEW"
  hdr2 "$wm" "$wv" "METRIC" "VALUE"
  row2 "$wm" "$wv" "hashrate (${HASH_WINDOW}s)" "$(human_hs "$st_diff" "$HASH_WINDOW")" "$green"
  row2 "$wm" "$wv" "active workers" "$st_workers"
  row2 "$wm" "$wv" "miners / sessions" "$(printf '%s / %s' "$cur_miners" "$cur_sessions")"
  row2 "$wm" "$wv" "network height" "$cur_height"
  row2 "$wm" "$wv" "network difficulty" "$(awk -v d="$cur_netdiff" 'BEGIN{printf "%.6g", d}')"
  row2 "$wm" "$wv" "shares 10m v/i" "$(printf '%s / %s' "$st_valid" "$st_invalid")"
  col="$green"; case "$eff" in 9[0-9].*%|100*%) col="$green" ;; [5-8][0-9].*%) col="$yellow" ;; -) col="$nc" ;; *) col="$red" ;; esac
  row2 "$wm" "$wv" "efficiency" "$eff" "$col"
  if [ "$age" -ge 0 ] 2>/dev/null; then
    col="$green"; [ "$age" -gt 60 ] && col="$yellow"; [ "$age" -gt 300 ] && col="$red"
    row2 "$wm" "$wv" "last share" "$(human_age "$age") ago" "$col"
  else
    row2 "$wm" "$wv" "last share" "none" "$red"
  fi
  boxrule
}

# Per-coin block finds — the merged-mining picture (which coins are finding blocks).
render_blocks() {
  local wc=6 wf=9 wcf=9 wp=9 wl c1 c2 c3 c4 c5 coin found conf pend lastts age now col
  wl=$(( W - wc - wf - wcf - wp - 12 ))
  now="$(date +%s)"
  boxtitle "BLOCK FINDS (per coin)"
  printf -v c1 '%-*s' "$wc" "COIN"; printf -v c2 '%*s' "$wf" "FOUND"
  printf -v c3 '%*s' "$wcf" "CONF"; printf -v c4 '%*s' "$wp" "PENDING"; printf -v c5 '%-*s' "$wl" "LAST"
  boxline "${cyan}${c1}${nc} ${blue}|${nc} ${cyan}${c2}${nc} ${blue}|${nc} ${cyan}${c3}${nc} ${blue}|${nc} ${cyan}${c4}${nc} ${blue}|${nc} ${cyan}${c5}${nc}"
  if [ -n "${cur_blocks:-}" ]; then
    while IFS=$'\t' read -r coin found conf pend lastts; do
      [ -n "$coin" ] || continue
      if [ "${lastts:-0}" -gt 0 ] 2>/dev/null; then age="$(human_age "$(( now - lastts ))") ago"; else age="-"; fi
      col="$green"; [ "${found:-0}" -eq 0 ] 2>/dev/null && col="$yellow"
      printf -v c1 '%-*s' "$wc" "$coin"; printf -v c2 '%*s' "$wf" "$found"
      printf -v c3 '%*s' "$wcf" "$conf"; printf -v c4 '%*s' "$wp" "$pend"; printf -v c5 '%-*s' "$wl" "$age"
      boxline "${col}${c1}${nc} ${blue}|${nc} ${c2} ${blue}|${nc} ${c3} ${blue}|${nc} ${c4} ${blue}|${nc} ${c5}"
    done <<< "$cur_blocks"
  else
    boxline "$(printf '%-*s' "$W" '(no block data)')"
  fi
  boxrule
}

render_progress() {
  local ws=20 wn=12 wd=10 wm c1 c2 c3 c4 mv col
  wm=$(( W - ws - wn - wd - 9 ))
  boxtitle "PROGRESS (stall signals)"
  printf -v c1 '%-*s' "$ws" "SIGNAL"; printf -v c2 '%*s' "$wn" "NOW"
  printf -v c3 '%*s' "$wd" "WIN +/-"; printf -v c4 '%-*s' "$wm" "MOVING"
  boxline "${cyan}${c1}${nc} ${blue}|${nc} ${cyan}${c2}${nc} ${blue}|${nc} ${cyan}${c3}${nc} ${blue}|${nc} ${cyan}${c4}${nc}"
  _prow() {
    IFS=$'\t' read -r mv col < <(moving_cell "$3")
    printf -v c1 '%-*s' "$ws" "$1"; printf -v c2 '%*s' "$wn" "$2"
    printf -v c3 '%*s' "$wd" "$3"; printf -v c4 '%-*s' "$wm" "$mv"
    boxline "${c1} ${blue}|${nc} ${c2} ${blue}|${nc} ${c3} ${blue}|${nc} ${col}${c4}${nc}"
  }
  _prow "accepted shares" "$cur_accepted" "${DW_ACCEPTED:--}"
  _prow "gotwork sent"    "$cur_gotwork"  "${DW_GOTWORK:--}"
  _prow "proxy templates" "$cur_templates" "${DW_TEMPLATES:--}"
  _prow "work height"     "$cur_height"   "${DW_HEIGHT:--}"
  boxrule
}

render_proxy() {
  local wm=22 wv col rt
  wv=$(( W - wm - 3 ))
  boxtitle "PROXY / CHAINS"
  hdr2 "$wm" "$wv" "METRIC" "VALUE"
  rt="${cur_ready}/${cur_total}"
  col="$green"; [ "$cur_ready" != "$cur_total" ] && col="$red"
  row2 "$wm" "$wv" "chains ready/total" "$rt" "$col"
  if [ -n "${cur_waiting:-}" ]; then row2 "$wm" "$wv" "waiting chains" "$cur_waiting" "$red"
  else row2 "$wm" "$wv" "waiting chains" "none" "$green"; fi
  row2 "$wm" "$wv" "aux age (s)" "$cur_aux" "$( [ "${cur_aux%%.*}" -gt 30 ] 2>/dev/null && printf '%s' "$red" || printf '%s' "$green")"
  row2 "$wm" "$wv" "template builds" "$cur_templates"
  row2 "$wm" "$wv" "build timing" "$(printf '%ss int / %sms last / %sms wait' "$cur_refresh" "$cur_lastdur" "$cur_buildwait")"
  row2 "$wm" "$wv" "submit attempts" "$cur_attempts"
  col="$green"; [ "${cur_stale:-0}" -gt 0 ] 2>/dev/null && col="$yellow"; [ "${cur_failed:-0}" -gt 0 ] 2>/dev/null && col="$red"
  row2 "$wm" "$wv" "submit fail/stale/na" "$(printf '%s / %s / %s' "$cur_failed" "$cur_stale" "$cur_notacc")" "$col"
  boxrule
}

render_procs() {
  local wm=22 wc=6 wv kv name cpu kib c1 c2
  wv=$(( W - wm - wc - 6 ))
  boxtitle "PROCESSES"
  printf -v c1 '%-*s' "$wm" "PROCESS"; printf -v c2 '%*s' "$wc" "CPU%"
  boxline "${cyan}${c1}${nc} ${blue}|${nc} ${cyan}${c2}${nc} ${blue}|${nc} ${cyan}$(printf '%-*s' "$wv" RSS)${nc}"
  if [ -n "${cur_rss:-}" ]; then
    for kv in $cur_rss; do
      name="${kv%%:*}"; kib="${kv##*:}"; cpu="${kv#*:}"; cpu="${cpu%:*}"
      [ -n "$name" ] || continue
      printf -v c1 '%-*s' "$wm" "$name"; printf -v c2 '%*s' "$wc" "$cpu"
      boxline "${c1} ${blue}|${nc} ${c2} ${blue}|${nc} $(printf '%-*s' "$wv" "$(human_kb "$kib")")"
    done
  else
    boxline "$(printf '%-*s' "$W" '(no data)')"
  fi
  boxrule
}

render_miner() {
  local wm=18 wv mhs acc rej stl gf
  wv=$(( W - wm - 3 ))
  boxtitle "MINER (baikal)"
  hdr2 "$wm" "$wv" "METRIC" "VALUE"
  if [ -n "${BAIKAL_JSON:-}" ] && [ "${BAIKAL_JSON}" != "{}" ]; then
    read -r mhs acc rej stl gf < <(jq -r '"\(.mhs5s) \(.accepted) \(.rejected) \(.stale) \(.getfail)"' <<<"$BAIKAL_JSON" 2>/dev/null)
    row2 "$wm" "$wv" "MHS 5s" "${mhs:-?}"
    row2 "$wm" "$wv" "accepted" "${acc:-?}"
    row2 "$wm" "$wv" "rejected" "${rej:-?}" "$( [ "${rej:-0}" -gt 0 ] 2>/dev/null && printf '%s' "$yellow" || printf '%s' "$green")"
    row2 "$wm" "$wv" "stale / getfail" "$(printf '%s / %s' "${stl:-?}" "${gf:-?}")"
  else
    row2 "$wm" "$wv" "reachable" "no ($BAIKAL)" "$red"
  fi
  boxrule
}

render_frame() {
  render_header; echo
  render_status; echo
  local LEFT RIGHT
  LEFT="$(render_overview; echo; render_blocks)"
  if [ -n "${BAIKAL:-}" ]; then
    RIGHT="$(render_progress; echo; render_proxy; echo; render_procs; echo; render_miner)"
  else
    RIGHT="$(render_progress; echo; render_proxy; echo; render_procs)"
  fi
  if [ "${COLS:-80}" -ge "$(( 2*(W+4) + 3 ))" ]; then
    two_col "$LEFT" "$RIGHT"
  else
    printf '%s\n' "$LEFT"; echo; printf '%s\n' "$RIGHT"
  fi
}

# ---------------------------------------------------------------------------
# Run loops
# ---------------------------------------------------------------------------
run_dashboard() {
  setup_colors
  trap 'printf "\033[?25h\n"; exit 0' INT TERM
  trap 'printf "\033[?25h"' EXIT
  printf '\033[?25l\033[2J'
  local base_accepted="" base_gotwork="" base_templates="" base_height="" last_eval=0 warmed=0
  local now elapsed progress_ok proxy_health frame
  stalled_samples=0; VERDICT="WARMING UP"; VC="$cyan"
  while true; do
    COLS="${WATCH_COLS:-}"; [ -n "$COLS" ] || COLS="$(tput cols 2>/dev/null || true)"; [ -n "$COLS" ] || COLS="${COLUMNS:-80}"
    TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; now="$(date +%s)"
    local_sample="$(sample_local 2>&1)"; LAST_RC=$?
    BAIKAL_JSON="$(sample_baikal)"
    if [ "$LAST_RC" -eq 0 ]; then
      LAST_OK=1
      parse_sample "$local_sample"
      if [ -z "$base_accepted" ]; then
        base_accepted=$cur_accepted; base_gotwork=$cur_gotwork; base_templates=$cur_templates; base_height=$cur_height; last_eval=$now
        DW_ACCEPTED="-"; DW_GOTWORK="-"; DW_TEMPLATES="-"; DW_HEIGHT="-"
      else
        DW_ACCEPTED=$(( cur_accepted - base_accepted ))
        DW_GOTWORK=$(( cur_gotwork - base_gotwork ))
        DW_TEMPLATES=$(( cur_templates - base_templates ))
        DW_HEIGHT=$(( cur_height - base_height ))
      fi
      proxy_health=0
      { [ "$cur_ready" != "$cur_total" ] || [ "${cur_failed:-0}" -gt 0 ] 2>/dev/null; } && proxy_health=1
      elapsed=$(( now - last_eval ))
      if [ "$elapsed" -ge "$INTERVAL_SECONDS" ]; then
        progress_ok=1
        if [ "$cur_accepted" -le "$base_accepted" ] && [ "$cur_gotwork" -le "$base_gotwork" ] && [ "$cur_templates" -le "$base_templates" ]; then
          progress_ok=0
        fi
        if [ "${cur_miners:-0}" -gt 0 ] && [ "$progress_ok" -eq 0 ] && { [ "${cur_aux%%.*}" -gt 30 ] 2>/dev/null || [ "$cur_templates" -le "$base_templates" ]; }; then
          stalled_samples=$(( stalled_samples + 1 ))
        else
          stalled_samples=0
        fi
        base_accepted=$cur_accepted; base_gotwork=$cur_gotwork; base_templates=$cur_templates; base_height=$cur_height; last_eval=$now; warmed=1
      fi
      REMAINING=$(( INTERVAL_SECONDS - (now - last_eval) )); [ "$REMAINING" -lt 0 ] && REMAINING=0
      if [ "$stalled_samples" -gt 0 ]; then VERDICT="STALL CANDIDATE x${stalled_samples}"; VC="$red"
      elif [ "$proxy_health" -eq 1 ]; then VERDICT="PROXY HEALTH"; VC="$yellow"
      elif [ "$warmed" -ne 1 ]; then VERDICT="WARMING UP (${REMAINING}s)"; VC="$cyan"
      else VERDICT="HEALTHY"; VC="$green"; fi
    else
      LAST_OK=0
    fi
    frame="$(render_frame)"
    printf '\033[H%s\n\033[0J' "$frame"
    sleep "$REFRESH_SECONDS"
  done
}

run_logger() {
  [ "$HAVE_BANNER" = "1" ] && print_blakestream_banner
  local prev_accepted= prev_gotwork= prev_templates= ts local_sample local_rc baikal
  local accepted gotwork miners aux_age templates ready total failed not_accepted progress_ok alert
  stalled_samples=0
  while true; do
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local_sample=$(sample_local 2>&1); local_rc=$?
    baikal=$(sample_baikal)
    if [ "$local_rc" -ne 0 ]; then
      printf '%s local_error rc=%s output=%q baikal=%s\n' "$ts" "$local_rc" "$local_sample" "$baikal"
      sleep "$INTERVAL_SECONDS"; continue
    fi
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
      if [ "$accepted" -le "$prev_accepted" ] && [ "$gotwork" -le "$prev_gotwork" ] && [ "$templates" -le "$prev_templates" ]; then
        progress_ok=0
      fi
    fi
    alert=""
    if [ "$miners" -gt 0 ] && [ "$progress_ok" -eq 0 ] && { [ "$aux_age" -gt 30 ] || [ "$templates" -le "${prev_templates:-0}" ]; }; then
      stalled_samples=$((stalled_samples + 1)); alert="stall_candidate_${stalled_samples}"
    else
      stalled_samples=0
    fi
    if [ "$ready" -ne "$total" ] || [ "$failed" -gt 0 ]; then alert="${alert:+$alert,}proxy_health"; fi
    printf '%s local=%s baikal=%s alert=%s\n' "$ts" "$local_sample" "$baikal" "${alert:-none}"
    prev_accepted=$accepted; prev_gotwork=$gotwork; prev_templates=$templates
    sleep "$INTERVAL_SECONDS"
  done
}

if [ -t 1 ] && [ "${WATCH_TABLE:-1}" != "0" ]; then
  run_dashboard
else
  run_logger
fi
