# BlakeStream MPOS Operator Tools

These tools are manual terminal helpers for a running MPOS pool server. Run
them from this `tools/` directory on the VPS where the pool is hosted. They are
not installed as cron jobs, dashboard actions, deploy hooks, or update hooks.

Operator scripts print a BlakeStream banner when they start. Set
`BLAKESTREAM_TOOL_BANNER=0` to suppress it in machine-parsed logs.

## Tools in This Directory

| Script | What it does |
| --- | --- |
| `wallet-maintenance.sh` | **Mainnet** tool. Two operations on the live `""` pool wallet: **Combine** (merge many UTXOs into fewer, in place — defragment) and **Rotate** (combine first, then reset `wallet.dat` to a small file while keeping the same keychain, tracker address, and MPOS payout endpoint — no pool repoint, no service reconfig). Finds each coin's daemon whether it runs in a Docker container or natively, and rotates/combines the selected coins concurrently (each on its own chain) with a live progress table. A bare run opens the live pool menu; also shows wallet UTXO health (`status`). |
| `regnet-wallet-maintenance.sh` | **Regtest twin** of `wallet-maintenance.sh` — a copy with the **identical** menu, boxes, tracker before/after table, live sweep table, and Rotate/Combine/Rescan mechanic; only the network differs. On startup it spins up a throwaway `-regtest` daemon per coin (`rgw-<coin>`, from the `sidgrip/<coin>` image), seeds each with coinbase on a tracker address, runs the same operator flow against them, then tears them all down on exit. Never touches the live pool. Bare run = menu; `regnet-wallet-maintenance.sh rotate\|combine\|rescan --all` non-interactive. |
| `regnet-mine-coins.sh` | Standalone regtest fixture builder: starts disposable regtest daemon containers, creates/reuses their datadirs, and mines spendable test outputs for ad-hoc regtest testing. Never touches live nodes. |
| `pool-watch.sh` | Live pool dashboard mirroring the system-status pages: hashrate, workers, network height/difficulty, share rate/efficiency, **per-coin block finds** (merged mining), proxy chain health, process CPU/RSS, plus a stall verdict (the old "live process, stale work" detector). Interactive = live two-column table; redirected = line log. Read-only. |
| `resource-io-watch.sh` | Live dashboard (interactive) / log (redirected) of CPU, memory, process RSS, disk usage/I/O, pool health, and recent kernel/service errors while miners stay connected. Read-only. |
| `mpos-metrics-snapshot.sh` | Capture a system, disk-I/O, and MariaDB read/write snapshot at a checkpoint for before/after comparison. |

`lib/tool-banner.sh` is a shared helper for the startup banner; it is not run directly.

## Local-Only Watchers

The pool and resource watchers read local services, local MariaDB, and local
JSON-RPC ports.

```bash
cd /path/to/php-mpos/tools
./pool-watch.sh            # live dashboard (INTERVAL_SECONDS=300 nohup ... >> log for a background line-log)
./resource-io-watch.sh
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

## Wallet UTXO Maintenance — Pool Wallet Rotation

`wallet-maintenance.sh` resets the live `""` pool wallet's `wallet.dat` to a
fresh, small file **without changing the keychain**. The pool's operational
wallet is `""` on each daemon: coinbase lands on a fixed eloipool tracker address
that is `ismine` on `""`, and MPOS pays out through `/wallet/` = `""`. So `""`
carries every coinbase and payout forever and its file only grows — Core has no
compact RPC and coin selection is not FIFO, so payouts never drain it in order.

A rotation, per coin:

1. sweeps `""`'s spendable funds to a temp wallet (this also **consolidates**
   them — one output per batch),
2. swaps the wallet file: unloads `""`, moves its `wallet.dat` aside in the host
   data folder, creates a fresh blank `""`, and re-imports the saved descriptors
   with a **scoped rescan** so the fresh `""` re-derives the same addresses (incl.
   the tracker) and recovers the still-immature coinbase, without re-importing the
   spent coinbase history that would re-bloat the file,
3. sweeps the funds back into the fresh `""`.

The tracker address stays `ismine` on `""` and MPOS keeps paying from `/wallet/`
= `""`. **eloipool and MPOS need zero changes** — no tracker repoint, no config
edit. This one operation replaces both a standalone consolidate and a standalone
sweep. The rescan depth is the coin's coinbase maturity + 100 blocks (ELT 560,
others 200). See `sweep.md` for the full design and the manual procedure.

`wallet-maintenance.sh` is the **mainnet** (live pool) tool; the **regtest**
validator is the separate `regnet-wallet-maintenance.sh` (isolated regtest daemons, never the
live pool). It reaches each coin's daemon whether it runs in a **Docker container**
or **natively** on the host (auto-detected per coin), and on testnet/regtest it
locates the `""` wallet under the network subdir (e.g. `testnet3/wallets/`).
(`--main` is still accepted as a harmless no-op for old commands.)

When several coins are selected they rotate (or combine) **concurrently** — each
coin is its own chain with its own mempool, so a slow chain never blocks the rest.
A live per-coin table shows each coin's UTXOs total/left, transactions sent,
current mempool, and state (combining / waiting / done) as the sweep runs.

A bare run scans the wallets once, then opens the picker (a blue-bordered box, the
same look as the coin selector): press a coin's number to toggle it (no Enter;
`0` = all). The Operation row carries: `A` Dry Run (independent toggle, on by
default — preview the plan, move nothing); `B` Rotate / `C` Combine (pick one —
Rotate is the default); and two value setters — `D` Mempool `[N]` (in-flight tx
cap, default 10) and `E` Refill `[M]` (resume sending once the mempool drains to M,
default 5); press the key, then type the number. A one-line description of the
chosen operation shows between the box and the Operation row:

- **Combine** — merge many of `""`'s UTXOs into fewer outputs, in place
  (defragment; the funds and the wallet's history stay put — `wallet.dat` does not
  shrink).
- **Rotate** — *combine first, then rotate*: consolidate the funds into a temp
  wallet, swap `""` for a fresh blank wallet (scoped re-import), then move the
  combined funds back. Resets `wallet.dat` to a small file, same keychain & tracker.
  Mining is paused for the swap by default — one window for the whole batch
  (eloipool drives the parent + merged aux, so it pauses all six); `--no-pause`
  skips it (the scoped rescan covers the window either way).

Press Enter to run the chosen operation on the selected coins, `q` to quit.

```bash
# mainnet (live pool)
sudo ./wallet-maintenance.sh                            # live menu
sudo ./wallet-maintenance.sh status  --all              # wallet UTXO health
sudo ./wallet-maintenance.sh rotate  --coin blc --dry-run    # preview, move nothing
sudo ./wallet-maintenance.sh rotate  --coin blc              # rotate  (after typed YES)
sudo ./wallet-maintenance.sh combine --coin blc --dry-run    # preview the combine
sudo ./wallet-maintenance.sh combine --coin blc              # combine (after typed YES)

# regtest twin (spins up throwaway regtest daemons, then the identical UI/mechanic)
sudo ./regnet-wallet-maintenance.sh                       # menu (same as mainnet, on regtest)
sudo ./regnet-wallet-maintenance.sh rotate  --all         # rotate every coin on regtest
sudo ./regnet-wallet-maintenance.sh combine --coin blc    # combine one coin on regtest
sudo ./regnet-wallet-maintenance.sh rescan  --all         # rescan every coin on regtest
```

Tuning: `--max-mempool N` (default 10) caps in-flight txs and `--mempool-resume N`
(default 5) is the refill threshold (env: `MPOS_UTXO_MAX_MEMPOOL` /
`MPOS_UTXO_MEMPOOL_RESUME`); `--batch-size N` (default 100) sets inputs per tx;
`--rescan-depth N` overrides the depth and `MPOS_ROTATE_RESCAN_MARGIN` (default
100) the margin past maturity; `--no-pause` skips the mining pause; `--temp-wallet
NAME` overrides the temp wallet name; `MPOS_MINING_UNITS` sets the systemd units
paused for the swap. For a coin whose daemon runs natively, `MPOS_NATIVE_CLI_<SYM>`
and `MPOS_NATIVE_DATADIR_<SYM>` override the auto-detected cli path and datadir.
The captured private descriptors (the keychain
re-imported into the fresh `""`) are written root-only under
`/root/blakestream-wallet-key-dumps/`; every live rotation is appended to
`wallet-maintenance.log` there (override with `MPOS_WALLET_UTXO_LOG`). The old
`wallet.dat` is kept under the datadir as `_rotated-<ts>/`, and the temp wallet is
unloaded but its file retained — remove both only once payouts run cleanly.

## Regtest Mining Fixture

`regnet-mine-coins.sh` is a standalone regtest fixture builder. It starts
disposable regtest daemon containers, creates or reuses their datadirs, and mines
spendable test outputs. It never uses live/mainnet mode.
It writes its JSON summary in the current directory and its run log under the
selected work directory.

Regtest containers default to names like `mpos-regtest-blc` so they do not
collide with live pool containers. Override the prefix with
`MPOS_REGTEST_CONTAINER_PREFIX` only when you need a separate fixture namespace.
Images default to `${MPOS_DOCKER_HUB:-sidgrip}/<coin>:${MPOS_IMAGE_TAG:-latest}`.
Per-coin overrides use `MPOS_REGTEST_IMAGE_BLC`, `MPOS_REGTEST_IMAGE_PHO`, and
so on. If no override is set, the miner can detect the image from an existing
non-test live container named by `MPOS_CONTAINER_BLC` or
`MPOS_DAEMON_CONTAINER_BLC`.

Mine all six regtest chains into the latest or a new fixture:

```bash
sudo ./regnet-mine-coins.sh
```

When run directly from a terminal, the script asks how many regtest blocks to
mine per selected coin. Press Enter to use the default. When another tool calls
it, the helper passes a block count and the noninteractive default remains 2000
blocks. Set `MPOS_REGTEST_PROMPT_BLOCKS=0` only when a direct terminal run must
use the default without asking.

Mine only when a fixture has fewer than five spendable outputs:

```bash
sudo ./regnet-mine-coins.sh --ensure-utxos 5
```

Use a specific shared fixture folder:

```bash
sudo MPOS_REGTEST_WORK_DIR=/path/to/shared-fixture ./regnet-mine-coins.sh
```

The wallet maintenance regtest tools also honor `MPOS_REGTEST_WORK_DIR`, so set
that variable when you want them to use one explicit test fixture.
