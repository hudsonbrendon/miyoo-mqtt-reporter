#!/bin/sh
# shellcheck shell=sh disable=SC1091

_j_num() { [ -n "$1" ] && printf '%s' "$1" || printf 'null'; }
_j_str() {
    if [ -z "$1" ]; then
        printf 'null'
    else
        # Escape backslashes and double quotes for valid JSON.
        printf '"%s"' "$(printf '%s' "$1" | sed -e 's|\\|\\\\|g' -e 's|"|\\"|g')"
    fi
}

# build_state_payload <battery_dir> <meminfo_path> <loadavg_path>
# Echoes a compact JSON object combining all metrics. Hardware-specific
# readers (read_*_miyoo) are wired by the executed-directly bootstrap so
# build_state_payload doesn't need to know whether it's running on the
# device or against fixtures.
build_state_payload() {
    local bat_dir="$1"
    local mem_path="$2"
    local load_path="$3"

    local bat_raw ram_raw cpu_raw vol_raw
    local uptime_v temp_v cpufreq_v sdfree_v
    local bright_v vbat_v ibat_v ip_v wifi_raw game_raw
    local load5 load15 swap_used kernel governor cpu_min cpu_max
    local thr_hi thr_lo wifi_mac wifi_br ntp theme mute csrc
    local mode bgm_vol hibernate_min lang hue sat ctr lum afix
    local blf bgm_mute autostart bat_warn cpuhk
    local pt_total pt_today most_played last_played gcount
    local onion_v cores mem_kb pcount rx tx wquality wfreq wbssid dns sscount sdpct
    local mem_cached mem_buffers disk_r disk_w apps_c emu_c themes_c saves_n saves_kb session_s

    bat_raw="$(read_battery "$bat_dir")"
    ram_raw="$(read_ram "$mem_path")"
    cpu_raw="$(read_cpu "$load_path")"
    vol_raw="$(read_volume)"

    uptime_v="$(read_uptime /proc/uptime 2>/dev/null)"
    temp_v="$(read_temperature /sys/class/thermal/thermal_zone0/temp 2>/dev/null)"
    cpufreq_v="$(read_cpu_freq /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null)"
    sdfree_v="$(read_sd_free /mnt/SDCARD 2>/dev/null)"

    load5="$(read_load_avg /proc/loadavg 2 2>/dev/null)"
    load15="$(read_load_avg /proc/loadavg 3 2>/dev/null)"
    swap_used="$(read_swap_used /proc/meminfo 2>/dev/null)"
    kernel="$(uname -r 2>/dev/null)"
    governor="$(read_first_line /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)"
    cpu_min="$(read_cpu_freq_khz_to_mhz /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq 2>/dev/null)"
    cpu_max="$(read_cpu_freq_khz_to_mhz /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>/dev/null)"
    thr_hi="$(read_first_line /sys/devices/system/cpu/cpufreq/temp_adjust_threshold_hi 2>/dev/null)"
    thr_lo="$(read_first_line /sys/devices/system/cpu/cpufreq/temp_adjust_threshold_lo 2>/dev/null)"
    wifi_mac="$(read_first_line /sys/class/net/wlan0/address 2>/dev/null)"
    cores="$(read_cpu_cores 2>/dev/null)"
    mem_kb="$(read_mem_total "$mem_path" 2>/dev/null)"
    pcount="$(read_process_count 2>/dev/null)"
    rx="$(read_wifi_rx_bytes 2>/dev/null)"
    tx="$(read_wifi_tx_bytes 2>/dev/null)"
    wquality="$(read_wifi_quality 2>/dev/null)"
    dns="$(read_dns_server 2>/dev/null)"
    mem_cached="$(read_meminfo_field "$mem_path" Cached 2>/dev/null)"
    mem_buffers="$(read_meminfo_field "$mem_path" Buffers 2>/dev/null)"
    disk_r="$(read_disk_read_sectors 2>/dev/null)"
    disk_w="$(read_disk_write_sectors 2>/dev/null)"

    # Miyoo-only readers are no-ops on the dev host (commands absent).
    if command -v read_brightness_miyoo >/dev/null 2>&1; then
        bright_v="$(read_brightness_miyoo 2>/dev/null)"
        vbat_v="$(read_battery_voltage_miyoo 2>/dev/null)"
        ibat_v="$(read_battery_current_miyoo 2>/dev/null)"
        ip_v="$(read_ip_miyoo 2>/dev/null)"
        wifi_raw="$(read_wifi_link_miyoo 2>/dev/null)"
        game_raw="$(read_running_game_miyoo 2>/dev/null)"
        wifi_br="$(read_wifi_bitrate_miyoo 2>/dev/null)"
        ntp="$(read_ntp_synced_miyoo 2>/dev/null)"
        theme="$(read_theme_miyoo 2>/dev/null)"
        mute="$(read_mute_miyoo 2>/dev/null)"
        csrc="$(read_charging_source_miyoo 2>/dev/null)"
        mode="$(detect_current_mode_miyoo 2>/dev/null)"
        bgm_vol="$(read_bgm_volume_miyoo 2>/dev/null)"
        hibernate_min="$(read_system_int_miyoo hibernate 2>/dev/null)"
        lang="$(read_system_str_miyoo language 2>/dev/null)"
        hue="$(read_system_int_miyoo hue 2>/dev/null)"
        sat="$(read_system_int_miyoo saturation 2>/dev/null)"
        ctr="$(read_system_int_miyoo contrast 2>/dev/null)"
        lum="$(read_system_int_miyoo lumination 2>/dev/null)"
        afix="$(read_system_int_miyoo audiofix 2>/dev/null)"
        blf="$(read_blue_light_miyoo 2>/dev/null)"
        bgm_mute="$(read_bgm_mute_miyoo 2>/dev/null)"
        autostart="$(read_autostart_enabled_miyoo 2>/dev/null)"
        bat_warn="$(read_battery_warning_enabled_miyoo 2>/dev/null)"
        cpuhk="$(read_cpuclock_hotkey_miyoo 2>/dev/null)"
        pt_total="$(read_playtime_total_miyoo 2>/dev/null)"
        pt_today="$(read_playtime_today_miyoo 2>/dev/null)"
        most_played="$(read_most_played_miyoo 2>/dev/null)"
        last_played="$(read_last_played_miyoo 2>/dev/null)"
        gcount="$(read_game_count_miyoo 2>/dev/null)"
        onion_v="$(read_onion_version_miyoo 2>/dev/null)"
        wfreq="$(read_wifi_freq_miyoo 2>/dev/null)"
        wbssid="$(read_wifi_bssid_miyoo 2>/dev/null)"
        sscount="$(read_save_state_count_miyoo 2>/dev/null)"
        sdpct="$(read_sd_usage_pct_miyoo 2>/dev/null)"
        apps_c="$(read_apps_count_miyoo 2>/dev/null)"
        emu_c="$(read_emulators_count_miyoo 2>/dev/null)"
        themes_c="$(read_themes_count_miyoo 2>/dev/null)"
        saves_n="$(read_saves_count_miyoo 2>/dev/null)"
        saves_kb="$(read_saves_size_kb_miyoo 2>/dev/null)"
        session_s="$(read_session_duration_miyoo 2>/dev/null)"
    fi

    local bat_pct charging_bool charging_str ram_pct cpu_load
    local rssi ssid core game

    bat_pct="$(printf '%s' "$bat_raw" | awk -F'|' '{print $1}')"
    charging_bool="$(printf '%s' "$bat_raw" | awk -F'|' '{print $2}')"
    if [ "$charging_bool" = "true" ]; then charging_str="ON"; else charging_str="OFF"; fi
    ram_pct="$(printf '%s' "$ram_raw" | awk -F'|' '{print $1}')"
    cpu_load="$(printf '%s' "$cpu_raw" | awk -F'|' '{print $1}')"
    rssi="$(printf '%s' "$wifi_raw" | awk -F'|' '{print $1}')"
    ssid="$(printf '%s' "$wifi_raw" | awk -F'|' '{print $2}')"
    core="$(printf '%s' "$game_raw" | awk -F'|' '{print $1}')"
    game="$(printf '%s' "$game_raw" | awk -F'|' '{print $2}')"

    printf '{'
    printf '"battery":%s,'    "$(_j_num "$bat_pct")"
    printf '"charging":"%s",' "$charging_str"
    printf '"volume":%s,'     "$(_j_num "$vol_raw")"
    printf '"ram":%s,'        "$(_j_num "$ram_pct")"
    printf '"cpu":%s,'        "$(_j_num "$cpu_load")"
    printf '"uptime":%s,'     "$(_j_num "$uptime_v")"
    printf '"temperature":%s,' "$(_j_num "$temp_v")"
    printf '"cpu_freq":%s,'   "$(_j_num "$cpufreq_v")"
    printf '"sd_free":%s,'    "$(_j_num "$sdfree_v")"
    printf '"brightness":%s,' "$(_j_num "$bright_v")"
    printf '"vbat":%s,'       "$(_j_num "$vbat_v")"
    printf '"ibat":%s,'       "$(_j_num "$ibat_v")"
    printf '"wifi_rssi":%s,'  "$(_j_num "$rssi")"
    printf '"wifi_ssid":%s,'  "$(_j_str "$ssid")"
    printf '"ip":%s,'         "$(_j_str "$ip_v")"
    printf '"core":%s,'       "$(_j_str "$core")"
    printf '"game":%s,'       "$(_j_str "$game")"
    printf '"cpu_load5":%s,'  "$(_j_num "$load5")"
    printf '"cpu_load15":%s,' "$(_j_num "$load15")"
    printf '"swap_used":%s,'  "$(_j_num "$swap_used")"
    printf '"kernel":%s,'     "$(_j_str "$kernel")"
    printf '"cpu_governor":%s,' "$(_j_str "$governor")"
    printf '"cpu_min_freq":%s,' "$(_j_num "$cpu_min")"
    printf '"cpu_max_freq":%s,' "$(_j_num "$cpu_max")"
    printf '"temp_throttle_hi":%s,' "$(_j_num "$thr_hi")"
    printf '"temp_throttle_lo":%s,' "$(_j_num "$thr_lo")"
    printf '"wifi_mac":%s,'   "$(_j_str "$wifi_mac")"
    printf '"wifi_bitrate":%s,' "$(_j_num "$wifi_br")"
    printf '"ntp_synced":"%s",' "${ntp:-OFF}"
    printf '"theme":%s,'      "$(_j_str "$theme")"
    printf '"mute":"%s",'     "${mute:-OFF}"
    printf '"charging_source":%s,' "$(_j_str "$csrc")"
    printf '"mode":%s,'       "$(_j_str "$mode")"
    printf '"bgm_volume":%s,' "$(_j_num "$bgm_vol")"
    printf '"hibernate_min":%s,' "$(_j_num "$hibernate_min")"
    printf '"language":%s,'   "$(_j_str "$lang")"
    printf '"hue":%s,'        "$(_j_num "$hue")"
    printf '"saturation":%s,' "$(_j_num "$sat")"
    printf '"contrast":%s,'   "$(_j_num "$ctr")"
    printf '"lumination":%s,' "$(_j_num "$lum")"
    printf '"audiofix":%s,'   "$(_j_num "$afix")"
    printf '"blue_light":"%s",' "${blf:-OFF}"
    printf '"bgm_mute":"%s",' "${bgm_mute:-OFF}"
    printf '"autostart":"%s",' "${autostart:-OFF}"
    printf '"battery_warning":"%s",' "${bat_warn:-OFF}"
    printf '"cpuclock_hotkey":"%s",' "${cpuhk:-OFF}"
    printf '"playtime_total_hours":%s,' "$(_j_num "$pt_total")"
    printf '"playtime_today_min":%s,'   "$(_j_num "$pt_today")"
    printf '"most_played":%s,' "$(_j_str "$most_played")"
    printf '"last_played":%s,' "$(_j_str "$last_played")"
    printf '"game_count":%s,' "$(_j_num "$gcount")"
    printf '"onion_version":%s,' "$(_j_str "$onion_v")"
    printf '"cpu_cores":%s,'  "$(_j_num "$cores")"
    printf '"mem_total_kb":%s,' "$(_j_num "$mem_kb")"
    printf '"process_count":%s,' "$(_j_num "$pcount")"
    printf '"wifi_rx_bytes":%s,' "$(_j_num "$rx")"
    printf '"wifi_tx_bytes":%s,' "$(_j_num "$tx")"
    printf '"wifi_quality":%s,' "$(_j_num "$wquality")"
    printf '"wifi_freq":%s,'  "$(_j_num "$wfreq")"
    printf '"wifi_bssid":%s,' "$(_j_str "$wbssid")"
    printf '"dns_server":%s,' "$(_j_str "$dns")"
    printf '"save_state_count":%s,' "$(_j_num "$sscount")"
    printf '"sd_usage_pct":%s,' "$(_j_num "$sdpct")"
    printf '"mem_cached_kb":%s,' "$(_j_num "$mem_cached")"
    printf '"mem_buffers_kb":%s,' "$(_j_num "$mem_buffers")"
    printf '"disk_read_sectors":%s,' "$(_j_num "$disk_r")"
    printf '"disk_write_sectors":%s,' "$(_j_num "$disk_w")"
    printf '"apps_count":%s,' "$(_j_num "$apps_c")"
    printf '"emulators_count":%s,' "$(_j_num "$emu_c")"
    printf '"themes_count":%s,' "$(_j_num "$themes_c")"
    printf '"saves_count":%s,' "$(_j_num "$saves_n")"
    printf '"saves_size_kb":%s,' "$(_j_num "$saves_kb")"
    printf '"session_duration_sec":%s' "$(_j_num "$session_s")"
    printf '}'
}

# Resolved at runtime by daemon_main.
BAT_DIR=""
MEM_PATH="/proc/meminfo"
LOAD_PATH="/proc/loadavg"
PID_FILE=""
STOP=0
STATUS_DIR="/tmp/mqttreporter"
STATUS_FILE="$STATUS_DIR/status.json"
# Roughly mirrors the count emitted by publish_discovery + state payload.
ENTITY_COUNT=73

_my_ip() {
    ip route get 1 2>/dev/null | awk '{ for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit} }'
}

# _write_runtime_status <broker_ok:true|false> <last_error_string_or_empty>
_write_runtime_status() {
    local ok="$1"
    local err="$2"
    local now ip
    now=$(date +%s 2>/dev/null)
    ip=$(_my_ip)
    mkdir -p "$STATUS_DIR" 2>/dev/null || true
    {
        printf '{'
        printf '"broker_ok":%s,'           "$ok"
        printf '"last_publish_epoch":%s,'  "${now:-null}"
        if [ -z "$err" ]; then
            printf '"last_error":null,'
        else
            printf '"last_error":"%s",' "$(printf '%s' "$err" | sed -e 's|\\|\\\\|g' -e 's|"|\\"|g')"
        fi
        printf '"entity_count":%s,'       "$ENTITY_COUNT"
        printf '"device_id":"%s",'        "${DEVICE_ID:-}"
        if [ -z "$ip" ]; then
            printf '"ip":null'
        else
            printf '"ip":"%s"' "$ip"
        fi
        printf '}'
    } > "$STATUS_FILE.tmp" 2>/dev/null && mv -f "$STATUS_FILE.tmp" "$STATUS_FILE" 2>/dev/null
}

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
    if mqtt_publish "$(state_topic "$DEVICE_ID")" "$payload" 0 false; then
        _write_runtime_status true ""
    else
        log_warn "publish failed"
        _write_runtime_status false "publish failed"
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

    # Per-entity opt-in: $APP_DIR/etc/entities.conf. Missing file = all enabled.
    load_enabled_entities "$(dirname "$cfg")/entities.conf"

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
    # Miyoo overrides: detect platform-specific data sources at runtime.
    if [ -r /tmp/percBat ]; then
        read_battery() { read_battery_miyoo; }
    fi
    if [ -r /sys/devices/system/cpu/cpufreq/temp_out ]; then
        # shellcheck disable=SC2317
        read_temperature() { read_temperature_miyoo; }
    fi
    if ls /mnt/SDCARD/.tmp_update/config/system/*.json >/dev/null 2>&1; then
        read_volume() { read_volume_miyoo; }
    fi
    daemon_main "$APP_DIR/etc/mqtt.conf"
fi
