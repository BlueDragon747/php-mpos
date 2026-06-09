<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;
$system_status_collector_mode = defined('BSX_SYSTEM_STATUS_COLLECTOR') && BSX_SYSTEM_STATUS_COLLECTOR;

// Admin-only.
if (!$system_status_collector_mode &&
    (!$user->isAuthenticated() || !$user->isAdmin($_SESSION['USERDATA']['id']))) {
  header("HTTP/1.1 404 Page not found");
  die("404 Page not found");
}

// CSRF + method enforcement for the inline settings forms. No-op
// for plain GET, which is the partial-poll + page render path.
require_once dirname(__FILE__) . '/../../admin_csrf.inc.php';
require_once __DIR__ . '/_daemon_rule_status.inc.php';
if (!$system_status_collector_mode) _require_admin_csrf($csrftoken);

$system_status_cache_key = 'ADMIN_SYSTEM_STATUS_V1';
$system_status_cache_last_good_key = $system_status_cache_key . '_LAST_GOOD';
$system_status_cache_fresh_ttl = 60;
$system_status_cache_stale_ttl = 180;
$system_status_cache_last_good_ttl = 86400;

function _system_status_cache_full_key($key) {
  global $config;
  return (isset($config['memcache']['keyprefix']) ? $config['memcache']['keyprefix'] : '') . $key;
}

function _system_status_cache_enabled() {
  global $config, $memcache;
  return isset($memcache) && is_object($memcache) && !empty($config['memcache']['enabled']);
}

function _system_status_cache_get($key) {
  global $memcache;
  if (!_system_status_cache_enabled()) return false;
  if (method_exists($memcache, 'getStatic')) return $memcache->getStatic($key);
  if (method_exists($memcache, 'get')) return $memcache->get(_system_status_cache_full_key($key));
  return false;
}

function _system_status_cache_set($key, $value, $expiration) {
  global $memcache;
  if (!_system_status_cache_enabled()) return false;
  if (method_exists($memcache, 'setStaticCache')) return $memcache->setStaticCache($key, $value, $expiration);
  if (method_exists($memcache, 'set')) return $memcache->set(_system_status_cache_full_key($key), $value, $expiration);
  return false;
}

function _system_status_cache_delete($key) {
  global $memcache;
  if (!_system_status_cache_enabled()) return false;
  if (method_exists($memcache, 'delete') || is_callable(array($memcache, 'delete'))) {
    return @$memcache->delete(_system_status_cache_full_key($key));
  }
  return false;
}

function _system_status_empty_payload($state = 'warming', $message = 'System status warming up') {
  global $system_status_cache_fresh_ttl, $system_status_cache_stale_ttl;
  return array(
    'ts'               => time(),
    'cache'            => array(
      'hit' => false,
      'state' => $state,
      'age' => 0,
      'ttl' => $system_status_cache_fresh_ttl,
      'stale_ttl' => $system_status_cache_stale_ttl,
      'message' => $message,
    ),
    'users'            => array('total' => 0, 'active' => 0, 'locked' => 0, 'admins' => 0, 'nofees' => 0),
    'logins'           => array('24hours' => 0, '7days' => 0, '1month' => 0, '6month' => 0, '1year' => 0),
    'invitations'      => null,
    'versions'         => array(),
    'health'           => array(),
    'services'         => array(),
    'backup'           => array(
      'enabled' => 0, 'last_mtime' => 0, 'last_size' => 0, 'next_run' => 0,
      'next_day_label' => '', 'retention_days' => 0, 'schedule_time' => '',
      'schedule_hour' => 0, 'schedule_minute' => 0, 'wallets' => array(),
      'tarball_path' => '', 'database' => '', 'database_size' => 0,
    ),
    'database'         => _system_status_empty_database_payload(),
    'cpu'              => array(),
    'cpu_cores'        => '—',
    'swap'             => array(),
    'swap_available'   => '—',
    'swap_configured'  => 0,
    'memory'           => array(),
    'memory_available' => '—',
    'memory_io_summary' => array('rw' => '— / —', 'util' => '—', 'ops' => '—'),
    'disk'             => array(),
    'disk_available'   => '—',
    'disk_io_summary'  => array('rw' => '— / —', 'util' => '—', 'ops' => '—'),
    'network'          => array(),
    'network_miners'   => '—',
    'network_iface'    => '—',
    'daemons'          => array(),
    'wallets'          => array(),
    'procs'            => array(),
    'outbox'           => array(),
    'outbox_open'      => 0,
    'outbox_counts'    => array('pending' => 0, 'broadcast' => 0, 'reconciled' => 0, 'other' => 0),
  );
}

function _system_status_cached_payload($key, $max_age = null) {
  global $system_status_cache_fresh_ttl, $system_status_cache_stale_ttl;
  $cached_payload = _system_status_cache_get($key);
  if (!is_array($cached_payload) ||
      !isset($cached_payload['ts'], $cached_payload['payload']) ||
      !is_array($cached_payload['payload'])) {
    return false;
  }

  $age = max(0, time() - (int)$cached_payload['ts']);
  $allowed_age = $max_age === null ? $system_status_cache_stale_ttl : (int)$max_age;
  if ($age > $allowed_age) return false;

  $payload = $cached_payload['payload'];
  $state = $age <= $system_status_cache_fresh_ttl ? 'fresh' : 'stale';
  $payload['cache'] = array(
    'hit' => true,
    'state' => $state,
    'age' => $age,
    'ttl' => $system_status_cache_fresh_ttl,
    'stale_ttl' => $allowed_age,
    'message' => $state === 'stale' ? 'System status stale' : 'System status fresh',
  );
  return $payload;
}

function _system_status_last_good_payload($state = 'warming', $message = 'System status warming up') {
  global $system_status_cache_last_good_key, $system_status_cache_fresh_ttl, $system_status_cache_last_good_ttl;
  $payload = _system_status_cached_payload($system_status_cache_last_good_key, $system_status_cache_last_good_ttl);
  if (!is_array($payload)) return false;

  $age = isset($payload['cache']['age']) ? (int)$payload['cache']['age'] : 0;
  $payload['cache'] = array(
    'hit' => true,
    'state' => $state,
    'age' => $age,
    'ttl' => $system_status_cache_fresh_ttl,
    'stale_ttl' => $system_status_cache_last_good_ttl,
    'message' => $message,
    'last_good' => true,
  );
  return $payload;
}

function _system_status_apply_live_backup_settings($payload) {
  global $setting;
  if (!is_array($payload)) return $payload;
  if (!isset($payload['backup']) || !is_array($payload['backup'])) {
    $payload['backup'] = _system_status_empty_payload()['backup'];
  }

  $enabled_value = trim((string)$setting->getValue('backups_enabled'));
  $hour = max(0, min(23, (int)($setting->getValue('backup_schedule_hour') ?: 3)));
  $minute = max(0, min(59, (int)($setting->getValue('backup_schedule_minute') ?: 30)));
  $retention_days = max(1, min(365, (int)($setting->getValue('backup_retention_days') ?: 14)));

  $now = time();
  $target_today = gmmktime($hour, $minute, 0,
    (int)gmdate('n', $now), (int)gmdate('j', $now), (int)gmdate('Y', $now));
  $next_is_today = $target_today > $now;
  $next_epoch = $next_is_today ? $target_today : ($target_today + 86400);

  $payload['backup']['enabled'] = $enabled_value === '0' ? 0 : 1;
  $payload['backup']['schedule_hour'] = $hour;
  $payload['backup']['schedule_minute'] = $minute;
  $payload['backup']['schedule_time'] = sprintf('%02d:%02d', $hour, $minute);
  $payload['backup']['retention_days'] = $retention_days;
  $payload['backup']['next_run'] = gmdate('Y-m-d H:i', $next_epoch) . ' UTC';
  $payload['backup']['next_day_label'] = $next_is_today ? 'today' : 'tomorrow';

  return $payload;
}

function _system_status_respond_payload($payload) {
  while (ob_get_level() > 0) ob_end_clean();
  if (defined('BSX_SYSTEM_STATUS_QUIET') && BSX_SYSTEM_STATUS_QUIET) {
    exit;
  }
  header('Content-Type: application/json; charset=utf-8');
  header('Cache-Control: no-store');
  echo json_encode($payload, JSON_UNESCAPED_SLASHES);
  exit;
}

function _system_status_ajax_request() {
  if (!empty($_REQUEST['_ajax'])) return true;
  if (!empty($_SERVER['HTTP_X_REQUESTED_WITH']) &&
      strtolower((string)$_SERVER['HTTP_X_REQUESTED_WITH']) === 'xmlhttprequest') {
    return true;
  }
  return false;
}

function _system_status_json_response($payload) {
  while (ob_get_level() > 0) ob_end_clean();
  header('Content-Type: application/json; charset=utf-8');
  header('Cache-Control: no-store');
  echo json_encode($payload, JSON_UNESCAPED_SLASHES);
  exit;
}

function _system_run_manual_backup() {
  $helper = '/usr/local/sbin/blakestream-mpos-backup-now';
  if (!is_executable($helper)) {
    return array(false, 'Manual backup helper is not installed yet.');
  }
  $cmd = 'sudo -n ' . escapeshellarg($helper) . ' 2>&1';
  $out = array();
  $rc = 1;
  @exec($cmd, $out, $rc);
  $msg = trim(implode("\n", $out));
  if ($rc === 0) return array(true, $msg !== '' ? $msg : 'Backup queued.');
  return array(false, $msg !== '' ? $msg : 'Backup could not be queued.');
}

// Single mutation supported here: toggle backups_enabled. Reuses the
// same settings table the admin Settings page writes to, so flipping
// it here = flipping it there.
if (!$system_status_collector_mode && @$_POST['do'] === 'update_backup_settings') {
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

  _system_status_cache_delete($system_status_cache_key);

  $log->log("warn", @$_SESSION['USERDATA']['username']
            . ' updated backup settings via System Status: ' . implode(', ', $msgs));
  if (_system_status_ajax_request()) {
    _system_status_json_response(array(
      'ok' => true,
      'message' => 'Backup settings saved (' . implode(', ', $msgs) . ').',
      'csrf_token' => (string)$smarty->getTemplateVars('CTOKEN'),
      'backup' => array(
        'enabled' => $new_val === '1' ? 1 : 0,
      ),
    ));
  }
  $_SESSION['POPUP'][] = array(
    'CONTENT' => 'Backup settings saved (' . implode(', ', $msgs) . ').',
    'TYPE'    => 'success',
  );
  header('Location: ?page=admin&action=system');
  exit;
}

if (!$system_status_collector_mode && @$_POST['do'] === 'run_backup_now') {
  list($ok, $msg) = _system_run_manual_backup();
  _system_status_cache_delete($system_status_cache_key);
  $log->log($ok ? "warn" : "error", @$_SESSION['USERDATA']['username']
            . ' requested manual backup via System Status: ' . $msg);
  if (_system_status_ajax_request()) {
    _system_status_json_response(array(
      'ok' => $ok,
      'message' => $msg,
      'csrf_token' => (string)$smarty->getTemplateVars('CTOKEN'),
    ));
  }
  $_SESSION['POPUP'][] = array(
    'CONTENT' => $msg,
    'TYPE'    => $ok ? 'success' : 'danger',
  );
  header('Location: ?page=admin&action=system');
  exit;
}

if (!$system_status_collector_mode && @$_POST['do'] === 'update_db_prune_settings') {
  $choices = array(0, 1, 3, 7, 14, 30, 60, 90, 180, 365);
  $raw_share_choices = array(250000, 500000, 1000000, 2000000, 5000000, 10000000, 20000000, 40000000);
  $days = isset($_POST['db_prune_after_days']) && is_numeric($_POST['db_prune_after_days'])
    ? (int)$_POST['db_prune_after_days']
    : 0;
  $keep_recent_shares = isset($_POST['db_prune_keep_recent_shares']) && is_numeric($_POST['db_prune_keep_recent_shares'])
    ? (int)$_POST['db_prune_keep_recent_shares']
    : 1000000;
  if (!in_array($days, $choices, true)) $days = 0;
  if (!in_array($keep_recent_shares, $raw_share_choices, true)) $keep_recent_shares = 1000000;

  $setting->setValue('db_prune_enabled', $days > 0 ? '1' : '0');
  if ($days > 0) $setting->setValue('db_prune_after_days', (string)$days);
  $setting->setValue('db_prune_keep_recent_shares', (string)$keep_recent_shares);

  _system_status_cache_delete($system_status_cache_key);

  $msg = $days > 0
    ? "Database archive pruning set to {$days} days / latest {$keep_recent_shares} raw shares"
    : 'Database archive pruning disabled';
  $log->log("warn", @$_SESSION['USERDATA']['username']
            . ' updated database prune settings via System Status: ' . $msg);
  if (_system_status_ajax_request()) {
    _system_status_json_response(array(
      'ok' => true,
      'message' => $msg,
      'csrf_token' => (string)$smarty->getTemplateVars('CTOKEN'),
      'database' => array(
        'prune_enabled' => $days > 0 ? 1 : 0,
        'prune_after_days' => $days,
        'keep_recent_shares' => $keep_recent_shares,
      ),
    ));
  }
  $_SESSION['POPUP'][] = array('CONTENT' => $msg . '.', 'TYPE' => 'success');
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

function _system_coin_slug($value) {
  $slug = strtolower(trim((string)$value));
  $slug = preg_replace('/[^a-z0-9]+/', '', $slug);
  return $slug ? $slug : '';
}

function _system_configured_daemon_container_candidates() {
  global $config;
  $candidates = array();
  $env = getenv('MPOS_DAEMON_CONTAINERS');
  if ($env !== false && trim($env) !== '') {
    foreach (explode(',', $env) as $name) {
      $slug = _system_coin_slug($name);
      if ($slug !== '') $candidates[$slug] = strtoupper($slug);
    }
  }
  foreach (array('currency', 'currency_mm', 'currency_mm1', 'currency_mm2', 'currency_mm3', 'currency_mm4', 'currency_mm5', 'currency_mm6') as $key) {
    if (empty($config[$key])) continue;
    $ticker = trim((string)$config[$key]);
    if ($ticker === '' || stripos($ticker, 'unused') !== false) continue;
    $slug = _system_coin_slug($ticker);
    if ($slug !== '') $candidates[$slug] = strtoupper($ticker);
  }
  return $candidates;
}

function _system_docker_mem_to_mb($value) {
  $value = trim((string)$value);
  if (!preg_match('/^([0-9]+(?:\.[0-9]+)?)\s*([KMGTPE]?i?B?)$/i', $value, $m)) return '';
  $n = (float)$m[1];
  $unit = strtoupper($m[2]);
  if ($unit === '' || $unit === 'B') return round($n / 1048576, 1);
  if ($unit === 'KB' || $unit === 'KIB') return round($n / 1024, 1);
  if ($unit === 'MB' || $unit === 'MIB') return round($n, 1);
  if ($unit === 'GB' || $unit === 'GIB') return round($n * 1024, 1);
  if ($unit === 'TB' || $unit === 'TIB') return round($n * 1048576, 1);
  return '';
}

function _system_process_metrics($pid) {
  $pid = (int)$pid;
  if ($pid <= 0) return array('pid' => '', 'cpu_pct' => '', 'rss_mb' => '');
  $raw = _system_run('ps -p ' . (int)$pid . ' -o pcpu=,rss=', 4096);
  if ($raw === '') return array('pid' => (string)$pid, 'cpu_pct' => '', 'rss_mb' => '');
  $parts = preg_split('/\s+/', trim($raw));
  $cpu = isset($parts[0]) && is_numeric($parts[0]) ? round((float)$parts[0], 1) : '';
  $rss = isset($parts[1]) && is_numeric($parts[1]) ? round(((int)$parts[1]) / 1024, 1) : '';
  return array(
    'pid'     => (string)$pid,
    'cpu_pct' => $cpu,
    'rss_mb'  => $rss,
  );
}

function _system_daemon_container_proc_rows() {
  $candidates = _system_configured_daemon_container_candidates();
  if (!$candidates) return array();
  $raw = _system_run("command -v docker >/dev/null 2>&1 && docker stats --no-stream --format '{{.Name}}\t{{.MemUsage}}'", 65536);
  if ($raw === '') return array();
  $rows = array();
  foreach (preg_split('/\r?\n/', $raw) as $line) {
    $line = trim($line);
    if ($line === '') continue;
    $parts = explode("\t", $line, 2);
    if (count($parts) < 2) continue;
    $name = trim($parts[0]);
    $slug = _system_coin_slug($name);
    if ($slug === '' || !isset($candidates[$slug])) continue;
    $mem = trim(explode('/', $parts[1], 2)[0]);
    $rows[] = array(
      'label'  => strtolower($candidates[$slug]),
      'pid'    => $name,
      'rss_mb' => _system_docker_mem_to_mb($mem),
    );
  }
  return $rows;
}

function _system_daemon_process_proc_rows() {
  $raw = _system_run("ps -eo pid=,rss=,args= | grep -- '-datadir=' | grep -v grep", 65536);
  if ($raw === '') return array();
  $rows = array();
  $seen = array();
  foreach (preg_split('/\r?\n/', $raw) as $line) {
    if (!preg_match('/^\s*([0-9]+)\s+([0-9]+)\s+(.+)$/', $line, $m)) continue;
    $pid = $m[1];
    $rss_kb = (int)$m[2];
    $args = $m[3];
    if (!preg_match('/(?:^|\s)-datadir=([^\s]+)/', $args, $dm)) continue;
    $datadir = trim($dm[1], "\"'");
    $label = basename($datadir);
    $label = ltrim($label, '.');
    $slug = _system_coin_slug($label);
    if ($slug === '' || isset($seen[$slug])) continue;
    $seen[$slug] = true;
    $rows[] = array(
      'label'  => $slug,
      'pid'    => $pid,
      'rss_mb' => round($rss_kb / 1024, 1),
    );
  }
  return $rows;
}

function _system_daemon_service_rows() {
  $raw = _system_run("ps -eo pid=,lstart=,args= | grep -- '-datadir=' | grep -v grep", 65536);
  if ($raw === '') return array();
  $rows = array();
  $seen = array();
  foreach (preg_split('/\r?\n/', $raw) as $line) {
    if (!preg_match('/^\s*([0-9]+)\s+([A-Z][a-z]{2}\s+[A-Z][a-z]{2}\s+\d{1,2}\s+\d\d:\d\d:\d\d\s+\d{4})\s+(.+)$/', $line, $m)) continue;
    $args = $m[3];
    if (!preg_match('/(?:^|\s)-datadir=([^\s]+)/', $args, $dm)) continue;
    $datadir = trim($dm[1], "\"'");
    $label = basename($datadir);
    $label = ltrim($label, '.');
    $slug = _system_coin_slug($label);
    if ($slug === '' || isset($seen[$slug])) continue;
    $seen[$slug] = true;
    $ts = strtotime($m[2]);
    $since_ts = $ts ? (int)$ts : 0;
    $metrics = _system_process_metrics((int)$m[1]);
    $rows[] = array(
      'label'    => $slug,
      'unit'     => 'process:' . $m[1],
      'state'    => 'active',
      'since'    => $since_ts ? gmdate('D Y-m-d H:i:s \U\T\C', $since_ts) : $m[2],
      'since_ts' => $since_ts,
      'duration' => _system_duration_from_epoch($since_ts),
      'pid'      => $metrics['pid'],
      'cpu_pct'  => $metrics['cpu_pct'],
      'rss_mb'   => $metrics['rss_mb'],
    );
  }
  usort($rows, function ($a, $b) {
    return strcmp($a['label'], $b['label']);
  });
  return $rows;
}

function _system_unit_candidate($unit) {
  $scope = 'system';
  $name = (string)$unit;
  if (preg_match('/^(user|system):(.*)$/', $name, $m)) {
    $scope = $m[1];
    $name = $m[2];
  }
  if ($name !== '' && substr($name, -8) !== '.service' && substr($name, -6) !== '.timer') {
    $name .= '.service';
  }
  return array('scope' => $scope, 'name' => $name);
}

function _system_unit_cmd($candidate, $verb) {
  $prefix = $candidate['scope'] === 'user' ? 'systemctl --user ' : 'systemctl ';
  return $prefix . $verb . ' ' . escapeshellarg($candidate['name']);
}

function _system_unit_best($units) {
  if (!is_array($units)) $units = array($units);

  $fallback = null;
  foreach ($units as $unit) {
    $candidate = _system_unit_candidate($unit);
    if ($candidate['name'] === '') continue;
    $state = _system_run(_system_unit_cmd($candidate, 'is-active'));
    if ($state === '' || $state === 'unknown') continue;

    $row = array(
      'scope' => $candidate['scope'],
      'name' => $candidate['name'],
      'state' => $state,
    );
    if (in_array($state, array('active', 'activating', 'failed'), true)) return $row;
    if ($fallback === null) $fallback = $row;
  }

  return $fallback ?: array('scope' => '', 'name' => '', 'state' => '');
}

/**
 * systemctl is-active <unit> → returns the literal state string
 * ("active", "inactive", "failed", "activating", or "" on error).
 * Candidate arrays are checked in order, with active/failed states taking
 * precedence over inactive legacy units.
 */
function _system_unit_state($unit) {
  $best = _system_unit_best($unit);
  return $best['state'];
}

function _system_unit_active_since($unit) {
  $best = _system_unit_best($unit);
  if ($best['name'] === '') return '';
  $ts = _system_run(_system_unit_cmd($best, 'show') . ' -p ActiveEnterTimestamp --value');
  if ($ts === '' || $ts === '0' || $ts === 'n/a') return '';
  return $ts;
}

function _system_unit_main_pid($unit) {
  $best = _system_unit_best($unit);
  if ($best['name'] === '' || substr($best['name'], -6) === '.timer') return 0;
  $pid = trim(_system_run(_system_unit_cmd($best, 'show') . ' -p MainPID --value'));
  return is_numeric($pid) ? (int)$pid : 0;
}

function _system_unit_selected_name($unit) {
  $best = _system_unit_best($unit);
  if ($best['name'] === '') return '';
  return ($best['scope'] !== '' ? $best['scope'] . ':' : '') . $best['name'];
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

function _system_ops_rate($ops) {
  $ops = max(0.0, (float)$ops);
  return number_format((int)round($ops)) . '/s';
}

function _system_size_from_mb($mb) {
  $mb = (int)$mb;
  if ($mb < 0) return '—';
  if ($mb >= 1024) return number_format($mb / 1024, 1) . ' GB';
  return number_format($mb) . ' MB';
}

function _system_daemon_status_cache_file() {
  $uid = function_exists('posix_geteuid') ? (string)posix_geteuid() : (string)getmyuid();
  return sys_get_temp_dir() . '/blakestream-mpos-daemon-status-v1-' . $uid . '.json';
}

function _system_daemon_status_cache_load() {
  $file = _system_daemon_status_cache_file();
  if (!is_file($file)) return array();
  $raw = @file_get_contents($file);
  if ($raw === false || $raw === '') return array();
  $data = json_decode($raw, true);
  return is_array($data) ? $data : array();
}

function _system_daemon_status_cache_save($cache) {
  if (!is_array($cache)) return;
  @file_put_contents(_system_daemon_status_cache_file(), json_encode($cache), LOCK_EX);
}

function _system_daemon_status_cache_entry($cache, $sym, $now, $grace_seconds) {
  $sym = strtoupper((string)$sym);
  if (!is_array($cache) || empty($cache[$sym]) || !is_array($cache[$sym])) return null;
  $entry = $cache[$sym];
  $ts = isset($entry['ts']) ? (int)$entry['ts'] : 0;
  if ($ts <= 0 || ($now - $ts) > $grace_seconds) return null;
  if (empty($entry['row']) || !is_array($entry['row'])) return null;
  return $entry;
}

function _system_daemon_status_cached_row($cache, $sym, $now, $grace_seconds, $error = '') {
  $entry = _system_daemon_status_cache_entry($cache, $sym, $now, $grace_seconds);
  if (!$entry) return null;

  $row = $entry['row'];
  $age = max(0, $now - (int)$entry['ts']);
  $detail = 'Using cached daemon status from ' . $age . 's ago after an RPC timeout.';
  $error = trim((string)$error);
  if ($error !== '') {
    $detail .= ' Last error: ' . substr($error, 0, 160);
  }

  $row['stale'] = true;
  $row['stale_age'] = $age;
  $row['stale_detail'] = $detail;
  return $row;
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

function _system_duration_compact_seconds($diff) {
  $diff = max(0, (int)$diff);
  $units = array(
    array('label' => 'y',  'seconds' => 31536000),
    array('label' => 'mo', 'seconds' => 2592000),
    array('label' => 'd',  'seconds' => 86400),
    array('label' => 'h',  'seconds' => 3600),
    array('label' => 'm',  'seconds' => 60),
  );
  $parts = array();
  foreach ($units as $unit) {
    if ($diff < $unit['seconds']) continue;
    $n = (int)floor($diff / $unit['seconds']);
    $diff -= $n * $unit['seconds'];
    $parts[] = $n . $unit['label'];
    if (count($parts) >= 3) break;
  }
  return $parts ? implode(' ', $parts) : 'now';
}

function _system_duration_from_epoch($epoch) {
  $epoch = (int)$epoch;
  if ($epoch <= 0) return '—';
  return _system_duration_compact_seconds(time() - $epoch);
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
  if ($txid === '') return '';
  if ($base === '' || stripos($base, 'explorer.litecoin.net') !== false) {
    $base = 'https://explorer.blakestream.io/{coin}?tx=';
  }
  if (strpos($base, '{coin}') !== false) {
    $base = str_replace('{coin}', rawurlencode(strtolower((string)$coin)), $base);
  }
  if (strpos($base, '{txid}') !== false) {
    return str_replace('{txid}', rawurlencode($txid), $base);
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

function _system_bytes_words($n) {
  if (!is_numeric($n) || $n < 0) return '—';
  $b = (float)$n; $units = array('Bytes','KBytes','MBytes','GBytes','TBytes','PBytes'); $i = 0;
  while ($b >= 1024 && $i < count($units) - 1) { $b /= 1024; $i++; }
  $fmt = $b >= 100 ? '%.0f %s' : ($b >= 10 ? '%.1f %s' : '%.2f %s');
  return sprintf($fmt, $b, $units[$i]);
}

function _system_db_prune_choices() {
  return array(
    array('value' => 0,   'label' => 'Disabled'),
    array('value' => 1,   'label' => '1 day'),
    array('value' => 3,   'label' => '3 days'),
    array('value' => 7,   'label' => '7 days'),
    array('value' => 14,  'label' => '14 days'),
    array('value' => 30,  'label' => '30 days'),
    array('value' => 60,  'label' => '60 days'),
    array('value' => 90,  'label' => '90 days'),
    array('value' => 180, 'label' => '180 days'),
    array('value' => 365, 'label' => '365 days'),
  );
}

function _system_db_keep_recent_share_choices() {
  return array(
    // 250k is the absolute accounting floor; 1M is the recommended
    // production default for low and mixed-difficulty pools.
    array('value' => 250000,   'label' => '250k shares'),
    array('value' => 500000,   'label' => '500k shares'),
    array('value' => 1000000,  'label' => '1M shares'),
    array('value' => 2000000,  'label' => '2M shares'),
    array('value' => 5000000,  'label' => '5M shares'),
    array('value' => 10000000, 'label' => '10M shares'),
    array('value' => 20000000, 'label' => '20M shares'),
    array('value' => 40000000, 'label' => '40M shares'),
  );
}

function _system_setting_int_value($name, $default, $min, $max) {
  global $setting;
  $raw = $setting->getValue($name);
  if ($raw === null || $raw === '' || !is_numeric($raw)) return (int)$default;
  return max((int)$min, min((int)$max, (int)$raw));
}

function _system_status_empty_database_payload() {
  global $setting;

  $enabled_raw = isset($setting) ? trim((string)$setting->getValue('db_prune_enabled')) : '1';
  $prune_enabled = $enabled_raw !== '0';
  $prune_after_days = _system_setting_int_value('db_prune_after_days', 180, 1, 3650);
  if (!$prune_enabled) $prune_after_days = 0;
  $keep_recent_shares = _system_setting_int_value('db_prune_keep_recent_shares', 1000000, 250000, 40000000);
  $prune_last_run = _system_setting_int_value('db_prune_last_run', 0, 0, PHP_INT_MAX);
  $prune_last_deleted = _system_setting_int_value('db_prune_last_deleted', 0, 0, PHP_INT_MAX);
  $prune_last_status = isset($setting) ? (string)$setting->getValue('db_prune_last_status') : '';

  return array(
    'tables' => array(), 'total_size' => '—', 'total_rows' => '—',
    'archive_oldest' => '—', 'archive_newest' => '—',
    'prune_enabled' => $prune_after_days > 0 ? 1 : 0,
    'prune_after_days' => $prune_after_days,
    'prune_choices' => _system_db_prune_choices(),
    'keep_recent_shares' => $keep_recent_shares,
    'keep_recent_share_choices' => _system_db_keep_recent_share_choices(),
    'prune_last_run' => $prune_last_run,
    'prune_last_run_age' => $prune_last_run > 0
      ? _system_age_compact(gmdate('Y-m-d H:i:s', $prune_last_run))
      : 'never',
    'prune_last_deleted' => $prune_last_deleted,
    'prune_last_status' => $prune_last_status,
  );
}

function _system_db_ident($name) {
  return preg_match('/^[A-Za-z0-9_]+$/', (string)$name)
    ? '`' . str_replace('`', '``', (string)$name) . '`'
    : '';
}

function _system_db_table_meta($mysqli, $tables) {
  $out = array();
  if (!isset($mysqli) || !is_object($mysqli) || empty($tables)) return $out;
  $names = array();
  foreach ($tables as $table) {
    if (preg_match('/^[A-Za-z0-9_]+$/', (string)$table)) {
      $names[] = "'" . $mysqli->real_escape_string((string)$table) . "'";
    }
  }
  if (!$names) return $out;

  $sql = "SELECT TABLE_NAME, TABLE_ROWS, DATA_LENGTH, INDEX_LENGTH "
       . "FROM information_schema.TABLES "
       . "WHERE TABLE_SCHEMA = DATABASE() "
       . "AND TABLE_NAME IN (" . implode(',', $names) . ")";
  if ($res = $mysqli->query($sql)) {
    while ($row = $res->fetch_assoc()) {
      $out[$row['TABLE_NAME']] = array(
        'rows'  => max(0, (int)$row['TABLE_ROWS']),
        'bytes' => max(0, (int)$row['DATA_LENGTH'] + (int)$row['INDEX_LENGTH']),
      );
    }
    $res->free();
  }
  return $out;
}

function _system_db_sum_meta($meta, $tables) {
  $rows = 0;
  $bytes = 0;
  foreach ($tables as $table) {
    if (!isset($meta[$table])) continue;
    $rows += (int)$meta[$table]['rows'];
    $bytes += (int)$meta[$table]['bytes'];
  }
  return array('rows' => $rows, 'bytes' => $bytes);
}

function _system_db_time_edge($mysqli, $table, $direction) {
  $ident = _system_db_ident($table);
  if (!$ident || !isset($mysqli) || !is_object($mysqli)) return '';
  $dir = strtoupper($direction) === 'DESC' ? 'DESC' : 'ASC';
  $sql = "SELECT time FROM {$ident} ORDER BY time {$dir} LIMIT 1";
  if ($res = $mysqli->query($sql)) {
    $row = $res->fetch_assoc();
    $res->free();
    return $row && !empty($row['time']) ? (string)$row['time'] : '';
  }
  return '';
}

function _system_db_archive_edge($mysqli, $tables, $direction) {
  $best = '';
  foreach ($tables as $table) {
    $ts = _system_db_time_edge($mysqli, $table, $direction);
    if ($ts === '') continue;
    if ($best === '') {
      $best = $ts;
      continue;
    }
    $cmp = strcmp($ts, $best);
    if ((strtoupper($direction) === 'ASC' && $cmp < 0) ||
        (strtoupper($direction) === 'DESC' && $cmp > 0)) {
      $best = $ts;
    }
  }
  return $best;
}

function _system_db_row_estimate($n) {
  if (!is_numeric($n)) return '—';
  return '~' . number_format((int)$n);
}

function _system_boot_time_str() {
  $stat = @file_get_contents('/proc/stat');
  if ($stat && preg_match('/^btime\s+(\d+)/m', $stat, $m)) {
    return gmdate('Y-m-d H:i \U\T\C', (int)$m[1]);
  }
  return '';
}

function _system_health_chip($label, $value, $state = 'ok', $tooltip = '', $items = array()) {
  $state = in_array($state, array('ok', 'warn', 'bad'), true) ? $state : 'warn';
  if (!is_array($items)) $items = array();
  return array(
    'label'      => (string)$label,
    'value'      => (string)$value,
    'state'      => $state,
    'tooltip'    => (string)$tooltip,
    'items'      => $items,
    'items_json' => json_encode($items),
  );
}

function _system_db_scalar($mysqli, $sql) {
  if (!isset($mysqli) || !is_object($mysqli)) return null;
  $res = @$mysqli->query($sql);
  if (!$res) return null;
  $row = $res->fetch_row();
  $res->free();
  return $row ? $row[0] : null;
}

function _system_auxpow_health_chip() {
  $payload = json_encode(array(
    'jsonrpc' => '2.0',
    'id'      => 1,
    'method'  => 'getaux',
    'params'  => array(),
  ));
  $ctx = stream_context_create(array(
    'http' => array(
      'method'        => 'POST',
      'header'        => "Content-Type: application/json\r\n",
      'content'       => $payload,
      'timeout'       => 2,
      'ignore_errors' => true,
    ),
  ));
  $raw = @file_get_contents('http://127.0.0.1:19335/', false, $ctx);
  if ($raw === false || trim($raw) === '') {
    return _system_health_chip('Aux', 'down', 'bad', 'Merged-mine proxy getaux did not respond.');
  }
  $json = json_decode($raw, true);
  if (!is_array($json) || !empty($json['error']) || empty($json['result']) || !is_array($json['result'])) {
    return _system_health_chip('Aux', 'error', 'bad', 'Merged-mine proxy getaux returned an error.');
  }
  $result = $json['result'];
  $ready = isset($result['ready_count']) ? (int)$result['ready_count'] : 0;
  $total = isset($result['total_chains']) ? (int)$result['total_chains'] : 0;
  if ($total <= 0 && !empty($result['readiness']) && is_array($result['readiness'])) {
    $total = count($result['readiness']);
  }
  $failures = 0;
  $parts = array();
  $items = array();
  if (!empty($result['readiness']) && is_array($result['readiness'])) {
    foreach ($result['readiness'] as $row) {
      if (!is_array($row)) continue;
      $name = isset($row['chain']) ? (string)$row['chain'] : (isset($row['alias']) ? (string)$row['alias'] : 'aux');
      $status = !empty($row['ready']) ? 'ready' : (isset($row['status']) ? (string)$row['status'] : 'waiting');
      $f = isset($row['failures']) ? (int)$row['failures'] : 0;
      $failures += $f;
      $parts[] = $name . ' ' . $status . ' failures ' . $f;
      $items[] = array(
        'label' => $name,
        'value' => $status,
        'state' => (!empty($row['ready']) && $f === 0) ? 'ok' : 'warn',
        'meta'  => 'failures ' . $f,
      );
    }
  }
  $state = ($total > 0 && $ready >= $total && $failures === 0) ? 'ok' : 'warn';
  $tip = 'AuxPoW readiness';
  if ($failures > 0) $tip .= ' — failures ' . $failures;
  if ($parts) $tip .= ': ' . implode('; ', $parts);
  return _system_health_chip('Aux', $ready . '/' . max(0, $total), $state, $tip, $items);
}

function _system_importer_health_chip() {
  $log_path = '/var/log/blakestream-eliopool-25.2-go/shares.log';
  $state_path = '/var/lib/blakestream-mpos/go-share-log-importer.state';
  if (!is_file($log_path) || !is_readable($log_path)) {
    return _system_health_chip('Importer', 'no log', 'warn', 'Share log is not readable.');
  }
  if (!is_file($state_path) || !is_readable($state_path)) {
    return _system_health_chip('Importer', 'no state', 'warn', 'Share importer state file is not readable.');
  }
  $state = json_decode((string)@file_get_contents($state_path), true);
  $st = @stat($log_path);
  if (!is_array($state) || !is_array($st)) {
    return _system_health_chip('Importer', 'unknown', 'warn', 'Could not compare share log and importer state.');
  }
  $same_file = isset($state['dev'], $state['ino']) && (int)$state['dev'] === (int)$st['dev'] && (int)$state['ino'] === (int)$st['ino'];
  $offset = isset($state['offset']) ? (int)$state['offset'] : 0;
  $size = isset($st['size']) ? (int)$st['size'] : 0;
  $lag = $same_file ? max(0, $size - $offset) : $size;
  $state_name = $lag <= 1048576 ? 'ok' : ($lag <= 10485760 ? 'warn' : 'bad');
  $value = $lag <= 0 ? 'OK' : _system_bytes_words($lag);
  $tip = 'Share-log importer lag: ' . _system_bytes_words($lag) . ' behind';
  if (!$same_file) $tip .= ' after log rotation';
  return _system_health_chip('Importer', $value, $state_name, $tip);
}

function _system_share_rate_health_chip($mysqli) {
  $shares = _system_db_scalar(
    $mysqli,
    "SELECT IFNULL(SUM(valid_count), 0) FROM share_stats_recent WHERE last_share_time > DATE_SUB(NOW(), INTERVAL 5 MINUTE)"
  );
  if ($shares === null) {
    return _system_health_chip('Shares', '—', 'warn', 'Recent share summary is not available.');
  }
  $shares = (int)$shares;
  $per_min = (int)round($shares / 5);
  $state = $shares > 0 ? 'ok' : 'warn';
  return _system_health_chip('Shares', number_format($per_min) . '/min', $state, number_format($shares) . ' accepted shares in the last 5 minutes.');
}

function _system_cron_health_chip($mysqli) {
  if (!isset($mysqli) || !is_object($mysqli)) {
    return _system_health_chip('Cron', '—', 'warn', 'Database connection unavailable.');
  }
  $bad = 0;
  $last_end = 0;
  $statuses = 0;
  $jobs = array();
  $res = @$mysqli->query("SELECT name, value FROM monitoring WHERE name LIKE '%\\_status' OR name LIKE '%\\_endtime'");
  if (!$res) {
    return _system_health_chip('Cron', '—', 'warn', 'Cron monitoring table is not readable.');
  }
  while ($row = $res->fetch_assoc()) {
    $name = isset($row['name']) ? (string)$row['name'] : '';
    $value = isset($row['value']) ? (string)$row['value'] : '';
    if (substr($name, -7) === '_status') {
      $statuses++;
      $job = substr($name, 0, -7);
      if (!isset($jobs[$job])) $jobs[$job] = array('status' => '', 'endtime' => 0);
      $jobs[$job]['status'] = $value;
      if ($value !== '' && $value !== '0') $bad++;
    } elseif (substr($name, -8) === '_endtime' && is_numeric($value)) {
      $job = substr($name, 0, -8);
      if (!isset($jobs[$job])) $jobs[$job] = array('status' => '', 'endtime' => 0);
      $jobs[$job]['endtime'] = (int)$value;
      $last_end = max($last_end, (int)$value);
    }
  }
  $res->free();
  if ($statuses <= 0) {
    return _system_health_chip('Cron', 'warming', 'warn', 'No cron job status rows have been recorded yet.');
  }
  $age = $last_end > 0 ? max(0, time() - $last_end) : 0;
  $state = $bad === 0 && ($last_end <= 0 || $age <= 900) ? 'ok' : 'warn';
  $value = $bad === 0 ? 'OK' : ($bad . ' bad');
  $tip = 'Cron status rows: ' . $statuses . '; last completed job ' . ($last_end > 0 ? _system_duration_compact_seconds($age) . ' ago' : 'unknown');
  ksort($jobs);
  $items = array();
  foreach ($jobs as $job => $row) {
    $status_raw = isset($row['status']) ? (string)$row['status'] : '';
    $ok = ($status_raw === '' || $status_raw === '0');
    $end = isset($row['endtime']) ? (int)$row['endtime'] : 0;
    $items[] = array(
      'label' => str_replace('_', ' ', $job),
      'value' => $ok ? 'OK' : ('exit ' . $status_raw),
      'state' => $ok ? 'ok' : 'bad',
      'meta'  => $end > 0 ? ('last ' . _system_duration_compact_seconds(max(0, time() - $end)) . ' ago') : 'last unknown',
    );
  }
  return _system_health_chip('Cron', $value, $state, $tip, $items);
}

function _system_health_summary($mysqli) {
  return array(
    _system_auxpow_health_chip(),
    _system_importer_health_chip(),
    _system_share_rate_health_chip($mysqli),
    _system_cron_health_chip($mysqli),
  );
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

function _system_disk_device_candidates($source) {
  $source = trim((string)$source);
  if ($source === '') return array();
  $base = basename($source);
  if ($base === '' || $base === '.' || $base === '..') return array();
  $out = array($base);
  if (preg_match('/^(nvme\d+n\d+)p\d+$/', $base, $m)) {
    $out[] = $m[1];
  } elseif (preg_match('/^(mmcblk\d+)p\d+$/', $base, $m)) {
    $out[] = $m[1];
  } elseif (preg_match('/^([A-Za-z]+)\d+$/', $base, $m)) {
    $out[] = $m[1];
  }
  return array_values(array_unique($out));
}

function _system_diskstats_read_for_path($path) {
  $source = trim(_system_run('df --output=source ' . escapeshellarg($path) . ' | tail -1'));
  $candidates = _system_disk_device_candidates($source);
  if (!$candidates) return null;
  $wanted = array_fill_keys($candidates, true);
  $lines = @file('/proc/diskstats', FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
  if (!$lines) return null;
  foreach ($lines as $line) {
    $parts = preg_split('/\s+/', trim($line));
    if (count($parts) < 14 || empty($wanted[$parts[2]])) continue;
    return array(
      'device'        => $parts[2],
      'reads'         => (int)$parts[3],
      'read_sectors'  => (int)$parts[5],
      'writes'        => (int)$parts[7],
      'write_sectors' => (int)$parts[9],
      'io_ms'         => (int)$parts[12],
      'ts'            => microtime(true),
    );
  }
  return null;
}

function _system_vmstat_read() {
  $lines = @file('/proc/vmstat', FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
  if (!$lines) return null;
  $wanted = array(
    'pgpgin' => 0, 'pgpgout' => 0,
    'pswpin' => 0, 'pswpout' => 0,
    'pgfault' => 0, 'pgmajfault' => 0,
  );
  foreach ($lines as $line) {
    $parts = preg_split('/\s+/', trim($line));
    if (count($parts) !== 2 || !array_key_exists($parts[0], $wanted)) continue;
    $wanted[$parts[0]] = (int)$parts[1];
  }
  $wanted['ts'] = microtime(true);
  return $wanted;
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

$system_status_payload = _system_status_cached_payload($system_status_cache_key);
if (!$system_status_collector_mode) {
  if (!is_array($system_status_payload)) {
    $system_status_payload = _system_status_last_good_payload('warming', 'System status warming up');
    if (!is_array($system_status_payload)) {
      $system_status_payload = _system_status_empty_payload();
    }
  }
} else {
  $lock_file = sys_get_temp_dir() . '/blakestream-mpos-system-status-cache.lock';
  $lock_fp = @fopen($lock_file, 'c');
  if (!$lock_fp || !@flock($lock_fp, LOCK_EX | LOCK_NB)) {
    if (is_array($system_status_payload)) {
      $system_status_payload['cache']['state'] = 'refreshing';
      $system_status_payload['cache']['message'] = 'System status refresh already running';
      _system_status_respond_payload($system_status_payload);
    }
    $last_good_payload = _system_status_last_good_payload('refreshing', 'System status refresh already running');
    if (is_array($last_good_payload)) {
      _system_status_respond_payload($last_good_payload);
    }
    _system_status_respond_payload(_system_status_empty_payload('warming', 'System status refresh already running'));
  }
}

if ($system_status_collector_mode) {
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

function _system_mariadb_version_label($mysqli) {
  if (!isset($mysqli) || !is_object($mysqli)) return '—';
  $server_info = '';
  if (isset($mysqli->server_info)) $server_info = (string)$mysqli->server_info;
  if ($server_info === '' && function_exists('mysqli_get_server_info')) {
    $server_info = (string)@mysqli_get_server_info($mysqli);
  }
  if ($server_info === '') return '—';
  if (preg_match('/\d+\.\d+(?:\.\d+)?/', $server_info, $m)) return $m[0];
  return $server_info;
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
  array('label' => 'Schema',   'current' => DB_VERSION,
        'installed' => (string)$setting->getValue('DB_VERSION'),
        'match' => DB_VERSION === (string)$setting->getValue('DB_VERSION')),
  array('label' => 'MariaDB',  'current' => _system_mariadb_version_label(isset($mysqli) ? $mysqli : null),
        'installed' => _system_mariadb_version_label(isset($mysqli) ? $mysqli : null),
        'match' => true),
);
$system_health = _system_health_summary(isset($mysqli) ? $mysqli : null);

// ---- Services panel -------------------------------------------------
$services = array(
  'go-eliopool'    => array('user:mpos25-go-eliopool.service', 'system:blakestream-eloipool-25.2-go.service', 'system:blakestream-eliopool-25.2-go.service', 'system:blakestream-mpos-eloipool.service'),
  'cronjobs-py'    => array('user:mpos25-cronjobs.service', 'system:blakestream-mpos-cronjobs.service'),
  'merged-mining'  => array('user:mpos25-go-eliopool.service', 'system:blakestream-eloipool-25.2-go.service', 'system:blakestream-eliopool-25.2-go.service', 'user:mpos25-mmp.service', 'system:blakestream-mpos-mergeminer.service'),
  'web'            => array('user:mpos25-web.service', 'system:nginx.service'),
  'mariadb'        => array('user:mpos25-mariadb.service', 'system:mariadb.service'),
  'memcached'      => 'system:memcached.service',
  'system-status'  => 'system:blakestream-mpos-system-status-cache.service',
  'backup-timer'   => array('user:mpos25-backup.timer', 'system:blakestream-mpos-backup.timer'),
);
$service_rows = array();
foreach ($services as $label => $unit) {
  $since = _system_unit_active_since($unit);
  $since_ts = $since !== '' ? (int)strtotime($since) : 0;
  $metrics = _system_process_metrics(_system_unit_main_pid($unit));
  $service_rows[] = array(
    'label'    => $label,
    'unit'     => _system_unit_selected_name($unit),
    'state'    => _system_unit_state($unit),
    'since'    => $since,
    'since_ts' => $since_ts,
    'duration' => _system_duration_from_epoch($since_ts),
    'pid'      => $metrics['pid'],
    'cpu_pct'  => $metrics['cpu_pct'],
    'rss_mb'   => $metrics['rss_mb'],
  );
}
foreach (_system_daemon_service_rows() as $daemon_service_row) {
  $service_rows[] = $daemon_service_row;
}
usort($service_rows, function ($a, $b) {
  return strcmp(strtolower($a['label']), strtolower($b['label']));
});

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

$disk_targets = array(
  'Backups'  => $backup_dir,
  'DB'       => '/var/lib/mysql',
  'Logs'     => '/var/log/blakestream-mpos',
  'Daemons'  => '__daemon_datadirs_total__',
);
$disk_rows = array();
$disk_helper_sizes = _system_disk_stats_helper_sizes();
$disk_available_str = '—';
foreach ($disk_targets as $label => $path) {
  $df_path = $path === '__daemon_datadirs_total__' ? '/' : $path;
  if (!is_dir($df_path) && $path !== '__daemon_datadirs_total__') continue;
  $line = _system_run('df -BM --output=source,size,used,avail,pcent ' . escapeshellarg($df_path) . ' | tail -1');
  if (!$line) continue;
  $parts = preg_split('/\s+/', trim($line));
  if (count($parts) < 5) continue;
  $fs_size_mb = (int)$parts[1];
  if ($disk_available_str === '—') $disk_available_str = _system_size_from_mb((int)$parts[3]);
  $dir_size = $path === '__daemon_datadirs_total__'
    ? (isset($disk_helper_sizes[$path])
        ? array('label' => _system_size_from_mb((int)$disk_helper_sizes[$path]), 'mb' => (int)$disk_helper_sizes[$path])
        : array('label' => '—', 'mb' => null))
    : _system_du_size_info($path, $disk_helper_sizes);
  $disk_rows[] = array(
    'label'   => $label,
    'path'    => $path === '__daemon_datadirs_total__' ? 'daemon data folders' : $path,
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
$disk_io_device = '—';
$disk_io_read_rate = '—';
$disk_io_write_rate = '—';
$disk_io_util = '—';
$disk_io_ops = '—';
$disk_io_now = _system_diskstats_read_for_path('/var/lib/mysql');
if ($disk_io_now) {
  $disk_io_device = $disk_io_now['device'];
  $uid = function_exists('posix_geteuid') ? (string)posix_geteuid() : (string)getmyuid();
  $state_file = sys_get_temp_dir() . '/blakestream-mpos-system-disk-io-' . $disk_io_device . '-' . $uid . '.json';
  if (is_readable($state_file)) {
    $prev = json_decode((string)@file_get_contents($state_file), true);
    if (is_array($prev) &&
        isset($prev['reads'], $prev['read_sectors'], $prev['writes'], $prev['write_sectors'], $prev['io_ms'], $prev['ts'])) {
      $age = $disk_io_now['ts'] - (float)$prev['ts'];
      if ($age >= 0.5 && $age < 300) {
        $read_bytes = max(0, ((int)$disk_io_now['read_sectors'] - (int)$prev['read_sectors']) * 512);
        $write_bytes = max(0, ((int)$disk_io_now['write_sectors'] - (int)$prev['write_sectors']) * 512);
        $read_ops = max(0, (int)$disk_io_now['reads'] - (int)$prev['reads']);
        $write_ops = max(0, (int)$disk_io_now['writes'] - (int)$prev['writes']);
        $io_ms = max(0, (int)$disk_io_now['io_ms'] - (int)$prev['io_ms']);
        $disk_io_read_rate = _system_bytes($read_bytes / $age) . '/s';
        $disk_io_write_rate = _system_bytes($write_bytes / $age) . '/s';
        $disk_io_util = number_format(min(999.9, ($io_ms / ($age * 1000)) * 100.0), 1) . ' %';
        $disk_io_ops = _system_ops_rate(($read_ops + $write_ops) / $age);
      }
    }
  }
  @file_put_contents($state_file, json_encode($disk_io_now), LOCK_EX);
}
$disk_io_summary = array(
  'rw'   => $disk_io_read_rate . ' / ' . $disk_io_write_rate,
  'util' => $disk_io_util,
  'ops'  => $disk_io_ops,
);

// ---- Database status + archive prune settings -----------------------
$db_hot_tables = array('shares');
$db_archive_tables = array(
  'shares_archive', 'shares_archive_mm', 'shares_archive_mm1',
  'shares_archive_mm3', 'shares_archive_mm4', 'shares_archive_mm5',
);
$db_stats_tables = array('share_stats_recent');
$db_block_tables = array(
  'blocks', 'blocks_mm', 'blocks_mm1', 'blocks_mm3', 'blocks_mm4', 'blocks_mm5',
);
$db_payout_tables = array(
  'transactions_outbox', 'payouts', 'payouts_mm', 'payouts_mm1',
  'payouts_mm3', 'payouts_mm4', 'payouts_mm5',
);
$db_all_groups = array_merge(
  $db_hot_tables,
  $db_archive_tables,
  $db_stats_tables,
  $db_block_tables,
  $db_payout_tables
);
$db_meta = _system_db_table_meta(isset($mysqli) ? $mysqli : null, $db_all_groups);
$db_group_rows = array();
foreach (array(
  'Hot shares'       => $db_hot_tables,
  'Archived shares'  => $db_archive_tables,
  'Recent summaries' => $db_stats_tables,
  'Blocks'           => $db_block_tables,
  'Payout queues'    => $db_payout_tables,
) as $label => $tables) {
  $sum = _system_db_sum_meta($db_meta, $tables);
  $db_group_rows[] = array(
    'label' => $label,
    'rows'  => _system_db_row_estimate($sum['rows']),
    'size'  => _system_bytes($sum['bytes']),
  );
}
$db_total = _system_db_sum_meta($db_meta, $db_all_groups);
$db_archive_oldest = _system_db_archive_edge(isset($mysqli) ? $mysqli : null, $db_archive_tables, 'ASC');
$db_archive_newest = _system_db_archive_edge(isset($mysqli) ? $mysqli : null, $db_archive_tables, 'DESC');
$db_prune_enabled = trim((string)$setting->getValue('db_prune_enabled')) !== '0';
$db_prune_after_days = _system_setting_int_value('db_prune_after_days', 180, 1, 3650);
if (!$db_prune_enabled) $db_prune_after_days = 0;
$db_prune_keep_recent_shares = _system_setting_int_value('db_prune_keep_recent_shares', 1000000, 250000, 40000000);
$db_prune_last_run = _system_setting_int_value('db_prune_last_run', 0, 0, PHP_INT_MAX);
$db_prune_last_deleted = _system_setting_int_value('db_prune_last_deleted', 0, 0, PHP_INT_MAX);
$db_prune_last_status = (string)$setting->getValue('db_prune_last_status');
$sys_database = array(
  'tables'              => $db_group_rows,
  'total_size'          => _system_bytes($db_total['bytes']),
  'total_rows'          => _system_db_row_estimate($db_total['rows']),
  'archive_oldest'      => $db_archive_oldest !== '' ? _system_age_compact($db_archive_oldest) : '—',
  'archive_newest'      => $db_archive_newest !== '' ? _system_age_compact($db_archive_newest) : '—',
  'prune_enabled'       => $db_prune_after_days > 0 ? 1 : 0,
  'prune_after_days'    => $db_prune_after_days,
  'prune_choices'       => _system_db_prune_choices(),
  'keep_recent_shares'  => $db_prune_keep_recent_shares,
  'keep_recent_share_choices' => _system_db_keep_recent_share_choices(),
  'prune_last_run'      => $db_prune_last_run,
  'prune_last_run_age'  => $db_prune_last_run > 0
                            ? _system_age_compact(gmdate('Y-m-d H:i:s', $db_prune_last_run))
                            : 'never',
  'prune_last_deleted'  => $db_prune_last_deleted,
  'prune_last_status'   => $db_prune_last_status,
);

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
$daemon_cache_grace = 90;
$daemon_cache_now = time();
$daemon_cache = _system_daemon_status_cache_load();
$daemon_cache_dirty = false;
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
  $rpc_error = '';
  $blockchain_ok = false;
  $cached_entry = _system_daemon_status_cache_entry($daemon_cache, $sym, $daemon_cache_now, $daemon_cache_grace);
  if ($btc) {
    try {
      $info = $btc->getblockchaininfo();
      if (is_array($info)) {
        if (isset($info['blocks']))  $blocks  = (string)$info['blocks'];
        if (isset($info['headers'])) $headers = (string)$info['headers'];
        if (isset($info['chain']))   $chain   = (string)$info['chain'];
        $blockchain_ok = true;
      }
    } catch (Exception $e) {
      $rpc_error = $e->getMessage();
    }
    if ($blockchain_ok) {
      try {
        $netinfo = $btc->getnetworkinfo();
        if (is_array($netinfo) && isset($netinfo['subversion'])) {
          // Strip the leading/trailing slashes from "/Satoshi:0.15.21/".
          $version = trim((string)$netinfo['subversion'], "/ \t");
        }
      } catch (Exception $e) {
        if ($cached_entry && !empty($cached_entry['row']['version'])
            && $cached_entry['row']['version'] !== '—') {
          $version = (string)$cached_entry['row']['version'];
        }
      }
    }
  }

  if (!$blockchain_ok) {
    $cached_row = _system_daemon_status_cached_row($daemon_cache, $sym, $daemon_cache_now, $daemon_cache_grace, $rpc_error);
    if ($cached_row) {
      $daemon_rows[] = $cached_row;
      continue;
    }
  }

  $rule_status = $blockchain_ok
    ? bsx_daemon_rule_status($btc, array(), $netinfo, $info, $sym)
    : bsx_daemon_rule_status($btc, array(), $netinfo, $info, $sym, array());
  $row = array(
    'sym'          => $sym,
    'chain'        => $chain !== '' ? $chain : '?',
    'version'      => $version !== '' ? $version : '—',
    'blocks'       => $blocks !== '' ? $blocks : '—',
    'headers'      => $headers !== '' ? $headers : '—',
    'synced'       => ($blocks !== '' && $headers !== '' && $blocks === $headers),
    'stale'        => false,
    'stale_age'    => 0,
    'stale_detail' => '',
    'rules'        => $rule_status,
  );
  $daemon_rows[] = $row;

  if ($blockchain_ok) {
    $daemon_cache[strtoupper($sym)] = array(
      'ts' => $daemon_cache_now,
      'row' => $row,
    );
    $daemon_cache_dirty = true;
  }
}
if ($daemon_cache_dirty) {
  _system_daemon_status_cache_save($daemon_cache);
}

// ---- Wallets -------------------------------------------------------
// Per-coin spendable balance + DB-tracked locked + maturing unconfirmed.
// Distinct from Coin Daemons (chain state) and Payout Outbox (queue) —
// answers "do I have enough cash on hand to drain my payment queue?".
$wallet_slot_globals = array(
  'BLC'  => array('',    isset($bitcoin)     ? $bitcoin     : null, isset($transaction)     ? $transaction     : null, isset($block)     ? $block     : null),
  'PHO'  => array('mm',  isset($bitcoin_mm)  ? $bitcoin_mm  : null, isset($transaction_mm)  ? $transaction_mm  : null, isset($block_mm)  ? $block_mm  : null),
  'BBTC' => array('mm1', isset($bitcoin_mm1) ? $bitcoin_mm1 : null, isset($transaction_mm1) ? $transaction_mm1 : null, isset($block_mm1) ? $block_mm1 : null),
  'ELT'  => array('mm3', isset($bitcoin_mm3) ? $bitcoin_mm3 : null, isset($transaction_mm3) ? $transaction_mm3 : null, isset($block_mm3) ? $block_mm3 : null),
  'UMO'  => array('mm4', isset($bitcoin_mm4) ? $bitcoin_mm4 : null, isset($transaction_mm4) ? $transaction_mm4 : null, isset($block_mm4) ? $block_mm4 : null),
  'LIT'  => array('mm5', isset($bitcoin_mm5) ? $bitcoin_mm5 : null, isset($transaction_mm5) ? $transaction_mm5 : null, isset($block_mm5) ? $block_mm5 : null),
);
$wallet_panel_rows = array();
foreach ($wallet_slot_globals as $sym => $tuple) {
  list($slot, $btc, $txn, $blk) = $tuple;
  $wallet_confs_key = $slot === '' ? 'network_confirmations' : ('network_confirmations_' . $slot);
  $wallet_confs = empty($config[$wallet_confs_key]) ? 120 : (int)$config[$wallet_confs_key];
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
  array('label' => 'RX/TX rate',  'value' => $network_rx_rate . ' / ' . $network_tx_rate),
  array('label' => 'RX/TX total', 'value' => $network_rx_total . ' / ' . $network_tx_total, 'tooltip' => $network_totals_tip),
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
  array('label' => 'System CPU', 'value' => $cpu_pct !== '' ? $cpu_pct . ' %' : '—'),
  array('label' => 'Load 1m',  'value' => $cpu_load1  !== '' ? $cpu_load1  : '—'),
  array('label' => 'Load 5m',  'value' => $cpu_load5  !== '' ? $cpu_load5  : '—'),
  array('label' => 'Load 15m', 'value' => $cpu_load15 !== '' ? $cpu_load15 : '—'),
);
$cpu_cores_str = $cpu_ncpu > 0 ? (string)$cpu_ncpu : '—';

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
        'value' => _system_mb($swap_used) . ' / ' . _system_mb($swap_total),
      ),
    )
  : array();
$swap_available_str = $swap_configured ? _system_mb($swap_free) : '—';
// Surfaced separately in the Memory card header rather than in the
// per-row table — operators glance at it more than the absolute used,
// so it belongs as a top-right stat.
$memory_available_str = $mem_avail > 0 ? _system_mb($mem_avail) : '—';
$memory_io_read_rate = '—';
$memory_io_write_rate = '—';
$memory_swap_io_rate = '—';
$memory_io_ops = '—';
$memory_io_now = _system_vmstat_read();
if ($memory_io_now) {
  $uid = function_exists('posix_geteuid') ? (string)posix_geteuid() : (string)getmyuid();
  $state_file = sys_get_temp_dir() . '/blakestream-mpos-system-memory-io-' . $uid . '.json';
  if (is_readable($state_file)) {
    $prev = json_decode((string)@file_get_contents($state_file), true);
    if (is_array($prev) &&
        isset($prev['pgpgin'], $prev['pgpgout'], $prev['pswpin'], $prev['pswpout'], $prev['pgfault'], $prev['pgmajfault'], $prev['ts'])) {
      $age = $memory_io_now['ts'] - (float)$prev['ts'];
      if ($age >= 0.5 && $age < 300) {
        $page_size = 4096;
        $page_in_bytes = max(0, (int)$memory_io_now['pgpgin'] - (int)$prev['pgpgin']) * 1024;
        $page_out_bytes = max(0, (int)$memory_io_now['pgpgout'] - (int)$prev['pgpgout']) * 1024;
        $swap_pages = max(0, (int)$memory_io_now['pswpin'] - (int)$prev['pswpin'])
                    + max(0, (int)$memory_io_now['pswpout'] - (int)$prev['pswpout']);
        $faults = max(0, (int)$memory_io_now['pgfault'] - (int)$prev['pgfault'])
                + max(0, (int)$memory_io_now['pgmajfault'] - (int)$prev['pgmajfault']);
        $memory_io_read_rate = _system_bytes($page_in_bytes / $age) . '/s';
        $memory_io_write_rate = _system_bytes($page_out_bytes / $age) . '/s';
        $memory_swap_io_rate = _system_bytes(($swap_pages * $page_size) / $age) . '/s';
        $memory_io_ops = _system_ops_rate($faults / $age);
      }
    }
  }
  @file_put_contents($state_file, json_encode($memory_io_now), LOCK_EX);
}
$memory_io_summary = array(
  'rw'   => $memory_io_read_rate . ' / ' . $memory_io_write_rate,
  'util' => $memory_swap_io_rate,
  'ops'  => $memory_io_ops,
);

// ---- Process RSS ---------------------------------------------------
$processes = array(
  'go-eliopool'=> "pgrep -af 'eliopool-25\\.2-go' | head -1 | awk '{cmd=\"ps -o rss= -p \"\$1; cmd | getline rss; print \$1\"|\"rss}'",
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
$daemon_proc_rows = _system_daemon_process_proc_rows();
if (!$daemon_proc_rows) $daemon_proc_rows = _system_daemon_container_proc_rows();
foreach ($daemon_proc_rows as $row) {
  $proc_rows[] = $row;
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
$tx_link_min_confirmations = 2;
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
      if ($status === 'pending') {
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
      if (in_array($row['status'], array('pending', 'broadcast'), true)) {
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
        'txurl'  => $tx_confirmations >= $tx_link_min_confirmations
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
// visible immediately. Once an open outbox row exists for the same
// account/slot, the outbox is authoritative; showing both rows makes one
// payout look like two. Failed/abandoned/review rows are not active payout
// requests and must not hide the legacy queue row.
$manual_payout_tables = array(
  ''    => array('payouts',     'transactions',     'blocks'),
  'mm'  => array('payouts_mm',  'transactions_mm',  'blocks_mm'),
  'mm1' => array('payouts_mm1', 'transactions_mm1', 'blocks_mm1'),
  'mm3' => array('payouts_mm3', 'transactions_mm3', 'blocks_mm3'),
  'mm4' => array('payouts_mm4', 'transactions_mm4', 'blocks_mm4'),
  'mm5' => array('payouts_mm5', 'transactions_mm5', 'blocks_mm5'),
);
$_manual_confirmations = isset($config['confirmations']) ? max(0, (int)$config['confirmations']) : 0;
foreach ($manual_payout_tables as $_slot => $_tables) {
  list($_table, $_tx_table, $_block_table) = $_tables;
  if (!preg_match('/^payouts(_mm[1345]?)?$/', $_table)) continue;
  if (!preg_match('/^transactions(_mm[1345]?)?$/', $_tx_table)) continue;
  if (!preg_match('/^blocks(_mm[1345]?)?$/', $_block_table)) continue;
  $_threshold_col = $_slot === '' ? 'ap_threshold' : 'ap_threshold_' . $_slot;
  if (!preg_match('/^ap_threshold(_mm[1345]?)?$/', $_threshold_col)) continue;
  $_threshold_key = $_threshold_col;
  $_configured_cap = 0.0;
  if (isset($config[$_threshold_key]) && is_array($config[$_threshold_key]) && isset($config[$_threshold_key]['max'])) {
    $_configured_cap = round((float)$config[$_threshold_key]['max'], 8);
  }
  $_configured_cap_sql = number_format($_configured_cap, 8, '.', '');
  $_slot_sql = isset($mysqli) ? $mysqli->real_escape_string($_slot) : $_slot;
  $_confirmed_expr =
    "IFNULL(ROUND(("
    . "SUM(IF(((t.type IN ('Credit','Bonus') AND b.confirmations >= " . $_manual_confirmations . ") OR t.type = 'Credit_PPS'), t.amount, 0)) "
    . "- SUM(IF(t.type IN ('Debit_MP','Debit_AP'), t.amount, 0)) "
    . "- SUM(IF(((t.type IN ('Donation','Fee') AND b.confirmations >= " . $_manual_confirmations . ") OR t.type IN ('Donation_PPS','Fee_PPS','TXFee')), t.amount, 0))"
    . "), 8), 0)";
  $sql = "SELECT COUNT(*) AS cnt, COUNT(DISTINCT q.account_id) AS user_count, "
       . "GROUP_CONCAT(DISTINCT q.username ORDER BY q.username SEPARATOR ', ') AS users, "
       . "SUM(LEAST(q.net_amount, CASE "
       . "  WHEN q.threshold > 0 AND (" . $_configured_cap_sql . " <= 0 OR q.threshold < " . $_configured_cap_sql . ") THEN q.threshold "
       . "  WHEN " . $_configured_cap_sql . " > 0 THEN " . $_configured_cap_sql . " "
       . "  ELSE q.net_amount END)) AS total_amount, "
       . "MIN(q.time) AS oldest, MAX(q.time) AS latest "
       . "FROM ("
       . "SELECT p.id, p.account_id, a.username, p.time, "
       . "a." . $_threshold_col . " AS threshold, "
       . "GREATEST(ROUND((" . $_confirmed_expr . "), 8), 0) AS net_amount "
       . "FROM " . $_table . " AS p "
       . "LEFT JOIN " . $accounts_table . " AS a ON a.id = p.account_id "
       . "LEFT JOIN " . $_tx_table . " AS t ON t.account_id = p.account_id AND t.archived = 0 "
       . "LEFT JOIN " . $_block_table . " AS b ON b.id = t.block_id "
       . "WHERE p.completed = 0 "
       . "AND NOT EXISTS ("
       . "  SELECT 1 FROM transactions_outbox AS o "
       . "  WHERE o.slot = '" . $_slot_sql . "' "
       . "    AND o.account_id = p.account_id "
       . "    AND o.status IN ('pending','broadcast')"
       . ") "
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

$system_status_payload = array(
  'ts'               => time(),
  'cache'            => array(
    'hit' => false,
    'state' => 'fresh',
    'age' => 0,
    'ttl' => $system_status_cache_fresh_ttl,
    'stale_ttl' => $system_status_cache_stale_ttl,
    'message' => 'System status refreshed',
  ),
  'users'            => $users_info,
  'logins'           => $logins_info,
  'invitations'      => $invitations_info,
  'versions'         => $mpos_versions,
  'health'           => $system_health,
  'services'         => $service_rows,
  'backup'           => $sys_backup,
  'database'         => $sys_database,
  'cpu'              => $cpu_rows,
  'cpu_cores'        => $cpu_cores_str,
  'swap'             => $swap_rows,
  'swap_available'   => $swap_available_str,
  'swap_configured'  => $swap_configured,
  'memory'           => $memory_rows,
  'memory_available' => $memory_available_str,
  'memory_io_summary' => $memory_io_summary,
  'disk'             => $disk_rows,
  'disk_available'   => $disk_available_str,
  'disk_io_summary'  => $disk_io_summary,
  'network'          => $network_rows,
  'network_miners'   => $network_miners_str,
  'network_iface'    => $network_iface,
  'daemons'          => $daemon_rows,
  'wallets'          => $wallet_panel_rows,
  'procs'            => $proc_rows,
  'outbox'           => $outbox_rows,
  'outbox_open'      => $outbox_open_count,
  'outbox_counts'    => $outbox_counts,
);

_system_status_cache_set(
  $system_status_cache_key,
  array('ts' => time(), 'payload' => $system_status_payload),
  $system_status_cache_stale_ttl + $system_status_cache_fresh_ttl
);
_system_status_cache_set(
  $system_status_cache_last_good_key,
  array('ts' => time(), 'payload' => $system_status_payload),
  $system_status_cache_last_good_ttl
);
  if (isset($lock_fp) && is_resource($lock_fp)) {
    @flock($lock_fp, LOCK_UN);
    @fclose($lock_fp);
  }
  _system_status_respond_payload($system_status_payload);
}

if (!$system_status_collector_mode) {
  $system_status_payload = _system_status_apply_live_backup_settings($system_status_payload);
}

$users_info           = $system_status_payload['users'];
$logins_info          = $system_status_payload['logins'];
$invitations_info     = $system_status_payload['invitations'];
$mpos_versions        = $system_status_payload['versions'];
$system_health        = isset($system_status_payload['health']) && is_array($system_status_payload['health'])
                          ? $system_status_payload['health']
                          : array();
$service_rows         = $system_status_payload['services'];
$sys_backup           = $system_status_payload['backup'];
$sys_database         = isset($system_status_payload['database'])
                          ? $system_status_payload['database']
                          : _system_status_empty_payload()['database'];
$cpu_rows             = $system_status_payload['cpu'];
$cpu_cores_str        = isset($system_status_payload['cpu_cores'])
                          ? (string)$system_status_payload['cpu_cores']
                          : '—';
if ($cpu_cores_str === '—' && is_array($cpu_rows)) {
  foreach ($cpu_rows as $idx => $row) {
    if (isset($row['label']) && strcasecmp((string)$row['label'], 'Cores') === 0) {
      $cpu_cores_str = isset($row['value']) ? (string)$row['value'] : '—';
      unset($cpu_rows[$idx]);
    }
  }
  $cpu_rows = array_values($cpu_rows);
}
$swap_rows            = $system_status_payload['swap'];
$swap_available_str   = $system_status_payload['swap_available'];
$swap_configured      = $system_status_payload['swap_configured'];
$memory_rows          = $system_status_payload['memory'];
$memory_available_str = $system_status_payload['memory_available'];
$memory_io_summary    = isset($system_status_payload['memory_io_summary'])
                          ? $system_status_payload['memory_io_summary']
                          : _system_status_empty_payload()['memory_io_summary'];
$disk_rows            = $system_status_payload['disk'];
$disk_available_str   = $system_status_payload['disk_available'];
$disk_io_summary      = isset($system_status_payload['disk_io_summary'])
                          ? $system_status_payload['disk_io_summary']
                          : _system_status_empty_payload()['disk_io_summary'];
$network_rows         = $system_status_payload['network'];
$network_miners_str   = $system_status_payload['network_miners'];
$network_iface        = $system_status_payload['network_iface'];
$daemon_rows          = $system_status_payload['daemons'];
$wallet_panel_rows    = $system_status_payload['wallets'];
$proc_rows            = $system_status_payload['procs'];
$outbox_rows          = $system_status_payload['outbox'];
$outbox_open_count    = $system_status_payload['outbox_open'];
$outbox_counts        = $system_status_payload['outbox_counts'];

// ---- _partial=1: JSON for the live-poll endpoint -------------------
if (!empty($_GET['_partial'])) {
  $system_status_payload['csrf_token'] = (string)$smarty->getTemplateVars('CTOKEN');
  _system_status_respond_payload($system_status_payload);
}

$smarty->assign('SYS_USERS',       $users_info);
$smarty->assign('SYS_LOGINS',      $logins_info);
$smarty->assign('SYS_INVITATIONS', $invitations_info);
$smarty->assign('SYS_VERSIONS',    $mpos_versions);
$smarty->assign('SYS_HEALTH',      $system_health);
$smarty->assign('SYS_SERVICES', $service_rows);
$smarty->assign('SYS_BACKUP',   $sys_backup);
$smarty->assign('SYS_DATABASE', $sys_database);
$smarty->assign('SYS_CPU',      $cpu_rows);
$smarty->assign('SYS_CPU_CORES', $cpu_cores_str);
$smarty->assign('SYS_SWAP',         $swap_rows);
$smarty->assign('SYS_SWAP_AVAIL',   $swap_available_str);
$smarty->assign('SYS_SWAP_OK',      $swap_configured);
$smarty->assign('SYS_MEMORY',       $memory_rows);
$smarty->assign('SYS_MEM_AVAIL',    $memory_available_str);
$smarty->assign('SYS_MEMORY_IO_SUMMARY', $memory_io_summary);
$smarty->assign('SYS_DISK',     $disk_rows);
$smarty->assign('SYS_DISK_AVAIL', $disk_available_str);
$smarty->assign('SYS_DISK_IO_SUMMARY', $disk_io_summary);
$smarty->assign('SYS_NETWORK',         $network_rows);
$smarty->assign('SYS_NET_MINERS',      $network_miners_str);
$smarty->assign('SYS_NET_IFACE',       $network_iface);
$smarty->assign('SYS_DAEMONS',  $daemon_rows);
$smarty->assign('SYS_WALLETS',  $wallet_panel_rows);
$smarty->assign('SYS_PROCS',    $proc_rows);
$smarty->assign('SYS_OUTBOX',   $outbox_rows);
$smarty->assign('SYS_OUTBOX_OPEN', $outbox_open_count);
$smarty->assign('SYS_OUTBOX_COUNTS', $outbox_counts);
$smarty->assign('SYS_STATUS_CACHE', $system_status_payload['cache']);

$smarty->assign('CONTENT', 'default.tpl');
?>
