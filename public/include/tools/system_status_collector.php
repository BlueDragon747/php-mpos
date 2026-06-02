#!/usr/bin/env php
<?php
define('SECURITY', '*)WT#&YHfd');
define('SECHASH_CHECK', false);
function cfip() { return defined('SECURITY') ? 1 : 0; }

define('BSX_SYSTEM_STATUS_COLLECTOR', true);
define('BASEPATH', dirname(__DIR__, 2) . '/');

$_SERVER['REMOTE_ADDR'] = '127.0.0.1';
$_SERVER['REQUEST_METHOD'] = 'GET';
$_SERVER['SERVER_NAME'] = 'localhost';
$_SERVER['SERVER_PORT'] = '80';
$_SERVER['SCRIPT_NAME'] = '/index.php';
$_REQUEST['page'] = 'admin';
$_REQUEST['action'] = 'system';
$_GET = array();
$_POST = array();

$interval = 10;
$loop = in_array('--loop', $argv, true);
$quiet = in_array('--quiet', $argv, true);
if ($quiet) define('BSX_SYSTEM_STATUS_QUIET', true);
foreach ($argv as $i => $arg) {
  if ($arg === '--interval' && isset($argv[$i + 1]) && is_numeric($argv[$i + 1])) {
    $interval = max(1, (int)$argv[$i + 1]);
  }
}

if ($loop) {
  while (true) {
    $started = time();
    $cmd = escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg(__FILE__) . ' --once --quiet';
    passthru($cmd);
    $elapsed = time() - $started;
    sleep(max(1, $interval - $elapsed));
  }
}

ob_start();
try {
  include BASEPATH . 'include/bootstrap.php';
  require_once BASEPATH . 'include/version.inc.php';
  require BASEPATH . 'include/pages/admin/system.inc.php';
  $out = trim(ob_get_clean());
  if (!$quiet && $out !== '') {
    fwrite(STDOUT, $out . PHP_EOL);
  }
  exit(0);
} catch (Throwable $e) {
  while (ob_get_level() > 0) ob_end_clean();
  fwrite(STDERR, 'system status collector failed: ' . $e->getMessage() . PHP_EOL);
  exit(1);
}
