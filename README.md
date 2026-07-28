# Menu Pulse

<p align="center">
  <img src="Packaging/AppIcon.png" alt="Menu Pulse icon" width="96">
</p>

[한국어 README](README.ko.md)

This is not a full monitoring dashboard. It is a small menu bar app for checking only the numbers you actually need.

By default it shows `CPU` and `RAM`. You can also enable `HOT` (the hottest available sensor) and `DISK`.

```text
CPU: 12%    HOT: 52°C
RAM: 63%    DISK: 87%
```

Menu Pulse is built for **Apple Silicon Macs running macOS 13 or later**, with **core metrics** and **low resource usage** as the main idea.


## Download

[Download latest DMG](https://github.com/hyunseop827/menu-pulse/releases/latest/download/MenuPulse.dmg)

Download the DMG and checksum file into the same directory, then verify the release:

```zsh
curl -LO https://github.com/hyunseop827/menu-pulse/releases/latest/download/MenuPulse.dmg
curl -LO https://github.com/hyunseop827/menu-pulse/releases/latest/download/SHA256SUMS.txt
shasum -a 256 -c SHA256SUMS.txt
```

`MenuPulse.dmg: OK` means the downloaded file matches the published checksum.

This app is not notarized by Apple yet, so macOS may show a warning on first launch.
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
- `HOT`: optional, off by default, Celsius/Fahrenheit
- `DISK`: optional, off by default

RAM is calculated close to Activity Monitor's `Memory Used`: app memory + wired memory + compressed memory.

Each temperature refresh compares every available IOHID sensor. If IOHID fails, it compares every supported SMC key.
The hottest valid reading is shown as `HOT`. It is not guaranteed on every device combination.
If no temperature can be read, it is shown as `HOT:--°C`.

Default refresh intervals:

```text
CPU  10s
RAM  10s
HOT  30s
DISK 300s
```

Refresh intervals are fixed to keep behavior simple and lightweight.

## Low Resource Intent

Menu Pulse is not trying to be a feature-heavy monitoring app. It is for checking small menu bar numbers with as little overhead as possible.

- Native Objective-C/AppKit app
- No Electron, web view, or charts
- No history storage or dashboard
- No Dock icon while running
- Only reads the metrics you enable
- Does not read temperature sensors when `HOT` is off
- Uses one lightweight timer to refresh only what is due
- Uses the native macOS login item API

If you want to benchmark it yourself:

```sh
Scripts/measure.sh
```

## Development

### Project Structure

```text
Sources/MenuPulse/
  main.m
  MenuPulse.m
  Monitors.m
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
  release.sh

Tests/
  MonitorTests.m
```

### Scripts

| Script | Use it for |
| --- | --- |
| `Scripts/build-app.sh` | Builds the Objective-C source into `build/release/Menu Pulse.app`. Use it for local development checks. |
| `Scripts/build-dmg.sh` | Rebuilds the app and creates `dist/MenuPulse.dmg`. Use it to check the distributable file. |
| `Scripts/install.sh` | Installs the app to `~/Applications` and registers it to open at login. macOS may require approval. |
| `Scripts/uninstall.sh` | Removes the installed app and the login auto-start setting. |
| `Scripts/measure.sh` | Runs the app briefly and measures CPU, memory usage, app size, and DMG size. |
| `Scripts/test.sh` | Checks monitor ranges, CPU reset behavior, and Mach host port reference leaks. |
| `Scripts/release.sh` | Takes a version, updates `Info.plist`, builds the DMG, commits, tags, and pushes. |
