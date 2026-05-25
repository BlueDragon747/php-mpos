# Blakestream MPOS Go Backend

Backend-first scaffold for the MPOS 25.2 rewrite. The legacy PHP/Python tree
stays in this fork as the parity reference while Go read models, jobs, and
accounting paths are implemented behind tests.

## Direction

- `cmd/mpos-api`: same-origin JSON API and static frontend host.
- `cmd/mpos-worker`: durable job/accounting worker process.
- `internal/httpapi`: Chi routes using standard `net/http` handlers.
- `internal/db`: MariaDB connection and future sqlc-generated query package.
- `db/migrations`: Go-owned tables separate from legacy MPOS schema.
- `db/queries`: explicit SQL inputs for sqlc.

The first implementation milestone is backend parity, not UI replacement.
No Go write path should become authoritative until replay/parity tests match
legacy PHP/Python behavior for shares, balances, blocks, and payouts.
