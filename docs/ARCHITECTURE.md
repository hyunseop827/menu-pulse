# Menu Pulse architecture

Menu Pulse is one Objective-C/AppKit executable with no third-party code. It
runs as a menu bar accessory (no Dock icon) and samples only the metrics that are
turned on. This page describes how the pieces fit together; `AGENTS.md` covers
how to build, test, and prepare changes.

## Components

| File | Responsibility |
| --- | --- |
| `main.m` | Creates `NSApplication` and `MPMenuPulse`, then runs the event loop. `MENU_PULSE_DISABLE_LOGIN_ITEM_MIGRATION=1` turns off the legacy login-item migration for test and benchmark builds. After an update, it waits for the replaced copy to quit and then shows Settings. |
| `MenuPulse.m` | `MPMenuPulse` coordinates the app: the status item, sampling, pausing, the tooltip, Settings, and Open at login. It is also the application delegate, so opening the app again shows Settings. |
| `RefreshScheduler.m` | One dispatch timer on the main queue decides which metrics are due. |
| `Monitors.m` | CPU, memory, and disk readings, plus small pure helpers that the tests check directly. |
| `TemperatureReader.m` | Reads temperature sensors through the IOKit HID event system on a background queue. |
| `SettingsStore.m` | Settings in `NSUserDefaults`, with validation and Reset Defaults. |
| `SettingsWindowController.m` | The programmatic Settings window and confirmation alerts. |
| `LoginItemManager.m` | Open at login through `SMAppService`, and migration from the LaunchAgent used by v1.0. |
| `Updater.m` | Check for Updates: reads the latest GitHub release, then downloads, verifies, and installs it. |

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

## Updates

**Check for Updates…** in Settings asks `MPMenuPulse` to run the check; the app
makes no other network requests. `MPUpdater` works on a private serial queue and
reports back on the main run loop, so the alerts that follow do not stop the
refresh timer.

1. It reads `tag_name` from the GitHub API's latest release, which excludes
   drafts and prereleases, and accepts only `vX.Y.Z` tags. A version that is not
   newer than the running one shows **Menu Pulse Is Up to Date**.
2. If the app's folder is read-only or not writable, for example inside the DMG
   or under App Translocation, Settings offers the download page instead.
3. After the user confirms, it downloads `SHA256SUMS.txt` and `MenuPulse.zip`
   from that release, compares the ZIP's SHA-256, and unpacks it with `ditto`
   into a replacement folder on the app's volume.
4. The unpacked app must have the running app's bundle identifier, the expected
   version, a valid code signature, and an `LSMinimumSystemVersion` this Mac
   meets. `NSFileManager` then swaps it into place, so the app's path and name
   stay the same.
5. The new copy is launched with `--relaunch-after-update <pid>`. It waits up to
   ten seconds for the old process to quit before adding its menu bar item, so
   only one item appears and its saved position is kept. The old copy quits
   right after the launch.

The checksum guards against a damaged download. Like a manual download, the
update trusts the GitHub release itself, because the app is signed ad hoc and
has no developer identity to check.

## Stored data

Settings live in the `dev.hyunseop.MenuPulse` defaults domain: the four show
flags, three refresh intervals, the temperature unit, whether the first-launch
prompt was answered, and positions saved by AppKit for the Settings window and
the menu bar item. The app keeps no history and contacts GitHub only when the
user clicks Check for Updates.

## Build and release

The `Makefile` compiles every source in one `clang` invocation, signs the bundle
ad hoc, and packages a DMG along with the ZIP that the updater installs. CI runs
`make check` on pull requests and on pushes to `main`. A push to `main` that
carries a new version also tags it and publishes the DMG, the ZIP, and release
notes; the steps live in `.github/workflows/`.
