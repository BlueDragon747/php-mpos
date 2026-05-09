#!/bin/bash
# MPOS pool health check — run from cron every few minutes, e.g.
#   */5 * * * * /opt/blakecoin-pool/bin/health-check.sh || mail -s 'MPOS ALERT' you@example.com < /tmp/mpos-health-last.txt
#
# Exits 0 if everything looks healthy, non-zero + writes a summary to
# $OUT_FILE otherwise. Written deliberately plain so you can read/modify
# without opinionated framework deps.

set -u

OUT_FILE="${OUT_FILE:-/tmp/mpos-health-last.txt}"
APACHE_URL="${APACHE_URL:-http://127.0.0.1/}"
STRATUM_HOST="${STRATUM_HOST:-127.0.0.1}"
STRATUM_PORT="${STRATUM_PORT:-3334}"
MEMCACHED_HOST="${MEMCACHED_HOST:-127.0.0.1}"
MEMCACHED_PORT="${MEMCACHED_PORT:-11211}"
MPOS_DB_CREDS="${MPOS_DB_CREDS:-/root/.mpos-db.creds}"
CHAIN_TIP_LAG_MAX_SEC="${CHAIN_TIP_LAG_MAX_SEC:-1800}"  # alert if primary chain tip > 30 min old

errors=()
warn=()
ok=()

# --- 1. Apache / MPOS web -------------------------------------------------
if curl -sfS -o /dev/null -m 5 "$APACHE_URL"; then
  ok+=("apache: $APACHE_URL 200")
else
  errors+=("apache: $APACHE_URL not responding")
fi

# --- 2. Stratum TCP accept ------------------------------------------------
if (echo > "/dev/tcp/$STRATUM_HOST/$STRATUM_PORT") >/dev/null 2>&1; then
  ok+=("stratum: $STRATUM_HOST:$STRATUM_PORT open")
else
  errors+=("stratum: $STRATUM_HOST:$STRATUM_PORT refused")
fi

# --- 3. Memcached reachable -----------------------------------------------
if (echo version; sleep 0.2) | nc -w 2 "$MEMCACHED_HOST" "$MEMCACHED_PORT" 2>/dev/null | grep -q VERSION; then
  ok+=("memcached: $MEMCACHED_HOST:$MEMCACHED_PORT ok")
else
  errors+=("memcached: $MEMCACHED_HOST:$MEMCACHED_PORT down")
fi

# --- 4. MySQL / MPOS row sanity -------------------------------------------
if [ -r "$MPOS_DB_CREDS" ]; then
  # shellcheck disable=SC1090
  . "$MPOS_DB_CREDS"
fi
: "${MPOS_DB_USER:=mpos}"
: "${MPOS_DB_PASS:=}"
if [ -n "$MPOS_DB_PASS" ]; then
  DB_STATE=$(mysql -u "$MPOS_DB_USER" -p"$MPOS_DB_PASS" -N -B mpos -e "
    SELECT CONCAT(
      'shares_last_5m=', (SELECT COUNT(*) FROM shares WHERE time >= NOW() - INTERVAL 5 MINUTE),
      ' unaccounted_blocks=', (SELECT COUNT(*) FROM blocks WHERE accounted=0),
      ' workers=', (SELECT COUNT(*) FROM pool_worker)
    )" 2>/dev/null)
  if [ -n "$DB_STATE" ]; then
    ok+=("mpos-db: $DB_STATE")
    # alert on completely idle pool (no shares in 5 min — we have workers set)
    if echo "$DB_STATE" | grep -q "shares_last_5m=0 " && echo "$DB_STATE" | grep -Eq "workers=[1-9]"; then
      warn+=("pool appears idle — no shares in last 5 minutes despite registered workers")
    fi
  else
    errors+=("mpos-db: query failed")
  fi
else
  warn+=("mpos-db: MPOS_DB_PASS not set, skipping DB checks")
fi

# --- 5. Coin daemons chain-tip lag ----------------------------------------
# Walk known datadirs; use whichever blakecoin-cli we can find. Operator
# can pin one with BLC_CLI, and a local libboost bundle with BLC_RUNTIME_LIBS.
export LD_LIBRARY_PATH="${BLC_RUNTIME_LIBS:-}${BLC_RUNTIME_LIBS:+:}${LD_LIBRARY_PATH:-}"
CLI_CANDIDATES=(
  "${BLC_CLI:-}"
  /opt/blakecoin-current/bin/blakecoin-cli
  /usr/local/bin/blakecoin-cli
  /usr/bin/blakecoin-cli
  "$(command -v blakecoin-cli 2>/dev/null || true)"
)
CLI=""
for c in "${CLI_CANDIDATES[@]}"; do [ -n "$c" ] && [ -x "$c" ] && { CLI="$c"; break; }; done

now=$(date +%s)
for dd in /home/*/.blakecoin /home/*/.blakebitcoin /home/*/.photon /home/*/.electron \
          /home/*/.lithium /home/*/.universalmolecule \
          /home/*/.blakecoin-regtest /home/*/.blakebitcoin-regtest \
          /home/*/.photon-regtest /home/*/.electron-regtest \
          /home/*/.lithium-regtest /home/*/.universalmolecule-regtest; do
  [ -d "$dd" ] || continue
  conf=$(ls "$dd"/*.conf 2>/dev/null | head -1)
  [ -n "$conf" ] || continue
  [ -n "$CLI" ] || continue
  # best-effort — some coins use differently-named cli binaries
  info=$("$CLI" -datadir="$dd" -conf="$conf" getblockchaininfo 2>/dev/null)
  [ -n "$info" ] || continue
  blocks=$(echo "$info" | grep '"blocks"' | tr -d ' ,' | cut -d: -f2)
  mediantime=$(echo "$info" | grep '"mediantime"' | tr -d ' ,' | cut -d: -f2)
  lag=$(( now - ${mediantime:-$now} ))
  name=$(basename "$dd" | sed 's/^\.//')
  if [ "$lag" -gt "$CHAIN_TIP_LAG_MAX_SEC" ] && echo "$info" | grep -q '"chain": "main"'; then
    errors+=("$name: tip ${lag}s behind wallclock on mainnet (blocks=$blocks)")
  else
    ok+=("$name: blocks=$blocks lag=${lag}s")
  fi
done

# --- 6. Eloipool / minerd processes ---------------------------------------
pgrep -af 'python3 eloipool.py' >/dev/null 2>&1 \
  && ok+=("eloipool: running") \
  || errors+=("eloipool: NOT running")

# --- Report ---------------------------------------------------------------
{
  echo "MPOS health check @ $(date -uIs)"
  echo
  if [ "${#errors[@]}" -gt 0 ]; then
    echo "ERRORS:"
    for e in "${errors[@]}"; do echo "  - $e"; done
    echo
  fi
  if [ "${#warn[@]}" -gt 0 ]; then
    echo "WARNINGS:"
    for w in "${warn[@]}"; do echo "  - $w"; done
    echo
  fi
  echo "OK:"
  for o in "${ok[@]}"; do echo "  - $o"; done
} > "$OUT_FILE"

if [ "${#errors[@]}" -gt 0 ]; then
  cat "$OUT_FILE"
  exit 1
fi
exit 0
