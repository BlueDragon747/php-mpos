# BlakeStream MPOS Operator Tools

These tools are manual terminal helpers for a running MPOS pool server. Run
them from this `tools/` directory on the VPS where the pool is hosted. They are
not installed as cron jobs, dashboard actions, deploy hooks, or update hooks.

Operator scripts print a BlakeStream banner when they start. Set
`BLAKESTREAM_TOOL_BANNER=0` to suppress it in machine-parsed logs.

## Local-Only Watchers

The pool and resource watchers read local services, local MariaDB, and local
JSON-RPC ports.

```bash
cd /path/to/php-mpos/tools
INTERVAL_SECONDS=300 ./pool-stall-watch.sh
INTERVAL_SECONDS=300 ./resource-io-watch.sh
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

`wallet-utxo-maintenance.sh` is for manual pool-wallet inspection,
rotation preparation, and consolidation.

The default mode is a regtest smoke test against rollback-smoke containers. It
must be run by the operator from a terminal. Live pool wallet work requires the
explicit `--main` flag. The tool refuses to run `--main` against containers
labeled as rollback-smoke test containers.

The regtest smoke path uses the shared fixture created by
`mine-regtest-coins.sh`. If the fixture is missing or has too few spendable
outputs, the wallet tool auto-starts the regtest containers and mines more
blocks before it tests consolidation.

When no `--coin` or `--all` option is supplied in a terminal, the tool shows a
numbered wallet-health selector. Type a number to toggle one coin, `0` to
toggle all, then press Enter on a blank line to continue. Selected coins show
`[*]`.

It does not edit MPOS config, does not change pool payout addresses, and does
not broadcast live consolidation transactions unless `--main --send` is
supplied and the operator confirms the exact prompt.

Live container names default to the coin symbols `blc`, `pho`, `bbtc`, `elt`,
`lit`, and `umo`. If an operator uses different Docker container names, set
per-coin variables before running live tools, for example:

```bash
export MPOS_CONTAINER_BLC=pool-blakecoin
export MPOS_CONTAINER_PHO=pool-photon
```

Regtest consolidation smoke test:

```bash
sudo ./wallet-utxo-maintenance.sh
```

Status check:

```bash
sudo ./wallet-utxo-maintenance.sh --main status --all
```

Prepare a new payout address and dump key material:

```bash
sudo ./wallet-utxo-maintenance.sh --main rotate --coin blc --old-address CURRENT_POOL_ADDRESS
```

Dry-run consolidation:

```bash
sudo ./wallet-utxo-maintenance.sh --main consolidate --coin blc --batch-size 100
```

Broadcast consolidation:

```bash
sudo ./wallet-utxo-maintenance.sh --main consolidate --coin blc --batch-size 100 --send
```

Any operation that creates a replacement address or moves funds writes a
root-only wallet backup and private key material under:

```text
/root/blakestream-wallet-key-dumps/
```

Legacy wallets use wallet dumps and address private-key files. Descriptor
wallets use `listdescriptors true` private descriptor exports plus address-info
files because `dumpwallet` and `dumpprivkey` are legacy-only RPCs.

Override that location with `MPOS_WALLET_KEY_DUMP_DIR` if the pool operator
stores key material somewhere else.

Store those files offline before changing pool payout addresses or retiring an
old wallet.

## Chain Rollback

`chain-rollback.sh` is a manual terminal tool for rollback smoke testing and
coordinated chain-tip rollback across pool nodes. By default it runs a
disposable regtest smoke test. Live-node rollback requires the explicit
`--main` flag.

The script clears the terminal and shows a numbered chain selector. Type a
number to toggle one chain, `0` to toggle all, then press Enter on a blank line
to continue. Selected chains show `[*]`. Mainnet plan mode shows each selected
chain's current height and asks for the rollback target height. Regtest smoke
mode does the same for the first/full rollback when run from an interactive
terminal; noninteractive smoke tests use the configured default target heights.

Run the regtest smoke test from the directory where you want result files
written:

```bash
cd /mnt/ram-build
sudo /path/to/php-mpos/tools/chain-rollback.sh
```

The smoke test starts disposable regtest daemon containers, mines test blocks,
runs a full rollback for the selected chains, then runs a partial rollback to
confirm other selected chains are not changed. Noninteractive runs default to
all six chains. It writes `chain-rollback-regtest-*.json` plans in the current
directory and writes run, verify, and apply logs under the matching
`chainrollback-regtest-*/logs/` directory. It also copies the JSON plans into
the matching work directory so the folder can be moved as a complete test
record. It uses the same regtest fixture and wallets as the UTXO maintenance
smoke test. It refuses to remove existing daemon containers unless they were
created by the smoke test.

By default the smoke containers remain available after a passing run so the
wallet UTXO tool can reuse the same datadirs and wallets. Set
`KEEP_ROLLBACK_TEST_CONTAINERS=0` to remove the smoke containers after success.

## Regtest Mining Fixture

`mine-regtest-coins.sh` is the shared regtest fixture builder used by the
rollback and wallet UTXO tools. It starts rollback-smoke daemon containers,
creates or reuses their datadirs, and mines spendable test outputs. It never
uses live/mainnet mode.
It writes its JSON summary in the current directory and its run log under the
selected `chainrollback-regtest-*/logs/` directory.

Regtest containers default to names like `mpos-regtest-blc` so they do not
collide with live pool containers. Override the prefix with
`MPOS_REGTEST_CONTAINER_PREFIX` only when you need a separate fixture namespace.
Images default to `${MPOS_DOCKER_HUB:-sidgrip}/<coin>:${MPOS_IMAGE_TAG:-25.2}`.
Per-coin overrides use `MPOS_REGTEST_IMAGE_BLC`, `MPOS_REGTEST_IMAGE_PHO`, and
so on. If no override is set, the miner can detect the image from an existing
non-test live container named by `MPOS_CONTAINER_BLC` or
`MPOS_DAEMON_CONTAINER_BLC`.

Mine all six regtest chains into the latest or a new fixture:

```bash
sudo ./mine-regtest-coins.sh
```

When run directly from a terminal, the script asks how many regtest blocks to
mine per selected coin. Press Enter to use the default. When another tool calls
it, the helper passes a block count and the noninteractive default remains 2000
blocks. Set `MPOS_REGTEST_PROMPT_BLOCKS=0` only when a direct terminal run must
use the default without asking.

Mine only when a fixture has fewer than five spendable outputs:

```bash
sudo ./mine-regtest-coins.sh --ensure-utxos 5
```

Use a specific shared fixture folder:

```bash
sudo MPOS_REGTEST_WORK_DIR=/mnt/ram-build/mpos-rollback-test/tools/chainrollback-regtest-shared ./mine-regtest-coins.sh
```

The rollback and wallet tools also honor `MPOS_REGTEST_WORK_DIR`, so set that
variable when you want both tools to use one explicit test fixture.

Create one live rollback plan on a synced node:

```bash
sudo ./chain-rollback.sh --main plan
```

The script asks which chains to include and the target height for each selected
chain, then writes a JSON plan containing the exact target heights and block
hashes. This plan is the source of truth for the rollback.

Copy that JSON plan to every node that should roll back, then apply the same
plan locally on each node:

```bash
sudo ./chain-rollback.sh --main apply --plan chain-rollback-plan.json
```

Check a node against a plan without applying it:

```bash
sudo ./chain-rollback.sh --main status --plan chain-rollback-plan.json
```

Using the same JSON plan on every node keeps all selected chains at the same
rollback heights. The apply step verifies that each node has the same planned
invalidate hash before it rolls back.

The live rollback path does not edit block database files. It uses daemon RPC
`invalidateblock` against the planned `target + 1` block. Plans and apply
manifests are written to `tools/logs/` by default unless the operator explicitly
sets `MPOS_LOG_ROOT`. When the tool is run with `sudo` by a normal user, the
default log directory, generated plan JSON files, and apply manifests are
chowned back to that invoking user and kept private. Files use mode `600`, so
they are readable through SFTP/WinSCP as the operator account without making
rollback details world-readable.
