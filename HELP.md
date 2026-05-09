# Operator help

Quick reference for running this MPOS deploy on your own host. The
upstream BlueDragon `php-mpos` repo ships with no installer; this fork
adds `deploy-bundle/` so you can stand up the full 6-coin merge-mined
stack with a single SSH-driven script.

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
- The deploy auto-clones the eloipool half from
  `https://github.com/SidGrip/eloipool_Blakecoin.git` (branch `15.21`).
  If you want to deploy from a local checkout instead, export
  `ELIOPOOL_TREE=/path/to/Blakestream-Eliopool-15.21`.
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

## Where to read more

- `deploy-bundle/README.md` — what each stage script does, dependency
  expectations, override patterns.
- `deploy-bundle/scripts/mainnet/` — the stage scripts themselves.
  They're short and readable; treat them as the authoritative source
  for "what gets installed where".
- `deploy-bundle/systemd/` — the systemd units installed on the host.
- `cronjobs-py/README.md` — the Python scheduler's job inventory.

## Upstream tracking

This is a fork of [`BlueDragon747/php-mpos`](https://github.com/BlueDragon747/php-mpos)
(itself a fork of [`MPOS/php-mpos`](https://github.com/MPOS/php-mpos)).
The eloipool half is a fork of
[`BlueDragon747/eloipool_Blakecoin`](https://github.com/BlueDragon747/eloipool_Blakecoin),
published as
[`SidGrip/eloipool_Blakecoin`](https://github.com/SidGrip/eloipool_Blakecoin).
