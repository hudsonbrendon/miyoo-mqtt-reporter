<div align="center">

```
                                                                  
       ███╗   ███╗ ██╗ ██╗   ██╗  ██████╗   ██████╗               
       ████╗ ████║ ██║ ╚██╗ ██╔╝ ██╔═══██╗ ██╔═══██╗              
       ██╔████╔██║ ██║  ╚████╔╝  ██║   ██║ ██║   ██║              
       ██║╚██╔╝██║ ██║   ╚██╔╝   ██║   ██║ ██║   ██║              
       ██║ ╚═╝ ██║ ██║    ██║    ╚██████╔╝ ╚██████╔╝              
       ╚═╝     ╚═╝ ╚═╝    ╚═╝     ╚═════╝   ╚═════╝               
                  M Q T T   ·   R E P O R T E R                   
       ──────────────────────────────────────────────────         
       POSIX-shell daemon · OnionOS · Miyoo Mini Plus             
       73 entities every 10s · MQTT Discovery → Home Assistant    
                                                                  
                handheld  ─►  broker  ─►  HA dashboard            
                                                                  
```

**`miyoo-mqtt-reporter`** — a tiny POSIX-shell plugin for [OnionOS](https://onionui.github.io/)
that publishes your handheld's system metrics to Home Assistant in real time.

[![Platform](https://img.shields.io/badge/platform-OnionOS_v4.3+-1e293b?style=flat-square)](https://onionui.github.io/)
[![Device](https://img.shields.io/badge/device-Miyoo_Mini_Plus-38bdf8?style=flat-square)](https://lemiyoo.cn/)
[![Shell](https://img.shields.io/badge/shell-POSIX_sh-yellow?style=flat-square)](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html)
[![MQTT](https://img.shields.io/badge/MQTT-Discovery-660198?style=flat-square)](https://www.home-assistant.io/integrations/mqtt/#mqtt-discovery)
[![Tested](https://img.shields.io/badge/tested-on_real_hardware-success?style=flat-square)](#)
[![ShellCheck](https://img.shields.io/badge/shellcheck-clean-success?style=flat-square)](https://www.shellcheck.net/)

</div>

---

## What it does

Every `INTERVAL` seconds (default **10s**) the daemon reads four metrics, packs
them into a compact JSON message, and publishes to your MQTT broker. Home
Assistant auto-creates five entities via **MQTT Discovery** — no
`configuration.yaml` edits required.

| Entity                 | Source on Miyoo                                          | HA type         |
| ---------------------- | -------------------------------------------------------- | --------------- |
**51 entities** in total. The daemon publishes a single JSON state payload
every `INTERVAL` seconds (default 10) and HA Discovery maps fields to entities.

| Entity                 | Source                                                    | HA type         |
| ---------------------- | --------------------------------------------------------- | --------------- |
| **Battery %**          | `/tmp/percBat` (written by Onion's `batmon`)              | `sensor`        |
| **Battery voltage**    | `axp` regs `78h:79h` × 1.1 mV                             | `sensor`        |
| **Battery current**    | `axp` regs `7Ah-7Dh` (drain − charge, 0.5 mA/LSB; positive = discharging) | `sensor`        |
| **Charging on/off**    | `axp 0` register, bit `0x4`                               | `binary_sensor` |
| **Power source**       | `axp 0` bits 7/5 → `ac` / `usb` / `ac+usb` / `none`       | `sensor`        |
| **Volume %**           | `/tmp/live_vol` (real-time via `vol-watcher.sh`)          | `sensor`        |
| **Mute**               | `system.json` `mute` (stale — see Quirks)                 | `binary_sensor` |
| **Brightness %**       | `system.json` `brightness` 0-10 scaled to %  (stale)      | `sensor`        |
| **RAM used %**         | `/proc/meminfo` (MemTotal vs MemAvailable)                | `sensor`        |
| **Swap used (kB)**     | `/proc/meminfo` SwapTotal − SwapFree                      | `sensor`        |
| **CPU load (1/5/15)**  | `/proc/loadavg` fields 1, 2, 3                            | 3× `sensor`     |
| **CPU frequency**      | `/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq`   | `sensor`        |
| **CPU min/max freq**   | `scaling_min_freq` / `scaling_max_freq` (kernel-set)      | 2× `sensor`     |
| **CPU governor**       | `scaling_governor` (e.g. `ondemand`)                      | `sensor`        |
| **Temperature**        | `/sys/devices/system/cpu/cpufreq/temp_out` (`Temp=NN`)    | `sensor`        |
| **Throttle hi/lo**     | `temp_adjust_threshold_hi` / `_lo` (Sigmastar)            | 2× `sensor`     |
| **Last Boot**          | `/proc/uptime` → HA renders "X min ago" (timestamp class) | `sensor`        |
| **SD free space (MB)** | `df -k /mnt/SDCARD`                                       | `sensor`        |
| **Kernel**             | `uname -r`                                                | `sensor`        |
| **WiFi RSSI / SSID**   | `iw dev wlan0 link`                                       | 2× `sensor`     |
| **WiFi bitrate**       | `iw dev wlan0 link` tx bitrate (Mbit/s)                   | `sensor`        |
| **WiFi MAC**           | `/sys/class/net/wlan0/address`                            | `sensor`        |
| **IP address**         | `ip addr show wlan0`                                      | `sensor`        |
| **NTP synced**         | `/tmp/ntp_synced` flag-file presence                      | `binary_sensor` |
| **Theme**              | basename of `theme` path in `system.json` (stale)         | `sensor`        |
| **Running game**       | `/mnt/SDCARD/.tmp_update/cmd_to_run.sh` (parsed)          | `sensor`        |
| **Emulator core**      | same file — either `<core>_libretro.so` or `Emu/<DIR>/`   | `sensor`        |
| **Mode**               | `cmd_to_run.sh` + process scan → `game` / `mainui` / `switcher` / `apps` / `advmenu` / `drastic` / `launching` / `unknown` | `sensor` |
| **Playtime total (h)** | sqlite3 `play_activity` aggregate (sessions > 60 s)       | `sensor`        |
| **Playtime today (min)** | sqlite3 filtered to localtime "start of day"            | `sensor`        |
| **Most played game**   | sqlite3 ORDER BY SUM(play_time) DESC LIMIT 1              | `sensor`        |
| **Last played game**   | sqlite3 ORDER BY created_at DESC LIMIT 1                  | `sensor`        |
| **Game count**         | sqlite3 COUNT(DISTINCT rom_id)                            | `sensor`        |
| **BGM volume**         | `system.json` `bgmvol` 0-20 → %                           | `sensor`        |
| **Hibernate setting**  | `system.json` `hibernate` (min)                           | `sensor`        |
| **Language**           | `system.json` `language` (e.g. `pt-BR.lang`)              | `sensor`        |
| **Hue/Sat/Contrast/Lum**| `system.json` 1-20 each                                  | 4× `sensor`     |
| **Blue light filter**  | `/tmp/.blfOn` presence                                    | `binary_sensor` |
| **BGM mute**           | `/tmp/.bgmMute` presence                                  | `binary_sensor` |
| **Autostart enabled**  | `!/tmp/.noAutoStart`                                      | `binary_sensor` |
| **Battery warning**    | `!/tmp/.noBatteryWarning`                                 | `binary_sensor` |
| **CPU clock hotkey**   | `/tmp/.cpuClockHotkey` presence                           | `binary_sensor` |
| **Audio fix**          | `system.json` `audiofix` (1 = on)                         | `binary_sensor` |

```
                    ┌─────────────────────────────────────────┐
                    │           Miyoo Mini Plus               │
                    │                                         │
                    │   /dev/input/event0 ─▶ vol-watcher.sh ──┼─▶ /tmp/live_vol
                    │                                         │
                    │   /tmp/percBat                          │
                    │   axp register 0      ─▶ collectors.sh ─┼─▶ build_state
                    │   /proc/meminfo                         │       │
                    │   /proc/loadavg                         │       ▼
                    │                                         │   mqtt_publish
                    │                                         │   (mosquitto_pub
                    │                                         │    ARMv7 + parasyte
                    │                                         │    glibc 2.28)
                    └─────────────────────────────────────────┘
                                                              ▼
                                                  ┌─────────────────────┐
                                                  │  MQTT Broker        │
                                                  └──────────┬──────────┘
                                                             ▼
                                                  ┌─────────────────────┐
                                                  │   Home Assistant    │
                                                  │   MQTT Discovery    │
                                                  │   → 5 entities      │
                                                  └─────────────────────┘
```

## Companion Lovelace card

A dedicated card visualises every entity this daemon publishes — battery,
volume, temperature, current game, playtime — in a single Miyoo-shaped
widget:

➡ **[hudsonbrendon/miyoo-mini-card](https://github.com/hudsonbrendon/miyoo-mini-card)**

<p align="center">
  <a href="https://github.com/hudsonbrendon/miyoo-mini-card">
    <img src="https://raw.githubusercontent.com/hudsonbrendon/miyoo-mini-card/main/assets/card-preview.png"
         alt="miyoo-mini-card preview" width="900" />
  </a>
</p>

Installable via HACS (Frontend → Custom repositories → category Lovelace) or
manually from the [latest release](https://github.com/hudsonbrendon/miyoo-mini-card/releases/latest).
The card auto-resolves all entity ids from the `DEVICE_ID` prefix you set in
`mqtt.conf` — no per-entity wiring required.

## Requirements

**Hardware**
- Miyoo Mini Plus running [OnionOS](https://onionui.github.io/) **≥ 4.3.1**
- Wi-Fi connected to the same network as the MQTT broker

**Server**
- Any MQTT broker (Mosquitto / EMQX / HiveMQ / HA's built-in add-on)
- Home Assistant 2023.4+ with the MQTT integration configured
- The broker reachable by **IP** from the Miyoo (mDNS does not work — see [Quirks](#quirks))

**Dev host (for hacking on the project)**
- POSIX `sh`, `shellcheck`, `mosquitto` + `mosquitto-clients` for integration tests
- `rsync` recommended for `install.sh`

## Quick install

```sh
git clone https://github.com/hudsonbrendon/miyoo-mqtt-reporter.git
cd miyoo-mqtt-reporter

# 1. Pre-edit the broker config
cp App/MQTTReporter/etc/mqtt.conf.example App/MQTTReporter/etc/mqtt.conf
$EDITOR App/MQTTReporter/etc/mqtt.conf
# At minimum set MQTT_HOST (LAN IP, NOT homeassistant.local), MQTT_USER, MQTT_PASS

# 2. Plug the Miyoo SD card into your computer, then deploy:
./install.sh /Volumes/Onion          # macOS
# or
./install.sh /media/$USER/Onion      # Linux

# 3. Eject. Slot the SD back into the Miyoo. Boot.
# Daemon autostarts in background; entities show up in HA within 10s.
# IMPORTANT: do NOT open "MQTT Reporter" from the Apps menu — that toggles it OFF.
```

The vendored `mosquitto_pub` ARMv7 binary + dependencies are already in the
repo (`App/MQTTReporter/bin/` and `App/MQTTReporter/lib/`). They target Debian
Buster armhf, glibc 2.28 — see [Quirks](#quirks) for why.

### Updating an already-installed device

```sh
git pull
./install.sh /Volumes/Onion
```

`install.sh` is idempotent:
- `rsync -aL --delete --exclude '/etc/mqtt.conf'` preserves your broker creds
- Re-creates the `state/enabled` flag so autostart stays on
- Removes any obsolete `runtime.sh.user` block from older installs

## Configuration

`App/MQTTReporter/etc/mqtt.conf` keys:

| Key             | Default                  | Purpose                                                   |
| --------------- | ------------------------ | --------------------------------------------------------- |
| `MQTT_HOST`     | `192.168.1.10`           | Broker IP (mDNS does not resolve on Miyoo, see Quirks)    |
| `MQTT_PORT`     | `1883`                   | Broker port                                               |
| `MQTT_USER`     | _empty_                  | Username (leave blank for anonymous)                      |
| `MQTT_PASS`     | _empty_                  | Password                                                  |
| `INTERVAL`      | `10`                     | Seconds between state publishes                           |
| `DEVICE_ID`     | `miyoominiplus`          | Stable identifier (overrides OnionOS's `DEVICE_ID=354`)   |
| `BATTERY_PATH`  | _empty_                  | Unused on Mini Plus — see [Battery](#battery)             |
| `KEEPALIVE`     | `60`                     | Passed to `mosquitto_pub -k`                              |

The file is sourced via POSIX `.` (so it accepts shell-quoted values too). It
is **not committed** to git (`.gitignore` excludes it).

### MQTT topics

| Topic                                                       | Retained | Payload                                                    |
| ----------------------------------------------------------- | -------- | ---------------------------------------------------------- |
| `miyoo/<device_id>/state`                                   | no       | full JSON — see below                                      |
| `miyoo/<device_id>/availability`                            | yes      | `online` / `offline`                                       |
| `homeassistant/sensor/<device_id>_<obj>/config` × 42        | yes      | HA Discovery configs (one per sensor)                      |
| `homeassistant/binary_sensor/<device_id>_<obj>/config` × 9  | yes      | binary entities (charging, mute, ntp, blue_light, ...)     |

State payload format (single JSON object per publish, abbreviated):

```json
{
  "battery": 36, "charging": "OFF", "charging_source": "none",
  "volume": 35, "mute": "OFF", "bgm_volume": 75, "bgm_mute": "OFF",
  "brightness": 100, "hue": 10, "saturation": 10, "contrast": 10, "lumination": 10,
  "ram": 29, "swap_used": 0,
  "cpu": 1.55, "cpu_load5": 0.38, "cpu_load15": 0.13,
  "cpu_freq": 800, "cpu_min_freq": 400, "cpu_max_freq": 1200,
  "cpu_governor": "ondemand",
  "temperature": 49, "temp_throttle_hi": 60, "temp_throttle_lo": 40,
  "uptime": 40,
  "sd_free": 3753,
  "vbat": 3687, "ibat": 500,
  "wifi_rssi": -53, "wifi_ssid": "CASA_396_2G", "wifi_bitrate": 72,
  "wifi_mac": "c8:fe:0f:87:d6:a7", "ip": "192.168.31.123",
  "ntp_synced": "ON",
  "kernel": "4.9.84", "language": "pt-BR.lang",
  "theme": "Onion Boy DX by PixelShift",
  "audiofix": 1,
  "hibernate_min": 15,
  "blue_light": "OFF", "autostart": "ON", "battery_warning": "ON", "cpuclock_hotkey": "OFF",
  "mode": "game",
  "core": "mgba", "game": "Pokemon FireRed", "last_played": "Pokemon FireRed",
  "most_played": "Final Fantasy VII", "game_count": 23,
  "playtime_total_hours": "42.7", "playtime_today_min": 35
}
```

Missing values are emitted as `null` (numbers) or `null` (strings) — Home
Assistant value templates handle this gracefully.

## Quirks

This section captures the hardware/OS gotchas we hit during real-device testing.

### Boot hook location

OnionOS **does not exec** `.tmp_update/runtime.sh.user` (a common but incorrect
assumption in older docs). The right place is:

```
/mnt/SDCARD/.tmp_update/startup/*.sh
```

`runtime.sh` iterates every `*.sh` in there at boot and runs it synchronously.
The repo's `boot/startup/mqttreporter.sh` is deployed there by `install.sh`.

**Implication:** your startup script must `nohup ... &` any long-running
process — otherwise boot is blocked until it exits.

### glibc 2.28 ceiling — must use Debian Buster binaries

OnionOS ships glibc up to **2.28** via the `parasyte` bundle
(`/mnt/SDCARD/.tmp_update/lib/parasyte/libc.so.6`). The system `/lib/libc.so.6`
is even older. So:

- ❌ Debian Bookworm (glibc 2.36+) → `GLIBC_2.34 not found`
- ❌ Debian Bullseye (glibc 2.31) → `GLIBC_2.31 not found`
- ✅ **Debian Buster (glibc 2.28)** — matches parasyte exactly

The repo vendors `mosquitto-clients 1.5.7-1+deb10u1` and `openssl 1.1.1n-0+deb10u3`
from Buster. See `App/MQTTReporter/bin/SOURCE.txt` for rebuild instructions.

The startup hook prepends `parasyte` to `LD_LIBRARY_PATH` so the loader resolves
`libc.so.6` against the 2.28 copy before the older system one.

### FAT32 doesn't preserve POSIX symlinks

Miyoo SD cards are FAT32. macOS preserves symlinks via AppleDouble metadata,
but Linux on the Miyoo reads the symlink as a text file (the link target as
content), and the dynamic loader chokes with `invalid ELF header`.

**Fix:** `install.sh` uses `rsync -aL` / `cp -RL` to dereference symlinks at
copy time. If you build the libs manually, use real file copies
(`cp libmosquitto.so.2.x.y libmosquitto.so.1`), never `ln -s`.

### Hardware: Sigmastar SSD202D, NOT Allwinner V3s

`/proc/cpuinfo` reports `Hardware: SStar Soc`. Many community docs claim
the Mini Plus uses Allwinner V3s — wrong. Real chip:

- **SoC:** Sigmastar SSD202D (dual-core Cortex-A7)
- **PMU:** AXP223 over I²C bus 1 addr 0x34, accessed via Onion's `axp <reg>`
- **Audio:** custom kernel module — no `/sys/class/sound/<...>/mixer`, no `amixer`
- **Display:** Sigmastar custom — no `/sys/class/backlight`, no `/sys/class/disp`
- **Temp sensor:** SoC die at `/sys/devices/system/cpu/cpufreq/temp_out`,
  format `Temp=NN` (NN in °C directly). The AXP223 die-temp regs `5Eh:5Fh`
  exist but the temp ADC is not enabled in `axp 82h` → always 0.

### No `/sys/class/power_supply` on Mini Plus

The Mini Plus exposes its PMU through the `axp` userspace binary, not sysfs:

- Battery percent → `cat /tmp/percBat` (Onion's `batmon` daemon writes here)
- Charging flag → `axp 0` register, bit `0x4` set = charging
- Charging source → `axp 0` bit `0x80` (ACIN) / bit `0x20` (VBUS)
- Battery voltage → `axp 78:79` × 1.1 mV
- Battery current → `axp 7A:7B` (charge) − `axp 7C:7D` (drain), × 0.5 mA/LSB

`read_battery_miyoo` and friends in `collectors.sh` handle these. Generic
sysfs readers stay for tests + portability to other devices.

### Volume isn't persisted in real-time

OnionOS only writes `system.json` (where `vol`, `mute`, `brightness`, `theme`
live) on certain events — power-off, returning to the home menu, hibernate.
Pressing volume keys mid-game does NOT update the JSON.

**Solution for volume:** `vol-watcher.sh` runs alongside Onion's `keymon`,
reads `/dev/input/event0` in parallel (both readers get the same event
stream), and tracks each `KEY_VOLUMEUP` (code 115) / `KEY_VOLUMEDOWN`
(code 114) press into `/tmp/live_vol`. `read_volume_miyoo` prefers
`/tmp/live_vol`.

**Same staleness, no workaround:** `mute`, `brightness`, and `theme` all
read from `system.json`. They only update after the user returns to MainUI
(triggers a save). No hardware mute key. No backlight sysfs file. No theme
IPC. Documented as a known limitation.

### No mDNS resolver

`homeassistant.local` will NOT resolve from the Miyoo. Use the broker's LAN IP.

### OnionOS pre-exports `DEVICE_ID=354`

OnionOS's `runtime.sh` exports `DEVICE_ID=354` (the Mini Plus model code) into
the boot environment. `device_id()` sees that and would use `354` as the
identifier, which is meaningless to humans. The example config pins
`DEVICE_ID=miyoominiplus` to keep entities stable.

### Don't open the app from the menu

`launch.sh` is wired as a **toggle**. If autostart is already on and you
open "MQTT Reporter" from the Apps menu, it will turn OFF and remove the
`state/enabled` flag so the next boot doesn't autostart. The recommended
workflow is to install once and never touch the menu entry — let it run in
background.

If you do want manual control:
- Currently OFF → open app → starts daemon, creates `state/enabled`
- Currently ON → open app → stops daemon, removes flag

## Usage

```
┌─────────────────────────────────────┐
│            MQTT Reporter            │
├─────────────────────────────────────┤
│  Status:  enabled=1 running=1       │
│  Press A to toggle ON / OFF         │
└─────────────────────────────────────┘
```

### From the Miyoo via SSH

SSH is not enabled by default on OnionOS. The OnionOS Tweaks app has a
toggle (`Tweaks → Network → SSH`), or you can add `dropbear` to the boot
hook yourself — `dropbear` ships in `/mnt/SDCARD/.tmp_update/bin/`.

Once SSH is up:

```sh
# tail logs
tail -f /mnt/SDCARD/App/MQTTReporter/state/daemon.log
tail -f /mnt/SDCARD/App/MQTTReporter/state/vol-watcher.log

# check status
sh /mnt/SDCARD/App/MQTTReporter/scripts/toggle.sh -c '. /mnt/SDCARD/App/MQTTReporter/scripts/toggle.sh && do_status'

# manually publish one sample (handy for broker debugging)
. /mnt/SDCARD/App/MQTTReporter/scripts/lib.sh
. /mnt/SDCARD/App/MQTTReporter/scripts/collectors.sh
. /mnt/SDCARD/App/MQTTReporter/scripts/discovery.sh
. /mnt/SDCARD/App/MQTTReporter/scripts/daemon.sh
load_config /mnt/SDCARD/App/MQTTReporter/etc/mqtt.conf
DEVICE_ID="$(device_id)"
build_state_payload "" /proc/meminfo /proc/loadavg
```

### From the Mac (when the SD is mounted)

```sh
cat /Volumes/Onion/App/MQTTReporter/state/daemon.log | tail
```

## Development

### Repository layout

```
.
├── App/MQTTReporter/             # Deployable OnionOS app bundle
│   ├── config.json               # OnionOS manifest (label / icon / launch)
│   ├── launch.sh                 # Menu entrypoint — toggle ON/OFF
│   ├── icon.png                  # 200×200 menu icon
│   ├── bin/
│   │   ├── mosquitto_pub         # Buster 1.5.7-1+deb10u1 armhf ELF
│   │   └── SOURCE.txt            # provenance + rebuild instructions
│   ├── lib/
│   │   ├── libmosquitto.so.1     # Buster 1.5.7 armhf
│   │   ├── libssl.so.1.1         # Buster 1.1.1n armhf
│   │   └── libcrypto.so.1.1      # Buster 1.1.1n armhf
│   ├── etc/
│   │   └── mqtt.conf.example     # config template (mqtt.conf is gitignored)
│   └── scripts/
│       ├── lib.sh                # logging, load_config, mqtt_publish
│       ├── collectors.sh         # read_battery / volume / ram / cpu (+ miyoo variants)
│       ├── discovery.sh          # device_id, state_topic, publish_discovery
│       ├── daemon.sh             # build_state_payload + main loop + LWT
│       ├── toggle.sh             # do_start / do_stop / do_status / do_toggle
│       └── vol-watcher.sh        # parallel /dev/input/event0 reader → /tmp/live_vol
├── boot/
│   └── startup/
│       └── mqttreporter.sh       # OnionOS .tmp_update/startup hook
├── tests/                        # shunit2 + sysfs/procfs fixtures, 27 tests
├── install.sh                    # deploy to a mounted SD card
├── .shellcheckrc                 # POSIX sh + 4 narrow disables
└── .gitignore
```

### Running the tests

Unit tests on any POSIX host:

```sh
for t in tests/test_*.sh; do echo "=== $t ==="; sh "$t" || exit 1; done
# expected: 4 suites · 27 tests · OK
```

Integration test against a real local broker:

```sh
brew install mosquitto                                 # macOS
sudo apt install mosquitto mosquitto-clients           # Debian/Ubuntu

sh tests/test_integration.sh
# expected: "Integration test: OK"
```

Static analysis:

```sh
shellcheck -s sh \
    App/MQTTReporter/scripts/*.sh \
    App/MQTTReporter/launch.sh \
    boot/startup/mqttreporter.sh \
    install.sh
```

### Project conventions

- **POSIX `sh` targeting BusyBox `ash`** — no bashisms (no `[[`, `$'...'`, arrays).
- `local` is allowed (BusyBox `ash` supports it). `.shellcheckrc` disables `SC3043` accordingly.
- Every public function in `collectors.sh` / `discovery.sh` has a behavioral
  shunit2 test using fixture dirs (no real `/proc` / `/sys`).
- Miyoo-specific functions are *suffixed* `_miyoo` and called only when the
  device's signature files exist (e.g. `/tmp/percBat`). The generic
  functions remain testable on any Linux/macOS dev host.

### Adding a new metric

1. Add a parser to `collectors.sh` with `local` discipline. Use fixture-driven paths if the data lives in a file.
2. Add a fixture under `tests/fixtures/` + a shunit2 test (TDD).
3. Wire the value into `build_state_payload` (`daemon.sh`).
4. Add an `_emit` call in `publish_discovery` (`discovery.sh`) with an `mdi:` icon and HA `device_class`.
5. Update the topic table above and (if device-specific) document the source in [Quirks](#quirks).

## Troubleshooting

| Symptom                                          | Where to look                                                              |
| ------------------------------------------------ | -------------------------------------------------------------------------- |
| Entities never appear in HA                      | `mosquitto_sub -h <broker> -t 'miyoo/#' -v` on the broker — anything landing? |
| Entities appear as `Unknown`                     | Discovery topic must be retained — check `homeassistant/sensor/...` traffic |
| `daemon.log` shows `Unable to connect (Lookup error.)` | `MQTT_HOST` is mDNS / unresolved. Use the LAN IP.                          |
| `daemon.log` shows `GLIBC_2.34 not found`        | You replaced binaries with Bookworm/Bullseye build. Use Buster (see SOURCE.txt). |
| `daemon.log` shows `invalid ELF header` on a `.so` | Symlink leaked through FAT32. Re-run `install.sh` (uses `rsync -aL`).      |
| Battery shows `Unknown` in HA                    | `/tmp/percBat` not populated yet (boot just finished). Wait one cycle.    |
| Charging stuck at OFF with cable plugged         | Check `axp 0` output via SSH — bit `0x4` should be set when charging.     |
| Volume frozen at last-saved value                | `vol-watcher.log` should show `/tmp/live_vol` writes. Check `state/enabled` exists. |
| Status shows `running=0` right after boot        | `tail /mnt/SDCARD/App/MQTTReporter/state/daemon.log` — config or auth error. |

## Limitations

- **LWT only on graceful stop.** The daemon publishes `availability=offline`
  on SIGTERM via the toggle. A hard power-off leaves HA showing the device as
  online until the broker timeout. Workaround: set `expire_after` on the
  availability sensor in HA, or migrate `mqtt_publish` to a persistent client
  with `--will-*` flags.
- **Mute state is stale.** No hardware mute key on the Mini Plus. The `mute`
  flag comes from `system.json` and only updates when MainUI persists.
- **Single device profile.** Hardcoded for Mini Plus (Allwinner V3s + axp223).
  Probing a Mini (non-Plus) or Mini+ revision may need different paths.

## Roadmap

- [ ] Real MQTT LWT (`--will-*` flags) — close the hard-power-off gap
- [ ] Log rotation (cap at 1 MB) for `daemon.log` and `vol-watcher.log`
- [ ] More metrics: temperature, brightness, WiFi RSSI, current ROM/emulator
- [ ] Auto-detect Mini vs Mini Plus and select battery path accordingly
- [ ] CI: shellcheck + tests on every push
- [ ] Pre-built Mini Plus tarball releases (clone → unzip → install)

## Contributing

PRs welcome. Please:

1. Keep it POSIX `sh` — `shellcheck -s sh` must stay silent.
2. Add a test in `tests/test_*.sh` for any new public function. Use fixture
   files, not real `/proc`.
3. One concern per file (the split in `scripts/` mirrors lifecycles).
4. Conventional Commits: `feat(collectors): add read_foo`, `fix(daemon): handle bar`.

## Credits

- **[OnionOS](https://onionui.github.io/)** — the firmware that makes this possible.
- **[Eclipse Mosquitto](https://mosquitto.org/)** — `mosquitto_pub` does the MQTT.
- **[Home Assistant](https://www.home-assistant.io/)** — for MQTT Discovery.
- **[shunit2](https://github.com/kward/shunit2)** — vendored at v2.1.8.
