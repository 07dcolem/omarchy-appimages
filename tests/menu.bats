#!/usr/bin/env bats

load helpers/harness

setup() {
  harness_setup
  MENU_FILE="$TESTROOT/omarchy-menu.jsonc"
  export MENU_FILE
}
teardown() { harness_teardown; }

@test "menu: creates a parseable file when none exists" {
  "$REPO_ROOT/menu/omarchy-appimage-menu" add "$MENU_FILE"
  strip_jsonc "$MENU_FILE" | jq -e 'keys' >/dev/null

  keys=$(strip_jsonc "$MENU_FILE" | jq -r 'keys[]')
  [[ $keys == *"install.appimage"* ]]
  [[ $keys == *"remove.appimage"* ]]
}

@test "menu: rows survive the exact transformation Omarchy applies before JSON.parse" {
  "$REPO_ROOT/menu/omarchy-appimage-menu" add "$MENU_FILE"
  action=$(strip_jsonc "$MENU_FILE" | jq -r '."install.appimage".action')
  [[ $action == *"omarchy-appimage-install"* ]]
  [[ $action == *"floating-terminal"* ]]
}

@test "menu: keeps an existing user row and is idempotent" {
  printf '{\n  "personal.notes": {"icon":"N","label":"Notes","action":"true"},\n}\n' >"$MENU_FILE"
  "$REPO_ROOT/menu/omarchy-appimage-menu" add "$MENU_FILE"
  "$REPO_ROOT/menu/omarchy-appimage-menu" add "$MENU_FILE"

  [ "$(grep -c '>>> omarchy-appimage-integration' "$MENU_FILE")" -eq 1 ]
  keys=$(strip_jsonc "$MENU_FILE" | jq -r 'keys[]')
  [[ $keys == *"personal.notes"* ]]
  [[ $keys == *"install.appimage"* ]]
}

@test "menu: uninstall restores the file byte-identically" {
  printf '{\n  "personal.notes": {"icon":"N","label":"Notes","action":"true"},\n}\n' >"$MENU_FILE"
  cp "$MENU_FILE" "$TESTROOT/before"

  "$REPO_ROOT/menu/omarchy-appimage-menu" add "$MENU_FILE"
  "$REPO_ROOT/menu/omarchy-appimage-menu" remove "$MENU_FILE"

  run cmp -s "$TESTROOT/before" "$MENU_FILE"
  [ "$status" -eq 0 ]
}

@test "menu: refuses a file with no opening brace rather than corrupting it" {
  printf 'not json at all\n' >"$MENU_FILE"
  cp "$MENU_FILE" "$TESTROOT/before"

  run "$REPO_ROOT/menu/omarchy-appimage-menu" add "$MENU_FILE"
  [ "$status" -ne 0 ]
  run cmp -s "$TESTROOT/before" "$MENU_FILE"
  [ "$status" -eq 0 ]
}

@test "menu: the remove row guard is false with no AppImages and true with one" {
  "$REPO_ROOT/menu/omarchy-appimage-menu" add "$MENU_FILE"
  guard=$(strip_jsonc "$MENU_FILE" | jq -r '."remove.appimage".when')

  run bash -c "$guard"
  [ "$status" -ne 0 ]

  make_appimage "$HOME/Downloads/Foo.AppImage" --name "Foo"
  omarchy-appimage-install "$HOME/Downloads/Foo.AppImage" >/dev/null

  run bash -c "$guard"
  [ "$status" -eq 0 ]
}

@test "menu: make install and uninstall drive the same rows" {
  run make -C "$REPO_ROOT" install BINDIR="$TESTROOT/bin" MENU_FILE="$MENU_FILE"
  [ "$status" -eq 0 ]
  [ -x "$TESTROOT/bin/omarchy-appimage-install" ]
  [ -f "$MENU_FILE" ]

  run make -C "$REPO_ROOT" uninstall BINDIR="$TESTROOT/bin" MENU_FILE="$MENU_FILE"
  [ "$status" -eq 0 ]
  [ ! -e "$TESTROOT/bin/omarchy-appimage-install" ]
  run grep -c 'omarchy-appimage-integration' "$MENU_FILE"
  [ "$status" -ne 0 ]
}
