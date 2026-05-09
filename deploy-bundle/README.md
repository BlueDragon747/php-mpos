# Blakestream-MPOS deploy-bundle

Layered on top of the canonical `eloipool_Blakecoin` testnet
stack, this bundle brings up the full pool with the MPOS web UI and
`cronjobs-py` scheduler in front.

What it installs:

- six BlakeStream daemons (parent + 5 aux) extracted from
  `sidgrip/<coin>:15.21` Docker images, with `libboost1.74` runtime
  staged into `ldconfig` so the jammy-built binaries run on 24.04 hosts
- `eloipool` stratum, `merged-mine-proxy.py3`, and the MPOS
  authentication backend wired into the `pool_worker` table
- MariaDB schema (`sql/database_blank.sql`) + a seeded admin account
- nginx + php-fpm vhost serving the MPOS web tree at
  `${MPOS_WEB_ROOT}` (default `/var/www/blakestream-mpos`)
- `cronjobs-py` scheduler running as a systemd service
- daily DB + wallet backup helper and systemd timer, controlled by the
  MPOS `settings.backups_enabled` admin setting

## Layout

```
deploy-bundle/
├── deploy.sh                 # main entry — orchestrates the steps
├── scripts/
│   ├── 05-wipe.sh            # purge prior MPOS install (--wipe)
│   ├── 10-system-deps.sh     # apt: nginx, php-fpm, mariadb, memcached, python, docker
│   ├── 20-pull-daemons.sh    # docker pull + binary extract + libboost ldconfig
│   ├── 30-init-daemons.sh    # write configs, systemd units, start 12 daemons
│   ├── 40-install-pool.sh    # eloipool + MPOS auth + MMP, render config
│   ├── 50-install-mpos.sh    # MariaDB DB, web tree, render global.inc.php, nginx vhost
│   ├── 60-install-cronjobs-py.sh
│   ├── mainnet/
│   │   ├── 21-bootstrap-coins.sh  # sequential solo daemon bootstrap (see below)
│   │   └── ...
│   └── 99-verify.sh
├── templates/
│   └── eloipool-testnet.config.py.template
└── README.md
```

## Bootstrapping daemons sequentially (mainnet)

> ⚠️ **ELT and UMO MUST bootstrap with every other daemon stopped.**
> On a 16 GB host, replaying their `bootstrap.dat` files (4-5 GB each,
> chains at 6 M+ blocks) while other daemons are also running causes
> deterministic OOM during the loadblk → validation transition. Solo,
> ELT bootstraps cleanly in ~30 minutes with RSS plateauing at ~10 GB
> and swap usage under 500 MB. Concurrent, the kernel OOM-kills it
> within ~5 minutes at <10% sync.

`scripts/mainnet/21-bootstrap-coins.sh` automates the rotation: it
stops all 6 containers, then for each coin in turn it sets peering
off, downloads `bootstrap.dat` atomically, starts the daemon solo, waits
for the daemon's external-file import completion log, and treats
`bootstrap.dat.old` as already consumed on reruns. It then flips peering
on and requires local height to be within `TIP_CATCH_LAG` blocks of the
peer tip before moving on. A peer tip a few blocks below local height is
allowed, but a stale peer tip far below local height is rejected. A
timed-out catch-up fails the deploy instead of silently continuing. After
all 6 have bootstrapped, it brings them back online one at a time with a
short health peek between each.

```bash
# Default rotation: ELT → UMO → PHO → LIT → BBTC → BLC, then start all
sudo bash deploy-bundle/scripts/mainnet/21-bootstrap-coins.sh

# Subset (e.g. just ELT and UMO if the smaller chains are already synced):
sudo bash deploy-bundle/scripts/mainnet/21-bootstrap-coins.sh elt umo

# Skip the final start-all phase (operator wants to launch each daemon manually):
START_AFTER=0 sudo bash deploy-bundle/scripts/mainnet/21-bootstrap-coins.sh
```

The script also ensures `dbcache=200` and `maxmempool=50` are set in
each `<coin>.conf`, which keeps post-bootstrap steady-state RAM well
within budget when all 6 daemons run concurrently.

## Mainnet Usage

Run mainnet deployment from a clone of:

```text
https://github.com/SidGrip/php-mpos
```

`deploy-mainnet.sh` pulls the six coin daemon images directly from
Docker Hub as `sidgrip/<coin>:latest` by default, so a separate daemon
container source checkout is not required for normal deployment:

```bash
cd php-mpos

export MPOS_DOMAIN=pool.example.com
export MPOS_ADMIN_EMAIL=admin@example.com
bash deploy-bundle/deploy-mainnet.sh root@your-vps
```

Set `MPOS_DOCKER_HUB` or `MPOS_IMAGE_TAG` only when testing images from
another Docker namespace or tag.

Eliopool is pulled from
`https://github.com/SidGrip/eloipool_Blakecoin.git` branch `master` when
`ELIOPOOL_TREE` is unset. To deploy from a local Eliopool checkout
instead:

```bash
git clone https://github.com/SidGrip/eloipool_Blakecoin.git Blakestream-Eliopool
export ELIOPOOL_TREE="$(cd Blakestream-Eliopool && pwd)"
```

## Legacy Local/Testnet Usage

```bash
# All-in-one install on the local host:
sudo bash deploy-bundle/deploy.sh -local

# Wipe a prior install before deploying:
sudo bash deploy-bundle/deploy.sh -local --wipe

# Skip the daemon + pool layer if already deployed:
sudo bash deploy-bundle/deploy.sh -local --skip-pool
```

`deploy.sh` writes its rendered env to
`${MPOS_INSTALL_ROOT}/.deploy.env` so each individual step script can be
re-run without re-deriving values:

```bash
. /opt/blakestream-mpos/.deploy.env
sudo -E bash deploy-bundle/scripts/50-install-mpos.sh
```

## Tunable env vars

See the comment block at the top of `deploy.sh`. Most operators only
need to change `MPOS_DOMAIN` (for non-catch-all nginx vhosts) and
`MPOS_HTTP_PORT`.

## Dependencies

- Mainnet deployment must be run from a clone of
  `https://github.com/SidGrip/php-mpos`.
- Mainnet daemon images are pulled from Docker Hub. The default image set is
  `sidgrip/{blakecoin,photon,blakebitcoin,electron,lithium,universalmolecule}:latest`.
  Override with `MPOS_DOCKER_HUB` and `MPOS_IMAGE_TAG` if needed.
- This bundle expects an `eloipool_Blakecoin` tree available
  at deploy time. By default the deploy script auto-clones it from
  `https://github.com/SidGrip/eloipool_Blakecoin.git` (branch `master`)
  into a temp directory; override with `ELIOPOOL_TREE=/path/to/checkout`
  to use a local copy instead. It rsyncs the eloipool tree from there
  rather than maintaining a parallel copy.
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
