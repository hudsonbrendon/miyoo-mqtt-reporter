#!/bin/sh
# shellcheck shell=sh

# device_id
# Echoes a stable identifier for this device.
# Order: $DEVICE_ID > sanitized wlan0 MAC > "miyoominiplus".
# Uses $NET_ADDR_READER (shell snippet) for testability; defaults to reading
# /sys/class/net/wlan0/address.
device_id() {
    if [ -n "${DEVICE_ID:-}" ]; then
        printf '%s' "$DEVICE_ID"
        return 0
    fi
    local reader mac clean
    reader="${NET_ADDR_READER:-cat /sys/class/net/wlan0/address}"
    mac="$(eval "$reader" 2>/dev/null || true)"
    if [ -n "$mac" ]; then
        clean="$(printf '%s' "$mac" | tr -d ':' | tr '[:upper:]' '[:lower:]')"
        printf 'miyoo-%s' "$clean"
        return 0
    fi
    printf 'miyoominiplus'
}

# state_topic <device_id>
state_topic() { printf 'miyoo/%s/state' "$1"; }

# availability_topic <device_id>
availability_topic() { printf 'miyoo/%s/availability' "$1"; }

# _emit <device_id> <component> <object_id> <name> <unit> <value_tpl> <icon> <device_class>
_emit() {
    local did="$1" comp="$2" obj="$3" name="$4" unit="$5" tpl="$6" icon="$7" cls="$8"
    local st at uid cfg_topic payload
    st="$(state_topic "$did")"
    at="$(availability_topic "$did")"
    uid="${did}_${obj}"
    cfg_topic="homeassistant/${comp}/${uid}/config"
    # Compact JSON, abbreviated HA keys.
    payload="$(printf '{"name":"%s","uniq_id":"%s","stat_t":"%s","avty_t":"%s","val_tpl":"%s","ic":"%s"%s%s,"dev":{"ids":["%s"],"name":"Miyoo Mini Plus (%s)","mf":"Miyoo","mdl":"Mini Plus","sw":"OnionOS"}}' \
        "$name" "$uid" "$st" "$at" "$tpl" "$icon" \
        "$( [ -n "$unit" ] && printf ',"unit_of_meas":"%s"' "$unit" )" \
        "$( [ -n "$cls" ]  && printf ',"dev_cla":"%s"' "$cls" )" \
        "$did" "$did")"
    mqtt_publish "$cfg_topic" "$payload" 0 true
}

# publish_discovery
# Emits retained Home Assistant Discovery configs for all entities.
publish_discovery() {
    local did
    did="$(device_id)"
    _emit "$did" sensor        battery     "Miyoo Battery"        "%"    "{{ value_json.battery }}"     "mdi:battery"           "battery"
    _emit "$did" sensor        volume      "Miyoo Volume"         "%"    "{{ value_json.volume }}"      "mdi:volume-high"       ""
    _emit "$did" sensor        ram         "Miyoo RAM Used"       "%"    "{{ value_json.ram }}"         "mdi:memory"            ""
    _emit "$did" sensor        cpu         "Miyoo CPU Load"       ""     "{{ value_json.cpu }}"         "mdi:chip"              ""
    _emit "$did" binary_sensor charging    "Miyoo Charging"       ""     "{{ value_json.charging }}"    "mdi:battery-charging"  "battery_charging"
    _emit "$did" sensor        uptime      "Miyoo Last Boot"      ""     "{{ as_datetime(utcnow().timestamp() - value_json.uptime) }}" "mdi:clock-outline" "timestamp"
    _emit "$did" sensor        temperature "Miyoo Temperature"    "°C"   "{{ value_json.temperature }}" "mdi:thermometer"       "temperature"
    _emit "$did" sensor        cpu_freq    "Miyoo CPU Frequency"  "MHz"  "{{ value_json.cpu_freq }}"    "mdi:speedometer"       "frequency"
    _emit "$did" sensor        sd_free     "Miyoo SD Free"        "MB"   "{{ value_json.sd_free }}"     "mdi:sd"                "data_size"
    _emit "$did" sensor        brightness  "Miyoo Brightness"     "%"    "{{ value_json.brightness }}"  "mdi:brightness-6"      ""
    _emit "$did" sensor        vbat        "Miyoo Battery Voltage" "mV"  "{{ value_json.vbat }}"        "mdi:flash"             "voltage"
    _emit "$did" sensor        ibat        "Miyoo Battery Current" "mA"  "{{ value_json.ibat }}"        "mdi:current-dc"        "current"
    _emit "$did" sensor        wifi_rssi   "Miyoo WiFi Signal"    "dBm"  "{{ value_json.wifi_rssi }}"   "mdi:wifi"              "signal_strength"
    _emit "$did" sensor        wifi_ssid   "Miyoo WiFi SSID"      ""     "{{ value_json.wifi_ssid }}"   "mdi:wifi"              ""
    _emit "$did" sensor        ip          "Miyoo IP"             ""     "{{ value_json.ip }}"          "mdi:ip-network"        ""
    _emit "$did" sensor        core        "Miyoo Emulator Core"  ""     "{{ value_json.core }}"        "mdi:gamepad-variant"   ""
    _emit "$did" sensor        game        "Miyoo Running Game"   ""     "{{ value_json.game }}"        "mdi:controller"        ""
    _emit "$did" sensor        cpu_load5   "Miyoo CPU Load 5min"  ""     "{{ value_json.cpu_load5 }}"   "mdi:chip"              ""
    _emit "$did" sensor        cpu_load15  "Miyoo CPU Load 15min" ""     "{{ value_json.cpu_load15 }}"  "mdi:chip"              ""
    _emit "$did" sensor        swap_used   "Miyoo Swap Used"      "kB"   "{{ value_json.swap_used }}"   "mdi:harddisk"          "data_size"
    _emit "$did" sensor        kernel      "Miyoo Kernel"         ""     "{{ value_json.kernel }}"      "mdi:linux"             ""
    _emit "$did" sensor        cpu_governor "Miyoo CPU Governor"  ""     "{{ value_json.cpu_governor }}" "mdi:tune"             ""
    _emit "$did" sensor        cpu_min_freq "Miyoo CPU Min Freq"  "MHz"  "{{ value_json.cpu_min_freq }}" "mdi:speedometer-slow" "frequency"
    _emit "$did" sensor        cpu_max_freq "Miyoo CPU Max Freq"  "MHz"  "{{ value_json.cpu_max_freq }}" "mdi:speedometer"      "frequency"
    _emit "$did" sensor        temp_throttle_hi "Miyoo Throttle High" "°C" "{{ value_json.temp_throttle_hi }}" "mdi:thermometer-alert" "temperature"
    _emit "$did" sensor        temp_throttle_lo "Miyoo Throttle Low"  "°C" "{{ value_json.temp_throttle_lo }}" "mdi:thermometer-minus" "temperature"
    _emit "$did" sensor        wifi_mac    "Miyoo WiFi MAC"       ""     "{{ value_json.wifi_mac }}"    "mdi:network"           ""
    _emit "$did" sensor        wifi_bitrate "Miyoo WiFi Bitrate"  "Mbit/s" "{{ value_json.wifi_bitrate }}" "mdi:wifi-arrow-up-down" "data_rate"
    _emit "$did" binary_sensor ntp_synced  "Miyoo NTP Synced"     ""     "{{ value_json.ntp_synced }}"  "mdi:clock-check"       ""
    _emit "$did" sensor        theme       "Miyoo Theme"          ""     "{{ value_json.theme }}"       "mdi:palette"           ""
    _emit "$did" binary_sensor mute        "Miyoo Mute"           ""     "{{ value_json.mute }}"        "mdi:volume-off"        ""
    _emit "$did" sensor        charging_source "Miyoo Power Source" ""   "{{ value_json.charging_source }}" "mdi:power-plug"    ""
    _emit "$did" sensor        mode        "Miyoo Mode"           ""     "{{ value_json.mode }}"        "mdi:gesture-tap"       ""
    _emit "$did" sensor        bgm_volume  "Miyoo BGM Volume"     "%"    "{{ value_json.bgm_volume }}"  "mdi:music-note"        ""
    _emit "$did" sensor        hibernate_min "Miyoo Hibernate Setting" "min" "{{ value_json.hibernate_min }}" "mdi:bed-clock"      "duration"
    _emit "$did" sensor        language    "Miyoo Language"       ""     "{{ value_json.language }}"    "mdi:translate"         ""
    _emit "$did" sensor        hue         "Miyoo Hue"            ""     "{{ value_json.hue }}"         "mdi:palette-outline"   ""
    _emit "$did" sensor        saturation  "Miyoo Saturation"     ""     "{{ value_json.saturation }}"  "mdi:palette-outline"   ""
    _emit "$did" sensor        contrast    "Miyoo Contrast"       ""     "{{ value_json.contrast }}"    "mdi:contrast-circle"   ""
    _emit "$did" sensor        lumination  "Miyoo Lumination"     ""     "{{ value_json.lumination }}"  "mdi:white-balance-sunny" ""
    _emit "$did" binary_sensor audiofix    "Miyoo Audio Fix"      ""     "{{ 'ON' if value_json.audiofix == 1 else 'OFF' }}" "mdi:audio-input-stereo-minijack" ""
    _emit "$did" binary_sensor blue_light  "Miyoo Blue Light Filter" ""  "{{ value_json.blue_light }}"  "mdi:eye-outline"       ""
    _emit "$did" binary_sensor bgm_mute    "Miyoo BGM Mute"       ""     "{{ value_json.bgm_mute }}"    "mdi:music-note-off"    ""
    _emit "$did" binary_sensor autostart   "Miyoo Game Autostart" ""     "{{ value_json.autostart }}"   "mdi:play-circle"       ""
    _emit "$did" binary_sensor battery_warning "Miyoo Battery Warning" "" "{{ value_json.battery_warning }}" "mdi:battery-alert-variant-outline" ""
    _emit "$did" binary_sensor cpuclock_hotkey "Miyoo CPU Clock Hotkey" "" "{{ value_json.cpuclock_hotkey }}" "mdi:speedometer"   ""
    _emit "$did" sensor        playtime_total_hours "Miyoo Playtime Total" "h" "{{ value_json.playtime_total_hours }}" "mdi:timer-sand" "duration"
    _emit "$did" sensor        playtime_today_min "Miyoo Playtime Today" "min" "{{ value_json.playtime_today_min }}" "mdi:timer" "duration"
    _emit "$did" sensor        most_played "Miyoo Most Played"    ""     "{{ value_json.most_played }}" "mdi:trophy"            ""
    _emit "$did" sensor        last_played "Miyoo Last Played"    ""     "{{ value_json.last_played }}" "mdi:history"           ""
    _emit "$did" sensor        game_count  "Miyoo Games Played"   ""     "{{ value_json.game_count }}"  "mdi:gamepad-square"    ""
    _emit "$did" sensor        onion_version "Miyoo Onion Version" ""    "{{ value_json.onion_version }}" "mdi:onepassword"     ""
    _emit "$did" sensor        cpu_cores   "Miyoo CPU Cores"      ""     "{{ value_json.cpu_cores }}"   "mdi:chip"              ""
    _emit "$did" sensor        mem_total_kb "Miyoo RAM Total"     "kB"   "{{ value_json.mem_total_kb }}" "mdi:memory"           "data_size"
    _emit "$did" sensor        process_count "Miyoo Process Count" ""    "{{ value_json.process_count }}" "mdi:application-cog" ""
    _emit "$did" sensor        wifi_rx_bytes "Miyoo WiFi RX Bytes" "B"   "{{ value_json.wifi_rx_bytes }}" "mdi:download-network" "data_size"
    _emit "$did" sensor        wifi_tx_bytes "Miyoo WiFi TX Bytes" "B"   "{{ value_json.wifi_tx_bytes }}" "mdi:upload-network"   "data_size"
    _emit "$did" sensor        wifi_quality "Miyoo WiFi Quality"  ""     "{{ value_json.wifi_quality }}" "mdi:wifi-strength-4-lock" ""
    _emit "$did" sensor        wifi_freq   "Miyoo WiFi Frequency" "MHz"  "{{ value_json.wifi_freq }}"   "mdi:antenna"           "frequency"
    _emit "$did" sensor        wifi_bssid  "Miyoo WiFi BSSID"     ""     "{{ value_json.wifi_bssid }}"  "mdi:router-wireless"   ""
    _emit "$did" sensor        dns_server  "Miyoo DNS Server"     ""     "{{ value_json.dns_server }}"  "mdi:dns"               ""
    _emit "$did" sensor        save_state_count "Miyoo Save States" ""   "{{ value_json.save_state_count }}" "mdi:content-save" ""
    _emit "$did" sensor        sd_usage_pct "Miyoo SD Usage"      "%"    "{{ value_json.sd_usage_pct }}" "mdi:sd"               ""
}
