# Menu Pulse

<p align="center">
  <img src="Packaging/AppIcon.png" alt="Menu Pulse icon" width="96">
</p>

[한국어 README](README.ko.md)

A compact CPU and RAM readout for your Mac's menu bar. Temperature and disk usage are optional.

<p align="center">
  <img src="menupulse-menubar.png" alt="Menu Pulse default CPU and RAM readout" width="136">
</p>

## Download

**[Download the latest DMG](https://github.com/hyunseop827/menu-pulse/releases/latest/download/MenuPulse.dmg)** · Free · Apple Silicon · macOS 13 or later

Open the DMG and drag **Menu Pulse** to **Applications**. To update, quit the existing app and replace it with the app from the new DMG. You do not need to clone or keep this repository to use the app.

**The app is ad-hoc signed and not notarized by Apple.** If macOS blocks the first launch, use **System Settings → Privacy & Security → Open Anyway** after trying to open it. See [Apple's instructions](https://support.apple.com/guide/mac-help/mh40616/mac).

See the [release notes](https://github.com/hyunseop827/menu-pulse/releases) for changes in each version.

<details>
<summary>Verify the download checksum</summary>

```zsh
curl -LO https://github.com/hyunseop827/menu-pulse/releases/latest/download/MenuPulse.dmg
curl -LO https://github.com/hyunseop827/menu-pulse/releases/latest/download/SHA256SUMS.txt
shasum -a 256 -c SHA256SUMS.txt
```

</details>

## Features

| Metric | Default | Refresh choices |
| --- | --- | --- |
| CPU | On | 1s, 3s, 10s — default 3s |
| RAM | On | Shares the CPU interval |
| TEMP | Off | 1s, 3s, 10s, 30s, 60s — default 30s |
| DISK | Off | 1m, 3m, 5m, 10m — default 5m |

TEMP supports Celsius and Fahrenheit and shows the hottest sensor the app can read. Sensor availability varies by Mac and macOS version; a failed read shows `--` and is retried after five minutes. Hover over the menu bar item for TEMP status. DISK shows usage of the home volume.

Settings shows the installed version and a link to the latest GitHub release. First launch asks about Open at Login once; you can change it in settings. **Reset Defaults restores the metric defaults and turns Open at Login on.** Reset and Quit require confirmation; quitting preserves your login setting.

<details>
<summary>Settings screenshot</summary>

<p align="center">
  <img src="menupulse-setting.png" alt="Menu Pulse settings" width="480">
</p>

</details>

## Resource use and privacy

- Native Objective-C/AppKit; no Electron, web view, chart, or Dock icon
- One timer reads only enabled metrics; periodic reads pause while displays are asleep
- No background network requests, telemetry, crash-reporting SDK, history, or metric log; the release link opens in your browser when clicked
- Stores only display choices, refresh intervals, temperature unit, and the one-time login prompt marker

Resource use depends on your Mac, macOS version, enabled metrics, and refresh intervals. The 1-second TEMP option performs the most sensor work and is best used for short checks. See [Benchmark](#benchmark) to measure a specific checkout with its test conditions recorded.

## Removal

Turn off **Open at Login** in the app's settings, choose **Quit**, then move `/Applications/Menu Pulse.app` to Trash.

## Development

```sh
make app      # Build the app in build/release
make check    # Check syntax, metadata, static analysis, tests, and the app
make dmg      # Create dist/MenuPulse.dmg and SHA256SUMS.txt
```

Xcode Command Line Tools are required. Building and testing do not install the app or register login items. Test executables run in a temporary directory and are removed afterward.

<details>
<summary>Clean up login items from older development builds</summary>

If an older development run left `MenuPulseUITests` or a deleted app in automatic startup, remove it under **System Settings → General → Login Items & Extensions → Open at Login**. Deleting repository files does not unregister existing login items.

</details>

## Benchmark

Requires Xcode Command Line Tools. The script builds and measures the current checkout with a separate app identifier; it does not measure the downloaded release DMG.

```sh
# Defaults: CPU + RAM every 3s; 30s warm-up + 5-minute measurement
Scripts/benchmark.sh

# All metrics at their shortest intervals
ALL_METRICS=1 CPU_RAM_REFRESH_INTERVAL=1 TEMPERATURE_REFRESH_INTERVAL=1 \
  DISK_REFRESH_INTERVAL=60 Scripts/benchmark.sh
```

Keep the display awake while measuring. Each run saves a report with its test conditions and raw output in a new `build/benchmarks/run-…/` directory:

- `report.txt`: build, machine, and sampling conditions; result summary
- `samples.txt`: CPU and RSS samples from `ps`
- `vmmap.txt`: final memory reading, when available
- `app.log`: output from the measured app

Set `RESULTS_DIR` to choose a different parent directory. For a short script check, use `WARMUP=0 DURATION=10 Scripts/benchmark.sh`; use longer, repeated runs for comparisons.

CPU results summarize `ps` readings, which are decaying averages over up to a minute, not independent one-second measurements. RSS and Private dirty are different memory measures, reported separately in MiB; Private dirty is not total memory use. Compare results only with matching hardware, macOS, enabled metrics, and refresh intervals.

The temporary build, isolated preferences, and measured process are cleaned up on exit; the results remain. The benchmark does not share the installed app's preferences or login registration.

## License

[MIT](LICENSE) — use, modify, and distribute freely; provided as-is without warranty.
