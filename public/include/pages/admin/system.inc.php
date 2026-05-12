<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

// Admin-only.
if (!$user->isAuthenticated() || !$user->isAdmin($_SESSION['USERDATA']['id'])) {
  header("HTTP/1.1 404 Page not found");
  die("404 Page not found");
}

// Read-only system status panel. No mutations here — the only knobs
// (settings.backups_enabled etc.) live on the standard admin Settings
// page so they go through the existing CSRF/POST guard. This page
// just observes.

/**
 * Run a shell command and return stdout (stderr swallowed).
 * Bounded output: trimmed to $maxBytes so a runaway helper can't
 * blow up the page. Returns '' on any failure.
 */
function _system_run($cmd, $maxBytes = 8192) {
  $h = @popen($cmd . ' 2>/dev/null', 'r');
  if (!$h) return '';
  $out = '';
  while (!feof($h) && strlen($out) < $maxBytes) {
    $out .= fread($h, 1024);
  }
  pclose($h);
  return trim($out);
}

/**
 * `systemctl is-active <unit>` → returns the literal state string
 * ("active", "inactive", "failed", "activating", or "" on error).
 */
function _system_unit_state($unit) {
  return _system_run('systemctl is-active ' . escapeshellarg($unit));
}

function _system_unit_active_since($unit) {
  $ts = _system_run('systemctl show ' . escapeshellarg($unit) . ' -p ActiveEnterTimestamp --value');
  if ($ts === '' || $ts === '0' || $ts === 'n/a') return '';
  return $ts;
}

// ---- Services panel -------------------------------------------------
$services = array(
  'eloipool'    => 'blakestream-mpos-eloipool',
  'cronjobs-py' => 'blakestream-mpos-cronjobs',
  'mergeminer'  => 'blakestream-mpos-mergeminer',
  'sse'         => 'blakestream-mpos-sse',
  'php-fpm'     => 'php8.3-fpm',
  'mariadb'     => 'mariadb',
  'memcached'   => 'memcached',
  'nginx'       => 'nginx',
  'backup-timer'=> 'blakestream-mpos-backup.timer',
);
$service_rows = array();
foreach ($services as $label => $unit) {
  $service_rows[] = array(
    'label'  => $label,
    'unit'   => $unit,
    'state'  => _system_unit_state($unit),
    'since'  => _system_unit_active_since($unit),
  );
}

// ---- Backups panel --------------------------------------------------
$backup_dir = '/var/backups/blakestream-mpos';
$latest_link = $backup_dir . '/latest.tar.gz';
$backup_status_file = '/var/log/blakestream-mpos/backup-status.ini';
$backup_status = is_readable($backup_status_file)
  ? (@parse_ini_file($backup_status_file) ?: array()) : array();
$last_backup_mtime = !empty($backup_status['last_mtime'])
  ? (int)$backup_status['last_mtime']
  : ((is_link($latest_link) || is_file($latest_link)) ? @filemtime($latest_link) : 0);
$last_backup_size = !empty($backup_status['last_size'])
  ? (int)$backup_status['last_size']
  : ((is_link($latest_link) || is_file($latest_link)) ? @filesize($latest_link) : 0);

// Disk usage for the backup dir + log dir + daemon datadir parent.
$disk_targets = array(
  'Backups'  => $backup_dir,
  'DB'       => '/var/lib/mysql',
  'Logs'     => '/var/log/blakestream-mpos',
  'Daemons'  => '/var/lib/blakestream-mpos',
);
$disk_rows = array();
foreach ($disk_targets as $label => $path) {
  if (!is_dir($path)) continue;
  $line = _system_run('df -BM --output=size,used,avail,pcent ' . escapeshellarg($path) . ' | tail -1');
  if (!$line) continue;
  $parts = preg_split('/\s+/', trim($line));
  if (count($parts) < 4) continue;
  $disk_rows[] = array(
    'label' => $label,
    'path'  => $path,
    'size'  => $parts[0],
    'used'  => $parts[1],
    'avail' => $parts[2],
    'pcent' => $parts[3],
  );
}

// Next scheduled backup run from `systemctl list-timers`.
$next_backup_run = _system_run("systemctl list-timers blakestream-mpos-backup.timer --no-pager | awk 'NR==2 {print \$1\" \"$2}'");

// Retention from .deploy.env (read-only).
$retention_days = '14';  // default
$envfile = '/opt/blakestream-mpos/.deploy.env';
if (is_readable($envfile)) {
  $env = @file_get_contents($envfile);
  if (preg_match('/BACKUP_RETENTION_DAYS=(\d+)/', $env ?: '', $m)) {
    $retention_days = $m[1];
  }
}

// Wallet backups inside latest tarball — show what's there.
$wallet_rows = array();
if (!empty($backup_status['wallets'])) {
  foreach (explode(',', $backup_status['wallets']) as $sym) {
    $sym = trim($sym);
    if ($sym !== '') $wallet_rows[] = $sym;
  }
} elseif ($last_backup_mtime > 0) {
  $listing = _system_run("tar -tzf " . escapeshellarg($latest_link) . " 2>/dev/null | grep '^./wallets/' | head -10");
  foreach (preg_split('/\r?\n/', $listing) as $line) {
    $line = trim($line);
    if ($line === '' || $line === './wallets/') continue;
    $sym = basename($line, '.dat');
    $wallet_rows[] = $sym;
  }
}

// ---- Daemon block heights -------------------------------------------
// Direct JSON-RPC via the existing $bitcoin* globals. The previous
// `docker exec` approach required www-data to have Docker socket
// access; the daemons' RPC ports are already reachable on localhost
// with the wallet credentials in $config['wallet*'].
$daemon_rows = array();
$daemons = array(
  'BLC'  => isset($bitcoin)     ? $bitcoin     : null,
  'PHO'  => isset($bitcoin_mm)  ? $bitcoin_mm  : null,
  'BBTC' => isset($bitcoin_mm1) ? $bitcoin_mm1 : null,
  'ELT'  => isset($bitcoin_mm3) ? $bitcoin_mm3 : null,
  'UMO'  => isset($bitcoin_mm4) ? $bitcoin_mm4 : null,
  'LIT'  => isset($bitcoin_mm5) ? $bitcoin_mm5 : null,
);
foreach ($daemons as $sym => $btc) {
  $blocks = ''; $headers = ''; $chain = '';
  if ($btc) {
    try {
      $info = $btc->getblockchaininfo();
      if (is_array($info)) {
        if (isset($info['blocks']))  $blocks  = (string)$info['blocks'];
        if (isset($info['headers'])) $headers = (string)$info['headers'];
        if (isset($info['chain']))   $chain   = (string)$info['chain'];
      }
    } catch (Exception $e) {
      // Leave the row blank — UI renders "UNREACHABLE".
    }
  }
  $daemon_rows[] = array(
    'sym'     => $sym,
    'chain'   => $chain ?: '?',
    'blocks'  => $blocks ?: '—',
    'headers' => $headers ?: '—',
    'synced'  => ($blocks !== '' && $headers !== '' && $blocks === $headers),
  );
}

// ---- Process RSS ---------------------------------------------------
$processes = array(
  'eloipool'   => "ps -C python -o pid=,rss=,cmd= | grep eloipool.py | head -1 | awk '{print \$1\"|\"\$2}'",
  'cronjobs-py'=> "ps -C python -o pid=,rss=,cmd= | grep cronjobs-py | head -1 | awk '{print \$1\"|\"\$2}'",
  'mariadb'    => "ps -C mariadbd -o pid=,rss= | head -1 | awk '{print \$1\"|\"\$2}'",
  'memcached'  => "ps -C memcached -o pid=,rss= | head -1 | awk '{print \$1\"|\"\$2}'",
);
$proc_rows = array();
foreach ($processes as $label => $cmd) {
  $line = _system_run($cmd);
  $pid = ''; $rss_kb = '';
  if ($line && strpos($line, '|') !== false) {
    list($pid, $rss_kb) = explode('|', $line, 2);
  }
  $proc_rows[] = array(
    'label'  => $label,
    'pid'    => trim($pid),
    'rss_mb' => $rss_kb !== '' ? round((int)$rss_kb / 1024, 1) : '',
  );
}

// ---- Outbox state distribution -------------------------------------
$outbox_rows = array();
if (isset($mysqli) && $stmt = $mysqli->prepare(
    "SELECT slot, status, COUNT(*) AS cnt, MAX(updated_at) AS latest "
    . "FROM transactions_outbox GROUP BY slot, status ORDER BY slot, status"
)) {
  if ($stmt->execute() && $res = $stmt->get_result()) {
    while ($row = $res->fetch_assoc()) {
      $outbox_rows[] = array(
        'slot'   => $row['slot'] === '' ? '(BLC)' : $row['slot'],
        'status' => $row['status'],
        'cnt'    => (int)$row['cnt'],
        'latest' => $row['latest'],
      );
    }
  }
  $stmt->close();
}

// ---- Pass to template ----------------------------------------------
$backups_enabled_value = trim((string)$setting->getValue('backups_enabled'));
$smarty->assign('SYS_SERVICES',  $service_rows);
$smarty->assign('SYS_BACKUP', array(
  'enabled'         => $backups_enabled_value === '0' ? 0 : 1,  // default 1
  'last_mtime'      => $last_backup_mtime,
  'last_size'       => $last_backup_size,
  'next_run'        => $next_backup_run,
  'retention_days'  => $retention_days,
  'wallets'         => $wallet_rows,
  'tarball_path'    => $latest_link,
));
$smarty->assign('SYS_DISK',     $disk_rows);
$smarty->assign('SYS_DAEMONS',  $daemon_rows);
$smarty->assign('SYS_PROCS',    $proc_rows);
$smarty->assign('SYS_OUTBOX',   $outbox_rows);

$smarty->assign('CONTENT', 'default.tpl');
?>
