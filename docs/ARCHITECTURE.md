# Menu Pulse architecture

Menu Pulse is one Objective-C/AppKit executable with no third-party code. It
runs as a menu bar accessory (no Dock icon) and samples only the metrics that are
turned on. This page describes how the pieces fit together; `AGENTS.md` covers
how to build, test, and prepare changes.

## Components

| File | Responsibility |
| --- | --- |
| `main.m` | Creates `NSApplication` and `MPMenuPulse`, then runs the event loop. `MENU_PULSE_DISABLE_LOGIN_ITEM_MIGRATION=1` turns off the legacy login-item migration for test and benchmark builds. |
| `MenuPulse.m` | `MPMenuPulse` coordinates the app: the status item, sampling, pausing, the tooltip, Settings, and Open at login. It is also the application delegate, so opening the app again shows Settings. |
| `RefreshScheduler.m` | One dispatch timer on the main queue decides which metrics are due. |
| `Monitors.m` | CPU, memory, and disk readings, plus small pure helpers that the tests check directly. |
| `TemperatureReader.m` | Reads temperature sensors through the IOKit HID event system on a background queue. |
| `SettingsStore.m` | Settings in `NSUserDefaults`, with validation and Reset Defaults. |
| `SettingsWindowController.m` | The programmatic Settings window and confirmation alerts. |
| `LoginItemManager.m` | Open at login through `SMAppService`, and migration from the LaunchAgent used by v1.0. |

## Sampling

`MPRefreshScheduler` keeps a deadline for each metric and arms a single one-shot
timer for the earliest one. The timer leeway is 10% of the delay, between 0.1
and 5 seconds, so macOS can group wake-ups.

- CPU and RAM share an interval (1, 3, or 10 seconds) and are always sampled on
  the same wake-up. CPU needs two readings, so the first value arrives one second
  after a fresh baseline.
- Temperature (1 to 60 seconds) is paused while a read is in flight. A failed read
  defers the next attempt by five minutes, and turning the metric off and on does
  not skip that wait.
- Disk (1 to 10 minutes) reads the home volume's capacity on the main thread.

Monitoring stops while every display is asleep or another user's session is
active. Pausing clears the cached values, and resuming rebuilds the CPU
baseline, so the first values do not include the paused time.

## Metrics

- **CPU**: `host_statistics(HOST_CPU_LOAD_INFO)` tick deltas between two
  readings, handling 32-bit counter wraparound.
- **RAM**: app, wired, and compressed pages from `host_statistics64` as a share
  of physical memory.
- **TEMP**: the hottest value among HID temperature services (usage page 0xff00,
  usage 5). Battery gauges and PMU `tcal` calibration channels are ignored, and
  sensors that report impossible values are skipped until the next sensor
  refresh. Reads run on a utility-QoS serial queue; a generation counter discards
  results that arrive after temperature was turned off or monitoring paused.
- **DISK**: total capacity and the larger of the volume's free space and
  "important usage" capacity, which counts purgeable space as available like
  Finder.

## Menu bar and Settings

The status item shows a template image drawn on demand, so it stays sharp on
every display. The text uses an 11-point monospaced font and fixed-width values,
so the item does not change width as numbers change. One or two metrics appear
one per line; with three or four, CPU and RAM form the left column and TEMP and
DISK the right. The tooltip and accessibility value carry the details.

The Settings window is built in code and sized to fit its controls. Its frame is
saved under `MenuPulseSettings`, and it handles ⌘W and Esc itself because the
app has no main menu. Closing it releases the window controller. First-launch and
approval alerts run from the main run loop rather than from a main-queue block,
so a modal alert does not stop the refresh timer.

## Open at login

When the user turns Open at login on or off, `MPLoginItemManager` registers or
unregisters `SMAppService.mainAppService` on a private serial queue and reports
completion on the main run loop. `MPMenuPulse` numbers each request so an older
completion cannot overwrite a newer one. At launch, when the app runs from
`/Applications` or `~/Applications`, the manager also replaces a LaunchAgent
left by v1.0 with the modern login item; that check runs synchronously.

## Stored data

Settings live in the `dev.hyunseop.MenuPulse` defaults domain: the four show
flags, three refresh intervals, the temperature unit, whether the first-launch
prompt was answered, and positions saved by AppKit for the Settings window and
the menu bar item. The app keeps no history and makes no network requests; the
release link opens in the browser only when clicked.

## Build and release

The `Makefile` compiles every source in one `clang` invocation, signs the bundle
ad hoc, and packages a DMG. CI runs `make check` on pull requests and on pushes
to `main`.
A push to `main` that carries a new version also tags it and publishes the DMG
and release notes; the steps live in `.github/workflows/`.
