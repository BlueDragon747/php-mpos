# cronjobs-py

Single-process Python rewrite of MPOS's PHP cronjob suite. Built to be
operationally robust where the PHP version is fragile (block reorgs,
brief RPC outages, out-of-order shares) and to be the long-term
production scheduler for the Blakestream pool stack.

The full design rationale is in
`../MPOS-Postsegwit.md` ("Why we ported PHP cronjobs to Python") and the
Wave 1 / Wave 2 implementation notes.

## Status (post-Wave 2)

The Wave 1 + Wave 2 work has landed all the correctness foundations:

| PHP cronjob                        | Python port                           |
| ---------------------------------- | ------------------------------------- |
| `cronjobs/findblock{,_mm}.php`     | `cronjobs_py.jobs.findblock`          |
| `cronjobs/blockupdate{,_mm}.php`   | `cronjobs_py.jobs.blockupdate`        |
| `cronjobs/pplns_payout{,_mm}.php`  | `cronjobs_py.jobs.pplns_payout`       |
| `cronjobs/payouts{,_mm}.php`       | `cronjobs_py.jobs.payouts`            |
| `cronjobs/liquid_payout.php`       | `cronjobs_py.jobs.liquid_payout`      |
| `cronjobs/statistics.php`          | `cronjobs_py.jobs.statistics`         |
| `cronjobs/archive_cleanup{,_mm}.php` | `cronjobs_py.jobs.archive_cleanup`  |
| `cronjobs/token_cleanup.php`       | `cronjobs_py.jobs.token_cleanup`      |
| `cronjobs/tickerupdate.php`        | `cronjobs_py.jobs.tickerupdate`       |
| `cronjobs/notifications.php`       | `cronjobs_py.jobs.notifications` (stub — see module docstring) |

Wave 3 (deployment hardening) and Wave 4 (replay tests + cutover gate)
are the remaining work. Until Wave 4 ships, **PHP cronjobs are the
authoritative scheduler for coin-moving work** and cronjobs-py runs
only the safe (read-only / non-balance-affecting) subset on the live
testnet. See "Wave 1 cutover state" below.

## Design

### Why one long-lived process

PHP cronjobs fork a fresh process per tick: re-bootstrap the autoloader,
re-parse `global.inc.php`, open a fresh DB and RPC connection, do
~5 seconds of work, exit. At our cadence (60–300 s per job × 6 slots ×
7 job kinds = 42 ticks/min) the per-fork overhead becomes most of the
wall clock. cronjobs-py runs as a single systemd-managed Python process
sharing one `RpcClient` (HTTP keepalive) and one `Db` (PyMySQL
persistent connection) across every tick.

### Three-way failure classification

PHP MPOS treats every failure as `logFatal` → abort → set
`monitoring._disabled = 1`. We classify into three buckets:

- `Transient` — connection refused, timeout, daemon RPC `-28`/`-8`/`-1`.
  Retried with exponential backoff (1s/2s/4s) inside the RPC client;
  what bubbles to the scheduler becomes "skip this tick, retry next".
- `Skip` — this row is unprocessable but the job can keep going.
  Mirrors `findblock.php` E0005 (non-pool block) and E0062 (block has
  no `share_id`).
- `Fatal` — data-integrity violation. Aborts the tick AND, for
  coin-moving jobs (findblock / pplns_payout / payouts / liquid_payout),
  writes a row to `cronjobs_py_disabled` keyed `slot:{slot}` so every
  later coin-moving tick in that slot is skipped until the operator
  clears the row. Non-coin-moving jobs only set `job:{name}`, so the
  dashboard / cleanup / notifications keep running.

### Idempotency anchors

`sendtoaddress` and friends are not idempotent — retrying after a
timeout risks a double-spend. cronjobs-py wraps every wallet send in a
4-step state machine via `transactions_outbox`:

1. INSERT outbox row with status=`pending` and a unique `wallet_comment`
   of the form `mpos:{slot}:{account_id}:{outbox_id}:{nonce_hex8}`.
2. Pass the wallet_comment as the bitcoind `comment` param to
   `sendtoaddress` (wallet-local, never on chain, queryable via
   `listtransactions`).
3. RPC call goes through `RpcClient.call_nonidempotent` which raises
   `Indeterminate` on Timeout / ConnectionError / 5xx / non-JSON, and
   `Fatal` on a clean daemon error response. NEVER retries.
4. On clean broadcast: status → `broadcast`, txid recorded, matching
   `Debit_AP` / `Debit_MP` + `TXFee` rows inserted in the same DB
   transaction. On `Indeterminate`: status → `indeterminate`, slot
   poison flag set, operator must reconcile via wallet listtransactions
   matching wallet_comment before payouts can resume.

### Transactional accounting

Every multi-statement payout (PPLNS credit + Fee + Donation + archive
shares + UPDATE block accounted=1) runs inside a single `db.transaction()`
context manager. The block row is locked via `SELECT ... FOR UPDATE`
at the start of the transaction so two concurrent ticks serialise.

Per-(account, type) inserts into `cronjobs_py_accounting` (UNIQUE on
slot/block_id/account_id/tx_type) precede every transaction-table row;
duplicate inserts caught by the UNIQUE mean "already credited, skip".

### Operator kill switches

Three layers:

| Layer | Mechanism | When to use |
| ----- | --------- | ----------- |
| Per-job | `CRONJOBS_PY_DISABLED_JOBS` env (comma-separated) | Pre-deploy gating, e.g. "run only safe subset" during cutover |
| Settings table | `disable_payouts` / `disable_auto_payouts` | Operator pause from the web UI for maintenance |
| Poison flag | `cronjobs_py_disabled` table (auto-set on Fatal) | Auto-quarantine a slot after a data-integrity violation |

Always check the poison-flag table first (`SELECT * FROM
cronjobs_py_disabled`) when a job has stopped behaving — that's where
the scheduler writes the reason.

### Slot-aware

Six coin slots (parent + `mm`/`mm1`/`mm3`/`mm4`/`mm5`). Each slot has
its own `transactions_<slot>`, `blocks_<slot>`, etc. The scheduler
registers per-slot job instances (`findblock-parent`,
`findblock-mm1`, ...) at startup; intervals are staggered by 3 s per
slot so all six slots don't hit the daemon RPC at the same instant.

## Layout

```
cronjobs-py/
  pyproject.toml
  README.md
  cronjobs_py/
    __init__.py
    __main__.py        # CLI entry: `cronjobs-py {run-once,serve}`
    rpc.py             # RpcClient: keepalive, retry-on-idempotent,
                       # call_nonidempotent for wallet sends
    db.py              # PyMySQL wrapper. Wave 1 added transaction()
                       # context, outbox helpers, accounting guard,
                       # disabled-flag helpers; Wave 2 added
                       # diff-normalised round/archive helpers,
                       # canonical balance SQL, manual queue,
                       # archive-in-cycle helper.
    cache.py           # memcached bridge (PHP-serialised payloads)
    settings.py        # `php -r` bridge to global.inc.php
    scheduler.py       # single-process tick loop, poison-flag check
    logger.py
    errors.py          # Transient / Skip / Fatal / Indeterminate /
                       # Disabled
    jobs/              # one file per job; coin-moving jobs declare
                       # `coin_moving = True`
      findblock.py
      blockupdate.py
      pplns_payout.py
      payouts.py
      liquid_payout.py
      statistics.py
      archive_cleanup.py
      token_cleanup.py
      tickerupdate.py
      notifications.py
```

## Install

The deploy bundle (`../deploy-bundle/`) installs cronjobs-py
end-to-end. To do it by hand:

```bash
cd /opt/blakestream-mpos/cronjobs-py   # or wherever
python3 -m venv .venv
.venv/bin/pip install --upgrade pip
.venv/bin/pip install -e .
```

Requirements: Python 3.10+, `php` on `$PATH` (used to evaluate the MPOS
config), MariaDB credentials per `global.inc.php`. Apply the Wave 1
schema migration before first run:

```bash
mariadb mpos < ../deploy-bundle/sql/01-cronjobs-py-wave1.sql
```

## Usage

```bash
# One tick of every registered job:
cronjobs-py run-once

# One tick of a specific job:
cronjobs-py run-once findblock-parent

# Long-lived scheduler (production mode):
cronjobs-py serve

# Override the MPOS config path:
cronjobs-py --config /etc/mpos/global.inc.php run-once
```

`serve` traps `SIGTERM` and `SIGINT` cleanly.

## Operator runbook

### Wave 1 cutover state — run only the safe subset

Until Wave 4 (replay tests) ships and proves numerical parity with the
PHP scheduler, cronjobs-py installs but does NOT enable the
coin-moving jobs (`findblock`, `pplns_payout`, `payouts`,
`liquid_payout`) by default. The deploy bundle's systemd unit sets:

```
Environment=CRONJOBS_PY_DISABLED_JOBS=findblock-parent,pplns-parent,payouts-parent,liquid-parent,findblock-mm,pplns-mm,payouts-mm,liquid-mm,...
```

The 22 non-coin-moving job slots (statistics × 1, blockupdate × 6,
archive_cleanup × 6, token_cleanup × 1, tickerupdate × 1,
notifications × 1) tick normally — the dashboard stays live.

To enable cronjobs-py end-to-end (after Wave 4 cutover gate is met):

```bash
sudo systemctl edit blakestream-mpos-cronjobs.service
# Remove or empty the Environment=CRONJOBS_PY_DISABLED_JOBS= line.
sudo systemctl restart blakestream-mpos-cronjobs.service
```

Then disable PHP cron:

```bash
# In your crontab (or /etc/cron.d/blakestream-mpos):
# Comment out every line that runs cronjobs/*.php.
```

### Investigating a stuck slot

```bash
# Check the poison-flag table:
mariadb mpos -e "SELECT * FROM cronjobs_py_disabled;"

# Find indeterminate outbox rows (sendtoaddress with unknown outcome):
mariadb mpos -e "SELECT * FROM transactions_outbox WHERE status='indeterminate';"

# For each indeterminate, query the wallet for the matching comment:
blakecoin-cli listtransactions "*" 1000 0 true \
  | jq '.[] | select(.comment | startswith("mpos:")) | {txid, comment, amount, confirmations}'
```

If the wallet shows the transaction broadcast, mark the outbox row
`reconciled` and insert the matching `Debit_AP` / `Debit_MP` + `TXFee`
rows manually. If not, mark it `abandoned`. Then clear the poison flag:

```bash
mariadb mpos -e "DELETE FROM cronjobs_py_disabled WHERE scope = 'slot:';"
```

### Recent log

```bash
sudo journalctl -u blakestream-mpos-cronjobs.service -n 200 --no-pager
sudo tail -f /var/log/blakestream-mpos/cronjobs.stdout
```

## Why not asyncio

The cronjob workload is serial: read a row, fan out a few RPC calls,
write a row, repeat. The parallelism opportunity is bounded (N coins
per tick) and we already get connection reuse via `requests.Session`
and `pymysql`. Threading + `requests` is enough; asyncio would add
complexity without measurable benefit at this scale.

## Future waves

- **Wave 3** (deployment hardening): wipe-script enumeration of all
  units, RPC-wait fail-hard, syntax-aware config rendering, SQL via
  bound parameters everywhere. **DONE.**
- **Wave 4** (replay tests + live gate): pytest fixtures replaying a
  recorded share/block stream against the new code path so we can
  prove numerical parity with PHP's output before flipping the
  coin-moving jobs on. **DONE — 14 tests passing.**
- **Wave 5** (drift gate + soak): shadow mode lets cronjobs-py
  predict alongside an authoritative PHP cron; the drift-check CLI
  compares predictions to PHP's writes. **DONE — 6 additional tests
  passing.**

## Mainnet cutover procedure

Once the soak window has passed (≥1 week of testnet ticking with
PHP cron authoritative + cronjobs-py shadowing) and `drift-check`
reports CLEAN, the cutover steps are:

```bash
# On the deploy target, as the operator with sudo:

# 1. Confirm the soak window is clean.
/opt/blakestream-mpos/cronjobs-py/.venv/bin/cronjobs-py drift-check
# Expect "VERDICT: CLEAN".

# 2. Disable the PHP cron schedule.
sudo rm /etc/cron.d/blakestream-mpos
sudo systemctl reload cron       # or `service cron reload`

# 3. Flip cronjobs-py from shadow to authoritative.
sudo systemctl edit blakestream-mpos-cronjobs.service
# Remove the line:
#     Environment=CRONJOBS_PY_SHADOW_MODE=1
# Save and exit.
sudo systemctl daemon-reload
sudo systemctl restart blakestream-mpos-cronjobs.service

# 4. Verify cronjobs-py is now writing to transactions_<slot>:
sudo tail -f /var/log/blakestream-mpos/cronjobs.stdout
mariadb mpos -e "SELECT mode, COUNT(*) FROM cronjobs_py_accounting \
                 WHERE created_at > DATE_SUB(NOW(), INTERVAL 1 HOUR) \
                 GROUP BY mode;"
# All new rows should be mode='live' (no more 'shadow').

# 5. Watch the dashboard at http://<host>/ for one or two PPLNS
#    cycles. If credits / payouts look correct, cutover is complete.

# Rollback (if anything goes wrong inside an hour or two of cutover):
#   sudo systemctl edit blakestream-mpos-cronjobs.service
#   # Add Environment=CRONJOBS_PY_SHADOW_MODE=1 back.
#   sudo cp deploy-bundle/cron/blakestream-mpos.cron \
#           /etc/cron.d/blakestream-mpos
#   sudo systemctl reload cron
#   sudo systemctl restart blakestream-mpos-cronjobs.service
# This puts the system back to "PHP authoritative, cronjobs-py shadow".
```

The drift-check exit code is 1 if any DIFF row exists. So a CI gate
or oncall script can wrap it:

```bash
# In a periodic check (e.g. /etc/cron.daily/cronjobs-py-drift):
/opt/blakestream-mpos/cronjobs-py/.venv/bin/cronjobs-py drift-check \
    --since "1 week ago" \
    || mail -s "cronjobs-py drift detected" oncall@example.com
```

## Soak window — what to watch for

A clean soak is `MATCH count growing` and `DIFF == 0`. A small
`MISSING` count is normal — when PHP cron credits a block faster
than cronjobs-py shadow predicts it, cronjobs-py never writes a
guard row and the prediction is lost. As long as MATCH ≫ MISSING
the soak is informative.

`PHP_ONLY` rows (use `drift-check --include-php-only`) are
`MISSING`'s mirror image: PHP credited but cronjobs-py never
shadowed. Same root cause; same expected count.

Drift you DO need to investigate:

| Symptom | Likely root cause |
| ------- | ----------------- |
| DIFF on Credit amount | Diff-normalised SUM bug or `getMinimumShareId` cutoff disagreement |
| DIFF on Fee amount | `no_fees` lookup disagreement, or the operator changed `config.fees` mid-window |
| DIFF on Donation | `donate_percent` lookup race (account changed donate_percent mid-window) |
| MISSING for a slot with growing PHP_ONLY | cronjobs-py's findblock isn't keeping up — investigate logs |
| MATCH=0 for a slot | the slot's pplns/findblock/payouts are in `cronjobs_py_disabled` |
