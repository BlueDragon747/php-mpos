#!/usr/bin/env bash
# 50-install-mpos.sh — install the MPOS web stack with mainnet wallet
# ports.
set -euo pipefail
say() { printf '\033[1;33m   %s\033[0m\n' "$*"; }

INSTALL_ROOT=/opt/blakestream-mpos
LOG_ROOT=/var/log/blakestream-mpos
WEB_ROOT=/var/www/blakestream-mpos
MPOS_REPO=/root/Blakestream-MPOS
PHP_VER=$(cat /opt/blakestream-mpos.php-version)
HOST_IP=$(hostname -I | awk '{print $1}')

# ---- MariaDB ----
say "creating database '${MPOS_DB_NAME}' and user '${MPOS_DB_USER}'"
mariadb <<SQL
CREATE DATABASE IF NOT EXISTS \`${MPOS_DB_NAME}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '${MPOS_DB_USER}'@'localhost' IDENTIFIED BY '${MPOS_DB_PASS}';
ALTER USER '${MPOS_DB_USER}'@'localhost' IDENTIFIED BY '${MPOS_DB_PASS}';
GRANT ALL PRIVILEGES ON \`${MPOS_DB_NAME}\`.* TO '${MPOS_DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

TABLES_PRESENT=$(mariadb -N -B -e "USE \`${MPOS_DB_NAME}\`; SHOW TABLES LIKE 'shares';" 2>/dev/null | wc -l)
if [ "$TABLES_PRESENT" = "0" ]; then
    say "loading database_blank.sql"
    mariadb "${MPOS_DB_NAME}" < "${MPOS_REPO}/sql/database_blank.sql"
else
    say "DB already populated; skipping schema import"
fi

say "applying cronjobs-py wave 1 + wave 5 migrations"
mariadb "${MPOS_DB_NAME}" < "${MPOS_REPO}/deploy-bundle/sql/01-cronjobs-py-wave1.sql" 2>&1 | grep -v "^ERROR 1050\|^ERROR 1061\|already exists" || true
mariadb "${MPOS_DB_NAME}" < "${MPOS_REPO}/deploy-bundle/sql/02-cronjobs-py-wave5.sql" 2>&1 | grep -v "^ERROR 1060\|already exists\|Duplicate column name\|Duplicate key" || true
mariadb "${MPOS_DB_NAME}" < "${MPOS_REPO}/deploy-bundle/sql/03-pplns-shares.sql"

say "seeding required settings rows"
mariadb "${MPOS_DB_NAME}" <<SQL || true
INSERT INTO settings (name, value)
VALUES ('DB_VERSION', '0.0.5')
ON DUPLICATE KEY UPDATE value = VALUES(value);
INSERT IGNORE INTO settings (name, value)
VALUES ('backups_enabled', '1');
SQL

# ---- web tree ----
say "syncing MPOS web tree to ${WEB_ROOT}"
mkdir -p "${WEB_ROOT}"
rsync -a --delete \
    --exclude='.git' --exclude='__pycache__' \
    --exclude='cronjobs-py' --exclude='deploy-bundle' \
    --exclude='ops' --exclude='templates_c' --exclude='tests' \
    "${MPOS_REPO}/public/" "${WEB_ROOT}/"

mkdir -p "${WEB_ROOT}/templates_c" "${LOG_ROOT}"
# MPOS's Smarty config (include/smarty.inc.php) actually sets the
# compile dir to `templates/compile/<THEME>/`, NOT `templates_c/`.
# The conventional `templates_c/` exists for back-compat but is unused
# at runtime. Always create AND clear the real one so template edits
# we just rsync'd take effect on the next request.
mkdir -p "${WEB_ROOT}/templates/compile/mpos" \
         "${WEB_ROOT}/templates/compile/mobile"
rm -f "${WEB_ROOT}/templates/compile/mpos"/*.php \
      "${WEB_ROOT}/templates/compile/mobile"/*.php 2>/dev/null || true
chown -R www-data:www-data "${WEB_ROOT}"
chmod 755 "${WEB_ROOT}"
chmod 770 "${WEB_ROOT}/templates_c" \
          "${WEB_ROOT}/templates/compile/mpos" \
          "${WEB_ROOT}/templates/compile/mobile"

say "installing read-only disk stats sudo helper"
install -o root -g root -m 0755 \
    "${MPOS_REPO}/deploy-bundle/scripts/system-disk-stats.sh" \
    /usr/local/sbin/blakestream-mpos-disk-stats
install -d -o root -g root -m 0750 /etc/sudoers.d
install -o root -g root -m 0440 \
    "${MPOS_REPO}/deploy-bundle/sudoers/blakestream-mpos-disk-stats" \
    /etc/sudoers.d/blakestream-mpos-disk-stats
visudo -cf /etc/sudoers.d/blakestream-mpos-disk-stats >/dev/null
sudo -u www-data sudo -n /usr/local/sbin/blakestream-mpos-disk-stats >/dev/null

# ---- /opt/blakestream-mpos/cronjobs symlink (PHP cron's BASEPATH=../public/) ----
ln -sfn "${WEB_ROOT}" "${INSTALL_ROOT}/public"

# ---- render global.inc.php with mainnet daemon RPC ports ----
say "rendering global.inc.php (mainnet)"
GLOBAL="${WEB_ROOT}/include/config/global.inc.php"
GLOBAL_DIST="${WEB_ROOT}/include/config/global.inc.dist.php"
if [ ! -f "$GLOBAL" ]; then
    cp "$GLOBAL_DIST" "$GLOBAL"
fi

sed -i -E "s|^\\\$config\\['SALT'\\][[:space:]]*=[[:space:]]*'[^']*';|\\\$config['SALT'] = '${MPOS_SALT}';|" "$GLOBAL"
sed -i -E "s|^\\\$config\\['SALTY'\\][[:space:]]*=[[:space:]]*'[^']*';|\\\$config['SALTY'] = '${MPOS_SALTY}';|" "$GLOBAL"
sed -i "s|^\\\$config\\['db'\\]\\['host'\\] = '[^']*';|\\\$config['db']['host'] = '${MPOS_DB_HOST}';|" "$GLOBAL"
sed -i "s|^\\\$config\\['db'\\]\\['user'\\] = '[^']*';|\\\$config['db']['user'] = '${MPOS_DB_USER}';|" "$GLOBAL"
sed -i "s|^\\\$config\\['db'\\]\\['pass'\\] = '[^']*';|\\\$config['db']['pass'] = '${MPOS_DB_PASS}';|" "$GLOBAL"
sed -i "s|^\\\$config\\['db'\\]\\['port'\\] = [0-9]*;|\\\$config['db']['port'] = ${MPOS_DB_PORT};|" "$GLOBAL"
sed -i "s|^\\\$config\\['db'\\]\\['name'\\] = '[^']*';|\\\$config['db']['name'] = '${MPOS_DB_NAME}';|" "$GLOBAL"
sed -i "s|^\\\$config\\['system'\\]\\['load'\\]\\['max'\\] = [0-9.]*;|\\\$config['system']['load']['max'] = 100.0;|" "$GLOBAL"

# Stratum URL on the Getting Started page.
sed -i "s|^\\\$config\\['gettingstarted'\\]\\['stratumurl'\\] = '[^']*';|\\\$config['gettingstarted']['stratumurl'] = '${HOST_IP}';|" "$GLOBAL"
sed -i "s|^\\\$config\\['gettingstarted'\\]\\['stratumport'\\] = '[^']*';|\\\$config['gettingstarted']['stratumport'] = '${MPOS_STRATUM_PORT}';|" "$GLOBAL"

# Mainnet daemon RPC ports.
python3 - <<PY "$GLOBAL"
import re, sys
path = sys.argv[1]
src = open(path).read()
ports = {
    "wallet"     : 8772,   # blakecoin mainnet (parent)
    "wallet_mm"  : 8984,   # photon
    "wallet_mm1" : 8243,   # blakebitcoin
    "wallet_mm3" : 6852,   # electron
    "wallet_mm4" : 5921,   # universalmolecule
    "wallet_mm5" : 12000,  # lithium
}
user = "${MPOS_NODE_RPC_USER}"
pw   = "${MPOS_NODE_RPC_PASS}"
for slot, port in ports.items():
    src = re.sub(
        rf"(\\\$config\\['{slot}'\\]\\['host'\\] = ')[^']*(';)",
        rf"\\g<1>localhost:{port}\\g<2>", src)
    src = re.sub(
        rf"(\\\$config\\['{slot}'\\]\\['username'\\] = ')[^']*(';)",
        rf"\\g<1>{user}\\g<2>", src)
    src = re.sub(
        rf"(\\\$config\\['{slot}'\\]\\['password'\\] = ')[^']*(';)",
        rf"\\g<1>{pw}\\g<2>", src)
open(path, "w").write(src)
PY

# Enforce the 25.2 maturity map on every deploy. Existing installs keep
# their global.inc.php, so these values must be refreshed explicitly.
python3 - "$GLOBAL" <<'PY'
import re, sys
path = sys.argv[1]
src = open(path).read()
values = {
    "confirmations": 120,
    "confirmations_mm": 120,
    "confirmations_mm1": 100,
    "confirmations_mm2": 120,
    "confirmations_mm3": 460,
    "confirmations_mm4": 120,
    "confirmations_mm5": 120,
    "confirmations_mm6": 120,
    "network_confirmations": 120,
    "network_confirmations_mm": 120,
    "network_confirmations_mm1": 100,
    "network_confirmations_mm2": 120,
    "network_confirmations_mm3": 460,
    "network_confirmations_mm4": 120,
    "network_confirmations_mm5": 120,
    "network_confirmations_mm6": 120,
}
for key, value in values.items():
    pattern = rf"^(\$config\['{re.escape(key)}'\]\s*=\s*)[0-9]+;"
    replacement = rf"\g<1>{value};"
    src, count = re.subn(pattern, replacement, src, flags=re.MULTILINE)
    if count == 0:
        src += f"\n$config['{key}'] = {value};\n"
open(path, "w").write(src)
PY

chown www-data:www-data "$GLOBAL"
chmod 640 "$GLOBAL"

say "tuning MPOS antidos limits"
SECURITY_CONF="${WEB_ROOT}/include/config/security.inc.php"
if [ -f "$SECURITY_CONF" ]; then
    sed -i "s|^\\\$config\\['mc_antidos'\\]\\['rate_limit_api'\\] = [0-9]*;|\\\$config['mc_antidos']['rate_limit_api'] = 6000;|" "$SECURITY_CONF"
    sed -i "s|^\\\$config\\['mc_antidos'\\]\\['rate_limit_site'\\] = [0-9]*;|\\\$config['mc_antidos']['rate_limit_site'] = 6000;|" "$SECURITY_CONF"
fi

# ---- nginx vhost ----
say "writing nginx vhost"
cat > /etc/nginx/sites-available/blakestream-mpos <<EOF
server {
    listen ${MPOS_HTTP_PORT} default_server;
    listen [::]:${MPOS_HTTP_PORT} default_server;
    server_name ${MPOS_DOMAIN};
    root ${WEB_ROOT};
    index index.php index.html;

    access_log ${LOG_ROOT}/nginx-access.log;
    error_log  ${LOG_ROOT}/nginx-error.log;

    location ~ ^/(include|templates|sql)(/|\$) {
        deny all;
        return 403;
    }

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \\.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php${PHP_VER}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        # Override the default SERVER_NAME (\"_\" because of the catch-all
        # \`server_name _\`) with the requesting Host header. MPOS's
        # login.inc.php builds the post-login redirect URL from
        # \$_SERVER['SERVER_NAME']; without this the redirect goes to
        # \"_/index.php?page=dashboard\" which the browser can't resolve.
        fastcgi_param SERVER_NAME \$host;
        fastcgi_read_timeout 60;
    }
}
EOF
ln -sf /etc/nginx/sites-available/blakestream-mpos /etc/nginx/sites-enabled/blakestream-mpos
rm -f /etc/nginx/sites-enabled/default

touch "${LOG_ROOT}/nginx-access.log" "${LOG_ROOT}/nginx-error.log"
chown www-data:www-data "${LOG_ROOT}/nginx-access.log" "${LOG_ROOT}/nginx-error.log"
nginx -t
systemctl restart nginx
systemctl restart "php${PHP_VER}-fpm"

# ---- admin seed ----
say "seeding admin '${MPOS_ADMIN_USER}'"
ADMIN_HASH=$(php -r "echo hash('sha256', '${MPOS_ADMIN_PASS}' . '${MPOS_SALT}');")
PIN_HASH=$(php -r "echo hash('sha256', '0000' . '${MPOS_SALT}');")
# api_key matches MPOS's own register-time formula: sha256(username . SALT).
# Without this, every API endpoint (dashboard live updates, navbar refresh,
# v2/dashboard, etc.) returns 401 because checkApiKey() fails on NULL.
ADMIN_API_KEY=$(php -r "echo hash('sha256', '${MPOS_ADMIN_USER}' . '${MPOS_SALT}');")
mariadb "${MPOS_DB_NAME}" <<SQL || true
INSERT INTO accounts (username, pass, pin, email, api_key, is_admin, is_locked, no_fees, donate_percent)
VALUES ('${MPOS_ADMIN_USER}', '${ADMIN_HASH}', '${PIN_HASH}', '${MPOS_ADMIN_EMAIL}', '${ADMIN_API_KEY}', 1, 0, 1, 0.0)
ON DUPLICATE KEY UPDATE pass = VALUES(pass), pin = VALUES(pin), email = VALUES(email),
                        api_key = VALUES(api_key),
                        is_admin = 1, is_locked = 0;
SQL

# eloipool was started in step 40 BEFORE the MPOS schema existed, so
# its authentication.mpos module failed its first SELECT against the
# pool_worker table. Restart it now (and mergeminer, which talks to
# eloipool's jsonrpc) so the auth module reconnects with the schema
# now in place.
if systemctl is-active --quiet blakestream-mpos-eloipool.service; then
    say "restarting eloipool now that MPOS schema is ready"
    systemctl restart blakestream-mpos-eloipool.service
fi
if systemctl is-active --quiet blakestream-mpos-mergeminer.service; then
    say "restarting merged-mine-proxy to re-handshake with eloipool"
    systemctl restart blakestream-mpos-mergeminer.service
fi

say "step 50 done — http://${HOST_IP}:${MPOS_HTTP_PORT}/"
