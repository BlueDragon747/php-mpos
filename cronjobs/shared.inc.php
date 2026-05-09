<?php

/*

Copyright:: 2013, Sebastian Grewe

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

 */

define('SECURITY', '*)WT#&YHfd');
// Whether or not to check SECHASH for validity, still checks if SECURITY defined as before if disabled
define('SECHASH_CHECK', false);

// PHP cronjobs are the production scheduler. The cronjobs-py rewrite is
// in development and gated behind MPOS_PYTHON_CRONJOBS_ACTIVE — until
// the Wave 0..4 plan in QC_POOL_UPDATE_2026-04-25.md lands, PHP cron is
// authoritative.
//
// Running both schedulers against the same DB produces double-credits
// and (worse) double on-chain payouts, since both stacks insert Credit
// / Debit_AP rows against the same DB. We refuse to run if the operator
// has explicitly flipped the cronjobs-py service to active — they need
// to disable one or the other before either runs again.
if (getenv('MPOS_PYTHON_CRONJOBS_ACTIVE') === '1' &&
    getenv('MPOS_PHP_CRONJOBS_OPT_IN') !== '1') {
    fwrite(STDERR,
        "MPOS PHP cronjobs are disabled — cronjobs-py has been activated.\n" .
        "If you really need to run this cronjob ad-hoc (e.g. emergency\n" .
        "reconciliation, data migration, dev work), set:\n" .
        "    MPOS_PHP_CRONJOBS_OPT_IN=1\n" .
        "in the environment first. WARNING: doing so while the cronjobs-py\n" .
        "service is running will cause double-payouts.\n"
    );
    exit(2);
}

// Nothing below here to configure, move along...

// change SECHASH every second, we allow up to 3 sec back for slow servers
if (SECHASH_CHECK) {
  function fip($tr=0) { return md5(SECURITY.(time()-$tr).SECURITY); }
  define('SECHASH', fip());
  function cfip() { return (fip()==SECHASH||fip(1)==SECHASH||fip(2)==SECHASH) ? 1 : 0; }
} else {
  function cfip() { return (@defined('SECURITY')) ? 1 : 0; }
}

// MODIFY THIS
// We need to find our include files so set this properly
define("BASEPATH", "../public/");

/*****************************************************
 * No need to change beyond this point               *
 *****************************************************/

// Used in autoloading of API class, adding it to stop PHP warnings
$dStartTime = microtime(true);

// Our cron name
$cron_name = basename($_SERVER['PHP_SELF'], '.php');

// Include our configuration (holding defines for the requires)
require_once(BASEPATH . 'include/config/global.inc.dist.php');
require_once(BASEPATH . 'include/config/global.inc.php');

require_once(BASEPATH . 'include/config/security.inc.dist.php');
@include_once(BASEPATH . 'include/config/security.inc.php');

require_once(BASEPATH . 'include/bootstrap.php');
require_once(BASEPATH . 'include/version.inc.php');

// Command line switches
array_shift($argv);
foreach ($argv as $option) {
  switch ($option) {
  case '-f':
    $monitoring->setStatus($cron_name . "_disabled", "yesno", 0);
    // Clear the monitoring status cache so the new value is read
    $monitoring->clearCache();
    break;
  }
}

// Load 3rd party logging library for running crons
$log = KLogger::instance( 'logs/' . $cron_name, KLogger::INFO );
$log->LogDebug('Starting ' . $cron_name);

// Load the start time for later runtime calculations for monitoring
$cron_start[$cron_name] = microtime(true);

// Check if our cron is activated
if ($monitoring->isDisabled($cron_name)) {
  $log->logFatal('Cronjob is currently disabled due to errors, use -f option to force running cron.');
  $monitoring->endCronjob($cron_name, 'E0018', 1, true, false);
}

// Mark cron as running for monitoring
$log->logDebug('Marking cronjob as running for monitoring');
$monitoring->setStatus($cron_name . '_starttime', 'date', time());

// Check if we need to halt our crons due to an outstanding upgrade
if ($setting->getValue('DB_VERSION') != DB_VERSION || $config['version'] != CONFIG_VERSION) {
  $log->logFatal('Cronjob is currently disabled due to required upgrades. Import any outstanding SQL files and check your configuration file.');
  $monitoring->endCronjob($cron_name, 'E0075', 0, true, false);
}

?>
