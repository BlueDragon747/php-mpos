<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

// Check user to ensure they are admin
if (!$user->isAuthenticated() || !$user->isAdmin($_SESSION['USERDATA']['id'])) {
  header("HTTP/1.1 404 Page not found");
  die("404 Page not found");
}

// CSRF + method enforcement on admin/templates mutations
// (theme/template save, file edits).
require_once dirname(__FILE__) . '/../../admin_csrf.inc.php';
_require_admin_csrf($csrftoken);

$aThemes = $template->getThemes();
$aTemplates = $template->getTemplatesTree($aThemes);
$aActiveTemplates = $template->cachedGetActiveTemplates();

$aFlatTemplatesList = array();
foreach($aThemes as $sTheme) {
  $templates = $template->getTemplateFiles($sTheme);
  $aFlatTemplatesList = array_merge($aFlatTemplatesList, $templates);
}

//Fetch current slug and template
$sTemplate = @$_REQUEST['template'];
if(!in_array($sTemplate, $aFlatTemplatesList)) {
  $sTemplate = $aFlatTemplatesList[0];
}

$sOriginalTemplate = $template->getTemplateContent($sTemplate);

if (@$_REQUEST['do'] == 'save') {
  if ($template->updateEntry(@$_REQUEST['template'], @$_REQUEST['content'], @$_REQUEST['active'])) {
    $_SESSION['POPUP'][] = array('CONTENT' => 'Page updated', 'TYPE' => 'success');
  } else {
    $_SESSION['POPUP'][] = array('CONTENT' => 'Page update failed: ' . $template->getError(), 'TYPE' => 'errormsg');
  }
}

$oDatabaseTemplate = $template->getEntry($sTemplate);

if ( $oDatabaseTemplate === false ) {
  $_SESSION['POPUP'][] = array('CONTENT' => 'Can\'t fetch template from Database. Have you created `templates` table? Run 005_create_templates_table.sql from sql folder', 'TYPE' => 'errormsg');
}

// AJAX path: when the page is requested with _ajax=1 (e.g. from the
// in-page tree click handler), return just the data the editor needs
// to swap in place. Avoids re-rendering master.tpl + reloading the
// dynatree, which is what was resetting the scroll position.
if (!empty($_REQUEST['_ajax'])) {
  header('Content-Type: application/json; charset=utf-8');
  echo json_encode(array(
    'currentTemplate'  => $sTemplate,
    'originalContent'  => $sOriginalTemplate,
    'databaseTemplate' => $oDatabaseTemplate ?: null,
  ));
  exit;
}

$smarty->assign("TEMPLATES", $aTemplates);
$smarty->assign("ACTIVE_TEMPLATES", $aActiveTemplates);
$smarty->assign("CURRENT_TEMPLATE", $sTemplate);
$smarty->assign("ORIGINAL_TEMPLATE", $sOriginalTemplate);
$smarty->assign("DATABASE_TEMPLATE", $oDatabaseTemplate);
$smarty->assign("CONTENT", "default.tpl");
?>
