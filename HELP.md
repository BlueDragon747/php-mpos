# Operator help

Quick reference for running the Blakestream MPOS deploy on your own host.
The included `deploy-bundle/` stands up the full 6-coin merge-mined stack
with a single SSH-driven script.

## What you get

- 6 Blakecoin-family daemons in Docker (BLC, PHO, BBTC, ELT, UMO, LIT)
- An eloipool stratum server (port 3334) merge-mining all six
- The PHP MPOS dashboard, served by nginx + php-fpm + MariaDB +
  memcached
- A Python `cronjobs-py` scheduler (authoritative replacement for the
  legacy PHP cron)
- A daily backup timer (`blakestream-mpos-backup.timer`) that snapshots
  the DB and per-coin wallets

## Prerequisites

- A target VPS with Ubuntu 22.04+, root SSH, and an SSH alias of your
  choice (this doc uses `<your-pool-host>` as the placeholder).
- A local checkout of `Blakestream-Containers` for the daemon image
  build. Export its path as `CONTAINERS_REPO` (required).
- The deploy auto-clones the 25.2 Go eloipool half from
  `https://github.com/BlueDragon747/eloipool_Blakecoin.git` (branch `25.2-GO`;
  branch page `https://github.com/BlueDragon747/eloipool_Blakecoin/tree/25.2-GO`).
  If you want to deploy from a local checkout instead, export
  `ELIOPOOL_TREE=/path/to/Blakestream-Eliopool-25.2-GO`.
- `ssh-copy-id <your-pool-host>` first so the deploy script has
  passwordless key auth.

## Deploy

```sh
CONTAINERS_REPO=/path/to/Blakestream-Containers \
bash deploy-bundle/deploy-mainnet.sh <your-pool-host>
```

The script is idempotent and runs in stages
(`deploy-bundle/scripts/mainnet/*.sh`); rerunning skips work that has
already completed. Run with `-h` for the full env-var list (domain,
ports, admin creds, RPC creds, bootstrap timeouts, etc.).

After the run finishes, hit `https://<your-pool-host>/` and log in
with the admin credentials the script printed.

## Common operator tasks

- Service control:
  ```sh
  ssh <your-pool-host> 'systemctl status blakestream-mpos-eloipool'
  ssh <your-pool-host> 'systemctl status blakestream-mpos-cronjobs'
  ssh <your-pool-host> 'systemctl status blakestream-mpos-mergeminer'
  ```
- Health check:
  `bash deploy-bundle/scripts/mainnet/99-verify.sh` (run remotely or
  locally over SSH).
- Daily backup status:
  `cat /var/log/blakestream-mpos/backup-status.ini` on the host.
  Toggle the daily run on/off via the admin UI under
  *Settings → System → Daily Backups*.
- Reject-rate / share inspection:
  ```sh
  ssh <your-pool-host> 'mysql mpos -BNe "
    SELECT reason, COUNT(*) FROM shares
     WHERE time > NOW() - INTERVAL 30 MINUTE AND our_result=\"N\"
     GROUP BY reason;"'
  ```

## Admin UI quick reference

- System Status:
  `Admin Panel -> System Status` is the main operator page. It shows
  services, backup state, CPU, memory, swap, disk, network traffic,
  daemon sync/rules, wallet balances, and payout state in one place.
- Coin daemons:
  `SYNC` should read `SYNCED`. `RULES` reads `OK` unless the daemon is
  actively signaling a known softfork rule, for example
  `SIGNALING - SEGWIT`. Hover the rules chip for activation details.
- Wallets:
  `Balance` is spendable wallet RPC balance, `Locked` is DB-tracked
  committed payout balance, and `Unconfirmed` is maturing block reward
  value.
- Disk:
  Directory sizes use the read-only helper
  `/usr/local/sbin/blakestream-mpos-disk-stats`. The deploy installer
  adds a narrowly scoped sudoers entry so `www-data` can run only that
  helper without a password. If disk rows show `restricted` or `-`,
  verify the helper exists, is executable, and the sudoers file was
  installed.
- Payout:
  Use the filter buttons to view `Pending`, `Broadcasted`,
  `Reconciled`, or `Other`. `Other` means abandoned or unknown payout
  states and should normally be zero.

## Payout lifecycle

- `Pending` means a manual or automatic payout is queued but has not
  been sent by the wallet yet.
- `Broadcasted` means the wallet accepted the send and returned a txid.
  The TX column stays blank until the daemon reports at least one
  confirmation, so clicking the link opens correctly in the explorer.
- `Reconciled` means the payout reached the configured reconciliation
  confirmation depth and accounting has closed it out.
- `Indeterminate` means the RPC result was ambiguous. Treat it as a
  stop-and-investigate state: check the wallet with `listtransactions`
  or `gettransaction`, reconcile manually, then clear the slot only
  after you know whether the wallet broadcast the payment.
- `Abandoned` means the daemon rejected the send and user balance was
  left unchanged. Investigate the rejection before retrying.

## Admin transactions

The old per-coin transaction menu entries are consolidated under
`Admin Panel -> Transactions`. Use the coin selector in the transaction
header to switch both the summary and history table between BLC, PHO,
BBTC, ELT, UMO, and LIT.

## Where to read more

- `deploy-bundle/README.md` — what each stage script does, dependency
  expectations, override patterns.
- `deploy-bundle/scripts/mainnet/` — the stage scripts themselves.
  They're short and readable; treat them as the authoritative source
  for "what gets installed where".
- `deploy-bundle/systemd/` — the systemd units installed on the host.
- `cronjobs-py/README.md` — the Python scheduler's job inventory.

## Upstream tracking

The MPOS upstream lineage is tracked at
[`BlueDragon747/php-mpos`](https://github.com/BlueDragon747/php-mpos), while
this 25.2 deploy lane keeps MPOS on the BlueDragon747 `25.2-GO` branch, Eloipool on
`BlueDragon747/eloipool_Blakecoin` branch `25.2-GO`, and wallet source builds
on the six `0.25.2` wallet branches until live cutover. Switch the Eloipool
and wallet source branch defaults to `master` after master carries those
updates. Set `MPOS_REPO_URL`, `ELIOPOOL_REPO_URL`, or `ELIOPOOL_TREE` to
override those defaults.
