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
$config['SALT'] = 'SOMEONEPLEASEMAKEMESOMETHINGRANDOM';
$config['SALTY'] = 'SOMEONETHISSHOULDALSOBERRAANNDDOOM'; 

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
$config['db']['pass'] = 'dbpass';
$config['db']['port'] = 3306;
$config['db']['name'] = 'mpos';

/**
 * Local wallet RPC
 *  RPC configuration for your daemon/wallet
 *   https://github.com/MPOS/php-mpos/wiki/Config-Setup#wiki-local-wallet-rpc
 **/
$config['wallet']['type'] = 'http';
$config['wallet']['host'] = 'localhost:8772';
$config['wallet']['username'] = 'rpcuser';
$config['wallet']['password'] = 'rpcpass';

$config['wallet_mm']['type'] = 'http';
$config['wallet_mm']['host'] = 'localhost:8494';
$config['wallet_mm']['username'] = 'rpcuser';
$config['wallet_mm']['password'] = 'rpcpass';

$config['wallet_mm1']['type'] = 'http';
$config['wallet_mm1']['host'] = 'localhost:8243';
$config['wallet_mm1']['username'] = 'rpcuser';
$config['wallet_mm1']['password'] = 'rpcpass';

$config['wallet_mm2']['type'] = 'http';
$config['wallet_mm2']['host'] = 'localhost:42024';
$config['wallet_mm2']['username'] = 'tba1';
$config['wallet_mm2']['password'] = 'x';

$config['wallet_mm3']['type'] = 'http';
$config['wallet_mm3']['host'] = 'localhost:6852';
$config['wallet_mm3']['username'] = 'rpcuser';
$config['wallet_mm3']['password'] = 'rpcpass';

$config['wallet_mm4']['type'] = 'http';
$config['wallet_mm4']['host'] = 'localhost:19738';
$config['wallet_mm4']['username'] = 'rpcuser';
$config['wallet_mm4']['password'] = 'rpcpass';

$config['wallet_mm5']['type'] = 'http';
$config['wallet_mm5']['host'] = 'localhost:12005';
$config['wallet_mm5']['username'] = 'rpcuser';
$config['wallet_mm5']['password'] = 'rpcpass';

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
$config['gettingstarted']['stratumurl'] = 'http://eu3.blakecoin.com/';
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
$config['ap_threshold_mm1']['max'] = 25;

$config['ap_threshold_mm2']['min'] = 0.01;
$config['ap_threshold_mm2']['max'] = 9999;

$config['ap_threshold_mm3']['min'] = 1;
$config['ap_threshold_mm3']['max'] = 1000;

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
 * Currency
 *  Shorthand name for the currency
 *   https://github.com/MPOS/php-mpos/wiki/Config-Setup#wiki-currency
 */
$config['currency'] = 'BLC';
$config['currency_mm'] = 'PHO';
$config['currency_mm1'] = 'BBTC';
$config['currency_mm2'] = 'unused1';
$config['currency_mm3'] = 'ELT';
$config['currency_mm4'] = 'UMO';
$config['currency_mm5'] = 'LIT';
$config['currency_mm6'] = 'unused2';


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
$config['sendmany']['enabled'] = true;

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
$config['pplns']['shares']['default'] = 9000;
$config['pplns']['shares']['type'] = 'blockavg';
$config['pplns']['blockavg']['blockcount'] = 3;
$config['pplns']['reverse_payout'] = false;
$config['pplns']['dynamic']['percent'] = 10;

/**
 * Difficulty  sha256d: 16  scrypt: 20  diff_32: 21 diff_256: 24 diff_512: 25 diff_1024: 26 diff_2048: 27
 *  Difficulty setting for stratum/pushpool
 *   https://github.com/MPOS/php-mpos/wiki/Config-Setup#wiki-pool-target-difficulty
 */
$config['difficulty'] = 25;

/**
 * Block Reward
 *  Block reward configuration details
 *   https://github.com/MPOS/php-mpos/wiki/Config-Setup#wiki-reward-settings
 **/
$config['reward_type'] = 'block';
$config['reward'] = 25;
$config['reward_mm'] = 32768;
$config['reward_mm1'] = 25;
$config['reward_mm2'] = 1.25;
$config['reward_mm3'] = 10;
$config['reward_mm4'] = 2;
$config['reward_mm5'] = 48;
$config['reward_mm6'] = 50;

/**
 * Confirmations
 *  Credit and Network confirmation settings
 *   https://github.com/MPOS/php-mpos/wiki/Config-Setup#wiki-confirmations
 */
$config['confirmations'] = 140;
$config['confirmations_mm'] = 140;
$config['confirmations_mm1'] = 120;
$config['confirmations_mm2'] = 140;
$config['confirmations_mm3'] = 480;
$config['confirmations_mm4'] = 140;
$config['confirmations_mm5'] = 140;
$config['confirmations_mm6'] = 140;
$config['network_confirmations'] = 120;
$config['network_confirmations_mm'] = 120;
$config['network_confirmations_mm1'] = 100;
$config['network_confirmations_mm2'] = 120;
$config['network_confirmations_mm3'] = 460;
$config['network_confirmations_mm4'] = 120;
$config['network_confirmations_mm5'] = 120;
$config['network_confirmations_mm6'] = 120;
/**
 * PPS
 *  Pay Per Share configuration details
 *   https://github.com/MPOS/php-mpos/wiki/Config-Setup#wiki-pps-settings
 **/
$config['pps']['reward']['default'] = 25;
$config['pps']['reward']['default_mm'] = 32768;
$config['pps']['reward']['default_mm1'] = 25;
$config['pps']['reward']['default_mm2'] = 1.25;
$config['pps']['reward']['default_mm3'] = 10;
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
$config['memcache']['force']['contrib_shares'] = false;

/**
 * Cookies
 *  Cookie configuration details
 *   https://github.com/MPOS/php-mpos/wiki/Config-Setup#wiki-cookies
 **/
$config['cookie']['duration'] = '1440';
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
$config['system']['load']['max'] = 10.0;

?>
