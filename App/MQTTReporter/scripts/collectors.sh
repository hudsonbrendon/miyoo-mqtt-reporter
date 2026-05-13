#!/bin/sh
# shellcheck shell=sh

# read_battery <sysfs_dir>
# Echoes "<capacity_percent>|<charging_bool>". Empty on failure.
read_battery() {
    local dir="$1"
    local cap_file="$dir/capacity"
    local sta_file="$dir/status"
    [ -r "$cap_file" ] && [ -r "$sta_file" ] || return 0
    local cap
    local sta
    local charging
    cap="$(cat "$cap_file")"
    sta="$(cat "$sta_file")"
    case "$sta" in
        Charging|Full) charging=true ;;
        *)             charging=false ;;
    esac
    printf '%s|%s' "$cap" "$charging"
}

# parse_volume_from
# Reads `amixer sget Master`-style output from stdin, echoes integer percent.
parse_volume_from() {
    # Lines look like:  "  Mono: Playback 73 [73%] [on]"
    # Capture first NN% after a bracket.
    sed -n 's/.*\[\([0-9]\{1,3\}\)%\].*/\1/p' | head -n1
}

# read_volume
# Returns current Master volume as integer percent, empty on failure.
read_volume() {
    if command -v amixer >/dev/null 2>&1; then
        amixer sget Master 2>/dev/null | parse_volume_from
    fi
}

# read_ram <meminfo_path>
# Echoes "<used_percent>|<available_kb>".
read_ram() {
    local f="$1"
    [ -r "$f" ] || return 0
    local total
    local avail
    local used_pct
    total="$(awk '/^MemTotal:/     { print $2; exit }' "$f")"
    avail="$(awk '/^MemAvailable:/ { print $2; exit }' "$f")"
    [ -n "$total" ] && [ -n "$avail" ] || return 0
    # Truncate used%
    used_pct="$(awk -v t="$total" -v a="$avail" \
        'BEGIN { printf "%d", (t-a)*100/t }')"
    printf '%s|%s' "$used_pct" "$avail"
}

# detect_battery_path <power_supply_root>
# Echoes path to first subdir whose `type` is "Battery", or empty.
detect_battery_path() {
    local root="$1"
    [ -d "$root" ] || return 0
    local d
    for d in "$root"/*; do
        [ -d "$d" ] || continue
        if [ -r "$d/type" ] && [ "$(cat "$d/type")" = "Battery" ]; then
            printf '%s' "$d"
            return 0
        fi
    done
}

# read_cpu <loadavg_path>
# Echoes "<load1>|<procs_running>".
read_cpu() {
    local f="$1"
    [ -r "$f" ] || return 0
    awk '{
        split($4, a, "/")
        printf "%s|%s", $1, a[1]
    }' "$f"
}

# read_battery_miyoo
# Miyoo Mini Plus has no /sys/class/power_supply. Onion's batmon writes
# /tmp/percBat; charging is bit 0x4 of axp register 0.
read_battery_miyoo() {
    [ -r /tmp/percBat ] || return 0
    local cap
    cap="$(cat /tmp/percBat)"
    [ -n "$cap" ] || return 0
    local charging=false
    if command -v axp >/dev/null 2>&1; then
        local reg0
        reg0="$(axp 0 2>/dev/null | sed -n 's/.*read value:\([0-9a-fA-F][0-9a-fA-F]*\).*/\1/p')"
        if [ -n "$reg0" ]; then
            if [ $((0x${reg0} & 4)) -eq 4 ]; then
                charging=true
            fi
        fi
    fi
    printf '%s|%s' "$cap" "$charging"
}

# read_volume_miyoo
# Prefers /tmp/live_vol (real-time from vol-watcher.sh), falls back to
# Onion's config/system/<uuid>.json (only persisted on power-off / menu nav).
# Scale 0-20 → 0-100. mute=1 forces 0 (read from system.json, stale).
read_volume_miyoo() {
    local cfg mute vol
    # Mute is only available from the (stale) system.json — accept that.
    for cfg in /mnt/SDCARD/.tmp_update/config/system/*.json; do
        [ -r "$cfg" ] || continue
        mute="$(sed -n 's/.*"mute":[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$cfg" | head -1)"
        break
    done
    if [ "$mute" = "1" ]; then
        printf '0'
        return 0
    fi
    if [ -r /tmp/live_vol ]; then
        vol="$(cat /tmp/live_vol)"
        [ -n "$vol" ] || return 0
        printf '%d' $((vol * 5))
        return 0
    fi
    for cfg in /mnt/SDCARD/.tmp_update/config/system/*.json; do
        [ -r "$cfg" ] || continue
        vol="$(sed -n 's/.*"vol":[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$cfg" | head -1)"
        [ -n "$vol" ] || return 0
        printf '%d' $((vol * 5))
        return 0
    done
}
