# Database Migrations

`deploy-bundle/scripts/50-install-mpos.sh` and
`deploy-bundle/scripts/mainnet/50-install-mpos.sh` run every `*.sql` file in
this directory in `LC_ALL=C` sorted filename order.

Rules for new migrations:

- Use a zero-padded numeric prefix so order is obvious and stable under
  `LC_ALL=C` sorting, for example `005-add-example-index.sql` or
  `010-add-example-column.sql`.
- Migrations must be safe to run more than once.
- Prefer `CREATE TABLE IF NOT EXISTS`, `ALTER TABLE ... ADD COLUMN IF NOT EXISTS`,
  `CREATE INDEX IF NOT EXISTS`, `INSERT IGNORE`, or `ON DUPLICATE KEY UPDATE`.
- Keep fresh installs aligned by updating `sql/database_blank.sql` when a new
  table, column, index, or default setting belongs in the baseline schema.

The update scripts stop on the first migration error and print the failing file
path so operators can fix the schema change before continuing.
