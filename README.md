# Menu Pulse

<p align="center">
  <img src="Packaging/AppIcon.png" alt="Menu Pulse icon" width="96">
</p>

[한국어 README](README.ko.md)

This is not a full monitoring dashboard. It is a small menu bar app for checking only the numbers you actually need.

By default it shows `CPU` and `RAM`. You can also enable `TEMP` (temperature) and `DISK`.

```text
CPU: 12%    TEMP: 52°C
RAM: 63%    DISK: 87%
```

Menu Pulse is built for **Apple Silicon Macs running macOS 13 or later**, with **core metrics** and **low resource usage** as the main idea.

## Screenshots

<p align="center">
  <img src="menupulse-menubar.png" alt="Menu Pulse menu bar showing CPU, RAM, TEMP, and DISK" width="292">
</p>
<p align="center"><sub>Menu bar monitoring</sub></p>

<p align="center">
  <img src="menupulse-setting.png" alt="Menu Pulse metric, refresh interval, and login item settings window" width="600">
</p>
<p align="center"><sub>Simple metric, refresh interval, and login settings</sub></p>

## Download

[Download latest DMG](https://github.com/hyunseop827/menu-pulse/releases/latest/download/MenuPulse.dmg)

Download the DMG and checksum file into the same directory, then verify the release:

```zsh
curl -LO https://github.com/hyunseop827/menu-pulse/releases/latest/download/MenuPulse.dmg
curl -LO https://github.com/hyunseop827/menu-pulse/releases/latest/download/SHA256SUMS.txt
shasum -a 256 -c SHA256SUMS.txt
```

`MenuPulse.dmg: OK` means the downloaded file matches the published checksum.

To keep distribution costs low, this build uses an ad-hoc signature instead of a Developer ID and is not notarized by Apple.
The signature alone cannot authenticate the distributor, and macOS may show a warning on first launch.
Move the app to `/Applications`, then right-click it in Finder and choose `Open`.
If macOS still blocks it and checksum verification succeeded, you can run:

```zsh
sudo xattr -dr com.apple.quarantine "/Applications/Menu Pulse.app"
open "/Applications/Menu Pulse.app"
```

## License

MIT License.

You can use, modify, and distribute it freely. The app is provided as-is, without warranty.

See [LICENSE](LICENSE) for details.

## Features

- `CPU`: on by default
- `RAM`: on by default
- `TEMP`: optional, off by default, Celsius/Fahrenheit, `1` to `60` seconds
- `DISK`: optional, off by default, `1` to `10` minutes
- CPU/RAM refresh: `1`, `3`, or `10` seconds; `3` seconds by default
- One-time Open at Login choice on a new launch; the repository installer enables it directly
- Confirmed Reset Defaults and Quit actions; Close hides only the settings window

RAM is calculated close to Activity Monitor's `Memory Used`: app memory + wired memory + compressed memory.

Each temperature refresh compares every available IOHID sensor. If IOHID fails, it compares every supported SMC key.
The hottest valid reading is shown as `TEMP`. It is not guaranteed on every device combination.
If no temperature can be read, it is shown as `TEMP:--°C`.

Refresh intervals:

```text
CPU + RAM  3s by default (select 1s, 3s, or 10s)
TEMP      30s by default (select 1s, 3s, 10s, 30s, or 60s)
DISK       5m by default (select 1m, 3m, 5m, or 10m)
```

For example, keep the 3-second default for everyday use. Select 1 second only when you want to watch a short build more closely.
Faster temperature updates can use more energy, so the 30-second default is better for normal use.

## Low Resource Intent

Menu Pulse is not trying to be a feature-heavy monitoring app. It is for checking small menu bar numbers with as little overhead as possible.

- Native Objective-C/AppKit app
- No Electron, web view, or charts
- No history storage or dashboard
- No Dock icon while running
- Only reads the metrics you enable
- Does not read temperature sensors when `TEMP` is off
- Uses one monotonic, one-shot timer to refresh only what is due
- Uses the native macOS login item API

### Measured Benchmark

Measured with Menu Pulse `1.3.0` on September 1, 2026.

- MacBook Air with an 8-core Apple M1
- 16GB memory and 256GB SSD
- macOS 26.6.2
- 30-second warm-up after launch
- 300 samples over 5 minutes at 1-second intervals per scenario

| Enabled metrics | CPU/RAM | TEMP | DISK | CPU average | CPU maximum | RSS average | RSS maximum | Private dirty |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| CPU + RAM (default) | 3s | Off | Off | 0.065% | 1.000% | 37.2MB | 37.3MB | 9.8MB |
| TEMP only | Off | 1s | Off | 0.273% | 1.500% | 40.0MB | 40.6MB | 12.4MB |
| DISK only | Off | Off | 1m | 0.000% | 0.100% | 37.4MB | 37.5MB | 9.8MB |
| CPU + RAM + TEMP + DISK (fastest) | 1s | 1s | 1m | 0.613% | 2.300% | 38.3MB | 38.3MB | 10.3MB |

- Installed app size: approximately 660KB
- Release DMG size: approximately 966KB

RSS includes shared system frameworks used by the app.
For example, the default configuration reported 37.2MB RSS, while private dirty memory, which is closer to app-specific changed memory, was 9.8MB.
The CPU maximum is a short burst while metrics refresh.
Results can vary with other running processes and the macOS cache state.

The 3-second default met the targets of 0.2% average CPU and 12MB private dirty memory.
The fastest combination met the 15MB private dirty target, but its 0.613% average CPU did not meet the intended 0.5% target.
A local profile identified 1-second IOHID temperature sensor reads as the dominant active work. TEMP is off by default, and the 1-second choice is intended for short checks.

To reproduce all four isolated scenarios without changing the installed app or persistent settings, run:

```sh
# Default CPU/RAM
WARMUP=30 DURATION=300 INTERVAL=1 SHOW_CPU=1 SHOW_RAM=1 SHOW_TEMPERATURE=0 SHOW_DISK=0 CPU_RAM_REFRESH_INTERVAL=3 Scripts/measure.sh

# TEMP only
WARMUP=30 DURATION=300 INTERVAL=1 SHOW_CPU=0 SHOW_RAM=0 SHOW_TEMPERATURE=1 SHOW_DISK=0 TEMPERATURE_REFRESH_INTERVAL=1 Scripts/measure.sh

# DISK only
WARMUP=30 DURATION=300 INTERVAL=1 SHOW_CPU=0 SHOW_RAM=0 SHOW_TEMPERATURE=0 SHOW_DISK=1 DISK_REFRESH_INTERVAL=60 Scripts/measure.sh

# Fastest combination
WARMUP=30 DURATION=300 INTERVAL=1 SHOW_CPU=1 SHOW_RAM=1 SHOW_TEMPERATURE=1 SHOW_DISK=1 CPU_RAM_REFRESH_INTERVAL=1 TEMPERATURE_REFRESH_INTERVAL=1 DISK_REFRESH_INTERVAL=60 Scripts/measure.sh
```

The script removes its temporary preferences, raw process samples, and app log when it exits.

## Privacy and complete removal

Menu Pulse does not send network requests. It has no telemetry, crash reporting SDK, measurement history, or metric log.

It stores only local preferences for enabled metrics, temperature unit, the three refresh intervals, and whether the one-time Open at Login question was answered. The actual login item state remains managed by macOS. macOS may also store the menu bar position, login item registration, cache, saved window state, and OS-generated crash diagnostics.

To remove both possible app copies and all Menu Pulse-specific local data, run from this repository:

```sh
Scripts/uninstall.sh
```

The script removes `/Applications/Menu Pulse.app`, `~/Applications/Menu Pulse.app`, the modern login item, the legacy LaunchAgent, `dev.hyunseop.MenuPulse` preferences, cache, saved state, dedicated logs, and matching macOS diagnostic reports. Diagnostic cleanup is limited to `MenuPulse` or the exact bundle-ID prefix with `.ips`, `.crash`, `.diag`, `.hang`, or `.spin` in `DiagnosticReports` and its `Retired` directory. It verifies the exact bundle identifier before deleting an app.
If it cannot inspect a previous app location, it stops instead of falsely reporting that a stale login item was removed.

## Development

### Project Structure

```text
Sources/MenuPulse/
  main.m
  MenuPulse.m
  SettingsWindowController.m
  Monitors.m
  RefreshScheduler.m
  SettingsStore.m
  TemperatureReader.m
  LoginItemManager.m

Packaging/
  Info.plist
  AppIcon.icns

Scripts/
  build-app.sh
  build-dmg.sh
  install.sh
  uninstall.sh
  measure.sh
  analyze.sh
  release.sh
  verify-release.sh

Tests/
  MonitorTests.m
  MemoryUserDefaults.m
  SettingsSchedulerTests.m
  MenuPulseUITests.m
  LifecycleScriptTests.sh
```

### Scripts

| Script | Use it for |
| --- | --- |
| `Scripts/build-app.sh` | Builds the Objective-C source into `build/release/Menu Pulse.app`. Use it for local development checks. |
| `Scripts/build-dmg.sh` | Rebuilds the app and creates `dist/MenuPulse.dmg`. Use it to check the distributable file. |
| `Scripts/install.sh` | Safely replaces the app in `/Applications`, removes an exact duplicate, and registers it to open at login. |
| `Scripts/uninstall.sh` | Removes both app locations, login items, settings, cache, saved state, and dedicated logs. |
| `Scripts/measure.sh` | Runs an isolated benchmark process and measures CPU, memory, app size, and DMG size. |
| `Scripts/analyze.sh` | Runs Clang static analysis for every Objective-C source file. |
| `Scripts/test.sh` | Runs monitor, settings/scheduler, UI/accessibility, and lifecycle tests. |
| `Scripts/release.sh` | Verifies `main == origin/main`, builds, tags, pushes, waits for publishing, and verifies downloaded assets. |
| `Scripts/verify-release.sh` | Downloads a GitHub Release again and verifies its SHA-256 checksum and DMG. |
