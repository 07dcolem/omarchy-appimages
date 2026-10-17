#!/usr/bin/env bats

load helpers/harness

setup() { harness_setup; }
teardown() { harness_teardown; }

install_fixture() {
  local file="${1:-Foo.AppImage}" name="${2:-Foo}"
  make_appimage "$HOME/Downloads/$file" --name "$name"
  omarchy-appimage-install "$HOME/Downloads/$file" >/dev/null
}

@test "remove: --drop-duplicates hides our shortcut and keeps the installed app" {
  install_fixture Foo.AppImage "Foo"
  cat >"$DESKTOP_DIR/foo-own.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Foo
Exec=$APPS_DIR/Foo.AppImage %U
EOF
  cat >"$DESKTOP_DIR/not-foo.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Not Foo
Exec=$APPS_DIR/Foo.AppImage.backup %U
EOF
  run omarchy-appimage-remove --drop-duplicates
  [ "$status" -eq 0 ]
  [[ $output == *"Hid the shortcut for Foo. It stays in this list."* ]]
  [ -e "$DESKTOP_DIR/Foo.desktop" ]
  grep -qx 'NoDisplay=true' "$DESKTOP_DIR/Foo.desktop"
  grep -qx 'X-AppImage-Suppressed=duplicate' "$DESKTOP_DIR/Foo.desktop"
  [ -e "$APPS_DIR/Foo.AppImage" ]
  [ -e "$DESKTOP_DIR/foo-own.desktop" ]
  [ -e "$DESKTOP_DIR/not-foo.desktop" ]
  [ -n "$(find "$ICON_BASE" -type f -name 'foo.*')" ]
  [ ! -e "$HOME/pwned" ]
  run omarchy-appimage-list
  [ "$status" -eq 0 ]
  [[ $output == *'"name":"Foo"'* ]]
  run omarchy-appimage-remove --drop-duplicates
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  grep -qx 'NoDisplay=true' "$DESKTOP_DIR/Foo.desktop"
}

@test "remove: --drop-duplicates ignores a launcher that is the only shortcut" {
  install_fixture Foo.AppImage "Foo"
  run omarchy-appimage-remove --drop-duplicates
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -e "$DESKTOP_DIR/Foo.desktop" ]
  [ -e "$APPS_DIR/Foo.AppImage" ]
}

@test "remove: --drop-duplicates matches a quoted path and does not run an Exec line" {
  install_fixture "My App.AppImage" "My App"
  printf '%s\n' '[Desktop Entry]' 'Type=Application' "Exec=\"$APPS_DIR/My App.AppImage\" %U" >"$DESKTOP_DIR/own.desktop"
  printf '%s\n' '[Desktop Entry]' 'Type=Application' 'Exec=$(touch '"$HOME"'/pwned)' >"$DESKTOP_DIR/trap.desktop"
  run omarchy-appimage-remove --drop-duplicates
  [ "$status" -eq 0 ]
  [[ $output == *"Hid the shortcut for My App. It stays in this list."* ]]
  [ -e "$DESKTOP_DIR/My App.desktop" ]
  grep -qx 'NoDisplay=true' "$DESKTOP_DIR/My App.desktop"
  [ -e "$APPS_DIR/My App.AppImage" ]
  [ -e "$DESKTOP_DIR/own.desktop" ]
  [ -e "$DESKTOP_DIR/trap.desktop" ]
  [ ! -e "$HOME/pwned" ]
  run omarchy-appimage-list
  [ "$status" -eq 0 ]
  [[ $output == *'"name":"My App"'* ]]
}

@test "remove: --drop-duplicates keeps a desktop action on the hidden launcher" {
  install_fixture Foo.AppImage "Foo"
  printf '\n%s\n' '[Desktop Action Extra]' 'Name=Extra' 'Exec=true' >>"$DESKTOP_DIR/Foo.desktop"
  printf '%s\n' '[Desktop Entry]' 'Type=Application' "Exec=$APPS_DIR/Foo.AppImage" >"$DESKTOP_DIR/own.desktop"
  run omarchy-appimage-remove --drop-duplicates
  [ "$status" -eq 0 ]
  grep -qx 'NoDisplay=true' "$DESKTOP_DIR/Foo.desktop"
  grep -qx '\[Desktop Action Extra\]' "$DESKTOP_DIR/Foo.desktop"
  grep -qx 'Name=Extra' "$DESKTOP_DIR/Foo.desktop"
  awk '
    /^\[Desktop Entry\]$/ { entry = 1; next }
    /^\[/ { entry = 0 }
    entry && $0 == "NoDisplay=true" { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$DESKTOP_DIR/Foo.desktop"
  run omarchy-appimage-list
  [[ $output == *'"name":"Foo"'* ]]
}

@test "remove: --drop-duplicates ignores a hidden handler that names the payload" {
  install_fixture Foo.AppImage "Foo"
  cat >"$DESKTOP_DIR/foo-handler.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Foo Handler
NoDisplay=true
Exec=$APPS_DIR/Foo.AppImage %U
EOF
  run omarchy-appimage-remove --drop-duplicates
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -e "$DESKTOP_DIR/Foo.desktop" ]
  ! grep -q '^NoDisplay=' "$DESKTOP_DIR/Foo.desktop"
  run omarchy-appimage-list
  [[ $output == *'"name":"Foo"'* ]]
}

@test "remove: --drop-duplicates restores our shortcut when the other one is gone" {
  install_fixture Foo.AppImage "Foo"
  printf '%s\n' '[Desktop Entry]' 'Type=Application' 'Name=Foo' "Exec=$APPS_DIR/Foo.AppImage" >"$DESKTOP_DIR/foo-own.desktop"
  omarchy-appimage-remove --drop-duplicates
  grep -qx 'NoDisplay=true' "$DESKTOP_DIR/Foo.desktop"
  rm -f "$DESKTOP_DIR/foo-own.desktop"
  run omarchy-appimage-remove --drop-duplicates
  [ "$status" -eq 0 ]
  [[ $output == *"Restored the shortcut for Foo."* ]]
  ! grep -q '^NoDisplay=' "$DESKTOP_DIR/Foo.desktop"
  ! grep -q '^X-AppImage-Suppressed=' "$DESKTOP_DIR/Foo.desktop"
  run omarchy-appimage-list
  [[ $output == *'"name":"Foo"'* ]]
}

@test "remove: --show-shortcuts restores our shortcut while the app's own stays" {
  install_fixture Foo.AppImage "Foo"
  printf '%s\n' '[Desktop Entry]' 'Type=Application' 'Name=Own Foo' "Exec=$APPS_DIR/Foo.AppImage" >"$DESKTOP_DIR/foo-own.desktop"
  omarchy-appimage-remove --drop-duplicates
  run omarchy-appimage-remove --show-shortcuts
  [ "$status" -eq 0 ]
  [[ $output == *"Restored the shortcut for Foo."* ]]
  ! grep -q '^NoDisplay=' "$DESKTOP_DIR/Foo.desktop"
  [ -e "$DESKTOP_DIR/foo-own.desktop" ]
  [ -e "$APPS_DIR/Foo.AppImage" ]
  run omarchy-appimage-list
  [[ $output == *'"name":"Foo"'* ]]
}

@test "remove: --show-shortcuts leaves a NoDisplay line it did not add" {
  install_fixture Foo.AppImage "Foo"
  printf '\n%s\n' 'NoDisplay=true' >>"$DESKTOP_DIR/Foo.desktop"
  run omarchy-appimage-remove --show-shortcuts
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  grep -qx 'NoDisplay=true' "$DESKTOP_DIR/Foo.desktop"
}

@test "remove: --drop-duplicates refuses to combine with a name" {
  run omarchy-appimage-remove --drop-duplicates --keep-file Foo
  [ "$status" -eq 2 ]
  [[ $output == *"Could not check shortcuts."* ]]
  run omarchy-appimage-remove --show-shortcuts --drop-duplicates
  [ "$status" -eq 2 ]
  run omarchy-appimage-remove --show-shortcuts Foo
  [ "$status" -eq 2 ]
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
