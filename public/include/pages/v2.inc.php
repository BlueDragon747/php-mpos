<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

if (!$user->isAuthenticated()) {
  header('Location: ?page=login');
  exit;
}

header('Location: ?page=v2&action=dashboard');
exit;
?>
