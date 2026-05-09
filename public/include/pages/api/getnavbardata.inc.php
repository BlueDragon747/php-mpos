<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

// Check if the system is enabled
if ($setting->getValue('disable_navbar_api')) {
  echo $api->get_json(array('error' => 'disabled'));
  die();
}

// System load check
if ($load = @sys_getloadavg()) {
  if (isset($config['system']['load']['max']) && $load[0] > $config['system']['load']['max']) {
    header('HTTP/1.1 503 Too busy, try again later');
    die('Server too busy. Please try again later.');
  }
}

// Fetch RPC information
if ($bitcoin->can_connect() === true) {
  $dNetworkHashrate = $bitcoin->getnetworkhashps();
  $dDifficulty = $bitcoin->getdifficulty();
  $iBlock = $bitcoin->getblockcount();
} else {
  $dNetworkHashrate = 0;
  $dDifficulty = 1;
  $iBlock = 0;
}

// Some settings
if ( ! $interval = $setting->getValue('statistics_ajax_data_interval')) $interval = 300;

// Fetch cached data maintained by cronjobs-py.
$dPoolHashrate = $statistics->getCurrentHashrate($interval);
if ($dPoolHashrate > $dNetworkHashrate) $dNetworkHashrate = $dPoolHashrate;

// Pool/network hashrate modifiers: prefer the operator-pinned setting
// when present, otherwise auto-pick to match smarty_globals.inc.php so
// the AJAX-refresh value the navbar gauge gets back stays in the same
// unit the page rendered the gauge label with. Inline the auto-pick
// rather than including smarty_globals.inc.php — that file has heavy
// DB side effects and is intentionally skipped for API pages.
$_navbar_auto_modifier = function($dKHs) {
  if ($dKHs >= 1e9) return 0.000000001;
  if ($dKHs >= 1e6) return 0.000001;
  if ($dKHs >= 1e3) return 0.001;
  return 1;
};
$dPoolPinApi    = $setting->getValue('statistics_pool_hashrate_modifier');
$dNetworkPinApi = $setting->getValue('statistics_network_hashrate_modifier');
$dPoolHashrateModifier    = $dPoolPinApi    ? (float)$dPoolPinApi    : $_navbar_auto_modifier($dPoolHashrate);
$dNetworkHashrateModifier = $dNetworkPinApi ? (float)$dNetworkPinApi : $_navbar_auto_modifier($dNetworkHashrate / 1000);

// Apply pool modifiers
$dPoolHashrateAdjusted = $dPoolHashrate * $dPoolHashrateModifier;
$dNetworkHashrateAdjusted = $dNetworkHashrate / 1000 * $dNetworkHashrateModifier;

// Use caches for this one
$aRoundShares = $statistics->getRoundShares();

$iTotalRoundShares = $aRoundShares['valid'] + $aRoundShares['invalid'];
if ($iTotalRoundShares > 0) {
  $dPoolInvalidPercent = round($aRoundShares['invalid'] / $iTotalRoundShares * 100, 2);
} else {
  $dUserInvalidPercent = 0;
  $dPoolInvalidPercent = 0;
}

// Round progress
$iEstShares = $statistics->getEstimatedShares($dDifficulty);
if ($iEstShares > 0 && $aRoundShares['valid'] > 0) {
    $dEstPercent = round(100 / $iEstShares * $aRoundShares['valid'], 2);
} else {
    $dEstPercent = 0;
}

// Output JSON format
$data = array(
  'raw' => array( 'workers' => $worker->getCountAllActiveWorkers(), 'pool' => array( 'hashrate' => $dPoolHashrate ) ),
  'pool' => array( 'workers' => $worker->getCountAllActiveWorkers(), 'hashrate' => $dPoolHashrateAdjusted, 'estimated' => $iEstShares, 'progress' => $dEstPercent ),
  'network' => array( 'hashrate' => $dNetworkHashrateAdjusted, 'difficulty' => $dDifficulty, 'block' => $iBlock ),
);
echo $api->get_json($data);

// Supress master template
$supress_master = 1;
?>
