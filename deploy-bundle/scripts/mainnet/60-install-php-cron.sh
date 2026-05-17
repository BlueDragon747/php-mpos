#!/usr/bin/env bash
# 60-install-php-cron.sh — install the PHP cronjobs/ TREE only.
#
# IMPORTANT: this script does NOT install /etc/cron.d/blakestream-mpos.
# cronjobs-py is authoritative on mainnet (see 70-install-cronjobs-py.sh).
# Running both PHP cron and cronjobs-py against the same DB would race
# on shares/transactions tables and double-send payouts.
#
# The PHP tree is staged under /opt/blakestream-mpos/cronjobs/ purely
# so an operator can run individual scripts ad-hoc for diagnostic
# purposes (e.g. `php cronjobs/blockupdate.php` to refresh a stuck
# block's confirmations). It is NOT scheduled.
#
# To re-enable PHP cron as authoritative (drift testing / rollback):
#   1. Set CRONJOBS_PY_SHADOW_MODE=1 in
#      /etc/systemd/system/blakestream-mpos-cronjobs.service
#   2. systemctl daemon-reload && systemctl restart blakestream-mpos-cronjobs
#   3. Install the cron file:
#      install -m 644 deploy-bundle/cron/blakestream-mpos.cron /etc/cron.d/blakestream-mpos
#   4. service cron reload
set -euo pipefail
say() { printf '\033[1;33m   %s\033[0m\n' "$*"; }

INSTALL_ROOT=/opt/blakestream-mpos
MPOS_REPO=/root/Blakestream-MPOS

mkdir -p "${INSTALL_ROOT}/cronjobs"
say "rsync cronjobs/ → ${INSTALL_ROOT}/cronjobs/ (tree only — NOT scheduled)"
rsync -a "${MPOS_REPO}/cronjobs/" "${INSTALL_ROOT}/cronjobs/"
chown -R www-data:www-data "${INSTALL_ROOT}/cronjobs"

# Sanity check: cronjobs/shared.inc.php must be able to load
# global.inc.php via BASEPATH=../public/.
say "smoke-test PHP cron require chain (ad-hoc invocation only)"
sudo -u www-data sh -c "cd ${INSTALL_ROOT}/cronjobs && php -r '
function cfip() { return true; }
\$config = [];
require_once \"../public/include/config/global.inc.dist.php\";
require_once \"../public/include/config/global.inc.php\";
echo \"db.host=\" . \$config[\"db\"][\"host\"] . \" wallet.host=\" . \$config[\"wallet\"][\"host\"] . PHP_EOL;
'"

# Defensive: remove any pre-existing /etc/cron.d/blakestream-mpos so a
# repeat install on a host that previously ran PHP-authoritative
# doesn't leave it scheduled alongside cronjobs-py.
if [ -f /etc/cron.d/blakestream-mpos ]; then
    say "removing stale /etc/cron.d/blakestream-mpos from prior PHP-authoritative deploy"
    rm -f /etc/cron.d/blakestream-mpos
    service cron reload || true
fi

say "step 60 done — PHP cron tree staged for ad-hoc use; NOT scheduled."
