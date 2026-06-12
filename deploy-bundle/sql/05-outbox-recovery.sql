-- Outbox orphan recovery.
--
-- A payout whose sendtoaddress succeeds but whose Debit/TXFee/archive
-- commit then rolls back leaves the outbox row stuck at 'pending' with the
-- coins already gone and the user balance never debited. The reconcile-orphans
-- job heals such rows by matching the wallet_comment / txid back to the wallet.
-- To write the correct Debit (auto vs manual) and close the manual request when
-- healing, the row needs to carry the payout kind and the manual payout id.
--
-- Idempotent: re-running the --mpos updater re-applies every migration.
ALTER TABLE transactions_outbox
  ADD COLUMN IF NOT EXISTS tx_kind VARCHAR(16) NULL AFTER status,
  ADD COLUMN IF NOT EXISTS manual_payout_id BIGINT UNSIGNED NULL AFTER tx_kind;

-- send_attempted gates the safe auto-abandon of an unsent orphan. The row
-- is inserted with its final wallet_comment atomically (no placeholder),
-- and this flag flips to 1 immediately before sendtoaddress is called. A
-- 'pending' row still showing send_attempted=0 therefore provably had no
-- broadcast, so reconcile-orphans can abandon it without a wallet lookup.
ALTER TABLE transactions_outbox
  ADD COLUMN IF NOT EXISTS send_attempted TINYINT(1) NOT NULL DEFAULT 0 AFTER manual_payout_id;

-- The recovery job scans unresolved rows by (slot, status, age); this index
-- keeps that scan cheap as the table grows.
ALTER TABLE transactions_outbox
  ADD INDEX IF NOT EXISTS idx_slot_status_created (slot, status, created_at);
