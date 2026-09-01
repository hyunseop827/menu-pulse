#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2016,SC2030,SC2031,SC2034,SC2329
set -euo pipefail

# These tests source the lifecycle scripts and exercise them in temporary
# directories. The complete install flow replaces its build, login-item, and open
# operations with test doubles so it never touches the developer's installed app.
# ShellCheck cannot see variables/functions consumed by the dynamically sourced
# scripts, and the single-quoted fixture lines intentionally defer expansion.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(/usr/bin/mktemp -d -t menu-pulse-lifecycle-tests)"
TEST_COUNT=0
TEST_HELPER_SOURCE="$TEST_ROOT/login-helper.c"
TEST_HELPER_BIN="$TEST_ROOT/login-helper"

/usr/bin/printf '%s\n' \
  '#include <stdio.h>' \
  '#include <stdlib.h>' \
  'int main(int argc, char **argv) {' \
  '    const char *log_path = getenv("MENU_PULSE_TEST_UNREGISTER_LOG");' \
  '    if (log_path) {' \
  '        FILE *log = fopen(log_path, "a");' \
  '        if (log) {' \
  '            for (int index = 1; index < argc; index += 1) fprintf(log, "%s\n", argv[index]);' \
  '            fclose(log);' \
  '        }' \
  '    }' \
  '    const char *exit_value = getenv("MENU_PULSE_TEST_UNREGISTER_EXIT");' \
  '    return exit_value ? atoi(exit_value) : 0;' \
  '}' > "$TEST_HELPER_SOURCE"
/usr/bin/xcrun clang -arch "$(uname -m)" -mmacosx-version-min=13.0 \
  "$TEST_HELPER_SOURCE" -o "$TEST_HELPER_BIN"

cleanup() {
  /bin/rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

fail_test() {
  echo "LifecycleScriptTests: $*" >&2
  exit 1
}

assert_exists() {
  local path="$1"
  [[ -e "$path" || -L "$path" ]] || fail_test "expected path to exist: $path"
}

assert_absent() {
  local path="$1"
  [[ ! -e "$path" && ! -L "$path" ]] || fail_test "expected path to be absent: $path"
}

assert_equal() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  [[ "$actual" == "$expected" ]] || fail_test "$message (expected '$expected', got '$actual')"
}

assert_contains() {
  local path="$1"
  local expected="$2"
  /usr/bin/grep -Fq -- "$expected" "$path" || fail_test "expected '$expected' in $path"
}

make_fake_app() {
  local app_path="$1"
  local bundle_id="$2"
  local version="$3"
  local plist_path="$app_path/Contents/Info.plist"
  local executable_path="$app_path/Contents/MacOS/MenuPulse"

  /bin/mkdir -p "$app_path/Contents/MacOS"
  /usr/bin/plutil -create xml1 "$plist_path"
  /usr/bin/plutil -insert CFBundleIdentifier -string "$bundle_id" "$plist_path"
  /usr/bin/plutil -insert CFBundleShortVersionString -string "$version" "$plist_path"
  /usr/bin/plutil -insert CFBundleVersion -string "$version" "$plist_path"
  /usr/bin/plutil -insert CFBundleExecutable -string MenuPulse "$plist_path"
  /usr/bin/printf '%s\n' \
    '#!/usr/bin/env bash' \
    'if [[ -n "${MENU_PULSE_TEST_UNREGISTER_LOG:-}" ]]; then' \
    '  printf "%s\n" "$*" >> "$MENU_PULSE_TEST_UNREGISTER_LOG"' \
    'fi' \
    'exit 0' > "$executable_path"
  /bin/chmod 755 "$executable_path"
}

make_verified_fake_app() {
  local app_path="$1"
  local bundle_id="$2"
  local version="$3"

  make_fake_app "$app_path" "$bundle_id" "$version"
  /bin/cp "$TEST_HELPER_BIN" "$app_path/Contents/MacOS/MenuPulse"
  /bin/chmod 755 "$app_path/Contents/MacOS/MenuPulse"
  /usr/bin/codesign --force --sign - "$app_path" >/dev/null
}

assert_validation_rejected_in_condition() {
  local app_path="$1"
  local expected_version="$2"
  local case_name="$3"
  local output_path="$4"

  if validate_app "$app_path" "$expected_version" 2> "$output_path"; then
    fail_test "$case_name was accepted when validate_app was called from an if condition"
  fi
}

run_test() {
  local name="$1"
  shift
  "$@"
  TEST_COUNT=$((TEST_COUNT + 1))
  echo "PASS: $name"
}

test_install_bundle_validation_and_refusal() (
  # shellcheck source=../Scripts/install.sh
  source "$ROOT_DIR/Scripts/install.sh"

  local case_dir="$TEST_ROOT/install-bundle"
  local valid_app="$case_dir/Valid Menu Pulse.app"
  local foreign_app="$case_dir/Foreign Menu Pulse.app"
  local refusal_log="$case_dir/refusal.log"

  /bin/mkdir -p "$case_dir"
  make_verified_fake_app "$valid_app" "$BUNDLE_ID" "1.2.0"
  validate_app "$valid_app" "1.2.0"
  has_expected_bundle_id "$valid_app" || fail_test "valid app bundle ID was rejected"

  make_fake_app "$foreign_app" "com.example.ForeignApp" "1.2.0"
  if remove_exact_app "$foreign_app" 2> "$refusal_log"; then
    fail_test "install helper removed a foreign app"
  fi
  assert_exists "$foreign_app"
  assert_contains "$refusal_log" "refusing to remove an app without bundle identifier $BUNDLE_ID"

  remove_exact_app "$valid_app"
  assert_absent "$valid_app"
)

test_install_validation_rejects_every_invalid_app_in_condition() (
  # shellcheck source=../Scripts/install.sh
  source "$ROOT_DIR/Scripts/install.sh"

  local case_dir="$TEST_ROOT/install-invalid-condition"
  local bundle_app="$case_dir/Invalid Bundle ID.app"
  local version_app="$case_dir/Invalid Version.app"
  local executable_app="$case_dir/Invalid Executable.app"
  local architecture_app="$case_dir/Invalid Architecture.app"
  local signature_app="$case_dir/Invalid Signature.app"
  local wrong_architecture="x86_64"
  local wrong_architecture_bin="$case_dir/wrong-architecture-helper"

  /bin/mkdir -p "$case_dir"

  make_verified_fake_app "$bundle_app" "com.example.ForeignApp" "1.2.1"
  assert_validation_rejected_in_condition \
    "$bundle_app" "1.2.1" "invalid bundle identifier" "$case_dir/bundle.log"
  assert_contains "$case_dir/bundle.log" "unexpected bundle identifier"

  make_verified_fake_app "$version_app" "$BUNDLE_ID" "9.9.9"
  assert_validation_rejected_in_condition \
    "$version_app" "1.2.1" "invalid version" "$case_dir/version.log"
  assert_contains "$case_dir/version.log" "expected version 1.2.1"

  make_fake_app "$executable_app" "$BUNDLE_ID" "1.2.1"
  /usr/bin/plutil -replace CFBundleExecutable -string WrongExecutable \
    "$executable_app/Contents/Info.plist"
  /bin/cp "$TEST_HELPER_BIN" "$executable_app/Contents/MacOS/MenuPulse"
  /bin/chmod 755 "$executable_app/Contents/MacOS/MenuPulse"
  /usr/bin/codesign --force --sign - "$executable_app" >/dev/null
  assert_validation_rejected_in_condition \
    "$executable_app" "1.2.1" "invalid executable" "$case_dir/executable.log"
  assert_contains "$case_dir/executable.log" "unexpected executable name"

  /usr/bin/xcrun clang -arch "$wrong_architecture" -mmacosx-version-min=13.0 \
    "$TEST_HELPER_SOURCE" -o "$wrong_architecture_bin"
  make_fake_app "$architecture_app" "$BUNDLE_ID" "1.2.1"
  /bin/cp "$wrong_architecture_bin" "$architecture_app/Contents/MacOS/MenuPulse"
  /bin/chmod 755 "$architecture_app/Contents/MacOS/MenuPulse"
  /usr/bin/codesign --force --sign - "$architecture_app" >/dev/null
  assert_validation_rejected_in_condition \
    "$architecture_app" "1.2.1" "invalid architecture" "$case_dir/architecture.log"
  assert_contains "$case_dir/architecture.log" "must contain only the arm64 architecture"

  make_verified_fake_app "$signature_app" "$BUNDLE_ID" "1.2.1"
  /usr/bin/codesign --remove-signature "$signature_app"
  assert_validation_rejected_in_condition \
    "$signature_app" "1.2.1" "invalid code signature" "$case_dir/signature.log"
  assert_contains "$case_dir/signature.log" "code signature verification failed"
)

test_install_rollback_restores_previous_app() (
  # shellcheck source=../Scripts/install.sh
  source "$ROOT_DIR/Scripts/install.sh"

  INSTALL_DIR_RESOLVED="$TEST_ROOT/install-rollback/Applications"
  INSTALL_APP_PATH="$INSTALL_DIR_RESOLVED/$APP_NAME"
  STAGING_DIR="$INSTALL_DIR_RESOLVED/.menu-pulse-install.fixture"
  BACKUP_APP_PATH="$STAGING_DIR/Previous $APP_NAME"
  BACKUP_CREATED=1
  NEW_AT_TARGET=1
  INSTALL_COMMITTED=0

  /bin/mkdir -p "$STAGING_DIR"
  make_verified_fake_app "$INSTALL_APP_PATH" "$BUNDLE_ID" "1.2.0"
  make_verified_fake_app "$BACKUP_APP_PATH" "$BUNDLE_ID" "1.1.1"

  local rollback_status=0
  (install_exit_cleanup 42) 2> "$TEST_ROOT/install-rollback.log" || rollback_status=$?

  assert_equal "42" "$rollback_status" "rollback helper did not preserve the failure status"
  assert_exists "$INSTALL_APP_PATH"
  assert_equal \
    "1.1.1" \
    "$(bundle_value "$INSTALL_APP_PATH" CFBundleShortVersionString)" \
    "rollback helper did not restore the previous app"
  assert_absent "$STAGING_DIR"
  assert_contains "$TEST_ROOT/install-rollback.log" "restored the previous app"
)

test_install_rollback_restores_after_corrupt_target() (
  # shellcheck source=../Scripts/install.sh
  source "$ROOT_DIR/Scripts/install.sh"

  INSTALL_DIR_RESOLVED="$TEST_ROOT/install-corrupt-rollback/Applications"
  INSTALL_APP_PATH="$INSTALL_DIR_RESOLVED/$APP_NAME"
  STAGING_DIR="$INSTALL_DIR_RESOLVED/.menu-pulse-install.fixture"
  BACKUP_APP_PATH="$STAGING_DIR/Previous $APP_NAME"
  BACKUP_CREATED=1
  NEW_AT_TARGET=1
  INSTALL_COMMITTED=0

  /bin/mkdir -p "$INSTALL_APP_PATH/Contents" "$STAGING_DIR"
  /usr/bin/printf '%s\n' "corrupt replacement" > "$INSTALL_APP_PATH/Contents/broken"
  make_verified_fake_app "$BACKUP_APP_PATH" "$BUNDLE_ID" "1.1.1"

  local rollback_status=0
  (install_exit_cleanup 43) 2> "$TEST_ROOT/install-corrupt-rollback.log" || rollback_status=$?

  assert_equal "43" "$rollback_status" "corrupt-target rollback did not preserve the failure status"
  assert_exists "$INSTALL_APP_PATH"
  assert_equal \
    "1.1.1" \
    "$(bundle_value "$INSTALL_APP_PATH" CFBundleShortVersionString)" \
    "corrupt-target rollback did not restore the previous app"
  validate_app "$INSTALL_APP_PATH" "1.1.1"
  assert_absent "$STAGING_DIR"
  assert_contains "$TEST_ROOT/install-corrupt-rollback.log" "restored the previous app"
)

test_install_rollback_preserves_backup_when_validation_fails() (
  # shellcheck source=../Scripts/install.sh
  source "$ROOT_DIR/Scripts/install.sh"

  INSTALL_DIR_RESOLVED="$TEST_ROOT/install-invalid-backup/Applications"
  INSTALL_APP_PATH="$INSTALL_DIR_RESOLVED/$APP_NAME"
  STAGING_DIR="$INSTALL_DIR_RESOLVED/.menu-pulse-install.fixture"
  BACKUP_APP_PATH="$STAGING_DIR/Previous $APP_NAME"
  BACKUP_CREATED=1
  NEW_AT_TARGET=1
  INSTALL_COMMITTED=0

  /bin/mkdir -p "$STAGING_DIR"
  make_verified_fake_app "$INSTALL_APP_PATH" "$BUNDLE_ID" "1.2.1"
  make_verified_fake_app "$BACKUP_APP_PATH" "com.example.CorruptBackup" "1.1.1"

  local rollback_status=0
  (install_exit_cleanup 44) 2> "$TEST_ROOT/install-invalid-backup.log" || rollback_status=$?

  assert_equal "44" "$rollback_status" "failed rollback did not preserve the install failure status"
  assert_exists "$STAGING_DIR"
  assert_exists "$BACKUP_APP_PATH"
  assert_equal \
    "1.1.1" \
    "$(bundle_value "$BACKUP_APP_PATH" CFBundleShortVersionString)" \
    "failed rollback did not preserve the previous app backup"
  assert_contains "$TEST_ROOT/install-invalid-backup.log" "automatic rollback failed"
  assert_contains "$TEST_ROOT/install-invalid-backup.log" "recovery files were preserved"
)

test_install_main_replaces_and_deduplicates() (
  local case_dir="$TEST_ROOT/install-main-success"
  local app_bundle_name="Menu Pulse.app"
  local system_applications="$case_dir/System Applications"
  local user_applications="$case_dir/Home/Applications"
  local test_home="$case_dir/Home"
  local built_app="$case_dir/Built Menu Pulse.app"
  local installed_app="$system_applications/$app_bundle_name"
  local installed_app_resolved=""
  local duplicate_app="$user_applications/$app_bundle_name"
  local call_log="$case_dir/calls.log"
  local legacy_plist="$test_home/Library/LaunchAgents/dev.hyunseop.MenuPulse.plist"

  HOME="$test_home"
  MENU_PULSE_INSTALL_DIR="$system_applications"
  MENU_PULSE_SYSTEM_APPLICATIONS_DIR="$system_applications"
  MENU_PULSE_USER_APPLICATIONS_DIR="$user_applications"
  export HOME MENU_PULSE_INSTALL_DIR MENU_PULSE_SYSTEM_APPLICATIONS_DIR MENU_PULSE_USER_APPLICATIONS_DIR
  /bin/mkdir -p "$system_applications" "$user_applications" "$(dirname "$legacy_plist")"
  installed_app_resolved="$(cd "$system_applications" && pwd -P)/$app_bundle_name"

  # shellcheck source=../Scripts/install.sh
  source "$ROOT_DIR/Scripts/install.sh"
  BUILD_APP_PATH="$built_app"
  make_verified_fake_app "$built_app" "$BUNDLE_ID" "1.2.0"
  make_verified_fake_app "$installed_app" "$BUNDLE_ID" "1.1.1"
  make_verified_fake_app "$duplicate_app" "$BUNDLE_ID" "1.1.1"
  /usr/bin/touch "$legacy_plist"

  build_release_app() {
    /usr/bin/printf '%s\n' "build" >> "$call_log"
  }
  stop_running_app() {
    /usr/bin/printf '%s\n' "stop" >> "$call_log"
  }
  unregister_existing_login_items() {
    [[ -d "$installed_app" && -d "$duplicate_app" ]] ||
      fail_test "install removed a duplicate before unregistering its login item"
    [[ "$(bundle_value "$installed_app" CFBundleShortVersionString)" == "1.2.0" ]] ||
      fail_test "install changed login-item state before validating the replacement"
    /usr/bin/printf '%s\n' "unregister-existing" >> "$call_log"
    return 9
  }
  register_installed_login_item() {
    /usr/bin/printf 'register %s\n' "$1" >> "$call_log"
  }
  open_installed_app() {
    /usr/bin/printf 'open %s\n' "$1" >> "$call_log"
  }

  main > "$case_dir/output.log" 2>&1

  assert_exists "$installed_app"
  assert_equal \
    "1.2.0" \
    "$(bundle_value "$installed_app" CFBundleShortVersionString)" \
    "install main did not replace v1.1.1 with v1.2.0"
  validate_app "$installed_app" "1.2.0"
  assert_absent "$duplicate_app"
  assert_absent "$legacy_plist"
  assert_contains "$call_log" "build"
  assert_contains "$call_log" "stop"
  assert_contains "$call_log" "unregister-existing"
  assert_contains "$call_log" "register $installed_app_resolved/Contents/MacOS/$EXECUTABLE_NAME"
  assert_contains "$call_log" "open $installed_app_resolved"
  assert_contains "$case_dir/output.log" "could not fully remove previous login-item registrations"
  assert_contains "$case_dir/output.log" "installed to $installed_app_resolved"
  if /usr/bin/find "$system_applications" -maxdepth 1 -name '.menu-pulse-install.*' -print -quit | /usr/bin/grep -q .; then
    fail_test "successful install left its staging directory"
  fi
)

test_uninstall_bundle_refusal() (
  MENU_PULSE_SYSTEM_APPLICATIONS_DIR="$TEST_ROOT/uninstall-refusal/System Applications"
  MENU_PULSE_USER_APPLICATIONS_DIR="$TEST_ROOT/uninstall-refusal/User Applications"
  MENU_PULSE_LIBRARY_DIR="$TEST_ROOT/uninstall-refusal/Library"
  export MENU_PULSE_SYSTEM_APPLICATIONS_DIR MENU_PULSE_USER_APPLICATIONS_DIR MENU_PULSE_LIBRARY_DIR
  # shellcheck source=../Scripts/uninstall.sh
  source "$ROOT_DIR/Scripts/uninstall.sh"

  local foreign_app="$MENU_PULSE_SYSTEM_APPLICATIONS_DIR/$APP_NAME"
  local refusal_log="$TEST_ROOT/uninstall-refusal.log"
  make_fake_app "$foreign_app" "com.example.ForeignApp" "1.2.0"

  if remove_exact_app "$foreign_app" 2> "$refusal_log"; then
    fail_test "uninstall helper removed a foreign app"
  fi
  assert_exists "$foreign_app"
  assert_contains "$refusal_log" "refusing to remove an app without bundle identifier $BUNDLE_ID"
)

test_uninstall_removes_all_scoped_data() (
  unset MENU_PULSE_INSTALL_DIR || true
  MENU_PULSE_SYSTEM_APPLICATIONS_DIR="$TEST_ROOT/uninstall-full/System Applications"
  MENU_PULSE_USER_APPLICATIONS_DIR="$TEST_ROOT/uninstall-full/User Applications"
  MENU_PULSE_LIBRARY_DIR="$TEST_ROOT/uninstall-full/Library"
  export MENU_PULSE_SYSTEM_APPLICATIONS_DIR MENU_PULSE_USER_APPLICATIONS_DIR MENU_PULSE_LIBRARY_DIR
  # shellcheck source=../Scripts/uninstall.sh
  source "$ROOT_DIR/Scripts/uninstall.sh"

  # A unique domain makes the absolute `defaults delete` call harmless to the
  # developer's real Menu Pulse preferences while preserving the complete flow.
  BUNDLE_ID="dev.hyunseop.MenuPulse.LifecycleTests.$$"
  LEGACY_PLIST_PATH="$LIBRARY_DIR/LaunchAgents/$BUNDLE_ID.plist"
  local system_app="$SYSTEM_APPLICATIONS_DIR/$APP_NAME"
  local user_app="$USER_APPLICATIONS_DIR/$APP_NAME"
  local unregister_log="$TEST_ROOT/uninstall-full/unregister.log"
  local preference_path="$LIBRARY_DIR/Preferences/$BUNDLE_ID.plist"
  local cache_path="$LIBRARY_DIR/Caches/$BUNDLE_ID"
  local saved_state_path="$LIBRARY_DIR/Saved Application State/$BUNDLE_ID.savedState"
  local bundle_log_path="$LIBRARY_DIR/Logs/$BUNDLE_ID"
  local spaced_log_path="$LIBRARY_DIR/Logs/Menu Pulse"
  local compact_log_path="$LIBRARY_DIR/Logs/MenuPulse"
  local diagnostic_path="$LIBRARY_DIR/Logs/DiagnosticReports"
  local retired_diagnostic_path="$diagnostic_path/Retired"
  local owned_ips="$diagnostic_path/MenuPulse-2026-09-01.ips"
  local owned_crash="$diagnostic_path/${BUNDLE_ID}_2026-09-01.crash"
  local owned_retired_diag="$retired_diagnostic_path/MenuPulse.old.diag"
  local owned_hang="$diagnostic_path/MenuPulse-2026-09-01.hang"
  local owned_retired_spin="$retired_diagnostic_path/${BUNDLE_ID}.spin"
  local unrelated_prefix="$diagnostic_path/MenuPulseHelper-2026-09-01.ips"
  local unrelated_extension="$diagnostic_path/MenuPulse-2026-09-01.txt"
  local nested_owned_name="$diagnostic_path/Nested/MenuPulse-2026-09-01.ips"

  make_verified_fake_app "$system_app" "$BUNDLE_ID" "1.2.0"
  make_verified_fake_app "$user_app" "$BUNDLE_ID" "1.2.0"
  /bin/mkdir -p \
    "$(dirname "$LEGACY_PLIST_PATH")" \
    "$(dirname "$preference_path")" \
    "$cache_path" \
    "$saved_state_path" \
    "$bundle_log_path" \
    "$spaced_log_path" \
    "$compact_log_path" \
    "$retired_diagnostic_path" \
    "$(dirname "$nested_owned_name")"
  /usr/bin/touch \
    "$LEGACY_PLIST_PATH" \
    "$preference_path" \
    "$cache_path/cache" \
    "$saved_state_path/state" \
    "$bundle_log_path/log" \
    "$spaced_log_path/log" \
    "$compact_log_path/log" \
    "$owned_ips" \
    "$owned_crash" \
    "$owned_retired_diag" \
    "$owned_hang" \
    "$owned_retired_spin" \
    "$unrelated_prefix" \
    "$unrelated_extension" \
    "$nested_owned_name"

  export MENU_PULSE_TEST_UNREGISTER_LOG="$unregister_log"
  stop_running_app() { return 0; }
  unregister_modern_login_items() {
    /usr/bin/printf '%s\n' "--unregister-login-item" >> "$MENU_PULSE_TEST_UNREGISTER_LOG"
    return 0
  }
  main > "$TEST_ROOT/uninstall-full/output.log"

  assert_absent "$system_app"
  assert_absent "$user_app"
  assert_absent "$LEGACY_PLIST_PATH"
  assert_absent "$preference_path"
  assert_absent "$cache_path"
  assert_absent "$saved_state_path"
  assert_absent "$bundle_log_path"
  assert_absent "$spaced_log_path"
  assert_absent "$compact_log_path"
  assert_absent "$owned_ips"
  assert_absent "$owned_crash"
  assert_absent "$owned_retired_diag"
  assert_absent "$owned_hang"
  assert_absent "$owned_retired_spin"
  assert_exists "$unrelated_prefix"
  assert_exists "$unrelated_extension"
  assert_exists "$nested_owned_name"
  assert_equal \
    "1" \
    "$(/usr/bin/grep -Fc -- "--unregister-login-item" "$unregister_log")" \
    "one verified installed copy should unregister the login item"
)

test_uninstall_login_only_preserves_apps_and_data() (
  unset MENU_PULSE_INSTALL_DIR || true
  MENU_PULSE_SYSTEM_APPLICATIONS_DIR="$TEST_ROOT/uninstall-login-only/System Applications"
  MENU_PULSE_USER_APPLICATIONS_DIR="$TEST_ROOT/uninstall-login-only/User Applications"
  MENU_PULSE_LIBRARY_DIR="$TEST_ROOT/uninstall-login-only/Library"
  export MENU_PULSE_SYSTEM_APPLICATIONS_DIR MENU_PULSE_USER_APPLICATIONS_DIR MENU_PULSE_LIBRARY_DIR
  # shellcheck source=../Scripts/uninstall.sh
  source "$ROOT_DIR/Scripts/uninstall.sh"

  local app_path="$MENU_PULSE_SYSTEM_APPLICATIONS_DIR/$APP_NAME"
  local preference_path="$MENU_PULSE_LIBRARY_DIR/Preferences/$BUNDLE_ID.plist"
  local legacy_path="$MENU_PULSE_LIBRARY_DIR/LaunchAgents/$BUNDLE_ID.plist"
  local call_log="$TEST_ROOT/uninstall-login-only/calls.log"

  make_verified_fake_app "$app_path" "$BUNDLE_ID" "1.1.1"
  /bin/mkdir -p "$(dirname "$preference_path")" "$(dirname "$legacy_path")" \
    "$MENU_PULSE_USER_APPLICATIONS_DIR"
  /usr/bin/touch "$preference_path" "$legacy_path"

  stop_running_app() {
    /usr/bin/printf '%s\n' "stop" >> "$call_log"
  }
  unregister_modern_login_items() {
    /usr/bin/printf '%s\n' "unregister" >> "$call_log"
  }

  main --login-items-only > "$TEST_ROOT/uninstall-login-only/output.log"

  assert_exists "$app_path"
  assert_exists "$preference_path"
  assert_exists "$legacy_path"
  assert_contains "$call_log" "stop"
  assert_contains "$call_log" "unregister"
  assert_contains "$TEST_ROOT/uninstall-login-only/output.log" "apps and local settings were preserved"
)

test_uninstall_preserves_files_when_unregister_fails() (
  unset MENU_PULSE_INSTALL_DIR || true
  MENU_PULSE_SYSTEM_APPLICATIONS_DIR="$TEST_ROOT/uninstall-failure/System Applications"
  MENU_PULSE_USER_APPLICATIONS_DIR="$TEST_ROOT/uninstall-failure/User Applications"
  MENU_PULSE_LIBRARY_DIR="$TEST_ROOT/uninstall-failure/Library"
  export MENU_PULSE_SYSTEM_APPLICATIONS_DIR MENU_PULSE_USER_APPLICATIONS_DIR MENU_PULSE_LIBRARY_DIR
  # shellcheck source=../Scripts/uninstall.sh
  source "$ROOT_DIR/Scripts/uninstall.sh"

  local app_path="$MENU_PULSE_SYSTEM_APPLICATIONS_DIR/$APP_NAME"
  local preference_path="$MENU_PULSE_LIBRARY_DIR/Preferences/$BUNDLE_ID.plist"
  make_verified_fake_app "$app_path" "$BUNDLE_ID" "1.2.0"
  /bin/mkdir -p "$(dirname "$preference_path")" "$MENU_PULSE_USER_APPLICATIONS_DIR"
  /usr/bin/touch "$preference_path"

  export MENU_PULSE_TEST_UNREGISTER_EXIT=9
  stop_running_app() { return 0; }
  unregister_modern_login_items() { return "$MENU_PULSE_TEST_UNREGISTER_EXIT"; }
  local uninstall_status=0
  main > "$TEST_ROOT/uninstall-failure.log" 2>&1 || uninstall_status=$?
  unset MENU_PULSE_TEST_UNREGISTER_EXIT

  assert_equal "1" "$uninstall_status" "unregister failure should fail the uninstall"
  assert_exists "$app_path"
  assert_exists "$preference_path"
  assert_contains "$TEST_ROOT/uninstall-failure.log" "no files were deleted"
)

test_uninstall_rejects_root_alias() (
  # shellcheck source=../Scripts/uninstall.sh
  source "$ROOT_DIR/Scripts/uninstall.sh"

  if resolved_directory "/tmp/.." >/dev/null; then
    fail_test "root path alias was accepted"
  fi
  if resolved_directory "/private/tmp/../.." >/dev/null; then
    fail_test "private root path alias was accepted"
  fi
)

test_uninstall_uses_trusted_same_path_helper() (
  # shellcheck source=../Scripts/uninstall.sh
  source "$ROOT_DIR/Scripts/uninstall.sh"

  local case_dir="$TEST_ROOT/uninstall-trusted-same-path"
  local app_parent="$case_dir/Applications"
  local installed_app="$app_parent/$APP_NAME"
  local trusted_root="$case_dir/trusted"
  local trusted_app="$trusted_root/$APP_NAME"
  local unregister_log="$case_dir/unregister.log"

  /bin/mkdir -p "$app_parent" "$trusted_root"
  make_fake_app "$installed_app" "$BUNDLE_ID" "1.1.1"
  /usr/bin/printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "UNTRUSTED_INSTALLED_HELPER_EXECUTED" >> "$MENU_PULSE_TEST_UNREGISTER_LOG"' \
    'exit 77' > "$installed_app/Contents/MacOS/$EXECUTABLE_NAME"
  /bin/chmod 755 "$installed_app/Contents/MacOS/$EXECUTABLE_NAME"
  make_verified_fake_app "$trusted_app" "$BUNDLE_ID" "1.2.0"

  UNINSTALL_HELPER_APP="$trusted_app"
  export MENU_PULSE_TEST_UNREGISTER_LOG="$unregister_log"
  run_trusted_helper_at_app_path "$installed_app"

  assert_exists "$installed_app"
  assert_equal \
    "1.1.1" \
    "$(bundle_value "$installed_app" CFBundleShortVersionString)" \
    "same-path helper did not restore the original app"
  assert_contains "$unregister_log" "--unregister-login-item"
  if /usr/bin/grep -Fq -- "UNTRUSTED_INSTALLED_HELPER_EXECUTED" "$unregister_log"; then
    fail_test "uninstall executed the installed app instead of the trusted helper"
  fi
  if /usr/bin/find "$app_parent" -maxdepth 1 -name '.menu-pulse-uninstall.*' -print -quit | /usr/bin/grep -q .; then
    fail_test "same-path helper left a staging directory"
  fi
)

test_uninstall_restores_app_when_trusted_helper_fails() (
  # shellcheck source=../Scripts/uninstall.sh
  source "$ROOT_DIR/Scripts/uninstall.sh"

  local case_dir="$TEST_ROOT/uninstall-trusted-failure"
  local app_parent="$case_dir/Applications"
  local installed_app="$app_parent/$APP_NAME"
  local trusted_app="$case_dir/trusted/$APP_NAME"

  /bin/mkdir -p "$app_parent" "$(dirname "$trusted_app")"
  make_fake_app "$installed_app" "$BUNDLE_ID" "1.1.1"
  make_verified_fake_app "$trusted_app" "$BUNDLE_ID" "1.2.0"
  UNINSTALL_HELPER_APP="$trusted_app"
  export MENU_PULSE_TEST_UNREGISTER_EXIT=9

  if run_trusted_helper_at_app_path "$installed_app" > "$case_dir/output.log" 2>&1; then
    fail_test "a failing trusted helper was accepted"
  fi
  unset MENU_PULSE_TEST_UNREGISTER_EXIT

  assert_exists "$installed_app"
  assert_equal \
    "1.1.1" \
    "$(bundle_value "$installed_app" CFBundleShortVersionString)" \
    "failed same-path helper did not restore the original app"
  if /usr/bin/find "$app_parent" -maxdepth 1 -name '.menu-pulse-uninstall.*' -print -quit | /usr/bin/grep -q .; then
    fail_test "failed same-path helper left a staging directory"
  fi
)

test_uninstall_attempts_login_removal_without_installed_app() (
  # shellcheck source=../Scripts/uninstall.sh
  source "$ROOT_DIR/Scripts/uninstall.sh"

  local case_dir="$TEST_ROOT/uninstall-absent-app"
  local absent_parent="$case_dir/Applications"
  local absent_app="$absent_parent/$APP_NAME"
  local trusted_app="$case_dir/trusted/$APP_NAME"
  local unregister_log="$case_dir/unregister.log"

  /bin/mkdir -p "$(dirname "$trusted_app")"
  make_verified_fake_app "$trusted_app" "$BUNDLE_ID" "1.2.0"
  UNINSTALL_HELPER_APP="$trusted_app"
  export MENU_PULSE_TEST_UNREGISTER_LOG="$unregister_log"

  run_trusted_helper_at_app_path "$absent_app"

  assert_contains "$unregister_log" "--unregister-login-item"
  assert_absent "$absent_app"
  assert_absent "$absent_parent"
)

test_uninstall_reports_unwritable_stale_path() (
  # shellcheck source=../Scripts/uninstall.sh
  source "$ROOT_DIR/Scripts/uninstall.sh"

  local case_dir="$TEST_ROOT/uninstall-existing-user-app"
  local unavailable_root="$case_dir/Unavailable"
  local unavailable_system_app="$unavailable_root/System Applications/$APP_NAME"
  local user_app="$case_dir/User Applications/$APP_NAME"
  local stale_app="$case_dir/Stale Applications/$APP_NAME"
  local trusted_app="$case_dir/trusted/$APP_NAME"
  local unregister_log="$case_dir/unregister.log"

  /bin/mkdir -p "$(dirname "$user_app")" "$(dirname "$trusted_app")" "$unavailable_root"
  /bin/chmod 555 "$unavailable_root"
  make_fake_app "$user_app" "$BUNDLE_ID" "1.1.1"
  make_verified_fake_app "$trusted_app" "$BUNDLE_ID" "1.2.0"
  build_trusted_uninstall_helper() {
    UNINSTALL_HELPER_APP="$trusted_app"
    return 0
  }
  export MENU_PULSE_TEST_UNREGISTER_LOG="$unregister_log"

  local unregister_status=0
  unregister_modern_login_items "$unavailable_system_app" "$user_app" "$stale_app" \
    > "$case_dir/output.log" 2>&1 || unregister_status=$?
  /bin/chmod 755 "$unavailable_root"

  assert_equal "1" "$unregister_status" \
    "an unverifiable stale path should prevent a complete-removal success"
  assert_exists "$user_app"
  assert_absent "$(dirname "$unavailable_system_app")"
  assert_absent "$(dirname "$stale_app")"
  assert_equal \
    "2" \
    "$(/usr/bin/grep -Fc -- "--unregister-login-item" "$unregister_log")" \
    "all writable paths should still be checked before reporting the permission failure"
  assert_contains "$case_dir/output.log" "cannot verify an unwritable previous app path"
)

test_uninstall_cleanup_covers_signal_windows() (
  # shellcheck source=../Scripts/uninstall.sh
  source "$ROOT_DIR/Scripts/uninstall.sh"

  local case_dir="$TEST_ROOT/uninstall-signal-windows"
  local app_parent="$case_dir/Applications"
  local app_path="$app_parent/$APP_NAME"
  local first_stage_dir=""

  /bin/mkdir -p "$app_parent"
  make_fake_app "$app_path" "$BUNDLE_ID" "1.1.1"
  ACTIVE_APP_PATH="$app_path"
  ACTIVE_APP_PARENT="$app_parent"
  ACTIVE_STAGE_DIR="$(/usr/bin/mktemp -d "$app_parent/.menu-pulse-uninstall.XXXXXX")"
  first_stage_dir="$ACTIVE_STAGE_DIR"
  ACTIVE_BACKUP_APP_PATH="$ACTIVE_STAGE_DIR/Original $APP_NAME"
  ACTIVE_ORIGINAL_MOVED=1
  cleanup_active_app_stage
  assert_exists "$app_path"
  assert_absent "$first_stage_dir"

  ACTIVE_APP_PATH="$app_path"
  ACTIVE_APP_PARENT="$app_parent"
  ACTIVE_STAGE_DIR="$(/usr/bin/mktemp -d "$app_parent/.menu-pulse-uninstall.XXXXXX")"
  ACTIVE_BACKUP_APP_PATH="$ACTIVE_STAGE_DIR/Original $APP_NAME"
  /bin/mv "$app_path" "$ACTIVE_BACKUP_APP_PATH"
  /bin/mkdir -p "$app_path/Contents"
  /usr/bin/touch "$app_path/Contents/partial-copy"
  ACTIVE_ORIGINAL_MOVED=1
  ACTIVE_HELPER_AT_TARGET=1
  cleanup_active_app_stage

  assert_exists "$app_path"
  assert_equal \
    "1.1.1" \
    "$(bundle_value "$app_path" CFBundleShortVersionString)" \
    "cleanup did not restore the original after an interrupted helper copy"
  if /usr/bin/find "$app_parent" -maxdepth 1 -name '.menu-pulse-uninstall.*' -print -quit | /usr/bin/grep -q .; then
    fail_test "signal-window cleanup left a staging directory"
  fi
)

test_uninstall_builds_and_cleans_trusted_helper() (
  # shellcheck source=../Scripts/uninstall.sh
  source "$ROOT_DIR/Scripts/uninstall.sh"

  local built_helper_dir=""

  build_trusted_uninstall_helper
  built_helper_dir="$UNINSTALL_HELPER_DIR"
  assert_exists "$UNINSTALL_HELPER_APP"
  is_valid_built_helper "$UNINSTALL_HELPER_APP" || \
    fail_test "freshly built uninstall helper failed validation"
  cleanup_uninstall_helper
  assert_absent "$built_helper_dir"
)

test_measure_isolates_persistent_preferences() (
  local case_dir="$TEST_ROOT/measure-isolation"
  local test_home="$case_dir/Home"
  local test_temp="$case_dir/Temp"
  local preference_path="$test_home/Library/Preferences/dev.hyunseop.MenuPulse.plist"
  local preference_snapshot="$case_dir/preferences.before.plist"
  local output_path="$case_dir/measure.log"
  local actual_legacy_path="$HOME/Library/LaunchAgents/dev.hyunseop.MenuPulse.plist"
  local actual_legacy_state="absent"
  local actual_legacy_hash=""

  /bin/mkdir -p "$(dirname "$preference_path")" "$test_temp"
  /usr/bin/plutil -create xml1 "$preference_path"
  /usr/bin/plutil -insert cpuRefreshInterval -float 9 "$preference_path"
  /usr/bin/plutil -insert ramRefreshInterval -float 9 "$preference_path"
  /usr/bin/plutil -insert temperatureRefreshInterval -float 9 "$preference_path"
  /usr/bin/plutil -insert diskRefreshInterval -float 9 "$preference_path"
  /bin/cp "$preference_path" "$preference_snapshot"
  if [[ -f "$actual_legacy_path" && ! -L "$actual_legacy_path" ]]; then
    actual_legacy_state="regular"
    actual_legacy_hash="$(/usr/bin/shasum -a 256 "$actual_legacy_path" | /usr/bin/awk '{ print $1 }')"
  elif [[ -e "$actual_legacy_path" || -L "$actual_legacy_path" ]]; then
    actual_legacy_state="other"
  fi

  HOME="$test_home" \
    TMPDIR="$test_temp/" \
    WARMUP=0 \
    DURATION=1 \
    INTERVAL=1 \
    REFRESH_INTERVAL=3 \
    ALL_METRICS=0 \
    "$ROOT_DIR/Scripts/measure.sh" > "$output_path"

  /usr/bin/cmp -s "$preference_snapshot" "$preference_path" || \
    fail_test "measurement changed persistent legacy preference keys"
  case "$actual_legacy_state" in
    absent)
      assert_absent "$actual_legacy_path"
      ;;
    regular)
      assert_equal \
        "$actual_legacy_hash" \
        "$(/usr/bin/shasum -a 256 "$actual_legacy_path" | /usr/bin/awk '{ print $1 }')" \
        "measurement changed the real legacy login item"
      ;;
    other)
      assert_exists "$actual_legacy_path"
      ;;
  esac
  assert_contains "$output_path" "CPU average:"
  if /usr/bin/find "$test_temp" -maxdepth 1 -name 'menu-pulse-benchmark-home.*' -print -quit | /usr/bin/grep -q .; then
    fail_test "measurement left its isolated preference home behind"
  fi
)

test_release_version_helpers() (
  # shellcheck source=../Scripts/release.sh
  source "$ROOT_DIR/Scripts/release.sh"

  local version=""
  for version in 0.0.0 1.2.0 10.20.30; do
    is_canonical_version "$version" || fail_test "canonical version was rejected: $version"
  done
  for version in v1.2.0 01.2.3 1.02.3 1.2.03 1.2 1.2.3.4 -1.2.3; do
    if is_canonical_version "$version"; then
      fail_test "non-canonical version was accepted: $version"
    fi
  done

  assert_equal "-1" "$(compare_versions 1.2.9 1.3.0)" "minor version comparison failed"
  assert_equal "1" "$(compare_versions 2.0.0 1.99.99)" "major version comparison failed"
  assert_equal "1" "$(compare_versions 1.10.0 1.9.99)" "numeric comparison failed"
  assert_equal "0" "$(compare_versions 1.2.0 1.2.0)" "equal version comparison failed"
)

test_release_commit_validation() (
  # shellcheck source=../Scripts/release.sh
  source "$ROOT_DIR/Scripts/release.sh"

  local repo_path="$TEST_ROOT/release-commit-repo"
  local validation_log="$TEST_ROOT/release-commit-validation.log"
  local parent_commit=""

  /usr/bin/git init -q -b main "$repo_path"
  /usr/bin/git -C "$repo_path" config user.email "menu-pulse-tests@example.invalid"
  /usr/bin/git -C "$repo_path" config user.name "Menu Pulse Tests"
  /bin/mkdir -p "$repo_path/Packaging"
  /usr/bin/plutil -create xml1 "$repo_path/Packaging/Info.plist"
  /usr/bin/plutil -insert CFBundleIdentifier -string "$BUNDLE_ID" "$repo_path/Packaging/Info.plist"
  /usr/bin/plutil -insert CFBundleShortVersionString -string 1.1.1 "$repo_path/Packaging/Info.plist"
  /usr/bin/plutil -insert CFBundleVersion -string 1.1.1 "$repo_path/Packaging/Info.plist"
  /usr/bin/git -C "$repo_path" add Packaging/Info.plist
  /usr/bin/git -C "$repo_path" commit -q -m initial
  parent_commit="$(/usr/bin/git -C "$repo_path" rev-parse HEAD)"

  cd "$repo_path"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 1.2.0" Packaging/Info.plist
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion 1.2.0" Packaging/Info.plist
  /usr/bin/git add Packaging/Info.plist
  /usr/bin/git commit -q -m "Release v1.2.0"
  validate_release_commit HEAD "$parent_commit" v1.2.0 || \
    fail_test "an exact release commit was rejected"

  /usr/bin/git switch -q --detach "$parent_commit"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 1.2.0" Packaging/Info.plist
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion 1.2.0" Packaging/Info.plist
  /usr/bin/touch unexpected-source-change
  /usr/bin/git add Packaging/Info.plist unexpected-source-change
  /usr/bin/git commit -q -m "Release v1.2.0"
  if validate_release_commit HEAD "$parent_commit" v1.2.0 > "$validation_log" 2>&1; then
    fail_test "release commit with an extra file was accepted"
  fi
  assert_contains "$validation_log" "must change only Packaging/Info.plist"

  /usr/bin/git switch -q --detach "$parent_commit"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 1.2.0" Packaging/Info.plist
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion 1.2.0" Packaging/Info.plist
  /usr/libexec/PlistBuddy -c "Add :UnexpectedReleaseValue string injected" Packaging/Info.plist
  /usr/bin/git add Packaging/Info.plist
  /usr/bin/git commit -q -m "Release v1.2.0"
  if validate_release_commit HEAD "$parent_commit" v1.2.0 > "$validation_log" 2>&1; then
    fail_test "release commit with an extra plist change was accepted"
  fi
  assert_contains "$validation_log" "changes beyond the two version values"
)

test_release_workflow_sha_and_failure_validation() (
  # shellcheck source=../Scripts/release.sh
  source "$ROOT_DIR/Scripts/release.sh"

  local repo_path="$TEST_ROOT/release-workflow-repo"
  local mock_root="$TEST_ROOT/release-workflow-root"
  local verify_log="$TEST_ROOT/release-workflow-verify.log"
  local output_log="$TEST_ROOT/release-workflow-output.log"
  local expected_sha=""
  local MOCK_WORKFLOW_HEAD=""
  local MOCK_WORKFLOW_CONCLUSION="success"
  local MOCK_WORKFLOW_WATCH_EXIT=0

  /usr/bin/git init -q -b main "$repo_path"
  /usr/bin/git -C "$repo_path" config user.email "menu-pulse-tests@example.invalid"
  /usr/bin/git -C "$repo_path" config user.name "Menu Pulse Tests"
  /usr/bin/touch "$repo_path/tracked"
  /usr/bin/git -C "$repo_path" add tracked
  /usr/bin/git -C "$repo_path" commit -q -m initial
  /usr/bin/git -C "$repo_path" tag -a v1.2.0 -m "Release v1.2.0"
  expected_sha="$(/usr/bin/git -C "$repo_path" rev-parse 'v1.2.0^{commit}')"

  /bin/mkdir -p "$mock_root/Scripts"
  /usr/bin/printf '%s\n' \
    '#!/usr/bin/env bash' \
    '/usr/bin/printf "%s\\n" "$1" >> "$MENU_PULSE_TEST_VERIFY_LOG"' \
    > "$mock_root/Scripts/verify-release.sh"
  /bin/chmod 755 "$mock_root/Scripts/verify-release.sh"
  export MENU_PULSE_TEST_VERIFY_LOG="$verify_log"
  ROOT_DIR="$mock_root"

  gh() {
    case "$1:$2" in
      run:list)
        /usr/bin/printf '%s\n' 9001
        ;;
      run:view)
        if [[ " $* " == *" --json conclusion "* ]]; then
          /usr/bin/printf '%s\n' "$MOCK_WORKFLOW_CONCLUSION"
        else
          /usr/bin/printf '%s\n' "$MOCK_WORKFLOW_HEAD"
        fi
        ;;
      run:watch)
        return "$MOCK_WORKFLOW_WATCH_EXIT"
        ;;
      *)
        return 2
        ;;
    esac
  }

  cd "$repo_path"
  MOCK_WORKFLOW_HEAD="$expected_sha"
  wait_for_release_and_verify v1.2.0 > "$output_log" 2>&1 || \
    fail_test "matching successful workflow was rejected"
  assert_equal "1" "$(/usr/bin/grep -Fc -- v1.2.0 "$verify_log")" \
    "verified workflow should verify published assets once"

  MOCK_WORKFLOW_HEAD="0000000000000000000000000000000000000000"
  if wait_for_release_and_verify v1.2.0 > "$output_log" 2>&1; then
    fail_test "workflow with a different head SHA was accepted"
  fi
  assert_contains "$output_log" "does not match v1.2.0"

  MOCK_WORKFLOW_HEAD="$expected_sha"
  MOCK_WORKFLOW_WATCH_EXIT=9
  if wait_for_release_and_verify v1.2.0 > "$output_log" 2>&1; then
    fail_test "failed workflow was accepted"
  fi
  assert_contains "$output_log" "workflow failed"
  assert_equal "1" "$(/usr/bin/grep -Fc -- v1.2.0 "$verify_log")" \
    "failed workflow must not verify or accept published assets"
)

test_release_rejects_feature_branch() (
  local repo_path="$TEST_ROOT/feature-repo"
  local output_path="$TEST_ROOT/feature-release.log"

  /usr/bin/git init -q "$repo_path"
  (
    cd "$repo_path"
    /usr/bin/git config user.email "menu-pulse-tests@example.invalid"
    /usr/bin/git config user.name "Menu Pulse Tests"
    /usr/bin/touch tracked
    /usr/bin/git add tracked
    /usr/bin/git commit -q -m initial
    /usr/bin/git checkout -q -b feature/lifecycle-test
  )

  if /bin/bash -c '
    set -euo pipefail
    source "$1"
    ROOT_DIR="$2"
    INFO_PLIST="$2/Packaging/Info.plist"
    APP_PATH="$2/build/release/Menu Pulse.app"
    DMG_PATH="$2/dist/MenuPulse.dmg"
    main 1.2.0
  ' lifecycle-release "$ROOT_DIR/Scripts/release.sh" "$repo_path" > "$output_path" 2>&1; then
    fail_test "release unexpectedly continued from a feature branch"
  fi

  assert_contains "$output_path" "releases are allowed only from main"
  [[ -z "$(/usr/bin/git -C "$repo_path" tag --list)" ]] || fail_test "feature-branch test created a tag"
)

run_test "install bundle validation and foreign-app refusal" test_install_bundle_validation_and_refusal
run_test "install rejects every invalid app from conditional validation" test_install_validation_rejects_every_invalid_app_in_condition
run_test "install rollback restores previous app" test_install_rollback_restores_previous_app
run_test "install rollback survives a corrupt replacement" test_install_rollback_restores_after_corrupt_target
run_test "install rollback preserves a backup after validation failure" test_install_rollback_preserves_backup_when_validation_fails
run_test "install main safely replaces despite stale-login cleanup failure" test_install_main_replaces_and_deduplicates
run_test "uninstall foreign-app refusal" test_uninstall_bundle_refusal
run_test "uninstall removes all scoped data" test_uninstall_removes_all_scoped_data
run_test "uninstall login-only mode preserves apps and data" test_uninstall_login_only_preserves_apps_and_data
run_test "uninstall preserves files when login removal fails" test_uninstall_preserves_files_when_unregister_fails
run_test "uninstall rejects root path aliases" test_uninstall_rejects_root_alias
run_test "uninstall uses only a trusted same-path helper" test_uninstall_uses_trusted_same_path_helper
run_test "uninstall restores an app after helper failure" test_uninstall_restores_app_when_trusted_helper_fails
run_test "uninstall attempts login removal without an app" test_uninstall_attempts_login_removal_without_installed_app
run_test "uninstall reports an unwritable stale path" test_uninstall_reports_unwritable_stale_path
run_test "uninstall cleanup covers signal windows" test_uninstall_cleanup_covers_signal_windows
run_test "uninstall builds and cleans its trusted helper" test_uninstall_builds_and_cleans_trusted_helper
run_test "measurement isolates persistent preferences" test_measure_isolates_persistent_preferences
run_test "release version helpers" test_release_version_helpers
run_test "release commit validation" test_release_commit_validation
run_test "release workflow SHA and failure validation" test_release_workflow_sha_and_failure_validation
run_test "release rejects feature branch" test_release_rejects_feature_branch

echo "LifecycleScriptTests passed ($TEST_COUNT cases)."
