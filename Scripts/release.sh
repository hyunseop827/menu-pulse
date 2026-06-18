#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

usage() {
  echo "Usage: Scripts/release.sh v0.1.1"
  echo "       Scripts/release.sh 0.1.1"
}

fail() {
  echo "release: $*" >&2
  exit 1
}

INPUT="${1:-}"
if [[ -z "$INPUT" || "$INPUT" == "-h" || "$INPUT" == "--help" ]]; then
  usage
  [[ -z "$INPUT" ]] && exit 1 || exit 0
fi

VERSION="${INPUT#v}"
TAG="v$VERSION"

[[ "$VERSION" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]] || fail "version must look like v0.1.1 or 0.1.1"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "not inside a git repository"

BRANCH="$(git branch --show-current)"
[[ -n "$BRANCH" ]] || fail "detached HEAD is not supported"
git remote get-url origin >/dev/null 2>&1 || fail "origin remote is missing"

if [[ -n "$(git status --porcelain)" ]]; then
  fail "working tree is not clean; commit or stash changes first"
fi

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  fail "local tag already exists: $TAG"
fi

git fetch --tags origin
if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
  fail "remote tag already exists: $TAG"
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Packaging/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" Packaging/Info.plist

Scripts/build-dmg.sh

if git diff --quiet -- Packaging/Info.plist; then
  echo "Info.plist is already at $VERSION; skipping version commit."
else
  git add Packaging/Info.plist
  git commit -m "Release $TAG"
fi

git tag "$TAG"
git push origin "$BRANCH"
git push origin "$TAG"

echo "Pushed $TAG. GitHub Actions will build and publish the release."
