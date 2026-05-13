#!/bin/sh
# shellcheck shell=sh disable=SC1090,SC1091,SC2034,SC2154,SC2329
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DISC="$SCRIPT_DIR/../App/MQTTReporter/scripts/discovery.sh"

testDeviceIdRespectsExplicitOverride() {
    . "$DISC"
    DEVICE_ID="manual-id"
    assertEquals "manual-id" "$(device_id)"
    unset DEVICE_ID
}

testDeviceIdSanitizesMac() {
    . "$DISC"
    # Stub `cat` for /sys/class/net/wlan0/address by exporting fake reader.
    NET_ADDR_READER='printf aa:bb:cc:dd:ee:ff' \
        out="$(device_id)"
    assertEquals "miyoo-aabbccddeeff" "$out"
}

testDeviceIdFallsBackWhenNoMac() {
    . "$DISC"
    NET_ADDR_READER='exit 1' out="$(device_id)"
    assertEquals "miyoominiplus" "$out"
}

testPublishDiscoveryEmitsAllRetainedConfigs() {
    LIB="$SCRIPT_DIR/../App/MQTTReporter/scripts/lib.sh"
    . "$LIB"
    . "$DISC"

    PUB_LOG="$(mktemp)"
    mqtt_publish() {
        printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "$PUB_LOG"
    }

    export DEVICE_ID="miyoo-test"
    publish_discovery
    unset DEVICE_ID

    cnt="$(wc -l < "$PUB_LOG" | tr -d ' ')"
    # 64 sensor + 9 binary_sensor = 73 retained discovery configs.
    assertEquals "73" "$cnt"

    # All retained, qos=0
    while IFS='|' read -r topic _payload qos retain; do
        assertEquals "0" "$qos"
        assertEquals "true" "$retain"
        case "$topic" in
            homeassistant/sensor/miyoo-test_battery/config) ;;
            homeassistant/sensor/miyoo-test_volume/config) ;;
            homeassistant/sensor/miyoo-test_ram/config) ;;
            homeassistant/sensor/miyoo-test_cpu/config) ;;
            homeassistant/sensor/miyoo-test_uptime/config) ;;
            homeassistant/sensor/miyoo-test_temperature/config) ;;
            homeassistant/sensor/miyoo-test_cpu_freq/config) ;;
            homeassistant/sensor/miyoo-test_sd_free/config) ;;
            homeassistant/sensor/miyoo-test_brightness/config) ;;
            homeassistant/sensor/miyoo-test_vbat/config) ;;
            homeassistant/sensor/miyoo-test_ibat/config) ;;
            homeassistant/sensor/miyoo-test_wifi_rssi/config) ;;
            homeassistant/sensor/miyoo-test_wifi_ssid/config) ;;
            homeassistant/sensor/miyoo-test_ip/config) ;;
            homeassistant/sensor/miyoo-test_core/config) ;;
            homeassistant/sensor/miyoo-test_game/config) ;;
            homeassistant/sensor/miyoo-test_cpu_load5/config) ;;
            homeassistant/sensor/miyoo-test_cpu_load15/config) ;;
            homeassistant/sensor/miyoo-test_swap_used/config) ;;
            homeassistant/sensor/miyoo-test_kernel/config) ;;
            homeassistant/sensor/miyoo-test_cpu_governor/config) ;;
            homeassistant/sensor/miyoo-test_cpu_min_freq/config) ;;
            homeassistant/sensor/miyoo-test_cpu_max_freq/config) ;;
            homeassistant/sensor/miyoo-test_temp_throttle_hi/config) ;;
            homeassistant/sensor/miyoo-test_temp_throttle_lo/config) ;;
            homeassistant/sensor/miyoo-test_wifi_mac/config) ;;
            homeassistant/sensor/miyoo-test_wifi_bitrate/config) ;;
            homeassistant/sensor/miyoo-test_theme/config) ;;
            homeassistant/sensor/miyoo-test_charging_source/config) ;;
            homeassistant/sensor/miyoo-test_mode/config) ;;
            homeassistant/sensor/miyoo-test_bgm_volume/config) ;;
            homeassistant/sensor/miyoo-test_hibernate_min/config) ;;
            homeassistant/sensor/miyoo-test_language/config) ;;
            homeassistant/sensor/miyoo-test_hue/config) ;;
            homeassistant/sensor/miyoo-test_saturation/config) ;;
            homeassistant/sensor/miyoo-test_contrast/config) ;;
            homeassistant/sensor/miyoo-test_lumination/config) ;;
            homeassistant/sensor/miyoo-test_playtime_total_hours/config) ;;
            homeassistant/sensor/miyoo-test_playtime_today_min/config) ;;
            homeassistant/sensor/miyoo-test_most_played/config) ;;
            homeassistant/sensor/miyoo-test_last_played/config) ;;
            homeassistant/sensor/miyoo-test_game_count/config) ;;
            homeassistant/binary_sensor/miyoo-test_charging/config) ;;
            homeassistant/binary_sensor/miyoo-test_ntp_synced/config) ;;
            homeassistant/binary_sensor/miyoo-test_mute/config) ;;
            homeassistant/binary_sensor/miyoo-test_audiofix/config) ;;
            homeassistant/binary_sensor/miyoo-test_blue_light/config) ;;
            homeassistant/binary_sensor/miyoo-test_bgm_mute/config) ;;
            homeassistant/binary_sensor/miyoo-test_autostart/config) ;;
            homeassistant/binary_sensor/miyoo-test_battery_warning/config) ;;
            homeassistant/binary_sensor/miyoo-test_cpuclock_hotkey/config) ;;
            homeassistant/sensor/miyoo-test_onion_version/config) ;;
            homeassistant/sensor/miyoo-test_cpu_cores/config) ;;
            homeassistant/sensor/miyoo-test_mem_total_kb/config) ;;
            homeassistant/sensor/miyoo-test_process_count/config) ;;
            homeassistant/sensor/miyoo-test_wifi_rx_bytes/config) ;;
            homeassistant/sensor/miyoo-test_wifi_tx_bytes/config) ;;
            homeassistant/sensor/miyoo-test_wifi_quality/config) ;;
            homeassistant/sensor/miyoo-test_wifi_freq/config) ;;
            homeassistant/sensor/miyoo-test_wifi_bssid/config) ;;
            homeassistant/sensor/miyoo-test_dns_server/config) ;;
            homeassistant/sensor/miyoo-test_save_state_count/config) ;;
            homeassistant/sensor/miyoo-test_sd_usage_pct/config) ;;
            homeassistant/sensor/miyoo-test_mem_cached_kb/config) ;;
            homeassistant/sensor/miyoo-test_mem_buffers_kb/config) ;;
            homeassistant/sensor/miyoo-test_disk_read_sectors/config) ;;
            homeassistant/sensor/miyoo-test_disk_write_sectors/config) ;;
            homeassistant/sensor/miyoo-test_apps_count/config) ;;
            homeassistant/sensor/miyoo-test_emulators_count/config) ;;
            homeassistant/sensor/miyoo-test_themes_count/config) ;;
            homeassistant/sensor/miyoo-test_saves_count/config) ;;
            homeassistant/sensor/miyoo-test_saves_size_kb/config) ;;
            homeassistant/sensor/miyoo-test_session_duration_sec/config) ;;
            *) fail "unexpected topic: $topic" ;;
        esac
    done < "$PUB_LOG"
    rm -f "$PUB_LOG"
}

testPublishDiscoveryConfigReferencesStateTopic() {
    LIB="$SCRIPT_DIR/../App/MQTTReporter/scripts/lib.sh"
    . "$LIB"
    . "$DISC"

    PUB_LOG="$(mktemp)"
    mqtt_publish() {
        printf '%s\n' "$2" >> "$PUB_LOG"
    }

    export DEVICE_ID="miyoo-test"
    publish_discovery
    unset DEVICE_ID

    grep -q 'miyoo/miyoo-test/state' "$PUB_LOG"
    assertEquals 0 $?
    grep -q '"avty_t":"miyoo/miyoo-test/availability"' "$PUB_LOG"
    assertEquals 0 $?
    rm -f "$PUB_LOG"
}

. "$SCRIPT_DIR/shunit2"
