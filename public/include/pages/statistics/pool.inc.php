<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

// Fetch data from wallet, always run this check
if ($bitcoin->can_connect() === true){
  $dDifficulty = $bitcoin->getdifficulty();
  $dNetworkHashrate = $bitcoin->getnetworkhashps();
  $iBlock = $bitcoin->getblockcount();
  is_int($iBlock) && $iBlock > 0 ? $sBlockHash = $bitcoin->getblockhash($iBlock) : $sBlockHash = '';
} else {
  $dDifficulty = 1;
  $dNetworkHashrate = 1;
  $iBlock = 0;
  $_SESSION['POPUP'][] = array('CONTENT' => 'Unable to connect to wallet RPC service: ' . $bitcoin->can_connect(), 'TYPE' => 'errormsg');
}

if (!$smarty->isCached('master.tpl', $smarty_cache_key)) {
  $debug->append('No cached version available, fetching from backend', 3);

  // Top share contributors
  $aContributorsShares = $statistics->getTopContributors('shares', 15);

  // Top hash contributors
  $aContributorsHashes = $statistics->getTopContributors('hashes', 15);

  // Merge into a single combined contributors list keyed by account.
  // Hashrate roster wins ordering (it's typically the primary stat);
  // shares are looked up from the shares roster where available.
  $byAcct = array();
  if (is_array($aContributorsHashes)) {
    foreach ($aContributorsHashes as $r) {
      if (!isset($r['account'])) continue;
      $r['shares']   = isset($r['shares'])   ? (int)$r['shares']   : 0;
      $r['hashrate'] = isset($r['hashrate']) ? (float)$r['hashrate'] : 0;
      $byAcct[$r['account']] = $r;
    }
  }
  if (is_array($aContributorsShares)) {
    foreach ($aContributorsShares as $r) {
      if (!isset($r['account'])) continue;
      if (isset($byAcct[$r['account']])) {
        $byAcct[$r['account']]['shares'] = isset($r['shares']) ? (int)$r['shares'] : 0;
      } else {
        $r['shares']   = isset($r['shares'])   ? (int)$r['shares']   : 0;
        $r['hashrate'] = isset($r['hashrate']) ? (float)$r['hashrate'] : 0;
        $byAcct[$r['account']] = $r;
      }
    }
  }
  $aContributors = array_values($byAcct);

  // Last 10 blocks found, merged across BLC + every active aux slot.
  // UNION ALL across blocks_<slot> tables, time-ordered. Each row is
  // tagged with `chain` (uppercase ticker) and `slot` (suffix) so the
  // template can render a coin column and the explorer deep-link.
  // Pattern mirrors the multi-chain pager in statistics/blocks.inc.php.
  $iLimit = 10;
  $aPoolActiveSlots = array();
  $aPoolActiveSlots[$config['currency']] = '';
  foreach (array('mm','mm1','mm2','mm3','mm4','mm5','mm6') as $s) {
    $tk = isset($config['currency_' . $s]) ? $config['currency_' . $s] : '';
    if ($tk !== '' && stripos($tk, 'unused') === false) {
      $aPoolActiveSlots[$tk] = $s;
    }
  }
  $aPoolUnions = array();
  foreach ($aPoolActiveSlots as $sTicker => $sSuffix) {
    $sBlocksTbl = 'blocks' . ($sSuffix !== '' ? '_' . $sSuffix : '');
    $sTickerSql = $mysqli->real_escape_string($sTicker);
    $aPoolUnions[] = "
      SELECT b.id, b.height, b.blockhash, b.confirmations, b.amount,
             b.difficulty, b.time, b.shares, b.account_id,
             a.username      AS finder,
             a.is_anonymous  AS is_anonymous,
             '{$sTickerSql}' AS chain,
             '{$sSuffix}'    AS slot
      FROM {$sBlocksTbl} AS b
      INNER JOIN " . $user->getTableName() . " AS a ON b.account_id = a.id
    ";
  }
  $sPoolSql = '(' . implode(' UNION ALL ', $aPoolUnions)
            . ') AS u ORDER BY u.time DESC LIMIT ' . (int)$iLimit;
  $aBlocksFoundData = array();
  if ($oRes = $mysqli->query("SELECT * FROM $sPoolSql")) {
    while ($r = $oRes->fetch_assoc()) $aBlocksFoundData[] = $r;
    $oRes->free();
  }
  count($aBlocksFoundData) > 0 ? $aBlockData = $aBlocksFoundData[0] : $aBlockData = array();

  // Estimated time to find the next block
  $iCurrentPoolHashrate =  $statistics->getCurrentHashrate();

  // Time in seconds, not hours, using modifier in smarty to translate
  $iCurrentPoolHashrate > 0 ? $iEstTime = $dDifficulty * pow(2,32) / ($iCurrentPoolHashrate * 1000) : $iEstTime = 0;

  // Time since last block
  if (!empty($aBlockData)) {
    $dTimeSinceLast = (time() - $aBlockData['time']);
    if ($dTimeSinceLast < 0) $dTimeSinceLast = 0;
  } else {
    $dTimeSinceLast = 0;
  }

  // Block average reward or fixed
  $reward = $config['reward_type'] == 'fixed' ? $config['reward'] : $block->getAverageAmount();

    // Round progress
  $iEstShares = $statistics->getEstimatedShares($dDifficulty);
  $aRoundShares = $statistics->getRoundShares();
  if ($iEstShares > 0 && $aRoundShares['valid'] > 0) {
    $dEstPercent = round(100 / $iEstShares * $aRoundShares['valid'], 2);
  } else {
    $dEstPercent = 0;
  }

  $dExpectedTimePerBlock = $statistics->getNetworkExpectedTimePerBlock();
  $dEstNextDifficulty = $statistics->getExpectedNextDifficulty();
  $iBlocksUntilDiffChange = $statistics->getBlocksUntilDiffChange();

  // ---- Per-coin General Statistics ------------------------------------
  // For each active slot (BLC + 5 mergemine), fetch the daemon-side
  // network stats (difficulty / network hashrate / current block / next-
  // diff bookkeeping) and the per-coin last-block-found row from the
  // matching blocks_<slot> table. Pool-wide stats (Pool Hash Rate,
  // Active Workers, Pool Efficiency) are merge-mined and identical
  // across coins, so they stay outside the tab and aren't packed here.
  //
  // Resilient to RPC failures: a missing daemon yields zeros for that
  // coin's network stats but doesn't break the page. Each $bitcoin_<s>
  // wrapper carries its own can_connect() guard.
  $iTargetBits = isset($config['target_bits']) ? (int)$config['target_bits'] : 32;
  $aStatsByCoin = array();
  foreach ($aPoolActiveSlots as $sTicker => $sSuffix) {
    $sCfgSuffix = ($sSuffix === '') ? '' : ('_' . $sSuffix);
    $oRpc       = ($sSuffix === '') ? $bitcoin : (isset($GLOBALS['bitcoin' . $sCfgSuffix]) ? $GLOBALS['bitcoin' . $sCfgSuffix] : null);
    $iCointarget       = isset($config['cointarget' . $sCfgSuffix])           ? (int)$config['cointarget' . $sCfgSuffix]           : 150;
    $iDiffChangeTarget = isset($config['coindiffchangetarget' . $sCfgSuffix]) ? (int)$config['coindiffchangetarget' . $sCfgSuffix] : 2016;

    $dDiffC      = 1;
    $dNetHashC   = 1;
    $iBlockC     = 0;
    $sBlockHashC = '';
    if ($oRpc !== null) {
      try {
        if ($oRpc->can_connect() === true) {
          $dDiffC    = (float)$oRpc->getdifficulty();
          $dNetHashC = (float)$oRpc->getnetworkhashps();
          $iBlockC   = (int)$oRpc->getblockcount();
          if ($iBlockC > 0) $sBlockHashC = (string)$oRpc->getblockhash($iBlockC);
        }
      } catch (Exception $e) {
        $debug->append('Pool stats per-coin RPC error for ' . $sTicker . ': ' . $e->getMessage(), 2);
      }
    }
    if ($dNetHashC <= 0) $dNetHashC = 1;
    if ($dDiffC    <= 0) $dDiffC    = 1;

    $dExpectedC      = pow(2, 32) * $dDiffC / $dNetHashC;
    $dEstNextDiffC   = round($dDiffC * $iCointarget / $dExpectedC, 8);
    $iBlocksUntilC   = $iDiffChangeTarget - ($iBlockC % max(1, $iDiffChangeTarget));
    $iEstSharesC     = round((pow(2, 32 - $iTargetBits) * $dDiffC) / pow(2, ($config['difficulty'] - 16)));
    $dEstPctC        = ($iEstSharesC > 0 && $aRoundShares['valid'] > 0)
                       ? round(100 / $iEstSharesC * $aRoundShares['valid'], 2) : 0;
    $iAvgPoolTimeC   = ($iCurrentPoolHashrate > 0) ? ($dDiffC * pow(2, 32) / ($iCurrentPoolHashrate * 1000)) : 0;

    // Last per-coin block from blocks_<slot>; null if the chain has
    // never produced a pool-found block yet.
    $sBlocksTbl = 'blocks' . $sCfgSuffix;
    $iLastBlockC = 0; $sLastBlockHashC = ''; $iLastBlockTimeC = 0;
    if ($oRes = $mysqli->query("SELECT height, blockhash, time FROM {$sBlocksTbl} ORDER BY id DESC LIMIT 1")) {
      if ($r = $oRes->fetch_assoc()) {
        $iLastBlockC     = (int)$r['height'];
        $sLastBlockHashC = (string)$r['blockhash'];
        $iLastBlockTimeC = (int)$r['time'];
      }
      $oRes->free();
    }
    $iTimeSinceLastC = $iLastBlockTimeC > 0 ? max(0, time() - $iLastBlockTimeC) : 0;

    $aStatsByCoin[$sTicker] = array(
      'chain'                  => $sTicker,
      'slot'                   => $sSuffix,
      'difficulty'             => $dDiffC,
      'EstNextDifficulty'      => $dEstNextDiffC,
      'BlocksUntilDiffChange'  => $iBlocksUntilC,
      'EstTimePerBlock'        => $dExpectedC,
      'EstShares'              => $iEstSharesC,
      'EstPercent'             => $dEstPctC,
      'AvgPoolTime'            => $iAvgPoolTimeC,
      'CurrentBlock'           => $iBlockC,
      'CurrentBlockHash'       => $sBlockHashC,
      'LastBlock'              => $iLastBlockC,
      'LastBlockHash'          => $sLastBlockHashC,
      'TimeSinceLast'          => $iTimeSinceLastC,
    );
  }
  $smarty->assign("STATS_BY_COIN", $aStatsByCoin);
  $smarty->assign("COIN_TICKERS",  array_keys($aPoolActiveSlots));
  $smarty->assign("COIN_NAMES",    array(
    'BLC'  => isset($config['gettingstarted']['coinname']) ? (string)$config['gettingstarted']['coinname'] : 'Blakecoin',
    'PHO'  => 'Photon',
    'BBTC' => 'BlakeBitcoin',
    'LIT'  => 'Lithium',
    'ELT'  => 'Electron',
    'UMO'  => 'Universalmolecule',
  ));

  // Propagate content our template
  $smarty->assign("ESTTIME", $iEstTime);
  $smarty->assign("TIMESINCELAST", $dTimeSinceLast);
  $smarty->assign("BLOCKSFOUND", $aBlocksFoundData);
  $smarty->assign("BLOCKLIMIT", $iLimit);
  $smarty->assign("CONTRIBSHARES", $aContributorsShares);
  $smarty->assign("CONTRIBHASHES", $aContributorsHashes);
  $smarty->assign("CONTRIBUTORS",  $aContributors);
  $smarty->assign("CURRENTBLOCK", $iBlock);
  $smarty->assign("CURRENTBLOCKHASH", @$sBlockHash);
  $smarty->assign('NETWORK', array('difficulty' => $dDifficulty, 'block' => $iBlock, 'EstNextDifficulty' => $dEstNextDifficulty, 'EstTimePerBlock' => $dExpectedTimePerBlock, 'BlocksUntilDiffChange' => $iBlocksUntilDiffChange));
  $smarty->assign('ESTIMATES', array('shares' => $iEstShares, 'percent' => $dEstPercent));
  if (count($aBlockData) > 0) {
    $smarty->assign("LASTBLOCK", $aBlockData['height']);
    $smarty->assign("LASTBLOCKHASH", $aBlockData['blockhash']);
  } else {
    $smarty->assign("LASTBLOCK", 0);
  }
  $smarty->assign("DIFFICULTY", $dDifficulty);
  $smarty->assign("REWARD", $reward);
} else {
  $debug->append('Using cached page', 3);
}


// Public / private page detection
if ($setting->getValue('acl_pool_statistics')) {
  $smarty->assign("CONTENT", "default.tpl");
} else if ($user->isAuthenticated() && ! $setting->getValue('acl_pool_statistics')) {
  $smarty->assign("CONTENT", "default.tpl");
} else {
  $smarty->assign("CONTENT", "../default.tpl");
}
?>
