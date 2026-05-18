<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

// Check if the API is activated
$api->isActive();

// Check user token
$user_id = $api->checkAccess($user->checkApiKey($_REQUEST['api_key']), @$_REQUEST['id']);

// Match the worker table's raw share-difficulty window to the same
// sampling window the cron uses before EMA smoothing hashrate.
if ( ! $interval = $setting->getValue('hashrate_window_seconds')) $interval = 900;
$interval = max(60, (int)$interval);

// Output JSON format
echo $api->get_json($worker->getWorkers($user_id, $interval));

// Supress master template
$supress_master = 1;
?>
