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
    _emit "$did" sensor        battery  "Miyoo Battery"   "%"  "{{ value_json.battery }}"   "mdi:battery"          "battery"
    _emit "$did" sensor        volume   "Miyoo Volume"    "%"  "{{ value_json.volume }}"    "mdi:volume-high"      ""
    _emit "$did" sensor        ram      "Miyoo RAM Used"  "%"  "{{ value_json.ram }}"       "mdi:memory"           ""
    _emit "$did" sensor        cpu      "Miyoo CPU Load"  ""   "{{ value_json.cpu }}"       "mdi:chip"             ""
    _emit "$did" binary_sensor charging "Miyoo Charging"  ""   "{{ value_json.charging }}"  "mdi:battery-charging" "battery_charging"
}
