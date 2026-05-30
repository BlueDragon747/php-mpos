<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

/**
 * Do not edit this unless you have confirmed that your config has been updated!
 *  https://github.com/MPOS/php-mpos/wiki/Config-Setup#wiki-config-version
 **/
$config['version'] = '0.0.7';

/**
 * Unless you disable this, we'll do a quick check on your config first.
 *  https://github.com/MPOS/php-mpos/wiki/Config-Setup#wiki-config-check
 */
$config['skip_config_tests'] = true;

/**
 * Defines
 *  Debug setting and salts for hashing passwords
 *   https://github.com/MPOS/php-mpos/wiki/Config-Setup#wiki-defines--salts
 */
$config['DEBUG'] = 0;
// SECURITY: These MUST be replaced with two long random strings
// before the pool accepts any real user. Password/PIN/api-key hashes
// are sha256(value + SALT) — if SALT is the shipped default, every
// MPOS install on the planet shares the same hash space and rainbow
// tables are trivial.
//
// Operators MUST override these in global.inc.php. The deploy bundle
// renders random hex into global.inc.php at install time. This file
// (dist) runs FIRST, so global.inc.php's overrides take precedence.
// The placeholder die-guard that used to live here was removed
// because it fires before global.inc.php has a chance to provide the
// real values; the post-load guard now lives in shared.inc.php
// (cron entry) and public/include/bootstrap.php (web entry).
$config['SALT']  = 'CHANGE_ME_BEFORE_DEPLOY_SALT_GENERATE_RANDOM_48CHARS';
$config['SALTY'] = 'CHANGE_ME_BEFORE_DEPLOY_SALTY_GENERATE_RANDOM_48CHARS';


/**
  * Coin Algorithm
  *  Algorithm used by this coin, sha256d or scrypt
  *   https://github.com/MPOS/php-mpos/wiki/Config-Setup#wiki-algorithm
  **/
$config['algorithm'] = 'sha256d';

/**
 * Database configuration
 *  MySQL database configuration
 *   https://github.com/MPOS/php-mpos/wiki/Config-Setup#wiki-database-configuration
 **/
$config['db']['host'] = 'localhost';
$config['db']['user'] = 'mpos';
$config['db']['pass'] = 'Dbpass2013';
$config['db']['port'] = 3306;
$config['db']['name'] = 'mpos';

/**
 * Local wallet RPC
 *  RPC configuration for your daemon/wallet
 *   https://github.com/MPOS/php-mpos/wiki/Config-Setup#wiki-local-wallet-rpc
 **/
// Mainnet defaults. All passwords MUST be overridden per-install with the
// real `rpcpassword=` value from each coin's .conf. Usernames align with
// the rpcuser= values operators typically use.
$config['wallet']['type'] = 'http';
$config['wallet']['host'] = 'localhost:8772';       // Blakecoin mainnet RPC
$config['wallet']['username'] = 'blakecoin';
$config['wallet']['password'] = 'x';

$config['wallet_mm']['type'] = 'http';
$config['wallet_mm']['host'] = 'localhost:8984';    // Photon mainnet RPC
$config['wallet_mm']['username'] = 'photon';
$config['wallet_mm']['password'] = 'x';

$config['wallet_mm1']['type'] = 'http';
$config['wallet_mm1']['host'] = 'localhost:8243';   // BlakeBitcoin mainnet RPC
$config['wallet_mm1']['username'] = 'blakebitcoin';
$config['wallet_mm1']['password'] = 'x';

$config['wallet_mm2']['type'] = 'http';
$config['wallet_mm2']['host'] = 'localhost:0';      // reserved legacy aux slot; inactive in 25.2
$config['wallet_mm2']['username'] = 'unused1';
$config['wallet_mm2']['password'] = 'x';

$config['wallet_mm3']['type'] = 'http';
$config['wallet_mm3']['host'] = 'localhost:6852';   // Electron-ELT mainnet RPC
$config['wallet_mm3']['username'] = 'electron';
$config['wallet_mm3']['password'] = 'x';

$config['wallet_mm4']['type'] = 'http';
$config['wallet_mm4']['host'] = 'localhost:5921';   // Universalmolecule mainnet RPC
$config['wallet_mm4']['username'] = 'umo';
$config['wallet_mm4']['password'] = 'x';

$config['wallet_mm5']['type'] = 'http';
$config['wallet_mm5']['host'] = 'localhost:12000';  // Lithium mainnet RPC
$config['wallet_mm5']['username'] = 'lithium';
$config['wallet_mm5']['password'] = 'x';

$config['wallet_mm6']['type'] = 'http';
$config['wallet_mm6']['host'] = 'localhost:456';
$config['wallet_mm6']['username'] = 'tba2';
$config['wallet_mm6']['password'] = 'x';

/**
 * Cold Wallet / Liquid Assets
 *  Automatically send liquid assets to a cold wallet
 *   https://github.com/MPOS/php-mpos/wiki/Config-Setup#wiki-liquid-assets--cold-wallet
 **/
$config['coldwallet']['address'] = '';
$config['coldwallet']['reserve'] = 50;
$config['coldwallet']['threshold'] = 5;

/**
 * Getting Started Config
 *  Shown to users in the 'Getting Started' section
 *   https://github.com/MPOS/php-mpos/wiki/Config-Setup#wiki-getting-started
 **/
$config['gettingstarted']['coinname'] = 'Blakecoin';
$config['gettingstarted']['coinurl'] = 'http://www.Blakecoin.org';
$config['gettingstarted']['stratumurl'] = 'http://188.226.213.85/';
$config['gettingstarted']['stratumport'] = '3334';

/**
 * Ticker API
 *  Fetch exchange rates via an API
 *   https://github.com/MPOS/php-mpos/wiki/Config-Setup#wiki-ticker-api
 **/
$config['price']['url'] = 'https://btc-e.com';
$config['price']['target'] = '/api/2/ltc_usd/ticker';
$config['price']['currency'] = null;

/**
 * Automatic Payout Thresholds
 *  Minimum and Maximum auto payout amount
 *   https://github.com/MPOS/php-mpos/wiki/Config-Setup#wiki-automatic-payout-thresholds
 **/
$config['ap_threshold']['min'] = 1;
$config['ap_threshold']['max'] = 2500;

$config['ap_threshold_mm']['min'] = 1;
$config['ap_threshold_mm']['max'] = 999999;

$config['ap_threshold_mm1']['min'] = 1;
$config['ap_threshold_mm1']['max'] = 9999;

$config['ap_threshold_mm2']['min'] = 0.1;
$config['ap_threshold_mm2']['max'] = 9999;

$config['ap_threshold_mm3']['min'] = 1;
$config['ap_threshold_mm3']['max'] = 9999;

$config['ap_threshold_mm4']['min'] = 0.1;
$config['ap_threshold_mm4']['max'] = 9999;

$config['ap_threshold_mm5']['min'] = 1;
$config['ap_threshold_mm5']['max'] = 9999;

$config['ap_threshold_mm6']['min'] = 1;
$config['ap_threshold_mm6']['max'] = 9999;

/**
 * Donation thresholds
 *  Minimum donation amount in percent
 *   https://github.com/MPOS/php-mpos/wiki/Config-Setup#wiki-donation-thresholds
 **/
$config['donate_threshold']['min'] = 1;

/**
 * Account Specific Settings
 *  Settings for each user account
 *   https://github.com/MPOS/php-mpos/wiki/Config-Setup#wiki-account-specific-settings
 **/
$config['accounts']['invitations']['count'] = 5;

/**
 * Currency / merged-mining slots
 * ------------------------------------------------------------------
 *
 * Per-coin ticker for the parent chain (`currency`) and each of the
 * up to seven aux slots (`currency_mm` … `currency_mm6`). These
 * strings drive several things across the pool, so they have to stay
 * in sync with the rest of the config:
 *
 *   1. **Coin chip rails.** The Statistics → Round Statistics and
 *      Statistics → BlockFinder pages auto-build a coloured chip
 *      rail per coin by reading these keys in order:
 *        - `currency`          → parent (first chip)
 *        - `currency_mm`       → second chip
 *        - `currency_mm1` … 6  → subsequent chips
 *      Add a real ticker here and the chip appears on the next page
 *      load — no template change required.
 *
 *   2. **'unused*' sentinel.** Any slot whose value contains
 *      `unused` (case-insensitive) is *hidden* from the chip rails
 *      and treated as a free slot. Use `unused1`, `unused2`, etc.
 *      to keep slot indices stable while still leaving room to wire
 *      a coin up later. Do NOT delete the row — the surrounding
 *      `wallet_mm*` / `ap_threshold_mm*` rows must keep their slot
 *      index for the existing coins to address the right tables.
 *
 *   3. **Wallet RPC.** Each non-`unused` slot needs a matching
 *      `$config['wallet_mm*']` block above (host/username/password)
 *      so the pool can reach that coin's daemon. Without it the
 *      slot's chip will render but every page that hits the daemon
 *      will fall over.
 *
 *   4. **Per-slot DB tables.** The slot suffix maps to MySQL tables
 *      `blocks_<slot>`, `transactions_<slot>`, `shares_<slot>`,
 *      `shares_archive_<slot>` (e.g. `blocks_mm3` for the
 *      `currency_mm3` slot). These get created by the SQL migrations
 *      in `sql/old/`. The parent uses the unsuffixed `blocks`,
 *      `transactions`, etc.
 *
 *   5. **Per-slot PHP classes.** Each slot has its own
 *      `Statistics_mm*`, `Block_mm*`, `Transaction_mm*` subclass
 *      under `include/classes/`, instantiated as
 *      `$statistics_mm*` / `$block_mm*` / `$transaction_mm*`. These
 *      are loaded by `include/init.inc.php` regardless of whether
 *      the slot is in use, so wiring up an `unused*` slot later is
 *      a config-only change.
 *
 *   6. **Auto-payout thresholds.** Each non-`unused` slot also wants
 *      a matching `ap_threshold_mm*` block below so the auto-payout
 *      cron can drain user balances on that coin.
 *
 *   7. **Per-coin tooling.** The Eloipool stratum and merged-mine
 *      proxy ALSO need to know which aux chain lives in which slot —
 *      that's a separate set of config files outside MPOS. Changing
 *      `currency_mm*` here without updating the proxy will lead to
 *      shares being credited to the wrong slot's table.
 *
 * See `https://github.com/MPOS/php-mpos/wiki/Config-Setup#wiki-currency`
 * for the upstream wiki page (predates the chip rails).
 */
$config['currency']     = 'BLC';
$config['currency_mm']  = 'PHO';   // Photon
$config['currency_mm1'] = 'BBTC';  // BlakeBitcoin (was HTML entity; plain ticker is safer)
$config['currency_mm2'] = 'unused1';  // reserved legacy aux slot
$config['currency_mm3'] = 'ELT';   // Electron
$config['currency_mm4'] = 'UMO';   // Universalmolecule
$config['currency_mm5'] = 'LIT';   // Lithium
$config['currency_mm6'] = 'unused2';  // free slot — see header for re-use checklist


/**
 * Address formats (SegWit / bech32 + legacy base58 version bytes)
 *
 * Used by Bitcoin::checkAddress() as a local fallback. MPOS's primary
 * address validation still goes through BitcoinClient::validateaddress()
 * (the coin daemon's RPC), but this config keeps the fallback path
 * bech32-aware so offline validation works for Blakecoin.
 *
 * Blakecoin 0.15.21 networks:
 *   - mainnet HRP  'blc'   P2PKH 25/26  P2SH 22
 *   - testnet HRP  'tblc'  P2PKH 142    P2SH 170
 *   - regtest HRP  'rblc'  P2PKH 26     P2SH 7
 *   - devnet  HRP  'dblk'  P2PKH 65     P2SH 120
 * Default ships mainnet + testnet only; add others as needed.
 */
// Production default is mainnet-only. Add 'tblc' for testnet, 'rblc' for
// regtest, 'dblk' for devnet in the dev instance's own global.inc.php as
// needed. Keeping mainnet narrow here so a copy-paste install can't
// accidentally accept a testnet address as a payout destination.
$config['segwit_hrps']         = array('blc');
$config['address_versions']    = array(25, 26);     // Blakecoin mainnet P2PKH
$config['address_versions_p2sh'] = array(22);       // Blakecoin mainnet P2SH
$config['segwit_hrps_by_slot'] = array(
  ''    => array('blc'),   // Blakecoin
  'mm'  => array('pho'),   // Photon
  'mm1' => array('bbtc'),  // BlakeBitcoin
  'mm3' => array('elt'),   // Electron
  'mm4' => array('umo'),   // Universalmolecule
  'mm5' => array('lit'),   // Lithium
);


/**
 * Coin Target
 *  Target time for coins to be generated
 *   https://github.com/MPOS/php-mpos/wiki/Config-Setup#wiki-coin-target
 **/
$config['cointarget'] = '180';
$config['cointarget_mm'] = '180';
$config['cointarget_mm1'] = '150';
$config['cointarget_mm2'] = '180';
$config['cointarget_mm3'] = '180';
$config['cointarget_mm4'] = '120';
$config['cointarget_mm5'] = '180';
$config['cointarget_mm6'] = '180';
/**
 * Coin Diff Change
 *  Amount of blocks between difficulty changes
 *   https://github.com/MPOS/php-mpos/wiki/Config-Setup#wiki-coin-diff-change
 **/
$config['coindiffchangetarget'] = 20;


/**
 * TX Fees
 *  Fees applied to transactions
 *   https://github.com/MPOS/php-mpos/wiki/Config-Setup#wiki-tx-fees
 **/
$config['txfee_auto'] = 0.001;
$config['txfee_manual'] = 0.001;

/**
 * Block Bonus
 *  Bonus in coins of block bonus
 *   https://github.com/MPOS/php-mpos/wiki/Config-Setup#wiki-block-bonus
 */
$config['block_bonus'] = 0;


/**
 * Payout System
 *  Payout system chosen
 *   https://github.com/MPOS/php-mpos/wiki/Config-Setup#wiki-payout-system
 *  prop  pplns
 **/
$config['payout_system'] = 'pplns';
$config['payout_system_mm'] = 'pplns';
$config['payout_system_mm1'] = 'pplns';
$config['payout_system_mm2'] = 'pplns';
$config['payout_system_mm3'] = 'pplns';
$config['payout_system_mm4'] = 'pplns';
$config['payout_system_mm5'] = 'pplns';
$config['payout_system_mm6'] = 'pplns';
/**
 * Sendmany Support
 *  Enable/Disable Sendmany RPC method
 *   https://github.com/MPOS/php-mpos/wiki/Config-Setup#wiki-sendmany-support
 **/
$config['sendmany']['enabled'] = false;

/**
 * Round Purging
 *  Round share purging configuration
 *   https://github.com/MPOS/php-mpos/wiki/Config-Setup#wiki-round-purging
 **/
$config['purge']['sleep'] = 1;
$config['purge']['shares'] = 25000;

/**
 * Share Archiving
 *  Share archiving configuration details
 *   https://github.com/MPOS/php-mpos/wiki/Config-Setup#wiki-archiving
 **/
$config['archive']['maxrounds'] = 10; 
$config['archive']['maxage'] = 60 * 24; 


/**
 * Pool Fees
 *  Fees applied to users
 *   https://github.com/MPOS/php-mpos/wiki/Config-Setup#wiki-pool-fees
 */
$config['fees'] = 1.5;
$config['fees_mm'] = 1.5;
$config['fees_mm1'] = 1.5;
$config['fees_mm2'] = 1.5;
$config['fees_mm3'] = 1.5;
$config['fees_mm4'] = 1.5;
$config['fees_mm5'] = 1.5;
$config['fees_mm6'] = 1.5;

/**
 * PPLNS
 *  Pay Per Last N Shares
 *   https://github.com/MPOS/php-mpos/wiki/Config-Setup#wiki-pplns-settings
 */
$config['pplns']['shares']['default'] = 4000000;
$config['pplns']['shares']['type'] = 'blockavg';
$config['pplns']['blockavg']['blockcount'] = 5;
$config['pplns']['reverse_payout'] = false;
$config['pplns']['dynamic']['percent'] = 30;

/**
 * Difficulty  sha256d: 16  scrypt: 20  diff_32: 21
 *  Difficulty setting for stratum/pushpool
 *   https://github.com/MPOS/php-mpos/wiki/Config-Setup#wiki-pool-target-difficulty
 */
$config['difficulty'] = 21;

/**
 * Block Reward
 *  Block reward configuration details
 *   https://github.com/MPOS/php-mpos/wiki/Config-Setup#wiki-reward-settings
 *
 * `reward_type = 'block'` tells findblock.php to read the actual coinbase
 * value from the daemon ($aData['amount']) — this is correct across
 * halvings. `reward` below is only the fallback when reward_type is not
 * 'block'. Keep it aligned with the current mainnet-era reward so a
 * misconfig still credits miners at a sane rate.
 */
$config['reward_type'] = 'block';
$config['reward'] = 50;
$config['reward_mm'] = 32768;
$config['reward_mm1'] = 50;
$config['reward_mm2'] = 50;
$config['reward_mm3'] = 20;
$config['reward_mm4'] = 2;
$config['reward_mm5'] = 50;
$config['reward_mm6'] = 50;

/**
 * Confirmations
 *  Credit and Network confirmation settings
 *   https://github.com/MPOS/php-mpos/wiki/Config-Setup#wiki-confirmations
 */
$config['confirmations'] = 120;
$config['confirmations_mm'] = 120;
$config['confirmations_mm1'] = 100;
$config['confirmations_mm2'] = 120;
$config['confirmations_mm3'] = 460;
$config['confirmations_mm4'] = 120;
$config['confirmations_mm5'] = 120;
$config['confirmations_mm6'] = 120;
$config['network_confirmations'] = 120;
$config['network_confirmations_mm'] = 120;
$config['network_confirmations_mm1'] = 100;
$config['network_confirmations_mm2'] = 120;
$config['network_confirmations_mm3'] = 460;
$config['network_confirmations_mm4'] = 120;
$config['network_confirmations_mm5'] = 120;
$config['network_confirmations_mm6'] = 120;
// Payout txids spend mature wallet outputs. Reconcile broadcast payouts after
// normal transaction finality instead of waiting for coinbase maturity.
$config['reconcile_min_confirmations'] = 6;
/**
 * PPS
 *  Pay Per Share configuration details
 *   https://github.com/MPOS/php-mpos/wiki/Config-Setup#wiki-pps-settings
 **/
$config['pps']['reward']['default'] = 25;
$config['pps']['reward']['default_mm'] = 32768;
$config['pps']['reward']['default_mm1'] = 50;
$config['pps']['reward']['default_mm2'] = 8;
$config['pps']['reward']['default_mm3'] = 20;
$config['pps']['reward']['default_mm4'] = 2;
$config['pps']['reward']['default_mm5'] = 10;
$config['pps']['reward']['default_mm6'] = 10;
$config['pps']['reward']['type'] = 'blockavg';
$config['pps']['blockavg']['blockcount'] = 10;

/**
 * Memcache
 *  Memcache configuration details
 *   https://github.com/MPOS/php-mpos/wiki/Config-Setup#wiki-memcache
 **/
$config['memcache']['enabled'] = true;
$config['memcache']['host'] = 'localhost';
$config['memcache']['port'] = 11211;
$config['memcache']['keyprefix'] = 'mpos_';
$config['memcache']['expiration'] = 90;
$config['memcache']['splay'] = 15;
$config['memcache']['force']['contrib_shares'] = true;

/**
 * Cookies
 *  Cookie configuration details
 *   https://github.com/MPOS/php-mpos/wiki/Config-Setup#wiki-cookies
 **/
$config['cookie']['duration'] = '1440';
$config['cookie']['name'] = '';
$config['cookie']['domain'] = '';
$config['cookie']['path'] = '/';
$config['cookie']['httponly'] = true;
$config['cookie']['secure'] = false;

/**
 * Smarty Cache
 *  Enable smarty cache and cache length
 *   https://github.com/MPOS/php-mpos/wiki/Config-Setup#wiki-smarty-cache
 **/
$config['smarty']['cache'] = 0;
$config['smarty']['cache_lifetime'] = 30;

/**
 * System load
 *  Disable some calls when high system load
 *   https://github.com/MPOS/php-mpos/wiki/Config-Setup#wiki-system-load
 **/
$config['system']['load']['max'] = 100.0;

?>
