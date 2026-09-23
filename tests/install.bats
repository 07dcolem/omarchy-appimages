#!/usr/bin/env bats

load helpers/harness

setup() { harness_setup; }
teardown() { harness_teardown; }

@test "install: local path lands the payload and a valid launcher" {
  make_appimage "$HOME/Downloads/Foo.AppImage" --name "Foo Bar"
  run omarchy-appimage-install "$HOME/Downloads/Foo.AppImage"
  [ "$status" -eq 0 ]

  [ -x "$APPS_DIR/Foo.AppImage" ]
  [ ! -e "$HOME/Downloads/Foo.AppImage" ]
  [ -f "$DESKTOP_DIR/Foo Bar.desktop" ]
  [ -f "$ICONS_DIR/foo-bar.png" ]
  [[ $output == *"Moved"* ]]

  run desktop-file-validate "$DESKTOP_DIR/Foo Bar.desktop"
  [ "$status" -eq 0 ]
}

@test "install: Exec starts with the routing marker and quotes the payload" {
  make_appimage "$HOME/Downloads/Foo.AppImage" --name "Foo Bar"
  omarchy-appimage-install "$HOME/Downloads/Foo.AppImage"

  exec_line=$(desktop_key "$DESKTOP_DIR/Foo Bar.desktop" Exec)
  # Exec quotes the launch script next to the installer. The plugin bin is not
  # on $PATH, so the desktop file cannot call a bare command name.
  launch_bin="$(cd "$REPO_ROOT/bin" && pwd)/omarchy-launch-appimage"
  [[ $exec_line == \"$launch_bin\"\ \"* ]]
}

@test "install: carries Categories and StartupWMClass from the bundle" {
  make_appimage "$HOME/Downloads/Foo.AppImage" --name "Foo" \
    --categories "Development;IDE;" --wmclass "foo-class"
  omarchy-appimage-install "$HOME/Downloads/Foo.AppImage"

  [ "$(desktop_key "$DESKTOP_DIR/Foo.desktop" Categories)" = "Development;IDE;" ]
  [ "$(desktop_key "$DESKTOP_DIR/Foo.desktop" StartupWMClass)" = "foo-class" ]
}

@test "install: omits Categories entirely when the bundle has none" {
  make_appimage "$HOME/Downloads/Foo.AppImage" --name "Foo" --categories "" --wmclass ""
  omarchy-appimage-install "$HOME/Downloads/Foo.AppImage"

  run grep -c '^Categories=' "$DESKTOP_DIR/Foo.desktop"
  [ "$status" -ne 0 ]
  run grep -c '^StartupWMClass=' "$DESKTOP_DIR/Foo.desktop"
  [ "$status" -ne 0 ]
}

@test "install: explicit name argument overrides the bundled name" {
  make_appimage "$HOME/Downloads/Foo.AppImage" --name "Bundled Name"
  omarchy-appimage-install "$HOME/Downloads/Foo.AppImage" "Chosen Name"

  [ -f "$DESKTOP_DIR/Chosen Name.desktop" ]
  [ ! -e "$DESKTOP_DIR/Bundled Name.desktop" ]
}

@test "install: a file already in Applications is left in place" {
  make_appimage "$APPS_DIR/Foo.AppImage" --name "Foo"
  run omarchy-appimage-install "$APPS_DIR/Foo.AppImage"
  [ "$status" -eq 0 ]
  [ -x "$APPS_DIR/Foo.AppImage" ]
  [[ $output == *"Already in place"* ]]
}

@test "install: rejects a file that is not an AppImage without moving it" {
  make_not_an_appimage "$HOME/Downloads/plain"
  run omarchy-appimage-install "$HOME/Downloads/plain"
  [ "$status" -ne 0 ]
  [[ $output == *"Not an AppImage"* ]]
  [ -e "$HOME/Downloads/plain" ]
  [ -z "$(ls -A "$APPS_DIR")" ]
}

@test "install: rejects a name containing a slash and writes nothing" {
  make_appimage "$HOME/Downloads/Foo.AppImage" --name "Foo"
  run omarchy-appimage-install "$HOME/Downloads/Foo.AppImage" "bad/name"
  [ "$status" -ne 0 ]
  [[ $output == *"cannot contain"* ]]
  [ -z "$(ls -A "$DESKTOP_DIR")" ]
  [ -e "$HOME/Downloads/Foo.AppImage" ]
}

@test "install: refuses a second app under an existing launcher name" {
  make_appimage "$HOME/Downloads/One.AppImage" --name "Same"
  omarchy-appimage-install "$HOME/Downloads/One.AppImage"

  make_appimage "$HOME/Downloads/Two.AppImage" --name "Same"
  run omarchy-appimage-install "$HOME/Downloads/Two.AppImage"
  [ "$status" -ne 0 ]
  [[ $output == *"already exists"* ]]
  [ -e "$HOME/Downloads/Two.AppImage" ]
}

@test "install: a newline in the given name is refused outright" {
  make_appimage "$HOME/Downloads/Foo.AppImage" --name "Foo"
  run omarchy-appimage-install "$HOME/Downloads/Foo.AppImage" "$(printf 'Evil\nExec=false')"
  [ "$status" -ne 0 ]
  [[ $output == *"cannot contain a tab"* ]]
  [ -z "$(ls -A "$DESKTOP_DIR")" ]
}

@test "install: a backslash and leading space in the name are escaped, not injected" {
  make_appimage "$HOME/Downloads/Foo.AppImage" --name "Foo"
  omarchy-appimage-install "$HOME/Downloads/Foo.AppImage" ' Back\slash App'

  launcher="$DESKTOP_DIR/ Back\slash App.desktop"
  [ -f "$launcher" ]
  [ "$(count_key "$launcher" Name)" -eq 1 ]
  [ "$(count_key "$launcher" Exec)" -eq 1 ]
  # Backslash doubled, and the leading space replaced by \s (which consumes it).
  [ "$(desktop_key "$launcher" Name)" = '\sBack\\slash App' ]
  run desktop-file-validate "$launcher"
  [ "$status" -eq 0 ]
}

@test "install: a payload path with shell metacharacters survives validation" {
  nasty='We"ird $ubuntu `x` 100% App.AppImage'
  make_appimage "$HOME/Downloads/$nasty" --name "Nasty"
  omarchy-appimage-install "$HOME/Downloads/$nasty"

  [ -x "$APPS_DIR/$nasty" ]
  run desktop-file-validate "$DESKTOP_DIR/Nasty.desktop"
  [ "$status" -eq 0 ]
}

@test "install: falls back to a generic icon when the bundle has none" {
  make_appimage "$HOME/Downloads/Foo.AppImage" --name "Foo" --no-icon
  run omarchy-appimage-install "$HOME/Downloads/Foo.AppImage"
  [ "$status" -eq 0 ]
  [[ $output == *"No icon found"* ]]
  [ "$(desktop_key "$DESKTOP_DIR/Foo.desktop" Icon)" = "application-x-executable" ]
}

@test "install: type-1 bundle uses the filename and a generic icon" {
  make_appimage "$HOME/Downloads/Legacy.AppImage" --type 1
  run omarchy-appimage-install "$HOME/Downloads/Legacy.AppImage"
  [ "$status" -eq 0 ]
  [ -f "$DESKTOP_DIR/Legacy.desktop" ]
  [ "$(desktop_key "$DESKTOP_DIR/Legacy.desktop" Icon)" = "application-x-executable" ]
}

@test "install: picks one bundled desktop entry deterministically" {
  make_appimage "$HOME/Downloads/Foo.AppImage" --name "Chosen" --extra-desktop
  omarchy-appimage-install "$HOME/Downloads/Foo.AppImage"
  [ -f "$DESKTOP_DIR/Chosen.desktop" ]
}

@test "install: URL strips the query string and appends .AppImage" {
  make_appimage "$TESTROOT/remote-payload" --name "Remote App"
  CURL_FIXTURE="$TESTROOT/remote-payload" \
    omarchy-appimage-install "https://example.com/Downloads/Bar?token=abc123"

  [ -x "$APPS_DIR/Bar.AppImage" ]
  [ -f "$DESKTOP_DIR/Remote App.desktop" ]
}

@test "install: a failed download leaves nothing at the final payload path" {
  run env CURL_FAIL=1 omarchy-appimage-install "https://example.com/Bar.AppImage"
  [ "$status" -ne 0 ]
  [ ! -e "$APPS_DIR/Bar.AppImage" ]
  [ -z "$(ls -A "$APPS_DIR")" ]
}

@test "install: cross-filesystem source still lands the payload whole" {
  if [ ! -w /dev/shm ]; then skip "/dev/shm not writable"; fi
  other=$(mktemp -d /dev/shm/appimage-test-XXXXXX)
  make_appimage "$other/Foo.AppImage" --name "Foo"
  before=$(stat -c %s "$other/Foo.AppImage")

  run omarchy-appimage-install "$other/Foo.AppImage"
  status_copy=$status
  after=$(stat -c %s "$APPS_DIR/Foo.AppImage" 2>/dev/null || echo -1)
  rm -rf "$other"

  [ "$status_copy" -eq 0 ]
  [ "$before" = "$after" ]
}

@test "install: warns but succeeds when libfuse.so.2 is missing" {
  make_appimage "$HOME/Downloads/Foo.AppImage" --name "Foo"
  run env FAKE_NO_FUSE=1 omarchy-appimage-install "$HOME/Downloads/Foo.AppImage"
  [ "$status" -eq 0 ]
  [[ $output == *"libfuse.so.2 is missing"* ]]
  run desktop-file-validate "$DESKTOP_DIR/Foo.desktop"
  [ "$status" -eq 0 ]
}

@test "install: extraction directory is cleaned up after success and failure" {
  make_appimage "$HOME/Downloads/Foo.AppImage" --name "Foo"
  omarchy-appimage-install "$HOME/Downloads/Foo.AppImage"
  [ -z "$(ls -A "$XDG_CACHE_HOME/omarchy-appimage" 2>/dev/null)" ]

  make_appimage "$HOME/Downloads/Bad.AppImage" --name "Foo"
  run omarchy-appimage-install "$HOME/Downloads/Bad.AppImage"
  [ "$status" -ne 0 ]
  [ -z "$(ls -A "$XDG_CACHE_HOME/omarchy-appimage" 2>/dev/null)" ]
}

@test "install: extraction does not use tmpfs /tmp" {
  make_appimage "$HOME/Downloads/Foo.AppImage" --name "Foo"
  TMPDIR=/nonexistent-on-purpose omarchy-appimage-install "$HOME/Downloads/Foo.AppImage"
  [ -f "$DESKTOP_DIR/Foo.desktop" ]
}

@test "install: carries MimeType through so URL scheme handlers survive" {
  make_appimage "$HOME/Downloads/Foo.AppImage" --name "Foo" \
    --mime "x-scheme-handler/foo;x-scheme-handler/bar;"
  omarchy-appimage-install "$HOME/Downloads/Foo.AppImage"

  [ "$(desktop_key "$DESKTOP_DIR/Foo.desktop" MimeType)" = "x-scheme-handler/foo;x-scheme-handler/bar;" ]
  run desktop-file-validate "$DESKTOP_DIR/Foo.desktop"
  [ "$status" -eq 0 ]
}

@test "install: omits MimeType when the bundle declares none" {
  make_appimage "$HOME/Downloads/Foo.AppImage" --name "Foo"
  omarchy-appimage-install "$HOME/Downloads/Foo.AppImage"
  run grep -c '^MimeType=' "$DESKTOP_DIR/Foo.desktop"
  [ "$status" -ne 0 ]
}

@test "install: uses the bundle's Comment, falling back to the name" {
  make_appimage "$HOME/Downloads/Foo.AppImage" --name "Foo" --comment "A real description"
  omarchy-appimage-install "$HOME/Downloads/Foo.AppImage"
  [ "$(desktop_key "$DESKTOP_DIR/Foo.desktop" Comment)" = "A real description" ]

  make_appimage "$HOME/Downloads/Bar.AppImage" --name "Bar"
  omarchy-appimage-install "$HOME/Downloads/Bar.AppImage"
  [ "$(desktop_key "$DESKTOP_DIR/Bar.desktop" Comment)" = "Bar" ]
}

@test "install: files the icon under the hicolor size matching its resolution" {
  make_appimage "$HOME/Downloads/Foo.AppImage" --name "Foo" --icon-128
  omarchy-appimage-install "$HOME/Downloads/Foo.AppImage"

  [ -f "$ICON_BASE/128x128/apps/foo.png" ]
  [ ! -e "$ICONS_DIR/foo.png" ]
}

@test "install: falls back to 256x256 for icons hicolor does not declare" {
  # hicolor's index.theme declares apps directories only up to 512x512, so an
  # icon filed under 1024x1024 is never found by freedesktop icon lookup.
  make_appimage "$HOME/Downloads/Big.AppImage" --name "Big" --icon-1024
  omarchy-appimage-install "$HOME/Downloads/Big.AppImage"

  [ -f "$ICON_BASE/256x256/apps/big.png" ]
  [ ! -e "$ICON_BASE/1024x1024/apps/big.png" ]
}

@test "install: warns loudly when a type-2 bundle will not extract" {
  make_appimage "$HOME/Downloads/Broken.AppImage" --type 2 --refuse-extract
  run omarchy-appimage-install "$HOME/Downloads/Broken.AppImage"
  [ "$status" -eq 0 ]
  [[ $output == *"could not extract"* ]]
  [[ $output == *"libfuse"* ]]
  [ -f "$DESKTOP_DIR/Broken.desktop" ]
  [ "$(desktop_key "$DESKTOP_DIR/Broken.desktop" Icon)" = "application-x-executable" ]
}

@test "install: the interactive picker supplies the path without typing" {
  make_appimage "$HOME/Downloads/Picked.AppImage" --name "Picked App"
  GUM_FILE="$HOME/Downloads/Picked.AppImage" run omarchy-appimage-install
  [ "$status" -eq 0 ]
  [ -f "$DESKTOP_DIR/Picked App.desktop" ]
  [ -x "$APPS_DIR/Picked.AppImage" ]
}

@test "install: escaping out of the picker falls through to the text prompt" {
  make_appimage "$HOME/Downloads/Typed.AppImage" --name "Typed App"
  GUM_INPUT="$HOME/Downloads/Typed.AppImage" run omarchy-appimage-install
  [ "$status" -eq 0 ]
  [ -f "$DESKTOP_DIR/Typed App.desktop" ]
}

@test "install: the picker lists AppImages newest first, not a filesystem browser" {
  # Noise the picker must not offer, of the kind a real Downloads folder is full of.
  touch "$HOME/Downloads/notes.pdf" "$HOME/Downloads/archive.tar.gz"
  make_appimage "$HOME/Downloads/Older.AppImage" --name "Older"
  sleep 0.01
  make_appimage "$HOME/Downloads/Newer.AppImage" --name "Newer"

  GUM_FILE="$HOME/Downloads/Newer.AppImage" run omarchy-appimage-install
  [ "$status" -eq 0 ]
  [ -f "$DESKTOP_DIR/Newer.desktop" ]

  offered=$(stub_log_for gum)
  [[ $offered == *"filter"* ]]
  [[ $offered != *"notes.pdf"* ]]
}

@test "install: with no AppImages lying around it goes straight to the prompt" {
  make_appimage "$TESTROOT/elsewhere/Hidden.AppImage" --name "Hidden"
  GUM_INPUT="$TESTROOT/elsewhere/Hidden.AppImage" run omarchy-appimage-install
  [ "$status" -eq 0 ]
  [ -f "$DESKTOP_DIR/Hidden.desktop" ]
}

@test "install: choosing 'Enter a path or URL' falls through to the prompt" {
  make_appimage "$HOME/Downloads/Listed.AppImage" --name "Listed"
  make_appimage "$TESTROOT/elsewhere/Typed.AppImage" --name "Typed"

  GUM_FILE="Enter a path or URL..." GUM_INPUT="$TESTROOT/elsewhere/Typed.AppImage" \
    run omarchy-appimage-install
  [ "$status" -eq 0 ]
  [ -f "$DESKTOP_DIR/Typed.desktop" ]
  [ ! -e "$DESKTOP_DIR/Listed.desktop" ]
}

@test "install: records X-AppImage-Version so an upgrade can name it" {
  make_appimage "$HOME/Downloads/Foo.AppImage" --name "Foo" --version "1.2.3"
  omarchy-appimage-install "$HOME/Downloads/Foo.AppImage"
  [ "$(desktop_key "$DESKTOP_DIR/Foo.desktop" X-AppImage-Version)" = "1.2.3" ]
}

@test "install: --replace upgrades in place and retires the old payload" {
  make_appimage "$HOME/Downloads/App-1.0.AppImage" --name "Same App" --version "1.0"
  omarchy-appimage-install "$HOME/Downloads/App-1.0.AppImage"
  [ -e "$APPS_DIR/App-1.0.AppImage" ]

  make_appimage "$HOME/Downloads/App-2.0.AppImage" --name "Same App" --version "2.0"
  run omarchy-appimage-install "$HOME/Downloads/App-2.0.AppImage" --replace
  [ "$status" -eq 0 ]

  # The differently-named old payload must not be left behind.
  [ ! -e "$APPS_DIR/App-1.0.AppImage" ]
  [ -e "$APPS_DIR/App-2.0.AppImage" ]
  [ "$(ls -A "$APPS_DIR" | wc -l)" -eq 1 ]
  [ "$(desktop_key "$DESKTOP_DIR/Same App.desktop" X-AppImage-Version)" = "2.0" ]
  [[ $output == *"Removed the previous payload"* ]]
}

@test "install: --replace works when the new build keeps the same filename" {
  make_appimage "$HOME/Downloads/App.AppImage" --name "Same App" --version "1.0"
  omarchy-appimage-install "$HOME/Downloads/App.AppImage"

  make_appimage "$HOME/Downloads/App.AppImage" --name "Same App" --version "2.0"
  run omarchy-appimage-install "$HOME/Downloads/App.AppImage" --replace
  [ "$status" -eq 0 ]
  [ -e "$APPS_DIR/App.AppImage" ]
  [ "$(desktop_key "$DESKTOP_DIR/Same App.desktop" X-AppImage-Version)" = "2.0" ]
}

@test "install: --replace sweeps an old icon of a different resolution" {
  make_appimage "$HOME/Downloads/App-1.0.AppImage" --name "Same App" --icon-128
  omarchy-appimage-install "$HOME/Downloads/App-1.0.AppImage"
  [ -f "$ICON_BASE/128x128/apps/same-app.png" ]

  make_appimage "$HOME/Downloads/App-2.0.AppImage" --name "Same App"
  omarchy-appimage-install "$HOME/Downloads/App-2.0.AppImage" --replace

  [ ! -e "$ICON_BASE/128x128/apps/same-app.png" ]
  [ "$(find "$ICON_BASE" -name 'same-app.*' -type f | wc -l)" -eq 1 ]
}

@test "install: the interactive prompt offers to replace, and declining aborts" {
  make_appimage "$HOME/Downloads/App-1.0.AppImage" --name "Same App" --version "1.0"
  omarchy-appimage-install "$HOME/Downloads/App-1.0.AppImage"

  make_appimage "$HOME/Downloads/App-2.0.AppImage" --name "Same App" --version "2.0"

  # Declining leaves the old install untouched.
  GUM_FILE="$HOME/Downloads/App-2.0.AppImage" GUM_CONFIRM=no run omarchy-appimage-install
  [ "$status" -ne 0 ]
  [ -e "$APPS_DIR/App-1.0.AppImage" ]
  [ "$(desktop_key "$DESKTOP_DIR/Same App.desktop" X-AppImage-Version)" = "1.0" ]

  # Accepting upgrades, and names both versions in the prompt.
  GUM_FILE="$HOME/Downloads/App-2.0.AppImage" GUM_CONFIRM=yes run omarchy-appimage-install
  [ "$status" -eq 0 ]
  [ "$(desktop_key "$DESKTOP_DIR/Same App.desktop" X-AppImage-Version)" = "2.0" ]
  [ ! -e "$APPS_DIR/App-1.0.AppImage" ]
  [[ $(stub_log_for gum) == *"1.0 with 2.0"* ]]
}

@test "install: still refuses a collision non-interactively without --replace" {
  make_appimage "$HOME/Downloads/One.AppImage" --name "Same App"
  omarchy-appimage-install "$HOME/Downloads/One.AppImage"

  make_appimage "$HOME/Downloads/Two.AppImage" --name "Same App"
  run omarchy-appimage-install "$HOME/Downloads/Two.AppImage"
  [ "$status" -ne 0 ]
  [[ $output == *"--replace"* ]]
  [ -e "$HOME/Downloads/Two.AppImage" ]
}

@test "install: records the payload path in its own key, unescaped for plain paths" {
  make_appimage "$HOME/Downloads/Foo.AppImage" --name "Foo"
  omarchy-appimage-install "$HOME/Downloads/Foo.AppImage"
  [ "$(desktop_key "$DESKTOP_DIR/Foo.desktop" X-AppImage-Payload)" = "$APPS_DIR/Foo.AppImage" ]
}

@test "install: the payload key round-trips shell metacharacters" {
  nasty='We"ird $ubuntu `x` 100% (1).AppImage'
  make_appimage "$HOME/Downloads/$nasty" --name "Nasty"
  omarchy-appimage-install "$HOME/Downloads/$nasty"

  # No escaping is needed for these: only backslash and a leading space are
  # transformed by desktop-entry string escaping.
  [ "$(desktop_key "$DESKTOP_DIR/Nasty.desktop" X-AppImage-Payload)" = "$APPS_DIR/$nasty" ]
  run desktop-file-validate "$DESKTOP_DIR/Nasty.desktop"
  [ "$status" -eq 0 ]
}

@test "install: a plain .DirIcon with no extension installs as a usable png" {
  make_appimage "$HOME/Downloads/Foo.AppImage" --name "Foo" --diricon-plain
  run omarchy-appimage-install "$HOME/Downloads/Foo.AppImage"
  [ "$status" -eq 0 ]

  # The extension comes from content, not the path: ${path##*.} on
  # .../extract-XXXX/squashfs-root/.DirIcon yields "DirIcon", which no icon
  # loader would ever find.
  [ -z "$(find "$ICON_BASE" -name 'foo.DirIcon')" ]
  [ -n "$(find "$ICON_BASE" -name 'foo.png' -type f)" ]
  [ "$(desktop_key "$DESKTOP_DIR/Foo.desktop" Icon)" = "foo" ]
}

@test "install: an icon that cannot be installed does not strand the payload" {
  make_appimage "$HOME/Downloads/Foo.AppImage" --name "Foo"
  # Block only the size subdirectory, not $ICON_BASE itself: install creates
  # the base early, before the payload moves, so breaking that would fail for a
  # different reason. The 1x1 fixture icon resolves to the 256x256 fallback.
  rm -rf "$ICON_BASE/256x256"
  : >"$ICON_BASE/256x256"

  run omarchy-appimage-install "$HOME/Downloads/Foo.AppImage"
  [ "$status" -eq 0 ]
  [[ $output == *"Could not install the bundle's icon"* ]]

  # The install still completed rather than aborting under set -e with the
  # user's file relocated and nothing pointing at it.
  [ -x "$APPS_DIR/Foo.AppImage" ]
  [ -f "$DESKTOP_DIR/Foo.desktop" ]
  [ "$(desktop_key "$DESKTOP_DIR/Foo.desktop" Icon)" = "application-x-executable" ]
  run desktop-file-validate "$DESKTOP_DIR/Foo.desktop"
  [ "$status" -eq 0 ]
}

@test "install: a non-executable download still yields the bundle's metadata" {
  # Browsers save AppImages without the executable bit. Extraction executes the
  # bundle, so without chmod first the metadata is silently lost and the app is
  # named after its filename.
  make_appimage "$HOME/Downloads/Foo.AppImage" --name "Real Name" \
    --categories "Network;" --version "9.9"
  chmod -x "$HOME/Downloads/Foo.AppImage"

  run omarchy-appimage-install "$HOME/Downloads/Foo.AppImage"
  [ "$status" -eq 0 ]
  [[ $output != *"could not extract"* ]]

  [ -f "$DESKTOP_DIR/Real Name.desktop" ]
  [ "$(desktop_key "$DESKTOP_DIR/Real Name.desktop" Categories)" = "Network;" ]
  [ "$(desktop_key "$DESKTOP_DIR/Real Name.desktop" X-AppImage-Version)" = "9.9" ]
  [ -x "$APPS_DIR/Foo.AppImage" ]
}
