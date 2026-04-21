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

if ($setting->getValue('disable_payouts') == 1) {
  $log->logInfo(" payouts disabled via admin panel");
  $monitoring->endCronjob($cron_name, 'E0009', 0, true, false);
}
$log->logInfo("Starting Payout mm...");
if ($bitcoin_mm->can_connect() !== true) {
  $log->logFatal(" unable to connect to merge mining RPC server, exiting");
  $monitoring->endCronjob($cron_name, 'E0006', 1, true);
}
if (!$dWalletBalance = $bitcoin_mm->getbalance())
  $dWalletBalance = 0;

// Fetch our manual payouts, process them
if ($setting->getValue('disable_manual_payouts') != 1 && $aManualPayouts = $transaction_mm->getMPQueue()) {
  // Calculate our sum first
  $dMPTotalAmount = 0;
  foreach ($aManualPayouts as $aUserData) $dMPTotalAmount += $aUserData['confirmed'];
  if ($dMPTotalAmount > $dWalletBalance) {
    $log->logError("  Wallet does not cover MP payouts [MM]");
    $monitoring->endCronjob($cron_name, 'E0079', 0, true);
  }

  $log->logInfo('  found ' . count($aManualPayouts) . ' queued manual payouts');
  $mask = '    | %-10.10s | %-25.25s | %-20.20s | %-40.40s | %-20.20s |';
  $log->logInfo(sprintf($mask, 'UserID', 'Username', 'Balance', 'Address', 'Payout ID'));
  foreach ($aManualPayouts as $aUserData) {
    $transaction_id = NULL;
    $rpc_txid = NULL;
    $log->logInfo(sprintf($mask, $aUserData['id'], $aUserData['username'], $aUserData['confirmed'], $aUserData['coin_address_mm'], $aUserData['payout_id']));
    if ($bitcoin_mm->validateaddress($aUserData['coin_address_mm'])) {
      // SAFE PAYOUT FLOW: Try RPC call FIRST, only deduct balance on success
      try {
        $rpc_txid = $bitcoin_mm->sendtoaddress($aUserData['coin_address_mm'], $aUserData['confirmed'] - $config['txfee_manual']);
      } catch (Exception $e) {
        $log->logError('E0078: RPC method did not return 200 OK [MM]: Address: ' . $aUserData['coin_address_mm'] . ' ERROR: ' . $e->getMessage());
        // RPC failed - skip this payout, will retry next cron run (balance not deducted yet)
        $log->logInfo('    payout failed for user [MM] ' . $aUserData['username'] . ' - RPC error, will retry next run');
        continue;
      }
      
      // RPC succeeded - now create debit record and mark as processed
      if (!$transaction_id = $transaction_mm->createPayoutDebitRecord($aUserData['id'], $aUserData['coin_address_mm'], $aUserData['confirmed'] - $config['txfee_manual'], 'Debit_AP')) {
        $log->logFatal('    failed to fully debit user [MM] ' . $aUserData['username'] . ': ' . $transaction_mm->getCronError());
        $monitoring->endCronjob($cron_name, 'E0064', 1, true);
      }
      
      // Update transaction with RPC Transaction ID
      if (empty($rpc_txid) || !$transaction_mm->setRPCTxId($transaction_id, $rpc_txid))
        $log->logError('Unable to add RPC transaction ID [MM] ' . $rpc_txid . ' to transaction record ' . $transaction_id . ': ' . $transaction_mm->getCronError());
      
      // Mark payout as processed
      if (!$oPayout->setProcessed_mm($aUserData['payout_id'])) {
        $log->logFatal('    unable to mark transactions [MM] ' . $aUserData['id'] . ' as processed. ERROR: ' . $oPayout->getCronError());
        $monitoring->endCronjob($cron_name, 'E0010', 1, true);
      }
    } else {
      $log->logInfo('    failed to validate address for user [MM]: ' . $aUserData['username']);
      continue;
    }
  }
}

if (!$dWalletBalance = $bitcoin_mm->getbalance())
  $dWalletBalance = 0;
// Fetch our auto payouts, process them
if ($setting->getValue('disable_auto_payouts') != 1 && $aAutoPayouts = $transaction_mm->getAPQueue()) {
  // Calculate our sum first
  $dAPTotalAmount = 0;
  foreach ($aAutoPayouts as $aUserData) $dAPTotalAmount += $aUserData['confirmed'];
  if ($dAPTotalAmount > $dWalletBalance) {
    $log->logError(" Wallet does not cover AP payouts [MM]");
    $monitoring->endCronjob($cron_name, 'E0079', 0, true);
  }

  $log->logInfo('  found ' . count($aAutoPayouts) . ' queued auto payouts');
  $mask = '    | %-10.10s | %-25.25s | %-20.20s | %-40.40s | %-20.20s |';
  $log->logInfo(sprintf($mask, 'UserID', 'Username', 'Balance', 'Address', 'Threshold'));
  foreach ($aAutoPayouts as $aUserData) {
    $transaction_id = NULL;
    $rpc_txid = NULL;
    $log->logInfo(sprintf($mask, $aUserData['id'], $aUserData['username'], $aUserData['confirmed'], $aUserData['coin_address_mm'], $aUserData['ap_threshold_mm']));
    if ($bitcoin_mm->validateaddress($aUserData['coin_address_mm'])) {
      // SAFE PAYOUT FLOW: Try RPC call FIRST, only deduct balance on success
      $sendAmount = $aUserData['confirmed'] - $config['txfee_auto'];
      $log->logInfo('    [DEBUG] About to send [MM] ' . $sendAmount . ' to user ' . $aUserData['username'] . ' (confirmed: ' . $aUserData['confirmed'] . ', fee: ' . $config['txfee_auto'] . ')');
      try {
        $rpc_txid = $bitcoin_mm->sendtoaddress($aUserData['coin_address_mm'], $sendAmount);
        $log->logInfo('    [DEBUG] RPC send successful [MM], txid: ' . $rpc_txid);
      } catch (Exception $e) {
        $log->logError('E0078: RPC method did not return 200 OK [MM]: Address: ' . $aUserData['coin_address_mm'] . ' ERROR: ' . $e->getMessage());
        
        // CRITICAL: Check if coins were actually sent despite the error
        // This can happen if RPC times out after coins are sent
        $log->logInfo('    [WARNING] [MM] RPC error occurred, checking if coins were already sent...');
        sleep(5); // Wait for transaction to propagate
        
        $foundTx = null;
        $maxRetries = 3;
        $retryDelay = 10; // seconds
        
        for ($retry = 1; $retry <= $maxRetries; $retry++) {
          try {
            // Check recent transactions up to 2 hours back (for repeated RPC errors)
            // and handle balance changes by looking for approximate amount match
            $twoHoursAgo = time() - 7200; // 2 hours ago
            $recentTxs = $bitcoin_mm->listsinceblock('', 1, true);
            
            if (!empty($recentTxs['transactions'])) {
              foreach ($recentTxs['transactions'] as $tx) {
                if ($tx['category'] == 'send' && 
                    $tx['address'] == $aUserData['coin_address_mm'] && 
                    $tx['confirmations'] >= 0 &&
                    $tx['timereceived'] >= $twoHoursAgo) {
                  
                  // Check if amount is close to expected (within 50 coin tolerance for fast chains)
                  // or if transaction is very recent (within 15 minutes, likely our payout)
                  $txAge = time() - $tx['timereceived'];
                  $expectedAmount = $sendAmount; // Fixed: was -$sendAmount which doubled the diff
                  $actualAmount = abs($tx['amount']);
                  $amountDiff = abs($actualAmount - $expectedAmount);
                  
                  // For fast chains, allow 50 coin difference
                  // OR if transaction is within 15 minutes (very recent, likely our payout)
                  if ($amountDiff < 50.0 || $txAge < 900) {
                    $foundTx = $tx;
                    $log->logInfo('    [DEBUG] [MM] Found matching transaction: txid=' . $tx['txid'] . ', amount=' . $actualAmount . ', expected=' . $expectedAmount . ', age=' . round($txAge/60) . 'min, diff=' . $amountDiff);
                    break 2; // Break out of both loops
                  }
                }
              }
            }
            
            // If we found a transaction, we're done
            if ($foundTx) {
              break;
            }
            
            // No transaction found yet, retry if we have attempts left
            if ($retry < $maxRetries) {
              $log->logInfo('    [WARNING] [MM] No matching transaction found, retrying check in ' . $retryDelay . ' seconds (attempt ' . $retry . '/' . $maxRetries . ')...');
              sleep($retryDelay);
            }
            
          } catch (Exception $e2) {
            $log->logError('    [ERROR] [MM] Failed to check recent transactions (attempt ' . $retry . '/' . $maxRetries . '): ' . $e2->getMessage());
            if ($retry < $maxRetries) {
              $log->logInfo('    [WARNING] [MM] Retrying transaction check in ' . $retryDelay . ' seconds...');
              sleep($retryDelay);
            } else {
              break; // Out of retries
            }
          }
        }
        
        if ($foundTx) {
          $rpc_txid = $foundTx['txid'];
          $log->logInfo('    [CRITICAL] [MM] Coins WERE sent despite error! txid: ' . $rpc_txid);
          $log->logInfo('    [CRITICAL] [MM] Proceeding with debit record creation to prevent duplicate payout');
          // Continue to debit record creation below
        } else {
          $log->logInfo('    payout failed for user [MM] ' . $aUserData['username'] . ' - RPC error, will retry next run');
          continue;
        }
      }
      
      // RPC succeeded - now create debit record
      $log->logInfo('    [DEBUG] Creating debit record [MM] for user ' . $aUserData['username'] . ', amount: ' . $sendAmount);
      $transaction_id = $transaction_mm->createPayoutDebitRecord($aUserData['id'], $aUserData['coin_address_mm'], $sendAmount, 'Debit_AP');
      if ($transaction_id === false || $transaction_id === null || $transaction_id === 0) {
        $error = $transaction_mm->getCronError();
        $log->logFatal('    [CRITICAL] FAILED to create debit record [MM] for user ' . $aUserData['username'] . ': ' . $error);
        $log->logFatal('    [CRITICAL] Coins were sent (txid: ' . $rpc_txid . ') but NO DEBIT RECORD CREATED!');
        $monitoring->endCronjob($cron_name, 'E0064', 1, true);
      }
      $log->logInfo('    [DEBUG] Debit record created successfully [MM], transaction_id: ' . $transaction_id);
      
      // Update transaction with RPC Transaction ID
      if (empty($rpc_txid) || !$transaction_mm->setRPCTxId($transaction_id, $rpc_txid)) {
        $log->logError('    [WARNING] Unable to add RPC transaction ID [MM] ' . $rpc_txid . ' to transaction record ' . $transaction_id . ': ' . $transaction_mm->getCronError());
        $log->logError('    [WARNING] Payout completed [MM] but txid not recorded in database');
      } else {
        $log->logInfo('    [DEBUG] RPC txid recorded successfully [MM]');
      }
      
      $log->logInfo('    [SUCCESS] Payout completed [MM] for user ' . $aUserData['username'] . ' - sent: ' . $sendAmount . ', txid: ' . $rpc_txid . ', tx_record: ' . $transaction_id);
    } else {
      $log->logInfo('    failed to validate address for user [MM]: ' . $aUserData['username']);
      continue;
    }
  }
}

require_once('cron_end.inc.php');
