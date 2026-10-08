#!/usr/bin/env bash
# Selects the newest released Xcode 26.x on a GitHub macOS runner, where the versions are installed side by side as
# /Applications/Xcode_<version>.app, with `sudo xcode-select --switch`. The Makefile's `xcrun clang` and
# `xcrun --show-sdk-path` then use that Xcode. Run by .github/workflows/ci.yml and release.yml before the first
# build. bash 3.2 compatible (the system bash on macOS).
#
# Only major version 26, on purpose. A newer major version must not be picked up just because a runner image gained
# it: the app is built with -Wall -Wextra -Werror, so a new compiler can fail the build with a new warning, and a new
# SDK changes how macOS treats the app (Makefile, OBJC_FLAGS). Raising `major` below is a deliberate change, to be
# tried on a pull request first.
#
# Optional environment:
#   XCODE_SEARCH_ROOT  folder that holds the Xcode_<version>.app bundles (default /Applications); for trying the
#                      selection against a fake folder, with stub sudo and xcodebuild first in PATH
set -euo pipefail

root="${XCODE_SEARCH_ROOT:-/Applications}"
major=26
best="" best_version=""
for app in "$root"/Xcode_*.app; do
  [[ -d "$app" ]] || continue
  # The bundle's own name decides, not the name it was found under: runner images give betas a plain-version link too
  # (Xcode_27.2.app → Xcode_27.2_beta.app). A link to a release (Xcode_26.4.app → Xcode_26.4.1.app) counts as 26.4.1.
  real="$(cd "$app" && pwd -P)" || continue
  name="${real##*/}"
  [[ "$name" == Xcode_*.app ]] || continue
  version="${name#Xcode_}"
  version="${version%.app}"
  # Released versions only (Xcode_26.6.app, Xcode_26.4.1.app), never betas or release candidates.
  [[ "$version" =~ ^[0-9]+(\.[0-9]+)*$ ]] || continue
  (( 10#${version%%.*} == major )) || continue
  if [[ -z "$best" || "$(printf '%s\n%s\n' "$best_version" "$version" | sort -V | tail -n 1)" == "$version" ]]; then
    best="$real" best_version="$version"
  fi
done
if [[ -z "$best" ]]; then
  echo "::error::This runner has no released Xcode $major.x: $(echo "$root"/Xcode*.app)"
  exit 1
fi
developer_dir="$best/Contents/Developer"
sudo xcode-select --switch "$developer_dir"
echo "Selected $developer_dir"
xcodebuild -version
