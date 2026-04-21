<?php

// Small helper array that may be used on some page controllers to
// fetch the crons we wish to monitor
//$aMonitorCrons = array('statistics','payouts', 'payouts_mm', 'token_cleanup','archive_cleanup','blockupdate', 'blockupdate_mm', 'findblock', 'findblock_mm', 'notifications','tickerupdate','liquid_payout');
//$aMonitorCrons = array('statistics','payouts', 'payouts_mm', 'payouts_mm1', 'token_cleanup','archive_cleanup','blockupdate', 'blockupdate_mm', 'blockupdate_mm1', 'findblock', 'findblock_mm', 'findblock_mm1', 'notifications','tickerupdate','liquid_payout');
//$aMonitorCrons = array('statistics','payouts', 'payouts_mm', 'payouts_mm1', 'payouts_mm2','token_cleanup','archive_cleanup','blockupdate', 'blockupdate_mm', 'blockupdate_mm1', 'blockupdate_mm2','findblock', 'findblock_mm', 'findblock_mm1', 'findblock_mm2','notifications','tickerupdate','liquid_payout');
//$aMonitorCrons = array('statistics','payouts', 'payouts_mm', 'payouts_mm1', 'payouts_mm2','token_cleanup','archive_cleanup','blockupdate', 'blockupdate_mm', 'blockupdate_mm1', 'blockupdate_mm2','findblock', 'findblock_mm', 'findblock_mm1', 'findblock_mm2','notifications','liquid_payout');
//$aMonitorCrons = array('statistics','payouts','payouts_mm','payouts_mm1','payouts_mm2','payouts_mm3','token_cleanup','archive_cleanup','blockupdate', 'blockupdate_mm', 'blockupdate_mm1', 'blockupdate_mm2','blockupdate_mm3','findblock', 'findblock_mm', 'findblock_mm1', 'findblock_mm2','findblock_mm3','notifications','liquid_payout');
//$aMonitorCrons = array('statistics','payouts','payouts_mm','payouts_mm1','payouts_mm2','payouts_mm3','payouts_mm4','token_cleanup','archive_cleanup','blockupdate', 'blockupdate_mm', 'blockupdate_mm1', 'blockupdate_mm2','blockupdate_mm3','blockupdate_mm4','findblock', 'findblock_mm', 'findblock_mm1', 'findblock_mm2','findblock_mm3','findblock_mm4','notifications','liquid_payout');
//$aMonitorCrons = array('statistics','payouts','payouts_mm','payouts_mm1','payouts_mm2','payouts_mm3','payouts_mm4','payouts_mm5','token_cleanup','archive_cleanup','blockupdate', 'blockupdate_mm', 'blockupdate_mm1', 'blockupdate_mm2','blockupdate_mm3','blockupdate_mm4','blockupdate_mm5','findblock', 'findblock_mm', 'findblock_mm1', 'findblock_mm2','findblock_mm3','findblock_mm4','findblock_mm5','notifications','liquid_payout');
//$aMonitorCrons = array('statistics','payouts','payouts_mm','payouts_mm1','payouts_mm2','payouts_mm3','payouts_mm4','payouts_mm5','payouts_mm6','token_cleanup','archive_cleanup','blockupdate', 'blockupdate_mm', 'blockupdate_mm1', 'blockupdate_mm2','blockupdate_mm3','blockupdate_mm4','blockupdate_mm5','blockupdate_mm6','findblock', 'findblock_mm', 'findblock_mm1', 'findblock_mm2','findblock_mm3','findblock_mm4','findblock_mm5','findblock_mm6','notifications','liquid_payout');
$aMonitorCrons = array('statistics','payouts','payouts_mm','payouts_mm1','payouts_mm3','payouts_mm4','payouts_mm5','token_cleanup','archive_cleanup','blockupdate', 'blockupdate_mm', 'blockupdate_mm1', 'blockupdate_mm3','blockupdate_mm4','blockupdate_mm5','findblock', 'findblock_mm', 'findblock_mm1', 'findblock_mm3','findblock_mm4','findblock_mm5','notifications','liquid_payout');

switch ($config['payout_system']) {
case 'pplns':
    $aMonitorCrons[] = $config['payout_system'] . '_payout';
      break;
case 'pps':
    $aMonitorCrons[] = $config['payout_system'] . '_payout';
      break;
case 'prop':
    $aMonitorCrons[] = 'proportional_payout';
      break;
}

switch ($config['payout_system_mm']) {
case 'pplns':
    $aMonitorCrons[] = $config['payout_system_mm'] . '_payout_mm';
      break;
case 'pps':
    $aMonitorCrons[] = 'findblock_mm_strict';
    $aMonitorCrons[] = $config['payout_system_mm'] . '_payout_mm';
      break;
case 'prop':
    $aMonitorCrons[] = 'proportional_payout_mm';
      break;
}

switch ($config['payout_system_mm1']) {
case 'pplns':
    $aMonitorCrons[] = $config['payout_system_mm1'] . '_payout_mm1';
      break;
case 'pps':
    $aMonitorCrons[] = 'findblock_mm1_strict';
    $aMonitorCrons[] = $config['payout_system_mm1'] . '_payout_mm1';
      break;
case 'prop':
    $aMonitorCrons[] = 'proportional_payout_mm1';
      break;
}
/*
switch ($config['payout_system_mm2']) {
case 'pplns':
    $aMonitorCrons[] = $config['payout_system_mm2'] . '_payout_mm2';
      break;
case 'pps':
    $aMonitorCrons[] = 'findblock_mm2_strict';
    $aMonitorCrons[] = $config['payout_system_mm2'] . '_payout_mm2';
      break;
case 'prop':
    $aMonitorCrons[] = 'proportional_payout_mm2';
      break;
}
*/
switch ($config['payout_system_mm3']) {
case 'pplns':
    $aMonitorCrons[] = $config['payout_system_mm3'] . '_payout_mm3';
      break;
case 'pps':
    $aMonitorCrons[] = 'findblock_mm3_strict';
    $aMonitorCrons[] = $config['payout_system_mm3'] . '_payout_mm3';
      break;
case 'prop':
    $aMonitorCrons[] = 'proportional_payout_mm3';
      break;
}
switch ($config['payout_system_mm4']) {
case 'pplns':
    $aMonitorCrons[] = $config['payout_system_mm4'] . '_payout_mm4';
      break;
case 'pps':
    $aMonitorCrons[] = 'findblock_mm4_strict';
    $aMonitorCrons[] = $config['payout_system_mm4'] . '_payout_mm4';
      break;
case 'prop':
    $aMonitorCrons[] = 'proportional_payout_mm4';
      break;
}

switch ($config['payout_system_mm5']) {
case 'pplns':
    $aMonitorCrons[] = $config['payout_system_mm5'] . '_payout_mm5';
      break;
case 'pps':
    $aMonitorCrons[] = 'findblock_mm5_strict';
    $aMonitorCrons[] = $config['payout_system_mm5'] . '_payout_mm5';
      break;
case 'prop':
    $aMonitorCrons[] = 'proportional_payout_mm5';
      break;
}

/*
switch ($config['payout_system_mm6']) {
case 'pplns':
    $aMonitorCrons[] = $config['payout_system_mm6'] . '_payout_mm6';
      break;
case 'pps':
    $aMonitorCrons[] = 'findblock_mm6_strict';
    $aMonitorCrons[] = $config['payout_system_mm6'] . '_payout_mm6';
      break;
case 'prop':
    $aMonitorCrons[] = 'proportional_payout_mm6';
      break;
}
*/