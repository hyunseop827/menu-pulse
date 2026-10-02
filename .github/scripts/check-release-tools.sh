#!/usr/bin/env bash
# Checks the two tools only a release runs, .github/scripts/make-appcast.sh and .github/scripts/ed25519-verify.swift,
# without a key, so a mistake in them shows in `make check` (and on pull requests), not in the first release that
# needs them.
#
#   bash .github/scripts/check-release-tools.sh
#
# No key is made, read, or used. The signatures are the published test vectors of RFC 8032 (section 7.1, TEST 1
# to 3: public key, message, signature; their private keys are not here). Sparkle's sign_update is replaced by a
# stand-in that prints one of those signatures, and what make-appcast.sh hands it as "the key" is a fixed text that
# is no key. What is checked:
# - ed25519-verify.swift compiles, accepts the three vectors (exit 0), refuses a signature of another message or key
#   (1), and reports malformed arguments (2);
# - make-appcast.sh writes a well-formed feed with the app's values, the address, the length and the signature, and
#   keeps the release notes as they are; the key reaches sign_update on standard input and is in no program's
#   environment or arguments;
# - make-appcast.sh refuses, without writing a feed: the placeholder key, a signature that does not fit the app's
#   public key, a build number Sparkle could not compare, an address that is not https, a missing key; and it never
#   shows what sign_update printed.
set -euo pipefail

cd "$(dirname "$0")/../.."
work="$(mktemp -d "${TMPDIR:-/tmp}/menu-pulse-release-tools.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# RFC 8032, section 7.1: public keys and signatures in base64 (as SUPublicEDKey and sparkle:edSignature are written),
# and the messages as files.
key1="11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo="
sig1="5VZDAMNgrHKQhuLMgG6CioSHfx645dl02HPgZSJJAVVfuIIVkKM7rMYeOXAc+bRr0lv18FlbviRlUUFDjnoQCw=="
key2="PUAXw+hDiVqStwqnTRt+vJyYLM8uxJaMwM1V8Sr0Zgw="
sig2="kqAJqfDUyrhyDoILX2QlQKKye1QWUD+Ps3YiI+vbadoIWsHkPhWZbkWPNhPQ8R2MOHsurrQwKu6wDSkWErsMAA=="
key3="/FHNjmIYoaONpH7QAjDwWAgW7RO6MwOsXeuRFUiQgCU="
sig3="YpHWV97sJAJIJ+acOr4BowzlSKKEdDpEXjaA19taw6wY/5tTjRbykK5n92CYTcZZSnwV6XFu0o3AJ77O6h7ECg=="
: > "$work/message1"
printf '\x72' > "$work/message2"
printf '\xaf\x82' > "$work/message3"

# Compiled once (this is also its type check); make-appcast.sh runs it as a script further down.
xcrun swiftc -o "$work/ed25519-verify" .github/scripts/ed25519-verify.swift
verify() { # <expected exit status> <what> <arguments of ed25519-verify.swift…>
  local expected="$1" what="$2" status=0
  shift 2
  "$work/ed25519-verify" "$@" 2> /dev/null || status=$?
  [[ $status == "$expected" ]] || fail "ed25519-verify.swift: $what exited with $status, not $expected."
}
verify 0 "RFC 8032 TEST 1 (empty message)" "$key1" "$work/message1" "$sig1"
verify 0 "RFC 8032 TEST 2 (1 byte)" "$key2" "$work/message2" "$sig2"
verify 0 "RFC 8032 TEST 3 (2 bytes)" "$key3" "$work/message3" "$sig3"
verify 1 "a signature of another file" "$key2" "$work/message3" "$sig2"
verify 1 "a signature of another key" "$key2" "$work/message2" "$sig3"
verify 2 "the placeholder key" "PASTE_PUBLIC_KEY_FROM_generate_keys" "$work/message2" "$sig2"
verify 2 "a public key as the signature" "$key2" "$work/message2" "$key2"
verify 2 "a missing file" "$key2" "$work/no-such-file" "$sig2"
verify 2 "too few arguments" "$key2" "$work/message2"

bash -n .github/scripts/make-appcast.sh
# An app as make-appcast.sh reads it: only Contents/Info.plist.
app() { # <name> <CFBundleVersion> <SUPublicEDKey>
  mkdir -p "$work/$1.app/Contents"
  cat > "$work/$1.app/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleShortVersionString</key><string>9.8.7</string>
<key>CFBundleVersion</key><string>$2</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>SUPublicEDKey</key><string>$3</string>
</dict></plist>
PLIST
}
app good 57 "$key2"
app placeholder 57 "PASTE_PUBLIC_KEY_FROM_generate_keys"
app zero 0 "$key2"
app padded 057 "$key2"
# The "disk image" is the message of TEST 2, so its published signature fits the app's key.
cp "$work/message2" "$work/update.dmg"
# Release notes with everything XML could trip over.
# shellcheck disable=SC2016 # the backticks are Markdown, not a command
printf '%s\n' '- Settings > `Check for Updates…` opens Sparkle' '- a < b && c > d, ]]> and <b>&amp;</b> 한글' > "$work/notes.md"

# The stand-in for sign_update. It signs nothing: it prints $STAND_IN_PRINTS and exits with $STAND_IN_STATUS, after
# noting in $STAND_IN_LOG what it was started with. make-appcast.sh must start it with "-p --ed-key-file - <dmg>",
# the key text on standard input, and no SPARKLE_PRIVATE_KEY in the environment.
mkdir "$work/bin"
cat > "$work/bin/sign_update" << 'STAND_IN'
#!/bin/sh
IFS= read -r input || true
{
  echo "arguments: $*"
  echo "standard input: $input"
  if [ -n "${SPARKLE_PRIVATE_KEY+set}" ]; then echo "environment: SPARKLE_PRIVATE_KEY is set"; else echo "environment: clean"; fi
} > "$STAND_IN_LOG"
echo "$STAND_IN_PRINTS"
exit "${STAND_IN_STATUS:-0}"
STAND_IN
chmod +x "$work/bin/sign_update"
not_a_key="stand-in text (not a key)"
export STAND_IN_LOG="$work/sign_update.log"
url="https://github.com/hyunseop827/menu-pulse/releases/download/v9.8.7/MenuPulse-9.8.7.dmg"

output=""
appcast() { # <expected exit status> <what> <app> <url> [VARIABLE=value…]: runs make-appcast.sh; its output is in $output
  local expected="$1" what="$2" app="$3" address="$4" status=0
  shift 4
  rm -f "$work/appcast.xml" "$work/appcast.xml.tmp" "$STAND_IN_LOG"
  output="$(env SPARKLE_BIN="$work/bin" SPARKLE_PRIVATE_KEY="$not_a_key" STAND_IN_PRINTS="$sig2" "$@" \
    bash .github/scripts/make-appcast.sh "$work/$app.app" "$work/update.dmg" "$address" "$work/notes.md" \
    "$work/appcast.xml" 2>&1)" || status=$?
  [[ $status == "$expected" ]] || fail "make-appcast.sh: $what exited with $status, not $expected: $output"
  if [[ $expected != 0 && ( -e "$work/appcast.xml" || -e "$work/appcast.xml.tmp" ) ]]; then
    fail "make-appcast.sh: $what failed but left a feed file."
  fi
  [[ "$output" != *"$not_a_key"* ]] || fail "make-appcast.sh: $what printed the text given as the key."
}
feed() { xmllint --xpath "string($1)" "$work/appcast.xml"; }
expect() { # <what> <actual> <expected>
  [[ "$2" == "$3" ]] || fail "make-appcast.sh: the feed's $1 is '$2', not '$3'."
}

appcast 0 "a good app and signature" good "$url"
xmllint --noout "$work/appcast.xml"
expect "item count" "$(feed 'count(//item)')" 1
expect "sparkle:version" "$(feed '//item/*[local-name()="version"]')" 57
expect "sparkle:shortVersionString" "$(feed '//item/*[local-name()="shortVersionString"]')" 9.8.7
expect "sparkle:minimumSystemVersion" "$(feed '//item/*[local-name()="minimumSystemVersion"]')" 13.0
expect "sparkle:hardwareRequirements" "$(feed '//item/*[local-name()="hardwareRequirements"]')" arm64
expect "enclosure url" "$(feed '//item/enclosure/@url')" "$url"
expect "enclosure length" "$(feed '//item/enclosure/@length')" 1
expect "sparkle:edSignature" "$(feed '//item/enclosure/@*[local-name()="edSignature"]')" "$sig2"
expect "description format" "$(feed '//item/description/@*[local-name()="format"]')" markdown
expect "release notes" "$(feed '//item/description')" "$(cat "$work/notes.md")"
expect "sign_update call" "$(cat "$STAND_IN_LOG")" "arguments: -p --ed-key-file - $work/update.dmg
standard input: $not_a_key
environment: clean"
appcast 0 "an http address on this Mac" good "http://127.0.0.1:8000/update.dmg"

appcast 1 "the placeholder key" placeholder "$url"
[[ "$output" == *PASTE_PUBLIC_KEY_FROM_generate_keys* && ! -e "$STAND_IN_LOG" ]] ||
  fail "make-appcast.sh ran sign_update with the placeholder key, or did not say why it stopped: $output"
appcast 1 "a signature that does not fit the app's key" good "$url" STAND_IN_PRINTS="$sig3"
appcast 1 "output that is not a signature" good "$url" STAND_IN_PRINTS="ERROR! this is not a signature"
appcast 1 "a failing sign_update whose output contains the key" good "$url" \
  STAND_IN_PRINTS="unable to decode $not_a_key" STAND_IN_STATUS=1
appcast 1 "no key" good "$url" SPARKLE_PRIVATE_KEY=
[[ ! -e "$STAND_IN_LOG" ]] || fail "make-appcast.sh ran sign_update without a key."
appcast 1 "build number 0" zero "$url"
appcast 1 "build number 057" padded "$url"
appcast 1 "an http address" good "http://github.com/hyunseop827/menu-pulse/releases/download/v9.8.7/x.dmg"
appcast 1 "an address with a line break" good "$url
"
appcast 1 "an address with a quote" good "$url\"x"
echo 'Release tool checks passed.'
