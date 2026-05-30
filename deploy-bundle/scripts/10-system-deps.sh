#!/usr/bin/env bash
# Install system packages needed by Blakestream-MPOS.
#   - nginx + php-fpm + extensions
#   - mariadb-server
#   - memcached
#   - python venv tooling for cronjobs-py
#   - docker (used for daemon image extraction in 20-pull-daemons)
set -euo pipefail

say() { printf '\033[1;33m   %s\033[0m\n' "$*"; }

export DEBIAN_FRONTEND=noninteractive

say "apt-get update"
apt-get update -qq

# PHP version varies by Ubuntu release. Detect.
PHP_VER=""
for v in 8.3 8.2 8.1; do
    if apt-cache show php${v}-fpm >/dev/null 2>&1; then
        PHP_VER="$v"
        break
    fi
done
[ -n "$PHP_VER" ] || { echo "no compatible php-fpm package found in apt" >&2; exit 1; }
say "selected PHP ${PHP_VER}"
echo "$PHP_VER" > "${MPOS_INSTALL_ROOT}/.php-version"

PKGS=(
    nginx
    "php${PHP_VER}-fpm" "php${PHP_VER}-mysql" "php${PHP_VER}-curl"
    "php${PHP_VER}-gd" "php${PHP_VER}-memcached" "php${PHP_VER}-xml"
    "php${PHP_VER}-mbstring" "php${PHP_VER}-bcmath" "php${PHP_VER}-cli"
    mariadb-server mariadb-client
    memcached
    python3 python3-venv python3-pip
    rsync unzip xz-utils xxd curl jq
    docker.io
    sudo
)

say "installing: ${PKGS[*]}"
apt-get install -y -qq --no-install-recommends "${PKGS[@]}"

say "stopping any prior apache2 (port 80 squatter)"
systemctl stop apache2 2>/dev/null || true
systemctl disable apache2 2>/dev/null || true

say "starting services"
systemctl enable --now mariadb >/dev/null
systemctl enable --now memcached >/dev/null
systemctl enable --now "php${PHP_VER}-fpm" >/dev/null
systemctl enable --now nginx >/dev/null
systemctl enable --now docker >/dev/null

# Verify each came up — `enable --now` can succeed even when the start
# half fails (port already bound, missing config file, etc).
for svc in mariadb memcached "php${PHP_VER}-fpm" nginx docker; do
    if ! systemctl is-active --quiet "$svc"; then
        echo "ERROR: $svc failed to start" >&2
        systemctl --no-pager status "$svc" | tail -10 >&2
        exit 1
    fi
done

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
systemctl restart "php${PHP_VER}-fpm"

say "system deps OK"
