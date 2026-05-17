<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

// Include markdown library
use \Michelf\Markdown;
require_once INCLUDE_DIR . '/safe_markdown.inc.php';

if (!$smarty->isCached('master.tpl', $smarty_cache_key)) {
  $debug->append('No cached version available, fetching from backend', 3);
  // Fetch active news to display
  $aNews = method_exists($news, 'getAllActiveFor') ? $news->getAllActiveFor('home') : $news->getAllActive();
  if (is_array($aNews)) {
    foreach ($aNews as $key => $aData) {
      $aNews[$key]['content'] = mpos_render_safe_markdown($aData['content']);
    }
  }

  $smarty->assign("HIDEAUTHOR", $setting->getValue('acl_hide_news_author'));
  $smarty->assign("NEWS", $aNews);
} else {
  $debug->append('Using cached page', 3);
}
// Load news entries for Desktop site and unauthenticated users
$smarty->assign("CONTENT", "default.tpl");
?>
