-- cronjobs-py Wave 5: drift-gate / shadow-mode column.
--
-- Adds a `mode` column to `cronjobs_py_accounting` so cronjobs-py can
-- run in shadow mode alongside the authoritative PHP cron during the
-- mainnet-cutover soak window.
--
-- Lifecycle:
--   mode = 'shadow' — cronjobs-py predicted the credit/fee/donation/
--                     bonus row (and the prediction is in the
--                     `amount` column) but did NOT write the matching
--                     transactions_<slot> row. PHP cron is the
--                     authoritative writer during the soak window.
--                     `txn_id` stays NULL.
--   mode = 'live'   — cronjobs-py both predicted AND wrote. `txn_id`
--                     points to the resulting transactions_<slot> row.
--                     This is the post-cutover steady state.
--
-- The drift-gate compares (slot, block_id, account_id, tx_type, amount)
-- across `cronjobs_py_accounting WHERE mode='shadow'` and the
-- corresponding `transactions_<slot>` rows authored by PHP cron. Zero
-- divergence over N blocks means cronjobs-py is safe to flip
-- authoritative.

ALTER TABLE cronjobs_py_accounting
    ADD COLUMN IF NOT EXISTS mode ENUM('live','shadow') NOT NULL DEFAULT 'live'
    AFTER tx_type;

-- Index on (mode, created_at) so the drift-check CLI can scan
-- shadow rows efficiently without a full table scan.
CREATE INDEX IF NOT EXISTS idx_mode_created ON cronjobs_py_accounting (mode, created_at);
