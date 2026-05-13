# Fix Unknown Sensors (Game/Core/Temperature) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `running_game`, `emulator_core`, and `temperature` report real values in Home Assistant instead of `Unknown`. All three were shipped in commit `8d954e3` but the underlying readers are looking at the wrong paths or wrong format.

**Architecture:** Three independent fixes in `collectors.sh`, all unit-testable against fixture files:
1. The Onion command file lives at `/mnt/SDCARD/.tmp_update/cmd_to_run.sh`, not `/tmp/cmd_to_run.sh`. Path was wrong since day one — `read_running_game_miyoo` returns empty.
2. Onion's `cmd_to_run.sh` is **not** a RetroArch invocation. It calls a per-emulator launcher: `LD_PRELOAD=... "/mnt/SDCARD/Emu/<CORE>/launch.sh" "/mnt/SDCARD/Roms/<CORE>/<rom>.<ext>"`. The current `parse_retroarch_cmd` only matches `-L <core>_libretro.so` and silently returns empty for every emulator.
3. `/sys/class/thermal/thermal_zone0/temp` does not exist on Miyoo Mini Plus (the Allwinner V3s kernel doesn't expose a thermal zone there). The temperature is available on the AXP223 PMU at register `5Eh`. Need a Miyoo-specific reader; the generic path-based reader stays for portability.

**Tech Stack:** POSIX shell, BusyBox `ash`, shunit2 (vendored). Same conventions as the rest of the repo — see [CLAUDE.md](../../../CLAUDE.md).

---

## File Structure

```
App/MQTTReporter/scripts/
├── collectors.sh                      # 1 path fix, 1 parser rewrite, 1 new fn
└── daemon.sh                          # 1 new override line in bootstrap

tests/
├── fixtures/
│   ├── cmd-to-run-onion-gg.sh         # NEW — Onion's Emu/<core>/launch.sh format
│   ├── cmd-to-run-retroarch.sh        # NEW — keep legacy retroarch format covered
│   └── axp-reg-5e-temp.txt            # NEW — AXP223 die-temp register
└── test_collectors.sh                 # +5 tests
```

Notes on decomposition:
- The existing `cmd-to-run-gba.sh` fixture is *retroarch* format. It is renamed to `cmd-to-run-retroarch.sh` to make the format explicit, since both formats now exist in production.
- `parse_retroarch_cmd` is renamed to `parse_onion_cmd` because it now handles both formats. Tests that mention the old name must be updated.
- `read_temperature` (generic, fixture-tested, takes a path) stays unchanged. `read_temperature_miyoo` is added alongside, following the same `_miyoo` suffix convention as battery/volume.

---

### Task 1: Add fixtures for the two cmd_to_run formats + AXP temp register

**Files:**
- Rename: `tests/fixtures/cmd-to-run-gba.sh` → `tests/fixtures/cmd-to-run-retroarch.sh`
- Create: `tests/fixtures/cmd-to-run-onion-gg.sh`
- Create: `tests/fixtures/axp-reg-5e-temp.txt`

- [ ] **Step 1: Rename the existing fixture (the only test using it will be updated in Task 2)**

```bash
git mv tests/fixtures/cmd-to-run-gba.sh tests/fixtures/cmd-to-run-retroarch.sh
```

- [ ] **Step 2: Create the Onion `Emu/<core>/launch.sh` fixture** (real content captured from the user's SD)

```bash
cat > tests/fixtures/cmd-to-run-onion-gg.sh <<'EOF'
LD_PRELOAD=/mnt/SDCARD/miyoo/app/../lib/libpadsp.so  "/mnt/SDCARD/Emu/GG/launch.sh" "/mnt/SDCARD/Roms/GG/Shinobi.zip"
EOF
```

- [ ] **Step 3: Create the AXP register-5E fixture**

```bash
cat > tests/fixtures/axp-reg-5e-temp.txt <<'EOF'
Read /dev/i2c-1-34 reg 5e, read value:8c
EOF
```

`0x8c` = 140 decimal. With the AXP223 formula `temp_°C = raw × 0.1 − 144.7`, that resolves to `−130.7 °C` — clearly wrong. The real AXP223 die-temp reading is a 12-bit value spread across two registers (`5Eh` high 8 bits, `5Fh` low 4 bits). A more realistic raw value for ~35 °C is `1797` → `(0x705)`, i.e. `5E=0x70`, `5F=0x05`. Use that instead:

```bash
cat > tests/fixtures/axp-reg-5e-temp.txt <<'EOF'
Read /dev/i2c-1-34 reg 5e, read value:70
EOF
cat > tests/fixtures/axp-reg-5f-temp.txt <<'EOF'
Read /dev/i2c-1-34 reg 5f, read value:05
EOF
```

- [ ] **Step 4: Commit**

```bash
git add tests/fixtures/cmd-to-run-retroarch.sh tests/fixtures/cmd-to-run-onion-gg.sh tests/fixtures/axp-reg-5e-temp.txt tests/fixtures/axp-reg-5f-temp.txt
git commit -m "test: add fixtures for Onion cmd_to_run format + AXP die-temp regs"
```

---

### Task 2: Rewrite `parse_retroarch_cmd` → `parse_onion_cmd` (TDD)

**Files:**
- Modify: `tests/test_collectors.sh:90-120` (the two retroarch tests)
- Modify: `App/MQTTReporter/scripts/collectors.sh:69-83` (parser body)

- [ ] **Step 1: Update the existing failing tests + add coverage for the Onion format**

Open `tests/test_collectors.sh`, replace the two `testParseRetroarchCmd...` tests with these four. The first two cover the legacy retroarch format (now via the renamed fixture), the second two cover Onion's per-emulator format.

```sh
testParseOnionCmdRetroarchFormatExtractsCoreAndGame() {
    . "$COL"
    out="$(parse_onion_cmd < "$FIX/cmd-to-run-retroarch.sh")"
    assertEquals "mgba|Pokemon FireRed" "$out"
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
```

- [ ] **Step 2: Run tests to verify they fail (old function name + missing logic)**

```bash
sh tests/test_collectors.sh 2>&1 | tail -10
```

Expected: 4 failures referring to `parse_onion_cmd: command not found` (plus the original `testParseRetroarchCmd*` tests now missing).

- [ ] **Step 3: Replace `parse_retroarch_cmd` in `collectors.sh`**

Open `App/MQTTReporter/scripts/collectors.sh`. Find the existing function (the comment block starts with `# parse_retroarch_cmd`). Replace it with:

```sh
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
    core="$(printf '%s' "$line" | sed -n 's|.*/\([^/_ ]*\)_libretro\.so.*|\1|p' | head -1)"
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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
sh tests/test_collectors.sh 2>&1 | tail -5
```

Expected: `Ran 25 tests. OK` (was 23, +4 new -2 removed = +2 net; but recount precisely from the output).

- [ ] **Step 5: Shellcheck**

```bash
shellcheck -s sh App/MQTTReporter/scripts/collectors.sh tests/test_collectors.sh
```

Expected: silent.

- [ ] **Step 6: Commit**

```bash
git add App/MQTTReporter/scripts/collectors.sh tests/test_collectors.sh
git commit -m "fix(collectors): parse_onion_cmd handles both retroarch + Emu launcher formats"
```

---

### Task 3: Fix `read_running_game_miyoo` path (TDD)

**Files:**
- Modify: `App/MQTTReporter/scripts/collectors.sh` (function `read_running_game_miyoo`)

The function currently reads `/tmp/cmd_to_run.sh` which doesn't exist on Miyoo. The real path is `/mnt/SDCARD/.tmp_update/cmd_to_run.sh` (verified by reading the user's SD and by `grep -n cmd_to_run runtime.sh` showing `$sysdir/cmd_to_run.sh` with `sysdir=/mnt/SDCARD/.tmp_update`).

No test fixture change needed — the function is a thin shell over `parse_onion_cmd` (already tested in Task 2). A simple "function returns empty when path absent" test confirms the fallback.

- [ ] **Step 1: Add a guard-clause test**

Append to `tests/test_collectors.sh` (before the final `. "$SCRIPT_DIR/shunit2"` line):

```sh
testReadRunningGameMiyooReturnsEmptyWhenCmdFileAbsent() {
    . "$COL"
    # The function reads a hardcoded device path. On the dev host that path
    # does not exist, so the function must return empty silently.
    out="$(read_running_game_miyoo 2>/dev/null)"
    assertEquals "" "$out"
}
```

- [ ] **Step 2: Run tests — new test passes already because parser still sees no file; the BUG is the *path*, fixed below**

```bash
sh tests/test_collectors.sh -- testReadRunningGameMiyooReturnsEmptyWhenCmdFileAbsent
```

Expected: PASS (one test, OK).

- [ ] **Step 3: Fix the path in `read_running_game_miyoo`**

Open `App/MQTTReporter/scripts/collectors.sh`. Find the function (search for `read_running_game_miyoo`). Replace it with:

```sh
# read_running_game_miyoo
# Onion writes /mnt/SDCARD/.tmp_update/cmd_to_run.sh whenever it launches a
# ROM (retroarch direct or per-emulator launcher). Format is handled by
# parse_onion_cmd. Echoes "<core>|<rom_basename>" or empty.
read_running_game_miyoo() {
    local f=/mnt/SDCARD/.tmp_update/cmd_to_run.sh
    [ -r "$f" ] || return 0
    parse_onion_cmd < "$f"
}
```

(Diff vs. current: `f=/tmp/cmd_to_run.sh` → `f=/mnt/SDCARD/.tmp_update/cmd_to_run.sh`, and the call site `parse_retroarch_cmd` → `parse_onion_cmd`.)

- [ ] **Step 4: Run the full collector suite**

```bash
sh tests/test_collectors.sh 2>&1 | tail -5
```

Expected: `Ran 26 tests. OK`.

- [ ] **Step 5: Shellcheck**

```bash
shellcheck -s sh App/MQTTReporter/scripts/collectors.sh tests/test_collectors.sh
```

Expected: silent.

- [ ] **Step 6: Commit**

```bash
git add App/MQTTReporter/scripts/collectors.sh tests/test_collectors.sh
git commit -m "fix(collectors): correct cmd_to_run.sh path to /mnt/SDCARD/.tmp_update/"
```

---

### Task 4: Add `read_temperature_miyoo` reading AXP223 die-temp (TDD)

**Files:**
- Modify: `App/MQTTReporter/scripts/collectors.sh` (append new function)
- Modify: `tests/test_collectors.sh` (append parser test using fixture)

The Miyoo Mini Plus has no `/sys/class/thermal/thermal_zone*` (verified empirically — the probe `find /sys -name 'thermal*'` returned nothing). The AXP223 PMU exposes its internal die temperature at registers `5Eh:5Fh` (12 bits, formula `raw × 0.1 °C − 144.7`).

The reader has to test in isolation, so split it: `parse_axp_temp` consumes two `axp` outputs (hi reg, lo reg) from stdin (one per line) and computes the °C value. `read_temperature_miyoo` wires that to the live `axp` binary.

- [ ] **Step 1: Add a fixture that combines both register dumps in one file**

```bash
cat > tests/fixtures/axp-temp-pair.txt <<'EOF'
Read /dev/i2c-1-34 reg 5e, read value:70
Read /dev/i2c-1-34 reg 5f, read value:05
EOF
```

`0x70` = 112, `0x05` = 5. 12-bit raw = `(112 << 4) | (5 & 0x0F)` = `1797`.
Temperature = `1797 × 0.1 − 144.7` = `179.7 − 144.7` = `35.0 °C`.

- [ ] **Step 2: Write the failing test**

Append to `tests/test_collectors.sh` (before `. "$SCRIPT_DIR/shunit2"`):

```sh
testParseAxpTempPairComputesCelsius() {
    . "$COL"
    out="$(parse_axp_temp < "$FIX/axp-temp-pair.txt")"
    # 0x70<<4 | 0x05&0x0F = 1797, * 0.1 - 144.7 = 35
    assertEquals "35" "$out"
}

testParseAxpTempEmptyOnGarbage() {
    . "$COL"
    out="$(printf 'nothing here\n' | parse_axp_temp)"
    assertEquals "" "$out"
}
```

- [ ] **Step 3: Run — should fail (function not defined)**

```bash
sh tests/test_collectors.sh -- testParseAxpTempPairComputesCelsius
```

Expected: FAIL `parse_axp_temp: command not found`.

- [ ] **Step 4: Implement `parse_axp_temp` and `read_temperature_miyoo`**

Append to `App/MQTTReporter/scripts/collectors.sh`:

```sh
# parse_axp_temp
# Reads two `axp` register dumps from stdin (hi byte then lo byte for AXP223
# die-temp registers 5Eh:5Fh). Echoes integer °C, or empty on parse failure.
# Formula: temp_°C = ((hi << 4) | (lo & 0x0F)) * 0.1 - 144.7
parse_axp_temp() {
    local hi lo raw
    hi="$(sed -n '1{s/.*read value:\([0-9a-fA-F][0-9a-fA-F]*\).*/\1/p;}')"
    lo="$(sed -n '2{s/.*read value:\([0-9a-fA-F][0-9a-fA-F]*\).*/\1/p;}')"
    [ -n "$hi" ] && [ -n "$lo" ] || return 0
    raw=$(( (0x${hi} << 4) | (0x${lo} & 0x0F) ))
    awk -v r="$raw" 'BEGIN { printf "%d", r * 0.1 - 144.7 }'
}

# read_temperature_miyoo
# Echoes AXP223 die temperature in integer °C. Empty if `axp` is absent
# or either register read fails.
read_temperature_miyoo() {
    command -v axp >/dev/null 2>&1 || return 0
    { axp 5E 2>/dev/null; axp 5F 2>/dev/null; } | parse_axp_temp
}
```

Note: `parse_axp_temp` uses `sed -n '1{...}' / '2{...}'` to read separate lines from a *seekable* stdin. When chained from `{ axp 5E; axp 5F; }` it works because each `axp` call writes a single line. The fixture file has the same two-line format.

The function feeds stdin **once** through two separate `sed -n` invocations. POSIX `sh` re-reads stdin for each subshell, so we need to read the input ONCE and split:

Replace the implementation with this version that reads stdin once:

```sh
parse_axp_temp() {
    local input hi lo raw
    input="$(cat)"
    hi="$(printf '%s\n' "$input" | sed -n '1s/.*read value:\([0-9a-fA-F][0-9a-fA-F]*\).*/\1/p')"
    lo="$(printf '%s\n' "$input" | sed -n '2s/.*read value:\([0-9a-fA-F][0-9a-fA-F]*\).*/\1/p')"
    [ -n "$hi" ] && [ -n "$lo" ] || return 0
    raw=$(( (0x${hi} << 4) | (0x${lo} & 0x0F) ))
    awk -v r="$raw" 'BEGIN { printf "%d", r * 0.1 - 144.7 }'
}
```

- [ ] **Step 5: Run tests**

```bash
sh tests/test_collectors.sh 2>&1 | tail -5
```

Expected: `Ran 28 tests. OK`.

- [ ] **Step 6: Shellcheck**

```bash
shellcheck -s sh App/MQTTReporter/scripts/collectors.sh tests/test_collectors.sh
```

Expected: silent.

- [ ] **Step 7: Commit**

```bash
git add App/MQTTReporter/scripts/collectors.sh tests/test_collectors.sh tests/fixtures/axp-temp-pair.txt tests/fixtures/axp-reg-5e-temp.txt tests/fixtures/axp-reg-5f-temp.txt
git commit -m "feat(collectors): read_temperature_miyoo via AXP223 die-temp regs 5E:5F"
```

---

### Task 5: Wire the Miyoo temperature override in daemon.sh

**Files:**
- Modify: `App/MQTTReporter/scripts/daemon.sh` (executed-directly bootstrap block)

The bootstrap currently overrides `read_battery` and `read_volume` based on signature files. Add a third override that points `read_temperature` (called via fixed path in `build_state_payload`) to `read_temperature_miyoo` when the `axp` binary is on PATH.

Also: `build_state_payload` calls `read_temperature /sys/class/thermal/thermal_zone0/temp`. On the device, that file doesn't exist, so without an override the result is empty (which is why HA shows Unknown). The override sidesteps the path entirely.

- [ ] **Step 1: Read the current bootstrap to confirm context**

```bash
sed -n '/if \[ "\${0##\*\/}" = "daemon.sh" \]/,/^fi/p' App/MQTTReporter/scripts/daemon.sh
```

Expected output contains the current `read_battery` and `read_volume` overrides.

- [ ] **Step 2: Add the temperature override**

Open `App/MQTTReporter/scripts/daemon.sh`. Find the override block (search for `read_battery_miyoo`). Insert this immediately after the existing battery override:

```sh
    if command -v axp >/dev/null 2>&1; then
        # shellcheck disable=SC2317
        read_temperature() { read_temperature_miyoo; }
    fi
```

The block should now look like:

```sh
    # Miyoo overrides: detect platform-specific data sources at runtime.
    if [ -r /tmp/percBat ]; then
        read_battery() { read_battery_miyoo; }
    fi
    if command -v axp >/dev/null 2>&1; then
        # shellcheck disable=SC2317
        read_temperature() { read_temperature_miyoo; }
    fi
    if ls /mnt/SDCARD/.tmp_update/config/system/*.json >/dev/null 2>&1; then
        read_volume() { read_volume_miyoo; }
    fi
```

- [ ] **Step 3: `build_state_payload` already calls `read_temperature` with the fixed sysfs path** — no change needed there, the override swallows the argument.

Confirm by inspecting:

```bash
grep -n 'read_temperature' App/MQTTReporter/scripts/daemon.sh
```

Expected: at least one call inside `build_state_payload` passing the sysfs path. The override discards the arg, which is fine (the function ignores positional parameters).

- [ ] **Step 4: Run full test suite — no regressions**

```bash
for t in tests/test_*.sh; do echo "=== $t ==="; sh "$t" 2>&1 | tail -3; done
```

Expected: 4 suites all OK. `test_daemon.sh` may now show 5 tests passing including the build_state_payload ones — temperature shows up as `null` on the dev host (no axp binary) which the JSON encoder handles via `_j_num`.

- [ ] **Step 5: Shellcheck**

```bash
shellcheck -s sh App/MQTTReporter/scripts/daemon.sh
```

Expected: silent.

- [ ] **Step 6: Commit**

```bash
git add App/MQTTReporter/scripts/daemon.sh
git commit -m "fix(daemon): override read_temperature with AXP-based reader on device"
```

---

### Task 6: Deploy + verify on hardware

This is a manual verification task — no automated tests on hardware.

- [ ] **Step 1: Confirm SD is mounted at `/Volumes/Onion`**

```bash
ls -d /Volumes/Onion
```

Expected: prints `/Volumes/Onion`. If not, ask the user to plug the SD into the Mac and retry.

- [ ] **Step 2: Re-deploy**

```bash
./install.sh /Volumes/Onion
```

Expected last lines:
```
Done. Next steps:
  1. Pre-edit ...
  ...
```

`install.sh` will `rsync -aL --delete --exclude '/etc/mqtt.conf'` — broker creds preserved, scripts overwritten with the fixed versions.

- [ ] **Step 3: Truncate the old daemon.log so we read only fresh output**

```bash
: > /Volumes/Onion/App/MQTTReporter/state/daemon.log
```

- [ ] **Step 4: Eject**

```bash
diskutil unmount /Volumes/Onion
```

Expected: `Volume Onion on disk4s1 unmounted`.

- [ ] **Step 5: User powers on the Miyoo and launches a ROM**

Instruct the user:

1. Plug the SD back into the Miyoo.
2. Boot.
3. **Do NOT open** the MQTT Reporter app from the Apps menu (toggle trap).
4. Launch any ROM (Game Gear / GBA / SNES / etc).
5. Wait ~15 seconds.
6. Check Home Assistant → Settings → Devices → MQTT → the Miyoo device.

Expected:
- `Miyoo Running Game` shows the ROM filename without extension (e.g. `Shinobi`).
- `Miyoo Emulator Core` shows the Emu folder name (e.g. `GG`, `GBA`).
- `Miyoo Temperature` shows a plausible value (20-50 °C typical).

- [ ] **Step 6: If anything is still wrong, pull SD and read the log**

```bash
ls -d /Volumes/Onion || echo "Ask the user to plug the SD back into the Mac."
tail -30 /Volumes/Onion/App/MQTTReporter/state/daemon.log
```

Specific log signatures and what they mean:

| Log line                                      | Diagnosis                                                                    |
| --------------------------------------------- | ---------------------------------------------------------------------------- |
| `axp: not found` (or no temperature output)   | `PATH` issue in startup hook — `axp` lives in `/mnt/SDCARD/.tmp_update/bin/`. |
| `temperature: -5` or negative                 | AXP223 formula calibration: register layout may differ from datasheet. Capture `axp 5E` and `axp 5F` raw output and adjust the formula in `parse_axp_temp`. |
| `game: null, core: null` while a ROM runs     | Verify `cat /mnt/SDCARD/.tmp_update/cmd_to_run.sh` matches one of the two known formats. If not, capture the new format and extend `parse_onion_cmd`. |

- [ ] **Step 7: This task does not commit anything — verification only.**

---

## Self-Review

**Spec coverage**
- Running Game shows Unknown → Task 2 (parser) + Task 3 (path). ✔
- Emulator Core shows Unknown → same tasks, same parser output (the `<core>` half). ✔
- Temperature shows Unknown → Task 4 (`read_temperature_miyoo`) + Task 5 (daemon override). ✔
- User suspicion that these don't update in real-time → only partially correct. The daemon polls every 10s; the readers will pick up changes on the next cycle. The actual bugs are *path / format wrong*, not *timing*. The verification step in Task 6 confirms by asking the user to launch a ROM and wait ~15s.

**Placeholder scan** — none found. Every step has full code blocks, exact paths, exact commands, exact expected output.

**Type / name consistency**
- `parse_onion_cmd` replaces `parse_retroarch_cmd`. Both the function definition (Task 2) and the only caller `read_running_game_miyoo` (Task 3) are updated.
- `parse_axp_temp` and `read_temperature_miyoo` are introduced in Task 4 and the override referencing `read_temperature_miyoo` is added in Task 5 — names match.
- Fixture renames: `cmd-to-run-gba.sh → cmd-to-run-retroarch.sh` (Task 1) is reflected in the rewritten test in Task 2.

**Known calibration risk** — Task 4 uses the published AXP223 datasheet formula (`raw × 0.1 − 144.7`). If real-device output is off by a constant, Task 6 step 6 captures the raw values so the engineer can adjust the multiplier/offset in `parse_axp_temp`. No need for a separate plan iteration.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-13-fix-unknown-sensors.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
