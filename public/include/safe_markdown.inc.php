<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

/**
 * Render Markdown -> HTML for content authored by the pool admin
 * (news entries, dashboard MOTD).
 *
 * Trust model:
 *   The author of news/MOTD is always an authenticated admin
 *   (admin/news.inc.php gates on $user->isAdmin(...) and the
 *   CSRF guard rejects mutations that aren't POST + valid ctoken).
 *   Admins routinely use inline HTML for styling — `<h2 style=...>`,
 *   `<span style="color:..">`, `<strong>` chips, etc. — that
 *   plain Markdown can't express. We pass that HTML through
 *   verbatim because the admin authored it on purpose.
 *
 * What we DO sanitize (defense-in-depth, not against the admin
 * but against URL-scheme smuggling that even an admin might paste
 * accidentally from a third party):
 *
 *   - Rewrite href= / src= URLs whose scheme is not http(s),
 *     mailto, fragment, or root-relative to "#". Catches
 *     `javascript:` and `data:` URLs that would execute on
 *     click in v-html / nofilter contexts.
 *
 * Notably we no longer set `$parser->no_markup = true`. That
 * setting strips/escapes raw HTML from the markdown source, which
 * defeats the admin's intentional styling and renders content as
 * literal `<h2 style=…>` text on the page (the symptom that
 * prompted this re-think). If the trust model ever changes (e.g.
 * we add a non-admin "comment" feature that goes through the
 * same renderer), introduce a separate stricter helper rather
 * than re-tightening this one.
 */
function mpos_render_safe_markdown($markdown) {
  $markdown = (string)$markdown;
  if (class_exists('\\Michelf\\Markdown')) {
    $parser = new \Michelf\Markdown();
    // no_markup is intentionally left at its default (false). See
    // trust-model note above.
    $html = $parser->transform($markdown);
  } else {
    // Fallback if the Michelf library isn't autoloaded for some
    // reason: render plain text safely. This SHOULDN'T happen on
    // the live deploy (autoloader.inc.php require_once's the
    // library), but better an escape than an exception.
    $html = nl2br(htmlspecialchars($markdown, ENT_QUOTES, 'UTF-8'));
  }

  return preg_replace_callback(
    '/(href|src)\s*=\s*"([^"]*)"/i',
    function ($m) {
      $attr = $m[1];
      $url  = trim($m[2]);
      if ($url === ''
          || preg_match('!^https?://!i', $url)
          || preg_match('!^mailto:!i', $url)
          || $url[0] === '#'
          || $url[0] === '/') {
        return $attr . '="' . htmlspecialchars($url, ENT_QUOTES, 'UTF-8') . '"';
      }
      return $attr . '="#"';
    },
    $html
  );
}
?>
