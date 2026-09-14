#!/usr/bin/env bats

load helpers/harness

setup() { harness_setup; }
teardown() { harness_teardown; }

@test "launch: no argument prints usage and exits non-zero" {
  run omarchy-launch-appimage
  [ "$status" -ne 0 ]
  [[ $output == *"Usage: omarchy-launch-appimage"* ]]
}

@test "launch: missing payload notifies instead of failing silently" {
  run omarchy-launch-appimage "$APPS_DIR/Gone.AppImage"
  [ "$status" -ne 0 ]
  stub_called omarchy-notification-send
  [[ $(stub_log_for omarchy-notification-send) == *"Gone.AppImage"* ]]
}

@test "launch: a non-executable payload is treated as missing" {
  touch "$APPS_DIR/NotExec.AppImage"
  run omarchy-launch-appimage "$APPS_DIR/NotExec.AppImage"
  [ "$status" -ne 0 ]
  stub_called omarchy-notification-send
}

@test "launch: forwards extra arguments to the AppImage" {
  make_appimage "$APPS_DIR/Foo.AppImage"
  run omarchy-launch-appimage "$APPS_DIR/Foo.AppImage" --flag "two words"
  [ "$status" -eq 0 ]
  [[ $(cat "$LAUNCH_LOG") == *"--flag two words"* ]]
}
