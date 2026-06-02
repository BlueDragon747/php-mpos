<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

if (!$smarty->isCached('master.tpl', $smarty_cache_key)) {
  $debug->append('No cached version available, fetching from backend', 3);
  $aPoolHourlyHashRates = $statistics->getHourlyHashrateByPool();
  $aHourlyHashRates = array();
  if ($user->isAuthenticated()) {
    $aHourlyHashRates = $statistics->getHourlyHashrateByAccount($_SESSION['USERDATA']['username'], $_SESSION['USERDATA']['id']);
  }
  $smarty->assign("YOURHASHRATES", $aHourlyHashRates);
  $smarty->assign("POOLHASHRATES", $aPoolHourlyHashRates);
  $smarty->assign("GRAPH_HAS_MINE", is_array($aHourlyHashRates) && count($aHourlyHashRates) > 0);
  $smarty->assign("GRAPH_HAS_POOL", is_array($aPoolHourlyHashRates) && count($aPoolHourlyHashRates) > 0);
} else {
  $debug->append('Using cached page', 3);
}

$smarty->assign("CONTENT", "default.tpl");
?>
