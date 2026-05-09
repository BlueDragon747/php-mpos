-- Persisted, slot-aware PPLNS round breakdown for cronjobs-py.
--
-- This matches the table created by deploy-bundle/scripts/50-install-mpos.sh
-- and keeps the MariaDB replay-test schema aligned with deployed pools.

CREATE TABLE IF NOT EXISTS pplns_shares (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  slot VARCHAR(8) NOT NULL DEFAULT '',
  block_id INT UNSIGNED NOT NULL,
  account_id INT UNSIGNED NOT NULL,
  pplns_valid DOUBLE NOT NULL DEFAULT 0,
  pplns_invalid DOUBLE NOT NULL DEFAULT 0,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uk_slot_block_account (slot, block_id, account_id),
  KEY idx_block (block_id),
  KEY idx_account (account_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
