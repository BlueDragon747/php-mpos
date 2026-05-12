<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

// Globally available variables
$debug->append('Global smarty variables', 3);

$debug->append('No cached page detected, loading smarty globals', 3);
// Defaults to get rid of PHP Notice warnings
$dDifficulty = 1;

// Fetch round shares
if (!$aRoundShares = $statistics->getRoundShares()) {
  $aRoundShares = array('valid' => 0, 'invalid' => 0);
}

if (!$aRoundShares_mm = $statistics_mm->getRoundShares()) {
  $aRoundShares_mm = array('valid' => 0, 'invalid' => 0);
}
if (!$aRoundShares_mm1 = $statistics_mm1->getRoundShares()) {
  $aRoundShares_mm1 = array('valid' => 0, 'invalid' => 0);
}


if (!$aRoundShares_mm3 = $statistics_mm3->getRoundShares()) {
  $aRoundShares_mm3 = array('valid' => 0, 'invalid' => 0);
}
if (!$aRoundShares_mm4 = $statistics_mm4->getRoundShares()) {
  $aRoundShares_mm4 = array('valid' => 0, 'invalid' => 0);
}
if (!$aRoundShares_mm5 = $statistics_mm5->getRoundShares()) {
  $aRoundShares_mm5 = array('valid' => 0, 'invalid' => 0);
}


if ($bitcoin->can_connect() === true) {
  $dDifficulty = $bitcoin->getdifficulty();
  $dNetworkHashrate = $bitcoin->getnetworkhashps();
} else {
  $dDifficulty = 1;
  $dNetworkHashrate = 0;
}

// Baseline pool hashrate for templates
$iCurrentPoolHashrate =  $statistics->getCurrentHashrate();

// Avoid confusion, ensure our nethash isn't higher than poolhash
if ($iCurrentPoolHashrate > $dNetworkHashrate / 1000) $dNetworkHashrate = $iCurrentPoolHashrate;

// Network hashrate is in raw H/s from getnetworkhashps; pool hashrate
// is already in KH/s from statistics::getCurrentHashrate. Normalise
// network to KH/s so the auto-scale logic below sees the same units.
$dNetworkHashrate = $dNetworkHashrate / 1000;

// Hashrate auto-scale (Blakestream-MPOS addition).
//
// Upstream MPOS made the operator pin a per-display modifier in the
// `settings` table (1 → KH/s, 0.001 → MH/s, 1e-6 → GH/s, 1e-9 → TH/s).
// That meant a small testnet pool always rendered as `0.001 GH/s` and
// a big mainnet pool always rendered as `763984227.67 KH/s` — the
// operator had to keep retuning. Auto-scale picks the most readable
// magnitude based on the actual raw KH/s value. Operators who really
// want a fixed display can still pin the corresponding settings row;
// any pinned value (modifier matching one of the scale keys) is
// respected via the manual override branch below.
function _hashrate_auto_modifier($dKHs) {
  if ($dKHs >= 1e9) return 0.000000001; // TH/s
  if ($dKHs >= 1e6) return 0.000001;    // GH/s
  if ($dKHs >= 1e3) return 0.001;       // MH/s
  return 1;                              // KH/s
}

// Pick the correct label for a given modifier. Doing this with a
// function instead of an array lookup avoids PHP's float-to-string
// conversion booby-trap: PHP stringifies `0.000001` as `"1.0E-6"`
// when used as an array key, so `$aHashunits[$dNetworkHashrateModifier]`
// silently returns null for GH/s and TH/s.
function _hashrate_unit_for($mod) {
  // Compare with epsilon-tolerant equality so float arithmetic
  // upstream doesn't throw the lookup off.
  if (abs($mod - 1)               < 1e-12)  return 'KH/s';
  if (abs($mod - 0.001)           < 1e-15)  return 'MH/s';
  if (abs($mod - 0.000001)        < 1e-18)  return 'GH/s';
  if (abs($mod - 0.000000001)     < 1e-21)  return 'TH/s';
  // Fallback for any operator-pinned modifier that doesn't match
  // one of the canonical scales — render the modifier itself so
  // the label at least conveys something rather than being blank.
  return 'KH/s × ' . $mod;
}

$dPoolPin     = $setting->getValue('statistics_pool_hashrate_modifier');
$dPersonalPin = $setting->getValue('statistics_personal_hashrate_modifier');
$dNetworkPin  = $setting->getValue('statistics_network_hashrate_modifier');

$dPoolHashrateModifier     = $dPoolPin     ? (float)$dPoolPin     : _hashrate_auto_modifier($iCurrentPoolHashrate);
$dNetworkHashrateModifier  = $dNetworkPin  ? (float)$dNetworkPin  : _hashrate_auto_modifier($dNetworkHashrate);
// Personal modifier is set later from the user's own raw hashrate
// (see the userdata block further down) — initialise to a safe
// default that the rest of this scope can read.
if ( ! $dPersonalHashrateModifier = $dPersonalPin ? (float)$dPersonalPin : null )
  $dPersonalHashrateModifier = 1;

// Apply modifier now
$dNetworkHashrate = $dNetworkHashrate * $dNetworkHashrateModifier;
$iCurrentPoolHashrate = $iCurrentPoolHashrate * $dPoolHashrateModifier;

// Share rate of the entire pool
$iCurrentPoolShareRate = $statistics->getCurrentShareRate();

// Active workers
if (!$iCurrentActiveWorkers = $worker->getCountAllActiveWorkers()) $iCurrentActiveWorkers = 0;

// Some settings to propagate to template
if (! $statistics_ajax_refresh_interval = $setting->getValue('statistics_ajax_refresh_interval')) $statistics_ajax_refresh_interval = 10;
if (! $statistics_ajax_long_refresh_interval = $setting->getValue('statistics_ajax_long_refresh_interval')) $statistics_ajax_long_refresh_interval = 10;

// Small helper array — kept for any external code that still indexes
// it directly. NEW code should use _hashrate_unit_for() because PHP
// converts float keys like `0.000001` to `"1.0E-6"` on lookup,
// missing the decimal-string keys here.
$aHashunits = array( '1' => 'KH/s', '0.001' => 'MH/s', '0.000001' => 'GH/s', '0.000000001' => 'TH/s' );

// Global data for Smarty
$aGlobal = array(
  'hashunits' => array(
    'pool'     => _hashrate_unit_for($dPoolHashrateModifier),
    'network'  => _hashrate_unit_for($dNetworkHashrateModifier),
    'personal' => _hashrate_unit_for($dPersonalHashrateModifier),
  ),
  // Numeric modifiers exposed to JavaScript so the SSE live-update
  // path (sse-live.js handleStats) can scale raw kH/s into the same
  // display units the page was rendered with.
  'hashmods_all' => array(
    'pool'     => $dPoolHashrateModifier,
    'network'  => $dNetworkHashrateModifier,
    'personal' => $dPersonalHashrateModifier,
  ),
  'hashmods' => array( 'personal' => $dPersonalHashrateModifier ),
  'hashrate' => $iCurrentPoolHashrate,
  // Raw KH/s before any modifier — the navbar JS scales this on
  // every AJAX tick so the gauge label tracks unit changes (e.g.
  // KH/s → GH/s as miners come online) instead of being baked in
  // at page-render time.
  'rawhashrate' => $iCurrentPoolHashrate / max($dPoolHashrateModifier, 1e-30),
  'nethashrate' => $dNetworkHashrate,
  'sharerate' => $iCurrentPoolShareRate,
  'workers' => $iCurrentActiveWorkers,
  'roundshares' => $aRoundShares,
  'roundshares_mm' => $aRoundShares_mm,
  'roundshares_mm1' => $aRoundShares_mm1,

  'roundshares_mm3' => $aRoundShares_mm3,
  'roundshares_mm4' => $aRoundShares_mm4,
  'roundshares_mm5' => $aRoundShares_mm5,

  'fees' => $config['fees'],
  'fees_mm' => $config['fees_mm'],
  'fees_mm1' => $config['fees_mm1'],

  'fees_mm3' => $config['fees_mm3'],
  'fees_mm4' => $config['fees_mm4'],
  'fees_mm5' => $config['fees_mm5'],

  'confirmations' => $config['confirmations'],
  'confirmations_mm' => $config['confirmations_mm'],
  'confirmations_mm1' => $config['confirmations_mm1'],

  'confirmations_mm3' => $config['confirmations_mm3'],
  'confirmations_mm4' => $config['confirmations_mm4'],
  'confirmations_mm5' => $config['confirmations_mm5'],

  'reward' => $config['reward_type'] == 'fixed' ? $config['reward'] : $block->getAverageAmount(),
  'price' => $setting->getValue('price'),
  'twofactor' => $config['twofactor'],
  'csrf' => $config['csrf'],
  'config' => array(
    'recaptcha_enabled' => $setting->getValue('recaptcha_enabled'),
    'recaptcha_enabled_logins' => $setting->getValue('recaptcha_enabled_logins'),
    'disable_navbar' => $setting->getValue('disable_navbar'),
    'disable_navbar_api' => $setting->getValue('disable_navbar_api'),
    'disable_payouts' => $setting->getValue('disable_payouts'),
    'disable_manual_payouts' => $setting->getValue('disable_manual_payouts'),
    'disable_auto_payouts' => $setting->getValue('disable_auto_payouts'),
    'disable_contactform' => $setting->getValue('disable_contactform'),
    'disable_contactform_guest' => $setting->getValue('disable_contactform_guest'),
    'algorithm' => $config['algorithm'],
    'target_bits' => $config['target_bits'],
    'accounts' => $config['accounts'],
    'disable_invitations' => $setting->getValue('disable_invitations'),
    'disable_notifications' => $setting->getValue('disable_notifications'),
    'monitoring_uptimerobot_api_keys' => $setting->getValue('monitoring_uptimerobot_api_keys'),
    'statistics_ajax_refresh_interval' => $statistics_ajax_refresh_interval,
    'statistics_ajax_long_refresh_interval' => $statistics_ajax_long_refresh_interval,
    'price' => array( 'currency' => $config['price']['currency'] ),
    'targetdiff' => $config['difficulty'],
    'currency' => $config['currency'],
    'currency_mm' => $config['currency_mm'],
    'currency_mm1' => $config['currency_mm1'],

    'currency_mm3' => $config['currency_mm3'],
    'currency_mm4' => $config['currency_mm4'],
    'currency_mm5' => $config['currency_mm5'],

    'txfee_manual' => $config['txfee_manual'],
    'txfee_auto' => $config['txfee_auto'],
    'payout_system' => $config['payout_system'],
    'payout_system_mm' => $config['payout_system_mm'],
    'payout_system_mm1' => $config['payout_system_mm1'],

    'payout_system_mm3' => $config['payout_system_mm3'],
    'payout_system_mm4' => $config['payout_system_mm4'],
    'payout_system_mm5' => $config['payout_system_mm5'],

    'ap_threshold' => array(
      'min' => $config['ap_threshold']['min'],
      'max' => $config['ap_threshold']['max']
    ), 
    'ap_threshold_mm' => array(
      'min' => $config['ap_threshold_mm']['min'],
      'max' => $config['ap_threshold_mm']['max']
    ),
    'ap_threshold_mm1' => array(
      'min' => $config['ap_threshold_mm1']['min'],
      'max' => $config['ap_threshold_mm1']['max']
    ),
    'ap_threshold_mm3' => array(
      'min' => $config['ap_threshold_mm3']['min'],
      'max' => $config['ap_threshold_mm3']['max']
    ),
    'ap_threshold_mm4' => array(
      'min' => $config['ap_threshold_mm4']['min'],
      'max' => $config['ap_threshold_mm4']['max']
    ),
    'ap_threshold_mm5' => array(
      'min' => $config['ap_threshold_mm5']['min'],
      'max' => $config['ap_threshold_mm5']['max']
    )
  )
);

// Website configurations
$aGlobal['website']['name'] = $setting->getValue('website_name');
$aGlobal['website']['title'] = $setting->getValue('website_title');
$aGlobal['website']['slogan'] = $setting->getValue('website_slogan');
$aGlobal['website']['email'] = $setting->getValue('website_email');
$aGlobal['website']['api']['disabled'] = $setting->getValue('disable_api');
$aGlobal['website']['blockexplorer']['disabled'] = $setting->getValue('website_blockexplorer_disabled');
$aGlobal['website']['transactionexplorer']['disabled'] = $setting->getValue('website_transactionexplorer_disabled');
$aGlobal['website']['chaininfo']['disabled'] = $setting->getValue('website_chaininfo_disabled');
$aGlobal['website']['donors']['disabled'] = $setting->getValue('disable_donors');
$aGlobal['website']['about']['disabled'] = $setting->getValue('disable_about');
$setting->getValue('website_blockexplorer_url') ? $aGlobal['website']['blockexplorer']['url'] = $setting->getValue('website_blockexplorer_url') : $aGlobal['website']['blockexplorer']['url'] = 'http://explorer.litecoin.net/block/';
$setting->getValue('website_transactionexplorer_url') ? $aGlobal['website']['transactionexplorer']['url'] = $setting->getValue('website_transactionexplorer_url') : $aGlobal['website']['transactionexplorer']['url'] = 'http://explorer.litecoin.net/tx/';
$setting->getValue('website_chaininfo_url') ? $aGlobal['website']['chaininfo']['url'] = $setting->getValue('website_chaininfo_url') : $aGlobal['website']['chaininfo']['url'] = 'http://allchains.info';

// Google Analytics
$aGlobal['statistics']['analytics']['enabled'] = $setting->getValue('statistics_analytics_enabled');
$aGlobal['statistics']['analytics']['code'] = $setting->getValue('statistics_analytics_code');

// ACLs
$aGlobal['acl']['pool']['statistics'] = $setting->getValue('acl_pool_statistics');
$aGlobal['acl']['block']['statistics'] = $setting->getValue('acl_block_statistics');
$aGlobal['acl']['round']['statistics'] = $setting->getValue('acl_round_statistics');
$aGlobal['acl']['blockfinder']['statistics'] = $setting->getValue('acl_blockfinder_statistics');
$aGlobal['acl']['uptime']['statistics'] = $setting->getValue('acl_uptime_statistics');

// We don't want these session infos cached
if (@$_SESSION['USERDATA']['id']) {
  $aGlobal['userdata'] = $_SESSION['USERDATA']['id'] ? $user->getUserData($_SESSION['USERDATA']['id']) : array();
  $aGlobal['userdata']['balance'] = $transaction->getBalance($_SESSION['USERDATA']['id']);
  $aGlobal['userdata']['balance_mm'] = $transaction_mm->getBalance($_SESSION['USERDATA']['id']);
  $aGlobal['userdata']['balance_mm1'] = $transaction_mm1->getBalance($_SESSION['USERDATA']['id']);

  $aGlobal['userdata']['balance_mm3'] = $transaction_mm3->getBalance($_SESSION['USERDATA']['id']);
  $aGlobal['userdata']['balance_mm4'] = $transaction_mm4->getBalance($_SESSION['USERDATA']['id']);
  $aGlobal['userdata']['balance_mm5'] = $transaction_mm5->getBalance($_SESSION['USERDATA']['id']);


  // Other userdata that we can cache savely
  $aGlobal['userdata']['shares'] = $statistics->getUserShares($_SESSION['USERDATA']['username'], $_SESSION['USERDATA']['id']);
  $aGlobal['userdata']['shares_mm'] = $statistics_mm->getUserShares_mm($_SESSION['USERDATA']['username'], $_SESSION['USERDATA']['id']);
  $aGlobal['userdata']['shares_mm1'] = $statistics_mm1->getUserShares_mm1($_SESSION['USERDATA']['username'], $_SESSION['USERDATA']['id']);

  $aGlobal['userdata']['shares_mm3'] = $statistics_mm3->getUserShares_mm3($_SESSION['USERDATA']['username'], $_SESSION['USERDATA']['id']);
  $aGlobal['userdata']['shares_mm4'] = $statistics_mm4->getUserShares_mm4($_SESSION['USERDATA']['username'], $_SESSION['USERDATA']['id']);
  $aGlobal['userdata']['shares_mm5'] = $statistics_mm5->getUserShares_mm5($_SESSION['USERDATA']['username'], $_SESSION['USERDATA']['id']);

  $aGlobal['userdata']['rawhashrate'] = $statistics->getUserHashrate($_SESSION['USERDATA']['username'], $_SESSION['USERDATA']['id']);
  // Auto-scale the personal hashrate magnitude unless the operator
  // pinned a modifier in settings. Mirrors the pool/network logic above.
  if ( ! $dPersonalPin ) {
    $dPersonalHashrateModifier = _hashrate_auto_modifier((float)$aGlobal['userdata']['rawhashrate']);
    $aGlobal['hashunits']['personal'] = _hashrate_unit_for($dPersonalHashrateModifier);
    $aGlobal['hashmods']['personal']  = $dPersonalHashrateModifier;
  }
  $aGlobal['userdata']['hashrate'] = $aGlobal['userdata']['rawhashrate'] * $dPersonalHashrateModifier;
  $aGlobal['userdata']['sharerate'] = $statistics->getUserSharerate($_SESSION['USERDATA']['username'], $_SESSION['USERDATA']['id']);

  switch ($config['payout_system']) {
  case 'prop':
    // Some estimations
    $aEstimates = $statistics->getUserEstimates($aRoundShares, $aGlobal['userdata']['shares'], $aGlobal['userdata']['donate_percent'], $aGlobal['userdata']['no_fees']);
    $aGlobal['userdata']['estimates'] = $aEstimates;
    break;
  case 'pplns':
    $aGlobal['pplns']['target'] = $config['pplns']['shares']['default'];
    if ($aLastBlock = $block->getLast()) {
      if ($iAvgBlockShares = round($block->getAvgBlockShares($aLastBlock['height'], $config['pplns']['blockavg']['blockcount']))) {
        $aGlobal['pplns']['target'] = $iAvgBlockShares;
      }
    }
    $aEstimates = $statistics->getUserEstimates($aRoundShares, $aGlobal['userdata']['shares'], $aGlobal['userdata']['donate_percent'], $aGlobal['userdata']['no_fees']);
    $aGlobal['userdata']['estimates'] = $aEstimates;
    break;
  case 'pps':
    $aGlobal['userdata']['pps']['unpaidshares'] = $statistics->getUserUnpaidPPSShares($_SESSION['USERDATA']['username'], $_SESSION['USERDATA']['id'], $setting->getValue('pps_last_share_id'));
    $aGlobal['ppsvalue'] = number_format($statistics->getPPSValue(), 12);
    $aGlobal['poolppsvalue'] = $aGlobal['ppsvalue'] * pow(2, $config['difficulty'] - 16);
    $aGlobal['userdata']['sharedifficulty'] = $statistics->getUserShareDifficulty($_SESSION['USERDATA']['username'], $_SESSION['USERDATA']['id']);
    $aGlobal['userdata']['estimates'] = $statistics->getUserEstimates($aGlobal['userdata']['sharerate'], $aGlobal['userdata']['sharedifficulty'], $aGlobal['userdata']['donate_percent'], $aGlobal['userdata']['no_fees'], $aGlobal['ppsvalue']);
    break;
  }

  switch ($config['payout_system_mm']) {
  case 'pplns':
    $aGlobal['pplns']['target_mm'] = $config['pplns']['shares']['default'];
    if ($aLastBlock_mm = $block_mm->getLast()) {
      if ($iAvgBlockShares_mm = round($block_mm->getAvgBlockShares($aLastBlock_mm['height'], $config['pplns']['blockavg']['blockcount']))) {
        $aGlobal['pplns']['target_mm'] = $iAvgBlockShares_mm;
      }
    }
    $aEstimates_mm = $statistics_mm->getUserEstimates($aRoundShares_mm, $aGlobal['userdata']['shares_mm'], $aGlobal['userdata']['donate_percent'], $aGlobal['userdata']['no_fees']);
    $aGlobal['userdata']['estimates_mm'] = $aEstimates_mm;
    break;
  case 'pps':
    $aGlobal['userdata']['pps_mm']['unpaidshares'] = $statistics_mm->getUserUnpaidPPSShares($_SESSION['USERDATA']['username'], $_SESSION['USERDATA']['id'], $setting->getValue('pps_last_share_id_mm'));
    $aGlobal['ppsvalue_mm'] = number_format($statistics_mm->getPPSValueExt(), 12);
    $aGlobal['poolppsvalue_mm'] = $aGlobal['ppsvalue_mm'] * pow(2, $config['difficulty'] - 16);
    $aGlobal['userdata']['sharedifficulty_mm'] = $statistics_mm->getUserShareDifficulty($_SESSION['USERDATA']['username'], $_SESSION['USERDATA']['id']);
    $aGlobal['userdata']['estimates_mm'] = $statistics_mm->getUserEstimates($aGlobal['userdata']['sharerate'], $aGlobal['userdata']['sharedifficulty_mm'], $aGlobal['userdata']['donate_percent'], $aGlobal['userdata']['no_fees'], $aGlobal['ppsvalue_mm']);
    break;
  }

  switch ($config['payout_system_mm1']) {
  case 'pplns':
    $aGlobal['pplns']['target_mm1'] = $config['pplns']['shares']['default'];
    if ($aLastBlock_mm1 = $block_mm1->getLast()) {
      if ($iAvgBlockShares_mm1 = round($block_mm1->getAvgBlockShares($aLastBlock_mm1['height'], $config['pplns']['blockavg']['blockcount']))) {
        $aGlobal['pplns']['target_mm1'] = $iAvgBlockShares_mm1;
      }
    }
    $aEstimates_mm1 = $statistics_mm1->getUserEstimates($aRoundShares_mm1, $aGlobal['userdata']['shares_mm1'], $aGlobal['userdata']['donate_percent'], $aGlobal['userdata']['no_fees']);
    $aGlobal['userdata']['estimates_mm1'] = $aEstimates_mm1;
    break;
  case 'pps':
    $aGlobal['userdata']['pps_mm1']['unpaidshares'] = $statistics_mm1->getUserUnpaidPPSShares($_SESSION['USERDATA']['username'], $_SESSION['USERDATA']['id'], $setting->getValue('pps_last_share_id_mm1'));
    $aGlobal['ppsvalue_mm1'] = number_format($statistics_mm1->getPPSValueExt(), 12);
    $aGlobal['poolppsvalue_mm1'] = $aGlobal['ppsvalue_mm1'] * pow(2, $config['difficulty'] - 16);
    $aGlobal['userdata']['sharedifficulty_mm1'] = $statistics_mm1->getUserShareDifficulty($_SESSION['USERDATA']['username'], $_SESSION['USERDATA']['id']);
    $aGlobal['userdata']['estimates_mm1'] = $statistics_mm1->getUserEstimates($aGlobal['userdata']['sharerate'], $aGlobal['userdata']['sharedifficulty_mm1'], $aGlobal['userdata']['donate_percent'], $aGlobal['userdata']['no_fees'], $aGlobal['ppsvalue_mm1']);
    break;
  }


  switch ($config['payout_system_mm3']) {
  case 'pplns':
    $aGlobal['pplns']['target_mm3'] = $config['pplns']['shares']['default'];
    if ($aLastBlock_mm3 = $block_mm3->getLast()) {
      if ($iAvgBlockShares_mm3 = round($block_mm3->getAvgBlockShares($aLastBlock_mm3['height'], $config['pplns']['blockavg']['blockcount']))) {
        $aGlobal['pplns']['target_mm3'] = $iAvgBlockShares_mm3;
      }
    }
    $aEstimates_mm3 = $statistics_mm3->getUserEstimates($aRoundShares_mm3, $aGlobal['userdata']['shares_mm3'], $aGlobal['userdata']['donate_percent'], $aGlobal['userdata']['no_fees']);
   $aGlobal['userdata']['estimates_mm3'] = $aEstimates_mm3;
    break;
  case 'pps':
    $aGlobal['userdata']['pps_mm3']['unpaidshares'] = $statistics_mm3->getUserUnpaidPPSShares($_SESSION['USERDATA']['username'], $_SESSION['USERDATA']['id'], $setting->getValue('pps_last_share_id_mm3'));
    $aGlobal['ppsvalue_mm3'] = number_format($statistics_mm3->getPPSValueExt(), 12);
    $aGlobal['poolppsvalue_mm3'] = $aGlobal['ppsvalue_mm3'] * pow(2, $config['difficulty'] - 16);
    $aGlobal['userdata']['sharedifficulty_mm3'] = $statistics_mm3->getUserShareDifficulty($_SESSION['USERDATA']['username'], $_SESSION['USERDATA']['id']);
    $aGlobal['userdata']['estimates_mm3'] = $statistics_mm3->getUserEstimates($aGlobal['userdata']['sharerate'], $aGlobal['userdata']['sharedifficulty_mm3'], $aGlobal['userdata']['donate_percent'], $aGlobal['userdata']['no_fees'], $aGlobal['ppsvalue_mm3']);
    break;
  }
  
  switch ($config['payout_system_mm4']) {
  case 'pplns':
    $aGlobal['pplns']['target_mm4'] = $config['pplns']['shares']['default'];
    if ($aLastBlock_mm4 = $block_mm4->getLast()) {
      if ($iAvgBlockShares_mm4 = round($block_mm4->getAvgBlockShares($aLastBlock_mm4['height'], $config['pplns']['blockavg']['blockcount']))) {
        $aGlobal['pplns']['target_mm4'] = $iAvgBlockShares_mm4;
      }
    }
    $aEstimates_mm4 = $statistics_mm4->getUserEstimates($aRoundShares_mm4, $aGlobal['userdata']['shares_mm4'], $aGlobal['userdata']['donate_percent'], $aGlobal['userdata']['no_fees']);
   $aGlobal['userdata']['estimates_mm4'] = $aEstimates_mm4;
    break;
  case 'pps':
    $aGlobal['userdata']['pps_mm4']['unpaidshares'] = $statistics_mm4->getUserUnpaidPPSShares($_SESSION['USERDATA']['username'], $_SESSION['USERDATA']['id'], $setting->getValue('pps_last_share_id_mm4'));
    $aGlobal['ppsvalue_mm4'] = number_format($statistics_mm4->getPPSValueExt(), 12);
    $aGlobal['poolppsvalue_mm4'] = $aGlobal['ppsvalue_mm4'] * pow(2, $config['difficulty'] - 16);
    $aGlobal['userdata']['sharedifficulty_mm4'] = $statistics_mm4->getUserShareDifficulty($_SESSION['USERDATA']['username'], $_SESSION['USERDATA']['id']);
    $aGlobal['userdata']['estimates_mm4'] = $statistics_mm4->getUserEstimates($aGlobal['userdata']['sharerate'], $aGlobal['userdata']['sharedifficulty_mm4'], $aGlobal['userdata']['donate_percent'], $aGlobal['userdata']['no_fees'], $aGlobal['ppsvalue_mm4']);
    break;
  }

  switch ($config['payout_system_mm5']) {
  case 'pplns':
    $aGlobal['pplns']['target_mm5'] = $config['pplns']['shares']['default'];
    if ($aLastBlock_mm5 = $block_mm5->getLast()) {
      if ($iAvgBlockShares_mm5 = round($block_mm5->getAvgBlockShares($aLastBlock_mm5['height'], $config['pplns']['blockavg']['blockcount']))) {
        $aGlobal['pplns']['target_mm5'] = $iAvgBlockShares_mm5;
      }
    }
    $aEstimates_mm5 = $statistics_mm5->getUserEstimates($aRoundShares_mm5, $aGlobal['userdata']['shares_mm5'], $aGlobal['userdata']['donate_percent'], $aGlobal['userdata']['no_fees']);
   $aGlobal['userdata']['estimates_mm5'] = $aEstimates_mm5;
    break;
  case 'pps':
    $aGlobal['userdata']['pps_mm5']['unpaidshares'] = $statistics_mm5->getUserUnpaidPPSShares($_SESSION['USERDATA']['username'], $_SESSION['USERDATA']['id'], $setting->getValue('pps_last_share_id_mm5'));
    $aGlobal['ppsvalue_mm5'] = number_format($statistics_mm5->getPPSValueExt(), 12);
    $aGlobal['poolppsvalue_mm5'] = $aGlobal['ppsvalue_mm5'] * pow(2, $config['difficulty'] - 16);
    $aGlobal['userdata']['sharedifficulty_mm5'] = $statistics_mm5->getUserShareDifficulty($_SESSION['USERDATA']['username'], $_SESSION['USERDATA']['id']);
    $aGlobal['userdata']['estimates_mm5'] = $statistics_mm5->getUserEstimates($aGlobal['userdata']['sharerate'], $aGlobal['userdata']['sharedifficulty_mm5'], $aGlobal['userdata']['donate_percent'], $aGlobal['userdata']['no_fees'], $aGlobal['ppsvalue_mm5']);
    break;
  }


  // Site-wide notifications, based on user events
  if ($aGlobal['userdata']['balance']['confirmed'] >= $config['ap_threshold']['max'])
    $_SESSION['POPUP'][] = array('CONTENT' => 'You have exceeded the pools configured ' . $config['currency'] . ' warning threshold. Please initiate a transfer!', 'TYPE' => 'errormsg');
  if ($user->getUserFailed($_SESSION['USERDATA']['id']) > 0)
    $_SESSION['POPUP'][] = array('CONTENT' => $user->getUserFailed($_SESSION['USERDATA']['id']) . ' failed login attempts on your account. <a href="?page=account&action=reset_failed">Reset counter</a>.', 'TYPE' => 'errormsg');
}

if ($setting->getValue('maintenance'))
  $_SESSION['POPUP'][] = array('CONTENT' => 'The pool is in maintenance mode. Mining stays online; account changes and payouts are temporarily paused.', 'TYPE' => 'warning');

// Message of the Day routing:
//   - Logged-OFF visitors  → pushed to $_SESSION['POPUP'] so the toast
//                             surfaces on every public page (login,
//                             register, gettingstarted, etc.) — same
//                             as the legacy behaviour.
//   - Logged-IN  users     → NOT pushed; MotD instead appears as the
//                             first card in the dashboard messages
//                             panel (see public/include/pages/dashboard.inc.php).
//   Operators author the MotD once via admin/settings → "Message of
//   the Day" — both surfaces read the same setting value.
if (($_motd = trim((string)$setting->getValue('system_motd'))) !== ''
    && !$user->isAuthenticated(false)) {
  $_SESSION['POPUP'][] = array('CONTENT' => $_motd, 'TYPE' => 'info');
}

// So we can display additional info
$smarty->assign('DEBUG', $config['DEBUG']);

// Lets check for our cron status and render a message
require_once(INCLUDE_DIR . '/config/monitor_crons.inc.php');
$bMessage = false;
$aCronMessage[] = 'We are investingating issues in the backend. Your shares and hashrate are safe and we will fix things ASAP.</br><br/>';
foreach ($aMonitorCrons as $strCron) {
  if ($monitoring->isDisabled($strCron) == 1) {
    $bMessage = true;
    switch ($strCron) {
    case 'payouts':
      $aCronMessage[] = '<li> Payouts disabled, you will not receive any coins to your offline wallet for the time being</li>';
      break;
    case 'findblock':
      $aCronMessage[] = '<li> Findblocks disabled, new blocks will currently not show up in the frontend</li>';
      break;
    case 'blockupdate':
      $aCronMessage[] = '<li> Blockupdate disabled, blocks and transactions confirmations are delayed</li>';
      break;
    case 'pplns_payout':
      $aCronMessage[] = '<li> PPLNS payout disabled, round credit transactions are delayed</li>';
      break;
    case 'prop_payout':
      $aCronMessage[] = '<li> Proportional payout disabled, round credit transactions are delayed</li>';
      break;
    case 'pps_payout':
      $aCronMessage[] = '<li> PPS payout disabled, share credit transactions are delayed</li>';
      break;
    }
  }
}
if ($bMessage)
  $_SESSION['POPUP'][] = array('CONTENT' => implode('', $aCronMessage));

// Make it available in Smarty
$smarty->assign('PATH', 'site_assets/' . THEME);
$smarty->assign('GLOBALASSETS', 'site_assets/global');
$smarty->assign('GLOBAL', $aGlobal);
?>
