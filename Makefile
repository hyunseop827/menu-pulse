SHELL := /bin/bash
.DEFAULT_GOAL := help

ARCH ?= arm64
TEST_ARCH ?= $(shell uname -m)
BUILD_DIR ?= build/release
BUNDLE_ID ?= dev.hyunseop.MenuPulse
SDKROOT = $(shell xcrun --sdk macosx --show-sdk-path)
OBJC_FLAGS = -fobjc-arc -fmodules -Wall -Wextra -Werror \
	-Wnullable-to-nonnull-conversion -mmacosx-version-min=13.0 \
	-isysroot "$(SDKROOT)" -I Sources/MenuPulse
FRAMEWORKS = -framework AppKit -framework Foundation -framework CoreFoundation -framework CoreGraphics \
	-framework IOKit -framework ServiceManagement

.PHONY: help app test analyze check verify-app dmg

help:
	@printf '%s\n' \
	  'make app      Build the app in build/release (does not install or launch)' \
	  'make test     Run tests in a temporary directory' \
	  'make analyze  Run Clang static analysis' \
	  'make check    Check scripts, metadata, analysis, tests, and app signature' \
	  'make dmg      Create dist/MenuPulse.dmg and dist/SHA256SUMS.txt' \
	  'Scripts/benchmark.sh  Measure an isolated temporary build'

app:
	@set -euo pipefail; \
	[[ "$(ARCH)" == arm64 ]] || { echo 'Menu Pulse supports arm64 only' >&2; exit 1; }; \
	app="$(BUILD_DIR)/Menu Pulse.app"; \
	rm -rf -- "$$app"; \
	mkdir -p "$$app/Contents/MacOS" "$$app/Contents/Resources"; \
	xcrun clang $(OBJC_FLAGS) -arch "$(ARCH)" -Oz -DNDEBUG \
	  Sources/MenuPulse/*.m -o "$$app/Contents/MacOS/MenuPulse" \
	  $(FRAMEWORKS) -Wl,-dead_strip; \
	strip -x "$$app/Contents/MacOS/MenuPulse"; \
	cp Packaging/Info.plist "$$app/Contents/Info.plist"; \
	/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier $(BUNDLE_ID)' "$$app/Contents/Info.plist"; \
	cp Packaging/AppIcon.icns "$$app/Contents/Resources/AppIcon.icns"; \
	printf 'APPL????' > "$$app/Contents/PkgInfo"; \
	codesign --force --sign - "$$app"; \
	codesign --verify --strict "$$app"; \
	echo "$$app"

test:
	@set -euo pipefail; \
	test_dir="$$(mktemp -d -t menu-pulse-tests)"; \
	trap 'rm -r -- "$$test_dir"' EXIT; \
	trap 'exit 130' INT; trap 'exit 143' TERM; \
	mkdir -p "$$test_dir/Home/Library/Preferences"; \
	xcrun clang $(OBJC_FLAGS) -I Tests -arch "$(TEST_ARCH)" \
	  Tests/MonitorTests.m Sources/MenuPulse/Monitors.m Sources/MenuPulse/TemperatureReader.m \
	  -o "$$test_dir/MonitorTests" -framework Foundation -framework IOKit; \
	CFFIXED_USER_HOME="$$test_dir/Home" "$$test_dir/MonitorTests"; \
	xcrun clang $(OBJC_FLAGS) -I Tests -arch "$(TEST_ARCH)" \
	  Tests/SettingsSchedulerTests.m Tests/MemoryUserDefaults.m \
	  Sources/MenuPulse/SettingsStore.m Sources/MenuPulse/RefreshScheduler.m \
	  -o "$$test_dir/SettingsSchedulerTests" -framework Foundation; \
	CFFIXED_USER_HOME="$$test_dir/Home" "$$test_dir/SettingsSchedulerTests"; \
	ui_sources=(); \
	for source in Sources/MenuPulse/*.m; do \
	  [[ "$$source" == Sources/MenuPulse/main.m ]] || ui_sources+=("$$source"); \
	done; \
	xcrun clang $(OBJC_FLAGS) -I Tests -arch "$(TEST_ARCH)" \
	  Tests/MenuPulseUITests.m Tests/MemoryUserDefaults.m "$${ui_sources[@]}" \
	  -o "$$test_dir/MenuPulseUITests" $(FRAMEWORKS); \
	CFFIXED_USER_HOME="$$test_dir/Home" "$$test_dir/MenuPulseUITests"; \
	CFFIXED_USER_HOME="$$test_dir/Home" bash Tests/BenchmarkTests.sh

analyze:
	@set -euo pipefail; \
	printf '%s\0' Sources/MenuPulse/*.m | \
	  xargs -0 -n 1 -P "$$(sysctl -n hw.ncpu)" \
	    xcrun clang --analyze $(OBJC_FLAGS) -arch "$(ARCH)" \
	      -Xanalyzer -analyzer-output=text -Xanalyzer -analyzer-werror -o /dev/null; \
	echo 'Clang static analysis passed.'

check:
	@set -euo pipefail; \
	for script in Scripts/*.sh Tests/*.sh; do bash -n "$$script"; done; \
	plutil -lint Packaging/Info.plist; \
	version="$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Packaging/Info.plist)"; \
	[[ "$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Packaging/Info.plist)" == "$$version" ]] || \
	  { echo 'CFBundleVersion must match CFBundleShortVersionString.' >&2; exit 1; }; \
	[[ "$$(head -n 1 .github/release-notes.md)" == "# v$$version" ]] || \
	  { echo "The release notes must begin with '# v$$version'." >&2; exit 1; }
	@$(MAKE) analyze
	@$(MAKE) test
	@$(MAKE) verify-app

verify-app: app
	@set -euo pipefail; \
	bin="$(BUILD_DIR)/Menu Pulse.app/Contents/MacOS/MenuPulse"; \
	[[ "$$(lipo -archs "$$bin")" == arm64 ]]; \
	file "$$bin"; \
	otool -L "$$bin"; \
	! otool -L "$$bin" | grep -q '/usr/lib/swift'

dmg: verify-app
	@set -euo pipefail; \
	staging="$$(mktemp -d -t menu-pulse-dmg)"; \
	trap 'rm -r -- "$$staging"' EXIT; \
	trap 'exit 130' INT; trap 'exit 143' TERM; \
	mkdir -p dist; \
	ditto "$(BUILD_DIR)/Menu Pulse.app" "$$staging/Menu Pulse.app"; \
	ln -s /Applications "$$staging/Applications"; \
	hdiutil create -volname 'Menu Pulse' -srcfolder "$$staging" \
	  -ov -format UDZO dist/MenuPulse.dmg; \
	hdiutil verify dist/MenuPulse.dmg; \
	cd dist; shasum -a 256 MenuPulse.dmg > SHA256SUMS.txt
