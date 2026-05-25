-- name: GetReadyJob :one
SELECT id, kind, idempotency_key, status, payload, attempts, max_attempts
FROM go_jobs
WHERE status = 'queued'
  AND run_after <= CURRENT_TIMESTAMP
ORDER BY run_after, id
LIMIT 1;

-- name: InsertAuditEvent :exec
INSERT INTO go_audit_events (actor_id, action, subject, ip_address, metadata)
VALUES (?, ?, ?, ?, ?);
