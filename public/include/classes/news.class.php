<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

class News extends Base {
  protected $table = 'news';

  /**
   * Get activation status of post
   * @param id int News ID
   * @return bool true or false
   **/
  public function getActive($id) {
    $this->debug->append("STA " . __METHOD__, 5);
    return $this->getSingle($id, 'active', 'id');
  }

  /**
   * Switch activation status
   * @param id int News ID
   * @return bool true or false
   **/
  public function toggleActive($id) {
    $this->debug->append("STA " . __METHOD__, 5);
    $field = array('name' => 'active', 'type' => 'i', 'value' => !$this->getActive($id));
    return $this->updateSingle($id, $field);
  }

  /**
   * Set placement (show_on) for a news entry.
   **/
  public function setShowOn($id, $show_on) {
    $this->debug->append("STA " . __METHOD__, 5);
    if (!in_array($show_on, array('home','dashboard','both'), true)) return false;
    $stmt = $this->mysqli->prepare("UPDATE $this->table SET show_on = ? WHERE id = ?");
    if ($stmt && $stmt->bind_param('si', $show_on, $id) && $stmt->execute())
      return true;
    return $this->sqlError('E0037');
  }

  /**
   * Get all active news
   **/
  public function getAllActive() {
    $this->debug->append("STA " . __METHOD__, 4);
    $stmt = $this->mysqli->prepare("SELECT n.*, a.username AS author FROM $this->table AS n LEFT JOIN " . $this->user->getTableName() . " AS a ON a.id = n.account_id WHERE active = 1 ORDER BY time DESC");
    if ($stmt && $stmt->execute() && $result = $stmt->get_result())
      return $result->fetch_all(MYSQLI_ASSOC);
    return $this->sqlError('E0040');
  }

  /**
   * Get active news for a placement: 'home' or 'dashboard'.
   * Includes entries set to 'both'.
   **/
  public function getAllActiveFor($placement) {
    $this->debug->append("STA " . __METHOD__, 4);
    if ($placement !== 'home' && $placement !== 'dashboard') return array();
    $stmt = $this->mysqli->prepare("SELECT n.*, a.username AS author FROM $this->table AS n LEFT JOIN " . $this->user->getTableName() . " AS a ON a.id = n.account_id WHERE active = 1 AND (show_on = ? OR show_on = 'both') ORDER BY time DESC");
    if ($stmt && $stmt->bind_param('s', $placement) && $stmt->execute() && $result = $stmt->get_result())
      return $result->fetch_all(MYSQLI_ASSOC);
    return $this->sqlError('E0040');
  }

  /**
   * Get all news
   **/
  public function getAll() {
    $this->debug->append("STA " . __METHOD__, 4);
    $stmt = $this->mysqli->prepare("SELECT n.*, a.username AS author FROM $this->table AS n LEFT JOIN " . $this->user->getTableName() . " AS a ON a.id = n.account_id ORDER BY time DESC");
    if ($stmt && $stmt->execute() && $result = $stmt->get_result())
      return $result->fetch_all(MYSQLI_ASSOC);
    return $this->sqlError('E0039');
  }

  /**
   * Get a specific news entry
   **/
  public function getEntry($id) {
    $this->debug->append("STA " . __METHOD__, 4);
    $stmt = $this->mysqli->prepare("SELECT * FROM $this->table WHERE id = ?");
    if ($stmt && $stmt->bind_param('i', $id) && $stmt->execute() && $result = $stmt->get_result())
      return $result->fetch_assoc();
    return $this->sqlError('E0038');
  }

  /**
   * Update a news entry
   **/
  public function updateNews($id, $header, $content, $active=0, $show_on='home') {
    $this->debug->append("STA " . __METHOD__, 4);
    if (!in_array($show_on, array('home','dashboard','both'), true)) $show_on = 'home';
    $stmt = $this->mysqli->prepare("UPDATE $this->table SET content = ?, header = ?, active = ?, show_on = ? WHERE id = ?");
    if ($stmt && $stmt->bind_param('ssisi', $content, $header, $active, $show_on, $id) && $stmt->execute() && $stmt->affected_rows == 1)
      return true;
    return $this->sqlError('E0037');
  }

  public function deleteNews($id) {
    $this->debug->append("STA " . __METHOD__, 4);
    if (!is_int($id)) return false;
    $stmt = $this->mysqli->prepare("DELETE FROM $this->table WHERE id = ?");
    if ($this->checkStmt($stmt) && $stmt->bind_param('i', $id) && $stmt->execute() && $stmt->affected_rows == 1)
      return true;
    return $this->sqlError('E0036');
  }

  /**
   * Add a new mews entry to the table
   * @param type string Type of the notification
   * @return bool
   **/
  public function addNews($account_id, $aData, $active=false) {
    $this->debug->append("STA " . __METHOD__, 4);
    if (empty($aData['header'])) return false;
    if (empty($aData['content'])) return false;
    if (!is_int($account_id)) return false;
    $show_on = isset($aData['show_on']) ? (string)$aData['show_on'] : 'home';
    if (!in_array($show_on, array('home','dashboard','both'), true)) $show_on = 'home';
    $iActive = $active ? 1 : 0;
    $stmt = $this->mysqli->prepare("INSERT INTO $this->table (account_id, header, content, active, show_on) VALUES (?,?,?,?,?)");
    if ($stmt && $stmt->bind_param('issis', $account_id, $aData['header'], $aData['content'], $iActive, $show_on) && $stmt->execute())
      return true;
    return $this->sqlError('E0035');
  }
}

$news = new News();
$news->setDebug($debug);
$news->setMysql($mysqli);
$news->setUser($user);
$news->setErrorCodes($aErrorCodes);
?>
