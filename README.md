Description
===========

MPOS is a web-based mining portal for cryptocurrency pools. It was created by
[TheSerapher](https://github.com/TheSerapher) and later adapted for the Blake
merge-mine pools by BlueDragon747.

This branch is the Blakestream 25.2-GO deploy lane. It keeps the legacy
PHP/Smarty MPOS application, adds Vue/Vite dashboard pieces, uses
`cronjobs-py` as the authoritative scheduler, and integrates with the Go
Eloipool 25.2 stratum stack.

**NOTE**: This is a merge-mine branch for the Blakecoin-family Blakestream
pool: BLC parent chain plus PHO, BBTC, ELT, UMO, and LIT aux chains.

Donations
=========


Website Footer
==============

When you decide to use `MPOS` please be so kind and leave the footer intact. You are not the author of the software and should honor those that have worked on it. I don't mind changing the LTC donation address at the bottom, but keep in mind who really wrote this software and would deserve those ;-).

Donors
======

These people have supported this project with a donation:


Pools running MPOS
==================

You can find a list of active pools [here](https://github.com/TheSerapher/php-mpos/wiki/Pools).

Requirements
============

The 25.2-GO deploy path is tested on Ubuntu 24.04 x86_64. Ubuntu 22.04 may
work, but Ubuntu 24.04 is the target for the current daemon builds and deploy
bundle.

Be aware that `MPOS` is **only** for pooled mining. Solo mining is not
supported because MPOS accounting depends on submitted pool shares; solo miners
create blocks directly and do not create the share records MPOS needs for reward
tracking.

Server requirements:

* 64-bit Ubuntu 24.04 VPS with systemd.
* Root access, or a sudo user that can run the deploy bundle with `sudo -E`.
* Outbound HTTPS and git access for package installs, Docker image pulls,
  bootstrap downloads, and optional source builds.
* Docker Engine for the six 25.2 wallet daemon containers.
* Nginx, PHP-FPM, MariaDB, memcached, Python 3 venv tooling, Bun, and Go.
  The mainnet deploy installs these on the pool server.
* Enough disk for chain data, Docker images, MPOS, logs, and backups. Source
  builds need about 15 GB extra under `/root/blakestream-daemon-builds`.

Pool software and branch requirements:

* MPOS: `BlueDragon747/php-mpos`, branch `25.2-GO`.
* Eloipool: `BlueDragon747/eloipool_Blakecoin`, branch `25.2-GO`.
* Wallet daemon source builds use these branches until live cutover:
  `BlueDragon747/Blakecoin` `0.25.2`,
  `BlueDragon747/photon` `0.25.2`,
  `BlakeBitcoin/BlakeBitcoin` `0.25.2`,
  `BlueDragon747/Electron-ELT` `0.25.2`,
  `BlueDragon747/universalmol` `0.25.2`, and
  `BlueDragon747/lithium` `0.25.2`.
* After live cutover, switch the Eloipool and wallet source defaults to
  `master` once those repositories carry the 25.2 updates on `master`.

Features
========

The following features have been implemented so far:

* Fully re-written GUI with [Smarty][2] templates
 * Full file based template support
 * **NEW** SQL based templates
* Mobile WebUI
* Blake-256 8-round, AuxPoW merge mining, and VARDIFF support
* Reward Systems
 * Proportional, PPS and PPLNS
* New Theme
 * Live Dashboard
 * AJAX Support
 * Overhauled API
* Web User accounts
 * Re-Captcha protected registration form
* Worker accounts
 * Worker activity
 * Worker hashrates
* Pool statistics
* Block statistics
* Pool donations, fees and block bonuses
* Manual and auto payout
 * Wallet-estimated network fees for 25.2 payout broadcasts
* Transaction list
* Admin Panel
 * Cron Monitoring Overview
 * User Listing including statistics
 * Wallet information
 * User Transactions
 * News Posts
 * Pool Settings
 * Templates
 * Pool Workers
 * User Reports
 * Template Overwrite
* Notification system
 * IDLE Workers
 * New blocks found in pool
 * Auto Payout
 * Manual Payout
* User-to-user Invitation System
* Support for various coins via config
 * All Blake-256 coins *8 round variant
* Blakestream 25.2 service monitoring and Go Eloipool share-log import into
  MPOS accounting tables

Installation
============

For the Blakestream mainnet deployment path, clone this repo on the pool
server and run the automated deploy bundle locally:

```bash
git clone -b 25.2-GO https://github.com/BlueDragon747/php-mpos.git php-mpos

cd php-mpos
export MPOS_DOMAIN=pool.example.com
export MPOS_ADMIN_EMAIL=admin@example.com

# If you are already root, drop the sudo -E prefix.
# No host argument means install on this local server.
sudo -E bash deploy-bundle/deploy-mainnet.sh
```

If you prefer to deploy from a separate workstation over SSH, use the same
repo clone and pass the target host:

```bash
cd php-mpos
export MPOS_DOMAIN=pool.example.com
export MPOS_ADMIN_EMAIL=admin@example.com

bash deploy-bundle/deploy-mainnet.sh root@your-vps
```

The deploy runs the six coin daemons from Docker images. By default it
pulls `sidgrip/<coin>:25.2` from Docker Hub. To build daemon images on
the pool server instead, disable daemon image pulls:

```bash
export MPOS_PULL_DAEMON_IMAGES=0
sudo -E bash deploy-bundle/deploy-mainnet.sh
```

That source-build path clones:
`BlueDragon747/Blakecoin`, `BlueDragon747/photon`,
`BlakeBitcoin/BlakeBitcoin`, `BlueDragon747/Electron-ELT`,
`BlueDragon747/universalmol`, and `BlueDragon747/lithium` from their
`0.25.2` branches by default, builds daemon binaries in Docker, then tags
local runtime images as `local/<coin>:25.2-local`.
Those source-build branch pins should switch to `master` after live
cutover once master carries the 25.2 wallet updates.

Source builds require Docker and enough disk for six source trees and build
outputs; plan for about 15 GB free under `/root/blakestream-daemon-builds`.

If you already built or loaded images yourself, point the deploy at those
image names and disable pulls:

```bash
export MPOS_DOCKER_HUB=local
export MPOS_IMAGE_TAG=25.2-test
export MPOS_PULL_DAEMON_IMAGES=0
export SKIP_DAEMON_IMAGE_BUILD=1
sudo -E bash deploy-bundle/deploy-mainnet.sh
```

`SKIP_DAEMON_IMAGE_BUILD=1` expects images to already be tagged as
`${MPOS_DOCKER_HUB}/<coin>:${MPOS_IMAGE_TAG}` on the target server.

Bootstrap options:

```bash
# Default: discover the fastest 25.2 mirror from mirrors.json, download
# each current *.dat.xz plus its .sha256 sidecar, verify, then decompress
# to bootstrap.dat before starting each daemon.
# If you are already root, use `bash deploy-bundle/deploy-mainnet.sh`.
sudo -E bash deploy-bundle/deploy-mainnet.sh

# Pin a specific public mirror instead of auto-picking from the registry.
export BOOTSTRAP_MIRROR_HOST=bootstrap-uk.blakestream.io
sudo -E bash deploy-bundle/deploy-mainnet.sh

# Use a local or private 25.2 bootstrap mirror. The mirror must expose:
#   /25.2/<coin>-bootstrap-<height>.dat.xz
#   /25.2/<coin>-bootstrap-<height>.dat.xz.sha256
export BOOTSTRAP_URL=http://127.0.0.1:8080
export BOOTSTRAP_MIRROR_DISCOVERY=0
sudo -E bash deploy-bundle/deploy-mainnet.sh

# Use pre-seeded bootstrap.dat files already placed in the daemon datadirs:
#   /root/.blakecoin/bootstrap.dat
#   /root/.photon/bootstrap.dat
#   /root/.blakebitcoin/bootstrap.dat
#   /root/.electron/bootstrap.dat
#   /root/.universalmolecule/bootstrap.dat
#   /root/.lithium/bootstrap.dat
sudo -E bash deploy-bundle/deploy-mainnet.sh

# Skip bootstrap replay and let daemons sync from peers instead.
export SKIP_BOOTSTRAP=1
sudo -E bash deploy-bundle/deploy-mainnet.sh
```

Eliopool is cloned automatically from
`https://github.com/BlueDragon747/eloipool_Blakecoin.git` branch `25.2-GO`
unless you set `ELIOPOOL_TREE` to a local checkout.
Switch the Eloipool branch default to `master` after live cutover once
master carries the Go Eloipool updates.

See [deploy-bundle/README.md](deploy-bundle/README.md) for deploy details.

The older upstream [Quick Start Guide](https://github.com/TheSerapher/php-mpos/wiki/Quick-Start-Guide) describes the legacy manual MPOS flow and is not the Blakestream mainnet deploy path.

Customization
=============

This project was meant to allow users to easily customize the system and templates. Hence no upstream framework was used to keep it as simple as possible.
If you are just using the system, there will be no need to adjust anything. Things will work out of the box! But if you plan on creating
your own theme, things are pretty easy:

* Create a new theme folder in `public/templates/`
* Create a new site_assets folder in `public/site_assets`
* Create your own complete custom template or copy from an existing one
* Change your theme in the `Admin Panel` and point it to the newly created folder

The good thing with this approach: You can keep the backend code updated! Since your new theme will never conflict with existing themes, a simple git pull will
keep your installation updated. You decide which new feature you'd like to integrate on your own theme. Bugfixes to the code will work out of the box!

Other customizations are also possible but will require merging changes together. Usually users would not need to change the backend code unless they wish to work
on non-existing features in `MPOS`. For the vast majority, adjusting themes should be enough to highlight your pool from others.

In all that, I humbly ask to keep the `MPOS` author reference and GitHub URL intact.

Related Software
================

There are a few other projects out there that take advantage of MPOS and it's included API. Here a quick list that you can check out for yourself:

* [MPOS IRC Bot](https://github.com/WKNiGHT-/mpos-bot) written in Python, standalone bot, using the MPOS API
* [MPOS Eggdrop Module](https://github.com/iAmShorty/mpos-eggdrop-tcl) written in TCL, adding MPOS commands to this bot, using the MPOS API
* [Windows Phone Pool App](http://www.windowsphone.com/en-us/store/app/meeneminermonitor/7ec6eac7-a642-409b-96c8-57b5cfdf45cf)
* [iPhone iMPOS App](https://itunes.apple.com/us/app/impos/id742179239?mt=8)

Contributing
============

You can contribute to this project in different ways:

* Report outstanding issues and bugs by creating an [Issue][1]
* Suggest feature enhancements also via [Issues][1]
* Create pull requests against `BlueDragon747/php-mpos` branch `25.2-GO` for
  Blakestream 25.2 pool work.

Contact
=======

Historical upstream MPOS discussion used Freenode `#MPOS`. Blakestream 25.2
work should be tracked through the active GitHub repository and branch above.

Team Members
============

Author and GitHub Owner: [TheSerapher](https://github.com/TheSerapher) aka Sebastian Grewe

Developers:

* [nrpatten](https://github.com/nrpatten)
* [Aim](https://github.com/fspijkerman)
* [raistlinthewiz](https://github.com/raistlinthewiz)
* [xisi](https://github.com/xisi)
* [nutnut](https://github.com/nutnut)
* [obigal](https://github.com/obigal)
* [iAmShorty](https://github.com/iAmShorty)
* [rog1121](https://github.com/rog1121)
* [neozonz](https://github.com/neozonz)
* [BlueDragon747](https://github.com/BlueDragon747)

License and Author
==================

Copyright 2012, Sebastian Grewe

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.


  [1]: https://github.com/BlueDragon747/php-mpos/issues "Issue"
  [2]: http://www.smarty.net/docs/en/ "Smarty"
