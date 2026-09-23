#!/usr/bin/env bats

load helpers/harness

setup() { harness_setup; }
teardown() { harness_teardown; }

install_fixture() {
  local file="${1:-Foo.AppImage}" name="${2:-Foo}"
  make_appimage "$HOME/Downloads/$file" --name "$name"
  omarchy-appimage-install "$HOME/Downloads/$file" >/dev/null
}

@test "remove: deletes launcher, icon and payload together" {
  install_fixture Foo.AppImage "Foo"
  run omarchy-appimage-remove "Foo"
  [ "$status" -eq 0 ]

  [ ! -e "$DESKTOP_DIR/Foo.desktop" ]
  [ ! -e "$APPS_DIR/Foo.AppImage" ]
  [ -z "$(ls -A "$ICONS_DIR")" ]
}

@test "remove: --keep-file preserves the payload only, in either argument order" {
  install_fixture Foo.AppImage "Foo"
  omarchy-appimage-remove --keep-file "Foo"
  [ -e "$APPS_DIR/Foo.AppImage" ]
  [ ! -e "$DESKTOP_DIR/Foo.desktop" ]
  rm -f "$APPS_DIR/Foo.AppImage"

  install_fixture Bar.AppImage "Bar"
  omarchy-appimage-remove "Bar" --keep-file
  [ -e "$APPS_DIR/Bar.AppImage" ]
  [ ! -e "$DESKTOP_DIR/Bar.desktop" ]
}

@test "remove: payload path with metacharacters round-trips and is deleted" {
  nasty='We"ird $ubuntu `x` 100% App.AppImage'
  install_fixture "$nasty" "Nasty"
  [ -e "$APPS_DIR/$nasty" ]

  omarchy-appimage-remove "Nasty"
  [ ! -e "$APPS_DIR/$nasty" ]
  [ -z "$(ls -A "$APPS_DIR")" ]
}

@test "remove: the picker lists only AppImage launchers" {
  install_fixture Foo.AppImage "Foo"
  cat >"$DESKTOP_DIR/A Web App.desktop" <<'DESK'
[Desktop Entry]
Name=A Web App
Exec=omarchy-launch-webapp "https://example.com"
Type=Application
DESK

  MENU_SELECT_CHOICE="Foo" omarchy-appimage-remove
  offered=$(stub_log_for omarchy-menu-select)
  [[ $offered == *"Foo"* ]]
  [[ $offered != *"A Web App"* ]]
  [ -e "$DESKTOP_DIR/A Web App.desktop" ]
}

@test "remove: exits non-zero with a message when nothing is installed" {
  run omarchy-appimage-remove
  [ "$status" -ne 0 ]
  [[ $output == *"No AppImages to remove"* ]]
}

@test "remove: a launcher whose payload is already gone is still cleaned up" {
  install_fixture Foo.AppImage "Foo"
  rm -f "$APPS_DIR/Foo.AppImage"

  run omarchy-appimage-remove "Foo"
  [ "$status" -eq 0 ]
  [ ! -e "$DESKTOP_DIR/Foo.desktop" ]
  [ -z "$(ls -A "$ICONS_DIR")" ]
}

@test "remove: notifies by default and stays quiet when suppressed" {
  install_fixture Foo.AppImage "Foo"
  omarchy-appimage-remove "Foo"
  stub_called omarchy-notification-send

  : >"$STUB_LOG"
  install_fixture Bar.AppImage "Bar"
  OMARCHY_REMOVE_NOTIFY=false omarchy-appimage-remove "Bar"
  run stub_called omarchy-notification-send
  [ "$status" -ne 0 ]
}

@test "remove: refreshes the desktop database" {
  install_fixture Foo.AppImage "Foo"
  : >"$STUB_LOG"
  omarchy-appimage-remove "Foo"
  stub_called update-desktop-database
}

@test "remove: sweeps icons out of whatever hicolor size they landed in" {
  make_appimage "$HOME/Downloads/Foo.AppImage" --name "Foo" --icon-128
  omarchy-appimage-install "$HOME/Downloads/Foo.AppImage" >/dev/null
  [ -f "$ICON_BASE/128x128/apps/foo.png" ]

  omarchy-appimage-remove "Foo"
  [ ! -e "$ICON_BASE/128x128/apps/foo.png" ]
  run find "$ICON_BASE" -name 'foo.*' -type f
  [ -z "$output" ]
}

@test "remove: reads the payload from its own key, not from Exec" {
  install_fixture Foo.AppImage "Foo"

  # Corrupt the Exec path. Removal must still find and delete the payload,
  # which it can only do by reading X-AppImage-Payload.
  sed -i 's|^Exec=.*|Exec=omarchy-launch-appimage "/nonexistent/Decoy.AppImage"|' \
    "$DESKTOP_DIR/Foo.desktop"

  omarchy-appimage-remove "Foo"
  [ ! -e "$APPS_DIR/Foo.AppImage" ]
  [ ! -e "$DESKTOP_DIR/Foo.desktop" ]
}

@test "remove: a launcher without the payload key still loses launcher and icon" {
  install_fixture Foo.AppImage "Foo"
  # A launcher as an older version of this tool would have written it.
  sed -i '/^X-AppImage-Payload=/d' "$DESKTOP_DIR/Foo.desktop"

  run omarchy-appimage-remove "Foo"
  [ "$status" -eq 0 ]
  [ ! -e "$DESKTOP_DIR/Foo.desktop" ]
  # The icon is keyed off the app name, so it goes regardless.
  [ -z "$(find "$ICON_BASE" -type f -name 'foo.*')" ]
  # The payload cannot be located without the key, so it is left behind.
  [ -e "$APPS_DIR/Foo.AppImage" ]
}
