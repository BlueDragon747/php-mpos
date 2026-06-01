-- cronjobs-py Wave 1: idempotency + poison + accounting guard.
--
-- These tables sit alongside MPOS's existing schema. Nothing in the PHP
-- cronjobs reads or writes them, so applying this migration is safe
-- whether the operator is currently running PHP cron or cronjobs-py.
--
-- Drop order is reverse-create order (FK-safe even though we have no
-- explicit FKs, just for clarity).

-- ---------------------------------------------------------------------
-- 1. transactions_outbox: pre-broadcast outbox state for non-idempotent
--    wallet sends (sendtoaddress, sendmany).
--
-- Row lifecycle:
--   pending     -> the wallet send is about to be issued. wallet_comment
--                  has been set to the value we'll pass to the daemon.
--   broadcast   -> daemon returned a txid. We have on-chain proof.
--   indeterminate -> RPC call timed out / disconnected after submission.
--                  We don't know if the daemon broadcast or not. The
--                  reconciliation job (Wave 2) queries the wallet for
--                  transactions matching wallet_comment to find out.
--   reconciled  -> reconciliation matched the indeterminate row to an
--                  on-chain txid; the matching transactions_<slot> row
--                  has been written.
--   abandoned   -> reconciliation determined the daemon never broadcast
--                  this; safe to retry as a fresh outbox row.
--
-- The wallet_comment column is the idempotency anchor. Format:
--   mpos:{slot}:{account_id}:{outbox_id}:{nonce_hex8}
-- where nonce is 8 random hex chars to defeat collisions if the same
-- outbox_id ever gets reused (it shouldn't, but this is defence in depth).

CREATE TABLE IF NOT EXISTS transactions_outbox (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  slot VARCHAR(8) NOT NULL DEFAULT '',
  account_id INT UNSIGNED NOT NULL,
  coin_address VARCHAR(255) NOT NULL,
  amount DECIMAL(20,8) NOT NULL,
  wallet_comment VARCHAR(64) NOT NULL,
  status ENUM('pending','broadcast','indeterminate','reconciled','abandoned')
    NOT NULL DEFAULT 'pending',
  txid VARCHAR(80) NULL,
  rpc_error TEXT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
    ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_wallet_comment (wallet_comment),
  KEY idx_status (status, created_at),
  KEY idx_slot_account (slot, account_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- 2. cronjobs_py_accounting: guard table for credit/fee/donation/bonus
--    inserts. UNIQUE prevents double-credit on retry after partial
--    failure. Inserted INSIDE the same transaction as the corresponding
--    transactions_<slot> row(s).
--
-- One row per (slot, block_id, account_id, tx_type). Insertion fails
-- with IntegrityError if the same (block, account, type) combo is
-- replayed — that's the signal to the caller that this work has
-- already been done.

CREATE TABLE IF NOT EXISTS cronjobs_py_accounting (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  slot VARCHAR(8) NOT NULL DEFAULT '',
  block_id BIGINT UNSIGNED NOT NULL,
  account_id INT UNSIGNED NOT NULL,
  tx_type VARCHAR(32) NOT NULL,
  mode ENUM('live','shadow') NOT NULL DEFAULT 'live',
  amount DECIMAL(20,8) NOT NULL,
  txn_id BIGINT UNSIGNED NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_block_account_type (slot, block_id, account_id, tx_type),
  KEY idx_block (slot, block_id),
  KEY idx_mode_created (mode, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- 3. cronjobs_py_disabled: poison-flag table. When a coin-moving job
--    raises Fatal, the scheduler writes a row here keyed by scope.
--    Subsequent ticks of any job whose scope matches a row here will
--    skip with a Disabled exception until an operator clears the row.
--
-- scope formats:
--   ""               -> scheduler-wide (every job halted; nuclear)
--   "slot:{slot}"    -> all coin-moving jobs in this slot halted
--   "job:{name}"     -> just this job halted
--
-- The Wave 1 default behaviour: on Fatal in a coin-moving job (pplns,
-- payouts, liquid_payout, findblock), set scope = "slot:{slot}".

CREATE TABLE IF NOT EXISTS cronjobs_py_disabled (
  scope VARCHAR(64) NOT NULL,
  reason TEXT NOT NULL,
  set_by VARCHAR(64) NOT NULL DEFAULT 'cronjobs-py',
  set_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (scope)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
