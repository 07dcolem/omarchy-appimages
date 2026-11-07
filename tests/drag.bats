#!/usr/bin/env bats

load helpers/harness

@test "drag: keyboard focus stays off until the drag session ends" {
  if ! command -v node >/dev/null; then skip "node not installed"; fi
  run node --test "$REPO_ROOT/tests/drag-focus.test.mjs"
  [ "$status" -eq 0 ]
}

@test "drag: drop handlers do not change keyboard focus" {
  python3 - "$REPO_ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])

def drop_bodies(text):
    bodies = []
    needle = "DropArea {"
    start = 0
    while True:
        at = text.find(needle, start)
        if at < 0:
            break
        brace = text.find("{", at)
        depth = 0
        for i in range(brace, len(text)):
            if text[i] == "{":
                depth += 1
            elif text[i] == "}":
                depth -= 1
                if depth == 0:
                    bodies.append(text[brace:i + 1])
                    start = i + 1
                    break
        else:
            raise SystemExit("unclosed DropArea")
    return bodies

panel = (root / "Panel.qml").read_text()
bar = (root / "BarWidget.qml").read_text()
assert "Model.keyboardFocusMode" in panel
assert "releaseDragGrab" in panel
for body in drop_bodies(panel) + drop_bodies(bar):
    for banned in ("dragging", "keyboardFocus", "holdKeys", "takeFocus"):
        if banned in body:
            raise SystemExit(f"DropArea writes {banned}:\n{body}")
bar_drop = [b for b in drop_bodies(bar) if "onDropped" in b][0]
later = bar_drop.find("Qt.callLater")
summon = bar_drop.find("summon")
if later < 0 or summon < later:
    raise SystemExit("bar drop must summon from Qt.callLater")
if "dragHover" in bar and "summon({ drag" in bar:
    raise SystemExit("bar must not summon while a drag is held")
PY
}
