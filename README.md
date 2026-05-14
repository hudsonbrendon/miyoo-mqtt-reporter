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

Every `INTERVAL` seconds (default **10s**) the daemon assembles one JSON
state payload and publishes it to your MQTT broker. **Home Assistant
auto-creates 73 entities** via [MQTT Discovery](https://www.home-assistant.io/integrations/mqtt/#mqtt-discovery) — no `configuration.yaml` edits.

Categories covered (see [`discovery.sh`](App/MQTTReporter/scripts/discovery.sh) for the full list):

- **Power** — battery %, voltage, current, charging, charging source
- **Performance** — CPU load/freq/governor, RAM, swap, temperature, throttle, uptime
- **Audio** — volume, mute, BGM volume / mute, audio-fix
- **Display** — brightness, hue / saturation / contrast / lumination, blue-light filter, theme, language
- **Network** — WiFi SSID / RSSI / quality / freq / BSSID / MAC, RX/TX bytes, IP, DNS, NTP synced
- **Storage** — SD free, SD usage %, disk read/write sectors, saves size
- **Gaming** — running game, emulator core, mode, playtime total / today, last / most played, game / save / app / emulator / theme counts, session duration, autostart, hibernate, CPU-clock hotkey
- **System** — kernel, CPU cores, OnionOS version, process count

You pick which subset to publish from the on-device web UI — uncheck what you
don't need.

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
The card auto-resolves all entity ids from the `DEVICE_ID` prefix the
daemon publishes under — no per-entity wiring required.

## Requirements

- Miyoo Mini Plus running [OnionOS](https://onionui.github.io/) **≥ 4.3.1**
- Wi-Fi reachable from the device
- An MQTT broker (Mosquitto / EMQX / HiveMQ / HA's built-in add-on)
- Home Assistant 2023.4+ with the MQTT integration configured
- The broker reachable **by LAN IP** from the Miyoo (mDNS doesn't resolve — see [Limitations](#limitations))

## Install

### Recommended — download the release zip

Easiest path. No `git`, no toolchain.

1. Download the latest zip from the [Releases page](https://github.com/hudsonbrendon/miyoo-mqtt-reporter/releases/latest).
2. Mount the Miyoo SD card on a computer.
3. **Extract the zip at the SD card's root**, merging into the existing
   folders. After extracting you should see:
   ```
   <SD root>/App/MQTTReporter/...
   <SD root>/.tmp_update/startup/mqttreporter.sh
   ```
4. Eject the SD, slot it into the Miyoo, boot.
5. Open the **MQTT Reporter** app from the Apps menu — see
   [Configure via the web UI](#configure-via-the-web-ui-recommended) below.

### From source (developers)

```sh
git clone https://github.com/hudsonbrendon/miyoo-mqtt-reporter.git
cd miyoo-mqtt-reporter

./install.sh /Volumes/Onion          # macOS
./install.sh /media/$USER/Onion      # Linux
```

`install.sh` is idempotent: re-running preserves your `etc/mqtt.conf`
and the autostart flag.

### Updating

- **Zip install:** download the new zip, extract at the SD root again.
  Your `etc/mqtt.conf` and `etc/entities.conf` aren't touched.
- **Source install:** `git pull && ./install.sh /Volumes/Onion`.

## Configure via the web UI (recommended)

After first boot, open the **MQTT Reporter** app from the Apps menu. You'll
see a help screen, press **A** for a QR code carrying the on-device config
URL (e.g. `http://192.168.1.42:8088`).

- **Scan the QR with your phone**, or type the URL on any device on the
  same Wi-Fi. No phone app to install.
- Fill in **broker host, port, user, password, publish interval, device id**.
- Hit **Save** — the daemon restarts and starts publishing within seconds.

Once you're connected, the same UI also lets you:

- Watch live broker / daemon status (last publish age, entity count, IP).
- **Toggle the daemon on/off** without touching the device.
- **Pick which entities are published** — uncheck any of the 73 entities
  and they're removed from Home Assistant on the next save.
- Switch between **dark and light themes**.

<p align="center">
  <img src="https://raw.githubusercontent.com/hudsonbrendon/miyoo-mqtt-reporter/main/assets/web-ui.png" alt="On-device web config UI" width="720" />
</p>

> Prefer to edit files directly? You can still set everything by editing
> `App/MQTTReporter/etc/mqtt.conf` on the SD card. See
> [Configuration reference](#configuration-reference) for the keys.

## Configuration reference

The web UI is the recommended path. This is for headless / scripted
setups where you'd rather pre-edit the conf file on the SD card.

`App/MQTTReporter/etc/mqtt.conf` keys:

| Key             | Default          | Purpose                                   |
| --------------- | ---------------- | ----------------------------------------- |
| `MQTT_HOST`     | `192.168.1.10`   | Broker IP (LAN address, **not** mDNS)     |
| `MQTT_PORT`     | `1883`           | Broker port                               |
| `MQTT_USER`     | _empty_          | Username (blank for anonymous)            |
| `MQTT_PASS`     | _empty_          | Password                                  |
| `INTERVAL`      | `10`             | Seconds between state publishes           |
| `DEVICE_ID`     | `miyoominiplus`  | Stable identifier (HA topic prefix)       |
| `KEEPALIVE`     | `60`             | Passed to `mosquitto_pub -k`              |

Restrict published entities by dropping one entity key per line into
`App/MQTTReporter/etc/entities.conf` before deploying (matches what the
web UI writes). Missing or empty file = all 73 entities.

### MQTT topics

| Topic                                                     | Retained | Payload                          |
| --------------------------------------------------------- | -------- | -------------------------------- |
| `miyoo/<device_id>/state`                                 | no       | full JSON, one per `INTERVAL`    |
| `miyoo/<device_id>/availability`                          | yes      | `online` / `offline`             |
| `homeassistant/sensor/<device_id>_<key>/config`           | yes      | HA Discovery config per sensor   |
| `homeassistant/binary_sensor/<device_id>_<key>/config`    | yes      | HA Discovery config per binary   |

Missing values come through as `null`. HA value templates handle this.

## Limitations

- **Use LAN IP for the broker.** The Miyoo has no mDNS resolver —
  `homeassistant.local` will not resolve.
- **`mute` / `brightness` / `theme` can be stale.** OnionOS only persists
  `system.json` when MainUI saves (power-off, returning home). No
  workaround on this hardware. Volume is read live via a separate keypress
  watcher and stays current.
- **LWT only on graceful stop.** A hard power-off leaves HA showing the
  device online until the broker timeout. Set `expire_after` on the
  availability sensor in HA as a workaround.
- **Single device profile.** Hardcoded for the Mini Plus
  (Sigmastar SSD202D + AXP223). Other models may need different paths.

## Troubleshooting

| Symptom                                              | Where to look                                                              |
| ---------------------------------------------------- | -------------------------------------------------------------------------- |
| Entities never appear in HA                          | `mosquitto_sub -h <broker> -t 'miyoo/#' -v` — anything landing?            |
| Entities appear as `Unknown`                         | Discovery configs are retained — check `homeassistant/sensor/...` traffic  |
| `daemon.log` shows `Unable to connect (Lookup error.)` | `MQTT_HOST` is mDNS / unresolved. Use the LAN IP.                          |
| Battery shows `Unknown`                              | `/tmp/percBat` not populated yet (just booted). Wait one cycle.            |
| Volume frozen at last-saved value                    | `vol-watcher.log` should show writes to `/tmp/live_vol`.                   |
| Status shows `running=0` after boot                  | Tail `state/daemon.log` — usually a config or auth error.                  |

### SSH access for debugging

SSH is off by default on OnionOS. Enable it in **Tweaks → Network → SSH**.
Then:

```sh
# tail logs
ssh root@<miyoo-ip> tail -f /mnt/SDCARD/App/MQTTReporter/state/daemon.log

# manually publish one sample
ssh root@<miyoo-ip> sh -c '
  cd /mnt/SDCARD/App/MQTTReporter
  . scripts/lib.sh; . scripts/collectors.sh; . scripts/discovery.sh; . scripts/daemon.sh
  load_config etc/mqtt.conf
  DEVICE_ID="$(device_id)"
  build_state_payload "" /proc/meminfo /proc/loadavg
'
```

## Development

```sh
# unit tests (POSIX host, no device required)
for t in tests/test_*.sh; do echo "=== $t ==="; sh "$t" || exit 1; done

# integration test (needs mosquitto installed locally)
sh tests/test_integration.sh

# static analysis (must stay silent)
shellcheck -s sh \
    App/MQTTReporter/scripts/*.sh \
    App/MQTTReporter/launch.sh \
    App/MQTTReporter/www/cgi-bin/* \
    boot/startup/mqttreporter.sh \
    install.sh
```

Conventions:

- **POSIX `sh` targeting BusyBox `ash`** — no bashisms (no `[[`, `$'...'`, arrays).
- Every public function in `collectors.sh` / `discovery.sh` has a
  fixture-driven shunit2 test under `tests/`. Never read real `/proc`
  in tests.
- Miyoo-specific functions are suffixed `_miyoo` and only fire when the
  device's signature files exist (e.g. `/tmp/percBat`). The generic
  variants stay testable on any Linux / macOS dev host.
- Conventional Commits: `feat(collectors): ...`, `fix(daemon): ...`.

Internals — boot hook flow, AXP register map, glibc 2.28 binary
constraint, FAT32 symlink handling — are documented in
[`CLAUDE.md`](CLAUDE.md).

## Credits

- **[OnionOS](https://onionui.github.io/)** — the firmware that makes this possible.
- **[Eclipse Mosquitto](https://mosquitto.org/)** — `mosquitto_pub` does the MQTT.
- **[Home Assistant](https://www.home-assistant.io/)** — for MQTT Discovery.
- **[libqrencode](https://fukuchi.org/works/qrencode/)** — on-device QR code.
- **[shunit2](https://github.com/kward/shunit2)** — vendored at v2.1.8.
