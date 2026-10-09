# Menu Pulse

<p align="center">
  <img src="docs/images/app-icon.png" alt="Menu Pulse icon" width="96">
</p>

[한국어 README](README.ko.md)

A compact CPU and RAM readout for your Mac's menu bar. Temperature and disk usage are optional.

<p align="center">
  <img src="docs/images/menubar.png" alt="Menu Pulse default CPU and RAM readout" width="160">
</p>

## Download

**[Download the latest DMG](https://github.com/hyunseop827/menu-pulse/releases/latest/download/MenuPulse.dmg)** · Free · Apple Silicon · macOS 13 or later

Open the DMG and drag **Menu Pulse** to **Applications**. You do not need to clone or keep this repository to use the app.

**The app is ad-hoc signed and not notarized by Apple.** If macOS blocks the first launch, use **System Settings → Privacy & Security → Open Anyway** after trying to open it. See [Apple's instructions](https://support.apple.com/guide/mac-help/mh40616/mac).

See the [release notes](https://github.com/hyunseop827/menu-pulse/releases) for changes in each version.

<details>
<summary>Verify the download checksum</summary>

```zsh
curl -LO https://github.com/hyunseop827/menu-pulse/releases/latest/download/MenuPulse.dmg
curl -LO https://github.com/hyunseop827/menu-pulse/releases/latest/download/SHA256SUMS.txt
shasum -a 256 -c --ignore-missing SHA256SUMS.txt
```

</details>

### Updating

- Click **Check for Updates…** in Settings to check right away. While it is running, Menu Pulse also checks once a day on its own.
- When there is a newer version, it shows what changed and asks. Only when you choose **Install Update** does it download the new version, verify its signature, replace the app, and reopen it. It never installs without asking.
- Keep the app in Applications. An app opened inside the DMG cannot update itself.
- **If you use 1.7.0**, its own **Check for Updates…** installs this version. Versions before 1.7.0 have no updater: replace the app with the one from the new DMG once.

## Features

| Metric | Default | Refresh choices |
| --- | --- | --- |
| CPU | On | 1s, 3s, 10s — default 3s |
| RAM | On | Shares the CPU interval |
| TEMP | Off | 1s, 3s, 10s, 30s, 60s — default 30s |
| DISK | Off | 1m, 3m, 5m, 10m — default 5m |

One or two metrics appear one per line. With three or four, CPU and RAM form the left column and TEMP and DISK the right.

<p align="center">
  <img src="docs/images/menubar-all.png" alt="Menu Pulse showing CPU, RAM, TEMP, and DISK" width="322">
</p>

TEMP supports Celsius and Fahrenheit and shows the hottest component sensor the app can read; battery and calibration sensors are ignored. Sensor availability varies by Mac and macOS version; a failed read shows `--` and is retried every five minutes. DISK shows usage of the home volume and, like Finder, counts purgeable space as available. Hover over the menu bar item for details such as free disk space and TEMP status.

Click the menu bar item to open Settings, which shows the installed version and **Check for Updates…**. If the item is hidden, for example behind the camera notch, open Menu Pulse again from Applications to show Settings. Close Settings with **⌘W** or **Esc**; it reopens where you left it. First launch asks about **Open at login** once; you can change it in Settings. **Reset Defaults restores the metric defaults and turns Open at login on.** Reset and Quit require confirmation; quitting preserves your login setting.

The menu bar item and the Settings window follow the system appearance, light or dark.

<details>
<summary>Settings screenshot</summary>

<p align="center">
  <img src="docs/images/settings.png" alt="Menu Pulse settings" width="480">
</p>

</details>

## Resource use and privacy

- Native Objective-C/AppKit; no Electron, web view, chart, or Dock icon
- One timer reads only enabled metrics; periodic reads pause while displays are asleep or another user's session is active
- No accounts and no usage tracking; no crash-reporting SDK, history, or metric log
- The only thing the app uses the internet for is the update check. Once a day while it is running, and when you choose **Check for Updates…**, it reads the latest release's list of updates (`appcast.xml`) from GitHub. Nothing about your Mac or its readings is sent
- The new version is downloaded from GitHub only when you choose to install it, and it is checked against the signing key (EdDSA) inside the app before it is opened. Updates are handled by [Sparkle](https://sparkle-project.org)
- Stores only display choices, refresh intervals, temperature unit, the Settings window and menu bar item positions, and the one-time login prompt marker. Sparkle keeps a little state in the app's preferences (when it last checked, a skipped version, window positions)

Resource use depends on your Mac, macOS version, enabled metrics, and refresh intervals. The 1-second TEMP option performs the most sensor work and is best used for short checks. See [Benchmark](#benchmark) to measure a specific checkout with its test conditions recorded.

## Removal

Turn off **Open at login** in Settings, click **Quit**, then move `/Applications/Menu Pulse.app` to Trash. To also remove saved settings, run `defaults delete dev.hyunseop.MenuPulse` after quitting.

## Development

```sh
make app      # Build the app in build/release
make check    # Check syntax, metadata, static analysis, tests, and the app
make dmg      # Create the DMGs, the ZIP, and SHA256SUMS.txt in dist
```

Xcode Command Line Tools are required. The first build downloads Sparkle 2.10.0 from its GitHub release, checks it against a pinned SHA-256, and keeps it in `build/sparkle`. Building and testing do not install the app or register login items. Test executables run in a temporary directory and are removed afterward.

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
- `vmmap.txt`: final `vmmap` output, or the reason it was unavailable
- `app.log`: output from the measured app

`SHOW_CPU`, `SHOW_RAM`, `SHOW_TEMPERATURE`, and `SHOW_DISK` (0 or 1) choose metrics individually, and `INTERVAL` sets the seconds between samples (default 1). Set `RESULTS_DIR` to choose a different parent directory. For a short script check, use `WARMUP=0 DURATION=10 Scripts/benchmark.sh`; use longer, repeated runs for comparisons.

CPU results summarize `ps` readings, which are decaying averages over up to a minute, not independent one-second measurements. RSS and Private dirty are different memory measures, reported separately in MiB; Private dirty is not total memory use. Compare results only with matching hardware, macOS, enabled metrics, and refresh intervals.

The temporary build, temporary home folder, and measured process are cleaned up on exit; the results remain. The measured build uses its own bundle identifier, so it does not share the installed app's preferences or login registration.

## AI-assisted development

Menu Pulse is developed with AI coding agents, including Claude Code, under the direction of Hyunseop Kim, who decides what to build and when to ship. The agents follow the project's rules in [`AGENTS.md`](AGENTS.md). See [AI-assisted development](docs/AI_DEVELOPMENT.md) for how changes are made and checked, and [Architecture](docs/ARCHITECTURE.md) for how the app works.

## License

[MIT](LICENSE) — use, modify, and distribute freely; provided as-is without warranty.

Menu Pulse updates itself with [Sparkle](https://github.com/sparkle-project/Sparkle) (MIT); its license ships inside the app as `ThirdPartyNotices.txt`.
