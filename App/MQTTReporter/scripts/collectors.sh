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
# Scale 0-20 → 0-100. Mute state is reported via its own binary sensor —
# this reader returns the actual volume level even when muted.
read_volume_miyoo() {
    local cfg vol
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

# read_uptime <uptime_path>
# Echoes uptime in integer seconds.
read_uptime() {
    local f="$1"
    [ -r "$f" ] || return 0
    awk '{ printf "%d", $1 }' "$f"
}

# read_temperature <thermal_zone_path>
# Echoes temperature in integer degrees Celsius (file is millicelsius).
read_temperature() {
    local f="$1"
    [ -r "$f" ] || return 0
    awk '{ printf "%d", $1 / 1000 }' "$f"
}

# read_cpu_freq <scaling_cur_freq_path>
# Echoes current CPU frequency in MHz (file is kHz).
read_cpu_freq() {
    local f="$1"
    [ -r "$f" ] || return 0
    awk '{ printf "%d", $1 / 1000 }' "$f"
}

# read_sd_free <mount_path>
# Echoes free space in MB. Uses df -k.
read_sd_free() {
    local m="$1"
    [ -d "$m" ] || return 0
    df -k "$m" 2>/dev/null | awk 'NR==2 { printf "%d", $4 / 1024 }'
}

# parse_df_free
# Reads `df -k` output from stdin, echoes available column / 1024 (MB).
parse_df_free() {
    awk 'NR==2 { printf "%d", $4 / 1024 }'
}

# parse_axp_byte
# Reads `axp <reg>` output from stdin, echoes hex byte (e.g. "d5"), empty on no match.
parse_axp_byte() {
    sed -n 's/.*read value:\([0-9a-fA-F][0-9a-fA-F]*\).*/\1/p' | head -1
}

# parse_iw_link_rssi
# Reads `iw dev wlan0 link` output from stdin, echoes signal in dBm.
parse_iw_link_rssi() {
    sed -n 's/.*signal:[[:space:]]*\(-\{0,1\}[0-9][0-9]*\)[[:space:]]*dBm.*/\1/p' | head -1
}

# parse_iw_link_ssid
# Reads `iw dev wlan0 link` output from stdin, echoes SSID string.
parse_iw_link_ssid() {
    sed -n 's/^[[:space:]]*SSID:[[:space:]]*\(.*\)/\1/p' | head -1
}

# parse_ip_addr_inet
# Reads `ip addr show <iface>` output from stdin, echoes IPv4 address (no /mask).
parse_ip_addr_inet() {
    sed -n 's|.*inet[[:space:]]\([0-9.][0-9.]*\)/.*|\1|p' | head -1
}

# parse_onion_cmd
# Reads .tmp_update/cmd_to_run.sh content from stdin, echoes "<core>|<rom_basename>".
# Handles both formats Onion writes:
#   1. RetroArch:        retroarch -L <path>/<core>_libretro.so "<rom_path>"
#   2. Per-emulator:     LD_PRELOAD=... "/mnt/SDCARD/Emu/<CORE>/launch.sh" "<rom_path>"
# Empty when neither format matches.
parse_onion_cmd() {
    local line core rom_path rom_base rom_name
    line="$(cat)"
    [ -n "$line" ] || return 0

    # RetroArch core name comes from `<dir>/<core>_libretro.so`
    core="$(printf '%s' "$line" | sed -n 's|.*/\([^/]*\)_libretro\.so.*|\1|p' | head -1)"
    # Onion Emu launcher core comes from `/mnt/SDCARD/Emu/<CORE>/launch.sh`
    if [ -z "$core" ]; then
        core="$(printf '%s' "$line" | sed -n 's|.*/Emu/\([^/]*\)/launch\.sh.*|\1|p' | head -1)"
    fi

    # ROM path is always the LAST double-quoted string on the line.
    rom_path="$(printf '%s' "$line" | sed -n 's|.*"\([^"]*\)"[[:space:]]*$|\1|p' | head -1)"
    if [ -n "$rom_path" ]; then
        rom_base="${rom_path##*/}"
        rom_name="${rom_base%.*}"
    fi

    if [ -z "$core" ] && [ -z "$rom_name" ]; then
        return 0
    fi
    printf '%s|%s' "$core" "$rom_name"
}

# read_brightness_miyoo
# Onion stores backlight 0-10 in system.json `brightness`. Scale to 0-100%.
read_brightness_miyoo() {
    local cfg b
    for cfg in /mnt/SDCARD/.tmp_update/config/system/*.json; do
        [ -r "$cfg" ] || continue
        b="$(sed -n 's/.*"brightness":[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$cfg" | head -1)"
        [ -n "$b" ] || return 0
        printf '%d' $((b * 10))
        return 0
    done
}

# read_battery_voltage_miyoo
# Reads AXP223 registers 78h:79h (12-bit), echoes mV. Formula: raw * 1.1.
read_battery_voltage_miyoo() {
    command -v axp >/dev/null 2>&1 || return 0
    local hi lo raw
    hi="$(axp 78 2>/dev/null | parse_axp_byte)"
    lo="$(axp 79 2>/dev/null | parse_axp_byte)"
    [ -n "$hi" ] && [ -n "$lo" ] || return 0
    raw=$(( (0x${hi} << 4) | (0x${lo} & 0x0F) ))
    awk -v r="$raw" 'BEGIN { printf "%d", r * 1.1 }'
}

# read_battery_current_miyoo
# Discharge current (7Ch:7Dh, 13-bit) minus charge current (7Ah:7Bh, 12-bit),
# scale 0.5 mA per LSB. Signed result follows the user-facing convention:
# positive = consuming (draining), negative = charging.
read_battery_current_miyoo() {
    command -v axp >/dev/null 2>&1 || return 0
    local cah cal dh dl charge_raw drain_raw
    cah="$(axp 7A 2>/dev/null | parse_axp_byte)"
    cal="$(axp 7B 2>/dev/null | parse_axp_byte)"
    dh="$(axp 7C 2>/dev/null | parse_axp_byte)"
    dl="$(axp 7D 2>/dev/null | parse_axp_byte)"
    [ -n "$cah" ] && [ -n "$cal" ] && [ -n "$dh" ] && [ -n "$dl" ] || return 0
    charge_raw=$(( (0x${cah} << 4) | (0x${cal} & 0x0F) ))
    drain_raw=$(( (0x${dh} << 5) | (0x${dl} & 0x1F) ))
    awk -v c="$charge_raw" -v d="$drain_raw" \
        'BEGIN { printf "%d", (d - c) / 2 }'
}

# read_wifi_link_miyoo
# Calls `iw dev wlan0 link`. Echoes "<rssi>|<ssid>" or empty.
read_wifi_link_miyoo() {
    command -v iw >/dev/null 2>&1 || return 0
    local out rssi ssid
    out="$(iw dev wlan0 link 2>/dev/null)"
    [ -n "$out" ] || return 0
    rssi="$(printf '%s\n' "$out" | parse_iw_link_rssi)"
    ssid="$(printf '%s\n' "$out" | parse_iw_link_ssid)"
    [ -n "$rssi" ] || [ -n "$ssid" ] || return 0
    printf '%s|%s' "$rssi" "$ssid"
}

# read_ip_miyoo
# Echoes IPv4 of wlan0. Empty if no link.
read_ip_miyoo() {
    command -v ip >/dev/null 2>&1 || return 0
    ip addr show wlan0 2>/dev/null | parse_ip_addr_inet
}

# read_running_game_miyoo
# Onion writes /mnt/SDCARD/.tmp_update/cmd_to_run.sh whenever it launches a
# ROM (retroarch direct or per-emulator launcher). Format is handled by
# parse_onion_cmd. Echoes "<core>|<rom_basename>" or empty.
read_running_game_miyoo() {
    local f=/mnt/SDCARD/.tmp_update/cmd_to_run.sh
    [ -r "$f" ] || return 0
    parse_onion_cmd < "$f"
}

# scale_temp <raw_int>
# Echoes integer °C, auto-detecting the source unit:
#   - raw > 200 → millicelsius (Linux thermal_zone convention) — divide by 1000
#   - else      → already °C
# Empty when input isn't a valid (possibly negative) integer.
scale_temp() {
    case "$1" in
        ''|*[!0-9-]*) return 0 ;;
        *) ;;
    esac
    if [ "$1" -gt 200 ]; then
        printf '%d' $(($1 / 1000))
    else
        printf '%d' "$1"
    fi
}

# read_temperature_miyoo
# Miyoo Mini Plus is Sigmastar SSD202D (NOT Allwinner V3s — `/proc/cpuinfo`
# says "SStar Soc"). The SoC exposes its temperature at
# `/sys/devices/system/cpu/cpufreq/temp_out` as the literal string `Temp=NN`
# (NN already in °C). Strip the prefix, then scale_temp validates + handles
# other kernels that emit raw millicelsius.
read_temperature_miyoo() {
    local f=/sys/devices/system/cpu/cpufreq/temp_out
    [ -r "$f" ] || return 0
    local raw v
    raw="$(head -1 "$f" 2>/dev/null)"
    v="${raw#Temp=}"
    scale_temp "$v"
}

# read_load_avg <loadavg_path> <field>
# Field 1=load1, 2=load5, 3=load15. Echoes the float as a string.
read_load_avg() {
    local f="$1"
    local field="$2"
    [ -r "$f" ] || return 0
    awk -v fld="$field" '{ printf "%s", $fld }' "$f"
}

# read_swap_used <meminfo_path>
# Echoes used swap in kB (SwapTotal - SwapFree). Empty if no swap config'd.
read_swap_used() {
    local f="$1"
    [ -r "$f" ] || return 0
    local total free
    total="$(awk '/^SwapTotal:/ { print $2; exit }' "$f")"
    free="$(awk '/^SwapFree:/  { print $2; exit }' "$f")"
    [ -n "$total" ] && [ -n "$free" ] || return 0
    [ "$total" -eq 0 ] && return 0
    printf '%d' $((total - free))
}

# read_first_line <path>
# Generic helper: cat first line of file (kernel version, governor, MAC, etc).
read_first_line() {
    local f="$1"
    [ -r "$f" ] || return 0
    head -1 "$f" 2>/dev/null
}

# read_cpu_freq_khz_to_mhz <path>
# Reads kHz from sysfs, echoes MHz integer. Used by min/max freq.
read_cpu_freq_khz_to_mhz() {
    local f="$1"
    [ -r "$f" ] || return 0
    awk '{ printf "%d", $1 / 1000 }' "$f"
}

# parse_iw_link_bitrate
# Reads `iw dev wlan0 link` from stdin, echoes tx bitrate in Mbps (integer).
parse_iw_link_bitrate() {
    sed -n 's|.*tx bitrate:[[:space:]]*\([0-9][0-9]*\).*|\1|p' | head -1
}

# read_wifi_bitrate_miyoo
read_wifi_bitrate_miyoo() {
    command -v iw >/dev/null 2>&1 || return 0
    iw dev wlan0 link 2>/dev/null | parse_iw_link_bitrate
}

# read_ntp_synced_miyoo
# Onion writes /tmp/ntp_synced as a flag-file once time is synced.
# Echoes ON/OFF (HA binary_sensor default payload).
read_ntp_synced_miyoo() {
    if [ -e /tmp/ntp_synced ]; then
        printf 'ON'
    else
        printf 'OFF'
    fi
}

# read_theme_miyoo
# Echoes the basename of the theme path in system.json.
read_theme_miyoo() {
    local cfg path
    for cfg in /mnt/SDCARD/.tmp_update/config/system/*.json; do
        [ -r "$cfg" ] || continue
        # Capture the full quoted value first, then strip path + trailing slash.
        path="$(sed -n 's|.*"theme":[[:space:]]*"\([^"]*\)".*|\1|p' "$cfg" | head -1)"
        path="${path%/}"
        printf '%s' "${path##*/}"
        return 0
    done
}

# read_mute_miyoo
# Echoes ON/OFF (HA binary_sensor default) from system.json `mute`.
# Stale (only persisted on MainUI save events — same caveat as brightness).
read_mute_miyoo() {
    local cfg m
    for cfg in /mnt/SDCARD/.tmp_update/config/system/*.json; do
        [ -r "$cfg" ] || continue
        m="$(sed -n 's/.*"mute":[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$cfg" | head -1)"
        if [ "$m" = "1" ]; then printf 'ON'; else printf 'OFF'; fi
        return 0
    done
    printf 'OFF'
}

# parse_axp_charging_source
# Reads `axp 0` output from stdin, decodes the power-source bits per AXP223:
#   bit 7 (0x80): ACIN exists (charger jack present)
#   bit 5 (0x20): VBUS exists (USB host)
# Echoes: "ac", "usb", "ac+usb", or "none".
parse_axp_charging_source() {
    local hex acin vbus
    hex="$(parse_axp_byte)"
    [ -n "$hex" ] || return 0
    acin=$(( 0x${hex} & 0x80 ))
    vbus=$(( 0x${hex} & 0x20 ))
    if [ "$acin" -ne 0 ] && [ "$vbus" -ne 0 ]; then
        printf 'ac+usb'
    elif [ "$acin" -ne 0 ]; then
        printf 'ac'
    elif [ "$vbus" -ne 0 ]; then
        printf 'usb'
    else
        printf 'none'
    fi
}

# read_charging_source_miyoo
read_charging_source_miyoo() {
    command -v axp >/dev/null 2>&1 || return 0
    axp 0 2>/dev/null | parse_axp_charging_source
}

# parse_system_json_int <cfg_file> <key>
# Extracts integer value for <key> from Onion's system.json.
parse_system_json_int() {
    sed -n "s/.*\"$2\":[[:space:]]*\([0-9][0-9]*\).*/\1/p" "$1" | head -1
}

# parse_system_json_str <cfg_file> <key>
# Extracts quoted string value for <key>.
parse_system_json_str() {
    sed -n "s|.*\"$2\":[[:space:]]*\"\([^\"]*\)\".*|\1|p" "$1" | head -1
}

# _system_json — echoes the first matching system json file (one per device)
_system_json() {
    local cfg
    for cfg in /mnt/SDCARD/.tmp_update/config/system/*.json; do
        [ -r "$cfg" ] || continue
        printf '%s' "$cfg"
        return
    done
}

# read_system_int_miyoo <key>
read_system_int_miyoo() {
    local cfg
    cfg="$(_system_json)"
    [ -n "$cfg" ] || return 0
    parse_system_json_int "$cfg" "$1"
}

# read_system_str_miyoo <key>
read_system_str_miyoo() {
    local cfg
    cfg="$(_system_json)"
    [ -n "$cfg" ] || return 0
    parse_system_json_str "$cfg" "$1"
}

# read_bgm_volume_miyoo — Onion bgmvol 0-20 scaled to %.
read_bgm_volume_miyoo() {
    local v
    v="$(read_system_int_miyoo bgmvol)"
    [ -n "$v" ] || return 0
    printf '%d' $((v * 5))
}

# Onion flag-file binary readers. Echo "ON"/"OFF" for HA binary_sensor.
_flag_present_on() {
    [ -e "$1" ] && printf 'ON' || printf 'OFF'
}
_flag_absent_on() {
    [ -e "$1" ] && printf 'OFF' || printf 'ON'
}

read_blue_light_miyoo()      { _flag_present_on /tmp/.blfOn; }
read_bgm_mute_miyoo()        { _flag_present_on /tmp/.bgmMute; }
read_autostart_enabled_miyoo()      { _flag_absent_on /tmp/.noAutoStart; }
read_battery_warning_enabled_miyoo(){ _flag_absent_on /tmp/.noBatteryWarning; }
read_cpuclock_hotkey_miyoo() { _flag_present_on /tmp/.cpuClockHotkey; }

# proc_exists <comm>
# True (0) if any /proc/<pid>/comm matches the given name.
proc_exists() {
    local d c
    for d in /proc/[0-9]*; do
        [ -r "$d/comm" ] || continue
        c="$(cat "$d/comm" 2>/dev/null)"
        [ "$c" = "$1" ] && return 0
    done
    return 1
}

# detect_current_mode_miyoo
# Returns one of: game / drastic / advmenu / launching / switcher / mainui / unknown.
# Mirrors Onion's check_isXxx logic from src/common/system/state.h.
detect_current_mode_miyoo() {
    if [ -e /mnt/SDCARD/.tmp_update/cmd_to_run.sh ]; then
        if proc_exists retroarch || proc_exists ra32; then
            printf 'game'; return
        fi
        if proc_exists drastic; then
            printf 'drastic'; return
        fi
        if proc_exists advmenu; then
            printf 'advmenu'; return
        fi
        printf 'launching'
        return
    fi
    if [ -e /mnt/SDCARD/.tmp_update/.runGameSwitcher ] && proc_exists gameSwitcher; then
        printf 'switcher'; return
    fi
    if proc_exists MainUI; then
        printf 'mainui'; return
    fi
    printf 'unknown'
}

# query_play_activity <sql>
# Runs a SQL query against Onion's play_activity SQLite DB. Empty on any
# failure (missing DB, missing sqlite3 binary, query error).
query_play_activity() {
    local db
    command -v sqlite3 >/dev/null 2>&1 || return 0
    for db in /mnt/SDCARD/Saves/CurrentProfile/play_activity/play_activity_db.sqlite \
              /mnt/SDCARD/Saves/CurrentProfile/saves/playActivity.db; do
        if [ -r "$db" ]; then
            sqlite3 "$db" "$1" 2>/dev/null
            return
        fi
    done
}

# Sessions ≤ 60 seconds are filtered out (matches Onion's own SUM query in
# src/playActivity/playActivityDB.h — avoids counting accidental boots).

read_playtime_total_miyoo() {
    query_play_activity "SELECT printf('%.1f', COALESCE(SUM(play_time), 0) / 3600.0) FROM play_activity WHERE play_time > 60;"
}

read_playtime_today_miyoo() {
    query_play_activity "SELECT COALESCE(SUM(play_time), 0) / 60 FROM play_activity WHERE play_time > 60 AND created_at >= strftime('%s', 'now', 'start of day', 'localtime');"
}

read_most_played_miyoo() {
    query_play_activity "SELECT rom.name FROM rom JOIN play_activity ON rom.id = play_activity.rom_id WHERE play_activity.play_time > 60 GROUP BY rom.id ORDER BY SUM(play_activity.play_time) DESC LIMIT 1;"
}

read_last_played_miyoo() {
    query_play_activity "SELECT rom.name FROM rom JOIN play_activity ON rom.id = play_activity.rom_id WHERE play_activity.play_time > 60 ORDER BY play_activity.created_at DESC LIMIT 1;"
}

read_game_count_miyoo() {
    query_play_activity "SELECT COUNT(DISTINCT rom_id) FROM play_activity WHERE play_time > 60;"
}

# read_onion_version_miyoo
read_onion_version_miyoo() {
    read_first_line /mnt/SDCARD/.tmp_update/onionVersion/version.txt
}

# read_cpu_cores
read_cpu_cores() {
    [ -r /proc/cpuinfo ] || return 0
    grep -c '^processor' /proc/cpuinfo
}

# read_mem_total <meminfo_path>
read_mem_total() {
    local f="$1"
    [ -r "$f" ] || return 0
    awk '/^MemTotal:/ { print $2; exit }' "$f"
}

# read_process_count
read_process_count() {
    set -- /proc/[0-9]*
    [ -e "$1" ] || { echo 0; return; }
    echo "$#"
}

# parse_net_dev_field <iface> <field_index>
# Reads /proc/net/dev from stdin. Fields (1-indexed after the iface name colon):
#   1=RX bytes 2=RX packets 3=RX errs ... 9=TX bytes 10=TX packets ...
parse_net_dev_field() {
    local iface="$1" idx="$2"
    awk -v ifc="$iface:" -v i="$idx" '
        $1 == ifc { print $(i + 1); exit }
    '
}

# read_wifi_rx_bytes
read_wifi_rx_bytes() {
    [ -r /proc/net/dev ] || return 0
    parse_net_dev_field wlan0 1 < /proc/net/dev
}

# read_wifi_tx_bytes
read_wifi_tx_bytes() {
    [ -r /proc/net/dev ] || return 0
    parse_net_dev_field wlan0 9 < /proc/net/dev
}

# parse_wireless_quality
# Reads /proc/net/wireless from stdin, echoes link quality column for wlan0.
parse_wireless_quality() {
    awk '
        /^[[:space:]]*wlan0:/ {
            # Fields: wlan0: status quality. level. noise. ...
            # Strip trailing dot from quality.
            q = $3; sub(/\.$/, "", q)
            print q; exit
        }
    '
}

# read_wifi_quality
read_wifi_quality() {
    [ -r /proc/net/wireless ] || return 0
    parse_wireless_quality < /proc/net/wireless
}

# parse_iw_link_freq
# Reads `iw dev wlan0 link` from stdin, echoes the freq MHz value.
parse_iw_link_freq() {
    sed -n 's|.*freq:[[:space:]]*\([0-9][0-9]*\).*|\1|p' | head -1
}

# parse_iw_link_bssid
# Reads `iw dev wlan0 link` from stdin, echoes the AP MAC ("Connected to <mac>").
parse_iw_link_bssid() {
    sed -n 's|^Connected to \([0-9a-fA-F:]\{17\}\).*|\1|p' | head -1
}

# read_wifi_freq_miyoo / read_wifi_bssid_miyoo
read_wifi_freq_miyoo() {
    command -v iw >/dev/null 2>&1 || return 0
    iw dev wlan0 link 2>/dev/null | parse_iw_link_freq
}
read_wifi_bssid_miyoo() {
    command -v iw >/dev/null 2>&1 || return 0
    iw dev wlan0 link 2>/dev/null | parse_iw_link_bssid
}

# parse_resolv_nameserver
# Reads /etc/resolv.conf from stdin, echoes first nameserver IP.
parse_resolv_nameserver() {
    sed -n 's/^nameserver[[:space:]][[:space:]]*\([0-9.][0-9.]*\)/\1/p' | head -1
}

# read_dns_server
read_dns_server() {
    [ -r /etc/resolv.conf ] || return 0
    parse_resolv_nameserver < /etc/resolv.conf
}

# read_save_state_count_miyoo — counts *.state* files under /mnt/SDCARD/Saves.
# May be slow on large libraries; the daemon's 10s interval absorbs the cost.
read_save_state_count_miyoo() {
    [ -d /mnt/SDCARD/Saves ] || return 0
    find /mnt/SDCARD/Saves -type f -name '*.state*' 2>/dev/null | wc -l | tr -d ' '
}

# read_sd_usage_pct_miyoo — % used of /mnt/SDCARD.
read_sd_usage_pct_miyoo() {
    df /mnt/SDCARD 2>/dev/null | awk 'NR==2 { sub(/%$/, "", $5); print $5 }'
}
