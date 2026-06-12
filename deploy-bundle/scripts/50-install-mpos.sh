#!/usr/bin/env bash
# Install MPOS web stack:
#   - MariaDB DB + user + schema
#   - rsync MPOS public/ tree to MPOS_WEB_ROOT
#   - render global.inc.php with deploy-time secrets and testnet RPCs
#   - nginx vhost + php-fpm pool
#   - seed admin user + DB_VERSION
set -euo pipefail

say() { printf '\033[1;33m   %s\033[0m\n' "$*"; }

PHP_VER=$(cat "${MPOS_INSTALL_ROOT}/.php-version")
HOST_IP=$(hostname -I | awk '{print $1}')

# ---- MariaDB DB + user --------------------------------------------------

say "creating MariaDB database '${MPOS_DB_NAME}' and user '${MPOS_DB_USER}'"
mariadb <<SQL
CREATE DATABASE IF NOT EXISTS \`${MPOS_DB_NAME}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '${MPOS_DB_USER}'@'localhost' IDENTIFIED BY '${MPOS_DB_PASS}';
ALTER USER '${MPOS_DB_USER}'@'localhost' IDENTIFIED BY '${MPOS_DB_PASS}';
GRANT ALL PRIVILEGES ON \`${MPOS_DB_NAME}\`.* TO '${MPOS_DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

# Import schema only if the shares table doesn't yet exist (idempotent
# across redeploys — preserves history).
TABLES_PRESENT=$(mariadb -N -B -e "USE \`${MPOS_DB_NAME}\`; SHOW TABLES LIKE 'shares';" 2>/dev/null | wc -l)
if [ "$TABLES_PRESENT" = "0" ]; then
    say "loading database_blank.sql"
    mariadb "${MPOS_DB_NAME}" < "${MPOS_REPO_ROOT}/sql/database_blank.sql"
else
    say "DB already populated; skipping schema import"
fi

apply_db_migrations() {
    local sql_dir="$1"
    local migration found=0

    if [ ! -d "$sql_dir" ]; then
        say "no database migration directory found at ${sql_dir}; skipping"
        return
    fi

    say "applying database migrations from ${sql_dir}"
    while IFS= read -r -d '' migration; do
        found=1
        say "applying database migration $(basename "$migration")"
        if ! mariadb "${MPOS_DB_NAME}" < "$migration"; then
            echo "database migration failed: ${migration}" >&2
            return 1
        fi
    done < <(find "$sql_dir" -maxdepth 1 -type f -name '*.sql' -print0 | LC_ALL=C sort -z)

    if [ "$found" = "0" ]; then
        say "no database migrations found in ${sql_dir}"
    fi
}

apply_db_migrations "${MPOS_REPO_ROOT}/deploy-bundle/sql"

say "seeding required settings rows"
mariadb "${MPOS_DB_NAME}" <<SQL || true
INSERT INTO settings (name, value)
VALUES ('DB_VERSION', '0.0.5')
ON DUPLICATE KEY UPDATE value = VALUES(value);
INSERT IGNORE INTO settings (name, value)
VALUES ('backups_enabled', '1');
SQL

# ---- MPOS web tree ------------------------------------------------------

say "syncing MPOS web tree to ${MPOS_WEB_ROOT}"
mkdir -p "${MPOS_WEB_ROOT}"
rsync -a --delete \
    --exclude='.git' --exclude='__pycache__' \
    --exclude='cronjobs-py' --exclude='deploy-bundle' \
    --exclude='ops' --exclude='templates_c' \
    "${MPOS_REPO_ROOT}/public/" "${MPOS_WEB_ROOT}/"

mkdir -p "${MPOS_WEB_ROOT}/templates_c"
# MPOS Smarty compile dir is templates/compile/<theme>/, not templates_c/.
# Always create + clear it so re-deploys actually pick up template edits.
mkdir -p "${MPOS_WEB_ROOT}/templates/compile/mpos" \
         "${MPOS_WEB_ROOT}/templates/compile/mobile"
rm -f "${MPOS_WEB_ROOT}/templates/compile/mpos"/*.php \
      "${MPOS_WEB_ROOT}/templates/compile/mobile"/*.php 2>/dev/null || true
chown -R "${MPOS_RUN_USER}:${MPOS_RUN_GROUP}" "${MPOS_WEB_ROOT}"
chmod 755 "${MPOS_WEB_ROOT}"
chmod 770 "${MPOS_WEB_ROOT}/templates_c" \
          "${MPOS_WEB_ROOT}/templates/compile/mpos" \
          "${MPOS_WEB_ROOT}/templates/compile/mobile"

say "installing read-only disk stats sudo helper"
install -o root -g root -m 0755 \
    "${MPOS_DEPLOY_BUNDLE}/scripts/system-disk-stats.sh" \
    /usr/local/sbin/blakestream-mpos-disk-stats
install -d -o root -g root -m 0750 /etc/sudoers.d
install -o root -g root -m 0440 \
    "${MPOS_DEPLOY_BUNDLE}/sudoers/blakestream-mpos-disk-stats" \
    /etc/sudoers.d/blakestream-mpos-disk-stats
visudo -cf /etc/sudoers.d/blakestream-mpos-disk-stats >/dev/null
sudo -u www-data sudo -n /usr/local/sbin/blakestream-mpos-disk-stats >/dev/null

# ---- Render global.inc.php ---------------------------------------------
#
# global.inc.php is NOT tracked in git (it contains DB creds + RPC creds
# rendered from this deploy's environment). We bootstrap from the
# upstream-MPOS .dist template if a previous deploy hasn't already
# rendered it; subsequent runs re-sed the existing copy in place so we
# preserve any operator hand-edits to non-secret keys.

say "rendering ${MPOS_WEB_ROOT}/include/config/global.inc.php"
GLOBAL="${MPOS_WEB_ROOT}/include/config/global.inc.php"
GLOBAL_DIST="${MPOS_WEB_ROOT}/include/config/global.inc.dist.php"
if [ ! -f "$GLOBAL" ]; then
    if [ ! -f "$GLOBAL_DIST" ]; then
        echo "missing both ${GLOBAL} and ${GLOBAL_DIST}; cannot bootstrap" >&2
        exit 1
    fi
    cp "$GLOBAL_DIST" "$GLOBAL"
fi
NODE_RPC_USER="${MPOS_NODE_RPC_USER:-blakestream}"
NODE_RPC_PASS="${MPOS_NODE_RPC_PASS:-blakestream-testnet}"
MPOS_DIFFICULTY_BITS="${MPOS_DIFFICULTY_BITS:-21}"

# Salts
sed -i -E "s|^\\\$config\\['SALT'\\][[:space:]]*=[[:space:]]*'[^']*';|\\\$config['SALT'] = '${MPOS_SALT}';|" "$GLOBAL"
sed -i -E "s|^\\\$config\\['SALTY'\\][[:space:]]*=[[:space:]]*'[^']*';|\\\$config['SALTY'] = '${MPOS_SALTY}';|" "$GLOBAL"

# DB
sed -i "s|^\\\$config\\['db'\\]\\['host'\\] = '[^']*';|\\\$config['db']['host'] = '${MPOS_DB_HOST}';|" "$GLOBAL"
sed -i "s|^\\\$config\\['db'\\]\\['user'\\] = '[^']*';|\\\$config['db']['user'] = '${MPOS_DB_USER}';|" "$GLOBAL"
sed -i "s|^\\\$config\\['db'\\]\\['pass'\\] = '[^']*';|\\\$config['db']['pass'] = '${MPOS_DB_PASS}';|" "$GLOBAL"
sed -i "s|^\\\$config\\['db'\\]\\['port'\\] = [0-9]*;|\\\$config['db']['port'] = ${MPOS_DB_PORT};|" "$GLOBAL"
sed -i "s|^\\\$config\\['db'\\]\\['name'\\] = '[^']*';|\\\$config['db']['name'] = '${MPOS_DB_NAME}';|" "$GLOBAL"
sed -i "s|^\\\$config\\['system'\\]\\['load'\\]\\['max'\\] = [0-9.]*;|\\\$config['system']['load']['max'] = 100.0;|" "$GLOBAL"
sed -i "s|^\\\$config\\['difficulty'\\][[:space:]]*=[[:space:]]*[0-9]*;|\\\$config['difficulty'] = ${MPOS_DIFFICULTY_BITS};|" "$GLOBAL"

# Stratum host displayed on the Getting Started page. Templates add the
# stratum+tcp:// scheme and configured port.
sed -i "s|^\\\$config\\['gettingstarted'\\]\\['stratumurl'\\] = '[^']*';|\\\$config['gettingstarted']['stratumurl'] = '${HOST_IP}';|" "$GLOBAL"

# Re-point wallet slots at the running testnet daemons. Use a Python
# in-place edit to handle the multi-line $config['wallet_*'] blocks safely.
python3 - <<PY "$GLOBAL"
import re, sys
path = sys.argv[1]
src = open(path).read()
ports = {
    "wallet"     : 29332,  # blakecoin testnet (parent)
    "wallet_mm"  : 28998,  # photon
    "wallet_mm1" : 29112,  # blakebitcoin
    "wallet_mm3" : 26852,  # electron
    "wallet_mm4" : 29738,  # universalmolecule
    "wallet_mm5" : 32004,  # lithium
}
user = "${NODE_RPC_USER}"
pw   = "${NODE_RPC_PASS}"
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

chown "${MPOS_RUN_USER}:${MPOS_RUN_GROUP}" "$GLOBAL"
chmod 640 "$GLOBAL"

say "tuning MPOS antidos limits"
SECURITY_CONF="${MPOS_WEB_ROOT}/include/config/security.inc.php"
if [ -f "$SECURITY_CONF" ]; then
    sed -i "s|^\\\$config\\['mc_antidos'\\]\\['rate_limit_api'\\] = [0-9]*;|\\\$config['mc_antidos']['rate_limit_api'] = 6000;|" "$SECURITY_CONF"
    sed -i "s|^\\\$config\\['mc_antidos'\\]\\['rate_limit_site'\\] = [0-9]*;|\\\$config['mc_antidos']['rate_limit_site'] = 6000;|" "$SECURITY_CONF"
fi

# ---- Nginx vhost --------------------------------------------------------

NGINX_VHOST=/etc/nginx/sites-available/blakestream-mpos
preserve_tls_vhost=0
if [ "${MPOS_PRESERVE_NGINX_SSL:-1}" = "1" ] \
   && [ -f "$NGINX_VHOST" ] \
   && grep -Eq 'listen[[:space:]].*443|ssl_certificate|managed by Certbot' "$NGINX_VHOST"; then
    preserve_tls_vhost=1
fi

if [ "$preserve_tls_vhost" = "1" ]; then
    say "preserving existing TLS-enabled nginx vhost"
else
    say "writing nginx vhost"
    cat > "$NGINX_VHOST" <<EOF
server {
    listen ${MPOS_HTTP_PORT} default_server;
    listen [::]:${MPOS_HTTP_PORT} default_server;
    server_name ${MPOS_DOMAIN};
    root ${MPOS_WEB_ROOT};
    index index.php index.html;

    access_log ${MPOS_LOG_ROOT}/nginx-access.log;
    error_log  ${MPOS_LOG_ROOT}/nginx-error.log;

    # Block direct access to include/, templates/, sql/.
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
        # Override SERVER_NAME (\"_\" because of catch-all server_name)
        # with the requesting Host header — MPOS login redirect builds
        # its URL from \$_SERVER['SERVER_NAME'].
        fastcgi_param SERVER_NAME \$host;
        fastcgi_read_timeout 60;
    }
}
EOF
fi
ln -sf "$NGINX_VHOST" /etc/nginx/sites-enabled/blakestream-mpos
rm -f /etc/nginx/sites-enabled/default

mkdir -p "${MPOS_LOG_ROOT}"
# Only chown the nginx log files — leave pool/ and daemons/ subdirs to
# their respective service users. (40-install-pool already gave pool/
# to blakestream-mpos; 30-init-daemons did the same for daemons/.)
touch "${MPOS_LOG_ROOT}/nginx-access.log" "${MPOS_LOG_ROOT}/nginx-error.log"
chown www-data:www-data "${MPOS_LOG_ROOT}/nginx-access.log" "${MPOS_LOG_ROOT}/nginx-error.log"

nginx -t
# Use restart instead of reload so a not-yet-running nginx (e.g. from a
# prior failed start) gets brought up cleanly.
systemctl restart nginx
systemctl restart "php${PHP_VER}-fpm"
systemctl is-active --quiet nginx || { systemctl --no-pager status nginx | tail -10; exit 1; }

# ---- Seed admin account -------------------------------------------------

say "seeding admin account '${MPOS_ADMIN_USER}'"
# MPOS hashes passwords as sha256(password . SALT) — see
# public/include/classes/user.class.php::getHash. SALTY is set in the
# config but isn't used by getHash; it's reserved for other places.
# Email must be a valid format with TLD or the login form's "must be
# email" filter rejects it.
ADMIN_HASH=$(php -r "echo hash('sha256', '${MPOS_ADMIN_PASS}' . '${MPOS_SALT}');")
PIN_HASH=$(php -r "echo hash('sha256', '${MPOS_ADMIN_PIN}' . '${MPOS_SALT}');")
# Random admin api_key, matching the current register-time behaviour
# (random_bytes), NOT the old deterministic sha256(username . SALT) — a
# predictable key lets anyone who knows/cracks SALT call the admin API.
# The api_key must be non-empty or every API endpoint (dashboard live
# updates, navbar refresh, v2/dashboard, etc.) returns 401 (checkApiKey()
# fails on NULL).
ADMIN_API_KEY=$(php -r 'echo bin2hex(random_bytes(32));')
ADMIN_EMAIL="${MPOS_ADMIN_EMAIL:-${MPOS_ADMIN_USER}@blakestream.local}"
# Fill-only on re-run: set the api_key ONLY when it is missing, and otherwise
# leave the existing value completely untouched. An update must never mutate a
# key the operator is already relying on. (A pool still carrying the old
# deterministic sha256(username.SALT) key should rotate it once by hand — see
# Config-Settings.md — rather than have an update silently change it.)
mariadb "${MPOS_DB_NAME}" <<SQL || true
INSERT INTO accounts (username, pass, pin, email, api_key, is_admin, is_locked, no_fees, donate_percent)
VALUES ('${MPOS_ADMIN_USER}', '${ADMIN_HASH}', '${PIN_HASH}', '${ADMIN_EMAIL}', '${ADMIN_API_KEY}', 1, 0, 1, 0.0)
ON DUPLICATE KEY UPDATE pass = VALUES(pass), pin = VALUES(pin), email = VALUES(email),
                        api_key = IF(api_key IS NULL OR api_key = '', VALUES(api_key), api_key),
                        is_admin = 1, is_locked = 0;
SQL

say "MPOS web stack up — http://${HOST_IP}:${MPOS_HTTP_PORT}/"
