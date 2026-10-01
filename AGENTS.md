# Menu Pulse

Menu Pulse is a small native Objective-C/AppKit menu bar app for Apple Silicon
Macs (macOS 13 or later). It shows CPU and RAM usage, with optional temperature
and disk usage. Keep the app lightweight and keep `Scripts/` limited to the
user-facing benchmark.

The project is developed with AI coding assistants under the maintainer's
direction; see `docs/AI_DEVELOPMENT.md`. `docs/ARCHITECTURE.md` explains how the
app is put together.

## Repository layout

- `Sources/MenuPulse/`: the app. `MenuPulse.m` coordinates everything;
  `RefreshScheduler`, `Monitors`, `TemperatureReader`, `SettingsStore`,
  `SettingsWindowController`, `LoginItemManager`, and `Updater` each own one
  concern.
- `Tests/`: four Objective-C test executables and `BenchmarkTests.sh`.
- `Scripts/benchmark.sh`: the only script; it builds and measures a separate copy.
- `Packaging/`: app bundle inputs only (`Info.plist`, `AppIcon.icns`).
- `docs/`: architecture and AI-development notes; `docs/images/` holds README images.
- `.github/workflows/`: CI (`ci.yml`) and publishing (`release.yml`);
  `.github/release-notes.md` holds the upcoming release's notes.

## Build and test

- `make app` builds `build/release/Menu Pulse.app`; `make check` runs script
  syntax checks, the version and release-notes check, static analysis, all
  tests, and the app architecture and signature check. `make dmg` packages it
  as `MenuPulse.dmg` and `MenuPulse.zip` and lists both in `SHA256SUMS.txt`.
  The in-app updater installs the ZIP from the release tagged `vX.Y.Z`, so keep
  those asset names and the `Menu Pulse.app` name inside the ZIP.
- Compiler flags are strict: ARC, `-Wall -Wextra -Werror`,
  `-Wnullable-to-nonnull-conversion`, and a macOS 13.0 deployment target. The app
  builds for arm64 only, links only system frameworks, and must not need the
  Swift runtime.
- The `Makefile` lists the sources of `MonitorTests`, `SettingsSchedulerTests`,
  and `UpdaterTests` explicitly. `UpdaterTests` builds signed test apps, zips
  them, and installs them from `file://` URLs, so it needs no network.
  `MenuPulseUITests` compiles every source except `main.m` and embeds
  `Tests/MenuPulseUITests-Info.plist`, so its version label reads 9.8.7. Update
  the `Makefile` when a test needs another source file.
- `CFFIXED_USER_HOME` changes the home folder the app sees but not where
  preferences are stored. Test binaries that use
  `NSUserDefaults.standardUserDefaults` write to the real `~/Library/Preferences`;
  the UI tests clear their own `MenuPulseUITests` domain, leaving only an empty
  file.

## Running the app safely

`build/release` uses the real bundle identifier, so launching it shares the
installed app's preferences and login item. To try a build, follow
`Scripts/benchmark.sh`:

- Build with `BUNDLE_ID=dev.hyunseop.MenuPulse.<Suffix>` and a separate
  `BUILD_DIR`.
- Start the executable with `CFFIXED_USER_HOME=<temporary folder>` and
  `MENU_PULSE_DISABLE_LOGIN_ITEM_MIGRATION=1`. The temporary home keeps the
  legacy login-item cleanup and the DISK reading away from the user's home.
- Pass settings as `-key value` arguments, including
  `-hasCompletedOpenAtLoginPrompt YES` so the Open at login prompt does not
  appear.
- Afterwards run `defaults delete dev.hyunseop.MenuPulse.<Suffix>`.

Do not install the app, change its login item, or quit the user's running copy
unless the user asks. Do not test Check for Updates on the installed copy: it
replaces the app in place. Test `MPUpdater` with its designated initializer,
local `file://` URLs, and an app under a temporary folder with a suffixed
bundle identifier.

## Code and documentation conventions

- Match the surrounding code: `MP` prefixes, `NS_ASSUME_NONNULL` headers,
  explicit nullability, and short comments that explain why.
- Do not add third-party dependencies.
- `README.md` and `README.ko.md` mirror each other section by section; change
  them together. The app's labels are English, so the Korean README names them in
  English, for example **Open at login**.
- Keep README images in `docs/images/` and capture them from the current build.

## Preparing changes for the user's commit

CI treats changes to `Sources/`, `Packaging/`, or `Makefile` as app build input
changes. Prepare their version and release notes before handing them back to the
user:

- Fetch the current remote tags (`git fetch --tags origin`, without force) before
  choosing a version; tags created by CI may not exist locally yet.
  If the current version is already tagged,
  choose the next semantic version: patch for fixes, minor for new features.
  If a newer version is already being prepared locally, keep that version and
  update its notes rather than incrementing it again on each conversation turn.
- Set both `CFBundleShortVersionString` and `CFBundleVersion` in
  `Packaging/Info.plist` to the same version.
- Update `.github/release-notes.md`. Its first line must be `# vX.Y.Z`, matching
  the app version. Write 3–5 concise bullets about the actual user-visible changes
  since the previous release. The user may edit this text before committing.
- Run `make check` for app changes. For workflow changes, also check the workflow
  syntax (for example with `actionlint`) and test release decisions without
  publishing to the real repository.
- Documentation-only changes do not need a version bump or a new release.

The user normally commits and pushes. CI validates a `main` push, then creates
the prepared version tag and publishes the DMG and notes. Do not make commits,
tags, pushes, or GitHub releases unless the user asks. Never move an existing
release tag to another commit.

Keep release procedure details out of the public READMEs. Release notes belong
on GitHub Releases; the file above holds the upcoming release's editable text.
