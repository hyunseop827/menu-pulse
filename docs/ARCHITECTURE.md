# Menu Pulse architecture

Menu Pulse is one Objective-C/AppKit executable; its only third-party code is
Sparkle, which handles updates. It runs as a menu bar accessory (no Dock icon)
and samples only the metrics that are turned on. This page describes how the
pieces fit together; `AGENTS.md` covers how to build, test, and prepare changes.

## Components

| File | Responsibility |
| --- | --- |
| `main.m` | Creates `NSApplication` and `MPMenuPulse`, then runs the event loop. `MENU_PULSE_DISABLE_LOGIN_ITEM_MIGRATION=1` turns off the legacy login-item migration and `MENU_PULSE_DISABLE_UPDATES=1` keeps Sparkle from starting, for test and benchmark builds. When Menu Pulse 1.7.0's own updater starts the new copy, it waits for the old one to quit and then shows Settings. |
| `MenuPulse.m` | `MPMenuPulse` coordinates the app: the status item, sampling, pausing, the tooltip, Settings, and Open at login. It is also the application delegate, so opening the app again shows Settings. |
| `RefreshScheduler.m` | One dispatch timer on the main queue decides which metrics are due. |
| `Monitors.m` | CPU, memory, and disk readings, plus small pure helpers that the tests check directly. |
| `TemperatureReader.m` | Reads temperature sensors through the IOKit HID event system on a background queue. |
| `SettingsStore.m` | Settings in `NSUserDefaults`, with validation and Reset Defaults. |
| `SettingsWindowController.m` | The programmatic Settings window and confirmation alerts. |
| `LoginItemManager.m` | Open at login through `SMAppService`, and migration from the LaunchAgent used by v1.0. |
| `Updater.m` | `MPUpdater` wraps Sparkle's `SPUStandardUpdaterController`: the daily check, Check for Updates…, and the reminder for an update window hidden behind other apps. It also handles the relaunch argument of 1.7.0's updater. |

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

Sparkle 2 checks `appcast.xml` from the latest GitHub release once a day and
when the user clicks **Check for Updates…**; the app makes no other network
requests. Sparkle starts in `applicationDidFinishLaunching:`, and only when
Info.plist names a feed and an EdDSA public key Sparkle can decode
(`MPUpdaterConfigurationCanStart`); a build without one (such as the
placeholder key) leaves updates off without an alert. The Settings button is disabled until Sparkle starts and while
a check runs (`MPUpdateCheckAvailable`); while an update is on screen, clicking
it brings Sparkle's window forward.

- **Feed and settings**: `Packaging/Info.plist` sets `SUFeedURL`,
  `SUPublicEDKey`, automatic checks on, automatic installation off (the update
  window has no "install automatically" option), and
  `SUVerifyUpdateBeforeExtraction`. The feed has one item: the versioned DMG,
  its `CFBundleVersion` (the CI run number), and the release notes.
- **Trust**: Sparkle checks the DMG's EdDSA signature against `SUPublicEDKey`
  before it opens the image, then requires the new app to be validly signed. It
  does not compare code-signing identities, so one ad-hoc build can replace
  another; the EdDSA key is the only anchor and can never be changed for
  copies already installed.
- **Windows**: Menu Pulse is an accessory app, so Sparkle activates it for
  checks the user starts and right after launch. A scheduled check that finds
  an update later opens the window behind other apps instead of taking focus
  while the user types, and the download and install windows never take focus.
  Until the user first looks at a scheduled update, the tooltip mentions it;
  until Sparkle ends the update session, clicking the menu bar item brings
  Sparkle's window forward instead of opening Settings.
- **Packaging**: the framework sits in `Contents/Frameworks` without its XPC
  services, which only sandboxed apps use. Sparkle's helpers, the framework,
  and the app are signed ad hoc with the hardened runtime, inside out, and the
  app's one entitlement (`com.apple.security.cs.disable-library-validation`)
  lets it load the ad-hoc framework.
- **From 1.7.0**: 1.7.0 has its own updater, which downloads `MenuPulse.zip`
  and `SHA256SUMS.txt`, checks the bundle identifier, version, signature, and
  minimum macOS, swaps the app, and starts it with `--relaunch-after-update
  <pid>`. Releases keep those assets so 1.7.0 copies can reach Sparkle.

## Stored data

Settings live in the `dev.hyunseop.MenuPulse` defaults domain: the four show
flags, three refresh intervals, the temperature unit, whether the first-launch
prompt was answered, and positions saved by AppKit for the Settings window and
the menu bar item. Sparkle adds its own keys there, such as the time of the
last update check. The app keeps no history.

## Build and release

The `Makefile` downloads Sparkle's pinned archive, compiles every source in one
`clang` invocation, embeds and signs the framework and the bundle ad hoc, and
packages the DMGs and the ZIP for 1.7.0's updater. CI runs `make check` on pull
requests and on pushes to `main`. A push to `main` that carries a new version
builds with the run number as `CFBundleVersion`, signs the versioned DMG with
the `SPARKLE_PRIVATE_KEY` secret and writes that EdDSA signature into
`appcast.xml` (`.github/scripts/make-appcast.sh`; the feed itself is not
signed), then tags it and publishes the DMGs, the ZIP, the feed, and the
release notes; the steps live in `.github/workflows/`, and
`.github/scripts/release-plan.py` makes the release decision, including the
check that the update key matches the published releases'. Pull requests run
that plan and `make check`, which also exercises the feed tools without a key
(`.github/scripts/check-release-tools.sh`).
