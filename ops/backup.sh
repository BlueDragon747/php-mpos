#!/bin/bash
# Blakestream-MPOS nightly backup.
#
# What it backs up:
#   1. MPOS MySQL DB (mysqldump, gzipped, daily rotation = 14)
#   2. Each live coin daemon's wallet.dat (via backupwallet RPC)
#   3. Each coin daemon's <coin>.conf (read-only copy)
#   4. /var/www/mpos/public/include/config/global.inc.php (contains live SALT + creds)
#
# Invocation: sudo -u root ops/backup.sh  (or via cron as root)
#
# Required env (override per-install, defaults work for the lab box):
#   BACKUP_DIR       — where the tarballs go           (default /var/backups/mpos)
#   RETAIN_DAYS      — how many days to keep           (default 14)
#   MPOS_DB_CREDS    — path to a file with two lines:  (default /root/.mpos-db.creds)
#                        MPOS_DB_USER=mpos
#                        MPOS_DB_PASS=<password>

set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/var/backups/mpos}"
RETAIN_DAYS="${RETAIN_DAYS:-14}"
MPOS_DB_CREDS="${MPOS_DB_CREDS:-/root/.mpos-db.creds}"

mkdir -p "$BACKUP_DIR"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="$BACKUP_DIR/$TS"
mkdir -p "$OUT"

# --- 1. MPOS DB dump --------------------------------------------------------
if [ -r "$MPOS_DB_CREDS" ]; then
  # shellcheck disable=SC1090
  . "$MPOS_DB_CREDS"
fi
: "${MPOS_DB_USER:=mpos}"
: "${MPOS_DB_PASS:?MPOS_DB_PASS not set — add to $MPOS_DB_CREDS}"

echo "[$(date -uIs)] dumping mpos DB"
mysqldump --single-transaction --quick --routines --triggers \
  -u "$MPOS_DB_USER" -p"$MPOS_DB_PASS" mpos \
  | gzip -9 > "$OUT/mpos.sql.gz"

# --- 2. wallet.dat per coin -------------------------------------------------
# Discover coins via conf files under common locations.
echo "[$(date -uIs)] backing up wallets"
for home in /home/*/.blakecoin /home/*/.blakebitcoin /home/*/.photon \
            /home/*/.electron /home/*/.lithium /home/*/.universalmolecule \
            /root/.blakecoin /root/.blakebitcoin /root/.photon \
            /root/.electron /root/.lithium /root/.universalmolecule; do
  [ -d "$home" ] || continue
  # Only back up the main (mainnet) wallet — skip -testnet/-regtest/-peer siblings.
  case "$home" in *-*) continue ;; esac
  conf=$(ls "$home"/*.conf 2>/dev/null | head -1) || continue
  [ -n "$conf" ] || continue
  coin=$(basename "$home" | sed 's/^\.//')
  # Guess cli binary path. Operator can override per-coin via <COIN>_CLI env
  # (e.g. BLC_CLI=/opt/blakecoin-current/bin/blakecoin-cli) or rely on PATH.
  cli=""
  coin_cli_var="$(echo "${coin}" | tr 'a-z' 'A-Z')_CLI"
  for candidate in \
    "${!coin_cli_var:-}" \
    /opt/${coin}-current/bin/${coin}-cli \
    /usr/local/bin/${coin}-cli \
    /usr/bin/${coin}-cli \
    "$(command -v ${coin}-cli 2>/dev/null || true)"; do
    [ -n "$candidate" ] && [ -x "$candidate" ] && { cli="$candidate"; break; }
  done
  if [ -z "$cli" ]; then
    echo "  [warn] no cli for $coin — skipping wallet RPC backup"
    continue
  fi
  # Ask the daemon to dump its wallet to a safe file we'll tar up.
  # BLC_RUNTIME_LIBS lets the operator point at a local libboost
  # bundle; otherwise we rely on the system loader.
  target="$OUT/$coin.wallet.dat"
  if LD_LIBRARY_PATH="${BLC_RUNTIME_LIBS:-}${BLC_RUNTIME_LIBS:+:}${LD_LIBRARY_PATH:-}" \
      "$cli" -datadir="$home" -conf="$conf" backupwallet "$target" 2>/dev/null; then
    echo "  [ok ] $coin"
  else
    echo "  [skip] $coin (RPC unreachable or backupwallet unsupported)"
  fi
  cp -p "$conf" "$OUT/$coin.conf" 2>/dev/null || true
done

# --- 3. MPOS live config ----------------------------------------------------
if [ -r /var/www/mpos/public/include/config/global.inc.php ]; then
  cp /var/www/mpos/public/include/config/global.inc.php "$OUT/mpos-global.inc.php"
fi

# --- 4. tar + perms ---------------------------------------------------------
chmod 700 "$OUT"
chown -R root:root "$OUT"

# --- 5. prune old snapshots -------------------------------------------------
find "$BACKUP_DIR" -maxdepth 1 -mindepth 1 -type d -mtime +"$RETAIN_DAYS" -exec rm -rf {} + || true

echo "[$(date -uIs)] backup complete: $OUT"
