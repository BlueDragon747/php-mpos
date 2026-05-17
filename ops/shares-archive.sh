#!/bin/bash
# ops/shares-archive.sh — rotate old rows from mpos.shares to mpos.shares_archive.
#
# Run periodically (the shipped /etc/cron.d/mpos invokes this every 4h).
# Without this, mpos.shares grows without bound as miners submit work —
# tens of thousands of rows per day per miner.
#
# Strategy: anything strictly older than KEEP_HOURS (default 48h) that's
# PAST the most-recently-accounted block's share_id (so PPLNS doesn't
# try to read its history out from under itself) gets moved.

set -eu

: "${MPOS_DB_CREDS:=/root/.mpos-db.creds}"
: "${KEEP_HOURS:=48}"

if [ -r "$MPOS_DB_CREDS" ]; then
  # shellcheck disable=SC1090
  . "$MPOS_DB_CREDS"
fi
: "${MPOS_DB_USER:=mpos}"
: "${MPOS_DB_PASS:?MPOS_DB_PASS not set}"

# Find a safe cutoff share_id: whichever is smaller of
#   1. the oldest share_id that's newer than KEEP_HOURS, and
#   2. the newest share_id that's already been accounted into a block
# ensures we never rotate shares that a future PPLNS pass still needs.
CUTOFF=$(mysql -u "$MPOS_DB_USER" -p"$MPOS_DB_PASS" -N -B mpos -e "
  SELECT LEAST(
    COALESCE((SELECT MIN(id) FROM shares WHERE time < NOW() - INTERVAL ${KEEP_HOURS} HOUR), 0),
    COALESCE((SELECT MAX(share_id) FROM blocks WHERE accounted = 1), 0)
  )
" 2>/dev/null)

if [ -z "$CUTOFF" ] || [ "$CUTOFF" -le 0 ]; then
  echo "[$(date -uIs)] shares-archive: nothing to rotate (cutoff=$CUTOFF)"
  exit 0
fi

mysql -u "$MPOS_DB_USER" -p"$MPOS_DB_PASS" mpos <<SQL
  -- Copy old rows into the archive table.
  INSERT INTO shares_archive
    (share_id, rem_host, username, our_result, upstream_result, reason, solution, difficulty, time)
  SELECT id, rem_host, username, our_result, upstream_result, reason, solution, difficulty, time
  FROM shares
  WHERE id < ${CUTOFF};

  -- Delete archived rows from the hot table.
  DELETE FROM shares WHERE id < ${CUTOFF};
SQL

echo "[$(date -uIs)] shares-archive: rotated rows with id < ${CUTOFF}"
