-- Index txid on the transaction ledgers + the payout outbox.
--
-- reconcile_payouts (UPDATE ... SET archived=1 WHERE txid=...), reconcile-
-- orphans (SELECT COUNT(*) ... WHERE txid=...) and compute_balance's
-- `LEFT JOIN transactions_outbox o ON t.txid = o.txid` all key off txid, which
-- was unindexed — a full scan that grows with the ledger. These prefix indexes
-- (txids are <=64 ASCII hex chars, so 72 covers them with margin) turn those
-- into index lookups. The columns differ in charset (transactions.txid utf8mb3
-- vs transactions_outbox.txid utf8mb4), but txids are ASCII hex so the
-- comparison is charset-neutral and each side's own index is usable.
--
-- Online + fail-loud (never a silent write-blocking COPY). Idempotent.
CREATE INDEX IF NOT EXISTS idx_txid ON transactions (txid(72)) ALGORITHM=INPLACE LOCK=NONE;
CREATE INDEX IF NOT EXISTS idx_txid ON transactions_mm (txid(72)) ALGORITHM=INPLACE LOCK=NONE;
CREATE INDEX IF NOT EXISTS idx_txid ON transactions_mm1 (txid(72)) ALGORITHM=INPLACE LOCK=NONE;
CREATE INDEX IF NOT EXISTS idx_txid ON transactions_mm2 (txid(72)) ALGORITHM=INPLACE LOCK=NONE;
CREATE INDEX IF NOT EXISTS idx_txid ON transactions_mm3 (txid(72)) ALGORITHM=INPLACE LOCK=NONE;
CREATE INDEX IF NOT EXISTS idx_txid ON transactions_mm4 (txid(72)) ALGORITHM=INPLACE LOCK=NONE;
CREATE INDEX IF NOT EXISTS idx_txid ON transactions_mm5 (txid(72)) ALGORITHM=INPLACE LOCK=NONE;
CREATE INDEX IF NOT EXISTS idx_txid ON transactions_mm6 (txid(72)) ALGORITHM=INPLACE LOCK=NONE;
CREATE INDEX IF NOT EXISTS idx_txid ON transactions_outbox (txid(72)) ALGORITHM=INPLACE LOCK=NONE;
