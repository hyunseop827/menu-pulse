SHELL := /bin/bash
.DEFAULT_GOAL := help

ARCH ?= arm64
TEST_ARCH ?= $(shell uname -m)
BUILD_DIR ?= build/release
BUNDLE_ID ?= dev.hyunseop.MenuPulse
# CFBundleVersion of the built app. Sparkle compares it, so release builds use
# the CI run number; other builds keep the value in Packaging/Info.plist.
APP_BUILD ?=
SDKROOT = $(shell xcrun --sdk macosx --show-sdk-path)
# Sparkle 2 is the one third-party dependency. The official archive is pinned
# by version and checksum and unpacked once under build/sparkle.
SPARKLE_VERSION = 2.10.0
SPARKLE_SHA256 = c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
# Make target names stay relative (make splits them on spaces); commands use the
# absolute path, quoted.
SPARKLE_STAMP = build/sparkle/$(SPARKLE_VERSION)/.extracted
SPARKLE_DIR = $(CURDIR)/build/sparkle/$(SPARKLE_VERSION)
OBJC_FLAGS = -fobjc-arc -fmodules -Wall -Wextra -Werror \
	-Wnullable-to-nonnull-conversion -mmacosx-version-min=13.0 \
	-isysroot "$(SDKROOT)" -I Sources/MenuPulse -F "$(SPARKLE_DIR)"
FRAMEWORKS = -framework AppKit -framework Foundation -framework CoreFoundation -framework CoreGraphics \
	-framework IOKit -framework ServiceManagement -framework Sparkle
# Test executables load Sparkle from the unpacked archive.
TEST_SPARKLE_RPATH = -Wl,-rpath,"$(SPARKLE_DIR)"

.PHONY: help app test analyze check verify-app dmg sparkle print-sparkle-bin

help:
	@printf '%s\n' \
	  'make app      Build the app in build/release (does not install or launch)' \
	  'make test     Run tests in a temporary directory' \
	  'make analyze  Run Clang static analysis' \
	  'make check    Check scripts, metadata, analysis, tests, and the app bundle' \
	  'make dmg      Create the DMGs, the update ZIP, and SHA256SUMS.txt in dist' \
	  'Scripts/benchmark.sh  Measure an isolated temporary build'

sparkle: $(SPARKLE_STAMP)

$(SPARKLE_STAMP):
	@set -euo pipefail; \
	archive="build/sparkle/Sparkle-$(SPARKLE_VERSION).tar.xz"; \
	mkdir -p build/sparkle; \
	if ! echo "$(SPARKLE_SHA256)  $$archive" | shasum -a 256 -c - >/dev/null 2>&1; then \
	  curl -fsSL -o "$$archive.download" \
	    "https://github.com/sparkle-project/Sparkle/releases/download/$(SPARKLE_VERSION)/Sparkle-$(SPARKLE_VERSION).tar.xz"; \
	  echo "$(SPARKLE_SHA256)  $$archive.download" | shasum -a 256 -c - >/dev/null || \
	    { rm -f "$$archive.download"; echo 'The Sparkle archive does not match its pinned SHA-256.' >&2; exit 1; }; \
	  mv "$$archive.download" "$$archive"; \
	fi; \
	rm -rf "$(SPARKLE_DIR)"; \
	mkdir -p "$(SPARKLE_DIR)"; \
	tar -xJf "$$archive" -C "$(SPARKLE_DIR)" \
	  ./Sparkle.framework ./bin/sign_update ./bin/generate_keys ./LICENSE; \
	touch "$@"

# The release workflow signs the update feed with this sign_update.
print-sparkle-bin: sparkle
	@echo "$(SPARKLE_DIR)/bin"

app: sparkle
	@set -euo pipefail; \
	[[ "$(ARCH)" == arm64 ]] || { echo 'Menu Pulse supports arm64 only' >&2; exit 1; }; \
	[[ -z "$(APP_BUILD)" || "$(APP_BUILD)" =~ ^[1-9][0-9]*$$ ]] || \
	  { echo 'APP_BUILD must be a positive integer.' >&2; exit 1; }; \
	app="$(BUILD_DIR)/Menu Pulse.app"; \
	framework="$$app/Contents/Frameworks/Sparkle.framework"; \
	rm -rf -- "$$app"; \
	mkdir -p "$$app/Contents/MacOS" "$$app/Contents/Resources" "$$app/Contents/Frameworks"; \
	xcrun clang $(OBJC_FLAGS) -arch "$(ARCH)" -Oz -DNDEBUG \
	  Sources/MenuPulse/*.m -o "$$app/Contents/MacOS/MenuPulse" \
	  $(FRAMEWORKS) -Wl,-rpath,@executable_path/../Frameworks -Wl,-dead_strip; \
	strip -x "$$app/Contents/MacOS/MenuPulse"; \
	cp Packaging/Info.plist "$$app/Contents/Info.plist"; \
	/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier $(BUNDLE_ID)' "$$app/Contents/Info.plist"; \
	if [[ -n "$(APP_BUILD)" ]]; then \
	  /usr/libexec/PlistBuddy -c 'Set :CFBundleVersion $(APP_BUILD)' "$$app/Contents/Info.plist"; \
	fi; \
	cp Packaging/AppIcon.icns "$$app/Contents/Resources/AppIcon.icns"; \
	cp Packaging/ThirdPartyNotices.txt "$$app/Contents/Resources/ThirdPartyNotices.txt"; \
	printf 'APPL????' > "$$app/Contents/PkgInfo"; \
	ditto "$(SPARKLE_DIR)/Sparkle.framework" "$$framework"; \
	rm -rf "$$framework/Versions/B/XPCServices" "$$framework/XPCServices"; \
	for binary in "$$framework/Versions/B/Sparkle" "$$framework/Versions/B/Autoupdate" \
	    "$$framework/Versions/B/Updater.app/Contents/MacOS/Updater"; do \
	  lipo "$$binary" -thin arm64 -output "$$binary.arm64"; \
	  mv "$$binary.arm64" "$$binary"; \
	done; \
	for code in "$$framework/Versions/B/Autoupdate" "$$framework/Versions/B/Updater.app" "$$framework"; do \
	  codesign --force --sign - --options runtime "$$code"; \
	done; \
	codesign --force --sign - --options runtime \
	  --entitlements Packaging/MenuPulse.entitlements "$$app"; \
	codesign --verify --deep --strict "$$app"; \
	echo "$$app"

test: sparkle
	@set -euo pipefail; \
	test_dir="$$(mktemp -d -t menu-pulse-tests)"; \
	trap 'rm -r -- "$$test_dir"; defaults delete MenuPulseUITests >/dev/null 2>&1 || true' EXIT; \
	trap 'exit 130' INT; trap 'exit 143' TERM; \
	mkdir -p "$$test_dir/Home"; \
	xcrun clang $(OBJC_FLAGS) -I Tests -arch "$(TEST_ARCH)" \
	  Tests/MonitorTests.m Sources/MenuPulse/Monitors.m Sources/MenuPulse/TemperatureReader.m \
	  -o "$$test_dir/MonitorTests" -framework Foundation -framework IOKit; \
	CFFIXED_USER_HOME="$$test_dir/Home" "$$test_dir/MonitorTests"; \
	xcrun clang $(OBJC_FLAGS) -I Tests -arch "$(TEST_ARCH)" \
	  Tests/SettingsSchedulerTests.m Tests/MemoryUserDefaults.m \
	  Sources/MenuPulse/SettingsStore.m Sources/MenuPulse/RefreshScheduler.m \
	  -o "$$test_dir/SettingsSchedulerTests" -framework Foundation; \
	CFFIXED_USER_HOME="$$test_dir/Home" "$$test_dir/SettingsSchedulerTests"; \
	xcrun clang $(OBJC_FLAGS) -I Tests -arch "$(TEST_ARCH)" \
	  Tests/UpdaterTests.m Sources/MenuPulse/Updater.m \
	  -o "$$test_dir/UpdaterTests" -framework AppKit -framework Sparkle $(TEST_SPARKLE_RPATH); \
	CFFIXED_USER_HOME="$$test_dir/Home" "$$test_dir/UpdaterTests"; \
	ui_sources=(); \
	for source in Sources/MenuPulse/*.m; do \
	  [[ "$$source" == Sources/MenuPulse/main.m ]] || ui_sources+=("$$source"); \
	done; \
	xcrun clang $(OBJC_FLAGS) -I Tests -arch "$(TEST_ARCH)" \
	  Tests/MenuPulseUITests.m Tests/MemoryUserDefaults.m "$${ui_sources[@]}" \
	  -Wl,-sectcreate,__TEXT,__info_plist,Tests/MenuPulseUITests-Info.plist \
	  -o "$$test_dir/MenuPulseUITests" $(FRAMEWORKS) $(TEST_SPARKLE_RPATH); \
	CFFIXED_USER_HOME="$$test_dir/Home" "$$test_dir/MenuPulseUITests"; \
	CFFIXED_USER_HOME="$$test_dir/Home" bash Tests/BenchmarkTests.sh

analyze: sparkle
	@set -euo pipefail; \
	printf '%s\0' Sources/MenuPulse/*.m | \
	  xargs -0 -n 1 -P "$$(sysctl -n hw.ncpu)" \
	    xcrun clang --analyze $(OBJC_FLAGS) -arch "$(ARCH)" \
	      -Xanalyzer -analyzer-output=text -Xanalyzer -analyzer-werror -o /dev/null; \
	echo 'Clang static analysis passed.'

check:
	@set -euo pipefail; \
	for script in Scripts/*.sh Tests/*.sh .github/scripts/*.sh; do bash -n "$$script"; done; \
	plutil -lint Packaging/Info.plist Packaging/MenuPulse.entitlements; \
	version="$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Packaging/Info.plist)"; \
	[[ "$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Packaging/Info.plist)" =~ ^[1-9][0-9]*$$ ]] || \
	  { echo 'CFBundleVersion must be a positive integer; release builds replace it with the CI run number.' >&2; exit 1; }; \
	[[ "$$(head -n 1 .github/release-notes.md)" == "# v$$version" ]] || \
	  { echo "The release notes must begin with '# v$$version'." >&2; exit 1; }; \
	bash .github/scripts/check-release-tools.sh
	@$(MAKE) analyze
	@$(MAKE) test
	@$(MAKE) verify-app
	@bash Tests/AppBundleTests.sh "$(BUILD_DIR)/Menu Pulse.app"

verify-app: app
	@set -euo pipefail; \
	app="$(BUILD_DIR)/Menu Pulse.app"; \
	bin="$$app/Contents/MacOS/MenuPulse"; \
	rpaths() { otool -l "$$1" | awk '/cmd LC_RPATH/ { getline; getline; print $$2 }'; }; \
	while IFS= read -r -d '' file; do \
	  if file -b "$$file" | grep -q 'Mach-O'; then \
	    [[ "$$(lipo -archs "$$file")" == arm64 ]] || \
	      { echo "Expected an arm64-only binary: $$file" >&2; exit 1; }; \
	    if otool -L "$$file" | grep -q '/usr/lib/swift'; then \
	      echo "Unexpected Swift runtime dependency: $$file" >&2; exit 1; \
	    fi; \
	    file_rpaths="$$(rpaths "$$file")"; \
	    [[ -z "$$file_rpaths" || "$$file_rpaths" == '@executable_path/../Frameworks' ]] || \
	      { echo "Unexpected LC_RPATH in $$file: $$file_rpaths" >&2; exit 1; }; \
	  fi; \
	done < <(find "$$app" -type f -print0); \
	[[ "$$(rpaths "$$bin")" == '@executable_path/../Frameworks' ]] || \
	  { echo 'The app must load frameworks only from Contents/Frameworks.' >&2; exit 1; }; \
	file "$$bin"; \
	otool -L "$$bin"

dmg: verify-app
	@set -euo pipefail; \
	version="$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$(BUILD_DIR)/Menu Pulse.app/Contents/Info.plist")"; \
	staging="$$(mktemp -d -t menu-pulse-dmg)"; \
	trap 'rm -r -- "$$staging"' EXIT; \
	trap 'exit 130' INT; trap 'exit 143' TERM; \
	mkdir -p dist; \
	rm -f dist/MenuPulse.dmg dist/MenuPulse-*.dmg dist/MenuPulse.zip dist/SHA256SUMS.txt; \
	ditto "$(BUILD_DIR)/Menu Pulse.app" "$$staging/Image/Menu Pulse.app"; \
	ln -s /Applications "$$staging/Image/Applications"; \
	hdiutil create -volname 'Menu Pulse' -srcfolder "$$staging/Image" \
	  -ov -format UDZO dist/MenuPulse.dmg; \
	hdiutil verify dist/MenuPulse.dmg; \
	cp dist/MenuPulse.dmg "dist/MenuPulse-$$version.dmg"; \
	ditto -c -k --keepParent "$(BUILD_DIR)/Menu Pulse.app" dist/MenuPulse.zip; \
	ditto -x -k dist/MenuPulse.zip "$$staging/Unzipped"; \
	unzipped_app="$$staging/Unzipped/Menu Pulse.app"; \
	codesign --verify --deep --strict "$$unzipped_app"; \
	[[ "$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$$unzipped_app/Contents/Info.plist")" == "$(BUNDLE_ID)" ]] || \
	  { echo 'The update ZIP must contain Menu Pulse.app at its top level.' >&2; exit 1; }; \
	cd dist; shasum -a 256 MenuPulse.dmg "MenuPulse-$$version.dmg" MenuPulse.zip > SHA256SUMS.txt
