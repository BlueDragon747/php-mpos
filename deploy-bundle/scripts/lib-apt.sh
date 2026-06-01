#!/usr/bin/env bash
# Helpers for deploy steps that touch apt/dpkg.

wait_for_apt_locks() {
    local waited=0
    local max_wait="${APT_LOCK_MAX_WAIT_SECONDS:-900}"
    local locks=(
        /var/lib/dpkg/lock-frontend
        /var/lib/dpkg/lock
        /var/cache/apt/archives/lock
        /var/lib/apt/lists/lock
    )

    while true; do
        local busy=0
        if command -v fuser >/dev/null 2>&1; then
            for lock in "${locks[@]}"; do
                if [ -e "$lock" ] && fuser "$lock" >/dev/null 2>&1; then
                    busy=1
                    break
                fi
            done
        elif pgrep -f 'apt.systemd.daily|unattended-upgrade|apt-get|/usr/bin/dpkg' >/dev/null 2>&1; then
            busy=1
        fi

        [ "$busy" = "0" ] && return 0
        if [ "$waited" -ge "$max_wait" ]; then
            echo "ERROR: apt/dpkg lock still held after ${max_wait}s" >&2
            return 1
        fi
        say "waiting for apt/dpkg lock (${waited}s/${max_wait}s)"
        sleep 5
        waited=$((waited + 5))
    done
}
