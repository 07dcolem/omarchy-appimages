#!/usr/bin/env bats

load helpers/harness

@test "list: a long app list scrolls inside the card" {
  if ! command -v node >/dev/null; then skip "node not installed"; fi
  run node --test "$REPO_ROOT/tests/list-scroll.test.mjs"
  [ "$status" -eq 0 ]
  grep -F 'id: appList' "$REPO_ROOT/Panel.qml"
  grep -F 'Model.listViewport' "$REPO_ROOT/Panel.qml"
  grep -F 'Model.listContentHeight' "$REPO_ROOT/Panel.qml"
  grep -F 'Model.listRoom' "$REPO_ROOT/Panel.qml"
  grep -F 'clip: true' "$REPO_ROOT/Panel.qml"
  grep -F 'ScrollBar.AsNeeded' "$REPO_ROOT/Panel.qml"
  grep -F 'keyNavigationEnabled: false' "$REPO_ROOT/Panel.qml"
  grep -F 'Keys.priority: Keys.BeforeItem' "$REPO_ROOT/Panel.qml"
  grep -F 'focusPolicy: Qt.NoFocus' "$REPO_ROOT/Panel.qml"
  grep -F 'positionViewAtIndex' "$REPO_ROOT/Panel.qml"
  ! grep -F 'id: listColumn' "$REPO_ROOT/Panel.qml"
}
