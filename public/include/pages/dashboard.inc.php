<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

if ($user->isAuthenticated()) {
  if (! $interval = $setting->getValue('statistics_ajax_data_interval')) $interval = 300;
  // Defaults to get rid of PHP Notice warnings
  $dNetworkHashrate = 0;
  $dDifficulty = 1;
  $aRoundShares = 1;
  $dDifficulty_mm = 1;
  $aRoundShares_mm = 1;
  $dDifficulty_mm1 = 1;
  $aRoundShares_mm1 = 1;

  $dDifficulty_mm3 = 1;
  $aRoundShares_mm3 = 1;
  $dDifficulty_mm4 = 1;
  $aRoundShares_mm4 = 1;
  $dDifficulty_mm5 = 1;
  $aRoundShares_mm5 = 1;


  $aRoundShares = $statistics->getRoundShares();
  $dDifficulty = 1;
  $aRoundShares_mm = $statistics_mm->getRoundShares();
  $dDifficulty_mm = 1;
  $aRoundShares_mm1 = $statistics_mm1->getRoundShares();

  $aRoundShares_mm3 = $statistics_mm3->getRoundShares();
  $dDifficulty_mm3 = 1;
  $aRoundShares_mm4 = $statistics_mm4->getRoundShares();
  $dDifficulty_mm4 = 1;
  $aRoundShares_mm5 = $statistics_mm5->getRoundShares();
  $dDifficulty_mm5 = 1;

  
  $dNetworkHashrate = 1;
  $dNetworkHashrate_mm = 1;
  $dNetworkHashrate_mm1 = 1;

  $dNetworkHashrate_mm3 = 1;
  $dNetworkHashrate_mm4 = 1;
  $dNetworkHashrate_mm5 = 1;

  
  $iBlock = 0;
  $iBlock_mm = 0;
  $iBlock_mm1 = 0;

  $iBlock_mm3 = 0;
  $iBlock_mm4 = 0;
  $iBlock_mm5 = 0;

  if ($bitcoin->can_connect() === true) {
    $dDifficulty = $bitcoin->getdifficulty();
    $dNetworkHashrate = $bitcoin->getnetworkhashps();
    $iBlock = $bitcoin->getblockcount();
  }
  if ($bitcoin_mm->can_connect() === true) {
    $dDifficulty_mm = $bitcoin_mm->getdifficulty();
    $dNetworkHashrate_mm = $bitcoin_mm->getnetworkhashps();
    $iBlock_mm = $bitcoin_mm->getblockcount();
  }
  if ($bitcoin_mm1->can_connect() === true) {
    $dDifficulty_mm1 = $bitcoin_mm1->getdifficulty();
    $dNetworkHashrate_mm1 = $bitcoin_mm1->getnetworkhashps();
    $iBlock_mm1 = $bitcoin_mm1->getblockcount();
  }
  if ($bitcoin_mm3->can_connect() === true) {
    $dDifficulty_mm3 = $bitcoin_mm3->getdifficulty();
    $dNetworkHashrate_mm3 = $bitcoin_mm3->getnetworkhashps();
    $iBlock_mm3 = $bitcoin_mm3->getblockcount();
  }
  if ($bitcoin_mm4->can_connect() === true) {
    $dDifficulty_mm4 = $bitcoin_mm4->getdifficulty();
    $dNetworkHashrate_mm4 = $bitcoin_mm4->getnetworkhashps();
    $iBlock_mm4 = $bitcoin_mm4->getblockcount();
  }
  if ($bitcoin_mm5->can_connect() === true) {
    $dDifficulty_mm5 = $bitcoin_mm5->getdifficulty();
    $dNetworkHashrate_mm5 = $bitcoin_mm5->getnetworkhashps();
    $iBlock_mm5 = $bitcoin_mm5->getblockcount();
  }


  // Fetch some data
  // Round progress
  $iEstShares = $statistics->getEstimatedShares($dDifficulty);
  if ($iEstShares > 0 && $aRoundShares['valid'] > 0) {
    $dEstPercent = round(100 / $iEstShares * $aRoundShares['valid'], 2);
  } else {
    $dEstPercent = 0;
  }
  $iEstShares_mm = $statistics_mm->getEstimatedShares($dDifficulty_mm);
  if ($iEstShares_mm > 0 && $aRoundShares_mm['valid'] > 0) {
    $dEstPercent_mm = round(100 / $iEstShares_mm * $aRoundShares_mm['valid'], 2);
  } else {
    $dEstPercent_mm = 0;
  }
  $iEstShares_mm1 = $statistics_mm1->getEstimatedShares($dDifficulty_mm1);
  if ($iEstShares_mm1 > 0 && $aRoundShares_mm1['valid'] > 0) {
    $dEstPercent_mm1 = round(100 / $iEstShares_mm1 * $aRoundShares_mm1['valid'], 2);
  } else {
    $dEstPercent_mm1 = 0;
  }

  $iEstShares_mm3 = $statistics_mm3->getEstimatedShares($dDifficulty_mm3);
  if ($iEstShares_mm3 > 0 && $aRoundShares_mm3['valid'] > 0) {
    $dEstPercent_mm3 = round(100 / $iEstShares_mm3 * $aRoundShares_mm3['valid'], 2);
  } else {
    $dEstPercent_mm3 = 0;
  }
  $iEstShares_mm4 = $statistics_mm4->getEstimatedShares($dDifficulty_mm4);
  if ($iEstShares_mm4 > 0 && $aRoundShares_mm4['valid'] > 0) {
    $dEstPercent_mm4 = round(100 / $iEstShares_mm4 * $aRoundShares_mm4['valid'], 2);
  } else {
    $dEstPercent_mm4 = 0;
  }
  $iEstShares_mm5 = $statistics_mm5->getEstimatedShares($dDifficulty_mm5);
  if ($iEstShares_mm5 > 0 && $aRoundShares_mm5['valid'] > 0) {
    $dEstPercent_mm5 = round(100 / $iEstShares_mm5 * $aRoundShares_mm5['valid'], 2);
  } else {
    $dEstPercent_mm5 = 0;
  }

  if (!$iCurrentActiveWorkers = $worker->getCountAllActiveWorkers()) $iCurrentActiveWorkers = 0;
  $iCurrentPoolHashrate =  $statistics->getCurrentHashrate();
  $iCurrentPoolShareRate = $statistics->getCurrentShareRate();

  // Avoid confusion, ensure our nethash isn't higher than poolhash
  if ($iCurrentPoolHashrate > $dNetworkHashrate) $dNetworkHashrate = $iCurrentPoolHashrate;
  if ($iCurrentPoolHashrate > $dNetworkHashrate_mm) $dNetworkHashrate_mm = $iCurrentPoolHashrate;
  if ($iCurrentPoolHashrate > $dNetworkHashrate_mm1) $dNetworkHashrate_mm1 = $iCurrentPoolHashrate;

  if ($iCurrentPoolHashrate > $dNetworkHashrate_mm3) $dNetworkHashrate_mm3 = $iCurrentPoolHashrate;
  if ($iCurrentPoolHashrate > $dNetworkHashrate_mm4) $dNetworkHashrate_mm4 = $iCurrentPoolHashrate;
  if ($iCurrentPoolHashrate > $dNetworkHashrate_mm5) $dNetworkHashrate_mm5 = $iCurrentPoolHashrate;

  $dExpectedTimePerBlock = $statistics->getNetworkExpectedTimePerBlock();
  $dEstNextDifficulty = $statistics->getExpectedNextDifficulty();
  $iBlocksUntilDiffChange = $statistics->getBlocksUntilDiffChange();
  $dExpectedTimePerBlock_mm = $statistics_mm->getNetworkExpectedTimePerBlock_mm();
  $dEstNextDifficulty_mm = $statistics_mm->getExpectedNextDifficulty_mm();
  $iBlocksUntilDiffChange_mm = $statistics_mm->getBlocksUntilDiffChange_mm();
  $dExpectedTimePerBlock_mm1 = $statistics_mm1->getNetworkExpectedTimePerBlock_mm1();
  $dEstNextDifficulty_mm1 = $statistics_mm1->getExpectedNextDifficulty_mm1();
  $iBlocksUntilDiffChange_mm1 = $statistics_mm1->getBlocksUntilDiffChange_mm1();

  $dExpectedTimePerBlock_mm3 = $statistics_mm3->getNetworkExpectedTimePerBlock_mm3();
  $dEstNextDifficulty_mm3 = $statistics_mm3->getExpectedNextDifficulty_mm3();
  $iBlocksUntilDiffChange_mm3 = $statistics_mm3->getBlocksUntilDiffChange_mm3();
  $dExpectedTimePerBlock_mm4 = $statistics_mm4->getNetworkExpectedTimePerBlock_mm4();
  $dEstNextDifficulty_mm4 = $statistics_mm4->getExpectedNextDifficulty_mm4();
  $iBlocksUntilDiffChange_mm4 = $statistics_mm4->getBlocksUntilDiffChange_mm4();
  $dExpectedTimePerBlock_mm5 = $statistics_mm5->getNetworkExpectedTimePerBlock_mm5();
  $dEstNextDifficulty_mm5 = $statistics_mm5->getExpectedNextDifficulty_mm5();
  $iBlocksUntilDiffChange_mm5 = $statistics_mm5->getBlocksUntilDiffChange_mm5();


  // Make it available in Smarty
  $smarty->assign('DISABLED_DASHBOARD', $setting->getValue('disable_dashboard'));
  $smarty->assign('DISABLED_DASHBOARD_API', $setting->getValue('disable_dashboard_api'));
  $smarty->assign('ESTIMATES', array('shares' => $iEstShares, 'percent' => $dEstPercent));
  $smarty->assign('ESTIMATES_MM', array('shares' => $iEstShares_mm, 'percent' => $dEstPercent_mm));
  $smarty->assign('ESTIMATES_MM1', array('shares' => $iEstShares_mm1, 'percent' => $dEstPercent_mm1));

  $smarty->assign('ESTIMATES_MM3', array('shares' => $iEstShares_mm3, 'percent' => $dEstPercent_mm3));
  $smarty->assign('ESTIMATES_MM4', array('shares' => $iEstShares_mm4, 'percent' => $dEstPercent_mm4));
  $smarty->assign('ESTIMATES_MM5', array('shares' => $iEstShares_mm5, 'percent' => $dEstPercent_mm5));

  $smarty->assign('NETWORK', array('difficulty' => $dDifficulty, 'block' => $iBlock, 'EstNextDifficulty' => $dEstNextDifficulty, 'EstTimePerBlock' => $dExpectedTimePerBlock, 'BlocksUntilDiffChange' => $iBlocksUntilDiffChange));
  $smarty->assign('NETWORK_MM', array('difficulty' => $dDifficulty_mm, 'block' => $iBlock_mm, 'EstNextDifficulty' => $dEstNextDifficulty_mm, 'EstTimePerBlock' => $dExpectedTimePerBlock_mm, 'BlocksUntilDiffChange' => $iBlocksUntilDiffChange_mm));
  $smarty->assign('NETWORK_MM1', array('difficulty' => $dDifficulty_mm1, 'block' => $iBlock_mm1, 'EstNextDifficulty' => $dEstNextDifficulty_mm1, 'EstTimePerBlock' => $dExpectedTimePerBlock_mm1, 'BlocksUntilDiffChange' => $iBlocksUntilDiffChange_mm1));

  $smarty->assign('NETWORK_MM3', array('difficulty' => $dDifficulty_mm3, 'block' => $iBlock_mm3, 'EstNextDifficulty' => $dEstNextDifficulty_mm3, 'EstTimePerBlock' => $dExpectedTimePerBlock_mm3, 'BlocksUntilDiffChange' => $iBlocksUntilDiffChange_mm3));
  $smarty->assign('NETWORK_MM4', array('difficulty' => $dDifficulty_mm4, 'block' => $iBlock_mm4, 'EstNextDifficulty' => $dEstNextDifficulty_mm4, 'EstTimePerBlock' => $dExpectedTimePerBlock_mm4, 'BlocksUntilDiffChange' => $iBlocksUntilDiffChange_mm4));
  $smarty->assign('NETWORK_MM5', array('difficulty' => $dDifficulty_mm5, 'block' => $iBlock_mm5, 'EstNextDifficulty' => $dEstNextDifficulty_mm5, 'EstTimePerBlock' => $dExpectedTimePerBlock_mm5, 'BlocksUntilDiffChange' => $iBlocksUntilDiffChange_mm5));

  $smarty->assign('INTERVAL', $interval / 60);
  $smarty->assign('CONTENT', 'default.tpl');
}

?>
