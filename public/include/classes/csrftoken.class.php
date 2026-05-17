<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

class CSRFToken Extends Base {
  public $valid = 0;
  /**
   * Gets a basic csrf token
   * @param string $user user or IP/host address
   * @param string $type page name or other unique per-page identifier
   */
  public function getBasic($user, $type) {
    $date = date('m/d/y/H/i');
    $d = explode('/', $date);
    $seed = $this->buildSeed($user.$type, $d[0], $d[1], $d[2], $d[3], $d[4]);
    return $this->getHash($seed);
  }
  
  /**
   * Returns +1 min and +1 hour rollovers hashes
   * @param string $user user or IP/host address
   * @param string $type page name or other unique per-page identifier
   * @return array 1min and 1hour hashes
   */
  public function checkAdditional($user, $type) {
    $date = date('m/d/y/H/i');
    $d = explode('/', $date);
    // minute may have rolled over
    $seed1 = $this->buildSeed($user.$type, $d[0], $d[1], $d[2], $d[3], ($d[4]-1));
    // hour may have rolled over
    $seed2 = $this->buildSeed($user.$type, $d[0], $d[1], $d[2], ($d[3]-1), 59);
    return array($this->getHash($seed1), $this->getHash($seed2));
  }
  
  /**
   * Builds a seed with the given data
   * @param string $data
   * @param int $year
   * @param int $month
   * @param int $day
   * @param int $hour
   * @param int $minute
   * @return string seed
   */
  private function buildSeed($data, $year, $month, $day, $hour, $minute) {
    return $this->salty.$year.$month.$day.$data.$hour.$minute.$this->salt;
  }
  
  /**
   * Checks if the token is correct as is, if not checks for rollovers with checkAdditional()
   * @param string $user user or IP/host address
   * @param string $type page name or other unique per-page identifier
   * @param string $token token to check against
   * @return boolean
   */
  public function checkBasic($user, $type, $token) {
    if (empty($token)) return false;
    $token_now = $this->getBasic($user, $type);
    if ($token_now !== $token) {
      $tokens_check = $this->checkAdditional($user, $type);
      $match = 0;
      foreach ($tokens_check as $checkit) {
        if ($checkit == $token) $match = 1;
      }
      return ($match) ? true : false;
    } else {
      return true;
    }
  }
  
  /**
   * Plain-text "session expired" message shown to a user when a
   * page-level CSRF token didn't match. Returned as a single line of
   * text — no HTML — so the v2 SPA can render it via text interpolation
   * without leaking raw markup, and legacy Smarty templates can show it
   * as-is. The questionmark-image tooltip from the upstream version is
   * dropped: the message itself is enough, and the operator-facing
   * "tokens mitigate attacks" tooltip never told end users anything
   * actionable.
   * @param string $tokentype optional context (e.g. "withdraw")
   * @param string $dowhat unused; kept for upstream signature parity
   */
  public static function getErrorWithDescriptionHTML($tokentype="", $dowhat="try") {
    if ($tokentype !== "") {
      return "Your session has expired. Please try " . $tokentype . " again.";
    }
    return "Your session has expired. Please try again.";
  }

  /**
   * Back-compat stub for any caller that still wants the legacy
   * questionmark-image tooltip. The v2 SPA never renders HTML in
   * popups, so this returns an empty string by default; if you want
   * to surface the tooltip in a legacy Smarty page, override there.
   */
  public static function getDescriptionImageHTML($dowhat="try") {
    return "";
  }
  
  private function getHash($string) {
    return hash('sha256', $this->salty.$string.$this->salt);
  }
}

$csrftoken = new CSRFToken();
$csrftoken->setDebug($debug);
$csrftoken->setMysql($mysqli);
$csrftoken->setSalt($config['SALT']);
$csrftoken->setSalty($config['SALTY']);
$csrftoken->setMail($mail);
$csrftoken->setUser($user);
$csrftoken->setToken($oToken);
$csrftoken->setConfig($config);
$csrftoken->setErrorCodes($aErrorCodes);
?>