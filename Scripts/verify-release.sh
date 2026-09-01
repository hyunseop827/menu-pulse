#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TAG="${1:-}"
VERIFY_DIR=""

fail() {
  echo "verify-release: $*" >&2
  exit 1
}

cleanup() {
  local verify_parent=""
  local expected_parent=""

  if [[ -n "$VERIFY_DIR" && -d "$VERIFY_DIR" ]]; then
    verify_parent="$(cd "$(dirname "$VERIFY_DIR")" && pwd -P)"
    expected_parent="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
  fi
  if [[ -n "$VERIFY_DIR" && "$(basename "$VERIFY_DIR")" == menu-pulse-release-verify.* &&
        "$verify_parent" == "$expected_parent" ]]; then
    /bin/rm -rf -- "$VERIFY_DIR"
  fi
}
trap cleanup EXIT

[[ "$TAG" =~ ^v(0|[1-9][0-9]*)[.](0|[1-9][0-9]*)[.](0|[1-9][0-9]*)$ ]] || \
  fail "usage: Scripts/verify-release.sh v1.2.0"
command -v gh >/dev/null 2>&1 || fail "GitHub CLI is required"

cd "$ROOT_DIR"
REPOSITORY="${MENU_PULSE_REPOSITORY:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
[[ -n "$REPOSITORY" ]] || fail "could not determine the GitHub repository"

VERIFY_DIR="$(/usr/bin/mktemp -d -t menu-pulse-release-verify)"
gh release download "$TAG" \
  --repo "$REPOSITORY" \
  --dir "$VERIFY_DIR" \
  --pattern MenuPulse.dmg \
  --pattern SHA256SUMS.txt

[[ -f "$VERIFY_DIR/MenuPulse.dmg" ]] || fail "published DMG is missing"
[[ -f "$VERIFY_DIR/SHA256SUMS.txt" ]] || fail "published checksum is missing"
(
  cd "$VERIFY_DIR"
  /usr/bin/shasum -a 256 -c SHA256SUMS.txt
)
/usr/bin/hdiutil verify "$VERIFY_DIR/MenuPulse.dmg" >/dev/null

echo "Published $TAG checksum and DMG verified from GitHub Release."
