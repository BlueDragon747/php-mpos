<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

require_once INCLUDE_DIR . '/safe_markdown.inc.php';

// JSON-encode for embedding inside a single-quoted HTML attribute.
// JSON_HEX_APOS escapes "'" so a string like "you'd" becomes
// "you'd" instead of breaking the attribute. JSON_HEX_AMP /
// JSON_HEX_QUOT / JSON_HEX_TAG belt-and-braces vs <, >, &, ".
function json_encode_attr($value) {
  return json_encode(
    $value,
    JSON_HEX_APOS | JSON_HEX_QUOT | JSON_HEX_AMP | JSON_HEX_TAG | JSON_UNESCAPED_UNICODE
  );
}

if (!$user->isAuthenticated()) {
  header('Location: ?page=login');
  exit;
}

// Read the Vite manifest so the wrapper template knows which hashed JS
// and CSS files to reference. Manifest is regenerated on every
// `cd frontend && bun run build`. Missing manifest => render a friendly
// "build not deployed" notice (template handles the empty path).
$manifest_path = $_SERVER['DOCUMENT_ROOT'] . '/v2/dist/.vite/manifest.json';
$dashboard_js = '';
$dashboard_css = array();
if (file_exists($manifest_path)) {
  $manifest_raw = @file_get_contents($manifest_path);
  $manifest = $manifest_raw ? json_decode($manifest_raw, true) : null;
  if (is_array($manifest) && isset($manifest['dashboard.html'])) {
    $entry = $manifest['dashboard.html'];
    if (!empty($entry['file'])) {
      $dashboard_js = '/v2/dist/' . $entry['file'];
    }
    if (!empty($entry['css']) && is_array($entry['css'])) {
      foreach ($entry['css'] as $css) {
        $dashboard_css[] = '/v2/dist/' . $css;
      }
    }
  }
}

// Resolve api_key fresh from DB. The session copy of USERDATA is set at
// login time; if the user's api_key was generated/rotated after login,
// the cached session value is stale and the SPA's JSON calls will 401.
// Look up by id (which is reliable in the session) and fall back to the
// session value only if the DB lookup fails.
$user_id = isset($_SESSION['USERDATA']['id']) ? (int)$_SESSION['USERDATA']['id'] : 0;
$api_key = isset($_SESSION['USERDATA']['api_key']) ? $_SESSION['USERDATA']['api_key'] : '';
if ($user_id > 0) {
  $stmt = $mysqli->prepare("SELECT api_key FROM accounts WHERE id = ? LIMIT 1");
  if ($stmt && $stmt->bind_param('i', $user_id) && $stmt->execute()) {
    $stmt->bind_result($db_api_key);
    if ($stmt->fetch() && !empty($db_api_key)) {
      $api_key = $db_api_key;
      // Also refresh the session so other code paths (legacy dashboard,
      // navbar AJAX) see the updated key without requiring re-login.
      $_SESSION['USERDATA']['api_key'] = $db_api_key;
    }
    $stmt->close();
  }
}

$smarty->assign('V2_JS', $dashboard_js);
$smarty->assign('V2_CSS', $dashboard_css);
$smarty->assign('V2_API_KEY', $api_key);
$smarty->assign('V2_USER_ID', $user_id);
$smarty->assign('V2_REFRESH_MS', (isset($config['statistics_ajax_refresh_interval']) ? $config['statistics_ajax_refresh_interval'] : 10) * 1000);
$smarty->assign('V2_LONG_REFRESH_MS', (isset($config['statistics_ajax_long_refresh_interval']) ? $config['statistics_ajax_long_refresh_interval'] : 10) * 1000);
$smarty->assign('V2_PAYOUT_SYSTEM', isset($config['payout_system']) ? $config['payout_system'] : 'pplns');
$smarty->assign('V2_CURRENCY', isset($config['currency']) ? $config['currency'] : 'BLC');

// Per-slot coin icon URLs for the dashboard PPLNS Stats card headers.
// Sourced from _wallet_coin_meta.inc.php so operators add the icon
// URL the same way they add a new coin (single edit point — name +
// releases URL + optional icon override). Templates use the
// COIN_ICON_<SLOT> Smarty vars; if the lookup returns '' (unmapped
// coin), the template's onerror handler hides the broken <img>.
require_once dirname(__FILE__) . '/admin/_wallet_coin_meta.inc.php';
$smarty->assign('COIN_ICON_PARENT', _wallet_coin_icon_url(isset($config['currency'])     ? $config['currency']     : ''));
$smarty->assign('COIN_ICON_MM',     _wallet_coin_icon_url(isset($config['currency_mm'])  ? $config['currency_mm']  : ''));
$smarty->assign('COIN_ICON_MM1',    _wallet_coin_icon_url(isset($config['currency_mm1']) ? $config['currency_mm1'] : ''));
$smarty->assign('COIN_ICON_MM3',    _wallet_coin_icon_url(isset($config['currency_mm3']) ? $config['currency_mm3'] : ''));
$smarty->assign('COIN_ICON_MM4',    _wallet_coin_icon_url(isset($config['currency_mm4']) ? $config['currency_mm4'] : ''));
$smarty->assign('COIN_ICON_MM5',    _wallet_coin_icon_url(isset($config['currency_mm5']) ? $config['currency_mm5'] : ''));
$smarty->assign('COIN_ICON_PARENT_FALLBACK', _wallet_coin_icon_fallback_url(isset($config['currency'])     ? $config['currency']     : ''));
$smarty->assign('COIN_ICON_MM_FALLBACK',     _wallet_coin_icon_fallback_url(isset($config['currency_mm'])  ? $config['currency_mm']  : ''));
$smarty->assign('COIN_ICON_MM1_FALLBACK',    _wallet_coin_icon_fallback_url(isset($config['currency_mm1']) ? $config['currency_mm1'] : ''));
$smarty->assign('COIN_ICON_MM3_FALLBACK',    _wallet_coin_icon_fallback_url(isset($config['currency_mm3']) ? $config['currency_mm3'] : ''));
$smarty->assign('COIN_ICON_MM4_FALLBACK',    _wallet_coin_icon_fallback_url(isset($config['currency_mm4']) ? $config['currency_mm4'] : ''));
$smarty->assign('COIN_ICON_MM5_FALLBACK',    _wallet_coin_icon_fallback_url(isset($config['currency_mm5']) ? $config['currency_mm5'] : ''));

// PPLNS target — only meaningful when payout_system is pplns. Read from
// the same place the legacy template does ($GLOBAL.pplns.target via the
// pplns class). We resolve it server-side rather than expose a new API
// endpoint for one number.
$pplns_target = '';
if (($config['payout_system'] ?? '') === 'pplns' && isset($pplns) && is_object($pplns) && method_exists($pplns, 'getTarget')) {
  $pplns_target = (string)$pplns->getTarget();
}
$smarty->assign('V2_PPLNS_TARGET', $pplns_target);

// All-coins balance snapshot — primary + 5 mergemine slots. Mirrors
// public/include/smarty_globals.inc.php:264-270 ($transaction_mm{,1,3,4,5}
// ->getBalance) and the currency labels passed from $config. Rendered
// as JSON in `data-balances` so the SPA can show all 6 balance cards
// without a per-coin AJAX endpoint.
$balance_slots = array(
  array('key' => 'primary', 'currency' => isset($config['currency']) ? $config['currency'] : 'BLC',
        'tx' => isset($transaction) ? $transaction : null),
  array('key' => 'mm',      'currency' => isset($config['currency_mm']) ? $config['currency_mm'] : '',
        'tx' => isset($transaction_mm) ? $transaction_mm : null),
  array('key' => 'mm1',     'currency' => isset($config['currency_mm1']) ? $config['currency_mm1'] : '',
        'tx' => isset($transaction_mm1) ? $transaction_mm1 : null),
  array('key' => 'mm3',     'currency' => isset($config['currency_mm3']) ? $config['currency_mm3'] : '',
        'tx' => isset($transaction_mm3) ? $transaction_mm3 : null),
  array('key' => 'mm4',     'currency' => isset($config['currency_mm4']) ? $config['currency_mm4'] : '',
        'tx' => isset($transaction_mm4) ? $transaction_mm4 : null),
  array('key' => 'mm5',     'currency' => isset($config['currency_mm5']) ? $config['currency_mm5'] : '',
        'tx' => isset($transaction_mm5) ? $transaction_mm5 : null),
);

$balances = array();
foreach ($balance_slots as $slot) {
  if (empty($slot['currency']) || $slot['tx'] === null) continue;
  $bal = method_exists($slot['tx'], 'getBalance') ? $slot['tx']->getBalance($user_id) : null;
  $balances[] = array(
    'key'         => $slot['key'],
    'currency'    => $slot['currency'],
    'confirmed'   => isset($bal['confirmed']) ? (float)$bal['confirmed'] : 0.0,
    'unconfirmed' => isset($bal['unconfirmed']) ? (float)$bal['unconfirmed'] : 0.0,
    'inflight'    => isset($bal['inflight']) ? (float)$bal['inflight'] : 0.0,
  );
}
$smarty->assign('V2_BALANCES_JSON', json_encode_attr($balances));

// Per-coin stats snapshot for the StatsBlock x6. We need the same data
// smarty_globals.inc.php builds for the legacy template — roundshares_mm{,1,3,4,5},
// userdata.shares_mm{,1,3,4,5}, userdata.estimates_mm{,1,3,4,5}, plus the
// per-coin network info (difficulty / esttimeperblock / block) which the
// legacy controller queries via $bitcoin_mm{,1,3,4,5}->get*().
//
// smarty_globals runs AFTER this controller in index.php's normal flow
// (see index.php line ~179). require_once it here so $GLOBAL is built
// now; the index.php call becomes a no-op (require_once dedups).
require_once(INCLUDE_DIR . '/smarty_globals.inc.php');
$global = $smarty->getTemplateVars('GLOBAL');

// Per-coin payout system (override of primary if set).
$payout_systems = array(
  'primary' => isset($global['config']['payout_system'])     ? $global['config']['payout_system']     : 'pplns',
  'mm'      => isset($global['config']['payout_system_mm'])  ? $global['config']['payout_system_mm']  : '',
  'mm1'     => isset($global['config']['payout_system_mm1']) ? $global['config']['payout_system_mm1'] : '',
  'mm3'     => isset($global['config']['payout_system_mm3']) ? $global['config']['payout_system_mm3'] : '',
  'mm4'     => isset($global['config']['payout_system_mm4']) ? $global['config']['payout_system_mm4'] : '',
  'mm5'     => isset($global['config']['payout_system_mm5']) ? $global['config']['payout_system_mm5'] : '',
);

// Per-coin pplns target.
$pplns_targets = array(
  'primary' => isset($global['pplns']['target'])     ? $global['pplns']['target']     : null,
  'mm'      => isset($global['pplns']['target_mm'])  ? $global['pplns']['target_mm']  : null,
  'mm1'     => isset($global['pplns']['target_mm1']) ? $global['pplns']['target_mm1'] : null,
  'mm3'     => isset($global['pplns']['target_mm3']) ? $global['pplns']['target_mm3'] : null,
  'mm4'     => isset($global['pplns']['target_mm4']) ? $global['pplns']['target_mm4'] : null,
  'mm5'     => isset($global['pplns']['target_mm5']) ? $global['pplns']['target_mm5'] : null,
);

// Per-coin network info — query the bitcoin_mm{,1,3,4,5} clients the
// same way legacy dashboard.inc.php does.
$network_clients = array(
  'primary' => isset($bitcoin)     ? $bitcoin     : null,
  'mm'      => isset($bitcoin_mm)  ? $bitcoin_mm  : null,
  'mm1'     => isset($bitcoin_mm1) ? $bitcoin_mm1 : null,
  'mm3'     => isset($bitcoin_mm3) ? $bitcoin_mm3 : null,
  'mm4'     => isset($bitcoin_mm4) ? $bitcoin_mm4 : null,
  'mm5'     => isset($bitcoin_mm5) ? $bitcoin_mm5 : null,
);

$statistics_clients = array(
  'primary' => isset($statistics)     ? $statistics     : null,
  'mm'      => isset($statistics_mm)  ? $statistics_mm  : null,
  'mm1'     => isset($statistics_mm1) ? $statistics_mm1 : null,
  'mm3'     => isset($statistics_mm3) ? $statistics_mm3 : null,
  'mm4'     => isset($statistics_mm4) ? $statistics_mm4 : null,
  'mm5'     => isset($statistics_mm5) ? $statistics_mm5 : null,
);

function v2_network_info($client) {
  if (!is_object($client) || !method_exists($client, 'can_connect') || $client->can_connect() !== true) {
    return array('difficulty' => 0, 'esttimeperblock' => 0, 'block' => 0);
  }
  $diff = method_exists($client, 'getdifficulty')      ? (float)$client->getdifficulty()      : 0.0;
  $hps  = method_exists($client, 'getnetworkhashps')   ? (float)$client->getnetworkhashps()   : 0.0;
  $blk  = method_exists($client, 'getblockcount')      ? (int)$client->getblockcount()        : 0;
  $secs = ($hps > 0 && $diff > 0) ? ($diff * pow(2, 32) / $hps) : 0;
  return array('difficulty' => $diff, 'esttimeperblock' => $secs, 'block' => $blk);
}

function v2_round_share_progress($statistics_client, $netinfo, $roundshares) {
  $estimated = 0;
  if (is_object($statistics_client) && method_exists($statistics_client, 'getEstimatedShares')) {
    $difficulty = isset($netinfo['difficulty']) ? (float)$netinfo['difficulty'] : 0.0;
    if ($difficulty > 0) {
      $estimated = (int)$statistics_client->getEstimatedShares($difficulty);
    }
  }
  $valid = isset($roundshares['valid']) ? (float)$roundshares['valid'] : 0.0;
  $progress = ($estimated > 0 && $valid > 0) ? round(100 / $estimated * $valid, 2) : 0.0;
  return array('estimated' => $estimated, 'progress' => $progress);
}

$stats = array();
$slot_to_currency = array();
foreach ($balances as $b) $slot_to_currency[$b['key']] = $b['currency'];

foreach (array('primary','mm','mm1','mm3','mm4','mm5') as $slot) {
  $currency = isset($slot_to_currency[$slot]) ? $slot_to_currency[$slot] : '';
  if (empty($currency)) continue;

  $rs_key  = $slot === 'primary' ? 'roundshares' : ('roundshares_'.$slot);
  $us_key  = $slot === 'primary' ? 'shares'      : ('shares_'.$slot);
  $est_key = $slot === 'primary' ? 'estimates'   : ('estimates_'.$slot);

  $roundshares = isset($global[$rs_key]) ? $global[$rs_key] : array('valid'=>0,'invalid'=>0,'estimated'=>0,'progress'=>0);
  $your_shares = isset($global['userdata'][$us_key]) ? $global['userdata'][$us_key] : array('valid'=>0,'invalid'=>0);
  $estimates   = isset($global['userdata'][$est_key]) ? $global['userdata'][$est_key] : array();
  $netinfo     = v2_network_info($network_clients[$slot]);
  $round_progress = v2_round_share_progress($statistics_clients[$slot], $netinfo, $roundshares);

  $stats[] = array(
    'key'           => $slot,
    'currency'      => $currency,
    'icon_url'      => _wallet_coin_icon_url($currency),
    'icon_fallback_url' => _wallet_coin_icon_fallback_url($currency),
    'payout_system' => $payout_systems[$slot] !== '' ? $payout_systems[$slot] : $payout_systems['primary'],
    'pplns_target'  => $pplns_targets[$slot],
    'roundshares'   => array(
      'valid'     => isset($roundshares['valid'])     ? (int)$roundshares['valid']   : 0,
      'invalid'   => isset($roundshares['invalid'])   ? (int)$roundshares['invalid'] : 0,
      'estimated' => $round_progress['estimated'],
      'progress'  => $round_progress['progress'],
    ),
    'your_shares'   => array(
      'valid'   => isset($your_shares['valid'])   ? (int)$your_shares['valid']   : 0,
      'invalid' => isset($your_shares['invalid']) ? (int)$your_shares['invalid'] : 0,
    ),
    'estimates'     => array(
      'block'    => isset($estimates['block'])    ? (float)$estimates['block']    : 0.0,
      'fee'      => isset($estimates['fee'])      ? (float)$estimates['fee']      : 0.0,
      'donation' => isset($estimates['donation']) ? (float)$estimates['donation'] : 0.0,
      'payout'   => isset($estimates['payout'])   ? (float)$estimates['payout']   : 0.0,
      'hours1'   => isset($estimates['hours1'])   ? (float)$estimates['hours1']   : 0.0,
      'hours24'  => isset($estimates['hours24'])  ? (float)$estimates['hours24']  : 0.0,
      'days7'    => isset($estimates['days7'])    ? (float)$estimates['days7']    : 0.0,
      'days14'   => isset($estimates['days14'])   ? (float)$estimates['days14']   : 0.0,
      'days30'   => isset($estimates['days30'])   ? (float)$estimates['days30']   : 0.0,
    ),
    'network'       => $netinfo,
  );
}
$smarty->assign('V2_STATS_JSON', json_encode_attr($stats));

// Pool messages — two sources, in priority order:
//   1) the system_motd admin setting (single short string), pinned first
//   2) news entries whose show_on is 'dashboard' or 'both', newest first
// MotD lives in admin/settings; news lives in admin/news. Together they
// drive the v2 dashboard messages panel.
$messages = array();
$sMotd = isset($setting) ? (string)$setting->getValue('system_motd') : '';
// Pin the MotD as a dashboard card ONLY in `popup` mode. In `always`
// mode the master.tpl banner is the single source of truth, so we
// skip the card to avoid double-rendering.
$sMotdMode = isset($setting) ? (string)$setting->getValue('system_motd_display_mode') : '';
if (!in_array($sMotdMode, array('always', 'popup'), true)) $sMotdMode = 'always';
if (trim($sMotd) !== '' && $sMotdMode === 'popup') {
  $messages[] = array(
    'id'     => 'motd',
    'type'   => 'info',
    'title'  => '',
    'body'   => mpos_render_safe_markdown($sMotd),
    'posted' => '',
  );
}
if (isset($news) && method_exists($news, 'getAllActiveFor')) {
  $aActiveNews = $news->getAllActiveFor('dashboard');
  if (is_array($aActiveNews)) {
    foreach ($aActiveNews as $n) {
      $body = isset($n['content']) ? (string)$n['content'] : '';
      // Same XSS-safe Markdown render the admin news page uses
      // (no_markup=true + URL scheme allow-list). The message body
      // ends up in v-html on the dashboard, so anything that survives
      // here executes for every dashboard viewer.
      $body = mpos_render_safe_markdown($body);
      $messages[] = array(
        'id'      => 'news-' . (isset($n['id']) ? (int)$n['id'] : 0),
        'type'    => 'info',
        'title'   => isset($n['header']) ? (string)$n['header'] : '',
        'body'    => $body,
        'posted'  => isset($n['time']) ? substr((string)$n['time'], 0, 10) : '',
      );
    }
  }
}
$smarty->assign('V2_MESSAGES_JSON', json_encode_attr($messages));

// Session-scoped key so dismissals reset on logout/login. Use the
// session id (changes on session_regenerate after login) so the
// browser's sessionStorage namespace flips when the user re-auths.
$smarty->assign('V2_SESSION_KEY', session_id() ?: 'anon');

// Surface key state in the rendered HTML so we can debug from the
// browser without DB access. Remove once v2 is stable.
$smarty->assign('V2_DEBUG', sprintf(
  'user_id=%d api_key=%s manifest=%s balances=%dB stats=%dB',
  $user_id,
  $api_key === '' ? '(empty)' : substr($api_key, 0, 8) . '…(' . strlen($api_key) . ' chars)',
  $dashboard_js === '' ? '(missing)' : 'ok',
  strlen($smarty->getTemplateVars('V2_BALANCES_JSON') ?? ''),
  strlen($smarty->getTemplateVars('V2_STATS_JSON') ?? '')
));

$smarty->assign('CONTENT', 'default.tpl');
?>
