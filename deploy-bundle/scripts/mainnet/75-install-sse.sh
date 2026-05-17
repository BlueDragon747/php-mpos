#!/usr/bin/env bash
# 75-install-sse.sh — install the cronjobs-py SSE side-car.
# Adds a systemd unit (blakestream-mpos-sse) listening on
# 127.0.0.1:8090 and patches the nginx vhost to proxy /sse/*
# without buffering.
set -euo pipefail
say() { printf '\033[1;33m   %s\033[0m\n' "$*"; }

INSTALL_ROOT=/opt/blakestream-mpos
LOG_ROOT=/var/log/blakestream-mpos
WEB_ROOT=/var/www/blakestream-mpos
MPOS_REPO=/root/Blakestream-MPOS

CRON_DEST="${INSTALL_ROOT}/cronjobs-py"
VENV="${CRON_DEST}/.venv"
SSE_BIND="${SSE_BIND:-127.0.0.1}"
SSE_PORT="${SSE_PORT:-8090}"

# 1. Ensure the SSE module is in the deployed cronjobs-py tree
#    (it's part of the same package; rsync covered this).
[ -f "${CRON_DEST}/cronjobs_py/sse.py" ] \
    || { echo "missing ${CRON_DEST}/cronjobs_py/sse.py" >&2; exit 1; }

# 2. Drop the frontend JS into the web root.
say "installing /site_assets/mpos/js/sse-live.js"
install -m 644 -o www-data -g www-data \
    "${MPOS_REPO}/public/site_assets/mpos/js/sse-live.js" \
    "${WEB_ROOT}/site_assets/mpos/js/sse-live.js"

# 3. Inject the <script> tag into whichever Smarty template owns the
#    closing </body>. Upstream MPOS uses templates/mpos/master.tpl;
#    forks may have moved it. We grep for the file rather than hard-
#    coding so re-runs and forks both work.
LAYOUT_TPL=$(grep -lE "</body>" "${WEB_ROOT}/templates/mpos"/*.tpl 2>/dev/null | head -1)
if [ -n "${LAYOUT_TPL}" ] && ! grep -q "sse-live.js" "${LAYOUT_TPL}"; then
    say "injecting sse-live.js <script> tag into ${LAYOUT_TPL}"
    sed -i 's|</body>|<script src="/site_assets/mpos/js/sse-live.js"></script>\n</body>|' \
        "${LAYOUT_TPL}"
elif [ -z "${LAYOUT_TPL}" ]; then
    say "no template with </body> found in ${WEB_ROOT}/templates/mpos; " \
        "add <script src=\"/site_assets/mpos/js/sse-live.js\"></script> " \
        "manually if you want live updates"
else
    say "${LAYOUT_TPL} already references sse-live.js"
fi

# Smarty caches compiled templates — drop them so the new <script>
# tag actually appears on the next request.
#
# IMPORTANT: MPOS sets `compile_dir = BASEPATH/templates/compile/<THEME>/`
# in include/smarty.inc.php, NOT the conventional `templates_c/`.
# The legacy `templates_c/` directory does exist for symmetry with
# the upstream Smarty default but it's UNUSED — clearing it is a
# no-op. Always clear `templates/compile/*/` too.
rm -rf "${WEB_ROOT}/templates_c"/*           2>/dev/null || true
rm -rf "${WEB_ROOT}/templates/compile"/*/*   2>/dev/null || true

# 4. systemd unit for the SSE side-car.
say "writing /etc/systemd/system/blakestream-mpos-sse.service"
cat > /etc/systemd/system/blakestream-mpos-sse.service <<EOF
[Unit]
Description=Blakestream-MPOS dashboard SSE side-car
After=mariadb.service
Wants=mariadb.service

[Service]
Type=simple
User=blakestream-mpos
Group=blakestream-mpos
WorkingDirectory=${CRON_DEST}
Environment=MPOS_CONFIG=${WEB_ROOT}/include/config/global.inc.php
ExecStart=${VENV}/bin/cronjobs-py --log-level INFO sse --bind ${SSE_BIND} --port ${SSE_PORT}
StandardOutput=append:${LOG_ROOT}/sse.stdout
StandardError=append:${LOG_ROOT}/sse.stderr
Restart=always
RestartSec=5
# Each client = one persistent fd; bump the limit for headroom.
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now blakestream-mpos-sse.service

# 5. nginx: proxy /sse/ → 127.0.0.1:8090 with buffering disabled
#    and a long read timeout so SSE connections can stay open.
NGINX_VHOST=/etc/nginx/sites-available/blakestream-mpos
if ! grep -q "location /sse/" "${NGINX_VHOST}" 2>/dev/null; then
    say "patching nginx vhost: /sse/ proxy block"
    # Insert just BEFORE the catch-all `location /` block.
    awk -v port="${SSE_PORT}" '
      /location \/ \{/ && !patched {
        print "    # SSE side-car (cronjobs-py sse). text/event-stream needs"
        print "    # buffering off and a generous read timeout."
        print "    location /sse/ {"
        print "        proxy_pass http://127.0.0.1:" port ";"
        print "        proxy_http_version 1.1;"
        print "        proxy_set_header Host $host;"
        print "        proxy_set_header X-Real-IP $remote_addr;"
        print "        proxy_buffering off;"
        print "        proxy_cache off;"
        print "        proxy_read_timeout 24h;"
        print "        chunked_transfer_encoding on;"
        print "    }"
        print ""
        patched = 1
      }
      { print }
    ' "${NGINX_VHOST}" > "${NGINX_VHOST}.new"
    mv "${NGINX_VHOST}.new" "${NGINX_VHOST}"
    nginx -t
    systemctl reload nginx
else
    say "nginx vhost already has /sse/ proxy"
fi

# 6. Smoke test.
say "smoke test: curl /sse/health"
sleep 2
curl -fsSL --max-time 5 "http://${SSE_BIND}:${SSE_PORT}/sse/health" | head -1 || true
say "step 75 done — SSE on ${SSE_BIND}:${SSE_PORT}, /sse/* proxied via nginx"
say "  watch:  curl -N http://${SSE_BIND}:${SSE_PORT}/sse/pool"
