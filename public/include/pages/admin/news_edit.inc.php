<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

// Check user to ensure they are admin
if (!$user->isAuthenticated() || !$user->isAdmin($_SESSION['USERDATA']['id'])) {
  header("HTTP/1.1 404 Page not found");
  die("404 Page not found");
}

// CSRF + method enforcement on admin/news_edit mutations.
require_once dirname(__FILE__) . '/../../admin_csrf.inc.php';
_require_admin_csrf($csrftoken);

// Include markdown library
use \Michelf\Markdown;

if (@$_REQUEST['do'] == 'save') {
  $show_on = isset($_REQUEST['show_on']) ? (string)$_REQUEST['show_on'] : 'home';
  if ($news->updateNews($_REQUEST['id'], $_REQUEST['header'], $_REQUEST['content'], $_REQUEST['active'], $show_on)) {
    $_SESSION['POPUP'][] = array('CONTENT' => 'News updated', 'TYPE' => 'success');
  } else {
    $_SESSION['POPUP'][] = array('CONTENT' => 'News update failed: ' . $news->getError(), 'TYPE' => 'errormsg');
  }
}

// Fetch news entry
$aNews = $news->getEntry($_REQUEST['id']);
$smarty->assign("NEWS", $aNews);
$smarty->assign("CONTENT", "default.tpl");
?>
