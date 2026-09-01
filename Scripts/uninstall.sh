#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_ID="dev.hyunseop.MenuPulse"
APP_NAME="Menu Pulse.app"
EXECUTABLE_NAME="MenuPulse"
DEFAULT_LIBRARY_DIR="$HOME/Library"
SYSTEM_APPLICATIONS_DIR="${MENU_PULSE_SYSTEM_APPLICATIONS_DIR:-/Applications}"
USER_APPLICATIONS_DIR="${MENU_PULSE_USER_APPLICATIONS_DIR:-$HOME/Applications}"
LIBRARY_DIR="${MENU_PULSE_LIBRARY_DIR:-$HOME/Library}"
LEGACY_PLIST_PATH="$LIBRARY_DIR/LaunchAgents/$BUNDLE_ID.plist"
UNINSTALL_HELPER_DIR=""
UNINSTALL_HELPER_APP=""
ACTIVE_APP_PATH=""
ACTIVE_APP_PARENT=""
ACTIVE_STAGE_DIR=""
ACTIVE_BACKUP_APP_PATH=""
ACTIVE_PARENT_CREATED=0
ACTIVE_ORIGINAL_MOVED=0
ACTIVE_HELPER_AT_TARGET=0

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

resolved_directory() {
  local directory_path="$1"
  local parent_path=""
  local base_name=""
  local resolved_parent=""

  [[ "$directory_path" == /* && "$directory_path" != "/" ]] || return 1
  if [[ -d "$directory_path" ]]; then
    resolved_parent="$(cd "$directory_path" && pwd -P)"
    [[ -n "$resolved_parent" && "$resolved_parent" != "/" ]] || return 1
    echo "$resolved_parent"
    return
  fi

  parent_path="$(dirname "$directory_path")"
  base_name="$(basename "$directory_path")"
  [[ -d "$parent_path" ]] || return 1
  resolved_parent="$(cd "$parent_path" && pwd -P)"
  [[ -n "$resolved_parent" && "$resolved_parent" != "/" ]] || return 1
  echo "$resolved_parent/$base_name"
}

is_valid_built_helper() {
  local app_path="$1"
  local executable=""
  local executable_path=""
  local short_version=""
  local bundle_version=""

  [[ -d "$app_path" && ! -L "$app_path" ]] || return 1
  [[ "$(bundle_value "$app_path" CFBundleIdentifier)" == "$BUNDLE_ID" ]] || return 1
  executable="$(bundle_value "$app_path" CFBundleExecutable)" || return 1
  [[ "$executable" == "$EXECUTABLE_NAME" ]] || return 1
  short_version="$(bundle_value "$app_path" CFBundleShortVersionString)" || return 1
  bundle_version="$(bundle_value "$app_path" CFBundleVersion)" || return 1
  [[ "$short_version" =~ ^(0|[1-9][0-9]*)[.](0|[1-9][0-9]*)[.](0|[1-9][0-9]*)$ ]] || return 1
  [[ "$bundle_version" == "$short_version" ]] || return 1

  executable_path="$app_path/Contents/MacOS/$EXECUTABLE_NAME"
  [[ -x "$executable_path" && ! -L "$executable_path" ]] || return 1
  [[ "$(/usr/bin/lipo -archs "$executable_path")" == "arm64" ]] || return 1
  /usr/bin/codesign --verify --strict "$app_path" >/dev/null 2>&1 || return 1
}

is_exact_trusted_helper_copy() {
  local app_path="$1"

  [[ -n "$UNINSTALL_HELPER_APP" ]] || return 1
  is_valid_built_helper "$app_path" || return 1
  /usr/bin/cmp -s \
    "$UNINSTALL_HELPER_APP/Contents/Info.plist" \
    "$app_path/Contents/Info.plist" || return 1
  /usr/bin/cmp -s \
    "$UNINSTALL_HELPER_APP/Contents/MacOS/$EXECUTABLE_NAME" \
    "$app_path/Contents/MacOS/$EXECUTABLE_NAME"
}

cleanup_active_app_stage() {
  local cleanup_failed=0

  if (( ACTIVE_HELPER_AT_TARGET == 1 )); then
    if [[ ! -e "$ACTIVE_APP_PATH" && ! -L "$ACTIVE_APP_PATH" ]]; then
      ACTIVE_HELPER_AT_TARGET=0
    elif [[ "$ACTIVE_APP_PATH" == "$ACTIVE_APP_PARENT/$APP_NAME" ]]; then
      /bin/rm -rf -- "$ACTIVE_APP_PATH"
      ACTIVE_HELPER_AT_TARGET=0
    else
      echo "uninstall: refusing to remove an unexpected app at $ACTIVE_APP_PATH" >&2
      cleanup_failed=1
    fi
  fi

  if (( ACTIVE_ORIGINAL_MOVED == 1 )); then
    if [[ -d "$ACTIVE_BACKUP_APP_PATH" && ! -L "$ACTIVE_BACKUP_APP_PATH" ]] &&
        [[ ! -e "$ACTIVE_APP_PATH" && ! -L "$ACTIVE_APP_PATH" ]] &&
        /bin/mv "$ACTIVE_BACKUP_APP_PATH" "$ACTIVE_APP_PATH"; then
      ACTIVE_ORIGINAL_MOVED=0
    elif [[ ! -e "$ACTIVE_BACKUP_APP_PATH" && ! -L "$ACTIVE_BACKUP_APP_PATH" ]] &&
        [[ -d "$ACTIVE_APP_PATH" && ! -L "$ACTIVE_APP_PATH" ]]; then
      ACTIVE_ORIGINAL_MOVED=0
    else
      echo "uninstall: automatic app restoration failed; recovery data remains at $ACTIVE_BACKUP_APP_PATH" >&2
      cleanup_failed=1
    fi
  fi

  if (( cleanup_failed == 0 )) && [[ -n "$ACTIVE_STAGE_DIR" ]]; then
    if [[ "$ACTIVE_STAGE_DIR" == "$ACTIVE_APP_PARENT"/.menu-pulse-uninstall.* ]]; then
      if [[ -d "$ACTIVE_STAGE_DIR" ]]; then
        /bin/rmdir "$ACTIVE_STAGE_DIR" 2>/dev/null || {
          echo "uninstall: could not remove the temporary directory $ACTIVE_STAGE_DIR" >&2
          cleanup_failed=1
        }
      elif [[ -e "$ACTIVE_STAGE_DIR" || -L "$ACTIVE_STAGE_DIR" ]]; then
        echo "uninstall: refusing an unexpected temporary path: $ACTIVE_STAGE_DIR" >&2
        cleanup_failed=1
      fi
    else
      echo "uninstall: refusing to remove an unexpected temporary directory: $ACTIVE_STAGE_DIR" >&2
      cleanup_failed=1
    fi
  fi

  if (( cleanup_failed == 0 && ACTIVE_PARENT_CREATED == 1 )); then
    if [[ -d "$ACTIVE_APP_PARENT" ]]; then
      /bin/rmdir "$ACTIVE_APP_PARENT" 2>/dev/null || {
        echo "uninstall: could not remove the temporary application directory $ACTIVE_APP_PARENT" >&2
        cleanup_failed=1
      }
    elif [[ -e "$ACTIVE_APP_PARENT" || -L "$ACTIVE_APP_PARENT" ]]; then
      echo "uninstall: refusing an unexpected application path: $ACTIVE_APP_PARENT" >&2
      cleanup_failed=1
    fi
  fi

  if (( cleanup_failed == 0 )); then
    ACTIVE_APP_PATH=""
    ACTIVE_APP_PARENT=""
    ACTIVE_STAGE_DIR=""
    ACTIVE_BACKUP_APP_PATH=""
    ACTIVE_PARENT_CREATED=0
    ACTIVE_ORIGINAL_MOVED=0
    ACTIVE_HELPER_AT_TARGET=0
  fi

  (( cleanup_failed == 0 ))
}

cleanup_uninstall_helper() {
  local helper_parent=""
  local expected_parent=""

  if [[ -n "$UNINSTALL_HELPER_DIR" && -d "$UNINSTALL_HELPER_DIR" ]]; then
    helper_parent="$(cd "$(dirname "$UNINSTALL_HELPER_DIR")" && pwd -P)"
    expected_parent="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
  fi
  if [[ -n "$UNINSTALL_HELPER_DIR" &&
        "$(basename "$UNINSTALL_HELPER_DIR")" == menu-pulse-uninstall-helper.* &&
        "$helper_parent" == "$expected_parent" ]]; then
    /bin/rm -rf -- "$UNINSTALL_HELPER_DIR"
  fi
  UNINSTALL_HELPER_DIR=""
  UNINSTALL_HELPER_APP=""
}

cleanup_uninstall_state() {
  cleanup_active_app_stage || true
  cleanup_uninstall_helper
}

build_trusted_uninstall_helper() {
  local helper_temp_root=""

  [[ -d "${TMPDIR:-/tmp}" ]] || {
    echo "uninstall: TMPDIR must refer to an existing directory" >&2
    return 1
  }
  helper_temp_root="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
  [[ -n "$helper_temp_root" && "$helper_temp_root" != "/" ]] || {
    echo "uninstall: TMPDIR must resolve to a non-root directory" >&2
    return 1
  }
  UNINSTALL_HELPER_DIR="$(/usr/bin/mktemp -d "$helper_temp_root/menu-pulse-uninstall-helper.XXXXXX")"
  if ! MENU_PULSE_BUILD_DIR="$UNINSTALL_HELPER_DIR" "$ROOT_DIR/Scripts/build-app.sh" >/dev/null; then
    echo "uninstall: could not build the trusted login item helper" >&2
    return 1
  fi

  UNINSTALL_HELPER_APP="$UNINSTALL_HELPER_DIR/$APP_NAME"
  is_valid_built_helper "$UNINSTALL_HELPER_APP" || {
    echo "uninstall: the freshly built login item helper failed validation" >&2
    return 1
  }
}

run_trusted_helper_at_app_path() {
  local app_path="$1"
  local had_original=0

  [[ -n "$UNINSTALL_HELPER_APP" ]] || {
    echo "uninstall: trusted login item helper is unavailable" >&2
    return 1
  }
  [[ "$app_path" == /* && "$(basename "$app_path")" == "$APP_NAME" ]] || {
    echo "uninstall: refusing an unexpected login item path: $app_path" >&2
    return 1
  }

  ACTIVE_APP_PATH="$app_path"
  ACTIVE_APP_PARENT="$(dirname "$app_path")"
  ACTIVE_STAGE_DIR=""
  ACTIVE_BACKUP_APP_PATH=""
  ACTIVE_PARENT_CREATED=0
  ACTIVE_ORIGINAL_MOVED=0
  ACTIVE_HELPER_AT_TARGET=0

  if [[ ! -d "$ACTIVE_APP_PARENT" ]]; then
    ACTIVE_PARENT_CREATED=1
    if ! /bin/mkdir "$ACTIVE_APP_PARENT"; then
      cleanup_active_app_stage || true
      return 1
    fi
  fi
  if ! ACTIVE_STAGE_DIR="$(/usr/bin/mktemp -d "$ACTIVE_APP_PARENT/.menu-pulse-uninstall.XXXXXX")"; then
    cleanup_active_app_stage || true
    return 1
  fi
  ACTIVE_BACKUP_APP_PATH="$ACTIVE_STAGE_DIR/Original $APP_NAME"

  if [[ -e "$ACTIVE_APP_PATH" || -L "$ACTIVE_APP_PATH" ]]; then
    if ! has_expected_bundle_id "$ACTIVE_APP_PATH"; then
      echo "uninstall: refusing to stage an app without bundle identifier $BUNDLE_ID: $ACTIVE_APP_PATH" >&2
      cleanup_active_app_stage || true
      return 1
    fi
    had_original=1
    ACTIVE_ORIGINAL_MOVED=1
    if ! /bin/mv "$ACTIVE_APP_PATH" "$ACTIVE_BACKUP_APP_PATH"; then
      cleanup_active_app_stage || true
      return 1
    fi
  fi

  ACTIVE_HELPER_AT_TARGET=1
  if ! /usr/bin/ditto "$UNINSTALL_HELPER_APP" "$ACTIVE_APP_PATH"; then
    cleanup_active_app_stage || true
    return 1
  fi
  if ! is_exact_trusted_helper_copy "$ACTIVE_APP_PATH"; then
    echo "uninstall: the staged login item helper failed exact-copy validation" >&2
    cleanup_active_app_stage || true
    return 1
  fi

  if ! "$ACTIVE_APP_PATH/Contents/MacOS/$EXECUTABLE_NAME" --unregister-login-item; then
    echo "uninstall: login item removal failed at $ACTIVE_APP_PATH" >&2
    cleanup_active_app_stage || true
    return 1
  fi

  if ! cleanup_active_app_stage; then
    return 1
  fi
  if (( had_original == 1 )) && ! has_expected_bundle_id "$app_path"; then
    echo "uninstall: the original app was not restored at $app_path" >&2
    return 1
  fi
}

can_stage_absent_app_path() {
  local app_path="$1"
  local app_parent=""
  local parent_parent=""

  app_parent="$(dirname "$app_path")"
  if [[ -d "$app_parent" ]]; then
    [[ ! -L "$app_parent" && -w "$app_parent" ]]
    return
  fi

  parent_parent="$(dirname "$app_parent")"
  [[ -d "$parent_parent" && ! -L "$parent_parent" && -w "$parent_parent" ]]
}

unregister_modern_login_items() {
  local app_path=""
  local attempted_count=0
  local failure_count=0
  local skipped_count=0

  if ! build_trusted_uninstall_helper; then
    cleanup_uninstall_helper
    return 1
  fi

  for app_path in "$@"; do
    if [[ ! -e "$app_path" && ! -L "$app_path" ]] &&
        ! can_stage_absent_app_path "$app_path"; then
      echo "uninstall: cannot verify an unwritable previous app path: $app_path" >&2
      skipped_count=$((skipped_count + 1))
      continue
    fi

    attempted_count=$((attempted_count + 1))
    if ! run_trusted_helper_at_app_path "$app_path"; then
      failure_count=$((failure_count + 1))
    fi
  done

  cleanup_uninstall_helper
  if (( attempted_count == 0 )); then
    echo "uninstall: no writable app location was available for login item removal" >&2
    return 1
  fi
  (( failure_count == 0 && skipped_count == 0 ))
}

running_app_pids() {
  /usr/bin/osascript -l JavaScript -e \
    "ObjC.import('AppKit'); $.NSRunningApplication.runningApplicationsWithBundleIdentifier('$BUNDLE_ID').js.map(function(app) { return String(app.processIdentifier); }).join(' ');" \
    2>/dev/null || true
}

stop_running_app() {
  local attempt=0

  [[ -n "$(running_app_pids)" ]] || return 0

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

  echo "uninstall: could not stop the running $BUNDLE_ID app" >&2
  return 1
}

remove_exact_app() {
  local app_path="$1"

  [[ -e "$app_path" || -L "$app_path" ]] || return 0
  if ! has_expected_bundle_id "$app_path"; then
    echo "uninstall: refusing to remove an app without bundle identifier $BUNDLE_ID: $app_path" >&2
    return 1
  fi

  /bin/rm -rf -- "$app_path"
}

is_owned_diagnostic_report_name() {
  local report_name="$1"
  local report_stem=""

  case "$report_name" in
    *.ips|*.crash|*.diag|*.hang|*.spin) ;;
    *) return 1 ;;
  esac

  report_stem="${report_name%.*}"
  [[ "$report_stem" == "MenuPulse" ||
     "$report_stem" == MenuPulse[-_.]* ||
     "$report_stem" == "$BUNDLE_ID" ||
     "$report_stem" == "$BUNDLE_ID"[-_.]* ]]
}

remove_owned_diagnostic_reports() {
  local diagnostic_root="$LIBRARY_DIR/Logs/DiagnosticReports"
  local report_directory=""
  local report_path=""
  local report_name=""

  for report_directory in "$diagnostic_root" "$diagnostic_root/Retired"; do
    [[ -d "$report_directory" && ! -L "$report_directory" ]] || continue
    while IFS= read -r -d '' report_path; do
      report_name="${report_path##*/}"
      if is_owned_diagnostic_report_name "$report_name"; then
        /bin/rm -f -- "$report_path"
      fi
    done < <(/usr/bin/find "$report_directory" -maxdepth 1 -type f -print0)
  done
}

main() {
  local mode="${1:-}"
  local app_paths=()
  local candidate_app_path=""
  local custom_app_path=""
  local app_path=""
  local known_app_path=""
  local duplicate_path=0
  local skipped_app=0
  local default_library_resolved=""

  if (( $# > 1 )) || [[ -n "$mode" && "$mode" != "--login-items-only" ]]; then
    echo "usage: Scripts/uninstall.sh [--login-items-only]" >&2
    return 1
  fi

  trap cleanup_uninstall_state EXIT

  if ! SYSTEM_APPLICATIONS_DIR="$(resolved_directory "$SYSTEM_APPLICATIONS_DIR")" ||
      ! USER_APPLICATIONS_DIR="$(resolved_directory "$USER_APPLICATIONS_DIR")" ||
      ! LIBRARY_DIR="$(resolved_directory "$LIBRARY_DIR")"; then
    echo "uninstall: application and library directories must be absolute, non-root paths" >&2
    return 1
  fi
  LEGACY_PLIST_PATH="$LIBRARY_DIR/LaunchAgents/$BUNDLE_ID.plist"
  default_library_resolved="$(resolved_directory "$DEFAULT_LIBRARY_DIR")"
  app_paths=("$SYSTEM_APPLICATIONS_DIR/$APP_NAME")
  candidate_app_path="$USER_APPLICATIONS_DIR/$APP_NAME"
  if [[ "$candidate_app_path" != "${app_paths[0]}" ]]; then
    app_paths+=("$candidate_app_path")
  fi

  if [[ -n "${MENU_PULSE_INSTALL_DIR:-}" ]]; then
    if ! MENU_PULSE_INSTALL_DIR="$(resolved_directory "$MENU_PULSE_INSTALL_DIR")"; then
      echo "uninstall: MENU_PULSE_INSTALL_DIR must be an absolute, non-root path" >&2
      return 1
    fi
    custom_app_path="$MENU_PULSE_INSTALL_DIR/$APP_NAME"
    duplicate_path=0
    for known_app_path in "${app_paths[@]}"; do
      [[ "$custom_app_path" == "$known_app_path" ]] && duplicate_path=1
    done
    if (( duplicate_path == 0 )); then
      app_paths+=("$custom_app_path")
    fi
  fi

  for app_path in "${app_paths[@]}"; do
    if [[ -e "$app_path" || -L "$app_path" ]] && ! has_expected_bundle_id "$app_path"; then
      echo "uninstall: refusing an app without bundle identifier $BUNDLE_ID: $app_path" >&2
      return 1
    fi
  done

  stop_running_app

  if ! unregister_modern_login_items "${app_paths[@]}"; then
    echo "uninstall: could not remove the modern login item; no files were deleted" >&2
    echo "uninstall: check System Settings > General > Login Items, then retry" >&2
    return 1
  fi
  cleanup_uninstall_helper

  if [[ "$mode" == "--login-items-only" ]]; then
    echo "Menu Pulse login items were removed; apps and local settings were preserved."
    return 0
  fi

  /bin/launchctl bootout "gui/$(/usr/bin/id -u)" "$LEGACY_PLIST_PATH" >/dev/null 2>&1 || true
  /bin/rm -f -- "$LEGACY_PLIST_PATH"

  for app_path in "${app_paths[@]}"; do
    if ! remove_exact_app "$app_path"; then
      skipped_app=1
    fi
  done

  if [[ "$LIBRARY_DIR" == "$default_library_resolved" ]]; then
    /usr/bin/defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
  fi
  /bin/rm -f -- "$LIBRARY_DIR/Preferences/$BUNDLE_ID.plist"
  /bin/rm -rf -- "$LIBRARY_DIR/Caches/$BUNDLE_ID"
  /bin/rm -rf -- "$LIBRARY_DIR/Saved Application State/$BUNDLE_ID.savedState"
  /bin/rm -rf -- "$LIBRARY_DIR/Logs/$BUNDLE_ID"
  /bin/rm -rf -- "$LIBRARY_DIR/Logs/Menu Pulse"
  /bin/rm -rf -- "$LIBRARY_DIR/Logs/MenuPulse"
  remove_owned_diagnostic_reports

  if (( skipped_app == 1 )); then
    echo "uninstall: private data was removed, but a non-matching app path was left untouched" >&2
    return 1
  fi

  echo "Menu Pulse and its local settings were permanently removed."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
