INSERT INTO `token_types` (`id`, `name`, `expiration`) VALUES
  (1, 'password_reset', 3600),
  (2, 'confirm_email', 0),
  (3, 'invitation', 0),
  (4, 'account_unlock', 0),
  (5, 'account_edit', 3600),
  (6, 'change_pw', 3600),
  (7, 'withdraw_funds', 3600)
ON DUPLICATE KEY UPDATE
  `name` = VALUES(`name`),
  `expiration` = VALUES(`expiration`);
