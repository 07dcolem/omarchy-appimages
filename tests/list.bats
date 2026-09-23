#!/usr/bin/env bats

load helpers/harness

setup() { harness_setup; }
teardown() { harness_teardown; }

@test "list: prints installers only, as JSON, and ignores other launchers" {
  make_appimage "$HOME/Downloads/Foo.AppImage" --name "Foo Bar" --comment "A fixture"
  omarchy-appimage-install "$HOME/Downloads/Foo.AppImage" >/dev/null

  cat >"$DESKTOP_DIR/A Web App.desktop" <<'DESK'
[Desktop Entry]
Name=A Web App
Exec=omarchy-launch-webapp "https://example.com"
Type=Application
DESK

  run omarchy-appimage-list
  [ "$status" -eq 0 ]
  [[ $output == *'"name":"Foo Bar"'* ]]
  [[ $output == *'"payload":"'"$APPS_DIR/Foo.AppImage"'"'* ]]
  [[ $output != *"A Web App"* ]]
  [[ $output == *'"fuse":true'* ]]
}

@test "list: an empty desktop dir is an empty app list" {
  run omarchy-appimage-list
  [ "$status" -eq 0 ]
  [[ $output == *'"apps":[]'* ]]
}

@test "list: reports fuse missing when ldconfig has no libfuse.so.2" {
  FAKE_NO_FUSE=1 run omarchy-appimage-list
  [ "$status" -eq 0 ]
  [[ $output == *'"fuse":false'* ]]
}
