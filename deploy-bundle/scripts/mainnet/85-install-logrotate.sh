#!/usr/bin/env bash
# 85-install-logrotate.sh — install the MPOS log retention policy.
# See deploy-bundle/logrotate/blakestream-mpos and the
# "Log files: kept vs rotated" section of MPOS-Postsegwit.md.
set -euo pipefail
say() { printf '\033[1;33m   %s\033[0m\n' "$*"; }

MPOS_REPO=/root/Blakestream-MPOS

say "installing /etc/logrotate.d/blakestream-mpos"
install -m 644 -o root -g root \
    "${MPOS_REPO}/deploy-bundle/logrotate/blakestream-mpos" \
    /etc/logrotate.d/blakestream-mpos

# Validate via dry-run so a typo doesn't ship.
say "validating with logrotate --debug"
if ! logrotate --debug /etc/logrotate.d/blakestream-mpos >/tmp/logrotate-debug.out 2>&1; then
    echo "logrotate validation failed:" >&2
    cat /tmp/logrotate-debug.out >&2
    exit 1
fi

# Truncate the two known-noisy logs that already exceed sane size,
# so we get the disk back without waiting for the first rotation
# tick. The systemd `copytruncate` will keep doing this thereafter.
for f in /var/log/blakestream-mpos/pool/mmp.log \
         /var/log/blakestream-mpos/pool/mergeminer.stderr; do
    if [ -f "$f" ] && [ "$(stat -c%s "$f")" -gt $((50*1024*1024)) ]; then
        say "truncating $(basename "$f") (was $(du -h "$f" | cut -f1))"
        : > "$f"
    fi
done

say "step 85 done — logrotate policy live"
