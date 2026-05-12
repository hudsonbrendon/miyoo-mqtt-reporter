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
