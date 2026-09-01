#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_ID="dev.hyunseop.MenuPulse"
APP_NAME="Menu Pulse.app"
EXECUTABLE_NAME="MenuPulse"
BUILD_APP_PATH="$ROOT_DIR/build/release/$APP_NAME"
REQUESTED_INSTALL_DIR="${MENU_PULSE_INSTALL_DIR:-/Applications}"
SYSTEM_APPLICATIONS_DIR="${MENU_PULSE_SYSTEM_APPLICATIONS_DIR:-/Applications}"
USER_APPLICATIONS_DIR="${MENU_PULSE_USER_APPLICATIONS_DIR:-$HOME/Applications}"
LEGACY_PLIST_PATH="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
INSTALL_DIR_RESOLVED=""
INSTALL_APP_PATH=""
STAGING_DIR=""
BACKUP_APP_PATH=""
BACKUP_CREATED=0
NEW_AT_TARGET=0
INSTALL_COMMITTED=0

fail() {
  echo "install: $*" >&2
  return 1
}

bundle_value() {
  local app_path="$1"
  local key="$2"
  /usr/libexec/PlistBuddy -c "Print :$key" "$app_path/Contents/Info.plist" 2>/dev/null
}

has_expected_bundle_id() {
  local app_path="$1"
  local actual_bundle_id=""

  [[ -d "$app_path" && ! -L "$app_path" ]] || return 1
  actual_bundle_id="$(bundle_value "$app_path" CFBundleIdentifier)" || return 1
  [[ "$actual_bundle_id" == "$BUNDLE_ID" ]]
}

validate_app() {
  local app_path="$1"
  local expected_version="${2:-}"
  local actual_bundle_id=""
  local short_version=""
  local bundle_version=""
  local executable=""

  [[ -d "$app_path" && ! -L "$app_path" ]] || {
    fail "app bundle is missing or is a symbolic link: $app_path"
    return 1
  }

  actual_bundle_id="$(bundle_value "$app_path" CFBundleIdentifier)" || {
    fail "cannot read CFBundleIdentifier from $app_path"
    return 1
  }
  [[ "$actual_bundle_id" == "$BUNDLE_ID" ]] || {
    fail "unexpected bundle identifier at $app_path: $actual_bundle_id"
    return 1
  }

  short_version="$(bundle_value "$app_path" CFBundleShortVersionString)" || {
    fail "cannot read CFBundleShortVersionString from $app_path"
    return 1
  }
  bundle_version="$(bundle_value "$app_path" CFBundleVersion)" || {
    fail "cannot read CFBundleVersion from $app_path"
    return 1
  }
  [[ -n "$short_version" && "$bundle_version" == "$short_version" ]] || {
    fail "bundle versions do not match at $app_path"
    return 1
  }
  if [[ -n "$expected_version" && "$short_version" != "$expected_version" ]]; then
    fail "expected version $expected_version at $app_path, found $short_version"
    return 1
  fi

  executable="$(bundle_value "$app_path" CFBundleExecutable)" || {
    fail "cannot read CFBundleExecutable from $app_path"
    return 1
  }
  [[ "$executable" == "$EXECUTABLE_NAME" ]] || {
    fail "unexpected executable name at $app_path: $executable"
    return 1
  }
  [[ -x "$app_path/Contents/MacOS/$EXECUTABLE_NAME" ]] || {
    fail "app executable is missing at $app_path"
    return 1
  }
  [[ "$(/usr/bin/lipo -archs "$app_path/Contents/MacOS/$EXECUTABLE_NAME")" == "arm64" ]] || \
    {
      fail "app executable must contain only the arm64 architecture at $app_path"
      return 1
    }
  /usr/bin/codesign --verify --strict "$app_path" >/dev/null 2>&1 || {
    fail "code signature verification failed at $app_path"
    return 1
  }
}

running_app_pids() {
  /usr/bin/osascript -l JavaScript -e \
    "ObjC.import('AppKit'); $.NSRunningApplication.runningApplicationsWithBundleIdentifier('$BUNDLE_ID').js.map(function(app) { return String(app.processIdentifier); }).join(' ');" \
    2>/dev/null || true
}

stop_running_app() {
  local pids=""
  local attempt=0

  pids="$(running_app_pids)"
  [[ -n "$pids" ]] || return 0

  /usr/bin/osascript -l JavaScript -e \
    "ObjC.import('AppKit'); $.NSRunningApplication.runningApplicationsWithBundleIdentifier('$BUNDLE_ID').js.forEach(function(app) { app.terminate; });" \
    >/dev/null 2>&1 || true

  while (( attempt < 50 )); do
    [[ -z "$(running_app_pids)" ]] && return 0
    /bin/sleep 0.1
    attempt=$((attempt + 1))
  done

  /usr/bin/osascript -l JavaScript -e \
    "ObjC.import('AppKit'); $.NSRunningApplication.runningApplicationsWithBundleIdentifier('$BUNDLE_ID').js.forEach(function(app) { app.forceTerminate; });" \
    >/dev/null 2>&1 || true

  attempt=0
  while (( attempt < 20 )); do
    [[ -z "$(running_app_pids)" ]] && return 0
    /bin/sleep 0.1
    attempt=$((attempt + 1))
  done

  fail "could not stop the running $BUNDLE_ID app"
}

remove_exact_app() {
  local app_path="$1"

  [[ -e "$app_path" || -L "$app_path" ]] || return 0
  if ! has_expected_bundle_id "$app_path"; then
    echo "install: refusing to remove an app without bundle identifier $BUNDLE_ID: $app_path" >&2
    return 1
  fi

  /bin/rm -rf -- "$app_path"
}

build_release_app() {
  "$ROOT_DIR/Scripts/build-app.sh"
}

unregister_existing_login_items() {
  "$ROOT_DIR/Scripts/uninstall.sh" --login-items-only >/dev/null
}

register_installed_login_item() {
  local installed_bin_path="$1"
  "$installed_bin_path" --register-login-item
}

mark_login_prompt_completed() {
  /usr/bin/defaults write "$BUNDLE_ID" hasCompletedOpenAtLoginPrompt -bool true
}

open_installed_app() {
  local installed_app_path="$1"
  /usr/bin/open "$installed_app_path"
}

cleanup_staging() {
  if [[ -n "$STAGING_DIR" && "$STAGING_DIR" == "$INSTALL_DIR_RESOLVED"/.menu-pulse-install.* ]]; then
    /bin/rm -rf -- "$STAGING_DIR"
  fi
}

install_exit_cleanup() {
  local exit_status="$1"
  local failed_app_path=""
  local recovery_failed=0
  trap - EXIT

  if (( exit_status != 0 && INSTALL_COMMITTED == 0 )); then
    failed_app_path="$STAGING_DIR/Failed $APP_NAME"
    if (( NEW_AT_TARGET == 1 )) && [[ -e "$INSTALL_APP_PATH" || -L "$INSTALL_APP_PATH" ]]; then
      if [[ "$INSTALL_APP_PATH" == "$INSTALL_DIR_RESOLVED/$APP_NAME" &&
            "$STAGING_DIR" == "$INSTALL_DIR_RESOLVED"/.menu-pulse-install.* ]]; then
        if ! /bin/mv "$INSTALL_APP_PATH" "$failed_app_path"; then
          recovery_failed=1
        fi
      else
        echo "install: refused to move an unexpected rollback target: $INSTALL_APP_PATH" >&2
        recovery_failed=1
      fi
    fi
    if (( BACKUP_CREATED == 1 )); then
      if [[ -d "$BACKUP_APP_PATH" && ! -e "$INSTALL_APP_PATH" ]] &&
          /usr/bin/ditto "$BACKUP_APP_PATH" "$INSTALL_APP_PATH" &&
          validate_app "$INSTALL_APP_PATH"; then
        echo "install: restored the previous app after installation failed" >&2
      else
        echo "install: automatic rollback failed; the backup is preserved at $BACKUP_APP_PATH" >&2
        recovery_failed=1
      fi
    fi
  fi

  if (( recovery_failed == 0 )); then
    cleanup_staging
  else
    echo "install: recovery files were preserved in $STAGING_DIR" >&2
  fi
  exit "$exit_status"
}

main() {
  local installed_bin_path=""
  local staged_app_path=""
  local expected_version=""
  local duplicate_dir=""
  local duplicate_app_path=""
  local login_message=""

  INSTALL_DIR_RESOLVED=""
  INSTALL_APP_PATH=""
  STAGING_DIR=""
  BACKUP_APP_PATH=""
  BACKUP_CREATED=0
  NEW_AT_TARGET=0
  INSTALL_COMMITTED=0

  /bin/mkdir -p "$REQUESTED_INSTALL_DIR"
  INSTALL_DIR_RESOLVED="$(cd "$REQUESTED_INSTALL_DIR" && pwd -P)"
  [[ -n "$INSTALL_DIR_RESOLVED" && "$INSTALL_DIR_RESOLVED" == /* && "$INSTALL_DIR_RESOLVED" != "/" ]] || \
    fail "install directory must resolve to an absolute, non-root path"

  INSTALL_APP_PATH="$INSTALL_DIR_RESOLVED/$APP_NAME"
  installed_bin_path="$INSTALL_APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"

  build_release_app
  validate_app "$BUILD_APP_PATH"
  expected_version="$(bundle_value "$BUILD_APP_PATH" CFBundleShortVersionString)"

  STAGING_DIR="$(/usr/bin/mktemp -d "$INSTALL_DIR_RESOLVED/.menu-pulse-install.XXXXXX")"
  staged_app_path="$STAGING_DIR/$APP_NAME"
  BACKUP_APP_PATH="$STAGING_DIR/Previous $APP_NAME"
  trap 'install_exit_cleanup $?' EXIT

  /usr/bin/ditto "$BUILD_APP_PATH" "$staged_app_path"
  validate_app "$staged_app_path" "$expected_version"

  if [[ -e "$INSTALL_APP_PATH" || -L "$INSTALL_APP_PATH" ]]; then
    has_expected_bundle_id "$INSTALL_APP_PATH" || fail "refusing to replace an app without bundle identifier $BUNDLE_ID: $INSTALL_APP_PATH"
  fi

  stop_running_app

  if [[ -d "$INSTALL_APP_PATH" ]]; then
    BACKUP_CREATED=1
    /bin/mv "$INSTALL_APP_PATH" "$BACKUP_APP_PATH"
  fi

  /bin/mv "$staged_app_path" "$INSTALL_APP_PATH"
  NEW_AT_TARGET=1
  validate_app "$INSTALL_APP_PATH" "$expected_version"
  INSTALL_COMMITTED=1

  # Do not alter the previous login-item state until the replacement has been
  # fully validated. A failure in the rollback window can then restore the old
  # app without also having to reconstruct ServiceManagement state.
  if ! unregister_existing_login_items; then
    echo "install: could not fully remove previous login-item registrations; continuing with the verified replacement" >&2
  fi

  for duplicate_dir in "$SYSTEM_APPLICATIONS_DIR" "$USER_APPLICATIONS_DIR"; do
    [[ -d "$duplicate_dir" ]] || continue
    duplicate_dir="$(cd "$duplicate_dir" && pwd -P)"
    duplicate_app_path="$duplicate_dir/$APP_NAME"
    [[ "$duplicate_app_path" == "$INSTALL_APP_PATH" ]] && continue
    if [[ -e "$duplicate_app_path" || -L "$duplicate_app_path" ]]; then
      remove_exact_app "$duplicate_app_path" || echo "install: left a non-matching duplicate path untouched" >&2
    fi
  done

  /bin/launchctl bootout "gui/$(/usr/bin/id -u)" "$LEGACY_PLIST_PATH" >/dev/null 2>&1 || true
  /bin/rm -f -- "$LEGACY_PLIST_PATH"

  if register_installed_login_item "$installed_bin_path"; then
    login_message="Open at login enabled."
  else
    login_message="Open at login needs approval in System Settings."
  fi

  # The installer has already made the login-item choice explicit. Persist the
  # one-time onboarding marker so the newly opened app does not ask again.
  if ! mark_login_prompt_completed; then
    echo "install: could not save the login prompt completion marker; the app may ask once at launch" >&2
  fi

  if ! open_installed_app "$INSTALL_APP_PATH"; then
    echo "install: installed successfully, but could not open the app" >&2
  fi

  echo "Menu Pulse $expected_version installed to $INSTALL_APP_PATH. $login_message"
  cleanup_staging
  trap - EXIT
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
