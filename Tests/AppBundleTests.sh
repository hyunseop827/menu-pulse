#!/usr/bin/env bash
# Checks a built Menu Pulse.app: the Sparkle settings in Info.plist, the
# embedded Sparkle.framework, and how the bundle is signed.
#
#   bash Tests/AppBundleTests.sh "build/release/Menu Pulse.app"
#
# The public-key check runs last: a build without a real EdDSA public key (such
# as the placeholder) never passes `make check` or CI.
set -euo pipefail

APP="${1:?usage: AppBundleTests.sh <Menu Pulse.app>}"
INFO="$APP/Contents/Info.plist"
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
FAILURES=0

fail() {
  echo "FAIL: $*" >&2
  FAILURES=$((FAILURES + 1))
}

plist() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$INFO" 2>/dev/null || true
}

# The value as a property-list element (<true/>, <false/>, <string>…</string>), or nothing when the key is missing,
# so a boolean written as a string does not pass.
plist_element() {
  plutil -extract "$1" xml1 -o - "$INFO" 2>/dev/null | sed -e '1,/<plist /d' -e '/<\/plist>/,$d' || true
}

[[ -f "$INFO" ]] || { echo "FAIL: $INFO is missing" >&2; exit 1; }

# Update settings (AGENTS.md, step 9): a daily check of the release feed, and
# installing only when the user chooses to.
[[ "$(plist SUFeedURL)" == "https://github.com/hyunseop827/menu-pulse/releases/latest/download/appcast.xml" ]] ||
  fail "SUFeedURL is '$(plist SUFeedURL)'"
[[ "$(plist_element SUEnableAutomaticChecks)" == '<true/>' ]] || fail 'SUEnableAutomaticChecks must be <true/>'
[[ "$(plist_element SUAllowsAutomaticUpdates)" == '<false/>' ]] || fail 'SUAllowsAutomaticUpdates must be <false/>'
[[ "$(plist_element SUVerifyUpdateBeforeExtraction)" == '<true/>' ]] || fail 'SUVerifyUpdateBeforeExtraction must be <true/>'
[[ "$(plist_element SUPublicEDKey)" == '<string>'* ]] || fail 'SUPublicEDKey must be a string'
# The default interval, no automatic installation, no system profile, no XPC services (they are not in the
# bundle), no old DSA key, and no exception to App Transport Security.
for key in SUScheduledCheckInterval SUAutomaticallyUpdate SUEnableSystemProfiling SUPublicDSAKeyFile \
    SUEnableInstallerLauncherService SUEnableDownloaderService SUEnableInstallerConnectionService \
    SUEnableInstallerStatusService NSAppTransportSecurity; do
  [[ -z "$(plist_element "$key")" ]] || fail "$key must not be set"
done
[[ "$(plist CFBundleVersion)" =~ ^[1-9][0-9]*$ ]] || fail "CFBundleVersion '$(plist CFBundleVersion)' is not a positive integer"
[[ "$(plist LSUIElement)" == true ]] || fail 'LSUIElement must stay true'

# The embedded framework: the pinned release, without the XPC services that
# only sandboxed apps use, found through the app's rpath.
sparkle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$FRAMEWORK/Versions/B/Resources/Info.plist" 2>/dev/null || true)"
[[ "$sparkle_version" == 2.10.0 ]] || fail "Sparkle.framework version is '$sparkle_version', expected 2.10.0"
[[ ! -e "$FRAMEWORK/XPCServices" && ! -e "$FRAMEWORK/Versions/B/XPCServices" ]] ||
  fail 'Sparkle.framework still contains XPCServices'
[[ -x "$FRAMEWORK/Versions/B/Autoupdate" && -d "$FRAMEWORK/Versions/B/Updater.app" ]] ||
  fail 'Sparkle.framework is missing Autoupdate or Updater.app'
otool -l "$APP/Contents/MacOS/MenuPulse" | grep -A2 LC_RPATH | grep -q '@executable_path/../Frameworks' ||
  fail 'the app has no @executable_path/../Frameworks rpath'
otool -L "$APP/Contents/MacOS/MenuPulse" | grep -q '@rpath/Sparkle.framework/Versions/B/Sparkle' ||
  fail 'the app does not link Sparkle.framework'
[[ -s "$APP/Contents/Resources/ThirdPartyNotices.txt" ]] &&
  grep -q 'Sparkle 2.10.0' "$APP/Contents/Resources/ThirdPartyNotices.txt" ||
  fail "ThirdPartyNotices.txt is missing Sparkle's license"

# Signing: ad hoc with the hardened runtime, inside out. The app's only
# entitlement lets it load the ad-hoc signed framework.
codesign --verify --deep --strict "$APP" 2>/dev/null || fail 'codesign --verify --deep --strict failed'
for code in "$FRAMEWORK/Versions/B/Autoupdate" "$FRAMEWORK/Versions/B/Updater.app" "$FRAMEWORK" "$APP"; do
  details="$(codesign -dv "$code" 2>&1 || true)"
  [[ "$details" == *"Signature=adhoc"* ]] || fail "${code#"$APP/"} is not ad-hoc signed"
  [[ "$details" == *"(adhoc,runtime)"* ]] || fail "${code#"$APP/"} is not signed with the hardened runtime"
done
entitlements="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -convert json -o - - 2>/dev/null || true)"
[[ "$entitlements" == '{"com.apple.security.cs.disable-library-validation":true}' ]] ||
  fail "unexpected entitlements: $entitlements"

# Last: Sparkle's EdDSA public key (base64 of 32 bytes). Installed copies only
# accept updates signed with the key they shipped with.
public_key="$(plist SUPublicEDKey)"
if [[ ! "$public_key" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
  fail "SUPublicEDKey is '$public_key', not an EdDSA public key; the owner adds it (AGENTS.md, 'Update key (owner only)')"
fi

if (( FAILURES > 0 )); then
  echo "$FAILURES app bundle check(s) failed" >&2
  exit 1
fi
echo 'App bundle checks passed.'
