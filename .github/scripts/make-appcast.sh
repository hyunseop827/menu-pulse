#!/usr/bin/env bash
# Writes the Sparkle appcast for one release: a feed with a single item, the given disk image, EdDSA-signed.
# Installed copies read it through SUFeedURL (Packaging/Info.plist).
#
#   .github/scripts/make-appcast.sh <app> <dmg> <download-url> <release-notes.md> <appcast.xml>
#
# <app>              the app inside <dmg> (build/release after `make dmg`): its CFBundleVersion,
#                    CFBundleShortVersionString, LSMinimumSystemVersion and SUPublicEDKey describe the item, so the
#                    feed always matches what it ships.
# <download-url>     where <dmg> will be downloaded from: an https address (CI: the versioned release asset). Plain
#                    http is accepted only for this Mac (http://127.0.0.1:<port>/… or http://localhost:<port>/…).
# <release-notes.md> Markdown shown in Sparkle's update window (the release notes without their '# vX.Y.Z' line).
#
# Environment:
#   SPARKLE_PRIVATE_KEY  the private EdDSA key, base64 (what `generate_keys --account menu-pulse -x` exports). Only
#                        the owner has it; CI gets it from the repository secret. It leaves the environment before
#                        any program is started and reaches only sign_update, on standard input.
#   SPARKLE_BIN          folder with Sparkle's sign_update (`make print-sparkle-bin`).
#
# Everything that needs no key is checked first. An app that still carries the placeholder key is refused: a copy
# released with it could never update. The signature is checked against the app's own SUPublicEDKey before the feed
# is written, so a private key that does not pair with the installed copies' key stops the release here.
# .github/scripts/check-release-tools.sh exercises this script without a key.
set -euo pipefail

# Out of the environment before the first program runs (PlistBuddy, sign_update, swift, xmllint would inherit it).
# A bash variable that is not exported stays in this shell.
PRIVATE_KEY="${SPARKLE_PRIVATE_KEY:-}"
unset SPARKLE_PRIVATE_KEY

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail() { echo "error: $*" >&2; exit 1; }
(( $# == 5 )) || { echo "usage: $0 <app> <dmg> <download-url> <release-notes.md> <appcast.xml>" >&2; exit 2; }
APP="$1" DMG="$2" URL="$3" NOTES="$4" OUT="$5"
[[ -f "$APP/Contents/Info.plist" && -f "$DMG" && -f "$NOTES" ]] || fail 'The app, disk image, or release notes are missing.'
# https, or http to this Mac only; nothing that would need escaping in the XML attribute, and no white space.
url_pattern='^(https://|http://(127\.0\.0\.1|localhost)(:[0-9]+)?/)[^"<>&[:space:]]+$'
[[ "$URL" =~ $url_pattern ]] || fail "Invalid download URL (it must be https): '$URL'"

# Empty when a key is missing, so the messages below are the ones shown.
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Contents/Info.plist" 2> /dev/null || true; }
BUILD="$(plist CFBundleVersion)"
VERSION="$(plist CFBundleShortVersionString)"
MIN_OS="$(plist LSMinimumSystemVersion)"
PUBLIC_KEY="$(plist SUPublicEDKey)"
# Sparkle compares sparkle:version (CFBundleVersion): a plain integer, the CI run number.
[[ "$BUILD" =~ ^[1-9][0-9]*$ ]] || fail "The app's CFBundleVersion is not an integer: '$BUILD'"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$MIN_OS" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] ||
  fail "Unexpected version information in the app: version '$VERSION', minimum macOS '$MIN_OS'"
[[ -n "$PUBLIC_KEY" ]] || fail "The app's Info.plist has no SUPublicEDKey."
if [[ "$PUBLIC_KEY" == PASTE_* ]]; then
  fail "The app's SUPublicEDKey is still the placeholder ('$PUBLIC_KEY'). The owner adds the public key that generate_keys --account menu-pulse prints to Packaging/Info.plist (AGENTS.md, 'Update key (owner only)'); a copy released with the placeholder could never update."
fi
[[ "$PUBLIC_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]] || fail "The app's SUPublicEDKey is not an EdDSA public key: '$PUBLIC_KEY'"

[[ -n "$PRIVATE_KEY" ]] || fail 'SPARKLE_PRIVATE_KEY is not set (the private key exported with generate_keys -x).'
[[ -x "${SPARKLE_BIN:-}/sign_update" ]] || fail "SPARKLE_BIN has no sign_update: '${SPARKLE_BIN:-}'"

# -p prints only the signature; the key goes in on standard input (printf is a shell builtin), so it is never an
# argument, an environment variable, or a file. The output is never printed: one of sign_update's errors repeats the key.
SIGNATURE="$(printf '%s\n' "$PRIVATE_KEY" | "$SPARKLE_BIN/sign_update" -p --ed-key-file - "$DMG")" ||
  fail 'sign_update could not sign with SPARKLE_PRIVATE_KEY. It must be the single-line base64 private key exported with generate_keys --account menu-pulse -x <file>; set it again with gh secret set SPARKLE_PRIVATE_KEY < <file>.'
unset PRIVATE_KEY
[[ "$SIGNATURE" =~ ^[A-Za-z0-9+/]{86}==$ ]] || fail 'sign_update did not produce a signature.'
VERIFIED=0
xcrun swift "$ROOT/.github/scripts/ed25519-verify.swift" "$PUBLIC_KEY" "$DMG" "$SIGNATURE" || VERIFIED=$?
case $VERIFIED in
  0) ;;
  1) fail "The signature does not match the app's SUPublicEDKey. Check that SPARKLE_PRIVATE_KEY pairs with the public key in Packaging/Info.plist." ;;
  *) fail "The signature could not be checked (ed25519-verify.swift exited with $VERIFIED)." ;;
esac
LENGTH="$(stat -f %z "$DMG")"
DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
BODY="$(<"$NOTES")"
BODY="${BODY//]]>/]]]]><![CDATA[>}"   # the only sequence CDATA cannot hold

TMP="$OUT.tmp"
cat > "$TMP" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Menu Pulse</title>
    <link>https://github.com/hyunseop827/menu-pulse</link>
    <item>
      <title>Menu Pulse $VERSION</title>
      <pubDate>$DATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
      <description sparkle:format="markdown"><![CDATA[$BODY]]></description>
      <enclosure url="$URL" length="$LENGTH" type="application/octet-stream" sparkle:edSignature="$SIGNATURE"/>
    </item>
  </channel>
</rss>
XML
xmllint --noout "$TMP" || { rm -f "$TMP"; fail 'The appcast XML is not well-formed.'; }
mv "$TMP" "$OUT"
echo "appcast: $OUT ($VERSION, build $BUILD, $LENGTH bytes, $URL)"
