#!/usr/bin/env bash
# 11-configure-swap.sh - show swap status and optionally create / resize swap.
# Runs on the VPS as root before daemon source builds and bootstrap import.
set -euo pipefail

say() { printf '\033[1;33m   %s\033[0m\n' "$*"; }
warn() { printf '\033[1;31m   %s\033[0m\n' "$*" >&2; }

detect_existing_swapfile() {
    local path
    path="$(swapon --show --noheadings --output NAME,TYPE 2>/dev/null \
        | awk '$2 == "file" {print $1; exit}')"
    if [ -z "$path" ]; then
        path="$(awk '$1 !~ /^#/ && $3 == "swap" && $1 ~ /^\// {print $1; exit}' /etc/fstab 2>/dev/null || true)"
    fi
    printf '%s\n' "${path:-/swapfile}"
}

SWAP_FILE="${MPOS_SWAP_FILE:-$(detect_existing_swapfile)}"
SWAP_ACTION="${MPOS_SWAP_ACTION:-prompt}" # prompt, auto, skip
SWAP_SIZE_MB="${MPOS_SWAP_SIZE_MB:-}"
PROMPT_TIMEOUT_S="${MPOS_SWAP_PROMPT_TIMEOUT_S:-120}"
DISK_RESERVE_MB="${MPOS_SWAP_DISK_RESERVE_MB:-4096}"
SWAP_SIZE_TOLERANCE_MB="${MPOS_SWAP_SIZE_TOLERANCE_MB:-64}"
KNOWN_SWAP_FILES="/swapfile /swap.img /blake_swap.img"

human_mb() {
    awk -v mb="${1:-0}" 'BEGIN {
        if (mb >= 1024) printf "%.1f GiB", mb / 1024;
        else printf "%d MiB", mb;
    }'
}

mb_from_gb() {
    awk -v gb="$1" 'BEGIN { printf "%d", gb * 1024 }'
}

mem_total_mb() {
    awk '/^MemTotal:/ {print int($2 / 1024)}' /proc/meminfo
}

swap_total_mb() {
    awk '/^SwapTotal:/ {print int($2 / 1024)}' /proc/meminfo
}

swap_used_mb() {
    awk '/^SwapTotal:/ {t=$2} /^SwapFree:/ {f=$2} END {print int((t - f) / 1024)}' /proc/meminfo
}

root_free_mb() {
    df -Pm / | awk 'NR == 2 {print $4}'
}

cpu_cores() {
    nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1
}

load_1m() {
    awk '{print $1}' /proc/loadavg 2>/dev/null || echo "0.00"
}

recommended_swap_mb() {
    local ram_mb="$1"
    # The full 25.2 mainnet pool runs six wallet daemons. ELT can spike
    # during block-index reload even after bootstrap import, so 16 GiB
    # VPSes need more than the distro default 4 GiB swap.
    if [ "$ram_mb" -lt 24576 ]; then
        echo 12288
    elif [ "$ram_mb" -lt 65536 ]; then
        echo 8192
    else
        echo 4096
    fi
}

active_swapfile_mb() {
    swapon --show --bytes --noheadings 2>/dev/null \
        | awk -v path="$SWAP_FILE" '
            $1 == path {
                for (i = 2; i <= NF; i++) {
                    if ($i ~ /^[0-9]+$/) {
                        print int($i / 1048576)
                        found = 1
                        exit
                    }
                }
            }
            END {if (!found) print 0}
        '
}

fstab_add_swapfile() {
    local tmp
    tmp="$(mktemp)"
    awk -v path="$SWAP_FILE" -v known="$KNOWN_SWAP_FILES" '
        BEGIN {
            split(known, files, " ")
            for (i in files) drop[files[i]] = 1
            drop[path] = 1
        }
        $1 in drop { next }
        { print }
    ' /etc/fstab > "$tmp"
    cat "$tmp" > /etc/fstab
    rm -f "$tmp"
    if ! awk -v path="$SWAP_FILE" '$1 == path && $3 == "swap" {found=1} END {exit found ? 0 : 1}' /etc/fstab; then
        printf '%s none swap sw 0 0\n' "$SWAP_FILE" >> /etc/fstab
    fi
}

configure_sysctl() {
    cat > /etc/sysctl.d/99-swappiness.conf <<SYSCTL
# Managed by Blakestream-MPOS deploy.
vm.swappiness=10
SYSCTL
    cat > /etc/sysctl.d/99-blakestream-mpos-swap.conf <<SYSCTL
# Managed by Blakestream-MPOS deploy.
vm.vfs_cache_pressure=50
SYSCTL
    sysctl --system >/dev/null 2>&1 || {
        sysctl -q -w vm.swappiness=10 >/dev/null || true
        sysctl -q -w vm.vfs_cache_pressure=50 >/dev/null || true
    }
}

create_swapfile() {
    local size_mb="$1" path type old

    if swapon --show --noheadings --output NAME 2>/dev/null | awk -v path="$SWAP_FILE" '$1 == path {found=1} END {exit !found}'; then
        say "turning off existing ${SWAP_FILE}"
        swapoff "$SWAP_FILE"
    fi

    while read -r path type; do
        [ -n "$path" ] || continue
        [ "$type" = "file" ] || continue
        [ "$path" != "$SWAP_FILE" ] || continue
        for old in $KNOWN_SWAP_FILES; do
            if [ "$path" = "$old" ]; then
                say "removing duplicate swap file ${path}"
                swapoff "$path" 2>/dev/null || true
                rm -f "$path"
                break
            fi
        done
    done < <(swapon --show --noheadings --output NAME,TYPE 2>/dev/null || true)

    rm -f "$SWAP_FILE"
    say "creating ${SWAP_FILE} ($(human_mb "$size_mb"))"
    if ! fallocate -l "${size_mb}M" "$SWAP_FILE" 2>/dev/null; then
        dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$size_mb" status=progress
    fi
    chmod 0600 "$SWAP_FILE"
    mkswap "$SWAP_FILE" >/dev/null
    swapon "$SWAP_FILE"
    fstab_add_swapfile
    configure_sysctl
}

clear_screen() {
    if [ -t 1 ]; then
        printf '\033[H\033[2J'
    fi
}

can_use_tty_ui() {
    [ -t 0 ] && [ -w /dev/tty ]
}

BOX_WIDTH=78
box_fill() {
    local char="$1" count="$2"
    printf '%*s' "$count" '' | tr ' ' "$char"
}

box_rule() {
    box_fill '=' "$BOX_WIDTH"
    printf '\n'
}

box_row() {
    local text="${1:-}"
    local inner=$((BOX_WIDTH - 4))
    if [ "${#text}" -gt "$inner" ]; then
        text="${text:0:$inner}"
    fi
    printf '= %-*s =\n' "$inner" "$text"
}

box_center() {
    local text="$1"
    local inner=$((BOX_WIDTH - 4))
    local left=$(((inner - ${#text}) / 2))
    local right=$((inner - left - ${#text}))
    if [ "$left" -lt 0 ]; then
        box_row "$text"
        return
    fi
    printf '= %*s%s%*s =\n' "$left" '' "$text" "$right" ''
}

box_choice() {
    local selected="$1" label="$2" mark=" "
    if [ "$selected" = "1" ]; then
        mark="*"
    fi
    box_row "  [${mark}] ${label}"
}

print_swap_panel() {
    local selected="${1:-0}"
    local cpu_label disk_label swap_label ram_label recommended_label

    cpu_label="$(cpu_cores)c L1:$(load_1m)"
    ram_label="$(human_mb "$RAM_MB")"
    disk_label="$(human_mb "$ROOT_FREE_MB") free"
    swap_label="$(human_mb "$CURRENT_SWAP_MB")"
    recommended_label="$(human_mb "$RECOMMENDED_MB")"

    box_rule
    box_center "MPOS 25.2-GO"
    box_rule
    box_row "CPU:${cpu_label}   RAM:${ram_label}   DISK:${disk_label}   SWAP:${swap_label}"
    box_rule
    box_center "Swap Creation"
    box_row ""
    box_row "Recommended swap size: ${recommended_label}"
    box_row "Swap file            : ${SWAP_FILE}"
    box_row ""
    box_rule
    box_choice "$([ "$selected" -eq 0 ] && echo 1 || echo 0)" "Use recommended swap size (${recommended_label})"
    box_choice "$([ "$selected" -eq 1 ] && echo 1 || echo 0)" "Use custom swap size"
    box_choice "$([ "$selected" -eq 2 ] && echo 1 || echo 0)" "Leave swap unchanged"
    box_row ""
    box_row "Use Up/Down arrows, Enter to select, q to leave unchanged."
    box_rule
}

print_custom_panel() {
    local max_gb="$1" message="${2:-}"
    local recommended_label
    recommended_label="$(human_mb "$RECOMMENDED_MB")"

    box_rule
    box_center "MPOS 25.2-GO"
    box_rule
    box_center "Custom Swap Size"
    box_row ""
    box_row "Enter a plain size in GB. Example: 12 creates 12288 MiB."
    box_row "Recommended swap size: ${recommended_label}"
    box_row "Maximum with disk reserve: ${max_gb} GiB"
    if [ -n "$message" ]; then
        box_row ""
        box_row "$message"
    fi
    box_row ""
    box_rule
}

read_key() {
    local key rest
    IFS= read -rsn1 key
    if [ "$key" = $'\033' ]; then
        IFS= read -rsn2 -t 0.1 rest || true
        key="${key}${rest}"
    fi
    printf '%s' "$key"
}

read_custom_swap_mb() {
    local input clean custom_mb max_gb message
    CUSTOM_SWAP_MB=0
    message=""

    max_gb="$(awk -v mb="$MAX_SAFE_MB" 'BEGIN { printf "%.1f", mb / 1024 }')"
    while true; do
        clear_screen
        print_custom_panel "$max_gb" "$message"
        printf 'Custom swap size in GB: '
        IFS= read -r input
        clean="$(printf '%s' "$input" | tr -d '[:space:]')"
        clean="${clean%GB}"
        clean="${clean%gb}"
        clean="${clean%G}"
        clean="${clean%g}"
        if ! [[ "$clean" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
            message="Enter a plain number like 12."
            continue
        fi
        custom_mb="$(mb_from_gb "$clean")"
        if [ "$custom_mb" -lt 1024 ]; then
            message="Swap size must be at least 1 GB."
            continue
        fi
        if [ "$custom_mb" -gt "$MAX_SAFE_MB" ]; then
            message="$(human_mb "$custom_mb") is too large for available disk reserve."
            continue
        fi
        CUSTOM_SWAP_MB="$custom_mb"
        return 0
    done
}

select_swap_action() {
    local selected=0 key option_count=3
    SELECTED_SWAP_MB=0

    while true; do
        clear_screen
        print_swap_panel "$selected"

        key="$(read_key)"
        case "$key" in
            $'\033[A')
                if [ "$selected" -le 0 ]; then
                    selected=$((option_count - 1))
                else
                    selected=$((selected - 1))
                fi
                ;;
            $'\033[B')
                selected=$(((selected + 1) % option_count))
                ;;
            "")
                case "$selected" in
                    0) SELECTED_SWAP_MB="$RECOMMENDED_MB"; return 0 ;;
                    1)
                        read_custom_swap_mb
                        SELECTED_SWAP_MB="$CUSTOM_SWAP_MB"
                        return 0
                        ;;
                    2) SELECTED_SWAP_MB=0; return 0 ;;
                esac
                ;;
            q|Q)
                SELECTED_SWAP_MB=0
                return 0
                ;;
        esac
    done
}

print_plain_swap_status() {
    say "swap status"
    printf '      RAM:           %s\n' "$(human_mb "$RAM_MB")"
    printf '      current swap:  %s total, %s used\n' "$(human_mb "$CURRENT_SWAP_MB")" "$(human_mb "$CURRENT_SWAP_USED_MB")"
    printf '      root free:     %s\n' "$(human_mb "$ROOT_FREE_MB")"
    if swapon --show --output NAME,TYPE,SIZE,USED,PRIO | grep -q .; then
        swapon --show --output NAME,TYPE,SIZE,USED,PRIO | sed 's/^/      /'
    else
        printf '      no active swap devices\n'
    fi
    printf '      recommended:   %s at %s\n' "$(human_mb "$RECOMMENDED_MB")" "$SWAP_FILE"
}

case "$SWAP_ACTION" in
    prompt|auto|skip) ;;
    *) warn "invalid MPOS_SWAP_ACTION=${SWAP_ACTION}; expected prompt, auto, or skip"; exit 1 ;;
esac

if [ -n "$SWAP_SIZE_MB" ] && ! [[ "$SWAP_SIZE_MB" =~ ^[1-9][0-9]{2,5}$ ]]; then
    warn "invalid MPOS_SWAP_SIZE_MB=${SWAP_SIZE_MB}; expected MiB"
    exit 1
fi

RAM_MB="$(mem_total_mb)"
CURRENT_SWAP_MB="$(swap_total_mb)"
CURRENT_SWAP_USED_MB="$(swap_used_mb)"
ROOT_FREE_MB="$(root_free_mb)"
RECOMMENDED_MB="${SWAP_SIZE_MB:-$(recommended_swap_mb "$RAM_MB")}"
MAX_SAFE_MB=$((ROOT_FREE_MB - DISK_RESERVE_MB))
if [ "$MAX_SAFE_MB" -lt 0 ]; then
    MAX_SAFE_MB=0
fi
if [ "$RECOMMENDED_MB" -gt "$MAX_SAFE_MB" ]; then
    warn "recommended swap $(human_mb "$RECOMMENDED_MB") exceeds root free disk reserve"
    warn "capping recommendation to $(human_mb "$MAX_SAFE_MB") to leave $(human_mb "$DISK_RESERVE_MB") free"
    RECOMMENDED_MB="$MAX_SAFE_MB"
fi

if [ "$SWAP_ACTION" != "prompt" ] || ! can_use_tty_ui; then
    print_plain_swap_status
fi

if [ "$RECOMMENDED_MB" -lt 1024 ]; then
    warn "not enough root disk free for a useful swapfile; skipping swap configuration"
    configure_sysctl
    exit 0
fi

configure_sysctl

ACTIVE_FILE_MB="$(active_swapfile_mb)"
if [ $((CURRENT_SWAP_MB + SWAP_SIZE_TOLERANCE_MB)) -ge "$RECOMMENDED_MB" ] \
    && [ $((ACTIVE_FILE_MB + SWAP_SIZE_TOLERANCE_MB)) -ge "$RECOMMENDED_MB" ]; then
    say "existing ${SWAP_FILE} is already at or above recommendation"
    configure_sysctl
    exit 0
fi

TARGET_SWAP_MB=0
case "$SWAP_ACTION" in
    skip)
        say "MPOS_SWAP_ACTION=skip - leaving swap unchanged"
        exit 0
        ;;
    auto)
        TARGET_SWAP_MB="$RECOMMENDED_MB"
        ;;
    prompt)
        if can_use_tty_ui; then
            select_swap_action > /dev/tty
            TARGET_SWAP_MB="$SELECTED_SWAP_MB"
        else
            printf '      create or resize %s to %s? [y/N]: ' "$SWAP_FILE" "$(human_mb "$RECOMMENDED_MB")"
            if IFS= read -r -t "$PROMPT_TIMEOUT_S" reply; then
                case "$reply" in
                    y|Y|yes|YES|Yes) TARGET_SWAP_MB="$RECOMMENDED_MB" ;;
                    *) TARGET_SWAP_MB=0 ;;
                esac
            else
                printf '\n'
                say "no swap choice received within ${PROMPT_TIMEOUT_S}s; leaving swap unchanged"
                TARGET_SWAP_MB=0
            fi
        fi
        ;;
esac

if [ "$TARGET_SWAP_MB" -lt 1024 ]; then
    say "leaving swap unchanged"
    exit 0
fi

if [ "$CURRENT_SWAP_USED_MB" -gt 0 ] && [ "$ACTIVE_FILE_MB" -gt 0 ] && [ "$TARGET_SWAP_MB" -gt "$ACTIVE_FILE_MB" ]; then
    warn "${SWAP_FILE} has $(human_mb "$CURRENT_SWAP_USED_MB") in use; not resizing live swap"
    warn "rerun before daemon startup or set MPOS_SWAP_SIZE_MB explicitly on a fresh deploy"
    exit 0
fi

create_swapfile "$TARGET_SWAP_MB"
say "swap configured"
swapon --show --output NAME,TYPE,SIZE,USED,PRIO | sed 's/^/      /'
