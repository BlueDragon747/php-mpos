# Blakestream-MPOS — Config Settings Reference

Every deploy-time knob, what it does, where it lives, and when you'd
change it. All settings are environment variables on the deploy command
line — none of them require hand-editing files.

```bash
export FOO=value
export BAR=value
sudo -E bash deploy-bundle/deploy-mainnet.sh
```

`sudo -E` preserves your exports across the privilege jump. If you're
already root, use `bash deploy-bundle/deploy-mainnet.sh`.

---

## Deploy mode

| Variable | Default | Notes |
|---|---|---|
| (no argument) | — | run locally on this server (`sudo -E bash deploy-bundle/deploy-mainnet.sh`) |
| `<ssh-host>` | — | first arg = SSH host alias or `root@1.2.3.4` for remote install |

---

## Deploy logging

| Variable | Default | Notes |
|---|---|---|
| `MPOS_DEPLOY_LOG` | `./mpos-25.2-go-deploy-<utc>.log` | Full deploy transcript path. Defaults to the repo root. Set to `0`, `off`, or `none` to disable transcript logging. |

---

## Daemon image source

| Variable | Default | Notes |
|---|---|---|
| `MPOS_PULL_DAEMON_IMAGES` | `1` | `1` = pull `sidgrip/<coin>:25.2` from Docker Hub. `0` = clone each coin source repo and build daemon binaries locally; outputs `local/<coin>:25.2-local`. |
| `MPOS_DOCKER_HUB` | `sidgrip` (pull) / `local` (build) | Docker Hub org/user for daemon images. Override when running already-loaded custom images. |
| `MPOS_IMAGE_TAG` | `25.2` (pull) / `25.2-local` (build) | Tag for all daemon images. |
| `SKIP_DAEMON_IMAGE_BUILD` | `0` | With `MPOS_PULL_DAEMON_IMAGES=0`, set `1` to skip source builds (expects images already tagged as `${MPOS_DOCKER_HUB}/<coin>:${MPOS_IMAGE_TAG}`). |
| `MPOS_FORCE_REBUILD` | `0` | With `MPOS_PULL_DAEMON_IMAGES=0`, set `1` to rebuild even when image is already cached. |
| `MPOS_DAEMON_SOURCE_REF` | `0.25.2` | Branch/tag used for source builds across all six coin repos. Change to `master` after live cutover once master carries the 25.2 wallet updates. |
| `MPOS_DAEMON_BUILD_ROOT` | `/root/blakestream-daemon-builds` | Working dir for cloned coin source trees (~15 GB total). |
| `MPOS_DAEMON_BUILD_JOBS` | `nproc - 1` | Parallel build jobs per coin. |
| `MPOS_DAEMON_BUILD_DOCKER_MODE` | `pull` | `pull` uses the pre-built native-base build image; `build` builds it locally. Slower but reproducible. |

**Source repos cloned when building:**
`BlueDragon747/Blakecoin`, `BlueDragon747/photon`, `BlakeBitcoin/BlakeBitcoin`,
`BlueDragon747/Electron-ELT`, `BlueDragon747/universalmol`, `BlueDragon747/lithium`.
These are pinned to `0.25.2` for pre-live 25.2 wallet builds; switch the
source ref to `master` after live cutover.

---

## Web + service ports

| Variable | Default | Notes |
|---|---|---|
| `MPOS_DOMAIN` | `_` | nginx vhost name. `_` is the catch-all. Set to your real FQDN for a single-tenant deploy. |
| `MPOS_HTTP_PORT` | `80` | nginx listen port. |
| `MPOS_STRATUM_PORT` | `3334` | Eloipool stratum bind port. |
| `MPOS_SSH_PORT` | auto-detect | Used for the UFW `allow ssh` rule (so we don't lock you out). |

---

## Database

| Variable | Default | Notes |
|---|---|---|
| `MPOS_DB_HOST` | `127.0.0.1` | MariaDB host (local socket-style on this box). |
| `MPOS_DB_PORT` | `3306` | |
| `MPOS_DB_NAME` | `mpos` | |
| `MPOS_DB_USER` | `mpos` | |
| `MPOS_DB_PASS` | random 32 hex | Override to set a known password. |

---

## Admin account

| Variable | Default | Notes |
|---|---|---|
| `MPOS_ADMIN_USER` | `admin` | First-login admin username. |
| `MPOS_ADMIN_PASS` | random 32 hex | First-login password. Saved in `/root/.mpos-deploy.env`. |
| `MPOS_ADMIN_PIN` | `0000` | First-login payout PIN. Saved in `/root/.mpos-deploy.env` with the other deploy secrets. |
| `MPOS_ADMIN_EMAIL` | `admin@blakestream.local` | Notification address (worker alerts, etc.). |

---

## Pool RPC credentials (shared across all six daemons)

| Variable | Default | Notes |
|---|---|---|
| `MPOS_NODE_RPC_USER` | `blakestream` | Written into every `<coin>.conf` as `rpcuser=`. |
| `MPOS_NODE_RPC_PASS` | random 24 hex | Same, as `rpcpassword=`. Re-uses the value baked into the daemon configs on re-runs. |

---

## Eloipool source

| Variable | Default | Notes |
|---|---|---|
| `ELIOPOOL_REPO_URL` | `https://github.com/BlueDragon747/eloipool_Blakecoin.git` | git URL the deploy clones from when `ELIOPOOL_TREE` is unset. |
| `ELIOPOOL_BRANCH` | `25.2-GO` | branch to clone. Change to `master` after live cutover once master carries the Go Eloipool updates. |
| `ELIOPOOL_TREE` | (unset) | If set, points at a local checkout; the deploy rsyncs from there instead of cloning. |

---

## Bootstrap (chain initial-sync)

| Variable | Default | Notes |
|---|---|---|
| `BOOTSTRAP_URL` | `https://bootstrap.blakestream.io` | Base URL for the 25.2 bootstrap mirror registry and index. The deploy uses `<URL>/25.2/` unless `BOOTSTRAP_URL` already ends in `/25.2`. |
| `BOOTSTRAP_SERIES` | `25.2` | Bootstrap series path used for `.dat.xz` files, sidecars, and `mirrors.json`. |
| `BOOTSTRAP_MIRROR_DISCOVERY` | `1` | `1` queries `mirrors.json`, probes every listed mirror, and downloads from the fastest least-loaded mirror. |
| `BOOTSTRAP_MIRROR_HOST` | (unset) | Optional fixed mirror hostname override, for example `bootstrap-uk.blakestream.io`. |
| `SKIP_BOOTSTRAP` | `0` | `1` skips the sequential bootstrap.dat rotation entirely and syncs via peers. Much slower for first deploys. |
| `BOOTSTRAP_IMPORT_TIMEOUT_S` | `21600` (6h) | Max time waiting for a daemon's bootstrap.dat import to finish. |
| `BOOTSTRAP_IMPORT_SLEEP_S` | `60` | Poll interval while waiting for import. |
| `BOOTSTRAP_POST_IMPORT_CHECK_TIMEOUT_S` | `3600` (1h) | Absolute safety-net timeout for daemon RPC height to reach the downloaded bootstrap height after `-loadblock` reports completion. |
| `BOOTSTRAP_POST_IMPORT_STALL_TIMEOUT_S` | `300` (5m) | Fail post-import verification if daemon height stops increasing for this long. |
| `BOOTSTRAP_DOWNLOAD_ATTEMPTS` | `12` | Per-coin download retries. |
| `BOOTSTRAP_DOWNLOAD_RETRY_SLEEP_S` | `60` | Sleep between download retries. |
| `BOOTSTRAP_DOWNLOAD_CONNECT_TIMEOUT_S` | `30` | wget connect timeout. |
| `BOOTSTRAP_DOWNLOAD_READ_TIMEOUT_S` | `90` | wget read timeout. |
| `TIP_CATCH_TIMEOUT_S` | `7200` (2h) | Max time waiting for a daemon to catch up to the network tip after import. |
| `TIP_CATCH_LAG` | `5` | Tolerable distance (in blocks) from the peer-reported tip. |

---

## Accounting confirmations

MPOS uses two maturity knobs per active coin slot. `confirmations*` controls
when payout/accounting jobs may spend or credit mature rewards.
`network_confirmations*` controls block status refresh windows. Keep both set
to the coin's actual coinbase maturity unless there is a specific operational
reason to widen the block refresh window.

| Coin | Active slot | `confirmations` key | `network_confirmations` key | Value |
|---|---:|---|---|---:|
| Blakecoin | parent | `confirmations` | `network_confirmations` | `120` |
| Photon | `mm` | `confirmations_mm` | `network_confirmations_mm` | `120` |
| BlakeBitcoin | `mm1` | `confirmations_mm1` | `network_confirmations_mm1` | `100` |
| Electron | `mm3` | `confirmations_mm3` | `network_confirmations_mm3` | `460` |
| UniversalMolecule | `mm4` | `confirmations_mm4` | `network_confirmations_mm4` | `120` |
| Lithium | `mm5` | `confirmations_mm5` | `network_confirmations_mm5` | `120` |

`reconcile_min_confirmations` defaults to `6` and is intentionally global:
it is the finality threshold for already-broadcast payout transactions, not
the per-coin coinbase maturity threshold above. Legacy `mm2` and `mm6` values
remain compatibility placeholders and are not active in the 25.2-GO pool.

---

## Swapfile

The deploy starts with an interactive swap screen before package installs,
source builds, or bootstrap work. It shows current RAM, current swap, root disk
free, and the recommended swapfile size. In prompt mode, use the arrow keys to
pick the recommendation, enter a custom size in GB, or leave swap unchanged.

| Variable | Default | Notes |
|---|---|---|
| `MPOS_SWAP_ACTION` | `prompt` | `prompt` shows the arrow-key menu, `auto` applies the recommendation without asking, `skip` leaves swap unchanged. |
| `MPOS_SWAP_SIZE_MB` | auto | Optional explicit swapfile size in MiB for unattended runs. Interactive custom entry is in GB and converted to MiB. |
| `MPOS_SWAP_FILE` | existing file swap, else `/swapfile` | Swapfile path managed by the deploy. By default, the deploy replaces the first existing file-backed swap entry instead of adding a second swapfile. |
| `MPOS_SWAP_PROMPT_TIMEOUT_S` | `120` | Prompt timeout before leaving swap unchanged. |
| `MPOS_SWAP_DISK_RESERVE_MB` | `4096` | Minimum root filesystem free space to leave unused when capping the recommendation. |

---

## Per-coin daemon tuning (written into each `<coin>.conf`)

The deploy renders `<coin>.conf` in `/root/.<coindir>/` for every coin.
These knobs flip between bootstrap and steady-state modes automatically.

| Variable | Default | Notes |
|---|---|---|
| `BOOTSTRAP_DBCACHE_MB` | `4000` | dbcache used during fresh bootstrap import (one daemon running solo, ~15 GB host RAM available). Bigger cache → fewer disk flushes → faster validation. |
| `STEADY_DBCACHE_MB` | `400` | dbcache after a coin reaches tip / for steady-state. Applied to all six configs once the rotation completes; baseline RAM = 6 × ~400 MB. |
| `DBCACHE_MB` | = `STEADY_DBCACHE_MB` | Override only if you want the same value for both phases. |
| `MAXMEMPOOL_MB` | `50` | mempool RAM cap per coin. |
| `PEERS_ON_MAXCONN` | `20` | `maxconnections=` value used once peering is flipped on. |
| `DBCACHE` (config-default) | `400` | Initial value `20-deploy-daemons.sh` writes into each `<coin>.conf`. |
| `daemon` / `server` / `txindex` / `listen` | (computed) | Set by the deploy. `txindex=1` so MPOS can look up transactions by hash; `listen` flips OFF for bootstrap, ON afterwards. |

---

## Stage / step skips (re-run shortcuts)

| Variable | Default | Notes |
|---|---|---|
| `SKIP_DAEMONS` | `0` | `1` skips the daemon stack entirely (assumes containers already running). |
| `SKIP_BOOTSTRAP` | `0` | `1` skips the per-coin solo bootstrap rotation. |
| `START_AFTER` | `1` | `0` skips the final "start all 6 daemons" pass at the end of step 21 (operator launches each daemon manually). |

---

## Sundry

| Variable | Default | Notes |
|---|---|---|
| `MPOS_INSTALL_ROOT` | `/opt/blakestream-mpos` | Where eloipool, venv, scripts, deploy.env live. |
| `MPOS_WEB_ROOT` | `/var/www/blakestream-mpos` | nginx document root for the MPOS UI. |
| `MPOS_LOG_ROOT` | `/var/log/blakestream-mpos` | Pool + cron + backup logs. |
| `MPOS_SALT`, `MPOS_SALTY`, `MPOS_API_TOKEN` | random hex | Per-deploy secrets baked into `global.inc.php`. |
| `MPOS_EXPLORER_API_BASE` | `https://explorer.blakestream.io/api` | Used by 20-deploy-daemons.sh to fetch live addnode peers per coin. |
| `MPOS_DAEMON_STOP_TIMEOUT_S` | `900` (15 min) | systemd `--stop-timeout` for daemon containers; covers slow chainstate flushes on big chains (ELT). |
| `BACKUP_FORCE` | `0` | `1` bypasses the backup script's schedule window + 22 h age debounce. Used internally by step 90 to take the first backup synchronously so step 99 verify finds artifacts on disk. |

---

## Common scenarios — copy-paste blocks

### Default: pull pre-built daemons, run on this server

```bash
export MPOS_DOMAIN=pool.example.com
export MPOS_ADMIN_EMAIL=admin@example.com
sudo -E bash deploy-bundle/deploy-mainnet.sh
```

### Build daemons from source on this server

```bash
export MPOS_DOMAIN=pool.example.com
export MPOS_ADMIN_EMAIL=admin@example.com
export MPOS_PULL_DAEMON_IMAGES=0
sudo -E bash deploy-bundle/deploy-mainnet.sh
```

### Faster bootstrap (more RAM, bigger UTXO buffer)

```bash
export BOOTSTRAP_DBCACHE_MB=6000   # bump from 4000 if the host has 32G+
sudo -E bash deploy-bundle/deploy-mainnet.sh
```

### Skip bootstrap.dat replay; rely on peer sync (much slower first deploy)

```bash
export SKIP_BOOTSTRAP=1
sudo -E bash deploy-bundle/deploy-mainnet.sh
```

### Use already-loaded custom daemon images

```bash
export MPOS_DOCKER_HUB=local
export MPOS_IMAGE_TAG=15.21-test
export MPOS_PULL_DAEMON_IMAGES=0
export SKIP_DAEMON_IMAGE_BUILD=1
sudo -E bash deploy-bundle/deploy-mainnet.sh
```

### Force a rebuild of already-cached images

```bash
export MPOS_PULL_DAEMON_IMAGES=0
export MPOS_FORCE_REBUILD=1
sudo -E bash deploy-bundle/deploy-mainnet.sh
```

### Use your own 25.2 bootstrap mirror

```bash
export BOOTSTRAP_URL=http://192.0.2.10:8080   # /25.2/*.dat.xz + .sha256
export BOOTSTRAP_MIRROR_DISCOVERY=0
sudo -E bash deploy-bundle/deploy-mainnet.sh
```

### Re-run safely (settings on prior `/root/.mpos-deploy.env` get adopted)

Just re-run with no new exports. The deploy script reads back the
previous run's secrets so DB passwords, RPC creds, salts, etc. don't
churn between runs.

```bash
sudo -E bash deploy-bundle/deploy-mainnet.sh
```

---

## Where these are read

- `deploy-bundle/deploy-mainnet.sh` — top-level orchestrator, sources `/root/.mpos-deploy.env` for re-runs.
- `deploy-bundle/scripts/mainnet/10-vps-system-deps.sh` — apt + docker + bun.
- `deploy-bundle/scripts/mainnet/11-configure-swap.sh` — swap status, recommendation, and optional swapfile creation.
- `deploy-bundle/scripts/mainnet/19-build-daemon-images.sh` — source-build daemons (only when `MPOS_PULL_DAEMON_IMAGES=0`).
- `deploy-bundle/scripts/mainnet/20-deploy-daemons.sh` — datadirs + configs + image confirmation. Reads `dbcache` default.
- `deploy-bundle/scripts/mainnet/21-bootstrap-coins.sh` — bootstrap rotation. Reads `BOOTSTRAP_DBCACHE_MB`, `STEADY_DBCACHE_MB`, `MAXMEMPOOL_MB`, `BOOTSTRAP_*`, `TIP_CATCH_*`, `PEERS_ON_MAXCONN`.
- `deploy-bundle/scripts/mainnet/40-install-pool.sh` — eloipool + merged-mine-proxy. Reads `MPOS_NODE_RPC_*`, `MPOS_STRATUM_PORT`.
- `deploy-bundle/scripts/mainnet/50-install-mpos.sh` — MariaDB schema, nginx, MPOS web stack. Reads `MPOS_DB_*`, `MPOS_ADMIN_*`, `MPOS_SALT*`, `MPOS_API_TOKEN`.
- `deploy-bundle/scripts/mainnet/90-install-backup.sh` — backup timer + first-run backup. Uses `BACKUP_FORCE=1` for the first run.

The active env file on the VPS after a successful deploy lives at:
```
/root/.mpos-deploy.env
```
Read it with `sudo sed -n "1,80p" /root/.mpos-deploy.env`.
