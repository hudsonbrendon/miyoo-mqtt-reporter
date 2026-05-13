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
