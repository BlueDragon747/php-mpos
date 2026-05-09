#!/usr/bin/php
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

// Change to working directory
chdir(dirname(__FILE__));

// Include all settings and classes
require_once('shared.inc.php');

if ( $bitcoin->can_connect() !== true ) {
  $log->logFatal("Failed to connect to RPC server\n");
  $monitoring->endCronjob($cron_name, 'E0006', 1, true);
}

// Fetch all unconfirmed blocks
$aAllBlocks = $block->getAllUnconfirmed(max($config['network_confirmations'],$config['confirmations']));

$header = false;
foreach ($aAllBlocks as $iIndex => $aBlock) {
  !$header ? $log->logInfo("ID\tHeight\tBlockhash\tConfirmations") : $header = true;
  try {
    $aBlockInfo = $bitcoin->getblock($aBlock['blockhash']);
  } catch (Exception $e) {
    $log->logError("    getblock({$aBlock['blockhash']}) RPC exception; skipping: " . $e->getMessage());
    continue;
  }
  // Defensive: an RPC error or unexpected shape (e.g. unknown
  // blockhash, daemon mid-restart) used to abort the whole loop and
  // leave subsequent blocks' confirmations stale. Skip the offending
  // row instead and keep going.
  if (!is_array($aBlockInfo) || !isset($aBlockInfo['confirmations'])) {
    $log->logError("    getblock({$aBlock['blockhash']}) returned no usable info; skipping");
    continue;
  }
  // tx[] may be empty on some pruned/special blocks. Guard before
  // dereferencing.
  $isOrphan = false;
  if (isset($aBlockInfo['tx'][0])) {
    try {
      $aTxDetails = $bitcoin->gettransaction($aBlockInfo['tx'][0]);
    } catch (Exception $e) {
      $log->logError("    gettransaction({$aBlockInfo['tx'][0]}) RPC exception; skipping orphan check: " . $e->getMessage());
      $aTxDetails = null;
    }
    if (is_array($aTxDetails)
        && isset($aTxDetails['details'][0]['category'])
        && $aTxDetails['details'][0]['category'] === 'orphan') {
      $isOrphan = true;
    }
  }
  $log->logInfo($aBlock['id'] . "\t" . $aBlock['height'] .  "\t" . $aBlock['blockhash'] . "\t" . $aBlock['confirmations'] . " -> " . $aBlockInfo['confirmations']);
  if ($isOrphan) {
    if ($block->setConfirmations($aBlock['id'], -1)) {
      $log->logInfo("    Block marked as orphan");
    } else {
      $log->logError("    Block became orphaned but unable to update database entries");
    }
    continue;
  }
  if ($aBlock['confirmations'] == $aBlockInfo['confirmations']) {
    $log->logDebug('    No update needed');
  } else if (!$block->setConfirmations($aBlock['id'], $aBlockInfo['confirmations'])) {
    $log->logError('    Failed to update block confirmations: ' . $block->getCronMessage());
  }
}

require_once('cron_end.inc.php');
?>
