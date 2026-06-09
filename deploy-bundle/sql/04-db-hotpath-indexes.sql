-- DB hot-path indexes for the Go pool + cronjobs-py runtime.
--
-- Fresh installs get these from sql/database_blank.sql. This idempotent
-- migration keeps existing deployments aligned without rebuilding the DB.
-- Idempotent hot-path indexes. Safe to run on existing deployments.

CREATE TABLE IF NOT EXISTS share_stats_recent (
  bucket_ts datetime NOT NULL,
  username varchar(120) NOT NULL,
  username_base varchar(120) NOT NULL DEFAULT '',
  valid_count bigint(20) unsigned NOT NULL DEFAULT 0,
  invalid_count bigint(20) unsigned NOT NULL DEFAULT 0,
  valid_diff double NOT NULL DEFAULT 0,
  invalid_diff double NOT NULL DEFAULT 0,
  worker_diff_sum double NOT NULL DEFAULT 0,
  last_share_time datetime NOT NULL,
  max_share_id bigint(20) unsigned NOT NULL DEFAULT 0,
  updated_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (bucket_ts, username),
  KEY username_bucket (username, bucket_ts),
  KEY username_last_share_time (username, last_share_time),
  KEY username_base_last_share_time (username_base, last_share_time),
  KEY last_share_time (last_share_time),
  KEY max_share_id (max_share_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

ALTER TABLE share_stats_recent
  ADD COLUMN IF NOT EXISTS username_base varchar(120) NOT NULL DEFAULT '' AFTER username;

UPDATE share_stats_recent
  SET username_base = SUBSTRING_INDEX(username, '.', 1)
  WHERE username_base = '';

CREATE INDEX IF NOT EXISTS username_last_share_time
  ON share_stats_recent (username, last_share_time);
CREATE INDEX IF NOT EXISTS username_base_last_share_time
  ON share_stats_recent (username_base, last_share_time);

-- Existing pools created before the MariaDB username_base optimization need
-- the generated columns too; fresh installs already get them from
-- sql/database_blank.sql.
ALTER TABLE shares
  ADD COLUMN IF NOT EXISTS username_base varchar(120)
    GENERATED ALWAYS AS (substring_index(`username`,'.',1)) STORED
    AFTER username;

ALTER TABLE shares_archive
  ADD COLUMN IF NOT EXISTS username_base varchar(120)
    GENERATED ALWAYS AS (substring_index(`username`,'.',1)) VIRTUAL
    AFTER username;

-- Go-pool stats hot-path controls. Existing operator values are kept.
INSERT IGNORE INTO settings (name, value)
  VALUES ('pool_worker_difficulty_update_seconds', '600');
INSERT IGNORE INTO settings (name, value)
  VALUES ('pool_worker_difficulty_zero_update_seconds', '600');
INSERT IGNORE INTO settings (name, value)
  VALUES ('pool_worker_difficulty_zero_batch_size', '500');
-- Default to 180 days / 1M raw shares so low and mixed-difficulty pools keep
-- useful audit history while still bounding archive growth through hourly
-- batched pruning.
INSERT IGNORE INTO settings (name, value)
  VALUES ('db_prune_enabled', '1');
INSERT IGNORE INTO settings (name, value)
  VALUES ('db_prune_after_days', '180');
INSERT IGNORE INTO settings (name, value)
  VALUES ('db_prune_keep_recent_blocks', '100');
INSERT IGNORE INTO settings (name, value)
  VALUES ('db_prune_keep_recent_shares', '1000000');
UPDATE settings
   SET value = '250000'
 WHERE name = 'db_prune_keep_recent_shares'
   AND CAST(value AS UNSIGNED) < 250000;
INSERT IGNORE INTO settings (name, value)
  VALUES ('db_prune_batch_size', '50000');
INSERT IGNORE INTO settings (name, value)
  VALUES ('db_prune_max_batches', '20');
UPDATE settings
   SET value = '20'
 WHERE name = 'db_prune_max_batches'
   AND CAST(value AS UNSIGNED) = 4;

-- Share stats and block-attribution reads.
CREATE INDEX IF NOT EXISTS result_time_user_diff
  ON shares (our_result, time, username, difficulty);
CREATE INDEX IF NOT EXISTS upstream_time_id
  ON shares (upstream_result, time, id);
CREATE INDEX IF NOT EXISTS idx_time_result
  ON shares (time, our_result);
CREATE INDEX IF NOT EXISTS idx_id_result
  ON shares (id, our_result);
CREATE INDEX IF NOT EXISTS idx_username_base_result_time
  ON shares (username_base, our_result, time);
CREATE INDEX IF NOT EXISTS result_time_user_diff
  ON shares_mm (our_result, time, username, difficulty);
CREATE INDEX IF NOT EXISTS upstream_time_id
  ON shares_mm (upstream_result, time, id);
CREATE INDEX IF NOT EXISTS result_time_user_diff
  ON shares_mm1 (our_result, time, username, difficulty);
CREATE INDEX IF NOT EXISTS upstream_time_id
  ON shares_mm1 (upstream_result, time, id);
CREATE INDEX IF NOT EXISTS result_time_user_diff
  ON shares_mm2 (our_result, time, username, difficulty);
CREATE INDEX IF NOT EXISTS upstream_time_id
  ON shares_mm2 (upstream_result, time, id);
CREATE INDEX IF NOT EXISTS result_time_user_diff
  ON shares_mm3 (our_result, time, username, difficulty);
CREATE INDEX IF NOT EXISTS upstream_time_id
  ON shares_mm3 (upstream_result, time, id);
CREATE INDEX IF NOT EXISTS result_time_user_diff
  ON shares_mm4 (our_result, time, username, difficulty);
CREATE INDEX IF NOT EXISTS upstream_time_id
  ON shares_mm4 (upstream_result, time, id);
CREATE INDEX IF NOT EXISTS result_time_user_diff
  ON shares_mm5 (our_result, time, username, difficulty);
CREATE INDEX IF NOT EXISTS upstream_time_id
  ON shares_mm5 (upstream_result, time, id);
CREATE INDEX IF NOT EXISTS result_time_user_diff
  ON shares_mm6 (our_result, time, username, difficulty);
CREATE INDEX IF NOT EXISTS upstream_time_id
  ON shares_mm6 (upstream_result, time, id);

CREATE INDEX IF NOT EXISTS result_time_user_diff
  ON shares_archive (our_result, time, username, difficulty, share_id);
CREATE INDEX IF NOT EXISTS upstream_time_share
  ON shares_archive (upstream_result, time, share_id);
CREATE INDEX IF NOT EXISTS idx_username_base_result_time
  ON shares_archive (username_base, our_result, time);
CREATE INDEX IF NOT EXISTS idx_share_id_result
  ON shares_archive (share_id, our_result);
CREATE INDEX IF NOT EXISTS result_time_user_diff
  ON shares_archive_mm (our_result, time, username, difficulty, share_id);
CREATE INDEX IF NOT EXISTS upstream_time_share
  ON shares_archive_mm (upstream_result, time, share_id);
CREATE INDEX IF NOT EXISTS result_time_user_diff
  ON shares_archive_mm1 (our_result, time, username, difficulty, share_id);
CREATE INDEX IF NOT EXISTS upstream_time_share
  ON shares_archive_mm1 (upstream_result, time, share_id);
CREATE INDEX IF NOT EXISTS result_time_user_diff
  ON shares_archive_mm2 (our_result, time, username, difficulty, share_id);
CREATE INDEX IF NOT EXISTS upstream_time_share
  ON shares_archive_mm2 (upstream_result, time, share_id);
CREATE INDEX IF NOT EXISTS result_time_user_diff
  ON shares_archive_mm3 (our_result, time, username, difficulty, share_id);
CREATE INDEX IF NOT EXISTS upstream_time_share
  ON shares_archive_mm3 (upstream_result, time, share_id);
CREATE INDEX IF NOT EXISTS result_time_user_diff
  ON shares_archive_mm4 (our_result, time, username, difficulty, share_id);
CREATE INDEX IF NOT EXISTS upstream_time_share
  ON shares_archive_mm4 (upstream_result, time, share_id);
CREATE INDEX IF NOT EXISTS result_time_user_diff
  ON shares_archive_mm5 (our_result, time, username, difficulty, share_id);
CREATE INDEX IF NOT EXISTS upstream_time_share
  ON shares_archive_mm5 (upstream_result, time, share_id);
CREATE INDEX IF NOT EXISTS result_time_user_diff
  ON shares_archive_mm6 (our_result, time, username, difficulty, share_id);
CREATE INDEX IF NOT EXISTS upstream_time_share
  ON shares_archive_mm6 (upstream_result, time, share_id);

-- Block accounting and findblock ordering.
CREATE INDEX IF NOT EXISTS block_accounted_share
  ON blocks (accounted, share_id, id);
CREATE INDEX IF NOT EXISTS block_share_id
  ON blocks (share_id);
CREATE INDEX IF NOT EXISTS block_accounted_share
  ON blocks_mm (accounted, share_id, id);
CREATE INDEX IF NOT EXISTS block_share_id
  ON blocks_mm (share_id);
CREATE INDEX IF NOT EXISTS block_accounted_share
  ON blocks_mm1 (accounted, share_id, id);
CREATE INDEX IF NOT EXISTS block_share_id
  ON blocks_mm1 (share_id);
CREATE INDEX IF NOT EXISTS block_accounted_share
  ON blocks_mm2 (accounted, share_id, id);
CREATE INDEX IF NOT EXISTS block_share_id
  ON blocks_mm2 (share_id);
CREATE INDEX IF NOT EXISTS block_accounted_share
  ON blocks_mm3 (accounted, share_id, id);
CREATE INDEX IF NOT EXISTS block_share_id
  ON blocks_mm3 (share_id);
CREATE INDEX IF NOT EXISTS block_accounted_share
  ON blocks_mm4 (accounted, share_id, id);
CREATE INDEX IF NOT EXISTS block_share_id
  ON blocks_mm4 (share_id);
CREATE INDEX IF NOT EXISTS block_accounted_share
  ON blocks_mm5 (accounted, share_id, id);
CREATE INDEX IF NOT EXISTS block_share_id
  ON blocks_mm5 (share_id);
CREATE INDEX IF NOT EXISTS block_accounted_share
  ON blocks_mm6 (accounted, share_id, id);
CREATE INDEX IF NOT EXISTS block_share_id
  ON blocks_mm6 (share_id);

-- Balance and payout queue scans.
CREATE INDEX IF NOT EXISTS account_archived_id
  ON transactions (account_id, archived, id);
CREATE INDEX IF NOT EXISTS archived_account_id
  ON transactions (archived, account_id, id);
CREATE INDEX IF NOT EXISTS account_archived_id
  ON transactions_mm (account_id, archived, id);
CREATE INDEX IF NOT EXISTS archived_account_id
  ON transactions_mm (archived, account_id, id);
CREATE INDEX IF NOT EXISTS account_archived_id
  ON transactions_mm1 (account_id, archived, id);
CREATE INDEX IF NOT EXISTS archived_account_id
  ON transactions_mm1 (archived, account_id, id);
CREATE INDEX IF NOT EXISTS account_archived_id
  ON transactions_mm2 (account_id, archived, id);
CREATE INDEX IF NOT EXISTS archived_account_id
  ON transactions_mm2 (archived, account_id, id);
CREATE INDEX IF NOT EXISTS account_archived_id
  ON transactions_mm3 (account_id, archived, id);
CREATE INDEX IF NOT EXISTS archived_account_id
  ON transactions_mm3 (archived, account_id, id);
CREATE INDEX IF NOT EXISTS account_archived_id
  ON transactions_mm4 (account_id, archived, id);
CREATE INDEX IF NOT EXISTS archived_account_id
  ON transactions_mm4 (archived, account_id, id);
CREATE INDEX IF NOT EXISTS account_archived_id
  ON transactions_mm5 (account_id, archived, id);
CREATE INDEX IF NOT EXISTS archived_account_id
  ON transactions_mm5 (archived, account_id, id);
CREATE INDEX IF NOT EXISTS account_archived_id
  ON transactions_mm6 (account_id, archived, id);
CREATE INDEX IF NOT EXISTS archived_account_id
  ON transactions_mm6 (archived, account_id, id);

CREATE INDEX IF NOT EXISTS account_completed
  ON payouts_mm (account_id, completed);
CREATE INDEX IF NOT EXISTS account_completed
  ON payouts_mm1 (account_id, completed);
CREATE INDEX IF NOT EXISTS account_completed
  ON payouts_mm2 (account_id, completed);
CREATE INDEX IF NOT EXISTS account_completed
  ON payouts_mm3 (account_id, completed);
CREATE INDEX IF NOT EXISTS account_completed
  ON payouts_mm4 (account_id, completed);
CREATE INDEX IF NOT EXISTS account_completed
  ON payouts_mm5 (account_id, completed);
CREATE INDEX IF NOT EXISTS account_completed
  ON payouts_mm6 (account_id, completed);
