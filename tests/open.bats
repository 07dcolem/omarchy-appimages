#!/usr/bin/env bats

load helpers/harness

setup() {
  harness_setup
  export APPIMAGE_RELEASE_WAIT=0
  export APPIMAGE_EXEC_LOG="$TESTROOT/exec.log"
  : >"$APPIMAGE_EXEC_LOG"
  HANDLER=$DESKTOP_DIR/07dcolem-appimages-open.desktop
  MIMEAPPS=$XDG_CONFIG_HOME/mimeapps.list
  STATE=$XDG_STATE_HOME/07dcolem-appimages/association.json
  MIME_PACKAGE=$XDG_DATA_HOME/mime/packages/07dcolem-appimages.xml
}

teardown() { harness_teardown; }

mime_default() {
  [[ -f $MIMEAPPS ]] || return 0
  awk -v mime="application/vnd.appimage" '
    BEGIN { section = 0 }
    {
      line = $0
      sub(/\r$/, "", line)
      if (substr(line, 1, 1) == "[") {
        section = (line == "[Default Applications]")
        next
      }
      if (section && index(line, mime "=") == 1) {
        print substr(line, length(mime) + 2)
        exit
      }
    }
  ' "$MIMEAPPS"
}

write_mimeapps() {
  mkdir -p "$XDG_CONFIG_HOME"
  printf '%s\n' "$@" >"$MIMEAPPS"
}

assert_handler_file() {
  [ -f "$HANDLER" ]
  [ ! -L "$HANDLER" ]
  grep -qx 'NoDisplay=true' "$HANDLER"
  grep -qx 'MimeType=application/vnd.appimage;' "$HANDLER"
  ! grep -q 'application/octet-stream' "$HANDLER"
  ! grep -q 'application/x-executable' "$HANDLER"
  grep -q 'omarchy-appimage-open' "$HANDLER"
  ! grep -q 'omarchy-launch-appimage' "$HANDLER"
}

@test "switch: a missing config key is off" {
  node --input-type=commonjs - "$REPO_ROOT/Model.js" "$REPO_ROOT/manifest.json" <<'JS'
const fs = require("fs")
const vm = require("vm")
const src = fs.readFileSync(process.argv[2], "utf8").replace(/^\.pragma library\s*/, "")
const context = {}
vm.createContext(context)
vm.runInContext(src, context)
function assert(cond, msg) {
  if (!cond) {
    console.error(msg)
    process.exit(1)
  }
}
const missing = { id: "07dcolem.appimages" }
assert(context.openWithPanelEnabled(missing) === false, "missing key")
assert(context.openWithPanelEnabled({}) === false, "empty settings")
assert(context.openWithPanelEnabled(null) === false, "null")
assert(context.openWithPanelEnabled({ openWithPanel: false }) === false, "false")
assert(context.openWithPanelEnabled({ openWithPanel: "true" }) === false, "string")
assert(context.openWithPanelEnabled({ openWithPanel: 1 }) === false, "number")
assert(context.openWithPanelEnabled({ openWithPanel: true }) === true, "boolean true")
const shell = {
  version: 1,
  bar: { layout: { left: [], center: [], right: [{ id: "07dcolem.appimages" }] } }
}
const entry = context.layoutEntry(shell, "07dcolem.appimages")
assert(entry && entry.openWithPanel === undefined, "layout entry has no key")
assert(context.openWithPanelEnabled(entry) === false, "layout entry is off")
const named = context.layoutEntry({ layout: { right: ["07dcolem.appimages"] } }, "07dcolem.appimages")
assert(named === "07dcolem.appimages", "string entry")
assert(context.openWithPanelEnabled(named) === false, "string entry is off")
const manifest = JSON.parse(fs.readFileSync(process.argv[3], "utf8"))
assert(manifest.version === "0.1.6", "version")
assert(manifest.barWidget.defaults.openWithPanel === false, "default")
const schema = manifest.barWidget.schema.find((item) => item.key === "openWithPanel")
assert(schema && schema.type === "boolean" && schema.defaultValue === false, "schema")
JS
  grep -F 'property bool associationOn: false' "$REPO_ROOT/Panel.qml"
  grep -F 'onSettingsChanged' "$REPO_ROOT/BarWidget.qml"
  ! grep -F 'Component.onCompleted' "$REPO_ROOT/BarWidget.qml"
  sentence='A double-click opens the panel, and the file does not run until Install or Update.'
  grep -F "$sentence" "$REPO_ROOT/Panel.qml"
  grep -F "$sentence" "$REPO_ROOT/README.md"
  grep -F "$sentence" "$REPO_ROOT/manifest.json"
}

@test "association: turning it on sets the MIME default" {
  write_mimeapps \
    '[Default Applications]' \
    'application/vnd.appimage=kept.desktop' \
    'text/plain=editor.desktop' \
    '' \
    '[Added Associations]'
  : >"$STUB_LOG"
  omarchy-appimage-open --on
  [ "$(mime_default)" = "07dcolem-appimages-open.desktop" ]
  grep -qx 'text/plain=editor.desktop' "$MIMEAPPS"
  [ "$(jq -r .previous "$STATE")" = "kept.desktop" ]
  assert_handler_file
  stub_called update-desktop-database
  # The system already ships this type, so no user mime package is added.
  [ ! -e "$MIME_PACKAGE" ]
  ! stub_called update-mime-database

  omarchy-appimage-open --on
  [ "$(jq -r .previous "$STATE")" = "kept.desktop" ]
  [ "$(mime_default)" = "07dcolem-appimages-open.desktop" ]
}

@test "association: turning it off restores the saved handler" {
  write_mimeapps \
    '[Default Applications]' \
    'application/vnd.appimage=kept.desktop;other.desktop' \
    'text/plain=editor.desktop'
  omarchy-appimage-open --on
  [ "$(mime_default)" = "07dcolem-appimages-open.desktop" ]
  omarchy-appimage-open --off
  [ "$(mime_default)" = "kept.desktop;other.desktop" ]
  grep -qx 'text/plain=editor.desktop' "$MIMEAPPS"
  [ ! -e "$HANDLER" ]
  [ ! -e "$STATE" ]
}

@test "association: no previous handler clears the default" {
  write_mimeapps \
    '[Default Applications]' \
    'text/plain=editor.desktop'
  omarchy-appimage-open --on
  [ "$(mime_default)" = "07dcolem-appimages-open.desktop" ]
  omarchy-appimage-open --off
  [ -z "$(mime_default)" ]
  grep -qx 'text/plain=editor.desktop' "$MIMEAPPS"
  [ ! -e "$HANDLER" ]
}

@test "association: a handler we no longer own is left alone" {
  write_mimeapps \
    '[Default Applications]' \
    'application/vnd.appimage=kept.desktop'
  omarchy-appimage-open --on
  write_mimeapps \
    '[Default Applications]' \
    'application/vnd.appimage=other.desktop' \
    'text/plain=editor.desktop'
  omarchy-appimage-open --off
  [ "$(mime_default)" = "other.desktop" ]
  grep -qx 'text/plain=editor.desktop' "$MIMEAPPS"
  [ ! -e "$HANDLER" ]
  [ ! -e "$STATE" ]
}

@test "association: a desktop file we did not write is left alone" {
  mkdir -p "$DESKTOP_DIR"
  printf 'not our handler\n' >"$HANDLER"
  omarchy-appimage-open --off
  [ "$(cat "$HANDLER")" = "not our handler" ]

  write_mimeapps '[Default Applications]' 'application/vnd.appimage=kept.desktop'
  omarchy-appimage-open --on
  printf 'replaced\n' >"$HANDLER"
  omarchy-appimage-open --off
  [ "$(cat "$HANDLER")" = "replaced" ]
  [ "$(mime_default)" = "kept.desktop" ]
}

@test "association: plugin remove restores the saved handler" {
  # Disable and remove destroy the bar widget. It --release's its token, which
  # is the same restore as the switch turning off.
  write_mimeapps \
    '[Default Applications]' \
    'application/vnd.appimage=kept.desktop' \
    'text/plain=editor.desktop'
  omarchy-appimage-open --apply tokenremove0001 on
  [ "$(mime_default)" = "07dcolem-appimages-open.desktop" ]
  omarchy-appimage-open --apply tokenremove0002 on 200
  omarchy-appimage-open --release tokenremove0001
  [ "$(mime_default)" = "07dcolem-appimages-open.desktop" ]
  [ -f "$HANDLER" ]
  omarchy-appimage-open --release tokenremove0002
  [ "$(mime_default)" = "kept.desktop" ]
  grep -qx 'text/plain=editor.desktop' "$MIMEAPPS"
  [ ! -e "$HANDLER" ]
  [ ! -e "$STATE" ]
}

@test "association: an older stamp cannot overwrite a newer one" {
  write_mimeapps '[Default Applications]' 'application/vnd.appimage=kept.desktop'
  omarchy-appimage-open --apply tokenstamp000001 on 300
  omarchy-appimage-open --apply tokenstamp000002 off 100
  [ "$(mime_default)" = "07dcolem-appimages-open.desktop" ]
  omarchy-appimage-open --apply tokenstamp000002 off 400
  [ "$(mime_default)" = "kept.desktop" ]
}

@test "association: the handler desktop file is NoDisplay=true" {
  write_mimeapps '[Default Applications]' 'text/plain=editor.desktop'
  omarchy-appimage-open --on
  assert_handler_file
  [ "$(basename "$HANDLER")" = "07dcolem-appimages-open.desktop" ]
  grep -q '%u' "$HANDLER"
}

@test "association: opening via the handler does not execute the file" {
  make_appimage "$HOME/Downloads/Foo.AppImage" --name "Foo"
  local_path=$HOME/Downloads/Foo.AppImage
  mode=$(stat -c %a "$local_path")
  [ -x "$local_path" ]
  : >"$STUB_LOG"
  : >"$APPIMAGE_EXEC_LOG"
  omarchy-appimage-open "$local_path"
  [ "$(stat -c %a "$local_path")" = "$mode" ]
  [ ! -s "$APPIMAGE_EXEC_LOG" ]
  grep -F "omarchy-shell shell summon 07dcolem.appimages" "$STUB_LOG"
  grep -F "$local_path" "$STUB_LOG"
  ! grep -q 'uwsm-app' "$STUB_LOG"

  : >"$STUB_LOG"
  : >"$APPIMAGE_EXEC_LOG"
  omarchy-appimage-open "file://localhost${local_path}"
  [ "$(stat -c %a "$local_path")" = "$mode" ]
  [ ! -s "$APPIMAGE_EXEC_LOG" ]
  grep -F "$local_path" "$STUB_LOG"

  spaced="$HOME/Downloads/My Files"
  mkdir -p "$spaced"
  make_appimage "$spaced/Bar.AppImage" --name "Bar"
  spaced_path=$spaced/Bar.AppImage
  spaced_mode=$(stat -c %a "$spaced_path")
  uri="file://${spaced_path// /%20}"
  : >"$STUB_LOG"
  : >"$APPIMAGE_EXEC_LOG"
  omarchy-appimage-open "$uri"
  [ "$(stat -c %a "$spaced_path")" = "$spaced_mode" ]
  [ ! -s "$APPIMAGE_EXEC_LOG" ]
  grep -F "$spaced_path" "$STUB_LOG"
}

@test "association: opening does not mark a file executable" {
  plain=$HOME/Downloads/Plain.AppImage
  printf 'not an elf\n' >"$plain"
  chmod 644 "$plain"
  : >"$STUB_LOG"
  omarchy-appimage-open "$plain"
  [ "$(stat -c %a "$plain")" = "644" ]
  [ ! -x "$plain" ]
  grep -F "$plain" "$STUB_LOG"
}

@test "association: a symlink or another scheme is refused" {
  make_appimage "$HOME/Downloads/Foo.AppImage" --name "Foo"
  ln -s "$HOME/Downloads/Foo.AppImage" "$HOME/Downloads/Link.AppImage"
  : >"$STUB_LOG"
  : >"$APPIMAGE_EXEC_LOG"
  run omarchy-appimage-open "$HOME/Downloads/Link.AppImage"
  [ "$status" -ne 0 ]
  [[ $output == *"symlink"* ]]
  [ ! -s "$APPIMAGE_EXEC_LOG" ]
  ! grep -q 'omarchy-shell' "$STUB_LOG"

  : >"$STUB_LOG"
  run omarchy-appimage-open "https://example.com/Foo.AppImage"
  [ "$status" -ne 0 ]
  [[ $output == *"refusing that location"* ]]
  ! grep -q 'omarchy-shell' "$STUB_LOG"

  run omarchy-appimage-open "file://example.com$HOME/Downloads/Foo.AppImage"
  [ "$status" -ne 0 ]
  run omarchy-appimage-open "file://$HOME/Downloads/Foo.AppImage?x=1"
  [ "$status" -ne 0 ]
  run omarchy-appimage-open "Foo.AppImage"
  [ "$status" -ne 0 ]
  run omarchy-appimage-open "$HOME/Downloads/Foo.AppImage" extra
  [ "$status" -eq 2 ]
  [ ! -s "$APPIMAGE_EXEC_LOG" ]
}

@test "association: a missing MIME type gets our package only" {
  export XDG_DATA_DIRS="$TESTROOT/empty-share"
  mkdir -p "$XDG_DATA_DIRS"
  write_mimeapps '[Default Applications]' 'text/plain=editor.desktop'
  : >"$STUB_LOG"
  omarchy-appimage-open --on
  [ -f "$MIME_PACKAGE" ]
  grep -q 'application/vnd.appimage' "$MIME_PACKAGE"
  ! grep -q 'application/octet-stream' "$MIME_PACKAGE"
  ! grep -q 'application/x-executable' "$MIME_PACKAGE"
  stub_called update-mime-database
  omarchy-appimage-open --off
  [ ! -e "$MIME_PACKAGE" ]
  stub_called update-desktop-database
}

@test "association: a mime package we did not add is left alone" {
  export XDG_DATA_DIRS="$TESTROOT/empty-share"
  mkdir -p "$TESTROOT/empty-share" "$(dirname "$MIME_PACKAGE")"
  printf 'foreign package\n' >"$MIME_PACKAGE"
  write_mimeapps '[Default Applications]' 'text/plain=editor.desktop'
  omarchy-appimage-open --on
  [ "$(cat "$MIME_PACKAGE")" = "foreign package" ]
  omarchy-appimage-open --off
  [ "$(cat "$MIME_PACKAGE")" = "foreign package" ]
}

@test "association: an existing launcher is not rewritten" {
  make_appimage "$HOME/Downloads/Foo.AppImage" --name "Foo Bar"
  omarchy-appimage-install "$HOME/Downloads/Foo.AppImage"
  launcher="$DESKTOP_DIR/Foo Bar.desktop"
  payload=$APPS_DIR/Foo.AppImage
  before=$(cat "$launcher")
  [ -e "$payload" ]
  omarchy-appimage-open --on
  [ "$(cat "$launcher")" = "$before" ]
  [ -e "$payload" ]
  [ -f "$HANDLER" ]
  [ "$HANDLER" != "$launcher" ]
  exec_line=$(desktop_key "$launcher" Exec)
  [[ $exec_line == *omarchy-launch-appimage* ]]
  [[ $exec_line != *omarchy-appimage-open* ]]
}

@test "association: nothing catches a direct execution" {
  ! grep -q 'binfmt_misc' "$REPO_ROOT/bin/omarchy-appimage-open"
  ! grep -q 'bashrc' "$REPO_ROOT/bin/omarchy-appimage-open"
  omarchy-appimage-open --on
  [ ! -e "$HOME/.bashrc" ]
  [ ! -e "$HOME/.profile" ]
}
