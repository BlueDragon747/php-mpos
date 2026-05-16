<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

#[\AllowDynamicProperties]
class Payout Extends Base {
  protected $table = 'payouts';
  protected $table_mm = 'payouts_mm';
  protected $table_mm1 = 'payouts_mm1';
  protected $table_mm3 = 'payouts_mm3';
  protected $table_mm4 = 'payouts_mm4';
  protected $table_mm5 = 'payouts_mm5';


  public function getTableNameMM() {
    return $this->table_mm;
  }
  public function getTableNameMM1() {
    return $this->table_mm1;
  }
  public function getTableNameMM3() {
    return $this->table_mm3;
  }
  public function getTableNameMM4() {
    return $this->table_mm4;
  }
  public function getTableNameMM5() {
    return $this->table_mm5;
  }


  /**
   * Check if the user has an active payout request already
   * @param account_id int Account ID
   * @return boolean bool True of False
   **/
  public function isPayoutActive($account_id) {
    $stmt = $this->mysqli->prepare("SELECT id FROM $this->table WHERE completed = 0 AND account_id = ? LIMIT 1");
    if ($stmt && $stmt->bind_param('i', $account_id) && $stmt->execute( )&& $stmt->store_result() && $stmt->num_rows > 0)
      return true;
    return $this->sqlError('E0048');
  }

  public function isPayoutActive_mm($account_id) {
    $stmt = $this->mysqli->prepare("SELECT id FROM $this->table_mm WHERE completed = 0 AND account_id = ? LIMIT 1");
    if ($stmt && $stmt->bind_param('i', $account_id) && $stmt->execute( )&& $stmt->store_result() && $stmt->num_rows > 0)
      return true;
    return $this->sqlError('E0048');
  }
  public function isPayoutActive_mm1($account_id) {
    $stmt = $this->mysqli->prepare("SELECT id FROM $this->table_mm1 WHERE completed = 0 AND account_id = ? LIMIT 1");
    if ($stmt && $stmt->bind_param('i', $account_id) && $stmt->execute( )&& $stmt->store_result() && $stmt->num_rows > 0)
      return true;
    return $this->sqlError('E0048');
  }

  public function isPayoutActive_mm3($account_id) {
    $stmt = $this->mysqli->prepare("SELECT id FROM $this->table_mm3 WHERE completed = 0 AND account_id = ? LIMIT 1");
    if ($stmt && $stmt->bind_param('i', $account_id) && $stmt->execute( )&& $stmt->store_result() && $stmt->num_rows > 0)
      return true;
    return $this->sqlError('E0048');
  }
  public function isPayoutActive_mm4($account_id) {
    $stmt = $this->mysqli->prepare("SELECT id FROM $this->table_mm4 WHERE completed = 0 AND account_id = ? LIMIT 1");
    if ($stmt && $stmt->bind_param('i', $account_id) && $stmt->execute( )&& $stmt->store_result() && $stmt->num_rows > 0)
      return true;
    return $this->sqlError('E0048');
  }
  public function isPayoutActive_mm5($account_id) {
    $stmt = $this->mysqli->prepare("SELECT id FROM $this->table_mm5 WHERE completed = 0 AND account_id = ? LIMIT 1");
    if ($stmt && $stmt->bind_param('i', $account_id) && $stmt->execute( )&& $stmt->store_result() && $stmt->num_rows > 0)
      return true;
    return $this->sqlError('E0048');
  }

  /**
   * Insert a new payout request
   * @param account_id int Account ID
   * @param strToken string Token to confirm
   * @return data mixed Inserted ID or false
   **/
  public function createPayout($account_id = NULL, $strToken = NULL) {
    // INSERT...SELECT...WHERE NOT EXISTS makes the active-payout
    // check atomic: a second concurrent request can't see "no active
    // payout" and still insert a row, since both inserts race on the
    // same row-level lock. Zero affected_rows = already-active.
    $stmt = $this->mysqli->prepare(
      "INSERT INTO $this->table (account_id) "
      . "SELECT ? FROM DUAL WHERE NOT EXISTS ("
      . "  SELECT 1 FROM $this->table WHERE account_id = ? AND completed = 0"
      . ")"
    );
    $exec_ok = $stmt && $stmt->bind_param('ii', $account_id, $account_id) && $stmt->execute();
    // MariaDB error 1467 (ER_AUTOINC_READ_FAILED) fires when extreme
    // concurrency on this INSERT...SELECT pattern exhausts the
    // auto-increment pre-allocation. Same race outcome as
    // affected_rows=0 — another concurrent request already inserted
    // the row, so treat it as "already active" rather than a raw SQL
    // error.
    if (!$exec_ok && $this->mysqli->errno === 1467) {
      $this->setErrorMessage('You already have one active manual payout request.');
      return false;
    }
    if ($exec_ok) {
      if ($stmt->affected_rows === 0) {
        $this->setErrorMessage('You already have one active manual payout request.');
        return false;
      }
      // twofactor - consume the token if it is enabled and valid
      if ($this->config['twofactor']['enabled'] && $this->config['twofactor']['options']['withdraw']) {
        $tValid = $this->token->isTokenValid($account_id, $strToken, 7);
        if ($tValid) {
          $delete = $this->token->deleteToken($strToken);
          if ($delete) {
            return true;
          } else {
            $this->log->log("info", "User $account_id requested manual payout but failed to delete payout token");
            $this->setErrorMessage("Couldn't consume the confirmation token. Please try the cash-out again.");
            return false;
          }
        } else {
          $this->log->log("info", "User $account_id requested manual payout using an invalid payout token");
          $this->setErrorMessage('Your withdraw confirmation has expired. Please start the cash-out again.');
          return false;
        }
      }
      return $stmt->insert_id;
    }
    return $this->sqlError('E0049');
  }

  public function createPayout_mm($account_id = NULL, $strToken = NULL) {
    $stmt = $this->mysqli->prepare(
      "INSERT INTO $this->table_mm (account_id) "
      . "SELECT ? FROM DUAL WHERE NOT EXISTS ("
      . "  SELECT 1 FROM $this->table_mm WHERE account_id = ? AND completed = 0"
      . ")"
    );
    $exec_ok = $stmt && $stmt->bind_param('ii', $account_id, $account_id) && $stmt->execute();
    // MariaDB error 1467 (ER_AUTOINC_READ_FAILED) fires when extreme
    // concurrency on this INSERT...SELECT pattern exhausts the
    // auto-increment pre-allocation. Same race outcome as
    // affected_rows=0 — another concurrent request already inserted
    // the row, so treat it as "already active" rather than a raw SQL
    // error.
    if (!$exec_ok && $this->mysqli->errno === 1467) {
      $this->setErrorMessage('You already have one active manual payout request.');
      return false;
    }
    if ($exec_ok) {
      if ($stmt->affected_rows === 0) {
        $this->setErrorMessage('You already have one active manual payout request.');
        return false;
      }
      // twofactor - consume the token if it is enabled and valid
      if ($this->config['twofactor']['enabled'] && $this->config['twofactor']['options']['withdraw']) {
        $tValid = $this->token->isTokenValid($account_id, $strToken, 7);
        if ($tValid) {
          $delete = $this->token->deleteToken($strToken);
          if ($delete) {
            return true;
          } else {
            $this->log->log("info", "User $account_id requested manual payout but failed to delete payout token");
            $this->setErrorMessage("Couldn't consume the confirmation token. Please try the cash-out again.");
            return false;
          }
        } else {
          $this->log->log("info", "User $account_id requested manual payout using an invalid payout token");
          $this->setErrorMessage('Your withdraw confirmation has expired. Please start the cash-out again.');
          return false;
        }
      }
      return $stmt->insert_id;
    }
    return $this->sqlError('E0049');
  }

  public function createPayout_mm1($account_id = NULL, $strToken = NULL) {
    $stmt = $this->mysqli->prepare(
      "INSERT INTO $this->table_mm1 (account_id) "
      . "SELECT ? FROM DUAL WHERE NOT EXISTS ("
      . "  SELECT 1 FROM $this->table_mm1 WHERE account_id = ? AND completed = 0"
      . ")"
    );
    $exec_ok = $stmt && $stmt->bind_param('ii', $account_id, $account_id) && $stmt->execute();
    // MariaDB error 1467 (ER_AUTOINC_READ_FAILED) fires when extreme
    // concurrency on this INSERT...SELECT pattern exhausts the
    // auto-increment pre-allocation. Same race outcome as
    // affected_rows=0 — another concurrent request already inserted
    // the row, so treat it as "already active" rather than a raw SQL
    // error.
    if (!$exec_ok && $this->mysqli->errno === 1467) {
      $this->setErrorMessage('You already have one active manual payout request.');
      return false;
    }
    if ($exec_ok) {
      if ($stmt->affected_rows === 0) {
        $this->setErrorMessage('You already have one active manual payout request.');
        return false;
      }
      // twofactor - consume the token if it is enabled and valid
      if ($this->config['twofactor']['enabled'] && $this->config['twofactor']['options']['withdraw']) {
        $tValid = $this->token->isTokenValid($account_id, $strToken, 7);
        if ($tValid) {
          $delete = $this->token->deleteToken($strToken);
          if ($delete) {
            return true;
          } else {
            $this->log->log("info", "User $account_id requested manual payout but failed to delete payout token");
            $this->setErrorMessage("Couldn't consume the confirmation token. Please try the cash-out again.");
            return false;
          }
        } else {
          $this->log->log("info", "User $account_id requested manual payout using an invalid payout token");
          $this->setErrorMessage('Your withdraw confirmation has expired. Please start the cash-out again.');
          return false;
        }
      }
      return $stmt->insert_id;
    }
    return $this->sqlError('E0049');
  }


  public function createPayout_mm3($account_id = NULL, $strToken = NULL) {
    $stmt = $this->mysqli->prepare(
      "INSERT INTO $this->table_mm3 (account_id) "
      . "SELECT ? FROM DUAL WHERE NOT EXISTS ("
      . "  SELECT 1 FROM $this->table_mm3 WHERE account_id = ? AND completed = 0"
      . ")"
    );
    $exec_ok = $stmt && $stmt->bind_param('ii', $account_id, $account_id) && $stmt->execute();
    // MariaDB error 1467 (ER_AUTOINC_READ_FAILED) fires when extreme
    // concurrency on this INSERT...SELECT pattern exhausts the
    // auto-increment pre-allocation. Same race outcome as
    // affected_rows=0 — another concurrent request already inserted
    // the row, so treat it as "already active" rather than a raw SQL
    // error.
    if (!$exec_ok && $this->mysqli->errno === 1467) {
      $this->setErrorMessage('You already have one active manual payout request.');
      return false;
    }
    if ($exec_ok) {
      if ($stmt->affected_rows === 0) {
        $this->setErrorMessage('You already have one active manual payout request.');
        return false;
      }
      // twofactor - consume the token if it is enabled and valid
      if ($this->config['twofactor']['enabled'] && $this->config['twofactor']['options']['withdraw']) {
        $tValid = $this->token->isTokenValid($account_id, $strToken, 7);
        if ($tValid) {
          $delete = $this->token->deleteToken($strToken);
          if ($delete) {
            return true;
          } else {
            $this->log->log("info", "User $account_id requested manual payout but failed to delete payout token");
            $this->setErrorMessage("Couldn't consume the confirmation token. Please try the cash-out again.");
            return false;
          }
        } else {
          $this->log->log("info", "User $account_id requested manual payout using an invalid payout token");
          $this->setErrorMessage('Your withdraw confirmation has expired. Please start the cash-out again.');
          return false;
        }
      }
      return $stmt->insert_id;
    }
    return $this->sqlError('E0049');
  }
  public function createPayout_mm4($account_id = NULL, $strToken = NULL) {
    $stmt = $this->mysqli->prepare(
      "INSERT INTO $this->table_mm4 (account_id) "
      . "SELECT ? FROM DUAL WHERE NOT EXISTS ("
      . "  SELECT 1 FROM $this->table_mm4 WHERE account_id = ? AND completed = 0"
      . ")"
    );
    $exec_ok = $stmt && $stmt->bind_param('ii', $account_id, $account_id) && $stmt->execute();
    // MariaDB error 1467 (ER_AUTOINC_READ_FAILED) fires when extreme
    // concurrency on this INSERT...SELECT pattern exhausts the
    // auto-increment pre-allocation. Same race outcome as
    // affected_rows=0 — another concurrent request already inserted
    // the row, so treat it as "already active" rather than a raw SQL
    // error.
    if (!$exec_ok && $this->mysqli->errno === 1467) {
      $this->setErrorMessage('You already have one active manual payout request.');
      return false;
    }
    if ($exec_ok) {
      if ($stmt->affected_rows === 0) {
        $this->setErrorMessage('You already have one active manual payout request.');
        return false;
      }
      // twofactor - consume the token if it is enabled and valid
      if ($this->config['twofactor']['enabled'] && $this->config['twofactor']['options']['withdraw']) {
        $tValid = $this->token->isTokenValid($account_id, $strToken, 7);
        if ($tValid) {
          $delete = $this->token->deleteToken($strToken);
          if ($delete) {
            return true;
          } else {
            $this->log->log("info", "User $account_id requested manual payout but failed to delete payout token");
            $this->setErrorMessage("Couldn't consume the confirmation token. Please try the cash-out again.");
            return false;
          }
        } else {
          $this->log->log("info", "User $account_id requested manual payout using an invalid payout token");
          $this->setErrorMessage('Your withdraw confirmation has expired. Please start the cash-out again.');
          return false;
        }
      }
      return $stmt->insert_id;
    }
    return $this->sqlError('E0049');
  }
  public function createPayout_mm5($account_id = NULL, $strToken = NULL) {
    $stmt = $this->mysqli->prepare(
      "INSERT INTO $this->table_mm5 (account_id) "
      . "SELECT ? FROM DUAL WHERE NOT EXISTS ("
      . "  SELECT 1 FROM $this->table_mm5 WHERE account_id = ? AND completed = 0"
      . ")"
    );
    $exec_ok = $stmt && $stmt->bind_param('ii', $account_id, $account_id) && $stmt->execute();
    // MariaDB error 1467 (ER_AUTOINC_READ_FAILED) fires when extreme
    // concurrency on this INSERT...SELECT pattern exhausts the
    // auto-increment pre-allocation. Same race outcome as
    // affected_rows=0 — another concurrent request already inserted
    // the row, so treat it as "already active" rather than a raw SQL
    // error.
    if (!$exec_ok && $this->mysqli->errno === 1467) {
      $this->setErrorMessage('You already have one active manual payout request.');
      return false;
    }
    if ($exec_ok) {
      if ($stmt->affected_rows === 0) {
        $this->setErrorMessage('You already have one active manual payout request.');
        return false;
      }
      // twofactor - consume the token if it is enabled and valid
      if ($this->config['twofactor']['enabled'] && $this->config['twofactor']['options']['withdraw']) {
        $tValid = $this->token->isTokenValid($account_id, $strToken, 7);
        if ($tValid) {
          $delete = $this->token->deleteToken($strToken);
          if ($delete) {
            return true;
          } else {
            $this->log->log("info", "User $account_id requested manual payout but failed to delete payout token");
            $this->setErrorMessage("Couldn't consume the confirmation token. Please try the cash-out again.");
            return false;
          }
        } else {
          $this->log->log("info", "User $account_id requested manual payout using an invalid payout token");
          $this->setErrorMessage('Your withdraw confirmation has expired. Please start the cash-out again.');
          return false;
        }
      }
      return $stmt->insert_id;
    }
    return $this->sqlError('E0049');
  }
  
  /**
   * Mark a payout as processed
   * @param id int Payout ID
   * @return boolean bool True or False
   **/
  public function setProcessed($id) {
    $stmt = $this->mysqli->prepare("UPDATE $this->table SET completed = 1 WHERE id = ? LIMIT 1");
    if ($stmt && $stmt->bind_param('i', $id) && $stmt->execute())
      return true;
    return $this->sqlError('E0051');
  }
  
  public function setProcessed_mm($id) {
    $stmt = $this->mysqli->prepare("UPDATE $this->table_mm SET completed = 1 WHERE id = ? LIMIT 1");
    if ($stmt && $stmt->bind_param('i', $id) && $stmt->execute())
      return true;
    return $this->sqlError('E0051');
  }
  public function setProcessed_mm1($id) {
    $stmt = $this->mysqli->prepare("UPDATE $this->table_mm1 SET completed = 1 WHERE id = ? LIMIT 1");
    if ($stmt && $stmt->bind_param('i', $id) && $stmt->execute())
      return true;
    return $this->sqlError('E0051');
  }

  public function setProcessed_mm2($id) {
    $stmt = $this->mysqli->prepare("UPDATE $this->table_mm2 SET completed = 1 WHERE id = ? LIMIT 1");
    if ($stmt && $stmt->bind_param('i', $id) && $stmt->execute())
      return true;
    return $this->sqlError('E0051');
  }

  public function setProcessed_mm3($id) {
    $stmt = $this->mysqli->prepare("UPDATE $this->table_mm3 SET completed = 1 WHERE id = ? LIMIT 1");
    if ($stmt && $stmt->bind_param('i', $id) && $stmt->execute())
      return true;
    return $this->sqlError('E0051');
  }
  public function setProcessed_mm4($id) {
    $stmt = $this->mysqli->prepare("UPDATE $this->table_mm4 SET completed = 1 WHERE id = ? LIMIT 1");
    if ($stmt && $stmt->bind_param('i', $id) && $stmt->execute())
      return true;
    return $this->sqlError('E0051');
  }
  public function setProcessed_mm5($id) {
    $stmt = $this->mysqli->prepare("UPDATE $this->table_mm5 SET completed = 1 WHERE id = ? LIMIT 1");
    if ($stmt && $stmt->bind_param('i', $id) && $stmt->execute())
      return true;
    return $this->sqlError('E0051');
  }

}

$oPayout = new Payout();
$oPayout->setDebug($debug);
$oPayout->setLog($log);
$oPayout->setMysql($mysqli);
$oPayout->setConfig($config);
$oPayout->setToken($oToken);
$oPayout->setErrorCodes($aErrorCodes);

?>
