<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

// Check user to ensure they are admin
if (!$user->isAuthenticated() || !$user->isAdmin($_SESSION['USERDATA']['id'])) {
  header("HTTP/1.1 404 Page not found");
  die("404 Page not found");
}

// CSRF + method enforcement. No-op for GET landing page, rejects any
// GET that carries a mutation param, requires valid ctoken on POST.
require_once dirname(__FILE__) . '/../../admin_csrf.inc.php';
_require_admin_csrf($csrftoken);
require_once INCLUDE_DIR . '/safe_markdown.inc.php';

use \Michelf\Markdown;

if (@$_REQUEST['do'] == 'toggle_active') {
  if ($news->toggleActive($_REQUEST['id']))
    $_SESSION['POPUP'][] = array('CONTENT' => 'News entry changed', 'TYPE' => 'success');
}

if (@$_REQUEST['do'] == 'set_show_on') {
  $newShowOn = isset($_REQUEST['show_on']) ? (string)$_REQUEST['show_on'] : '';
  if ($news->setShowOn((int)$_REQUEST['id'], $newShowOn)) {
    $_SESSION['POPUP'][] = array('CONTENT' => 'Placement updated', 'TYPE' => 'success');
  } else {
    $_SESSION['POPUP'][] = array('CONTENT' => 'Failed to update placement: ' . $news->getError(), 'TYPE' => 'errormsg');
  }
}

if (@$_REQUEST['do'] == 'add') {
  if ($news->addNews($_SESSION['USERDATA']['id'], $_POST['data'])) {
    $_SESSION['POPUP'][] = array('CONTENT' => 'News entry added', 'TYPE' => 'success');
  } else {
    $_SESSION['POPUP'][] = array('CONTENT' => 'Failed to add new entry: ' . $news->getError(), 'TYPE' => 'errormsg');
  }
}

// Update folded in from the (now-deprecated) news_edit page so the SPA
// can edit-in-place from the same form.
if (@$_REQUEST['do'] == 'update') {
  $iId      = isset($_REQUEST['id'])      ? (int)$_REQUEST['id'] : 0;
  $sHeader  = isset($_REQUEST['header'])  ? (string)$_REQUEST['header']  : '';
  $sContent = isset($_REQUEST['content']) ? (string)$_REQUEST['content'] : '';
  $iActive  = isset($_REQUEST['active'])  ? (int)$_REQUEST['active']     : 0;
  $sShowOn  = isset($_REQUEST['show_on']) ? (string)$_REQUEST['show_on'] : 'home';
  if ($news->updateNews($iId, $sHeader, $sContent, $iActive, $sShowOn)) {
    $_SESSION['POPUP'][] = array('CONTENT' => 'News updated', 'TYPE' => 'success');
  } else {
    $_SESSION['POPUP'][] = array('CONTENT' => 'News update failed: ' . $news->getError(), 'TYPE' => 'errormsg');
  }
}

if (@$_REQUEST['do'] == 'delete') {
  if ($news->deleteNews((int)$_REQUEST['id'])) {
    $_SESSION['POPUP'][] = array('CONTENT' => 'Successfully removed news entry', 'TYPE' => 'success');
  } else {
    $_SESSION['POPUP'][] = array('CONTENT' => 'Failed to delete entry: ' . $news->getError(), 'TYPE' => 'errormsg');
  }
}

/**
 * Render Markdown → HTML with raw HTML stripped + dangerous URL
 * schemes neutralised. Output goes to v-html in the SPA, so anything
 * we let through executes for any viewer of the news list.
 *
 * Defense layers (defense-in-depth):
 *  1. Michelf $parser->no_markup = true: drops <script>, <iframe>,
 *     event-handler attributes, etc. that the admin might paste
 *     into the markdown source. Markdown's own emitted HTML
 *     (<p>, <a>, <em>, <strong>, <code>, <ul>, etc.) is preserved.
 *  2. Post-process: rewrite any href= / src= URLs whose scheme is
 *     not http://, https://, mailto:, or a relative path. Catches
 *     `javascript:` and `data:` smuggling that Markdown would
 *     otherwise pass through verbatim if a link target is one.
 */
function _news_render_safe($markdown) {
  return mpos_render_safe_markdown($markdown);
}

// Fetch all news, both raw markdown (for editing) and rendered HTML
// (for the list display). The Vue side uses both: textarea on edit,
// v-html on the list (sanitized via _news_render_safe above).
$aNews = $news->getAll();
$aNewsForSPA = array();
foreach ($aNews as $row) {
  $aNewsForSPA[] = array(
    'id'         => (int)$row['id'],
    'header'     => (string)$row['header'],
    'content'    => (string)$row['content'],
    'contentHtml'=> _news_render_safe($row['content']),
    'active'     => (int)$row['active'],
    'show_on'    => isset($row['show_on']) ? (string)$row['show_on'] : 'home',
    'time'       => isset($row['time']) ? (string)$row['time'] : '',
    'author'     => isset($row['author']) ? (string)$row['author'] : '',
  );
}

// Resolve the v2 bundle from the Vite manifest.
$manifest_path = $_SERVER['DOCUMENT_ROOT'] . '/v2/dist/.vite/manifest.json';
$news_js = '';
$news_css = array();
if (file_exists($manifest_path)) {
  $manifest_raw = @file_get_contents($manifest_path);
  $manifest = $manifest_raw ? json_decode($manifest_raw, true) : null;
  if (is_array($manifest) && isset($manifest['news.html'])) {
    $entry = $manifest['news.html'];
    if (!empty($entry['file'])) $news_js = '/v2/dist/' . $entry['file'];
    if (!empty($entry['css']) && is_array($entry['css'])) {
      foreach ($entry['css'] as $css) $news_css[] = '/v2/dist/' . $css;
    }
  }
}

// JSON-encode initial state for the SPA. Same pattern the other
// migrated pages use.
function _admin_news_json_attr($value) {
  return json_encode(
    $value,
    JSON_HEX_APOS | JSON_HEX_QUOT | JSON_HEX_AMP | JSON_HEX_TAG | JSON_UNESCAPED_UNICODE
  );
}

$initial = array(
  'formAction' => '?page=admin&action=news',
  'csrfToken'  => (string)($smarty->getTemplateVars('CTOKEN') ?? ''),
  'news'       => $aNewsForSPA,
);

$smarty->assign('NEWS_INITIAL_JSON', _admin_news_json_attr($initial));
$smarty->assign('NEWS_JS',  $news_js);
$smarty->assign('NEWS_CSS', $news_css);
$smarty->assign('CONTENT', 'default.tpl');
?>
