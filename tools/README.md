# BlakeStream MPOS Operator Tools

These tools are manual terminal helpers for a running MPOS pool server. Run
them from this `tools/` directory on the VPS where the pool is hosted. They are
not installed as cron jobs, dashboard actions, deploy hooks, or update hooks.

## Local-Only Watchers

The pool and resource watchers read local services, local MariaDB, and local
JSON-RPC ports. They do not SSH to another server.

```bash
cd /path/to/php-mpos/tools
INTERVAL_SECONDS=300 ./blakestream-pool-stall-watch.sh
INTERVAL_SECONDS=300 ./blakestream-resource-io-watch.sh
```

Optional settings:

```bash
POOL_DB=mpos
BAIKAL=miner-lan-ip
INTERVAL_SECONDS=300
```

`BAIKAL` is optional miner-side context. Leave it unset when the pool VPS cannot
reach the miner API.

## Metrics Snapshot

Use this before and after deploy, update, mining, prune, or stress-test work.

```bash
./mpos-metrics-snapshot.sh ./mpos-metrics-before.log
./mpos-metrics-snapshot.sh ./mpos-metrics-after.log
```

Optional settings:

```bash
DB_NAME=mpos
MYSQL_CMD=mysql
```

## Wallet UTXO Maintenance

`blakestream-wallet-utxo-maintenance.sh` is for manual pool-wallet inspection,
rotation preparation, and consolidation on the mainnet Docker daemon stack.

It must be run by the operator from a terminal. It does not edit MPOS config,
does not change pool payout addresses, and does not broadcast consolidation
transactions unless `--send` is supplied and the operator confirms the exact
prompt.

Status check:

```bash
sudo ./blakestream-wallet-utxo-maintenance.sh status --all
```

Prepare a new payout address and dump key material:

```bash
sudo ./blakestream-wallet-utxo-maintenance.sh rotate --coin blc --old-address CURRENT_POOL_ADDRESS
```

Dry-run consolidation:

```bash
sudo ./blakestream-wallet-utxo-maintenance.sh consolidate --coin blc --batch-size 100
```

Broadcast consolidation:

```bash
sudo ./blakestream-wallet-utxo-maintenance.sh consolidate --coin blc --batch-size 100 --send
```

Any operation that creates a replacement address or moves funds writes a
root-only wallet backup, wallet dump, and relevant private keys under:

```text
/root/blakestream-wallet-key-dumps/
```

Override that location with `MPOS_WALLET_KEY_DUMP_DIR` if the pool operator
stores key material somewhere else.

Store those files offline before changing pool payout addresses or retiring an
old wallet.
