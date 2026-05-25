<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

// Shared ticker → display-name map for the admin wallet pages. Each
// wallet controller (wallet.inc.php, wallet_mm{,1,2,3,4,5,6}.inc.php)
// sets $wallet_ticker to the relevant $config['currency_*'] before
// including this file. Resolves COIN_TICKER + COIN_NAME for the
// shared admin/wallet/default.tpl Smarty template.

$_wallet_coin_names = array(
  'BLC'  => 'Blakecoin',
  'PHO'  => 'Photon',
  'BBTC' => 'BlakeBitcoin',
  'LIT'  => 'Lithium',
  'ELT'  => 'Electron',
  'UMO'  => 'UniversalMolecule',
);

// Ticker → GitHub releases URL. Used by gettingstarted.inc.php to
// surface a clickable list of coin clients. Hardcoded here because
// the URLs are stable upstream; operators who fork can override
// per-coin without touching the template.
$_wallet_coin_releases = array(
  'BLC'  => 'https://github.com/BlueDragon747/Blakecoin/releases',
  'PHO'  => 'https://github.com/BlueDragon747/photon/releases',
  'BBTC' => 'https://github.com/BlakeBitcoin/BlakeBitcoin/releases',
  'ELT'  => 'https://github.com/BlueDragon747/Electron-ELT/releases',
  'UMO'  => 'https://github.com/BlueDragon747/universalmol/releases',
  'LIT'  => 'https://github.com/BlueDragon747/lithium/releases',
);

// Current 25.2 Qt icon basename by ticker. The path remains the standard
// Bitcoin-Qt resource path; 25.2 repos use coin-specific filenames, with
// bitcoin.png kept as the runtime fallback.
$_wallet_coin_icon_files = array(
  'BLC'  => 'blakecoin.png',
  'PHO'  => 'photon.png',
  'BBTC' => 'blakebitcoin.png',
  'ELT'  => 'electron.png',
  'LIT'  => 'lithium.png',
  'UMO'  => 'universalmolecule.png',
);

// Optional operator override for per-coin icon URL. When adding a
// new coin to the pool, an operator can set an entry here pointing
// at a non-GitHub URL or a custom CDN; otherwise the icon URL is
// auto-derived from the matching releases URL via
// _wallet_coin_icon_url() below using the standard Bitcoin-Qt
// resource path `src/qt/res/icons/<icon-file>` on master.
//
// Example operator override:
//   $_wallet_coin_icons['BLC'] = 'https://my-cdn.example.com/blc.png';
$_wallet_coin_icons = array();

if (!function_exists('_wallet_coin_raw_icon_base_url')) {
  function _wallet_coin_raw_icon_base_url($ticker) {
    global $_wallet_coin_releases;
    $tk = strtoupper((string)$ticker);
    if ($tk === '' || !isset($_wallet_coin_releases[$tk])) return '';
    if (!preg_match('#github\.com/([^/]+/[^/.]+)#',
                    $_wallet_coin_releases[$tk], $m)) {
      return '';
    }
    return 'https://raw.githubusercontent.com/' . $m[1]
         . '/master/src/qt/res/icons/';
  }
}

if (!function_exists('_wallet_coin_icon_url')) {
  // Resolution order:
  //   1. Operator override in $_wallet_coin_icons[<TICKER>]
  //   2. Auto-derived GitHub raw URL from $_wallet_coin_releases
  //      using the current 25.2 icon basename for that coin.
  //   3. '' if no entry at all.
  function _wallet_coin_icon_url($ticker) {
    global $_wallet_coin_icons, $_wallet_coin_icon_files;
    $tk = strtoupper((string)$ticker);
    if ($tk === '') return '';
    if (isset($_wallet_coin_icons[$tk]) && $_wallet_coin_icons[$tk] !== '') {
      return $_wallet_coin_icons[$tk];
    }
    $base = _wallet_coin_raw_icon_base_url($tk);
    if ($base === '') return '';
    $file = isset($_wallet_coin_icon_files[$tk]) ? $_wallet_coin_icon_files[$tk] : 'bitcoin.png';
    return $base . $file;
  }
}

if (!function_exists('_wallet_coin_icon_fallback_url')) {
  function _wallet_coin_icon_fallback_url($ticker) {
    global $_wallet_coin_icons, $_wallet_coin_icon_files;
    $tk = strtoupper((string)$ticker);
    if ($tk === '' || isset($_wallet_coin_icons[$tk])) return '';
    if (!isset($_wallet_coin_icon_files[$tk]) || $_wallet_coin_icon_files[$tk] === 'bitcoin.png') {
      return '';
    }
    $base = _wallet_coin_raw_icon_base_url($tk);
    return $base === '' ? '' : $base . 'bitcoin.png';
  }
}

$_ticker = isset($wallet_ticker) ? (string)$wallet_ticker : '';
$_name   = isset($_wallet_coin_names[$_ticker])
  ? $_wallet_coin_names[$_ticker]
  : ($_ticker !== '' ? $_ticker : '');

$smarty->assign('COIN_TICKER', $_ticker);
$smarty->assign('COIN_NAME', $_name);
?>
