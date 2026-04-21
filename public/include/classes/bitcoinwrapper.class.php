<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

/**
 * We use a wrapper class around BitcoinClient to add
 * some basic caching functionality and some debugging
 **/
class BitcoinWrapper extends BitcoinClient {
  private $socket_timeout = 3; // 3 second timeout for all connections
  private $port;
  
  public function __construct($type, $username, $password, $host, $debug_level, $debug_object, $memcache) {
    $this->type = $type;
    $this->username = $username;
    $this->password = $password;
    $this->host = $host;
    // Parse port from host:port for cache key generation
    if (strpos($host, ':') !== false) {
      list($host_part, $port_part) = explode(':', $host);
      $this->port = $port_part;
    } else {
      $this->port = '';
    }
    // $this->debug is already used
    $this->oDebug = $debug_object;
    $this->memcache = $memcache;
    $debug_level > 0 ? $debug_level = true : $debug_level = false;
    return parent::__construct($this->type, $this->username, $this->password, $this->host, '', $debug_level);
  }
  /**
   * Wrap variouns methods to add caching
   **/
  // Caching this, used for each can_connect call
  public function getinfo() {
    $this->oDebug->append("STA " . __METHOD__, 4);
    // Quick cache check first - if we failed recently, return cached error
    $cacheKey = __FUNCTION__ . '_status';
    if ($status = $this->memcache->get($cacheKey)) {
      if ($status === 'unreachable') {
        return array(); // Return empty if we know daemon is unreachable
      }
    }
    
    if ($data = $this->memcache->get(__FUNCTION__)) return $data;
    
    // Set short timeout to prevent hanging
    $old_timeout = ini_get('default_socket_timeout');
    ini_set('default_socket_timeout', $this->socket_timeout);
    try {
      $data = parent::getinfo();
      $this->memcache->setCache($cacheKey, 'reachable', 60); // Cache success for 1 minute
    } catch (Exception $e) {
      ini_set('default_socket_timeout', $old_timeout);
      $this->memcache->setCache($cacheKey, 'unreachable', 30); // Cache failure for 30 seconds
      return array(); // Return empty array on failure
    }
    ini_set('default_socket_timeout', $old_timeout);
    return $this->memcache->setCache(__FUNCTION__, $data, 30);
  }
  public function getmininginfo() {
    $this->oDebug->append("STA " . __METHOD__, 4);
    if ($data = $this->memcache->get(__FUNCTION__)) return $data;
    // Set short timeout to prevent hanging
    $old_timeout = ini_get('default_socket_timeout');
    ini_set('default_socket_timeout', $this->socket_timeout);
    try {
      $data = parent::getmininginfo();
    } catch (Exception $e) {
      ini_set('default_socket_timeout', $old_timeout);
      return array(); // Return empty array on failure
    }
    ini_set('default_socket_timeout', $old_timeout);
    return $this->memcache->setCache(__FUNCTION__, $data, 30);
  }
  private function getCacheKey($function) {
    // Create unique cache key per wallet instance using host:port
    return $function . '_' . md5($this->host . ':' . $this->port);
  }

  public function getblockcount() {
    $this->oDebug->append("STA " . __METHOD__, 4);
    $cacheKey = $this->getCacheKey(__FUNCTION__);
    if ($data = $this->memcache->get($cacheKey)) return $data;
    // Set short timeout to prevent hanging
    $old_timeout = ini_get('default_socket_timeout');
    ini_set('default_socket_timeout', $this->socket_timeout);
    try {
      $data = parent::getblockcount();
    } catch (Exception $e) {
      ini_set('default_socket_timeout', $old_timeout);
      return 0; // Return 0 on failure
    }
    ini_set('default_socket_timeout', $old_timeout);
    return $this->memcache->setCache($cacheKey, $data, 30);
  }
  public function getdifficulty() {
    $this->oDebug->append("STA " . __METHOD__, 4);
    $cacheKey = $this->getCacheKey(__FUNCTION__);
    if ($data = $this->memcache->get($cacheKey)) {
      // Check if cached data is negative, if so, clear cache and re-fetch
      if (is_numeric($data) && $data < 0) {
        $this->memcache->delete($cacheKey);
      } else {
        return $data;
      }
    }
    // Set short timeout to prevent hanging
    $old_timeout = ini_get('default_socket_timeout');
    ini_set('default_socket_timeout', $this->socket_timeout);
    try {
      $data = parent::getdifficulty();
    } catch (Exception $e) {
      ini_set('default_socket_timeout', $old_timeout);
      return 1; // Return default value on failure
    }
    ini_set('default_socket_timeout', $old_timeout);
    // Check for PoS/PoW coins
    if (is_array($data) && array_key_exists('proof-of-work', $data))
      $data = $data['proof-of-work'];
    
    // Protect against negative difficulty values
    if (is_numeric($data) && $data < 0) {
      $this->oDebug->append("WARNING: Negative difficulty received from RPC: $data, returning default", 2);
      return 1;
    }
    
    return $this->memcache->setCache($cacheKey, $data, 30);
  }
  public function getestimatedtime($iCurrentPoolHashrate) {
    $this->oDebug->append("STA " . __METHOD__, 4);
    if ($iCurrentPoolHashrate == 0) return 0;
    $cacheKey = $this->getCacheKey(__FUNCTION__);
    if ($data = $this->memcache->get($cacheKey)) return $data;
    $dDifficulty = $this->getdifficulty();
    return $this->memcache->setCache($cacheKey, $dDifficulty * pow(2,32) / $iCurrentPoolHashrate, 30);
  }
  public function getnetworkhashps() {
    $this->oDebug->append("STA " . __METHOD__, 4);
    $cacheKey = $this->getCacheKey(__FUNCTION__);
    if ($data = $this->memcache->get($cacheKey)) {
      // Verify cached data isn't negative
      if (is_numeric($data) && $data < 0) {
        $this->oDebug->append("WARNING: Cached negative network hashrate detected, clearing cache", 2);
        $this->memcache->delete($cacheKey);
      } else {
        return $data;
      }
    }
    // Set short timeout to prevent hanging
    $old_timeout = ini_get('default_socket_timeout');
    ini_set('default_socket_timeout', $this->socket_timeout);
    try {
      $dNetworkHashrate = $this->getmininginfo();
      if (is_array($dNetworkHashrate)) {
        if (array_key_exists('networkhashps', $dNetworkHashrate)) {
          $dNetworkHashrate = $dNetworkHashrate['networkhashps'];
        } else if (array_key_exists('hashespersec', $dNetworkHashrate)) {
          $dNetworkHashrate = $dNetworkHashrate['hashespersec'];
        } else if (array_key_exists('netmhashps', $dNetworkHashrate)) {
          $dNetworkHashrate = $dNetworkHashrate['netmhashps'] * 1000 * 1000;
        } else {
          // Unsupported implementation
          $dNetworkHashrate = 0;
        }
      }
    } catch (Exception $e) {
      // getmininginfo does not exist, cache for an hour
      ini_set('default_socket_timeout', $old_timeout);
      return $this->memcache->setCache($cacheKey, 0, 3600);
    }
    ini_set('default_socket_timeout', $old_timeout);
    
    // Protect against negative or invalid hashrate values
    if (!is_numeric($dNetworkHashrate) || $dNetworkHashrate < 0) {
      $this->oDebug->append("WARNING: Invalid network hashrate received: " . var_export($dNetworkHashrate, true) . ", returning 0", 2);
      return $this->memcache->setCache($cacheKey, 0, 3600);
    }
    
    return $this->memcache->setCache($cacheKey, $dNetworkHashrate, 30);
  }
}

// Load this wrapper
$bitcoin = new BitcoinWrapper($config['wallet']['type'], $config['wallet']['username'], $config['wallet']['password'], $config['wallet']['host'], $config['DEBUG'], $debug, $memcache);
$bitcoin_mm = new BitcoinWrapper($config['wallet_mm']['type'], $config['wallet_mm']['username'], $config['wallet_mm']['password'], $config['wallet_mm']['host'], $config['DEBUG'], $debug, $memcache_mm);
$bitcoin_mm1 = new BitcoinWrapper($config['wallet_mm1']['type'], $config['wallet_mm1']['username'], $config['wallet_mm1']['password'], $config['wallet_mm1']['host'], $config['DEBUG'], $debug, $memcache_mm1);
$bitcoin_mm3 = new BitcoinWrapper($config['wallet_mm3']['type'], $config['wallet_mm3']['username'], $config['wallet_mm3']['password'], $config['wallet_mm3']['host'], $config['DEBUG'], $debug, $memcache_mm3);
$bitcoin_mm4 = new BitcoinWrapper($config['wallet_mm4']['type'], $config['wallet_mm4']['username'], $config['wallet_mm4']['password'], $config['wallet_mm4']['host'], $config['DEBUG'], $debug, $memcache_mm4);
$bitcoin_mm5 = new BitcoinWrapper($config['wallet_mm5']['type'], $config['wallet_mm5']['username'], $config['wallet_mm5']['password'], $config['wallet_mm5']['host'], $config['DEBUG'], $debug, $memcache_mm5);
