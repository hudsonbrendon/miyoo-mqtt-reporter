#!/bin/sh
# shellcheck shell=sh disable=SC1091

# build_state_payload <battery_dir> <meminfo_path> <loadavg_path>
# Echoes a compact JSON object combining all metrics.
# Missing values are emitted as null.
build_state_payload() {
    local bat_dir="$1"
    local mem_path="$2"
    local load_path="$3"

    local bat_raw
    local ram_raw
    local cpu_raw
    local vol_raw

    bat_raw="$(read_battery "$bat_dir")"      # "<pct>|<bool>" or empty
    ram_raw="$(read_ram "$mem_path")"         # "<pct>|<kb>"   or empty
    cpu_raw="$(read_cpu "$load_path")"        # "<load>|<n>"   or empty
    vol_raw="$(read_volume)"                  # "<pct>"        or empty

    local bat_pct
    local charging_bool
    local charging_str
    local ram_pct
    local cpu_load

    bat_pct="$(printf '%s' "$bat_raw" | awk -F'|' '{print $1}')"
    charging_bool="$(printf '%s' "$bat_raw" | awk -F'|' '{print $2}')"
    if [ "$charging_bool" = "true" ]; then
        charging_str="ON"
    else
        charging_str="OFF"
    fi

    ram_pct="$(printf '%s' "$ram_raw" | awk -F'|' '{print $1}')"
    cpu_load="$(printf '%s' "$cpu_raw" | awk -F'|' '{print $1}')"

    j_num() { [ -n "$1" ] && printf '%s' "$1" || printf 'null'; }

    printf '{"battery":%s,"charging":"%s","volume":%s,"ram":%s,"cpu":%s}' \
        "$(j_num "$bat_pct")" \
        "$charging_str" \
        "$(j_num "$vol_raw")" \
        "$(j_num "$ram_pct")" \
        "$(j_num "$cpu_load")"
}
