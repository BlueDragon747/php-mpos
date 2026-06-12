#!/usr/bin/env bash
set -u

# MPOS pool metrics snapshot helper.
#
# Purpose:
#   Capture the system, disk I/O, and MariaDB read/write state before,
#   during, or after a pool code/test change. Run it at every checkpoint
#   so DB/I/O trends are compared with evidence instead of memory.
#
# Usage on a pool VPS:
#   chmod +x tools/mpos-metrics-snapshot.sh
#   MYSQL_CMD="mysql -uroot -pPASSWORD" DB_NAME=mpos \
#     tools/mpos-metrics-snapshot.sh ./mpos-metrics-before.log
#
# If MariaDB auth is available through ~/.my.cnf or unix socket root access:
#   tools/mpos-metrics-snapshot.sh ./mpos-metrics-before.log
#
# Run multiple snapshots around a test:
#   tools/mpos-metrics-snapshot.sh ./mpos-before.log
#   # run stress/mining test
#   tools/mpos-metrics-snapshot.sh ./mpos-after.log
#
# This file lives under tools/ so operators can capture comparable before/after
# resource snapshots during deploy, update, and stress-test work.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [ -r "${SCRIPT_DIR}/lib/tool-banner.sh" ]; then
  # shellcheck disable=SC1091
  . "${SCRIPT_DIR}/lib/tool-banner.sh"
  print_blakestream_banner
fi

OUT="${1:-/tmp/mpos-metrics-$(date -u +%Y%m%dT%H%M%SZ).log}"
DB_NAME="${DB_NAME:-mpos}"
MYSQL_CMD="${MYSQL_CMD:-mysql}"

section() {
  printf '\n===== %s =====\n' "$1"
}

run() {
  printf '$ %s\n' "$*"
  "$@" 2>&1 || true
}

mysql_query() {
  local title="$1"
  local sql="$2"
  section "$title"
  bash -lc "${MYSQL_CMD} --database='${DB_NAME}' --table" <<<"$sql" 2>&1 || true
}

{
  section "snapshot"
  date -u '+utc=%Y-%m-%dT%H:%M:%SZ'
  printf 'host=%s\n' "$(hostname -f 2>/dev/null || hostname)"
  printf 'db=%s\n' "$DB_NAME"

  section "system"
  run uname -a
  run uptime
  run free -h
  run df -h /

  section "vmstat"
  if command -v vmstat >/dev/null 2>&1; then
    run vmstat 1 5
  else
    echo "vmstat not installed"
  fi

  section "iostat"
  if command -v iostat >/dev/null 2>&1; then
    run iostat -dx 1 5
  else
    echo "iostat not installed; install sysstat for disk await/%util samples"
  fi

  section "top processes"
  run ps -eo pid,comm,pcpu,pmem,rss,vsz,args --sort=-pcpu

  mysql_query "mariadb version and row counts" "
SELECT VERSION() AS version;
SELECT 'shares' AS table_name, COUNT(*) AS rows_count FROM shares
UNION ALL
SELECT 'shares_archive', COUNT(*) FROM shares_archive
UNION ALL
SELECT 'share_stats_recent', COUNT(*) FROM share_stats_recent
UNION ALL
SELECT 'pool_worker', COUNT(*) FROM pool_worker;
"

  mysql_query "mariadb read write counters" "
SHOW GLOBAL STATUS WHERE Variable_name IN (
  'Innodb_data_reads',
  'Innodb_data_writes',
  'Innodb_buffer_pool_reads',
  'Innodb_buffer_pool_read_requests',
  'Com_select',
  'Com_insert',
  'Com_update',
  'Com_delete',
  'Created_tmp_disk_tables',
  'Handler_read_rnd_next',
  'Innodb_row_lock_waits',
  'Innodb_row_lock_time'
);
"

  mysql_query "mariadb processlist" "SHOW FULL PROCESSLIST;"

  mysql_query "innodb status" "SHOW ENGINE INNODB STATUS\\G"
} >"$OUT"

printf 'wrote %s\n' "$OUT"
