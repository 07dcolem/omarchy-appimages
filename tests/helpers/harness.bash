#!/bin/bash
#
# Per-test isolation: a throwaway HOME, a stub PATH, and a teardown assertion
# that nothing escaped into the real home directory.

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
export REPO_ROOT

# shellcheck source=tests/helpers/fixtures.bash
source "$REPO_ROOT/tests/helpers/fixtures.bash"

harness_setup() {
  REAL_HOME="$HOME"
  export REAL_HOME
  REAL_APPS_EXISTED=0
  [[ -e "$REAL_HOME/Applications" ]] && REAL_APPS_EXISTED=1

  TESTROOT=$(mktemp -d)
  export TESTROOT
  export HOME="$TESTROOT/home"
  export XDG_CACHE_HOME="$HOME/.cache"
  export XDG_CONFIG_HOME="$HOME/.config"
  export XDG_DATA_HOME="$HOME/.local/share"
  export XDG_STATE_HOME="$HOME/.local/state"
  # A session value would hide /usr/share, and the association script trusts
  # XDG_DATA_DIRS when it is set. Keep the system mime dir visible.
  export XDG_DATA_DIRS="/usr/local/share:/usr/share"
  export APPS_DIR="$HOME/Applications"
  export DESKTOP_DIR="$HOME/.local/share/applications"
  export ICON_BASE="$HOME/.local/share/icons/hicolor"
  export ICONS_DIR="$ICON_BASE/256x256/apps"

  mkdir -p "$HOME/Downloads" "$APPS_DIR" "$DESKTOP_DIR" "$ICONS_DIR" \
    "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"

  REAL_OPEN_DESKTOP="$REAL_HOME/.local/share/applications/07dcolem-appimages-open.desktop"
  REAL_OPEN_STATE="$REAL_HOME/.local/state/07dcolem-appimages"
  REAL_OPEN_MIME="$REAL_HOME/.local/share/mime/packages/07dcolem-appimages.xml"
  REAL_OPEN_DESKTOP_EXISTED=0
  REAL_OPEN_STATE_EXISTED=0
  REAL_OPEN_MIME_EXISTED=0
  [[ -e $REAL_OPEN_DESKTOP ]] && REAL_OPEN_DESKTOP_EXISTED=1
  [[ -e $REAL_OPEN_STATE ]] && REAL_OPEN_STATE_EXISTED=1
  [[ -e $REAL_OPEN_MIME ]] && REAL_OPEN_MIME_EXISTED=1

  export STUB_LOG="$TESTROOT/stub.log"
  export LAUNCH_LOG="$TESTROOT/launch.log"
  : >"$STUB_LOG"
  : >"$LAUNCH_LOG"

  export PATH="$REPO_ROOT/tests/helpers/stubs:$REPO_ROOT/bin:$PATH"
}

harness_teardown() {
  # The suite must never touch the developer's real home directory.
  if ((REAL_APPS_EXISTED == 0)) && [[ -e "$REAL_HOME/Applications" ]]; then
    echo "FATAL: a test created $REAL_HOME/Applications" >&2
    return 1
  fi
  if ((REAL_OPEN_DESKTOP_EXISTED == 0)) && [[ -e $REAL_OPEN_DESKTOP ]]; then
    echo "FATAL: a test created $REAL_OPEN_DESKTOP" >&2
    return 1
  fi
  if ((REAL_OPEN_STATE_EXISTED == 0)) && [[ -e $REAL_OPEN_STATE ]]; then
    echo "FATAL: a test created $REAL_OPEN_STATE" >&2
    return 1
  fi
  if ((REAL_OPEN_MIME_EXISTED == 0)) && [[ -e $REAL_OPEN_MIME ]]; then
    echo "FATAL: a test created $REAL_OPEN_MIME" >&2
    return 1
  fi
  [[ -n ${TESTROOT-} ]] && rm -rf "$TESTROOT"
  return 0
}

stub_called() {
  grep -q "^$1 " "$STUB_LOG"
}

stub_log_for() {
  grep "^$1 " "$STUB_LOG" || true
}

# The exact transformation Omarchy's stripJsonc applies before JSON.parse:
# whole-line // comments removed, then trailing commas before } or ].
strip_jsonc() {
  perl -0777 -pe 's{^\s*//[^\n]*(\n|$)}{}gm; s/,(\s*[}\]])/$1/g' "$1"
}

desktop_key() {
  sed -n "s/^$2=//p" "$1" | head -1
}

count_key() {
  grep -c "^$2=" "$1" || true
}
