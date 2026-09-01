# Menu Pulse

<p align="center">
  <img src="Packaging/AppIcon.png" alt="Menu Pulse icon" width="96">
</p>

[한국어 README](README.ko.md)

A small native menu bar app for checking CPU, memory, temperature, and disk usage without a dashboard or history.

**Apple Silicon · macOS 13 or later**

## Screenshots

<p align="center">
  <img src="menupulse-menubar.png" alt="Menu Pulse menu bar" width="292">
  <br>
  <img src="menupulse-setting.png" alt="Menu Pulse settings" width="480">
</p>

## Download

[Download the latest DMG](https://github.com/hyunseop827/menu-pulse/releases/latest/download/MenuPulse.dmg)

Verify the download with the published checksum:

```zsh
curl -LO https://github.com/hyunseop827/menu-pulse/releases/latest/download/MenuPulse.dmg
curl -LO https://github.com/hyunseop827/menu-pulse/releases/latest/download/SHA256SUMS.txt
shasum -a 256 -c SHA256SUMS.txt
```

This low-cost build is ad-hoc signed and not notarized. After checksum verification, move it to `/Applications`, then right-click it in Finder and choose `Open`. If macOS still blocks it:

```zsh
sudo xattr -dr com.apple.quarantine "/Applications/Menu Pulse.app"
open "/Applications/Menu Pulse.app"
```

## Features

| Metric | Default | Refresh choices |
| --- | --- | --- |
| CPU | On | 1s, 3s, 10s — default 3s |
| RAM | On | Shares the CPU interval |
| TEMP | Off | 1s, 3s, 10s, 30s, 60s — default 30s |
| DISK | Off | 1m, 3m, 5m, 10m — default 5m |

TEMP supports Celsius and Fahrenheit and shows the hottest available sensor. DISK shows usage of the home volume.

The settings window also provides Open at Login, Reset Defaults, Close, and Quit. Reset and Quit require confirmation. A new direct launch asks about Open at Login once; the repository installer enables it automatically.

## Lightweight and private

- Native Objective-C/AppKit; no Electron, web view, chart, or Dock icon
- One monotonic one-shot timer; only enabled metrics are read
- No network requests, telemetry, crash-reporting SDK, history, or metric log
- Stores only display choices, refresh intervals, temperature unit, and the one-time login prompt marker

Measured on an M1 MacBook Air with 16GB RAM and a 256GB SSD over five minutes:

| Scenario | Average CPU | Private dirty |
| --- | ---: | ---: |
| Default CPU + RAM, 3s | 0.065% | 9.8MB |
| All metrics at shortest intervals | 0.613% | 10.3MB |

The fastest scenario exceeded the intended 0.5% CPU target but stayed below the 15MB private dirty target.
The 1-second TEMP option performs the most sensor work and is best used for short checks.

## Complete removal

From this repository, run:

```sh
Scripts/uninstall.sh
```

It verifies the bundle identifier and removes both installation locations, login items, preferences, cache, saved state, dedicated logs, and matching diagnostics.

## Development

```sh
Scripts/build-app.sh   # Build the app
Scripts/test.sh        # Run all tests
Scripts/analyze.sh     # Run Clang static analysis
```

## License

[MIT](LICENSE) — use, modify, and distribute freely; provided as-is without warranty.
