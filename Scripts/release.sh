#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFO_PLIST="$ROOT_DIR/Packaging/Info.plist"
BUNDLE_ID="dev.hyunseop.MenuPulse"
APP_PATH="$ROOT_DIR/build/release/Menu Pulse.app"
DMG_PATH="$ROOT_DIR/dist/MenuPulse.dmg"
INFO_BACKUP=""
RESTORE_INFO=0

usage() {
  echo "Usage: Scripts/release.sh v1.2.0"
  echo "       Scripts/release.sh 1.2.0"
}

fail() {
  echo "release: $*" >&2
  return 1
}

is_canonical_version() {
  [[ "$1" =~ ^(0|[1-9][0-9]*)[.](0|[1-9][0-9]*)[.](0|[1-9][0-9]*)$ ]]
}

compare_versions() {
  local left_major=0 left_minor=0 left_patch=0
  local right_major=0 right_minor=0 right_patch=0

  IFS=. read -r left_major left_minor left_patch <<< "$1"
  IFS=. read -r right_major right_minor right_patch <<< "$2"

  if (( 10#$left_major < 10#$right_major )); then echo -1; return; fi
  if (( 10#$left_major > 10#$right_major )); then echo 1; return; fi
  if (( 10#$left_minor < 10#$right_minor )); then echo -1; return; fi
  if (( 10#$left_minor > 10#$right_minor )); then echo 1; return; fi
  if (( 10#$left_patch < 10#$right_patch )); then echo -1; return; fi
  if (( 10#$left_patch > 10#$right_patch )); then echo 1; return; fi
  echo 0
}

plist_value() {
  local plist_path="$1"
  local key="$2"
  /usr/libexec/PlistBuddy -c "Print :$key" "$plist_path" 2>/dev/null
}

validate_release_app() {
  local expected_version="$1"
  local actual_bundle_id=""
  local short_version=""
  local bundle_version=""
  local executable_path="$APP_PATH/Contents/MacOS/MenuPulse"

  [[ -d "$APP_PATH" && ! -L "$APP_PATH" ]] || fail "built app is missing: $APP_PATH"
  actual_bundle_id="$(plist_value "$APP_PATH/Contents/Info.plist" CFBundleIdentifier)" || fail "built app has no bundle identifier"
  short_version="$(plist_value "$APP_PATH/Contents/Info.plist" CFBundleShortVersionString)" || fail "built app has no short version"
  bundle_version="$(plist_value "$APP_PATH/Contents/Info.plist" CFBundleVersion)" || fail "built app has no bundle version"

  [[ "$actual_bundle_id" == "$BUNDLE_ID" ]] || fail "built app bundle identifier is $actual_bundle_id, expected $BUNDLE_ID"
  [[ "$short_version" == "$expected_version" && "$bundle_version" == "$expected_version" ]] || \
    fail "built app version does not match $expected_version"
  /usr/bin/codesign --verify --strict "$APP_PATH" >/dev/null 2>&1 || fail "built app code signature is invalid"
  [[ "$(/usr/bin/lipo -archs "$executable_path")" == "arm64" ]] || \
    fail "built app must contain only the arm64 architecture"
}

assert_only_version_change() {
  local status_line=""

  while IFS= read -r status_line; do
    [[ -n "$status_line" ]] || continue
    case "$status_line" in
      " M Packaging/Info.plist"|"M  Packaging/Info.plist") ;;
      *) fail "unexpected working tree change during release: $status_line" ;;
    esac
  done < <(git status --porcelain --untracked-files=all)
}

validate_release_commit() (
  set -euo pipefail

  local commit="$1"
  local expected_parent="$2"
  local tag="$3"
  local version="${tag#v}"
  local commit_sha=""
  local parent_line=""
  local listed_commit=""
  local first_parent=""
  local extra_parent=""
  local changed_files=""
  local subject=""
  local validation_dir=""
  local parent_plist=""
  local expected_plist=""
  local committed_plist=""

  commit_sha="$(git rev-parse "$commit^{commit}")" || { fail "cannot resolve release commit $commit"; exit 1; }
  expected_parent="$(git rev-parse "$expected_parent^{commit}")" || { fail "cannot resolve expected release parent"; exit 1; }
  parent_line="$(git rev-list --parents -n 1 "$commit_sha")" || { fail "cannot read release commit parents"; exit 1; }
  read -r listed_commit first_parent extra_parent <<< "$parent_line"
  [[ "$listed_commit" == "$commit_sha" && "$first_parent" == "$expected_parent" && -z "$extra_parent" ]] || \
    { fail "release commit must have origin/main as its only parent"; exit 1; }

  subject="$(git show -s --format=%s "$commit_sha")" || { fail "cannot read release commit subject"; exit 1; }
  [[ "$subject" == "Release $tag" ]] || { fail "release commit subject must be 'Release $tag'"; exit 1; }

  changed_files="$(git diff-tree --no-commit-id --name-only -r "$commit_sha")" || \
    { fail "cannot read release commit changes"; exit 1; }
  [[ "$changed_files" == "Packaging/Info.plist" ]] || \
    { fail "release commit must change only Packaging/Info.plist"; exit 1; }

  validation_dir="$(/usr/bin/mktemp -d -t menu-pulse-release-commit)" || \
    { fail "cannot create release validation directory"; exit 1; }
  trap '/bin/rm -rf -- "$validation_dir"' EXIT
  parent_plist="$validation_dir/parent.plist"
  expected_plist="$validation_dir/expected.plist"
  committed_plist="$validation_dir/committed.plist"

  git show "$expected_parent:Packaging/Info.plist" > "$parent_plist" || \
    { fail "release parent has no Packaging/Info.plist"; exit 1; }
  git show "$commit_sha:Packaging/Info.plist" > "$committed_plist" || \
    { fail "release commit has no Packaging/Info.plist"; exit 1; }
  /bin/cp "$parent_plist" "$expected_plist" || { fail "cannot prepare release commit validation"; exit 1; }
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$expected_plist" || \
    { fail "release parent has no short version"; exit 1; }
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $version" "$expected_plist" || \
    { fail "release parent has no bundle version"; exit 1; }
  /usr/bin/cmp -s "$expected_plist" "$committed_plist" || \
    { fail "release commit contains changes beyond the two version values"; exit 1; }
  [[ "$(plist_value "$committed_plist" CFBundleIdentifier)" == "$BUNDLE_ID" ]] || \
    { fail "release commit changed the bundle identifier"; exit 1; }
)

release_cleanup() {
  local exit_status="$1"
  trap - EXIT

  if (( exit_status != 0 && RESTORE_INFO == 1 )) && [[ -n "$INFO_BACKUP" && -f "$INFO_BACKUP" ]]; then
    git restore --staged -- Packaging/Info.plist >/dev/null 2>&1 || true
    /bin/cp "$INFO_BACKUP" "$INFO_PLIST"
    echo "release: restored Packaging/Info.plist after failure" >&2
  fi
  if [[ -n "$INFO_BACKUP" && -f "$INFO_BACKUP" ]]; then
    /bin/rm -f -- "$INFO_BACKUP"
  fi

  exit "$exit_status"
}

wait_for_release_and_verify() {
  local tag="$1"
  local expected_tag_sha=""
  local run_id=""
  local run_head_sha=""
  local run_conclusion=""
  local attempt=0

  command -v gh >/dev/null 2>&1 || { fail "GitHub CLI is required to verify the published release"; return 1; }
  expected_tag_sha="$(git rev-parse "$tag^{commit}")" || { fail "cannot resolve commit for $tag"; return 1; }
  while (( attempt < 30 )); do
    if ! run_id="$(gh run list \
      --workflow release.yml \
      --branch "$tag" \
      --event push \
      --limit 20 \
      --json databaseId,headSha \
      --jq "map(select(.headSha == \"$expected_tag_sha\"))[0].databaseId // empty")"; then
      fail "cannot list GitHub Release workflow runs"
      return 1
    fi
    [[ -z "$run_id" ]] || break
    /bin/sleep 2
    attempt=$((attempt + 1))
  done

  [[ -n "$run_id" ]] || { fail "GitHub Release workflow did not appear for $tag at $expected_tag_sha"; return 1; }
  run_head_sha="$(gh run view "$run_id" --json headSha --jq '.headSha')" || \
    { fail "cannot read GitHub Release workflow $run_id"; return 1; }
  [[ "$run_head_sha" == "$expected_tag_sha" ]] || \
    { fail "GitHub Release workflow head $run_head_sha does not match $tag at $expected_tag_sha"; return 1; }
  if ! gh run watch "$run_id" --exit-status; then
    fail "GitHub Release workflow failed for $tag"
    return 1
  fi
  run_head_sha="$(gh run view "$run_id" --json headSha --jq '.headSha')" || \
    { fail "cannot re-read GitHub Release workflow $run_id"; return 1; }
  run_conclusion="$(gh run view "$run_id" --json conclusion --jq '.conclusion')" || \
    { fail "cannot read GitHub Release workflow conclusion"; return 1; }
  [[ "$run_head_sha" == "$expected_tag_sha" ]] || \
    { fail "completed workflow head $run_head_sha does not match $tag at $expected_tag_sha"; return 1; }
  [[ "$run_conclusion" == "success" ]] || \
    { fail "GitHub Release workflow conclusion is $run_conclusion"; return 1; }
  "$ROOT_DIR/Scripts/verify-release.sh" "$tag" || { fail "published release verification failed"; return 1; }
}

main() {
  local input="${1:-}"
  local version=""
  local tag=""
  local branch=""
  local local_head=""
  local remote_head=""
  local current_short_version=""
  local current_bundle_version=""
  local current_bundle_id=""
  local latest_version=""
  local existing_tag=""
  local existing_version=""
  local local_tag_exists=0
  local remote_tag_exists=0
  local tag_commit=""
  local release_resume=0
  local already_pushed=0

  if [[ -z "$input" || "$input" == "-h" || "$input" == "--help" ]]; then
    usage
    [[ -z "$input" ]] && return 1 || return 0
  fi

  version="${input#v}"
  tag="v$version"
  is_canonical_version "$version" || fail "version must be canonical, for example v1.2.0 or 1.2.0"

  cd "$ROOT_DIR"
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "not inside a git repository"
  branch="$(git branch --show-current)"
  [[ "$branch" == "main" ]] || fail "releases are allowed only from main; current branch is ${branch:-detached HEAD}"
  git remote get-url origin >/dev/null 2>&1 || fail "origin remote is missing"
  command -v gh >/dev/null 2>&1 || fail "GitHub CLI is required"
  [[ -z "$(git status --porcelain --untracked-files=all)" ]] || fail "working tree is not clean; commit or stash changes first"

  git fetch --tags origin "+refs/heads/main:refs/remotes/origin/main"
  [[ -z "$(git status --porcelain --untracked-files=all)" ]] || fail "working tree changed during fetch"
  local_head="$(git rev-parse HEAD)"
  remote_head="$(git rev-parse refs/remotes/origin/main)"
  if git rev-parse -q --verify "refs/tags/$tag" >/dev/null 2>&1; then
    local_tag_exists=1
    tag_commit="$(git rev-list -n 1 "$tag")"
    [[ "$tag_commit" == "$local_head" ]] || fail "existing tag $tag does not point to HEAD"
  fi
  if git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1; then
    remote_tag_exists=1
  fi

  if (( remote_tag_exists == 1 )); then
    [[ "$local_tag_exists" == 1 && "$tag_commit" == "$remote_head" && "$local_head" == "$remote_head" ]] || \
      fail "remote tag $tag does not match local main and origin/main"
    release_resume=1
    already_pushed=1
  elif (( local_tag_exists == 1 )); then
    if [[ "$local_head" != "$remote_head" ]]; then
      validate_release_commit "$local_head" "$remote_head" "$tag" || \
        fail "local main may be ahead of origin/main only by the exact release commit"
    fi
    release_resume=1
  elif [[ "$local_head" != "$remote_head" ]]; then
    validate_release_commit "$local_head" "$remote_head" "$tag" || \
      fail "local main may be ahead of origin/main only by the exact release commit"
    release_resume=1
  fi

  while IFS= read -r existing_tag; do
    existing_version="${existing_tag#v}"
    is_canonical_version "$existing_version" || continue
    if [[ -z "$latest_version" || "$(compare_versions "$existing_version" "$latest_version")" == "1" ]]; then
      latest_version="$existing_version"
    fi
  done < <(git tag --list 'v*')
  if [[ -n "$latest_version" ]]; then
    if (( release_resume == 1 && local_tag_exists == 1 )); then
      [[ "$(compare_versions "$version" "$latest_version")" == "0" ]] || \
        fail "resume version $version must match the latest tag v$latest_version"
    elif [[ "$(compare_versions "$version" "$latest_version")" != "1" ]]; then
      fail "version $version must be newer than the latest tag v$latest_version"
    fi
  fi

  current_bundle_id="$(plist_value "$INFO_PLIST" CFBundleIdentifier)" || fail "cannot read CFBundleIdentifier"
  current_short_version="$(plist_value "$INFO_PLIST" CFBundleShortVersionString)" || fail "cannot read CFBundleShortVersionString"
  current_bundle_version="$(plist_value "$INFO_PLIST" CFBundleVersion)" || fail "cannot read CFBundleVersion"
  [[ "$current_bundle_id" == "$BUNDLE_ID" ]] || fail "unexpected bundle identifier: $current_bundle_id"
  is_canonical_version "$current_short_version" || fail "current short version is not canonical: $current_short_version"
  [[ "$current_bundle_version" == "$current_short_version" ]] || fail "current bundle versions do not match"
  if [[ "$(compare_versions "$version" "$current_short_version")" == "-1" ]]; then
    fail "version $version cannot be older than current version $current_short_version"
  fi
  if (( release_resume == 1 )); then
    [[ "$current_short_version" == "$version" ]] || fail "resume version does not match Packaging/Info.plist"
  fi

  INFO_BACKUP="$(/usr/bin/mktemp -t menu-pulse-release-info)"
  /bin/cp "$INFO_PLIST" "$INFO_BACKUP"
  RESTORE_INFO=1
  trap 'release_cleanup $?' EXIT

  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $version" "$INFO_PLIST"
  [[ "$(plist_value "$INFO_PLIST" CFBundleShortVersionString)" == "$version" ]] || fail "failed to set short version"
  [[ "$(plist_value "$INFO_PLIST" CFBundleVersion)" == "$version" ]] || fail "failed to set bundle version"
  assert_only_version_change

  Scripts/analyze.sh
  Scripts/test.sh
  Scripts/build-dmg.sh
  validate_release_app "$version"
  [[ -f "$DMG_PATH" ]] || fail "DMG was not created: $DMG_PATH"
  /usr/bin/hdiutil verify "$DMG_PATH" >/dev/null || fail "DMG verification failed"
  assert_only_version_change

  if (( release_resume == 1 )); then
    echo "Resuming $tag from the existing release commit or tag."
  elif git diff --quiet -- Packaging/Info.plist; then
    echo "Packaging/Info.plist is already at $version; skipping version commit."
  else
    git add Packaging/Info.plist
    git commit -m "Release $tag"
    validate_release_commit HEAD "$remote_head" "$tag"
  fi
  RESTORE_INFO=0

  [[ -z "$(git status --porcelain --untracked-files=all)" ]] || fail "working tree is not clean after version commit"
  [[ "$(plist_value "$INFO_PLIST" CFBundleShortVersionString)" == "$version" ]] || fail "committed short version does not match $tag"
  [[ "$(plist_value "$INFO_PLIST" CFBundleVersion)" == "$version" ]] || fail "committed bundle version does not match $tag"

  if (( local_tag_exists == 0 )); then
    git tag -a "$tag" -m "Release $tag"
  fi
  [[ "$(git rev-list -n 1 "$tag")" == "$(git rev-parse HEAD)" ]] || fail "tag does not point to HEAD"
  if (( already_pushed == 0 )); then
    git push --atomic origin main "$tag"
    echo "Pushed $tag from main. Waiting for GitHub Release verification."
  else
    echo "$tag is already on origin. Resuming GitHub Release verification."
  fi

  wait_for_release_and_verify "$tag"
  echo "$tag is published and verified."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
