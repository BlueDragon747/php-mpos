# Blakestream-MPOS deploy-bundle

Layered on top of the canonical `eloipool_Blakecoin` mainnet stack,
this bundle brings up the full pool with the MPOS web UI and
`cronjobs-py` scheduler in front.

What it installs:

- six BlakeStream daemons (parent + 5 aux) extracted from
  `sidgrip/<coin>:25.2` Docker images, with `libboost1.74` runtime
  staged into `ldconfig` so the jammy-built binaries run on 24.04 hosts
- `eloipool` stratum, `merged-mine-proxy.py3`, and the MPOS
  authentication backend wired into the `pool_worker` table
- MariaDB schema (`sql/database_blank.sql`) + a seeded admin account
- nginx + php-fpm vhost serving the MPOS web tree at
  `${MPOS_WEB_ROOT}` (default `/var/www/blakestream-mpos`)
- `cronjobs-py` scheduler running as a systemd service
- daily DB + wallet backup helper and systemd timer, controlled by the
  MPOS `settings.backups_enabled` admin setting
- logrotate policy for MPOS, Go Eloipool, MMP, share importer, nginx,
  backup, and cron logs
- optional resource-based `/swapfile` setup before source builds and
  bootstrap replay
- a root-owned, no-argument disk stats helper with a sudoers rule limited
  to `www-data` running `/usr/local/sbin/blakestream-mpos-disk-stats`

## Layout

```
deploy-bundle/
├── deploy-testnet.sh         # testnet entry — orchestrates testnet steps
├── deploy-mainnet.sh         # mainnet entry — orchestrates mainnet steps
├── scripts/
│   ├── 05-wipe.sh            # purge prior MPOS install (--wipe)
│   ├── 10-system-deps.sh     # apt: nginx, php-fpm, mariadb, memcached, python, docker
│   ├── system-disk-stats.sh  # read-only allowlisted disk stats helper
│   ├── 20-pull-daemons.sh    # docker pull + binary extract + libboost ldconfig
│   ├── 30-init-daemons.sh    # write configs, systemd units, start 12 daemons
│   ├── 40-install-pool.sh    # eloipool + MPOS auth + MMP, render config
│   ├── 50-install-mpos.sh    # MariaDB DB, web tree, render global.inc.php, nginx vhost
│   ├── 60-install-cronjobs-py.sh
│   ├── mainnet/
│   │   ├── 11-configure-swap.sh  # show current swap and apply operator choice
│   │   ├── 19-build-daemon-images.sh  # optional source-build runtime images
│   │   ├── 21-bootstrap-coins.sh  # rolling bootstrap download/import scheduler
│   │   └── ...
│   └── 99-verify.sh
├── sudoers/
│   └── blakestream-mpos-disk-stats
├── templates/
│   └── eloipool-testnet.config.py.template
└── README.md
```

## Bootstrapping Daemons (Mainnet)

`scripts/mainnet/21-bootstrap-coins.sh` now runs in two phases:

- Phase A downloads and verifies every selected 25.2 bootstrap in a rolling
  pool. `DOWNLOAD_CONCURRENCY` defaults to `3`, so completed downloads free a
  slot for the next coin without waiting for a fixed batch.
- Phase B imports and catches up bootstraps in a rolling daemon pool.
  `SYNC_CONCURRENCY` defaults to `2`; the scheduler starts the next eligible
  coin as soon as a running coin finishes.

ELT and UMO are the heavy import pair. The scheduler will not run them at the
same time, but either one may run beside a smaller chain when host resources
allow it. On smaller VPSes, set `SYNC_CONCURRENCY=1` to force a fully serial
import.

For each coin, the script stages `/root/.<coin>/bootstrap.dat`, starts the
daemon with `-loadblock=<datadir>/bootstrap.dat`, waits for the external-file
import to finish, verifies the daemon height reached the bootstrap filename
height, then moves the file to `bootstrap.dat.old` so reruns do not import it
again. It then flips peering on and requires local height to be within
`TIP_CATCH_LAG` blocks of the peer tip. A peer tip a few blocks below local
height is allowed, but a stale peer tip far below local height is rejected. A
timed-out catch-up fails the deploy instead of silently continuing. After the
rolling import pool finishes, it brings all six daemons online one at a time.

```bash
# Default: rolling downloads, then rolling import/sync with ELT/UMO mutex
sudo bash deploy-bundle/scripts/mainnet/21-bootstrap-coins.sh

# Subset (e.g. just ELT and UMO if the smaller chains are already synced):
sudo bash deploy-bundle/scripts/mainnet/21-bootstrap-coins.sh elt umo

# Fully serial import/sync for smaller hosts:
SYNC_CONCURRENCY=1 sudo bash deploy-bundle/scripts/mainnet/21-bootstrap-coins.sh

# Skip the final start-all phase (operator wants to launch each daemon manually):
START_AFTER=0 sudo bash deploy-bundle/scripts/mainnet/21-bootstrap-coins.sh
```

The script also restores steady-state cache settings after import:
`STEADY_DBCACHE_MB` defaults to `400` and `MAXMEMPOOL_MB` defaults to `50`.
That keeps post-bootstrap RAM within budget when all six daemons run
concurrently.

## Swapfile prompt

`deploy-mainnet.sh` runs `scripts/mainnet/11-configure-swap.sh` at the
start of the deploy, before package installs, source builds, bootstrap
downloads, or imports. The step clears the screen, prints current RAM,
active swap, root disk free, and a resource-based recommendation. By
default it opens an arrow-key menu so the operator can pick the
recommended size, enter a custom size in GB, or leave swap unchanged, then
leave the deploy running. If a file-backed swap entry already exists, the
deploy resizes/replaces that file instead of adding a second swapfile. The
same step writes `/etc/sysctl.d/99-swappiness.conf` with
`vm.swappiness=10` and applies it with `sysctl --system`, even when swap is
left unchanged.

Useful overrides:

```bash
# Apply the recommended size without prompting
MPOS_SWAP_ACTION=auto sudo -E bash deploy-bundle/deploy-mainnet.sh

# Force 12 GiB, useful on small Ubuntu 24.04 builders
MPOS_SWAP_ACTION=auto MPOS_SWAP_SIZE_MB=12288 sudo -E bash deploy-bundle/deploy-mainnet.sh

# Leave host swap untouched
MPOS_SWAP_ACTION=skip sudo -E bash deploy-bundle/deploy-mainnet.sh
```

## Log rotation

`deploy-mainnet.sh` installs `deploy-bundle/logrotate/blakestream-mpos`
as `/etc/logrotate.d/blakestream-mpos`. The policy rotates and compresses
the direct pool logs so `shares.log`, `mmp.log`, `eloipool-go.log`,
systemd stdout/stderr captures, nginx logs, backup logs, and cron logs do
not grow unbounded. Pool-facing logs keep 7 daily rotations and rotate
early at 100 MB. PHP cron per-job logs keep 4 weekly rotations with a
30-day max age.

Validate the active policy with:

```bash
sudo logrotate --debug /etc/logrotate.d/blakestream-mpos
systemctl status logrotate.timer
```

## Mainnet Usage

Every scenario starts by cloning this repo, on either the pool server
(local install) or your workstation (SSH install):

```bash
git clone -b 25.2-GO https://github.com/BlueDragon747/php-mpos.git php-mpos
cd php-mpos
```

`sudo -E` preserves the `export`ed env vars across the privilege jump.
If you are already root, replace `sudo -E bash …` with `bash …`.

Each run writes a full deploy transcript in the repo root by default:

```text
mpos-25.2-go-deploy-<utc>.log
```

Override it with `MPOS_DEPLOY_LOG=/path/to/deploy.log`, or set
`MPOS_DEPLOY_LOG=0` to disable transcript logging.

The deploy creates the first admin account from `MPOS_ADMIN_USER`,
`MPOS_ADMIN_PASS`, `MPOS_ADMIN_EMAIL`, and `MPOS_ADMIN_PIN`. If
`MPOS_ADMIN_PIN` is not set, the default payout PIN is `0000`. The selected
PIN is saved with the other deploy secrets.

### Deploy on the VPS — pull pre-built daemon containers (recommended)

Pulls `sidgrip/<coin>:25.2` from Docker Hub. Fastest clean install.
Run on the pool server:

```bash
export MPOS_DOMAIN=pool.example.com
export MPOS_ADMIN_EMAIL=admin@example.com

sudo -E bash deploy-bundle/deploy-mainnet.sh
```

### Deploy on the VPS — build daemon containers from source

Clones each coin's GitHub repo, builds daemon binaries in Docker, and
tags the result as `local/<coin>:25.2-local`. Bootstrap downloads run
in parallel with the build phase to save wall time. Needs ~15 GB free
under `/root/blakestream-daemon-builds`.

```bash
export MPOS_DOMAIN=pool.example.com
export MPOS_ADMIN_EMAIL=admin@example.com
export MPOS_PULL_DAEMON_IMAGES=0

sudo -E bash deploy-bundle/deploy-mainnet.sh
```

Source repos used: `BlueDragon747/Blakecoin`, `BlueDragon747/photon`,
`BlakeBitcoin/BlakeBitcoin`, `BlueDragon747/Electron-ELT`,
`BlueDragon747/universalmol`, `BlueDragon747/lithium` — all at branch
`0.25.2` unless overridden via `MPOS_DAEMON_SOURCE_REF`. Change the source
ref to `master` after live cutover once master carries the 25.2 wallet updates.

### Deploy over SSH from a workstation — pull pre-built containers

Run from your dev box with passwordless key auth already configured to
the pool server (`ssh-copy-id` first):

```bash
export MPOS_DOMAIN=pool.example.com
export MPOS_ADMIN_EMAIL=admin@example.com

bash deploy-bundle/deploy-mainnet.sh root@your-vps
```

### Deploy over SSH from a workstation — build containers on the server

```bash
export MPOS_DOMAIN=pool.example.com
export MPOS_ADMIN_EMAIL=admin@example.com
export MPOS_PULL_DAEMON_IMAGES=0

bash deploy-bundle/deploy-mainnet.sh root@your-vps
```

### Use daemon images you loaded yourself

If `${MPOS_DOCKER_HUB}/<coin>:${MPOS_IMAGE_TAG}` already exists on the
target server (for example after `docker load < my-images.tar`), skip
both the pull and the source-build:

```bash
export MPOS_DOCKER_HUB=local
export MPOS_IMAGE_TAG=25.2-test
export MPOS_PULL_DAEMON_IMAGES=0
export SKIP_DAEMON_IMAGE_BUILD=1

sudo -E bash deploy-bundle/deploy-mainnet.sh
```

### Bootstrap options

By default the deploy queries
`https://bootstrap.blakestream.io/25.2/mirrors.json`, probes every listed
mirror, downloads the current `*.dat.xz` and `.sha256` sidecar from the
fastest least-loaded mirror, verifies the sidecar, then decompresses to
`bootstrap.dat` before replay. Add one of these `export`s to any scenario
above:

```bash
# Pin a public mirror instead of auto-picking from mirrors.json:
export BOOTSTRAP_MIRROR_HOST=bootstrap-uk.blakestream.io

# Use your own HTTP bootstrap mirror (must serve /25.2/*.dat.xz + .sha256):
export BOOTSTRAP_URL=http://127.0.0.1:8080
export BOOTSTRAP_MIRROR_DISCOVERY=0

# Skip bootstrap replay entirely — sync the long way via peers:
export SKIP_BOOTSTRAP=1
```

If `bootstrap.dat` is already staged in `/root/.<coin>/` from a prior
run, the deploy detects it and skips re-download.

Eliopool is pulled from
`https://github.com/BlueDragon747/eloipool_Blakecoin.git` branch `25.2-GO`
(`https://github.com/BlueDragon747/eloipool_Blakecoin/tree/25.2-GO`) when
`ELIOPOOL_TREE` is unset. To deploy from a local Eliopool checkout
instead:

```bash
git clone -b 25.2-GO https://github.com/BlueDragon747/eloipool_Blakecoin.git Blakestream-Eliopool-25.2-GO
export ELIOPOOL_TREE="$(cd Blakestream-Eliopool-25.2-GO && pwd)"
```

## Testnet Usage

Testnet uses the same MPOS web stack, share importer, scheduler, payout
pipeline, and verification path as mainnet. The network-specific differences
are the testnet daemon mode/config, testnet ports, testnet addresses, and
testnet chain data. `cronjobs-py` starts by default; set
`MPOS_PYTHON_CRONJOBS_ACTIVE=0` only when intentionally staging it disabled
for ad-hoc tests.

```bash
# All-in-one install on the local host:
sudo bash deploy-bundle/deploy-testnet.sh -local

# Wipe a prior install before deploying:
sudo bash deploy-bundle/deploy-testnet.sh -local --wipe

# Skip the daemon + pool layer if already deployed:
sudo bash deploy-bundle/deploy-testnet.sh -local --skip-pool
```

`deploy-testnet.sh` writes its rendered env to
`${MPOS_INSTALL_ROOT}/.deploy.env` so each individual step script can be
re-run without re-deriving values:

```bash
. /opt/blakestream-mpos/.deploy.env
sudo -E bash deploy-bundle/scripts/50-install-mpos.sh
```

## Tunable env vars

See the comment block at the top of `deploy-testnet.sh`. Most operators only
need to change `MPOS_DOMAIN` (for non-catch-all nginx vhosts) and
`MPOS_HTTP_PORT`.

## Dependencies

- Mainnet deployment must be run from a clone of
  `https://github.com/BlueDragon747/php-mpos/tree/25.2-GO`.
- Mainnet daemon images are pulled from Docker Hub by default. The default
  image set is
  `sidgrip/{blakecoin,photon,blakebitcoin,electron,lithium,universalmolecule}:25.2`.
  Set `MPOS_PULL_DAEMON_IMAGES=0` to clone the coin source repos and build
  local daemon runtime images instead. If images are already loaded on the
  target host, also set `SKIP_DAEMON_IMAGE_BUILD=1`.
- This bundle expects an `eloipool_Blakecoin` tree available
  at deploy time. By default the deploy script auto-clones it from
  `https://github.com/BlueDragon747/eloipool_Blakecoin.git` (branch `25.2-GO`;
  `https://github.com/BlueDragon747/eloipool_Blakecoin/tree/25.2-GO`)
  into a temp directory; override with `ELIOPOOL_TREE=/path/to/checkout`
  to use a local copy instead. It rsyncs the eloipool tree from there
  rather than maintaining a parallel copy.
  Change `ELIOPOOL_BRANCH` to `master` after live cutover once master carries
  the Go Eloipool updates.
- This bundle expects `cronjobs-py/` at the MPOS repo root (already
  shipped in this repo).

## Verification

`scripts/99-verify.sh` checks: 6 daemon RPCs respond, all three pool
services are active, all four pool/UI ports are listening, MPOS HTTP
returns 2xx/3xx, and the MPOS DB is reachable. Exit 0 = green.

## Mainnet Status

Mainnet is wired through `deploy-mainnet.sh` and the
`scripts/mainnet/` step set. Release validation has covered all six
bootstrap links, daemon RPCs, pool services, web UI, cronjobs-py, SSE,
and backup checks.
