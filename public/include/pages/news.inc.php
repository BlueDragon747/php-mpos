<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

// Include markdown library
use \Michelf\Markdown;
require_once INCLUDE_DIR . '/safe_markdown.inc.php';

// Fetch active news to display
$aNews = $news->getAllActive();
if (is_array($aNews)) {
  foreach ($aNews as $key => $aData) {
    $aNews[$key]['content'] = mpos_render_safe_markdown($aData['content']);
  }
}

// Tempalte specifics
$smarty->assign("HIDEAUTHOR", $settings->getValue('acl_hide_news_author'));
$smarty->assign("NEWS", $aNews);
$smarty->assign("CONTENT", "default.tpl");
?>
