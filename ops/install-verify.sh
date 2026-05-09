#!/bin/bash
# Run BEFORE you point real miners at a fresh MPOS install.
# Catches the 10 most common "I deployed and nothing works" failures
# without touching the pool.
#
# Non-zero exit = not ready. Human-readable output either way.

set -u
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'
fail()  { echo -e "${RED}[FAIL]${NC} $*"; FAILS=$((FAILS+1)); }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; WARNS=$((WARNS+1)); }
ok()    { echo -e "${GREEN}[ OK ]${NC} $*"; }
FAILS=0; WARNS=0

: "${CFG:=/var/www/mpos/public/include/config/global.inc.php}"

echo "== MPOS install-verify =="
echo "config: $CFG"
echo

# 1. SALT / SALTY not shipped placeholders --------------------------------
if [ -r "$CFG" ]; then
  salt=$(grep -oE "\\\$config\\['SALT'\\]\\s*=\\s*'[^']+'" "$CFG" | head -1 | sed -E "s/.*='([^']+)'/\\1/")
  salty=$(grep -oE "\\\$config\\['SALTY'\\]\\s*=\\s*'[^']+'" "$CFG" | head -1 | sed -E "s/.*='([^']+)'/\\1/")
  case "$salt" in
    CHANGE_ME_BEFORE_DEPLOY_*|PLEASEMAKEMESOMETHINGRANDOM) fail "\$config['SALT'] is the shipped placeholder" ;;
    "") fail "\$config['SALT'] not set" ;;
    *) [ "${#salt}" -lt 24 ] && warn "\$config['SALT'] is only ${#salt} chars (want ≥24)" || ok "SALT is set (${#salt} chars)" ;;
  esac
  case "$salty" in
    CHANGE_ME_BEFORE_DEPLOY_*|THISSHOULDALSOBERRAANNDDOOM) fail "\$config['SALTY'] is the shipped placeholder" ;;
    "") fail "\$config['SALTY'] not set" ;;
    *) [ "${#salty}" -lt 24 ] && warn "\$config['SALTY'] is only ${#salty} chars (want ≥24)" || ok "SALTY is set (${#salty} chars)" ;;
  esac
else
  fail "config not readable at $CFG"
fi

# 2. DB_VERSION seed ------------------------------------------------------
if [ -r "${MPOS_DB_CREDS:-/root/.mpos-db.creds}" ]; then
  # shellcheck disable=SC1090
  . "${MPOS_DB_CREDS:-/root/.mpos-db.creds}"
fi
: "${MPOS_DB_USER:=mpos}"
if [ -n "${MPOS_DB_PASS:-}" ]; then
  row=$(mysql -u "$MPOS_DB_USER" -p"$MPOS_DB_PASS" -N -B mpos -e \
    "SELECT value FROM settings WHERE name='DB_VERSION'" 2>/dev/null)
  if [ -z "$row" ]; then
    fail "settings.DB_VERSION row missing — cronjobs will refuse to run (add 'INSERT INTO settings (name,value) VALUES (\"DB_VERSION\",\"0.0.5\")')"
  else
    ok "settings.DB_VERSION = $row"
  fi
else
  warn "MPOS_DB_PASS not set, skipping DB_VERSION check"
fi

# 3. cron log dirs exist ---------------------------------------------------
for d in pplns_payout findblock payouts blockupdate; do
  if [ -d /var/www/mpos/cronjobs/logs/$d ]; then
    ok "cronjobs/logs/$d exists"
  else
    warn "cronjobs/logs/$d missing — KLogger will try to mkdir at first run"
  fi
done

# 4. segwit_hrps matches deployed network ---------------------------------
hrps=$(grep -oE "\\\$config\\['segwit_hrps'\\]\\s*=\\s*array\\([^)]*\\)" "$CFG" | head -1)
if echo "$hrps" | grep -q "'rblc'"; then
  warn "segwit_hrps includes 'rblc' (regtest) — sanity-check you're not shipping a dev config"
fi
if echo "$hrps" | grep -q "'blc'"; then
  ok "segwit_hrps includes 'blc' (mainnet)"
else
  fail "segwit_hrps missing 'blc' — mainnet addresses will be rejected"
fi

# 5. confirmations threshold sane -----------------------------------------
confs=$(grep -oE "\\\$config\\['confirmations'\\]\\s*=\\s*[0-9]+" "$CFG" | head -1 | grep -oE '[0-9]+')
if [ -n "$confs" ]; then
  if [ "$confs" -lt 100 ]; then
    warn "\$config['confirmations']=$confs looks low for mainnet (real coin expects ≥100, typically 140)"
  else
    ok "confirmations=$confs"
  fi
fi

# 6. Apache + PHP + extensions --------------------------------------------
if systemctl is-active --quiet apache2; then ok "apache2 active"; else fail "apache2 not active"; fi
if systemctl is-active --quiet mariadb;   then ok "mariadb active"; else fail "mariadb not active"; fi
if systemctl is-active --quiet memcached; then ok "memcached active"; else fail "memcached not active"; fi

for ext in mysqli mbstring curl gd bcmath memcached; do
  php -m 2>/dev/null | grep -iq "^$ext$" && ok "PHP extension: $ext" || fail "PHP extension missing: $ext"
done

# 7. Sendmail present ------------------------------------------------------
if command -v sendmail >/dev/null 2>&1; then
  ok "sendmail in PATH ($(command -v sendmail))"
else
  warn "sendmail not found — MPOS won't send signup/password/payout emails"
fi

# 8. TLS cert -------------------------------------------------------------
if [ -r /etc/letsencrypt/live ]; then
  dom=$(ls /etc/letsencrypt/live 2>/dev/null | head -1)
  if [ -n "$dom" ] && [ -r "/etc/letsencrypt/live/$dom/fullchain.pem" ]; then
    ok "Let's Encrypt cert present for $dom"
  else
    warn "TLS: /etc/letsencrypt/live exists but no fullchain.pem"
  fi
else
  warn "TLS: no Let's Encrypt cert — production pool should serve HTTPS"
fi

# 9. Admin password strength ----------------------------------------------
# Run the hash through PHP so the SALT value never hits the shell's word
# list (avoids escaping bugs and accidental shell-metachar expansion).
if [ -n "${MPOS_DB_PASS:-}" ] && [ -r "$CFG" ]; then
  # PHP script: print the sha256 hash of each trivial password under this
  # install's SALT. Read the CFG directly so we don't depend on our own
  # grep of it matching.
  weak_hashes=$(php -r '
    function cfip() { return true; }
    require $argv[1];
    $salt = $config["SALT"] ?? "";
    foreach (["sid","admin","password","changeme","mpos","pool","123456"] as $p) {
      echo hash("sha256", $p . $salt) . "\n";
    }
  ' "$CFG" 2>/dev/null)
  if [ -n "$weak_hashes" ]; then
    weak_list=$(printf "%s\n" $weak_hashes | awk '{printf("%s\"%s\"", (NR==1?"":","), $0)}')
    weak_users=$(mysql -u "$MPOS_DB_USER" -p"$MPOS_DB_PASS" -N -B mpos -e \
      "SELECT username FROM accounts WHERE is_admin=1 AND pass IN ($weak_list)" 2>/dev/null)
    if [ -n "$weak_users" ]; then
      fail "admin account(s) using a trivial password: $weak_users"
    else
      ok "admin password not trivially weak (sid/admin/password/changeme/mpos/pool/123456)"
    fi
  else
    warn "skipped trivial-admin-password check (PHP hash helper failed)"
  fi
fi

# 10. Reward sanity -------------------------------------------------------
# Use PHP to read the config rather than grep — the previous grep regex
# false-positive'd on the assignment line and reported the wrong value.
if [ -r "$CFG" ]; then
  rt=$(php -r 'function cfip(){return true;} require $argv[1]; echo $config["reward_type"] ?? "";' "$CFG" 2>/dev/null)
  rw=$(php -r 'function cfip(){return true;} require $argv[1]; echo $config["reward"] ?? "";' "$CFG" 2>/dev/null)
  if [ "$rt" = "block" ]; then
    ok "reward_type=block (reads true coinbase from daemon)"
  else
    warn "reward_type='$rt' — static fallback reward=$rw will be credited; ensure it matches current halving era"
  fi
fi

echo
echo "== result =="
if [ "$FAILS" -gt 0 ]; then
  echo -e "${RED}$FAILS failure(s), $WARNS warning(s) — NOT READY${NC}"
  exit 1
elif [ "$WARNS" -gt 0 ]; then
  echo -e "${YELLOW}$WARNS warning(s), 0 failures — review before launch${NC}"
  exit 0
else
  echo -e "${GREEN}all checks passed${NC}"
  exit 0
fi
