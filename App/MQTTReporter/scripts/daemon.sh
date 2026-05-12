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

# Resolved at runtime by daemon_main.
BAT_DIR=""
MEM_PATH="/proc/meminfo"
LOAD_PATH="/proc/loadavg"
PID_FILE=""
STOP=0

_resolve_battery_path() {
    if [ -n "${BATTERY_PATH:-}" ]; then
        BAT_DIR="$BATTERY_PATH"
    else
        BAT_DIR="$(detect_battery_path /sys/class/power_supply)"
    fi
    [ -n "$BAT_DIR" ] || log_warn "no battery sysfs path detected"
}

_signal_stop() { STOP=1; }

_publish_state() {
    local payload
    payload="$(build_state_payload "$BAT_DIR" "$MEM_PATH" "$LOAD_PATH")"
    if ! mqtt_publish "$(state_topic "$DEVICE_ID")" "$payload" 0 false; then
        log_warn "publish failed"
    fi
}

_publish_availability() {
    mqtt_publish "$(availability_topic "$DEVICE_ID")" "$1" 0 true || true
}

# daemon_main <config_path>
daemon_main() {
    local cfg="$1"
    load_config "$cfg" || return 1
    : "${INTERVAL:=30}"

    DEVICE_ID="$(device_id)"
    _resolve_battery_path

    PID_FILE="${PID_FILE:-/tmp/mqttreporter.pid}"
    echo $$ > "$PID_FILE"

    trap '_signal_stop' INT TERM HUP

    log_info "daemon starting device_id=$DEVICE_ID interval=${INTERVAL}s"
    publish_discovery
    _publish_availability "online"

    while [ "$STOP" -eq 0 ]; do
        _publish_state
        # Sleep in 1s slices so signals interrupt promptly.
        local i=0
        while [ "$i" -lt "$INTERVAL" ] && [ "$STOP" -eq 0 ]; do
            sleep 1
            i=$((i + 1))
        done
    done

    _publish_availability "offline"
    rm -f "$PID_FILE"
    log_info "daemon stopped"
}

# When executed directly, run daemon_main with default config.
if [ "${0##*/}" = "daemon.sh" ]; then
    APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
    PATH="$APP_DIR/bin:$PATH"
    LD_LIBRARY_PATH="$APP_DIR/lib:${LD_LIBRARY_PATH:-}"
    export PATH LD_LIBRARY_PATH
    # shellcheck disable=SC1091
    . "$APP_DIR/scripts/lib.sh"
    # shellcheck disable=SC1091
    . "$APP_DIR/scripts/collectors.sh"
    # shellcheck disable=SC1091
    . "$APP_DIR/scripts/discovery.sh"
    daemon_main "$APP_DIR/etc/mqtt.conf"
fi
