#!/bin/sh
# shellcheck shell=sh disable=SC1090,SC1091
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FIX="$SCRIPT_DIR/fixtures"
COL="$SCRIPT_DIR/../App/MQTTReporter/scripts/collectors.sh"

testReadBatteryReturnsCapacityForDischarging() {
    . "$COL"
    out="$(read_battery "$FIX/power-supply-ok")"
    # format: "<capacity>|<charging:true|false>"
    assertEquals "60|false" "$out"
}

testReadBatteryReturnsChargingTrue() {
    . "$COL"
    out="$(read_battery "$FIX/power-supply-charging")"
    assertEquals "90|true" "$out"
}

testReadBatteryReturnsEmptyWhenPathMissing() {
    . "$COL"
    out="$(read_battery /no/such/path 2>/dev/null)"
    assertEquals "" "$out"
}

testParseVolumeExtractsPercent() {
    . "$COL"
    out="$(parse_volume_from < "$FIX/amixer-master.txt")"
    assertEquals "73" "$out"
}

testParseVolumeReturnsEmptyOnGarbage() {
    . "$COL"
    out="$(printf 'no match here\n' | parse_volume_from)"
    assertEquals "" "$out"
}

testReadRamReturnsUsedPercentAndAvailableKb() {
    . "$COL"
    out="$(read_ram "$FIX/proc-meminfo")"
    # format: "<used_percent>|<available_kb>"
    # MemTotal=257784, MemAvailable=124880 -> used%=51 (round)
    assertEquals "51|124880" "$out"
}

testReadRamReturnsEmptyOnMissingFile() {
    . "$COL"
    out="$(read_ram /no/such/file 2>/dev/null)"
    assertEquals "" "$out"
}

testReadCpuReturnsLoad1AndProcsRunning() {
    . "$COL"
    out="$(read_cpu "$FIX/proc-loadavg")"
    # loadavg fixture: "0.42 0.31 0.18 2/95 1234"
    # format: "<load1>|<procs_running>"
    assertEquals "0.42|2" "$out"
}

testReadCpuReturnsEmptyOnMissingFile() {
    . "$COL"
    out="$(read_cpu /no/such/file 2>/dev/null)"
    assertEquals "" "$out"
}

testDetectBatteryPathPicksDirWithTypeBattery() {
    . "$COL"
    out="$(detect_battery_path "$FIX/power-supply-root")"
    assertEquals "$FIX/power-supply-root/axp20x-battery" "$out"
}

testDetectBatteryPathReturnsEmptyOnNoMatch() {
    . "$COL"
    tmp="$(mktemp -d)"
    out="$(detect_battery_path "$tmp" 2>/dev/null)"
    assertEquals "" "$out"
    rmdir "$tmp"
}

testReadUptimeReturnsIntegerSeconds() {
    . "$COL"
    out="$(read_uptime "$FIX/proc-uptime")"
    # Fixture: "12345.67 9876.54" → 12345
    assertEquals "12345" "$out"
}

testReadUptimeReturnsEmptyOnMissingFile() {
    . "$COL"
    out="$(read_uptime /no/such/file 2>/dev/null)"
    assertEquals "" "$out"
}

testReadTemperatureScalesMillicelsiusToCelsius() {
    . "$COL"
    out="$(read_temperature "$FIX/thermal-zone0-temp")"
    # Fixture: "45000" → 45
    assertEquals "45" "$out"
}

testReadCpuFreqScalesKhzToMhz() {
    . "$COL"
    out="$(read_cpu_freq "$FIX/cpufreq-scaling-cur-freq")"
    # Fixture: "1200000" kHz → 1200 MHz
    assertEquals "1200" "$out"
}

testParseDfFreeExtractsAvailableMb() {
    . "$COL"
    out="$(parse_df_free < "$FIX/df-output.txt")"
    # Fixture: Available=43876352 KB → 42848 MB
    assertEquals "42848" "$out"
}

testParseAxpByteExtractsHex() {
    . "$COL"
    out="$(parse_axp_byte < "$FIX/axp-reg-78.txt")"
    assertEquals "d5" "$out"
}

testParseAxpByteEmptyOnGarbage() {
    . "$COL"
    out="$(printf 'nothing here\n' | parse_axp_byte)"
    assertEquals "" "$out"
}

testParseIwLinkRssiExtractsNegativeDbm() {
    . "$COL"
    out="$(parse_iw_link_rssi < "$FIX/iw-dev-link.txt")"
    assertEquals "-57" "$out"
}

testParseIwLinkSsidExtractsName() {
    . "$COL"
    out="$(parse_iw_link_ssid < "$FIX/iw-dev-link.txt")"
    assertEquals "MinhaWiFi" "$out"
}

testParseIpAddrInetExtractsIpv4() {
    . "$COL"
    out="$(parse_ip_addr_inet < "$FIX/ip-addr-wlan0.txt")"
    assertEquals "192.168.31.123" "$out"
}

testParseOnionCmdRetroarchFormatExtractsCoreAndGame() {
    . "$COL"
    out="$(parse_onion_cmd < "$FIX/cmd-to-run-retroarch.sh")"
    assertEquals "mgba|Pokemon FireRed" "$out"
}

testParseOnionCmdRetroarchCoreWithUnderscoresInName() {
    . "$COL"
    out="$(printf 'retroarch -L /usr/lib/cores/pcsx_rearmed_libretro.so "/mnt/SDCARD/Roms/PSX/Castlevania SOTN.chd"\n' | parse_onion_cmd)"
    assertEquals "pcsx_rearmed|Castlevania SOTN" "$out"
}

testParseOnionCmdEmuLauncherFormatExtractsCoreAndGame() {
    . "$COL"
    out="$(parse_onion_cmd < "$FIX/cmd-to-run-onion-gg.sh")"
    # /mnt/SDCARD/Emu/GG/launch.sh + /mnt/SDCARD/Roms/GG/Shinobi.zip
    assertEquals "GG|Shinobi" "$out"
}

testParseOnionCmdEmptyOnNonGameScript() {
    . "$COL"
    out="$(printf '#!/bin/sh\necho hello\n' | parse_onion_cmd)"
    assertEquals "" "$out"
}

testParseOnionCmdHandlesRomWithSpaces() {
    . "$COL"
    out="$(printf 'LD_PRELOAD=x  "/mnt/SDCARD/Emu/PSX/launch.sh" "/mnt/SDCARD/Roms/PSX/Final Fantasy VII.chd"\n' | parse_onion_cmd)"
    assertEquals "PSX|Final Fantasy VII" "$out"
}

testReadRunningGameMiyooReturnsEmptyWhenCmdFileAbsent() {
    . "$COL"
    # The function reads a hardcoded device path. On the dev host that path
    # does not exist, so the function must return empty silently.
    out="$(read_running_game_miyoo 2>/dev/null)"
    assertEquals "" "$out"
}

testScaleTempPassesThroughDirectCelsius() {
    . "$COL"
    assertEquals "35" "$(scale_temp 35)"
}

testScaleTempScalesMillicelsius() {
    . "$COL"
    assertEquals "42" "$(scale_temp 42500)"
}

testScaleTempEmptyOnGarbage() {
    . "$COL"
    out="$(scale_temp 'not-a-number' 2>/dev/null)"
    assertEquals "" "$out"
}

testScaleTempEmptyOnEmptyInput() {
    . "$COL"
    out="$(scale_temp '' 2>/dev/null)"
    assertEquals "" "$out"
}

testScaleTempAllowsNegative() {
    . "$COL"
    # Negative direct °C should pass through.
    assertEquals "-5" "$(scale_temp -5)"
}

testScaleTempRejectsSigmastarPrefix() {
    . "$COL"
    # scale_temp is strict — `Temp=53` must be pre-stripped before calling it.
    # This test pins that contract so read_temperature_miyoo stays honest.
    out="$(scale_temp 'Temp=53' 2>/dev/null)"
    assertEquals "" "$out"
}

testStripTempPrefixIsPosixSafe() {
    . "$COL"
    # read_temperature_miyoo uses ${raw#Temp=} — verify the shell does what
    # we expect for the two known Sigmastar formats.
    raw='Temp=53'
    assertEquals "53" "${raw#Temp=}"
    raw='53000'
    assertEquals "53000" "${raw#Temp=}"
}

testReadLoadAvgExtractsFieldByIndex() {
    . "$COL"
    # fixture: "0.42 0.31 0.18 2/95 1234"
    assertEquals "0.42" "$(read_load_avg "$FIX/proc-loadavg" 1)"
    assertEquals "0.31" "$(read_load_avg "$FIX/proc-loadavg" 2)"
    assertEquals "0.18" "$(read_load_avg "$FIX/proc-loadavg" 3)"
}

testReadSwapUsedComputesDelta() {
    . "$COL"
    # fixture: SwapTotal=524288, SwapFree=460800 -> used=63488
    assertEquals "63488" "$(read_swap_used "$FIX/proc-meminfo-with-swap")"
}

testReadSwapUsedEmptyWhenNoSwap() {
    . "$COL"
    # The standard meminfo fixture has no Swap lines.
    out="$(read_swap_used "$FIX/proc-meminfo")"
    assertEquals "" "$out"
}

testReadFirstLineCatsKernelVersion() {
    . "$COL"
    assertEquals "5.10.99+" "$(read_first_line "$FIX/kernel-version")"
}

testReadFirstLineEmptyOnMissingFile() {
    . "$COL"
    out="$(read_first_line /no/such/file 2>/dev/null)"
    assertEquals "" "$out"
}

testReadCpuFreqMinMhz() {
    . "$COL"
    # 600000 kHz -> 600 MHz
    assertEquals "600" "$(read_cpu_freq_khz_to_mhz "$FIX/cpufreq-min-freq")"
}

testReadCpuFreqMaxMhz() {
    . "$COL"
    assertEquals "1200" "$(read_cpu_freq_khz_to_mhz "$FIX/cpufreq-max-freq")"
}

testParseIwLinkBitrateExtractsMbps() {
    . "$COL"
    # fixture line: "tx bitrate: 24.0 MBit/s" → 24
    out="$(parse_iw_link_bitrate < "$FIX/iw-dev-link.txt")"
    assertEquals "24" "$out"
}

testParseIwLinkBitrateEmptyOnGarbage() {
    . "$COL"
    out="$(printf 'no link\n' | parse_iw_link_bitrate)"
    assertEquals "" "$out"
}

testParseAxpChargingSourceDetectsAcin() {
    . "$COL"
    # 0xf4 = 11110100 → bit7 set (ACIN), bit5 clear (no VBUS)
    out="$(parse_axp_charging_source < "$FIX/axp-reg-0-charging-acin.txt")"
    assertEquals "ac" "$out"
}

testParseAxpChargingSourceDetectsVbus() {
    . "$COL"
    # 0x34 = 00110100 → bit5 set, bit7 clear
    out="$(parse_axp_charging_source < "$FIX/axp-reg-0-vbus.txt")"
    assertEquals "usb" "$out"
}

testParseAxpChargingSourceDetectsBatteryOnly() {
    . "$COL"
    # 0x00 = no external power
    out="$(parse_axp_charging_source < "$FIX/axp-reg-0-battery.txt")"
    assertEquals "none" "$out"
}

. "$SCRIPT_DIR/shunit2"
