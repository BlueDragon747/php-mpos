<?php
// Normalize daemon soft-fork/versionbits state into an operator-facing
// status. Raw daemon warnings stay available in the JSON payload, while the
// tooltip gives operators the short consensus explanation they need.

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
    $status = _bsx_deployment_status_from_deployment($deployment);
    $label = _bsx_rule_display_name($name);
    $since = _bsx_deployment_since($deployment);
    $stats = _bsx_deployment_stats($deployment);
    if ($status === 'active') return $label . ' active';
    if ($status === 'locked_in') {
      $text = $label . ' locked in';
      if ($since !== null) $text .= ', since block ' . $since;
      return $text;
    }
    if ($stats) {
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
    $text = $label . ($status !== '' ? ' ' . str_replace('_', ' ', $status) : '');
    if ($since !== null) $text .= ', since block ' . $since;
    return $text;
  }
}

if (!function_exists('_bsx_deployment_from_info')) {
  function _bsx_deployment_from_info($blockchaininfo, $deploymentinfo, $name) {
    $name = strtolower((string)$name);

    if (is_array($deploymentinfo)
        && !empty($deploymentinfo['deployments'])
        && is_array($deploymentinfo['deployments'])
        && !empty($deploymentinfo['deployments'][$name])
        && is_array($deploymentinfo['deployments'][$name])) {
      return $deploymentinfo['deployments'][$name];
    }

    if (is_array($blockchaininfo)
        && !empty($blockchaininfo['softforks'])
        && is_array($blockchaininfo['softforks'])
        && !empty($blockchaininfo['softforks'][$name])
        && is_array($blockchaininfo['softforks'][$name])) {
      return $blockchaininfo['softforks'][$name];
    }

    if (is_array($blockchaininfo)
        && !empty($blockchaininfo['bip9_softforks'])
        && is_array($blockchaininfo['bip9_softforks'])
        && !empty($blockchaininfo['bip9_softforks'][$name])
        && is_array($blockchaininfo['bip9_softforks'][$name])) {
      return $blockchaininfo['bip9_softforks'][$name];
    }

    return array();
  }
}

if (!function_exists('_bsx_deployment_bip9')) {
  function _bsx_deployment_bip9($deployment) {
    if (!is_array($deployment)) return array();
    if (!empty($deployment['bip9']) && is_array($deployment['bip9'])) {
      return $deployment['bip9'];
    }
    return $deployment;
  }
}

if (!function_exists('_bsx_deployment_status_from_deployment')) {
  function _bsx_deployment_status_from_deployment($deployment) {
    if (!is_array($deployment)) return '';
    if (!empty($deployment['active'])) return 'active';
    if (!empty($deployment['status'])) return strtolower((string)$deployment['status']);
    $bip9 = _bsx_deployment_bip9($deployment);
    if (!empty($bip9['status'])) return strtolower((string)$bip9['status']);
    return '';
  }
}

if (!function_exists('_bsx_deployment_stats')) {
  function _bsx_deployment_stats($deployment) {
    if (!is_array($deployment)) return array();
    if (!empty($deployment['statistics']) && is_array($deployment['statistics'])) {
      return $deployment['statistics'];
    }
    $bip9 = _bsx_deployment_bip9($deployment);
    if (!empty($bip9['statistics']) && is_array($bip9['statistics'])) {
      return $bip9['statistics'];
    }
    return array();
  }
}

if (!function_exists('_bsx_deployment_since')) {
  function _bsx_deployment_since($deployment) {
    if (!is_array($deployment)) return null;
    if (isset($deployment['since'])) return (int)$deployment['since'];
    $bip9 = _bsx_deployment_bip9($deployment);
    if (isset($bip9['since'])) return (int)$bip9['since'];
    return null;
  }
}

if (!function_exists('_bsx_deployment_min_activation_height')) {
  function _bsx_deployment_min_activation_height($deployment) {
    if (!is_array($deployment)) return null;
    if (isset($deployment['min_activation_height'])) {
      return (int)$deployment['min_activation_height'];
    }
    $bip9 = _bsx_deployment_bip9($deployment);
    if (isset($bip9['min_activation_height'])) {
      return (int)$bip9['min_activation_height'];
    }
    return null;
  }
}

if (!function_exists('_bsx_taproot_upcoming_detail')) {
  function _bsx_taproot_upcoming_detail($deployment) {
    $height = _bsx_deployment_min_activation_height($deployment);
    if ($height !== null && $height > 0) {
      return 'Taproot upcoming - min activation height ' . $height;
    }
    return 'Taproot upcoming';
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

if (!function_exists('_bsx_rule_deployment_status')) {
  function _bsx_rule_deployment_status($blockchaininfo, $name, $deploymentinfo = array()) {
    $deployment = _bsx_deployment_from_info($blockchaininfo, $deploymentinfo, $name);
    return _bsx_deployment_status_from_deployment($deployment);
  }
}

if (!function_exists('_bsx_taproot_rule_detail')) {
  function _bsx_taproot_rule_detail($blockchaininfo, $deploymentinfo = array()) {
    $deployment = _bsx_deployment_from_info($blockchaininfo, $deploymentinfo, 'taproot');
    $status = _bsx_deployment_status_from_deployment($deployment);
    if ($status === 'active') return 'Taproot active';
    if ($status === 'locked_in') return _bsx_rule_deployment_label('taproot', $deployment);
    if ($status === 'started') return 'Taproot signaling';
    return _bsx_taproot_upcoming_detail($deployment);
  }
}

if (!function_exists('_bsx_add_rule_detail')) {
  function _bsx_add_rule_detail(&$details, $detail) {
    $detail = trim((string)$detail);
    if ($detail !== '' && !in_array($detail, $details, true)) $details[] = $detail;
  }
}

if (!function_exists('_bsx_format_rule_details')) {
  function _bsx_format_rule_details($active_rules, $extra_details = array()) {
    $details = array();
    if ($active_rules) {
      $details[] = implode(', ', $active_rules) . ' active';
    }
    foreach ($extra_details as $detail) {
      _bsx_add_rule_detail($details, $detail);
    }
    return $details;
  }
}

if (!function_exists('_bsx_coin_segwit_active')) {
  function _bsx_coin_segwit_active($sym, $blockchaininfo, $deploymentinfo = array()) {
    $status = _bsx_rule_deployment_status($blockchaininfo, 'segwit', $deploymentinfo);
    if ($status === 'active') return true;

    // Current 25.2 mainnet state. BBTC remains pre-SegWit until its chain
    // activates it, so it is intentionally not in this fallback list.
    $sym = strtoupper((string)$sym);
    return in_array($sym, array('BLC', 'PHO', 'ELT', 'UMO', 'LIT'), true);
  }
}

if (!function_exists('_bsx_expected_rule_details')) {
  function _bsx_expected_rule_details($sym, $blockchaininfo, $force_active = array(), $deploymentinfo = array()) {
    $sym = strtoupper((string)$sym);
    $active_rules = array();
    $extra_details = array();
    $known_coin = in_array($sym, array('BLC', 'PHO', 'BBTC', 'ELT', 'UMO', 'LIT'), true);
    if (!$known_coin && !$force_active) return array();

    if (in_array($sym, array('PHO', 'BBTC', 'ELT', 'UMO', 'LIT'), true)) {
      _bsx_add_rule_detail($active_rules, 'AuxPoW');
    }
    if (_bsx_coin_segwit_active($sym, $blockchaininfo, $deploymentinfo)) {
      _bsx_add_rule_detail($active_rules, 'SegWit');
    }
    foreach ($force_active as $rule) {
      _bsx_add_rule_detail($active_rules, $rule);
    }

    $taproot_deployment = _bsx_deployment_from_info($blockchaininfo, $deploymentinfo, 'taproot');
    $taproot_status = _bsx_deployment_status_from_deployment($taproot_deployment);
    if ($taproot_status === 'active' || in_array('Taproot', $active_rules, true)) {
      _bsx_add_rule_detail($active_rules, 'Taproot');
    } elseif ($taproot_status === 'locked_in') {
      _bsx_add_rule_detail($extra_details, _bsx_rule_deployment_label('taproot', $taproot_deployment));
    } elseif ($taproot_status === 'started') {
      _bsx_add_rule_detail($extra_details, _bsx_rule_deployment_label('taproot', $taproot_deployment));
    } elseif ($known_coin) {
      _bsx_add_rule_detail($extra_details, _bsx_taproot_upcoming_detail($taproot_deployment));
    }

    return _bsx_format_rule_details($active_rules, $extra_details);
  }
}

if (!function_exists('_bsx_known_versionbit_detail')) {
  function _bsx_known_versionbit_detail($bit, $sym) {
    $bit = (int)$bit;
    $sym = strtoupper((string)$sym);

    if ($bit === 1) {
      return 'SegWit';
    }

    if ($bit === 2) {
      return 'Taproot';
    }

    if ($bit === 4 && in_array($sym, array('PHO', 'BBTC', 'ELT', 'UMO', 'LIT'), true)) {
      return 'AuxPoW';
    }

    return '';
  }
}

if (!function_exists('_bsx_known_versionbit_warning')) {
  function _bsx_known_versionbit_warning($warning_text, $sym, $blockchaininfo = array(), $deploymentinfo = array()) {
    $warning_text = trim((string)$warning_text);
    if ($warning_text === '') return null;

    $active_rules = array();
    foreach (preg_split('/\s+\|\s+/', $warning_text) as $part) {
      $part = trim($part);
      if ($part === '') continue;
      if (!preg_match('/^Unknown new rules activated \(versionbit (\d+)\)$/i', $part, $m)) {
        return null;
      }
      $detail = _bsx_known_versionbit_detail((int)$m[1], $sym);
      if ($detail === '') return null;
      _bsx_add_rule_detail($active_rules, $detail);
    }

    if (!$active_rules) return null;
    $details = _bsx_expected_rule_details($sym, $blockchaininfo, $active_rules, $deploymentinfo);

    return array(
      'label' => 'Active',
      'detail' => implode('. ', $details) . '.',
    );
  }
}

if (!function_exists('_bsx_daemon_rule_status_from_info')) {
  function _bsx_daemon_rule_status_from_info($blockchaininfo, $warning_text = '', $sym = '', $deploymentinfo = array()) {
    $warning_text = trim((string)$warning_text);
    $deployments = array();
    $signaling = array();
    $signaling_names = array();
    $locked = array();
    $locked_names = array();
    $deployment_source = array();

    if (is_array($deploymentinfo)
        && !empty($deploymentinfo['deployments'])
        && is_array($deploymentinfo['deployments'])) {
      $deployment_source = $deploymentinfo['deployments'];
    } elseif (is_array($blockchaininfo)
        && !empty($blockchaininfo['bip9_softforks'])
        && is_array($blockchaininfo['bip9_softforks'])) {
      $deployment_source = $blockchaininfo['bip9_softforks'];
    } elseif (is_array($blockchaininfo)
        && !empty($blockchaininfo['softforks'])
        && is_array($blockchaininfo['softforks'])) {
      $deployment_source = $blockchaininfo['softforks'];
    }

    if ($deployment_source) {
      foreach ($deployment_source as $name => $deployment) {
        if (!is_array($deployment)) continue;
        $rule_name = strtolower((string)$name);
        // CSV is buried consensus plumbing on 25.2. Keep the operator-facing
        // rule pill focused on the active/upcoming deployment.
        if ($rule_name !== 'taproot') continue;
        $status = _bsx_deployment_status_from_deployment($deployment);
        $detail = _bsx_rule_deployment_label($name, $deployment);
        $deployments[] = $detail;
        if ($status === 'started') {
          $signaling[] = $detail;
          $signaling_names[] = _bsx_rule_display_name($name);
        } elseif ($status === 'locked_in') {
          $locked[] = $detail;
          $locked_names[] = _bsx_rule_display_name($name);
        }
      }
    }

    $unknown_block_warning = stripos($warning_text, 'Unknown block versions being mined') !== false;
    $known_versionbit_warning = _bsx_known_versionbit_warning($warning_text, $sym, $blockchaininfo, $deploymentinfo);
    $expected_rule_details = _bsx_expected_rule_details($sym, $blockchaininfo, array(), $deploymentinfo);
    $deployment_detail = $deployments ? implode(', ', $deployments) : 'No active signaling';
    $rule_detail = $expected_rule_details
      ? implode('. ', $expected_rule_details) . '.'
      : ($deployment_detail !== '' ? $deployment_detail . '.' : '');
    $detail_parts = array();
    if ($deployments) $detail_parts[] = $deployment_detail;
    if ($warning_text !== '') $detail_parts[] = 'Daemon: ' . $warning_text;

    if ($known_versionbit_warning && !$signaling && !$locked) {
      return array(
        'label' => $known_versionbit_warning['label'],
        'class' => 'ok',
        'state' => 'active',
        'detail' => $known_versionbit_warning['detail'],
        'raw_warning' => $warning_text,
        'warning_explained' => true,
      );
    }

    if ($warning_text !== '' && !$unknown_block_warning && !$known_versionbit_warning) {
      return array(
        'label' => 'Warning',
        'class' => 'err',
        'state' => 'warning',
        'detail' => $warning_text,
        'raw_warning' => $warning_text,
        'warning_explained' => false,
      );
    }

    if ($expected_rule_details && !$signaling && !$locked && $warning_text === '') {
      return array(
        'label' => 'Active',
        'class' => 'ok',
        'state' => 'active',
        'detail' => implode('. ', $expected_rule_details) . '.',
        'raw_warning' => '',
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
        'detail' => $rule_detail,
        'raw_warning' => $warning_text,
        'warning_explained' => ($unknown_block_warning || $known_versionbit_warning),
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
        'detail' => $rule_detail,
        'raw_warning' => $warning_text,
        'warning_explained' => ($unknown_block_warning || $known_versionbit_warning),
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
  function bsx_daemon_rule_status($btc, $wallet_info = array(), $network_info = null, $blockchain_info = null, $sym = '', $deployment_info = null) {
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
    if (!is_array($deployment_info)) {
      try {
        $deployment_info = $btc ? $btc->getdeploymentinfo() : array();
      } catch (Exception $e) {
        $deployment_info = array();
      }
    }
    $warning_text = _bsx_rule_warning_text($wallet_info, $network_info);
    return _bsx_daemon_rule_status_from_info($blockchain_info, $warning_text, $sym, $deployment_info);
  }
}
?>
