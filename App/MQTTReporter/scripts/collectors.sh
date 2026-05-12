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
