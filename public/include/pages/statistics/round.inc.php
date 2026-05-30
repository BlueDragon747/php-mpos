<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

if (!$smarty->isCached('master.tpl', $smarty_cache_key)) {
  $debug->append('No cached version available, fetching from backend', 3);

  // Resolve ?coin=<TICKER> → slot suffix so the page can query the
  // right per-coin tables. Empty suffix = parent (BLC). Unknown or
  // missing tickers fall back to the parent.
  $sRoundCoin = isset($_REQUEST['coin']) ? strtoupper(trim($_REQUEST['coin'])) : '';
  $aSlotMap = array('' => $config['currency']);
  foreach (array('mm','mm1','mm2','mm3','mm4','mm5','mm6') as $s) {
    $tk = isset($config['currency_' . $s]) ? $config['currency_' . $s] : '';
    if ($tk !== '' && stripos($tk, 'unused') === false) $aSlotMap[$s] = $tk;
  }
  $aTickerToSlot = array_flip($aSlotMap);
  if ($sRoundCoin === '' || !isset($aTickerToSlot[$sRoundCoin])) {
    $sRoundCoin = $config['currency'];
    $sCoinSlot  = '';
  } else {
    $sCoinSlot = $aTickerToSlot[$sRoundCoin];
  }
  $sRoundConfirmKey = ($sCoinSlot === '') ? 'confirmations' : ('confirmations_' . $sCoinSlot);
  $iRoundConfirmations = isset($config[$sRoundConfirmKey])
    ? (int)$config[$sRoundConfirmKey]
    : (int)$config['confirmations'];
  $sBlocksTable = $sCoinSlot === '' ? 'blocks'       : ('blocks_'       . $sCoinSlot);
  $sTransTable  = $sCoinSlot === '' ? 'transactions' : ('transactions_' . $sCoinSlot);

  // Pick the right Block instance for getLast() / getAvgBlockShares().
  $oBlockSlot = $block;
  if ($sCoinSlot !== '') {
    $sBlockVar = 'block_' . $sCoinSlot;
    if (isset($$sBlockVar)) $oBlockSlot = $$sBlockVar;
  }

  $fetchHeightOne = function($sql, $iVal) use ($mysqli) {
    $stmt = $mysqli->prepare($sql);
    if (!$stmt) return 0;
    $stmt->bind_param('i', $iVal);
    $iOut = 0;
    if ($stmt->execute() && ($r = $stmt->get_result())) {
      if ($row = $r->fetch_object()) $iOut = (int)$row->height;
    }
    $stmt->close();
    return $iOut;
  };

  if (@$_REQUEST['search']) {
    if ($sCoinSlot === '') {
      $_REQUEST['height'] = $roundstats->searchForBlockHeight($_REQUEST['search']);
    } else {
      $_REQUEST['height'] = $fetchHeightOne(
        "SELECT height FROM $sBlocksTable WHERE height >= ? ORDER BY height ASC LIMIT 1",
        (int)$_REQUEST['search']);
    }
  }
  if (@$_REQUEST['next'] && !empty($_REQUEST['height'])) {
    if ($sCoinSlot === '') {
      $iHeight = @$roundstats->getNextBlock($_REQUEST['height']);
    } else {
      $iHeight = $fetchHeightOne(
        "SELECT height FROM $sBlocksTable WHERE height > ? ORDER BY height ASC LIMIT 1",
        (int)$_REQUEST['height']);
    }
    if (!$iHeight) {
      $iBlock  = $oBlockSlot->getLast();
      $iHeight = isset($iBlock['height']) ? $iBlock['height'] : 0;
    }
  } else if (@$_REQUEST['prev'] && !empty($_REQUEST['height'])) {
    if ($sCoinSlot === '') {
      $iHeight = $roundstats->getPreviousBlock($_REQUEST['height']);
    } else {
      $iHeight = $fetchHeightOne(
        "SELECT height FROM $sBlocksTable WHERE height < ? ORDER BY height DESC LIMIT 1",
        (int)$_REQUEST['height']);
    }
  } else if (empty($_REQUEST['height'])) {
    $iBlock  = $oBlockSlot->getLast();
    $iHeight = isset($iBlock['height']) ? $iBlock['height'] : 0;
  } else {
    $iHeight = $_REQUEST['height'];
  }
  $_REQUEST['height'] = $iHeight;

  $iPPLNSShares = 0;

  // Block details: BLC uses $roundstats unchanged; aux runs inline SQL
  // against blocks_<slot>.
  if ($sCoinSlot === '') {
    $aDetailsForBlockHeight = $roundstats->getDetailsForBlockHeight($iHeight);
  } else {
    $iDifficulty = (int)$config['difficulty'];
    $aDetailsForBlockHeight = array();
    if ($stmt = $mysqli->prepare(
      "SELECT b.id, b.height, b.blockhash, b.amount, b.confirmations,
              b.difficulty, FROM_UNIXTIME(b.time) AS time, b.shares,
              IF(a.is_anonymous, 'anonymous', a.username) AS finder,
              ROUND((b.difficulty * 65535) / POW(2, ($iDifficulty - 16)), 0) AS estshares,
              (b.time - (SELECT time FROM $sBlocksTable WHERE height < ? ORDER BY height DESC LIMIT 1)) AS round_time
         FROM $sBlocksTable AS b
         LEFT JOIN accounts AS a ON b.account_id = a.id
        WHERE b.height = ?
        LIMIT 1")) {
      $stmt->bind_param('ii', $iHeight, $iHeight);
      if ($stmt->execute() && ($r = $stmt->get_result())) {
        $aDetailsForBlockHeight = $r->fetch_assoc() ?: array();
      }
      $stmt->close();
    }
  }
  if (is_array($aDetailsForBlockHeight)) {
    $aDetailsForBlockHeight['confirmations_required'] = $iRoundConfirmations;
  }

  // Per-account round shares come from `shares_archive` (per-share
  // detail rows that already have block_id stamped on them) rather
  // than `statistics_shares` — the cronjobs-py rewrite stopped writing
  // statistics_shares so the legacy $roundstats->getRoundStatsForAccounts
  // returns empty for any block past the cutover. shares_archive is
  // populated per-block for both parent and aux paths.
  //
  // For aux blocks we resolve the originating share_id back to the
  // parent block_id (blocks_<slot>.share_id → shares_archive.share_id
  // → shares_archive.block_id), then aggregate the same way as parent.
  // Worker-suffixed usernames ("admin.1111") are split on the first
  // dot so they group under the account they belong to.
  $iParentBlockId = 0;
  if ($sCoinSlot === '') {
    if ($stmt = $mysqli->prepare("SELECT id FROM blocks WHERE height = ? LIMIT 1")) {
      $stmt->bind_param('i', $iHeight);
      if ($stmt->execute() && ($r = $stmt->get_result())) {
        if ($row = $r->fetch_object()) $iParentBlockId = (int)$row->id;
      }
      $stmt->close();
    }
  } else {
    if ($stmt = $mysqli->prepare(
      "SELECT sa.block_id AS pid
         FROM $sBlocksTable AS bm
         LEFT JOIN shares_archive AS sa ON bm.share_id = sa.share_id
        WHERE bm.height = ? LIMIT 1")) {
      $stmt->bind_param('i', $iHeight);
      if ($stmt->execute() && ($r = $stmt->get_result())) {
        if ($row = $r->fetch_object()) $iParentBlockId = (int)$row->pid;
      }
      $stmt->close();
    }
  }

  $aRoundShareStats = array();
  if ($iParentBlockId > 0) {
    if ($stmt = $mysqli->prepare(
      "SELECT a.id, a.username, a.is_anonymous,
              SUM(s.our_result = 'Y') AS valid,
              SUM(s.our_result = 'N') AS invalid
         FROM shares_archive AS s
         INNER JOIN accounts AS a ON SUBSTRING_INDEX(s.username, '.', 1) = a.username
        WHERE s.block_id = ?
        GROUP BY a.id, a.username, a.is_anonymous
        HAVING valid > 0
        ORDER BY valid DESC")) {
      $stmt->bind_param('i', $iParentBlockId);
      if ($stmt->execute() && ($r = $stmt->get_result())) {
        while ($row = $r->fetch_assoc()) {
          $aRoundShareStats[$row['id']] = $row;
        }
      }
      $stmt->close();
    }
  }

  // Round transactions: per-slot table for both BLC and aux.
  $aUserRoundTransactions = array();
  if ($stmt = $mysqli->prepare(
    "SELECT t.id AS id, a.id AS uid, a.username AS username,
            a.is_anonymous, t.type AS type, t.amount AS amount
       FROM $sTransTable AS t
       LEFT JOIN $sBlocksTable AS b ON t.block_id = b.id
       LEFT JOIN accounts AS a ON t.account_id = a.id
      WHERE b.height = ? AND t.type = 'Credit'
      ORDER BY amount DESC")) {
    $stmt->bind_param('i', $iHeight);
    if ($stmt->execute() && ($r = $stmt->get_result())) {
      $aUserRoundTransactions = $r->fetch_all(MYSQLI_ASSOC);
    }
    $stmt->close();
  }

  if ($config['payout_system'] == 'pplns') {
    // PPLNS shares are read from `pplns_shares` (slot-aware,
    // populated by cronjobs-py at payout time). Replaces the legacy
    // BLC-only `statistics_shares` reader, which the cronjobs-py
    // rewrite stopped writing post-cutover (2026-04-27).
    //
    // For BLC the block_id is the parent blocks.id ($iParentBlockId);
    // for aux it's the aux blocks_<slot>.id from the details query.
    $iSlotBlockId = ($sCoinSlot === '')
      ? $iParentBlockId
      : (isset($aDetailsForBlockHeight['id']) ? (int)$aDetailsForBlockHeight['id'] : 0);
    $aPPLNSRoundShares = array();
    if ($iSlotBlockId > 0) {
      if ($stmt = $mysqli->prepare(
        "SELECT a.username, a.is_anonymous,
                ps.pplns_valid, ps.pplns_invalid
           FROM pplns_shares AS ps
           INNER JOIN accounts AS a ON a.id = ps.account_id
          WHERE ps.slot = ? AND ps.block_id = ?
          ORDER BY ps.pplns_valid DESC")) {
        $stmt->bind_param('si', $sCoinSlot, $iSlotBlockId);
        if ($stmt->execute() && ($r = $stmt->get_result())) {
          while ($row = $r->fetch_assoc()) {
            $aPPLNSRoundShares[] = $row;
            $iPPLNSShares += (float)$row['pplns_valid'];
          }
        }
        $stmt->close();
      }
    }
    // Block-average target — only meaningful for BLC; aux PPLNS uses
    // the same parent share window so the average doesn't translate.
    $block_avg = ($sCoinSlot === '')
      ? $block->getAvgBlockShares($iHeight, $config['pplns']['blockavg']['blockcount'])
      : 0;
    $smarty->assign('PPLNSROUNDSHARES', $aPPLNSRoundShares);
    $smarty->assign("PPLNSSHARES", $iPPLNSShares);
    $smarty->assign("BLOCKAVGCOUNT", $config['pplns']['blockavg']['blockcount']);
    $smarty->assign("BLOCKAVERAGE", $block_avg);
  }

  $smarty->assign('BLOCKDETAILS', $aDetailsForBlockHeight);
  $smarty->assign("ROUND_CONFIRMATIONS", $iRoundConfirmations);
  $smarty->assign('ROUNDSHARES', $aRoundShareStats);
  $smarty->assign("ROUNDTRANSACTIONS", $aUserRoundTransactions);
  $smarty->assign("ROUND_COIN", $sRoundCoin);
  // Ordered list of every configured ticker (parent first, then aux
  // slots in mm/mm1…mm6 order, skipping 'unused*' placeholders) — the
  // template renders one chip per entry so the operator can flip
  // between coins without leaving the round view.
  $smarty->assign("ROUND_COIN_LIST", array_values($aSlotMap));
  $smarty->assign("COIN_NAMES", array(
    'BLC'  => isset($config['gettingstarted']['coinname']) ? (string)$config['gettingstarted']['coinname'] : 'Blakecoin',
    'PHO'  => 'Photon',
    'BBTC' => 'BlakeBitcoin',
    'LIT'  => 'Lithium',
    'ELT'  => 'Electron',
    'UMO'  => 'Universalmolecule',
  ));
} else {
  $debug->append('Using cached page', 3);
}

if ($setting->getValue('acl_round_statistics')) {
  $smarty->assign("CONTENT", "default.tpl");
} else if ($user->isAuthenticated(false)) {
  $smarty->assign("CONTENT", "default.tpl");
} else {
  $smarty->assign("CONTENT", "empty");
}
?>
