<?php
// Normalize daemon soft-fork/versionbits state into an operator-facing
// status. This intentionally keeps raw daemon warnings available in the
// tooltip/detail while preventing known BIP9 signaling from reading like a
// fatal wallet error on AuxPoW chains.

if (!function_exists('_bsx_rule_warning_text')) {
  function _bsx_rule_warning_text() {
    $warnings = array();
    foreach (func_get_args() as $info) {
      if (!is_array($info)) continue;
      foreach (array('warnings', 'errors') as $key) {
        if (!empty($info[$key])) $warnings[] = trim((string)$info[$key]);
      }
    }
    $warnings = array_values(array_unique(array_filter($warnings)));
    return implode(' | ', $warnings);
  }
}

if (!function_exists('_bsx_rule_deployment_label')) {
  function _bsx_rule_deployment_label($name, $deployment) {
    $status = isset($deployment['status']) ? strtolower((string)$deployment['status']) : '';
    $label = _bsx_rule_display_name($name);
    $since = isset($deployment['since']) ? (int)$deployment['since'] : null;
    if (!empty($deployment['statistics']) && is_array($deployment['statistics'])) {
      $stats = $deployment['statistics'];
      $count = isset($stats['count']) ? (int)$stats['count'] : 0;
      $period = isset($stats['period']) ? (int)$stats['period'] : 0;
      $threshold = isset($stats['threshold']) ? (int)$stats['threshold'] : 0;
      if ($status === 'started' && $period > 0) {
        $parts = array($label . ' window ' . $count . '/' . $period);
        if ($threshold > 0) $parts[] = 'threshold ' . $threshold;
        if ($since !== null) $parts[] = 'since block ' . $since;
        return implode(', ', $parts);
      }
      if ($period > 0) {
        $parts = array($label . ($status !== '' ? ' ' . str_replace('_', ' ', $status) : ''));
        $parts[] = 'window ' . $count . '/' . $period;
        if ($threshold > 0) $parts[] = 'threshold ' . $threshold;
        if ($since !== null) $parts[] = 'since block ' . $since;
        return implode(', ', $parts);
      }
      if ($count > 0) return $label . ' count ' . $count;
    }
    if ($status === 'active') return $label . ' active';
    $text = $label . ($status !== '' ? ' ' . str_replace('_', ' ', $status) : '');
    if ($since !== null) $text .= ', since block ' . $since;
    return $text;
  }
}

if (!function_exists('_bsx_rule_display_name')) {
  function _bsx_rule_display_name($name) {
    $key = strtolower((string)$name);
    $names = array(
      'segwit' => 'SegWit',
      'taproot' => 'Taproot',
      'csv' => 'CSV',
      'testdummy' => 'TestDummy',
    );
    return isset($names[$key]) ? $names[$key] : strtoupper((string)$name);
  }
}

if (!function_exists('_bsx_daemon_rule_status_from_info')) {
  function _bsx_daemon_rule_status_from_info($blockchaininfo, $warning_text = '') {
    $warning_text = trim((string)$warning_text);
    $deployments = array();
    $signaling = array();
    $signaling_names = array();
    $locked = array();
    $locked_names = array();

    if (is_array($blockchaininfo) && !empty($blockchaininfo['bip9_softforks'])
        && is_array($blockchaininfo['bip9_softforks'])) {
      foreach ($blockchaininfo['bip9_softforks'] as $name => $deployment) {
        if (!is_array($deployment)) continue;
        $status = isset($deployment['status']) ? strtolower((string)$deployment['status']) : '';
        $detail = _bsx_rule_deployment_label($name, $deployment);
        $deployments[] = $detail;
        if ($status === 'started') {
          $count = 0;
          if (!empty($deployment['statistics']) && is_array($deployment['statistics'])
              && isset($deployment['statistics']['count'])) {
            $count = (int)$deployment['statistics']['count'];
          }
          if ($count > 0) {
            $signaling[] = $detail;
            $signaling_names[] = _bsx_rule_display_name($name);
          }
        } elseif ($status === 'locked_in') {
          $locked[] = $detail;
          $locked_names[] = _bsx_rule_display_name($name);
        }
      }
    }

    $unknown_block_warning = stripos($warning_text, 'Unknown block versions being mined') !== false;
    $deployment_detail = $deployments ? implode(', ', $deployments) : 'No active signaling';
    $detail_parts = array();
    if ($deployments) $detail_parts[] = $deployment_detail;
    if ($warning_text !== '') $detail_parts[] = 'Daemon: ' . $warning_text;

    if ($warning_text !== '' && !$unknown_block_warning) {
      return array(
        'label' => 'Warning',
        'class' => 'err',
        'state' => 'warning',
        'detail' => $warning_text,
        'raw_warning' => $warning_text,
        'warning_explained' => false,
      );
    }

    if ($signaling) {
      $signal_label = count($signaling_names) === 1
        ? 'Signaling - ' . $signaling_names[0]
        : 'Signaling - Multiple';
      return array(
        'label' => $signal_label,
        'class' => 'signal',
        'state' => 'signaling',
        'detail' => $deployment_detail,
        'raw_warning' => $warning_text,
        'warning_explained' => $unknown_block_warning,
      );
    }

    if ($locked) {
      $locked_label = count($locked_names) === 1
        ? 'Locked In - ' . $locked_names[0]
        : 'Locked In - Multiple';
      return array(
        'label' => $locked_label,
        'class' => 'signal',
        'state' => 'locked_in',
        'detail' => $deployment_detail,
        'raw_warning' => $warning_text,
        'warning_explained' => $unknown_block_warning,
      );
    }

    if ($warning_text !== '') {
      return array(
        'label' => 'Warning',
        'class' => 'err',
        'state' => 'warning',
        'detail' => $warning_text,
        'raw_warning' => $warning_text,
        'warning_explained' => false,
      );
    }

    return array(
      'label' => 'OK',
      'class' => 'ok',
      'state' => 'ok',
      'detail' => $deployment_detail,
      'raw_warning' => '',
      'warning_explained' => false,
    );
  }
}

if (!function_exists('bsx_daemon_rule_status')) {
  function bsx_daemon_rule_status($btc, $wallet_info = array(), $network_info = null, $blockchain_info = null) {
    if (!is_array($wallet_info)) $wallet_info = array();
    if (!is_array($network_info)) {
      try {
        $network_info = $btc ? $btc->getnetworkinfo() : array();
      } catch (Exception $e) {
        $network_info = array('warnings' => $e->getMessage());
      }
    }
    if (!is_array($blockchain_info)) {
      try {
        $blockchain_info = $btc ? $btc->getblockchaininfo() : array();
      } catch (Exception $e) {
        $blockchain_info = array();
      }
    }
    $warning_text = _bsx_rule_warning_text($wallet_info, $network_info);
    return _bsx_daemon_rule_status_from_info($blockchain_info, $warning_text);
  }
}
?>
