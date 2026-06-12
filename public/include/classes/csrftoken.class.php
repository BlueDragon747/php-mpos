<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

class CSRFToken Extends Base {
  public $valid = 0;

  /**
   * Per-session CSRF secret. Generated once per session with a CSPRNG and
   * stored in $_SESSION, so tokens are bound to the browser session rather
   * than to the client IP and a wall-clock minute. Falls back to the server
   * salt only when no session is active, which does not occur in the normal
   * request flow — bootstrap.php starts the session before CSRF runs.
   * @return string secret
   */
  private function sessionSecret() {
    if (session_status() === PHP_SESSION_ACTIVE) {
      if (empty($_SESSION['CSRF_SECRET']) || !is_string($_SESSION['CSRF_SECRET'])) {
        $_SESSION['CSRF_SECRET'] = bin2hex(random_bytes(32));
      }
      return $_SESSION['CSRF_SECRET'];
    }
    return (string)$this->salty . '|' . (string)$this->salt;
  }

  /**
   * Returns the CSRF token for a page, bound to the session secret.
   * @param string $user kept for signature parity; no longer seeds the
   *                     token (the old client-IP binding is removed)
   * @param string $type page name or other unique per-page identifier
   * @return string token
   */
  public function getBasic($user, $type) {
    return hash_hmac('sha256', (string)$type, $this->sessionSecret());
  }

  /**
   * Validates a submitted token against this session's token for the page,
   * using a constant-time comparison.
   * @param string $user kept for signature parity (unused)
   * @param string $type page name or other unique per-page identifier
   * @param string $token token to check against
   * @return boolean
   */
  public function checkBasic($user, $type, $token) {
    if (!is_string($token) || $token === '') return false;
    return hash_equals($this->getBasic($user, $type), $token);
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