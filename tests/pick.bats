#!/usr/bin/env bats

load helpers/harness

setup() {
  harness_setup
  STUB_DIR="$TESTROOT/stubs"
  mkdir -p "$STUB_DIR"
  cat >"$STUB_DIR/gdbus" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"${PICK_STUB_LOG:?}"
if [[ $* == *Request.Close* ]]; then
  exit 0
fi
if [[ $* == *OpenFile* ]]; then
  if [[ -n ${PICK_STUB_OPEN_FAIL:-} ]]; then
    exit 1
  fi
  printf '%s\n' "${!#}" >"${PICK_STUB_OPTIONS:?}"
  printf '%s\n' "(objectpath '/org/freedesktop/portal/desktop/request/1_7/pick',)"
  exit 0
fi
if [[ $* == *monitor* ]]; then
  printf '%s\n' "$$" >"${PICK_STUB_MON_PID:?}"
  if [[ -n ${PICK_STUB_SLEEP:-} ]]; then
    sleep 30
    exit 0
  fi
  printf '%s\n' "${PICK_STUB_RESPONSE:-}"
  if [[ -n ${PICK_STUB_HOLD:-} ]]; then
    sleep 30
  fi
  exit 0
fi
printf 'unexpected gdbus\n' >&2
exit 99
STUB
  chmod 755 "$STUB_DIR/gdbus"
  export PATH="$STUB_DIR:$PATH"
  # The developer session is Hyprland. Raising must not touch that compositor.
  unset HYPRLAND_INSTANCE_SIGNATURE
  export PICK_STUB_LOG="$TESTROOT/gdbus.log"
  export PICK_STUB_OPTIONS="$TESTROOT/options"
  export PICK_STUB_MON_PID="$TESTROOT/mon.pid"
  : >"$PICK_STUB_LOG"
}

teardown() { harness_teardown; }

decode_folder() {
  local options=$1 rest n byte out=""
  [[ $options == *"'current_folder': <[byte "* ]]
  rest=${options#*"'current_folder': <["}
  rest=${rest%%']>'*}
  while read -r n; do
    printf -v byte '\\%03o' "$n"
    out+=$(printf '%b' "$byte")
  done < <(grep -oE '[0-9]+' <<<"$rest")
  printf '%s' "${out%$'\0'}"
}

@test "pick: prints one decoded local path and does not keep the monitor" {
  export PICK_STUB_RESPONSE="/org/freedesktop/portal/desktop/request/1_7/pick: org.freedesktop.portal.Request.Response (uint32 0, {'uris': <['file:///tmp/My%20App%27s.AppImage']>})"
  export PICK_STUB_HOLD=1
  run timeout 5 omarchy-appimage-pick "$HOME/Downloads"
  [ "$status" -eq 0 ]
  [ "$output" = "/tmp/My App's.AppImage" ]
  [ -s "$PICK_STUB_MON_PID" ]
  ! kill -0 "$(cat "$PICK_STUB_MON_PID")" 2>/dev/null
}

@test "pick: a cancelled chooser exits quietly" {
  export PICK_STUB_RESPONSE="/org/freedesktop/portal/desktop/request/1_7/pick: org.freedesktop.portal.Request.Response (uint32 1, @a{sv} {})"
  run timeout 5 omarchy-appimage-pick
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "pick: a non-file URI and an embedded NUL are refused" {
  export PICK_STUB_RESPONSE="/org/freedesktop/portal/desktop/request/1_7/pick: org.freedesktop.portal.Request.Response (uint32 0, {'uris': <['http://example.com/a.AppImage']>})"
  run timeout 5 omarchy-appimage-pick
  [ "$status" -eq 2 ]
  [[ $output == *"will not use"* ]]

  export PICK_STUB_RESPONSE="/org/freedesktop/portal/desktop/request/1_7/pick: org.freedesktop.portal.Request.Response (uint32 0, {'uris': <['file:///tmp/a%00.AppImage']>})"
  run timeout 5 omarchy-appimage-pick
  [ "$status" -eq 2 ]
}

@test "pick: a missing portal reports failure and runs nothing else" {
  export PICK_STUB_OPEN_FAIL=1
  run timeout 5 omarchy-appimage-pick
  [ "$status" -eq 2 ]
  [[ $output == *"Could not open the file chooser."* ]]
  ! grep -q monitor "$PICK_STUB_LOG"
}

@test "pick: the start folder is decimal bytes, so a quote in it is not shell" {
  nasty="$TESTROOT/odd'name\$(touch $HOME/pwned)"
  mkdir -p -- "$nasty"
  export PICK_STUB_RESPONSE="/org/freedesktop/portal/desktop/request/1_7/pick: org.freedesktop.portal.Request.Response (uint32 0, {'uris': <['file:///tmp/Ok.AppImage']>})"
  run timeout 5 omarchy-appimage-pick "$nasty"
  [ "$status" -eq 0 ]
  [ "$output" = "/tmp/Ok.AppImage" ]
  [ ! -e "$HOME/pwned" ]
  options=$(cat "$PICK_STUB_OPTIONS")
  [[ $options == '{'*'}' ]]
  [[ $options != *'}',* ]]
  [[ $options == *"'current_folder': <[byte "* ]]
  [[ $options != *"odd'name"* ]]
  [[ $options != *'$(touch'* ]]
  [ "$(decode_folder "$options")" = "$nasty" ]
}

@test "pick: stopping the script stops the chooser monitor" {
  export PICK_STUB_SLEEP=1
  omarchy-appimage-pick "$HOME/Downloads" &
  pid=$!
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    [[ -s $PICK_STUB_MON_PID ]] && break
    sleep 0.05
  done
  [ -s "$PICK_STUB_MON_PID" ]
  mon=$(cat "$PICK_STUB_MON_PID")
  kill -TERM "$pid"
  wait "$pid" || true
  ! kill -0 "$mon" 2>/dev/null
  ! kill -0 "$pid" 2>/dev/null
}

@test "pick: Hyprland focus uses the portal address and not the window title" {
  export HYPRLAND_INSTANCE_SIGNATURE=test
  export PICK_STUB_HYPR_LOG="$TESTROOT/hypr.log"
  : >"$PICK_STUB_HYPR_LOG"
  cat >"$STUB_DIR/hyprctl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"${PICK_STUB_HYPR_LOG:?}"
if [[ $1 == clients ]]; then
  printf '%s\n' "Window 0xbad -> Add an AppImage:"
  printf '%s\n' "	floating: 0"
  printf '%s\n' "	class: not-the-portal"
  printf '%s\n' "	title: Add an AppImage"
  printf '%s\n' "	title: \$(touch pwned)"
  printf '%s\n' "Window deadbeef -> Add an AppImage:"
  printf '%s\n' "	floating: ${PICK_STUB_FLOATING:-1}"
  printf '%s\n' "	class: xdg-desktop-portal-gtk"
  printf '%s\n' "	title: Add an AppImage"
fi
exit 0
STUB
  chmod 755 "$STUB_DIR/hyprctl"
  export PICK_STUB_RESPONSE="/org/freedesktop/portal/desktop/request/1_7/pick: org.freedesktop.portal.Request.Response (uint32 0, {'uris': <['file:///tmp/Ok.AppImage']>})"
  export PICK_STUB_FLOATING=1
  run timeout 5 omarchy-appimage-pick "$HOME/Downloads"
  [ "$status" -eq 0 ]
  [ "$output" = "/tmp/Ok.AppImage" ]
  [ ! -e "$HOME/pwned" ]
  grep -F 'hl.dsp.window.pin({ window = "address:0xdeadbeef", action = "set" })' "$PICK_STUB_HYPR_LOG"
  grep -F 'hl.dsp.focus({ window = "address:0xdeadbeef" })' "$PICK_STUB_HYPR_LOG"
  grep -F 'hl.dsp.window.alter_zorder({ window = "address:0xdeadbeef", mode = "top" })' "$PICK_STUB_HYPR_LOG"
  grep -F 'hl.dsp.window.bring_to_top({ window = "address:0xdeadbeef" })' "$PICK_STUB_HYPR_LOG"
  ! grep -F 'hl.dsp.window.float' "$PICK_STUB_HYPR_LOG"
  ! grep -F '0xbad' "$PICK_STUB_HYPR_LOG"
  ! grep -F 'touch' "$PICK_STUB_HYPR_LOG"
  ! grep -F 'not-the-portal' "$PICK_STUB_HYPR_LOG"
  options=$(cat "$PICK_STUB_OPTIONS")
  [[ $options == *"'modal': <true>"* ]]

  : >"$PICK_STUB_HYPR_LOG"
  export PICK_STUB_FLOATING=0
  run timeout 5 omarchy-appimage-pick "$HOME/Downloads"
  [ "$status" -eq 0 ]
  grep -F 'hl.dsp.window.float({ window = "address:0xdeadbeef", action = "set" })' "$PICK_STUB_HYPR_LOG"
  grep -F 'hl.dsp.window.pin({ window = "address:0xdeadbeef", action = "set" })' "$PICK_STUB_HYPR_LOG"
  ! grep -F '0xbad' "$PICK_STUB_HYPR_LOG"
}

@test "panel: add does not open a Qt file dialog, and a row can unlist" {
  ! grep -E 'QtQuick\.Dialogs|FileDialog' "$REPO_ROOT/Panel.qml"
  grep -F 'omarchy-appimage-pick' "$REPO_ROOT/Panel.qml"
  grep -F 'stdbuf -oL gdbus monitor' "$REPO_ROOT/bin/omarchy-appimage-pick"
  grep -F 'label: "Unlist"' "$REPO_ROOT/Panel.qml"
  grep -F 'root.removeApp(true)' "$REPO_ROOT/Panel.qml"
  grep -F 'pickProc.running' "$REPO_ROOT/Panel.qml"
  grep -F 'raise_chooser' "$REPO_ROOT/bin/omarchy-appimage-pick"
  grep -F 'Removes the desktop entry' "$REPO_ROOT/README.md" || grep -F 'deletes the desktop entry' "$REPO_ROOT/README.md"
}
