CREATE TABLE IF NOT EXISTS go_jobs (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  kind VARCHAR(64) NOT NULL,
  idempotency_key VARCHAR(191) NOT NULL,
  status ENUM('queued','leased','succeeded','failed','dead') NOT NULL DEFAULT 'queued',
  payload JSON NULL,
  attempts INT UNSIGNED NOT NULL DEFAULT 0,
  max_attempts INT UNSIGNED NOT NULL DEFAULT 5,
  run_after DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  leased_by VARCHAR(128) NULL,
  leased_until DATETIME NULL,
  last_error TEXT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_go_jobs_idempotency (kind, idempotency_key),
  KEY idx_go_jobs_ready (status, run_after),
  KEY idx_go_jobs_lease (leased_until)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS go_audit_events (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  actor_id BIGINT UNSIGNED NULL,
  action VARCHAR(128) NOT NULL,
  subject VARCHAR(191) NOT NULL,
  ip_address VARCHAR(64) NULL,
  metadata JSON NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_go_audit_actor (actor_id, created_at),
  KEY idx_go_audit_subject (subject, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS go_sessions (
  token_hash VARBINARY(32) NOT NULL,
  account_id BIGINT UNSIGNED NULL,
  data JSON NOT NULL,
  expires_at DATETIME NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (token_hash),
  KEY idx_go_sessions_account (account_id),
  KEY idx_go_sessions_expiry (expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
