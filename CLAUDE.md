# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`miyoo-mqtt-reporter` is a POSIX-shell plugin for OnionOS on the Miyoo Mini Plus
that publishes system metrics (battery, charging, volume, RAM, CPU load) to an
MQTT broker for Home Assistant via MQTT Discovery.

Runtime target is BusyBox `ash` on ARMv7 (Allwinner V3s). Development and tests
run on macOS / Linux with POSIX `sh`.

## Commands

```sh
# Run all unit tests (4 suites, 27 tests)
for t in tests/test_*.sh; do echo "=== $t ==="; sh "$t" || exit 1; done

# Run a single test file
sh tests/test_collectors.sh

# Run a single test case within a file
sh tests/test_collectors.sh -- testReadBatteryReturnsCapacityForDischarging

# Integration test (spins up a local mosquitto broker on :11883)
# Requires: brew install mosquitto  |  apt install mosquitto mosquitto-clients
sh tests/test_integration.sh

# Static analysis — must stay silent before any commit
shellcheck -s sh \
    App/MQTTReporter/scripts/*.sh \
    App/MQTTReporter/launch.sh \
    boot/startup/mqttreporter.sh \
    install.sh

# Deploy to a mounted Miyoo SD card
./install.sh /Volumes/Onion        # macOS
./install.sh /media/$USER/Onion    # Linux
```

There is no build step. The "binaries" in `App/MQTTReporter/bin/` and
`App/MQTTReporter/lib/` are pre-vendored Debian Buster armhf ELFs; rebuilding
is documented in `App/MQTTReporter/bin/SOURCE.txt`.

## Architecture

Everything is sourced shell. Files under `App/MQTTReporter/scripts/` are
*libraries* — they only define functions, no side effects on source. The two
processes that actually run on device are:

```
   .tmp_update/startup/mqttreporter.sh   (OnionOS boot hook)
       │
       ├─ nohup setsid sh vol-watcher.sh &       → /tmp/live_vol
       └─ nohup setsid sh daemon.sh &            → mqtt_publish loop
```

`daemon.sh` has a dual identity: when **sourced** it only exposes
`daemon_main` and the helpers, when **executed** (the `if [ "${0##*/}" = "daemon.sh" ]`
block at the bottom) it sources `lib.sh` / `collectors.sh` / `discovery.sh`,
applies the Miyoo-specific function overrides, and enters `daemon_main`. The
tests rely on the sourced mode (no overrides fire on the dev host).

`daemon_main` flow:

```
load_config (./mqtt.conf via set -a + .)   →  exports MQTT_*, INTERVAL, DEVICE_ID
device_id  (env > wlan0 MAC > "miyoominiplus")
publish_discovery  (5 retained configs, qos=0, retain=true)
_publish_availability "online" (retained)
loop:
    build_state_payload  →  one JSON  →  mqtt_publish state (qos=0, no retain)
    sleep in 1-second slices for prompt SIGTERM response
on signal:
    _publish_availability "offline" (retained)
    rm pidfile
```

`build_state_payload` calls `read_battery / read_volume / read_ram / read_cpu`
(generic, take path args, fixture-testable) and assembles JSON. On the device
the bootstrap block replaces `read_battery` and `read_volume` with their
`_miyoo` siblings; on the dev host the originals run against fixtures.

`vol-watcher.sh` runs alongside Onion's `keymon` reading `/dev/input/event0`
in parallel (kernel evdev supports multiple readers). It tracks
`KEY_VOLUMEUP` (115) and `KEY_VOLUMEDOWN` (114) presses into `/tmp/live_vol`
on a 0-20 OnionOS scale. `read_volume_miyoo` prefers this file over the
stale `system.json`.

State and control:

- `App/MQTTReporter/state/enabled` — presence-flag for autostart. Boot hook
  exits early if absent. Created by `install.sh` and by `do_start` in
  `toggle.sh`; removed by `do_stop` (which is also what `launch.sh` calls if
  the user opens the menu entry while it's running — that's why the README
  tells users not to open the app from the menu).
- `/tmp/mqttreporter.pid` — daemon pidfile, for liveness checks in `toggle.sh`.

## Hardware quirks that drive the code

The Miyoo Mini Plus is **Sigmastar SSD202D** (dual Cortex-A7), NOT Allwinner V3s
as community docs sometimes claim. `/proc/cpuinfo` confirms `Hardware: SStar Soc`.
The `_miyoo`-suffixed collectors exist because this SoC + OnionOS diverge from
generic Linux in ways that matter:

| Concern | Generic Linux | Miyoo Mini Plus |
| --- | --- | --- |
| Battery % | `/sys/class/power_supply/<bat>/capacity` | `/tmp/percBat` (Onion's `batmon`) |
| Charging | `/sys/.../status` reads `Charging` | `axp 0` register, bit `0x4` |
| Power source | (varies) | `axp 0` bit `0x80` ACIN / bit `0x20` VBUS |
| Battery voltage | (varies) | `axp 78h:79h` × 1.1 mV |
| Battery current | (varies) | `axp 7A:7B` (charge) − `axp 7C:7D` (drain), 0.5 mA/LSB |
| Temperature | `/sys/class/thermal/thermal_zone*/temp` | `/sys/devices/system/cpu/cpufreq/temp_out`, format `Temp=NN` (the AXP die-temp regs 5Eh:5Fh exist but the ADC is not enabled) |
| Volume | `amixer sget Master` (`amixer` is absent) | `/dev/input/event0` press counter → `/tmp/live_vol` |
| Brightness / mute / theme | live IPC | only `system.json`, only persisted on MainUI save events (stale) |
| Boot hook | many shapes | `.tmp_update/startup/*.sh` only (NOT `runtime.sh.user`) |
| Filesystem | usually ext4 | FAT32 — symlinks DO NOT survive |
| libc | distro-current | parasyte caps at glibc 2.28 — Bookworm binaries fail with `GLIBC_2.34 not found` |
| DNS | nsswitch + mDNS | no mDNS — broker must be referenced by IP |
| `DEVICE_ID` env | unset | pre-exported as `354` by OnionOS — config must pin a real id |

The `cmd_to_run.sh` file (which carries the currently-launched ROM) lives at
`/mnt/SDCARD/.tmp_update/cmd_to_run.sh` and uses **one of two formats**:
either the RetroArch invocation (`retroarch -L <path>/<core>_libretro.so "<rom>"`)
or Onion's per-emulator launcher (`LD_PRELOAD=... "/mnt/SDCARD/Emu/<CORE>/launch.sh" "<rom>"`).
`parse_onion_cmd` handles both.

## Onion state surfaces the daemon reads

Beyond the hardware concerns above, several useful state lives only in
Onion's userspace — these inform mode detection, playtime tracking, and
the various flag-files surfaced as binary sensors:

- `/mnt/SDCARD/Saves/CurrentProfile/play_activity/play_activity_db.sqlite`
  (new path) or `…/saves/playActivity.db` (legacy) — the SQLite database
  Onion populates with each game session. Schema:
  `rom(id, type, name, file_path, image_path)` +
  `play_activity(rom_id, play_time, created_at)`. Sessions ≤ 60 seconds are
  filtered out by convention (mirrors Onion's own queries).
- `/tmp/.blfOn`, `/tmp/.bgmMute`, `/tmp/.noAutoStart`, `/tmp/.noBatteryWarning`,
  `/tmp/.cpuClockHotkey` — presence-based Onion flag-files. The `_flag_present_on`
  and `_flag_absent_on` helpers in `collectors.sh` convert presence to ON/OFF
  for HA binary sensors. Inverted readers (autostart, battery_warning) flip
  the polarity.
- `/tmp/percBat`, `/tmp/ntp_synced`, `/tmp/state_changed`, `/tmp/.axp_result`,
  `/tmp/screen_resolution` — runtime state Onion daemons write. `batmon`
  owns percBat; MainUI owns the rest.
- `/mnt/SDCARD/.tmp_update/.runGameSwitcher` — flag indicating the
  GameSwitcher is active (used by `detect_current_mode_miyoo`).
- Mode detection mirrors `src/common/system/state.h::check_isXxx` from
  the Onion repo: a `/proc/<pid>/comm` scan combined with the `cmd_to_run.sh`
  presence test. The `proc_exists` helper does the scan in pure shell so the
  function stays tested by sourcing alone.

See [README.md](./README.md#quirks) for the full list with workarounds. Adding
new collectors for hardware-specific data should follow the same pattern: a
generic, path-arg, fixture-tested `read_<x>` plus a hardware-specific
`read_<x>_miyoo` and an entry in the daemon bootstrap override block.

## Project conventions

- POSIX `sh` only — no bashisms (`[[`, `$'...'`, arrays). `local` is
  allowed because the target is BusyBox `ash`; `.shellcheckrc` disables
  `SC3043` for this reason.
- `.shellcheckrc` runs with `enable=all` + narrow disables (`SC2250`,
  `SC2312`, `SC3043`). The shellcheck step must produce no output before
  any commit.
- Tests are shunit2 (vendored at `tests/shunit2`, v2.1.8). Every public
  function in `collectors.sh` / `discovery.sh` / `lib.sh` has a test using
  fixture files under `tests/fixtures/` — *never* real `/proc` or `/sys`.
  Tests must be added before implementation (TDD).
- `mqtt.conf` is gitignored (it holds the broker password). Edit
  `mqtt.conf.example` if conventions or defaults need to change.
- Pre-vendored Debian Buster (10) armhf binaries live in `App/MQTTReporter/`
  `bin/` and `lib/`. Don't replace with Bookworm/Bullseye — they'd require
  glibc the device doesn't have. See `bin/SOURCE.txt` for the rebuild recipe.
- Commit messages follow Conventional Commits with scopes that match the
  module: `feat(collectors): ...`, `fix(daemon): ...`, `docs: ...`.
