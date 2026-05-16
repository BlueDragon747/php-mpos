<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

// Admin-only.
if (!$user->isAuthenticated() || !$user->isAdmin($_SESSION['USERDATA']['id'])) {
  header("HTTP/1.1 404 Page not found");
  die("404 Page not found");
}

// CSRF + method enforcement for the inline backup settings form. No-op
// for plain GET, which is the partial-poll + page render path.
require_once dirname(__FILE__) . '/../../admin_csrf.inc.php';
require_once __DIR__ . '/_daemon_rule_status.inc.php';
_require_admin_csrf($csrftoken);

// Single mutation supported here: toggle backups_enabled. Reuses the
// same settings table the admin Settings page writes to, so flipping
// it here = flipping it there.
if (@$_POST['do'] === 'update_backup_settings') {
  $msgs = array();

  // Enabled toggle (unchecked = absent → write 0).
  $new_val = !empty($_POST['backups_enabled']) ? '1' : '0';
  $setting->setValue('backups_enabled', $new_val);
  $msgs[] = $new_val === '1' ? 'Backups enabled' : 'Backups disabled';

  // Schedule (HH:MM from <input type="time">) — clamp into range,
  // default to 03:30 on garbage input.
  if (isset($_POST['backup_schedule_time']) &&
      preg_match('/^(\d{1,2}):(\d{1,2})$/', (string)$_POST['backup_schedule_time'], $m)) {
    $hour = max(0, min(23, (int)$m[1]));
    $min  = max(0, min(59, (int)$m[2]));
    $setting->setValue('backup_schedule_hour',   (string)$hour);
    $setting->setValue('backup_schedule_minute', (string)$min);
    $msgs[] = sprintf('schedule %02d:%02d UTC', $hour, $min);
  }

  // Retention days — clamp 1..365.
  if (isset($_POST['backup_retention_days']) && is_numeric($_POST['backup_retention_days'])) {
    $days = max(1, min(365, (int)$_POST['backup_retention_days']));
    $setting->setValue('backup_retention_days', (string)$days);
    $msgs[] = "retention {$days}d";
  }

  $log->log("warn", @$_SESSION['USERDATA']['username']
            . ' updated backup settings via System Status: ' . implode(', ', $msgs));
  $_SESSION['POPUP'][] = array(
    'CONTENT' => 'Backup settings saved (' . implode(', ', $msgs) . ').',
    'TYPE'    => 'success',
  );
  header('Location: ?page=admin&action=system');
  exit;
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

function _system_run_all($cmd, $maxBytes = 8192) {
  $h = @popen($cmd . ' 2>&1', 'r');
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

function _system_first_existing_dir($paths) {
  foreach ($paths as $path) {
    if (is_dir($path)) return $path;
  }
  return '';
}

function _system_mb($kb) {
  return number_format((int)round(((int)$kb) / 1024)) . ' MB';
}

function _system_pct($used, $total) {
  if ((int)$total <= 0) return '—';
  return number_format(100.0 * ((int)$used / (int)$total), 1) . ' %';
}

function _system_size_from_mb($mb) {
  $mb = (int)$mb;
  if ($mb < 0) return '—';
  if ($mb >= 1024) return number_format($mb / 1024, 1) . ' GB';
  return number_format($mb) . ' MB';
}

function _system_disk_stats_helper_sizes() {
  $helper = '/usr/local/sbin/blakestream-mpos-disk-stats';
  if (!is_file($helper) || !is_executable($helper)) return array();

  $uid = function_exists('posix_geteuid') ? (string)posix_geteuid() : (string)getmyuid();
  $cache_file = sys_get_temp_dir() . '/blakestream-mpos-system-disk-v2-' . $uid . '.json';
  if (is_readable($cache_file) && @filemtime($cache_file) >= time() - 60) {
    $cached = json_decode((string)@file_get_contents($cache_file), true);
    if (is_array($cached)) return $cached;
  }

  $out = _system_run_all('sudo -n ' . escapeshellarg($helper), 8192);
  if ($out === '') return array();
  if (stripos($out, 'password') !== false || stripos($out, 'not allowed') !== false) {
    return array();
  }

  $sizes = array();
  foreach (preg_split('/\r?\n/', $out) as $line) {
    $line = trim($line);
    if ($line === '') continue;
    $parts = explode("\t", $line);
    if (count($parts) < 2 || $parts[0] === '' || !is_numeric($parts[1])) continue;
    $sizes[$parts[0]] = (int)$parts[1];
  }
  if (!empty($sizes)) @file_put_contents($cache_file, json_encode($sizes), LOCK_EX);
  return $sizes;
}

function _system_du_size_info($path, $helper_sizes = array()) {
  if (!is_dir($path)) return array('label' => '—', 'mb' => null);
  if (isset($helper_sizes[$path])) {
    $mb = (int)$helper_sizes[$path];
    return array('label' => _system_size_from_mb($mb), 'mb' => $mb);
  }
  if (!is_readable($path) || !is_executable($path)) {
    return array('label' => 'restricted', 'mb' => null);
  }
  $out = _system_run_all('du -sm -- ' . escapeshellarg($path), 4096);
  if ($out === '') return array('label' => '—', 'mb' => null);
  if (stripos($out, 'Permission denied') !== false) {
    return array('label' => 'restricted', 'mb' => null);
  }
  if (preg_match('/^\s*(\d+)/', $out, $m)) {
    $mb = (int)$m[1];
    return array('label' => _system_size_from_mb($mb), 'mb' => $mb);
  }
  return array('label' => '—', 'mb' => null);
}

function _system_dir_pct_from_mb($dir_mb, $fs_mb) {
  if ($dir_mb === null || (int)$fs_mb <= 0) return '—';
  $pct = 100.0 * ((int)$dir_mb / (int)$fs_mb);
  if ($pct > 0 && $pct < 0.1) return '<0.1 %';
  return number_format($pct, 1) . ' %';
}

function _system_age_compact($ts) {
  if ($ts === null || $ts === '') return '—';
  $when = strtotime((string)$ts);
  if (!$when) return '—';
  $diff = time() - $when;
  if ($diff < 60) return 'now';
  if ($diff < 3600) return floor($diff / 60) . 'm';
  if ($diff < 86400) return floor($diff / 3600) . 'h';
  if ($diff < 604800) return floor($diff / 86400) . 'd';
  if ($diff < 31536000) return floor($diff / 604800) . 'w';
  return floor($diff / 31536000) . 'y';
}

function _system_amount_compact($amount) {
  if ($amount === null || $amount === '') return '—';
  $s = number_format((float)$amount, 8, '.', ',');
  $s = rtrim(rtrim($s, '0'), '.');
  return $s === '-0' ? '0' : $s;
}

function _system_txid_short($txid) {
  $txid = trim((string)$txid);
  if ($txid === '') return '—';
  if (strlen($txid) <= 18) return $txid;
  return substr($txid, 0, 8) . '...' . substr($txid, -8);
}

function _system_tx_explorer_url($coin, $txid, $setting) {
  $txid = trim((string)$txid);
  $base = trim((string)$setting);
  if ($txid === '' || $base === '') return '';
  if (strpos($base, '{coin}') !== false) {
    $base = str_replace('{coin}', strtolower((string)$coin), $base);
  }
  return $base . rawurlencode($txid);
}

function _system_tx_confirmations($btc, $txid) {
  $txid = trim((string)$txid);
  if (!$btc || $txid === '') return 0;

  $old_timeout = ini_get('default_socket_timeout');
  ini_set('default_socket_timeout', 2);
  try {
    $tx = $btc->gettransaction($txid);
    ini_set('default_socket_timeout', $old_timeout);
    if (is_array($tx) && isset($tx['confirmations']) && is_numeric($tx['confirmations'])) {
      return max(0, (int)$tx['confirmations']);
    }
  } catch (Exception $e) {
    ini_set('default_socket_timeout', $old_timeout);
    return 0;
  }
  ini_set('default_socket_timeout', $old_timeout);
  return 0;
}

function _system_user_summary($count, $users) {
  $count = (int)$count;
  $users = trim((string)$users);
  if ($count <= 0) return '—';
  if ($count === 1 && $users !== '') return $users;
  return $count . ' users';
}

function _system_bytes($n) {
  if (!is_numeric($n) || $n < 0) return '—';
  $b = (float)$n; $units = array('B','KB','MB','GB','TB','PB'); $i = 0;
  while ($b >= 1024 && $i < count($units) - 1) { $b /= 1024; $i++; }
  $fmt = $b >= 100 ? '%.0f %s' : ($b >= 10 ? '%.1f %s' : '%.2f %s');
  return sprintf($fmt, $b, $units[$i]);
}

function _system_boot_time_str() {
  $stat = @file_get_contents('/proc/stat');
  if ($stat && preg_match('/^btime\s+(\d+)/m', $stat, $m)) {
    return gmdate('Y-m-d H:i \U\T\C', (int)$m[1]);
  }
  return '';
}

function _system_net_primary_iface() {
  $iface = trim(_system_run("ip -o -4 route show to default 2>/dev/null | awk '{print \$5}' | head -1"));
  if ($iface !== '') return $iface;
  foreach (array('eth0','ens3','enp0s3','eno1') as $candidate) {
    if (@file_exists("/sys/class/net/$candidate")) return $candidate;
  }
  return 'lo';
}

function _system_net_read($iface) {
  $lines = @file('/proc/net/dev', FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
  if (!$lines) return null;
  foreach ($lines as $line) {
    if (preg_match('/^\s*' . preg_quote($iface, '/') . ':\s*(\d+)\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+(\d+)/', $line, $m)) {
      return array('rx' => (int)$m[1], 'tx' => (int)$m[2], 'ts' => microtime(true));
    }
  }
  return null;
}

function _system_net_stratum_port() {
  $cfg = '/opt/blakestream-mpos/eloipool/config.py';
  if (is_readable($cfg)) {
    $body = @file_get_contents($cfg);
    if ($body && preg_match('/ServerTCP\s*=\s*\(\s*[\'"][^\'"]*[\'"]\s*,\s*(\d{2,5})/', $body, $m)) {
      return (int)$m[1];
    }
  }
  $env = '/opt/blakestream-mpos/.deploy.env';
  if (is_readable($env)) {
    $body = @file_get_contents($env);
    if ($body && preg_match('/MPOS_STRATUM_PORT=(\d+)/', $body, $m)) {
      return (int)$m[1];
    }
  }
  return 3334;
}

function _system_net_miners_count($port) {
  $port = (int)$port;
  $out = trim(_system_run("ss -tnH state established sport = :$port 2>/dev/null | wc -l"));
  return is_numeric($out) ? (int)$out : null;
}

function _system_cpu_read_stat() {
  $stat = @file_get_contents('/proc/stat');
  if (!$stat) return null;
  $first = strtok($stat, "\n");
  $parts = preg_split('/\s+/', trim($first));
  if (count($parts) < 5 || $parts[0] !== 'cpu') return null;
  $vals = array_map('intval', array_slice($parts, 1, 8));
  return array(
    'idle'  => $vals[3] + $vals[4],
    'total' => array_sum($vals),
    'ts'    => microtime(true),
  );
}

function _system_cpu_busy_pct_from_samples($old, $new) {
  if (!$old || !$new) return '';
  $dt = (int)$new['total'] - (int)$old['total'];
  $di = (int)$new['idle']  - (int)$old['idle'];
  if ($dt <= 0) return '';
  return number_format(100.0 * (1.0 - ($di / $dt)), 1);
}

function _system_cpu_busy_pct() {
  $uid = function_exists('posix_geteuid') ? (string)posix_geteuid() : (string)getmyuid();
  $state_file = sys_get_temp_dir() . '/blakestream-mpos-system-cpu-' . $uid . '.json';
  $now = _system_cpu_read_stat();
  if (!$now) return '';

  $pct = '';
  if (is_readable($state_file)) {
    $prev = json_decode((string)@file_get_contents($state_file), true);
    if (is_array($prev) && isset($prev['idle'], $prev['total'], $prev['ts'])) {
      $age = $now['ts'] - (float)$prev['ts'];
      if ($age >= 0.5 && $age < 300) {
        $pct = _system_cpu_busy_pct_from_samples($prev, $now);
      }
    }
  }

  // Store this sample for the next admin poll. That makes the normal
  // value represent the whole polling interval instead of a tiny instant,
  // which can misleadingly show 0.0% while daemon containers are doing
  // low but steady work.
  @file_put_contents($state_file, json_encode($now), LOCK_EX);
  if ($pct !== '') return $pct;

  // First request after deploy/reboot: take a 1s warm-up sample. This is
  // slower than the old 200ms probe, but avoids the common false-zero case.
  usleep(1000000);
  $later = _system_cpu_read_stat();
  if ($later) @file_put_contents($state_file, json_encode($later), LOCK_EX);
  return _system_cpu_busy_pct_from_samples($now, $later);
}

// ---- Users / Invitations / Logins (migrated from admin Dashboard) --
$users_info = array(
  'total'  => (int)$user->getCount(),
  'active' => (int)$statistics->getCountAllActiveUsers(),
  'locked' => (int)$user->getCountFiltered('is_locked', 1),
  'admins' => (int)$user->getCountFiltered('is_admin', 1),
  'nofees' => (int)$user->getCountFiltered('no_fees', 1),
);
$logins_info = array(
  '24hours' => (int)$user->getCountFiltered('last_login', time() - 86400,           'i', '>='),
  '7days'   => (int)$user->getCountFiltered('last_login', time() - 86400 * 7,       'i', '>='),
  '1month'  => (int)$user->getCountFiltered('last_login', time() - 86400 * 7 * 4,   'i', '>='),
  '6month'  => (int)$user->getCountFiltered('last_login', time() - 86400 * 7 * 4 * 6,'i', '>='),
  '1year'   => (int)$user->getCountFiltered('last_login', time() - 86400 * 365,     'i', '>='),
);
$invitations_info = null;
$invitations_enabled = !$setting->getValue('disable_invitations');
if ($invitations_enabled && isset($invitation)) {
  $invitations_info = array(
    'total'       => (int)$invitation->getCount(),
    'activated'   => (int)$invitation->getCountFiltered('is_activated', 1),
    'outstanding' => (int)$invitation->getCountFiltered('is_activated', 0),
  );
}

// ---- MPOS version (migrated from admin Dashboard, shown inside the
//      Services panel header so it lives next to the runtime list) ---
$mpos_versions = array(
  array('label' => 'MPOS',     'current' => MPOS_VERSION,
        'installed' => MPOS_VERSION,
        'match' => true),
  array('label' => 'Config',   'current' => CONFIG_VERSION,
        'installed' => (string)$config['version'],
        'match' => CONFIG_VERSION === (string)$config['version']),
  array('label' => 'Database', 'current' => DB_VERSION,
        'installed' => (string)$setting->getValue('DB_VERSION'),
        'match' => DB_VERSION === (string)$setting->getValue('DB_VERSION')),
);

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
// Production mainnet currently keeps daemon datadirs under /root/.<coin>,
// which www-data cannot traverse. Prefer an explicit daemon parent when it
// exists, otherwise use the accessible backing filesystem so the operator
// still sees the capacity pressure for the daemon storage.
$daemon_disk_path = _system_first_existing_dir(array(
  '/var/lib/blakestream-mpos',
  '/root/.blakecoin',
  '/root/.photon',
  '/root/.blakebitcoin',
  '/root/.electron',
  '/root/.universalmolecule',
  '/root/.lithium',
  '/var/lib/docker',
  '/',
));
$disk_targets = array(
  'Backups'  => $backup_dir,
  'DB'       => '/var/lib/mysql',
  'Logs'     => '/var/log/blakestream-mpos',
);
if ($daemon_disk_path !== '') $disk_targets['Daemons'] = $daemon_disk_path;
$disk_rows = array();
$disk_helper_sizes = _system_disk_stats_helper_sizes();
$disk_available_str = '—';
foreach ($disk_targets as $label => $path) {
  if (!is_dir($path)) continue;
  $line = _system_run('df -BM --output=source,size,used,avail,pcent ' . escapeshellarg($path) . ' | tail -1');
  if (!$line) continue;
  $parts = preg_split('/\s+/', trim($line));
  if (count($parts) < 5) continue;
  $fs_size_mb = (int)$parts[1];
  if ($disk_available_str === '—') $disk_available_str = _system_size_from_mb((int)$parts[3]);
  $dir_size = _system_du_size_info($path, $disk_helper_sizes);
  $disk_rows[] = array(
    'label'   => $label,
    'path'    => $path,
    'fs'      => $parts[0],
    'size'    => $parts[1],
    'fs_used' => $parts[2],
    'avail'   => $parts[3],
    'pcent'   => $parts[4],
    'dirsize' => $dir_size['label'],
    'dirmb'   => $dir_size['mb'],
    'dirpct'  => _system_dir_pct_from_mb($dir_size['mb'], $fs_size_mb),
  );
}

// Schedule + retention come from the settings table (admin-editable).
// Compute next-run from those values rather than parsing
// `systemctl list-timers`, because the systemd timer now fires every
// 30 min and the script decides whether to actually run — so the
// timer's "next" is meaningless, the *configured* time is what the
// operator wants to see.
$schedule_hour   = max(0, min(23, (int)($setting->getValue('backup_schedule_hour')   ?: 3)));
$schedule_minute = max(0, min(59, (int)($setting->getValue('backup_schedule_minute') ?: 30)));
$retention_days  = max(1, min(365, (int)($setting->getValue('backup_retention_days') ?: 14)));
$schedule_time_str = sprintf('%02d:%02d', $schedule_hour, $schedule_minute);

$_now = time();
$_target_today = gmmktime($schedule_hour, $schedule_minute, 0,
  (int)gmdate('n', $_now), (int)gmdate('j', $_now), (int)gmdate('Y', $_now));
$_next_is_today = $_target_today > $_now;
$next_epoch = $_next_is_today ? $_target_today : ($_target_today + 86400);
$next_backup_run = gmdate('Y-m-d H:i', $next_epoch) . ' UTC';
$next_day_label = $_next_is_today ? 'today' : 'tomorrow';

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
  $blocks = ''; $headers = ''; $chain = ''; $version = '';
  $info = array();
  $netinfo = array();
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
    try {
      $netinfo = $btc->getnetworkinfo();
      if (is_array($netinfo) && isset($netinfo['subversion'])) {
        // Strip the leading/trailing slashes from "/Satoshi:0.15.21/".
        $version = trim((string)$netinfo['subversion'], "/ \t");
      }
    } catch (Exception $e) {
      // Older daemons may not expose getnetworkinfo — leave blank.
    }
  }
  $rule_status = bsx_daemon_rule_status($btc, array(), $netinfo, $info);
  $daemon_rows[] = array(
    'sym'     => $sym,
    'chain'   => $chain ?: '?',
    'version' => $version ?: '—',
    'blocks'  => $blocks ?: '—',
    'headers' => $headers ?: '—',
    'synced'  => ($blocks !== '' && $headers !== '' && $blocks === $headers),
    'rules'   => $rule_status,
  );
}

// ---- Wallets -------------------------------------------------------
// Per-coin spendable balance + DB-tracked locked + maturing unconfirmed.
// Distinct from Coin Daemons (chain state) and Payout Outbox (queue) —
// answers "do I have enough cash on hand to drain my payment queue?".
empty($config['network_confirmations']) ? $wallet_confs = 120 : $wallet_confs = (int)$config['network_confirmations'];
$wallet_slot_globals = array(
  'BLC'  => array(isset($bitcoin)     ? $bitcoin     : null, isset($transaction)     ? $transaction     : null, isset($block)     ? $block     : null),
  'PHO'  => array(isset($bitcoin_mm)  ? $bitcoin_mm  : null, isset($transaction_mm)  ? $transaction_mm  : null, isset($block_mm)  ? $block_mm  : null),
  'BBTC' => array(isset($bitcoin_mm1) ? $bitcoin_mm1 : null, isset($transaction_mm1) ? $transaction_mm1 : null, isset($block_mm1) ? $block_mm1 : null),
  'ELT'  => array(isset($bitcoin_mm3) ? $bitcoin_mm3 : null, isset($transaction_mm3) ? $transaction_mm3 : null, isset($block_mm3) ? $block_mm3 : null),
  'UMO'  => array(isset($bitcoin_mm4) ? $bitcoin_mm4 : null, isset($transaction_mm4) ? $transaction_mm4 : null, isset($block_mm4) ? $block_mm4 : null),
  'LIT'  => array(isset($bitcoin_mm5) ? $bitcoin_mm5 : null, isset($transaction_mm5) ? $transaction_mm5 : null, isset($block_mm5) ? $block_mm5 : null),
);
$wallet_panel_rows = array();
foreach ($wallet_slot_globals as $sym => $tuple) {
  list($btc, $txn, $blk) = $tuple;
  $balance = null; $locked = null; $unconfirmed = null;
  if ($btc) {
    try { if ($btc->can_connect() === true) { $balance = (float)$btc->getbalance(); } } catch (Exception $e) {}
  }
  if ($txn) {
    try { $lb = $txn->getLockedBalance(); if (is_numeric($lb)) $locked = (float)$lb; } catch (Exception $e) {}
  }
  if ($blk) {
    try {
      $rows = $blk->getAllUnconfirmed($wallet_confs);
      $sum = 0;
      if (is_array($rows)) foreach ($rows as $r) $sum += (float)$r['amount'];
      $unconfirmed = $sum;
    } catch (Exception $e) {}
  }
  $wallet_panel_rows[] = array(
    'sym'         => $sym,
    'balance'     => $balance     === null ? '—' : number_format($balance,     8),
    'locked'      => $locked      === null ? '—' : number_format($locked,      8),
    'unconfirmed' => $unconfirmed === null ? '—' : number_format($unconfirmed, 8),
    'reachable'   => $balance !== null,
  );
}

// ---- Network -------------------------------------------------------
$network_iface = _system_net_primary_iface();
$network_now   = _system_net_read($network_iface);
$network_rx_rate = '—'; $network_tx_rate = '—';
$network_rx_total = '—'; $network_tx_total = '—';
if ($network_now) {
  $uid = function_exists('posix_geteuid') ? (string)posix_geteuid() : (string)getmyuid();
  $state_file = sys_get_temp_dir() . '/blakestream-mpos-system-net-' . $network_iface . '-' . $uid . '.json';
  if (is_readable($state_file)) {
    $prev = json_decode((string)@file_get_contents($state_file), true);
    if (is_array($prev) && isset($prev['rx'], $prev['tx'], $prev['ts'])) {
      $age = $network_now['ts'] - (float)$prev['ts'];
      if ($age >= 0.5 && $age < 300) {
        $network_rx_rate = _system_bytes(($network_now['rx'] - (int)$prev['rx']) / $age) . '/s';
        $network_tx_rate = _system_bytes(($network_now['tx'] - (int)$prev['tx']) / $age) . '/s';
      }
    }
  }
  @file_put_contents($state_file, json_encode($network_now), LOCK_EX);
  $network_rx_total = _system_bytes($network_now['rx']);
  $network_tx_total = _system_bytes($network_now['tx']);
}
$network_boot_str = _system_boot_time_str();
$network_totals_tip = $network_boot_str !== '' ? 'Since boot — ' . $network_boot_str : '';
$network_rows = array(
  array('label' => 'RX rate',  'value' => $network_rx_rate),
  array('label' => 'TX rate',  'value' => $network_tx_rate),
  array('label' => 'RX total', 'value' => $network_rx_total, 'tooltip' => $network_totals_tip),
  array('label' => 'TX total', 'value' => $network_tx_total, 'tooltip' => $network_totals_tip),
);
// "Miners" = active workers (devices that submitted a share in the
// last 120 s). TCP-connection counts on the stratum port over-count:
// each subscription, eloipool's internal sockets, and stale-but-not-
// closed connections all show up there.
$network_miners_count = isset($worker) && method_exists($worker, 'getCountAllActiveWorkers')
  ? (int)$worker->getCountAllActiveWorkers()
  : null;
$network_miners_str = $network_miners_count === null ? '—' : (string)$network_miners_count;

// ---- CPU -----------------------------------------------------------
$cpu_load1 = $cpu_load5 = $cpu_load15 = '';
$loadavg = @file_get_contents('/proc/loadavg');
if ($loadavg && preg_match('/^(\S+) (\S+) (\S+)/', $loadavg, $m)) {
  $cpu_load1  = $m[1];
  $cpu_load5  = $m[2];
  $cpu_load15 = $m[3];
}
$cpu_ncpu = (int)_system_run('nproc');

$cpu_pct = _system_cpu_busy_pct();

$cpu_rows = array(
  array('label' => 'Utilization', 'value' => $cpu_pct !== '' ? $cpu_pct . ' %' : '—'),
  array('label' => 'Load 1m',  'value' => $cpu_load1  !== '' ? $cpu_load1  : '—'),
  array('label' => 'Load 5m',  'value' => $cpu_load5  !== '' ? $cpu_load5  : '—'),
  array('label' => 'Load 15m', 'value' => $cpu_load15 !== '' ? $cpu_load15 : '—'),
  array('label' => 'Cores',    'value' => $cpu_ncpu > 0 ? (string)$cpu_ncpu : '—'),
);

// ---- System memory -------------------------------------------------
$meminfo = array();
foreach (@file('/proc/meminfo', FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: array() as $line) {
  if (preg_match('/^([A-Za-z_()]+):\s+(\d+)\s+kB$/', $line, $m)) {
    $meminfo[$m[1]] = (int)$m[2];
  }
}
$mem_total = isset($meminfo['MemTotal']) ? $meminfo['MemTotal'] : 0;
$mem_avail = isset($meminfo['MemAvailable']) ? $meminfo['MemAvailable'] : 0;
$mem_used = max(0, $mem_total - $mem_avail);
$swap_total = isset($meminfo['SwapTotal']) ? $meminfo['SwapTotal'] : 0;
$swap_free = isset($meminfo['SwapFree']) ? $meminfo['SwapFree'] : 0;
$swap_used = max(0, $swap_total - $swap_free);
$memory_rows = array(
  array('label' => 'RAM used',  'value' => $mem_total > 0 ? _system_mb($mem_used) . ' / ' . _system_mb($mem_total) . ' (' . _system_pct($mem_used, $mem_total) . ')' : '—'),
);
// Swap is its own card, stacked under CPU in the resources row (the
// operator looks at swap pressure separately from RAM pressure, and
// keeping them in distinct cards makes both states easier to scan).
// When the kernel reports no swap (SwapTotal=0) the card renders a
// muted "No swap configured" message in place of the table so the
// row stays balanced without dumping confusing zeros.
$swap_configured = $swap_total > 0;
$swap_rows = $swap_configured
  ? array(
      array(
        'label' => 'Used',
        'value' => _system_mb($swap_used) . ' / ' . _system_mb($swap_total)
                   . ' (' . _system_pct($swap_used, $swap_total) . ')',
      ),
    )
  : array();
$swap_available_str = $swap_configured ? _system_mb($swap_free) : '—';
// Surfaced separately in the Memory card header rather than in the
// per-row table — operators glance at it more than the absolute used,
// so it belongs as a top-right stat.
$memory_available_str = $mem_avail > 0 ? _system_mb($mem_avail) : '—';

// ---- Process RSS ---------------------------------------------------
$processes = array(
  'eloipool'   => "ps -C python -o pid=,rss=,cmd= | grep eloipool.py | head -1 | awk '{print \$1\"|\"\$2}'",
  // cronjobs-py renames its kernel comm to 'cronjobs-py' (setproctitle),
  // so we can't grep through `ps -C python`. The scheduler is bound to
  // 'serve'; the SSE worker uses 'sse' — pick the scheduler.
  'cronjobs-py'=> "pgrep -af 'cronjobs-py.*serve' | head -1 | awk '{cmd=\"ps -o rss= -p \"\$1; cmd | getline rss; print \$1\"|\"rss}'",
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
// Build a live slot→ticker map from $config so the outbox table shows
// 'BLC', 'PHO', 'BBTC', etc. instead of the internal 'mm', 'mm1', …
// suffixes. Rebuilt every request, so renaming a ticker in
// global.inc.php is reflected immediately. Unconfigured slots fall
// back to the raw suffix.
$slot_to_ticker = array('' => $config['currency']);
foreach (array('mm','mm1','mm2','mm3','mm4','mm5','mm6') as $_s) {
  $_tk = isset($config['currency_' . $_s]) ? $config['currency_' . $_s] : '';
  if ($_tk !== '' && stripos($_tk, 'unused') === false) $slot_to_ticker[$_s] = $_tk;
}
$slot_to_daemon = array(
  ''    => isset($bitcoin)     ? $bitcoin     : null,
  'mm'  => isset($bitcoin_mm)  ? $bitcoin_mm  : null,
  'mm1' => isset($bitcoin_mm1) ? $bitcoin_mm1 : null,
  'mm3' => isset($bitcoin_mm3) ? $bitcoin_mm3 : null,
  'mm4' => isset($bitcoin_mm4) ? $bitcoin_mm4 : null,
  'mm5' => isset($bitcoin_mm5) ? $bitcoin_mm5 : null,
);
$outbox_rows = array();
$outbox_open_count = 0;
$accounts_table = (isset($user) && method_exists($user, 'getTableName'))
  ? (string)$user->getTableName()
  : 'accounts';
if (!preg_match('/^[A-Za-z0-9_]+$/', $accounts_table)) $accounts_table = 'accounts';
$tx_explorer_url = !empty($setting->getValue('website_transactionexplorer_disabled'))
  ? ''
  : (string)$setting->getValue('website_transactionexplorer_url');
$outbox_counts = array(
  'pending'    => 0,
  'broadcast'  => 0,
  'reconciled' => 0,
  'other'      => 0,
);
if (isset($mysqli) && $stmt = $mysqli->prepare(
    "SELECT o.slot, o.status, COUNT(*) AS cnt, SUM(o.amount) AS total_amount, "
    . "SUBSTRING_INDEX(GROUP_CONCAT(o.txid ORDER BY o.updated_at DESC SEPARATOR ','), ',', 1) AS latest_txid, "
    . "COUNT(DISTINCT o.account_id) AS user_count, "
    . "GROUP_CONCAT(DISTINCT a.username ORDER BY a.username SEPARATOR ', ') AS users, "
    . "MIN(o.updated_at) AS oldest, MAX(o.updated_at) AS latest "
    . "FROM transactions_outbox AS o "
    . "LEFT JOIN " . $accounts_table . " AS a ON a.id = o.account_id "
    . "GROUP BY o.slot, o.status "
    . "ORDER BY FIELD(o.status, 'pending', 'broadcast', 'indeterminate', 'reconciled', 'abandoned'), o.slot, o.status"
)) {
  if ($stmt->execute() && $res = $stmt->get_result()) {
    while ($row = $res->fetch_assoc()) {
      $status = (string)$row['status'];
      $cnt = (int)$row['cnt'];
      $group = 'other';
      if ($status === 'pending' || $status === 'indeterminate') {
        $group = 'pending';
      } elseif ($status === 'broadcast') {
        $group = 'broadcast';
      } elseif ($status === 'reconciled') {
        $group = 'reconciled';
      }
      $ticker = isset($slot_to_ticker[$row['slot']])
        ? $slot_to_ticker[$row['slot']]
        : $row['slot'];
      $txid = (string)$row['latest_txid'];
      $tx_confirmations = $status === 'broadcast'
        ? _system_tx_confirmations(
            isset($slot_to_daemon[$row['slot']]) ? $slot_to_daemon[$row['slot']] : null,
            $txid
          )
        : 0;
      $outbox_counts[$group] += $cnt;
      if (in_array($row['status'], array('pending', 'broadcast', 'indeterminate'), true)) {
        $outbox_open_count += $cnt;
      }
      $outbox_rows[] = array(
        'slot'   => $ticker,
        'status' => $status,
        'group'  => $group,
        'cnt'    => $cnt,
        'amount' => _system_amount_compact($row['total_amount']),
        'txid'   => $txid,
        'txshort'=> _system_txid_short($txid),
        'txconfirmations' => $tx_confirmations,
        'txurl'  => $tx_confirmations > 0
                    ? _system_tx_explorer_url($ticker, $txid, $tx_explorer_url)
                    : '',
        'user'   => _system_user_summary($row['user_count'], $row['users']),
        'oldest' => $row['oldest'],
        'latest' => $row['latest'],
        'age'    => _system_age_compact($row['latest']),
      );
    }
  }
  $stmt->close();
}

// Manual payout requests spend a short time in the legacy payouts_<slot>
// tables before the payout worker converts them into transactions_outbox.
// Include those completed=0 rows in Pending so a fresh Cash Out click is
// visible immediately instead of only after the worker broadcasts it.
$manual_payout_tables = array(
  ''    => array('payouts',     'transactions',     'blocks'),
  'mm'  => array('payouts_mm',  'transactions_mm',  'blocks_mm'),
  'mm1' => array('payouts_mm1', 'transactions_mm1', 'blocks_mm1'),
  'mm3' => array('payouts_mm3', 'transactions_mm3', 'blocks_mm3'),
  'mm4' => array('payouts_mm4', 'transactions_mm4', 'blocks_mm4'),
  'mm5' => array('payouts_mm5', 'transactions_mm5', 'blocks_mm5'),
);
$_manual_confirmations = isset($config['confirmations']) ? max(0, (int)$config['confirmations']) : 0;
$_manual_txfee = isset($config['txfee_manual']) ? (float)$config['txfee_manual'] : 0.0;
$_manual_txfee_sql = number_format($_manual_txfee, 8, '.', '');
foreach ($manual_payout_tables as $_slot => $_tables) {
  list($_table, $_tx_table, $_block_table) = $_tables;
  if (!preg_match('/^payouts(_mm[1345]?)?$/', $_table)) continue;
  if (!preg_match('/^transactions(_mm[1345]?)?$/', $_tx_table)) continue;
  if (!preg_match('/^blocks(_mm[1345]?)?$/', $_block_table)) continue;
  $_confirmed_expr =
    "IFNULL(ROUND(("
    . "SUM(IF(((t.type IN ('Credit','Bonus') AND b.confirmations >= " . $_manual_confirmations . ") OR t.type = 'Credit_PPS'), t.amount, 0)) "
    . "- SUM(IF(t.type IN ('Debit_MP','Debit_AP'), t.amount, 0)) "
    . "- SUM(IF(((t.type IN ('Donation','Fee') AND b.confirmations >= " . $_manual_confirmations . ") OR t.type IN ('Donation_PPS','Fee_PPS','TXFee')), t.amount, 0))"
    . "), 8), 0)";
  $sql = "SELECT COUNT(*) AS cnt, COUNT(DISTINCT q.account_id) AS user_count, "
       . "GROUP_CONCAT(DISTINCT q.username ORDER BY q.username SEPARATOR ', ') AS users, "
       . "SUM(q.net_amount) AS total_amount, MIN(q.time) AS oldest, MAX(q.time) AS latest "
       . "FROM ("
       . "SELECT p.id, p.account_id, a.username, p.time, "
       . "GREATEST(ROUND((" . $_confirmed_expr . ") - " . $_manual_txfee_sql . ", 8), 0) AS net_amount "
       . "FROM " . $_table . " AS p "
       . "LEFT JOIN " . $accounts_table . " AS a ON a.id = p.account_id "
       . "LEFT JOIN " . $_tx_table . " AS t ON t.account_id = p.account_id AND t.archived = 0 "
       . "LEFT JOIN " . $_block_table . " AS b ON b.id = t.block_id "
       . "WHERE p.completed = 0 "
       . "GROUP BY p.id, p.account_id, a.username, p.time"
       . ") AS q";
  if (isset($mysqli) && $stmt = $mysqli->prepare($sql)) {
    if ($stmt->execute() && $res = $stmt->get_result()) {
      if ($row = $res->fetch_assoc()) {
        $cnt = (int)$row['cnt'];
        if ($cnt > 0) {
          $ticker = isset($slot_to_ticker[$_slot]) ? $slot_to_ticker[$_slot] : $_slot;
          $outbox_counts['pending'] += $cnt;
          $outbox_open_count += $cnt;
          $outbox_rows[] = array(
            'slot'   => $ticker,
            'status' => 'pending',
            'group'  => 'pending',
            'cnt'    => $cnt,
            'amount' => _system_amount_compact($row['total_amount']),
            'txid'   => '',
            'txshort'=> '—',
            'txconfirmations' => 0,
            'txurl'  => '',
            'user'   => _system_user_summary($row['user_count'], $row['users']),
            'oldest' => $row['oldest'],
            'latest' => $row['latest'],
            'age'    => _system_age_compact($row['latest']),
          );
        }
      }
    }
    $stmt->close();
  }
}

$backups_enabled_value = trim((string)$setting->getValue('backups_enabled'));
$sys_backup = array(
  'enabled'         => $backups_enabled_value === '0' ? 0 : 1,
  'last_mtime'      => $last_backup_mtime,
  'last_size'       => $last_backup_size,
  'next_run'        => $next_backup_run,
  'next_day_label'  => $next_day_label,
  'retention_days'  => $retention_days,
  'schedule_time'   => $schedule_time_str,
  'schedule_hour'   => $schedule_hour,
  'schedule_minute' => $schedule_minute,
  'wallets'         => $wallet_rows,
  'tarball_path'    => $latest_link,
  'database'        => !empty($backup_status['database'])
                          ? (string)$backup_status['database']
                          : '',
  'database_size'   => !empty($backup_status['database_size'])
                          ? (int)$backup_status['database_size']
                          : 0,
);

// ---- _partial=1: JSON for the live-poll endpoint -------------------
if (!empty($_GET['_partial'])) {
  while (ob_get_level() > 0) ob_end_clean();
  header('Content-Type: application/json; charset=utf-8');
  header('Cache-Control: no-store');
  echo json_encode(array(
    'ts'          => time(),
    'users'       => $users_info,
    'logins'      => $logins_info,
    'invitations' => $invitations_info,
    'versions'    => $mpos_versions,
    'services'    => $service_rows,
    'backup'      => $sys_backup,
    'cpu'         => $cpu_rows,
    'swap'             => $swap_rows,
    'swap_available'   => $swap_available_str,
    'swap_configured'  => $swap_configured,
    'memory'           => $memory_rows,
    'memory_available' => $memory_available_str,
    'disk'             => $disk_rows,
    'disk_available'   => $disk_available_str,
    'network'         => $network_rows,
    'network_miners'  => $network_miners_str,
    'network_iface'   => $network_iface,
    'daemons'     => $daemon_rows,
    'wallets'     => $wallet_panel_rows,
    'procs'       => $proc_rows,
    'outbox'      => $outbox_rows,
    'outbox_open' => $outbox_open_count,
    'outbox_counts' => $outbox_counts,
  ), JSON_UNESCAPED_SLASHES);
  exit;
}

$smarty->assign('SYS_USERS',       $users_info);
$smarty->assign('SYS_LOGINS',      $logins_info);
$smarty->assign('SYS_INVITATIONS', $invitations_info);
$smarty->assign('SYS_VERSIONS',    $mpos_versions);
$smarty->assign('SYS_SERVICES', $service_rows);
$smarty->assign('SYS_BACKUP',   $sys_backup);
$smarty->assign('SYS_CPU',      $cpu_rows);
$smarty->assign('SYS_SWAP',         $swap_rows);
$smarty->assign('SYS_SWAP_AVAIL',   $swap_available_str);
$smarty->assign('SYS_SWAP_OK',      $swap_configured);
$smarty->assign('SYS_MEMORY',       $memory_rows);
$smarty->assign('SYS_MEM_AVAIL',    $memory_available_str);
$smarty->assign('SYS_DISK',     $disk_rows);
$smarty->assign('SYS_DISK_AVAIL', $disk_available_str);
$smarty->assign('SYS_NETWORK',         $network_rows);
$smarty->assign('SYS_NET_MINERS',      $network_miners_str);
$smarty->assign('SYS_NET_IFACE',       $network_iface);
$smarty->assign('SYS_DAEMONS',  $daemon_rows);
$smarty->assign('SYS_WALLETS',  $wallet_panel_rows);
$smarty->assign('SYS_PROCS',    $proc_rows);
$smarty->assign('SYS_OUTBOX',   $outbox_rows);
$smarty->assign('SYS_OUTBOX_OPEN', $outbox_open_count);
$smarty->assign('SYS_OUTBOX_COUNTS', $outbox_counts);

$smarty->assign('CONTENT', 'default.tpl');
?>
