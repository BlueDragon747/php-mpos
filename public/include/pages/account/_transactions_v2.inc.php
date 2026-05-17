<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

// Shared v2 hydration for the Transactions page across all coins.
// Called by transactions.inc.php (BLC) + transactions_mm{,1,3,4,5}.inc.php
// (mergemine slots). The caller sets these context variables BEFORE
// including this file:
//
//   $tx_v2_action      string  — e.g. 'transactions', 'transactions_mm'
//   $tx_v2_currency    string  — ticker, e.g. 'BLC', 'PHO', 'BBTC'
//   $tx_v2_transactions array  — rows from $transaction*->getTransactions()
//   $tx_v2_types       array  — rows from $transaction*->getTypes()
//   $tx_v2_summary     array  — rows from $transaction*->getTransactionSummary*()
//                                (or empty/null when summary disabled)
//   $tx_v2_summary_disabled bool — admin disable_transactionsummary flag
//   $tx_v2_start       int    — pagination offset
//   $tx_v2_limit       int    — pagination size
//
// Output: assigns TX_JS / TX_CSS / TX_INITIAL_JSON to Smarty so the
// per-coin default.tpl wrapper can mount the SPA.

// Vite manifest lookup (one shared 'transactions' bundle for all coins).
$_tx_manifest_path = $_SERVER['DOCUMENT_ROOT'] . '/v2/dist/.vite/manifest.json';
$_tx_js = '';
$_tx_css = array();
if (file_exists($_tx_manifest_path)) {
  $_tx_manifest_raw = @file_get_contents($_tx_manifest_path);
  $_tx_manifest = $_tx_manifest_raw ? json_decode($_tx_manifest_raw, true) : null;
  if (is_array($_tx_manifest) && isset($_tx_manifest['transactions.html'])) {
    $_tx_entry = $_tx_manifest['transactions.html'];
    if (!empty($_tx_entry['file'])) $_tx_js = '/v2/dist/' . $_tx_entry['file'];
    if (!empty($_tx_entry['css']) && is_array($_tx_entry['css'])) {
      foreach ($_tx_entry['css'] as $_css) $_tx_css[] = '/v2/dist/' . $_css;
    }
  }
}

// Confirmations threshold + explorer URL.
// Read the Setting rows directly: smarty_globals.inc.php runs AFTER
// page controllers in index.php, so $aGlobal isn't populated yet when
// this file executes. The configured URL may contain `{coin}` —
// substituted with the lowercase ticker of the current slot so one
// settings row covers all 6 coins. Matches the round-page pattern in
// templates/mpos/statistics/round/default.tpl (deep-link into the
// BlakeStream Explorer's per-coin dashboard via a query param).
$_tx_confirmations_threshold = isset($GLOBAL['confirmations']) ? (int)$GLOBAL['confirmations'] : 6;
$_tx_explorer_disabled = !empty($setting->getValue('website_transactionexplorer_disabled'));
$_tx_explorer_url = $_tx_explorer_disabled ? '' : (string)$setting->getValue('website_transactionexplorer_url');
if ($_tx_explorer_url !== '' && strpos($_tx_explorer_url, '{coin}') !== false) {
  $_tx_explorer_url = str_replace('{coin}', strtolower((string)$tx_v2_currency), $_tx_explorer_url);
}

// Status derivation mirrors the legacy templates/mpos/account/transactions/
// default.tpl logic so the SPA doesn't have to re-port it.
$_tx_always_confirmed = array('Credit_PPS','Fee_PPS','Donation_PPS','Debit_MP','Debit_AP','TXFee');
$_tx_credit_types     = array('Credit', 'Credit_PPS', 'Bonus');

// Reshape transactions for the SPA.
$_tx_v2_rows = array();
if (is_array($tx_v2_transactions)) {
  foreach ($tx_v2_transactions as $_t) {
    $_type = isset($_t['type']) ? $_t['type'] : '';
    $_confs = isset($_t['confirmations']) ? (int)$_t['confirmations'] : 0;
    if (in_array($_type, $_tx_always_confirmed, true) || $_confs >= $_tx_confirmations_threshold) {
      $_status = 'Confirmed';
    } else if ($_confs == -1) {
      $_status = 'Orphan';
    } else {
      $_status = 'Unconfirmed';
    }
    $_tx_v2_rows[] = array(
      'id'           => isset($_t['id']) ? (int)$_t['id'] : 0,
      'timestamp'    => isset($_t['timestamp']) ? (string)$_t['timestamp'] : '',
      'username'     => isset($_t['username']) ? (string)$_t['username'] : '',
      'type'         => $_type,
      'status'       => $_status,
      'coinAddress'  => isset($_t['coin_address']) ? (string)$_t['coin_address'] : '',
      'txid'         => isset($_t['txid']) ? (string)$_t['txid'] : '',
      'height'       => isset($_t['height']) ? (int)$_t['height'] : 0,
      'amount'       => isset($_t['amount']) ? (float)$_t['amount'] : 0.0,
      'amountClass'  => in_array($_type, $_tx_credit_types, true) ? 'credit' : 'debit',
    );
  }
}

// Summary — same shape the legacy template iterated over.
$_tx_summary_v2 = array();
if (empty($tx_v2_summary_disabled) && isset($tx_v2_summary) && is_array($tx_v2_summary)) {
  foreach ($tx_v2_summary as $_type => $_total) {
    $_tx_summary_v2[(string)$_type] = (float)$_total;
  }
}

// Pop-ups from $_SESSION (e.g. "Could not find any transaction").
$_tx_popups = array();
if (isset($_SESSION['POPUP']) && is_array($_SESSION['POPUP'])) {
  foreach ($_SESSION['POPUP'] as $_p) {
    $_tx_popups[] = array(
      'content' => isset($_p['CONTENT']) ? (string)$_p['CONTENT'] : '',
      'type'    => isset($_p['TYPE']) ? (string)$_p['TYPE'] : 'info',
    );
  }
  $_SESSION['POPUP'] = array();
}

// Coin name lookup — the gettingstarted config only stores the BLC
// coin name; for the mergemine slots we fall back to a hardcoded
// ticker→name map (matches the comments in global.inc.dist.php).
$_tx_coin_names = array(
  'BLC'  => 'Blakecoin',
  'PHO'  => 'Photon',
  'BBTC' => 'BlakeBitcoin',
  'LIT'  => 'Lithium',
  'ELT'  => 'Electron',
  'UMO'  => 'Universalmolecule',
);
$_tx_currency = isset($tx_v2_currency) ? (string)$tx_v2_currency : '';
if ($_tx_currency === 'BLC' && isset($config['gettingstarted']['coinname'])) {
  $_tx_coin_name = (string)$config['gettingstarted']['coinname'];
} else if (isset($_tx_coin_names[$_tx_currency])) {
  $_tx_coin_name = $_tx_coin_names[$_tx_currency];
} else {
  $_tx_coin_name = $_tx_currency;
}

// Page slug for the form action — 'account' for the user-facing
// transactions, 'admin' for the admin view. Defaults to 'account' so
// existing callers don't have to set it.
$_tx_page = isset($tx_v2_page) ? (string)$tx_v2_page : 'account';
$_tx_form_action = isset($tx_v2_form_action) && (string)$tx_v2_form_action !== ''
  ? (string)$tx_v2_form_action
  : ('?page=' . $_tx_page . '&action=' . (isset($tx_v2_action) ? $tx_v2_action : 'transactions'));
$_tx_coin_options = array();
if (isset($tx_v2_coin_options) && is_array($tx_v2_coin_options)) {
  foreach ($tx_v2_coin_options as $_coin_option) {
    if (!is_array($_coin_option) || empty($_coin_option['value'])) continue;
    $_tx_coin_options[] = array(
      'value'    => (string)$_coin_option['value'],
      'label'    => isset($_coin_option['label']) ? (string)$_coin_option['label'] : (string)$_coin_option['value'],
      'currency' => isset($_coin_option['currency']) ? (string)$_coin_option['currency'] : '',
      'name'     => isset($_coin_option['name']) ? (string)$_coin_option['name'] : '',
    );
  }
}

$_tx_initial = array(
  'formAction'         => $_tx_form_action,
  'transactions'       => $_tx_v2_rows,
  'transactionTypes'   => is_array($tx_v2_types) ? $tx_v2_types : array(),
  'transactionStatus'  => array('' => '— Any —', 'Confirmed' => 'Confirmed', 'Unconfirmed' => 'Unconfirmed', 'Orphan' => 'Orphan'),
  'filter'             => array(
    'type'    => isset($_REQUEST['filter']['type'])    ? (string)$_REQUEST['filter']['type']    : '',
    'status'  => isset($_REQUEST['filter']['status'])  ? (string)$_REQUEST['filter']['status']  : '',
    // Admin-only filters (exact-match on username / coin_address).
    // The SPA only renders inputs when showUsername is true; values
    // are always carried through here so pagination URLs preserve
    // them.
    'account' => isset($_REQUEST['filter']['account']) ? (string)$_REQUEST['filter']['account'] : '',
    'address' => isset($_REQUEST['filter']['address']) ? (string)$_REQUEST['filter']['address'] : '',
  ),
  'limit'              => isset($tx_v2_limit) ? (int)$tx_v2_limit : 30,
  'start'              => isset($tx_v2_start) ? (int)$tx_v2_start : 0,
  'explorerUrl'        => $_tx_explorer_url,
  'explorerDisabled'   => $_tx_explorer_disabled,
  'summary'            => (object)$_tx_summary_v2,
  'summaryDisabled'    => !empty($tx_v2_summary_disabled),
  'currency'           => $_tx_currency,
  'selectedCoin'       => isset($tx_v2_selected_coin) ? (string)$tx_v2_selected_coin : strtolower($_tx_currency),
  'coinOptions'        => $_tx_coin_options,
  'coinName'           => $_tx_coin_name,
  // When true, the SPA renders a Username column (admin view across
  // all users). User-facing transactions leave this false.
  'showUsername'       => !empty($tx_v2_show_username),
  'popups'             => $_tx_popups,
);
$_tx_initial_json = json_encode(
  $_tx_initial,
  JSON_HEX_APOS | JSON_HEX_QUOT | JSON_HEX_AMP | JSON_HEX_TAG | JSON_UNESCAPED_UNICODE
);

$smarty->assign('TX_JS', $_tx_js);
$smarty->assign('TX_CSS', $_tx_css);
$smarty->assign('TX_INITIAL_JSON', $_tx_initial_json);
?>
