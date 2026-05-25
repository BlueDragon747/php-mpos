#!/usr/bin/env bash
# 10-vps-system-deps.sh — install Docker, LAMP, memcached.
# Runs on the VPS as root.
set -euo pipefail
say() { printf '\033[1;33m   %s\033[0m\n' "$*"; }

export DEBIAN_FRONTEND=noninteractive

# Are we on Ubuntu 24.04 (the only release this is tested on)?
# shellcheck source=/dev/null
. /etc/os-release
if [ "${ID}" != "ubuntu" ]; then
    echo "warn: only tested on Ubuntu (found ${ID}); proceeding anyway" >&2
fi
PHP_VER="8.3"

say "apt update"
apt-get -qq update

# Core LAMP + helpers + Docker prereqs. git/ufw/cron/logrotate are
# present on most Ubuntu base images but minimal cloud installs may
# omit them; the daemon source-build step needs git, step 80 needs ufw,
# step 60 needs cron, step 85 needs logrotate.
say "apt install (LAMP + helpers + docker prereqs)"
apt-get -qq install -y \
    curl jq wget rsync xz-utils xxd ca-certificates gnupg lsb-release sudo \
    git ufw cron logrotate \
    nginx \
    mariadb-server \
    php${PHP_VER}-cli php${PHP_VER}-fpm php${PHP_VER}-mysql \
    php${PHP_VER}-curl php${PHP_VER}-gd php${PHP_VER}-memcached \
    php${PHP_VER}-mbstring php${PHP_VER}-xml \
    memcached libmemcached-tools \
    python3 python3-venv python3-pip

# Docker repo + docker-ce.
if ! command -v docker >/dev/null 2>&1; then
    say "installing docker-ce"
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
        > /etc/apt/sources.list.d/docker.list
    apt-get -qq update
    apt-get -qq install -y docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
    say "docker installed; version: $(docker --version)"
else
    say "docker already installed: $(docker --version)"
fi

# bun (used to build the Vue v2 frontend in deploy-mainnet.sh).
if ! command -v bun >/dev/null 2>&1; then
    say "installing bun system-wide"
    BUN_INSTALL=/usr/local bash -c 'curl -fsSL https://bun.sh/install | bash' \
        >/tmp/bun-install.log 2>&1 \
        || { cat /tmp/bun-install.log >&2; exit 1; }
    say "bun installed: $(/usr/local/bin/bun --version)"
else
    say "bun already installed: $(bun --version)"
fi

# MariaDB on
systemctl enable --now mariadb
say "mariadb: $(systemctl is-active mariadb)"

# memcached on
systemctl enable --now memcached
say "memcached: $(systemctl is-active memcached)"

# nginx on
systemctl enable --now nginx
say "nginx: $(systemctl is-active nginx)"

# PHP-FPM on
systemctl enable --now php${PHP_VER}-fpm
say "php-fpm: $(systemctl is-active php${PHP_VER}-fpm)"

say "tuning php-fpm pool"
FPM_POOL=/etc/php/${PHP_VER}/fpm/pool.d/www.conf
set_fpm_pool_value() {
    local key="$1" value="$2"
    local pattern="${key//./\\.}"
    if grep -Eq "^[;[:space:]]*${pattern}[[:space:]]*=" "$FPM_POOL"; then
        sed -i "s|^[;[:space:]]*${pattern}[[:space:]]*=.*|${key} = ${value}|" "$FPM_POOL"
    else
        printf '%s = %s\n' "$key" "$value" >> "$FPM_POOL"
    fi
}
set_fpm_pool_value pm.max_children 200
set_fpm_pool_value pm.start_servers 5
set_fpm_pool_value pm.min_spare_servers 5
set_fpm_pool_value pm.max_spare_servers 35
set_fpm_pool_value pm.max_requests 500
set_fpm_pool_value request_terminate_timeout 60s

# Memcached PHP serializer must match what MPOS writes (php-native, not igbinary).
# Write a drop-in conf to be sure (apt may default to igbinary).
PHP_INI_CONF=/etc/php/${PHP_VER}/mods-available/blakestream-memcached.ini
cat > "$PHP_INI_CONF" <<INI
; Forced by Blakestream-MPOS deploy: cronjobs-py reads what PHP wrote, so
; serializer must be php-native.
memcached.serializer = php
INI
ln -sf "$PHP_INI_CONF" /etc/php/${PHP_VER}/cli/conf.d/30-blakestream-memcached.ini
ln -sf "$PHP_INI_CONF" /etc/php/${PHP_VER}/fpm/conf.d/30-blakestream-memcached.ini
systemctl restart php${PHP_VER}-fpm

# Persist the PHP version we picked so subsequent steps can read it.
echo "${PHP_VER}" > /opt/blakestream-mpos.php-version 2>/dev/null \
    || { mkdir -p /opt && echo "${PHP_VER}" > /opt/blakestream-mpos.php-version; }

say "step 10 done"
