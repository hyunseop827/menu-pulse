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

See the [release notes](https://github.com/hyunseop827/menu-pulse/releases) for changes in each version.

Verify the download with the published checksum:

```zsh
curl -LO https://github.com/hyunseop827/menu-pulse/releases/latest/download/MenuPulse.dmg
curl -LO https://github.com/hyunseop827/menu-pulse/releases/latest/download/SHA256SUMS.txt
shasum -a 256 -c SHA256SUMS.txt
```

Open the DMG and copy the app to `/Applications`. To update, quit the existing app and replace it with the app from the new DMG. The installed app runs independently of this repository.

The app is ad-hoc signed and not notarized. If macOS blocks the first launch, use **System Settings → Privacy & Security → Open Anyway** after trying to open it. See [Apple's instructions](https://support.apple.com/guide/mac-help/mh40616/mac).

## Features

| Metric | Default | Refresh choices |
| --- | --- | --- |
| CPU | On | 1s, 3s, 10s — default 3s |
| RAM | On | Shares the CPU interval |
| TEMP | Off | 1s, 3s, 10s, 30s, 60s — default 30s |
| DISK | Off | 1m, 3m, 5m, 10m — default 5m |

TEMP supports Celsius and Fahrenheit and shows the hottest sensor the app can read. Sensor availability varies by Mac and macOS version; a failed read shows `--` and is retried after five minutes. Hover over the menu bar item for TEMP status. DISK shows usage of the home volume.

Settings shows the installed version and a link to the latest GitHub release. First launch asks about Open at Login once; you can change it in settings. **Reset Defaults restores the metric defaults and turns Open at Login on.** Reset and Quit require confirmation; quitting preserves your login setting.

## Lightweight and private

- Native Objective-C/AppKit; no Electron, web view, chart, or Dock icon
- One timer reads only enabled metrics; periodic reads pause while displays are asleep
- No background network requests, telemetry, crash-reporting SDK, history, or metric log; the release link opens in your browser when clicked
- Stores only display choices, refresh intervals, temperature unit, and the one-time login prompt marker

Historical five-minute measurements on an M1 MacBook Air with 16GB RAM and a 256GB SSD are shown below. The app version and macOS version were not recorded; these are reference values, not measurements of the current code.

| Scenario | Average CPU | Private dirty |
| --- | ---: | ---: |
| Default CPU + RAM, 3s | 0.065% | 9.8MB |
| All metrics at shortest intervals | 0.613% | 10.3MB |

The 1-second TEMP option performs the most sensor work and is best used for short checks.

## Removal

Turn off **Open at Login** in the app's settings, choose **Quit**, then move `/Applications/Menu Pulse.app` to Trash.

If an older development run left `MenuPulseUITests` or a deleted app in automatic startup, remove it under **System Settings → General → Login Items & Extensions → Open at Login**. Deleting repository files does not unregister existing login items.

## Development

```sh
make app      # Build the app in build/release
make check    # Check syntax, metadata, static analysis, tests, and the app
make dmg      # Create dist/MenuPulse.dmg and SHA256SUMS.txt
```

Xcode Command Line Tools are required. Building and testing do not install the app or register login items. Test executables run in a temporary directory and are removed afterward.

## Benchmark

```sh
# Defaults: CPU + RAM every 3s; 30s warm-up + 5-minute measurement
Scripts/benchmark.sh

# All metrics at their shortest intervals
ALL_METRICS=1 CPU_RAM_REFRESH_INTERVAL=1 TEMPERATURE_REFRESH_INTERVAL=1 \
  DISK_REFRESH_INTERVAL=60 Scripts/benchmark.sh
```

Keep the display awake while measuring. Reports average and maximum `ps` CPU/RSS samples and, when available, a final Private dirty reading from `vmmap`. Record the commit and macOS version when comparing results. For a short check, use `WARMUP=0 DURATION=10 Scripts/benchmark.sh`.

Uses a separate app identifier, temporary build, and isolated preferences. The measured process and temporary files are cleaned up on exit. It does not share the installed app's preferences or login registration.

## License

[MIT](LICENSE) — use, modify, and distribute freely; provided as-is without warranty.
