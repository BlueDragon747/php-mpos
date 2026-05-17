<?php
/**
 * Shared CSRF / method enforcement for admin handlers.
 *
 * Admin pages historically read mutation intent from `$_REQUEST['do']`,
 * which accepts both GET and POST. Combined with $csrftoken being
 * advisory rather than enforced, this allows a logged-in admin to be
 * CSRFed into any state mutation by visiting a URL.
 *
 * `_require_admin_csrf()` brings two enforcements:
 *
 *   1. METHOD: any request that carries a mutation param (do= or
 *      do_action=) MUST be POST. GET with a mutation is rejected
 *      with HTTP 405. Plain GET with no mutation param is allowed
 *      through (renders the page).
 *   2. TOKEN: POST mutations MUST carry a valid ctoken matching the
 *      session/IP/page binding. Invalid → HTTP 403.
 *
 * Call this once at the top of every admin handler that accepts
 * mutations. It is a no-op for GET-without-mutation requests, so
 * landing-page renders are unaffected.
 */
function _require_admin_csrf($csrftoken) {
    $readOnlyDo = array('query');
    $hasMutation = isset($_REQUEST['do_action']);
    if (isset($_REQUEST['do']) && !in_array((string)$_REQUEST['do'], $readOnlyDo, true)) {
        $hasMutation = true;
    }
    if (!$hasMutation) {
        return; // Read-only landing page render — allow through.
    }

    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        header('HTTP/1.1 405 Method Not Allowed', true, 405);
        header('Allow: POST');
        exit('Method not allowed: admin state changes require POST.');
    }

    // POST mutation must carry a valid ctoken. The token validity is
    // computed in public/index.php against the session IP and page name.
    if (!isset($csrftoken) || !is_object($csrftoken)
        || !isset($csrftoken->valid) || (int)$csrftoken->valid !== 1) {
        header('HTTP/1.1 403 Forbidden', true, 403);
        exit('Invalid or missing CSRF token.');
    }
}
