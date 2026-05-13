<div align="center">

```
   ___ ___   ___   ___    .------.
  |   v   | |   | |   |  /        \    M Q T T   R E P O R T E R
  |       |_|   |_|   | /  .----.  \   ─────────────────────────
  |_|_|_|_|_|_|_|_|_|_| (   |  ()|   )    OnionOS  ·  Miyoo Mini Plus
                        \  '----'  /          ↓
       Home Assistant    \        /     [battery] [vol] [ram] [cpu]
       ─── MQTT ───        '------'           via MQTT Discovery
```

**`miyoo-mqtt-reporter`** — a tiny POSIX-shell plugin for [OnionOS](https://onionui.github.io/)
that publishes your handheld's system metrics to Home Assistant in real time.

[![Platform](https://img.shields.io/badge/platform-OnionOS-1e293b?style=flat-square)](https://onionui.github.io/)
[![Device](https://img.shields.io/badge/device-Miyoo%20Mini%20Plus-38bdf8?style=flat-square)](https://lemiyoo.cn/)
[![Shell](https://img.shields.io/badge/shell-POSIX%20sh-yellow?style=flat-square)](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html)
[![MQTT](https://img.shields.io/badge/MQTT-Discovery-660198?style=flat-square)](https://www.home-assistant.io/integrations/mqtt/#mqtt-discovery)
[![Tests](https://img.shields.io/badge/tests-27%20unit%20+%201%20integration-success?style=flat-square)](#development)
[![ShellCheck](https://img.shields.io/badge/shellcheck-clean-success?style=flat-square)](https://www.shellcheck.net/)

</div>

---

## What it does

Every `INTERVAL` seconds (default 30s) the daemon reads four metrics from `/proc` and `/sys`,
packs them into a compact JSON state message, and publishes to your MQTT broker.
Home Assistant picks them up automatically through **MQTT Discovery** — no `configuration.yaml`
edits, no manual sensor wiring.

| Entity                 | Source                                    | HA type         |
| ---------------------- | ----------------------------------------- | --------------- |
| **Battery %**          | `/sys/class/power_supply/<bat>/capacity`  | `sensor`        |
| **Charging on/off**    | `/sys/class/power_supply/<bat>/status`    | `binary_sensor` |
| **Volume %**           | `amixer sget Master`                      | `sensor`        |
| **RAM used %**         | `/proc/meminfo` (MemTotal vs MemAvailable)| `sensor`        |
| **CPU load (1 min)**   | `/proc/loadavg`                           | `sensor`        |

```
                    ┌─────────────────────────────────────────┐
                    │           Miyoo Mini Plus               │
                    │     ┌──────────────────────────┐        │
                    │     │   collectors.sh          │        │
   /proc  ────▶─────┼─▶   │   ├ read_battery         │        │
   /sys   ────▶─────┼─▶   │   ├ read_volume          │        │
   amixer ────▶─────┼─▶   │   ├ read_ram             │        │
                    │     │   └ read_cpu             │        │
                    │     └──────────┬───────────────┘        │
                    │                ▼                        │
                    │     ┌──────────────────────────┐        │
                    │     │   daemon.sh main loop    │        │
                    │     │   build_state_payload    │        │
                    │     └──────────┬───────────────┘        │
                    │                ▼                        │
                    │     ┌──────────────────────────┐        │
                    │     │   mqtt_publish wrapper   │        │
                    │     └──────────┬───────────────┘        │
                    └────────────────┼────────────────────────┘
                                     ▼
                          ┌──────────────────────┐
                          │   mosquitto_pub      │ ─── TCP ───┐
                          │   (vendored ARMv7)   │            │
                          └──────────────────────┘            │
                                                              ▼
                                                  ┌─────────────────────┐
                                                  │  MQTT Broker        │
                                                  │  (Mosquitto / EMQX) │
                                                  └──────────┬──────────┘
                                                             ▼
                                                  ┌─────────────────────┐
                                                  │   Home Assistant    │
                                                  │   ├ MQTT Discovery  │
                                                  │   └ 5 entities auto │
                                                  └─────────────────────┘
```

## Requirements

**Hardware**
- Miyoo Mini Plus running [OnionOS](https://onionui.github.io/) **≥ 4.3**
- Wi-Fi connected to the same network as your MQTT broker

**Software (target device)**
- BusyBox `ash` (ships with OnionOS)
- `amixer` (ships with OnionOS)
- `mosquitto_pub` ARMv7 binary — **vendored as a placeholder**, you must drop in the real one
  (see [Installation step 2](#2-drop-in-the-armv7-mosquitto_pub-binary))

**Server side**
- Any MQTT broker (Mosquitto / EMQX / HiveMQ / HA's built-in add-on)
- Home Assistant **2023.4+** with the MQTT integration configured

**Dev host (only if you want to hack on it)**
- POSIX `sh`, `shellcheck`, `mosquitto` + `mosquitto-clients` for integration tests

## Installation

### 1. Clone the repo on your dev machine

```sh
git clone https://github.com/hudsonbrendon/miyoo-mqtt-reporter.git
cd miyoo-mqtt-reporter
```

### 2. Drop in the ARMv7 `mosquitto_pub` binary

OnionOS does not ship Mosquitto clients. The repo contains a **placeholder** at
`App/MQTTReporter/bin/mosquitto_pub` that exits 127 — replace it with a real ARMv7 binary.

The easiest path on a Debian/Ubuntu workstation:

```sh
mkdir -p /tmp/mqv && cd /tmp/mqv
apt-get download mosquitto-clients:armhf libmosquitto1:armhf
dpkg-deb -x ./mosquitto-clients_*.deb extracted/
dpkg-deb -x ./libmosquitto1_*.deb extracted/

# Back to the repo:
cd -
cp /tmp/mqv/extracted/usr/bin/mosquitto_pub                                  App/MQTTReporter/bin/
cp /tmp/mqv/extracted/usr/lib/arm-linux-gnueabihf/libmosquitto.so.*          App/MQTTReporter/lib/
chmod +x App/MQTTReporter/bin/mosquitto_pub
file App/MQTTReporter/bin/mosquitto_pub
#  expected: ELF 32-bit LSB executable, ARM, EABI5, ...
```

Other options (Onion buildroot, extracting from existing community plugins) are documented in
`App/MQTTReporter/bin/SOURCE.txt`.

### 3. Pre-configure (optional, you can do this on the device too)

```sh
cp App/MQTTReporter/etc/mqtt.conf.example App/MQTTReporter/etc/mqtt.conf
$EDITOR App/MQTTReporter/etc/mqtt.conf
```

See [Configuration](#configuration) for all keys.

### 4. Deploy to SD card

Plug the Miyoo SD card into your computer, then run:

```sh
./install.sh /Volumes/MIYOO        # macOS
./install.sh /media/$USER/MIYOO    # Linux
```

The installer:

1. Validates that `<SD_MOUNT>/.tmp_update/` exists (sanity check that it's an OnionOS card)
2. `rsync`s `App/MQTTReporter/` to `<SD>/App/MQTTReporter/`
3. Installs `boot/runtime.sh.user` to `<SD>/.tmp_update/runtime.sh.user`
   - If a user runtime hook already exists, our block is appended (not overwritten)
4. Ensures everything is executable

### 5. First run

1. Eject the SD card, slot it in the Miyoo, boot.
2. Go to **Apps → MQTT Reporter** in the launcher.
3. If this is the first run and you skipped step 3 above, the app will copy
   `mqtt.conf.example` → `mqtt.conf` and ask you to edit it. SSH into the device
   (or pop the SD back out) and fill in `MQTT_HOST`, `MQTT_USER`, `MQTT_PASS`.
4. Open the app again. You should see:
   ```
   MQTT Reporter: ON (enabled=1 running=1)
   ```
5. Home Assistant → **Settings → Devices & Services → MQTT → Devices** —
   a new device "**Miyoo Mini Plus (miyoo-<mac>)**" appears with 5 entities.

The daemon **autostarts on every boot** while the enabled flag is set. Open the
app again to toggle it off.

## Configuration

`App/MQTTReporter/etc/mqtt.conf` keys (defaults in parens):

| Key             | Default                  | Purpose                                                   |
| --------------- | ------------------------ | --------------------------------------------------------- |
| `MQTT_HOST`     | `homeassistant.local`    | Broker hostname or IP                                     |
| `MQTT_PORT`     | `1883`                   | Broker port                                               |
| `MQTT_USER`     | _empty_                  | Username (leave blank for anonymous)                      |
| `MQTT_PASS`     | _empty_                  | Password                                                  |
| `INTERVAL`      | `30`                     | Seconds between state publishes                           |
| `DEVICE_ID`     | _derived from wlan0 MAC_ | Override identifier (e.g. `miyoo-couch`)                  |
| `BATTERY_PATH`  | _auto-detected_          | Override `/sys/class/power_supply/<name>` path            |
| `KEEPALIVE`     | `60`                     | Passed to `mosquitto_pub -k`                              |

Values are sourced via POSIX `.` — if you put shell expressions in there, they'll be evaluated.
Trust boundary: the file lives on your SD card, owned by you.

### MQTT topics

| Topic                                                       | Retained | Payload                                                    |
| ----------------------------------------------------------- | -------- | ---------------------------------------------------------- |
| `miyoo/<device_id>/state`                                   | no       | `{"battery":90,"charging":"ON","volume":73,"ram":51,"cpu":0.42}` |
| `miyoo/<device_id>/availability`                            | yes      | `online` / `offline`                                       |
| `homeassistant/sensor/<device_id>_battery/config`           | yes      | HA Discovery config                                        |
| `homeassistant/sensor/<device_id>_volume/config`            | yes      | HA Discovery config                                        |
| `homeassistant/sensor/<device_id>_ram/config`               | yes      | HA Discovery config                                        |
| `homeassistant/sensor/<device_id>_cpu/config`               | yes      | HA Discovery config                                        |
| `homeassistant/binary_sensor/<device_id>_charging/config`   | yes      | HA Discovery config                                        |

## Usage

Once installed, the **MQTT Reporter** entry in the OnionOS Apps menu acts as a toggle:

```
┌─────────────────────────────────────┐
│            MQTT Reporter            │
├─────────────────────────────────────┤
│  Status:  enabled=1 running=1       │
│  Press A to toggle ON / OFF         │
└─────────────────────────────────────┘
```

- **First open** → copies `mqtt.conf.example` → `mqtt.conf` and prompts you to edit.
- **Subsequent opens** → toggles the daemon. On boot it autostarts when the
  `state/enabled` flag-file is present.

### From SSH

```sh
# tail logs
tail -f /mnt/SDCARD/App/MQTTReporter/state/daemon.log

# check status
sh /mnt/SDCARD/App/MQTTReporter/scripts/toggle.sh && do_status

# manually publish one state sample (useful for debugging)
. /mnt/SDCARD/App/MQTTReporter/scripts/lib.sh
. /mnt/SDCARD/App/MQTTReporter/scripts/collectors.sh
. /mnt/SDCARD/App/MQTTReporter/scripts/discovery.sh
. /mnt/SDCARD/App/MQTTReporter/scripts/daemon.sh
load_config /mnt/SDCARD/App/MQTTReporter/etc/mqtt.conf
DEVICE_ID="$(device_id)"
build_state_payload "$(detect_battery_path /sys/class/power_supply)" /proc/meminfo /proc/loadavg
```

## Development

### Repository layout

```
.
├── App/MQTTReporter/             # Deployable OnionOS app bundle
│   ├── config.json               # OnionOS manifest (label / icon / launch)
│   ├── launch.sh                 # Menu entrypoint (toggle + first-run config)
│   ├── icon.png                  # 200×200 menu icon
│   ├── bin/
│   │   ├── mosquitto_pub         # placeholder → replace with real ARMv7 binary
│   │   └── SOURCE.txt            # 3 ways to acquire the real binary
│   ├── lib/                      # for libmosquitto.so.* if your build is dynamic
│   ├── etc/
│   │   └── mqtt.conf.example     # config template
│   └── scripts/
│       ├── lib.sh                # logging, load_config, mqtt_publish
│       ├── collectors.sh         # read_battery / read_volume / read_ram / read_cpu / detect_battery_path
│       ├── discovery.sh          # device_id, state_topic, availability_topic, _emit, publish_discovery
│       ├── daemon.sh             # build_state_payload + daemon_main loop + LWT
│       └── toggle.sh             # do_start / do_stop / do_status / do_toggle
├── boot/
│   └── runtime.sh.user           # OnionOS boot hook (auto-start if enabled flag)
├── tests/
│   ├── shunit2                   # v2.1.8 vendored
│   ├── fixtures/                 # sysfs / procfs / amixer snapshots
│   ├── test_lib.sh               # 9 tests
│   ├── test_collectors.sh        # 11 tests
│   ├── test_discovery.sh         # 5 tests
│   ├── test_daemon.sh            # 2 tests
│   └── test_integration.sh       # end-to-end against local mosquitto
├── install.sh                    # deploy to a mounted SD card
├── .shellcheckrc
└── .gitignore
```

### Running the tests

Unit tests run on any POSIX host:

```sh
for t in tests/test_*.sh; do echo "=== $t ==="; sh "$t" || exit 1; done
```

Expected: **4 suites · 27 tests · all OK**.

The integration test spins up a real `mosquitto` broker on port 11883:

```sh
# install once
brew install mosquitto                 # macOS
sudo apt install mosquitto mosquitto-clients   # Debian/Ubuntu

sh tests/test_integration.sh
# expected: "Integration test: OK"
```

### Static analysis

```sh
shellcheck -s sh \
    App/MQTTReporter/scripts/*.sh \
    App/MQTTReporter/launch.sh \
    boot/runtime.sh.user \
    install.sh
# expected: silent (exit 0)
```

### Project conventions

- **POSIX `sh` targeting BusyBox `ash`** — no bashisms (no `[[`, `$'...'`, arrays).
- **`local` keyword** is allowed (BusyBox `ash` supports it). `.shellcheckrc` already disables `SC3043`.
- Every public function has a behavioral shunit2 test using fixture dirs (no real `/proc` / `/sys`).
- Pipe-delimited multi-value returns: `read_battery` echoes `<pct>|<charging:bool>` etc.
- Collectors return **empty stdout** + **exit 0** on logical absence (missing file, no battery).
  Hard errors are not currently distinguished — see [Limitations](#limitations).

### Adding a new metric

1. Add a parser to `collectors.sh` (e.g. `read_temperature <path>`).
2. Add a fixture under `tests/fixtures/` + a test in `tests/test_collectors.sh` (TDD).
3. Include the value in `build_state_payload` (`daemon.sh`).
4. Add an `_emit` call in `publish_discovery` (`discovery.sh`) with an `mdi:` icon and HA `device_class`.
5. Update the topic table above.

## Limitations

- **No real Last-Will-and-Testament.** The daemon publishes `availability=online` (retained) on
  start and `availability=offline` (retained) only on **graceful** SIGTERM via the toggle.
  A hard power-off leaves HA showing the device as online indefinitely. Workaround: set
  `expire_after` on the availability sensor in HA, or contribute proper `--will-*` flag support
  (`lib.sh::mqtt_publish`).
- **No log rotation.** `state/daemon.log` grows unbounded. SSH in and truncate, or symlink to
  `/tmp` if you don't mind losing it on reboot.
- **Stale PID after crash.** `toggle.sh` checks `kill -0` for liveness, but a recycled PID could
  theoretically match. Not a practical risk on a single-user handheld.
- **Placeholder binary.** Until you drop in a real ARMv7 `mosquitto_pub`, publishes will fail
  silently (the daemon logs "publish failed" and continues).

## Troubleshooting

| Symptom                                          | Check                                                                      |
| ------------------------------------------------ | -------------------------------------------------------------------------- |
| App appears but no entities in HA                | `mosquitto_sub -h <broker> -t 'miyoo/#' -v` — are messages landing?        |
| Entities in HA but `Unknown`                     | Check `mosquitto_sub -h <broker> -t 'homeassistant/#' -v` — Discovery config retained? |
| Daemon "running=0" right after toggle ON         | `tail /mnt/SDCARD/App/MQTTReporter/state/daemon.log` — likely config error |
| `mosquitto_pub: placeholder binary` in logs      | You haven't done [Installation step 2](#2-drop-in-the-armv7-mosquitto_pub-binary) |
| Charging stuck at OFF                            | `cat /sys/class/power_supply/*/type` — is one of them `Battery`? Set `BATTERY_PATH=` manually |
| Volume always empty                              | `amixer sget Master` on the device — does it match the parser regex?       |

## Roadmap

- [ ] Real MQTT LWT via `mosquitto_pub --will-*` flags
- [ ] Log rotation (cap at 1 MB, rotate to `.1`)
- [ ] More metrics: temperature, brightness, WiFi RSSI, current ROM/emulator
- [ ] Idempotent install (markers around the boot hook block)
- [ ] `make` / CI wrapper for shellcheck + tests
- [ ] Pre-built ARMv7 `mosquitto_pub` in releases

## Contributing

PRs welcome. Please:

1. Keep it POSIX `sh` — no bashisms (`shellcheck -s sh` must stay silent).
2. Add a test in `tests/test_*.sh` for any new public function. Use fixture files, not real `/proc`.
3. One concern per file (the split in `App/MQTTReporter/scripts/` mirrors lifecycles, not technical layers).
4. Conventional Commits: `feat(collectors): add read_foo`, `fix(daemon): handle bar`, etc.

## Credits

- **[OnionOS](https://onionui.github.io/)** — the custom firmware that makes this possible.
- **[Eclipse Mosquitto](https://mosquitto.org/)** — `mosquitto_pub` is doing all the actual MQTT work.
- **[Home Assistant](https://www.home-assistant.io/)** — for MQTT Discovery, which turns a JSON message into a real device card.
- **[shunit2](https://github.com/kward/shunit2)** — the unobtrusive POSIX-shell test framework, vendored at v2.1.8.
