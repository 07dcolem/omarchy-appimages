# AppImage integration for Omarchy

Spec for a set of `omarchy-appimage-*` scripts that give AppImages the same
install/launch/remove treatment Omarchy already gives web apps and TUIs.
Nothing here is implemented yet — this is the design plus a reference
implementation to build from on the main install.

Verified against **Omarchy 4.0.3-1** on the test box, 2026-09-13.

## Why

Omarchy has no AppImage handling at all. A case-insensitive grep across the
entire `/usr/share/omarchy` tree (bin, install scripts, config templates,
defaults) returns zero matches. There is no `omarchy appimage` command group,
no desktop-entry generation, no mimetype handling, no integration daemon.

This is consistent with Omarchy's packages-first philosophy — `omarchy pkg add`
and `omarchy install ...` cover pacman and the AUR, and most apps people reach
for as AppImages have an AUR package. But it leaves a real gap for the ones
that don't (vendor-only builds, betas, one-off tools).

Meanwhile Omarchy *does* ship first-class launcher generation for two other
kinds of not-a-pacman-package software:

| Command | What it makes |
|---------|---------------|
| `omarchy webapp install` | `.desktop` running `omarchy-launch-webapp <url>` |
| `omarchy tui install` | `.desktop` running `xdg-terminal-exec ... -e <cmd>` |
| `omarchy games retro install` | `.desktop` for a RetroArch game |

AppImages should be a third entry in that table. The design below is a direct
mirror of the webapp/tui pattern rather than anything novel.

### What the old main install did (do not just recreate it)

The pre-Omarchy Arch install on `/mnt/main` used **AppImageLauncher**
(`appimagelauncher 3.0.0_beta_3-1`, explicitly installed, plus `libappimage`),
which is what produced `~/Applications/*_<32 hex chars>.AppImage` and the
`~/.config/appimagelauncher.cfg` there. It works by intercepting AppImage
execution and prompting to "integrate" — heavier than what's needed here, and
the packaged version is still a years-old beta.

The spec below deliberately does not depend on it. If the scripts turn out not
to be worth maintaining, installing AppImageLauncher again is the fallback, not
the plan.

## Prerequisite: FUSE 2

**Omarchy does not install `fuse2`.** The test box has only `fuse3 3.18.2-1` and
`fuse-common`. Type-2 AppImages (essentially all of them) dlopen
`libfuse.so.2` and fail on a stock install with:

```
dlopen(): error loading libfuse.so.2
AppImages require FUSE to run.
```

So on the main install, before any of this matters:

```bash
omarchy pkg add fuse2
```

`fuse2` is in the `extra` repo and coexists with `fuse3`. The alternative is
running each AppImage with `--appimage-extract-and-run`, which needs no FUSE but
unpacks the whole bundle to a temp dir on every launch — slower startup and
noticeable disk churn for large apps. The install script below warns when
`libfuse.so.2` is missing rather than failing, since the launcher is still valid
once FUSE is added.

## How Omarchy's existing launcher machinery works

Three mechanics discovered by reading the source; the design depends on all
three, so they're recorded here rather than re-derived later.

**1. Removal is routed by sniffing the `Exec=` line.**
`omarchy-remove-launcher-entry` (hidden command, and what the app launcher's
right-click "remove" calls) reads the first `Exec=` out of the `.desktop` and
dispatches:

- matches `omarchy-launch-webapp|omarchy-webapp-handler` → `omarchy-webapp-remove`
- matches `$TERMINAL|xdg-terminal-exec ... -e` → `omarchy-tui-remove`
- otherwise, if the file is in a user applications dir → plain `rm -f` + `update-desktop-database`
- otherwise, if pacman owns it → `sudo pacman -Rns` in a floating terminal
- otherwise, if flatpak knows it → `flatpak uninstall`

This is why the launcher's `Exec` should start with a dedicated
`omarchy-launch-appimage` wrapper rather than pointing straight at the
`.AppImage`: the wrapper name is the hook that makes clean routing possible.
Note the fallback already deletes a hand-written user `.desktop` today — so
**removal partly works with no new code**, it just leaves the icon and the
AppImage payload behind.

**2. The `omarchy` dispatcher only scans its own directory.**

```bash
OMARCHY_BIN_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
...
for file in "$OMARCHY_BIN_DIR"/omarchy-*; do
```

Routes are derived from the filename stem with dashes turned into spaces, so
`omarchy-appimage-install` would route as `omarchy appimage install` and land in
an `appimage` group. But `$OMARCHY_BIN_DIR` is `/usr/share/omarchy/bin`, **not**
`$PATH` — so the `omarchy appimage install` dispatch form only exists if the
scripts live in that package-owned directory. See "Installing" below.

Commands self-describe with comment metadata the dispatcher parses from the
first 80 lines:

```bash
# omarchy:summary=Create a desktop launcher for a web app
# omarchy:args=[name url icon-url-or-name [custom-exec] [mime-types]]
# omarchy:hidden=true
# omarchy:requires-sudo=true
```

**3. Desktop-entry escaping is not optional.** `omarchy-webapp-install` carries
two escaping helpers with long comments explaining why: a raw newline in a value
would start a new key line and let a name inject a second `Exec=`, and Exec
arguments need the freedesktop quoting rules (`" \` $ \` escaped, literal `%`
doubled). Both are copied verbatim into the reference implementation below.
Don't drop them — the AppImage's *own* bundled desktop file is attacker-ish
input in exactly the same way a pasted URL is.

## Design

Three scripts, mirroring the webapp trio:

| Script | Route (if upstreamed) | Purpose |
|--------|----------------------|---------|
| `omarchy-launch-appimage` | `omarchy launch appimage` | Thin exec wrapper; the routing marker |
| `omarchy-appimage-install` | `omarchy appimage install` | Stage the file, generate the launcher |
| `omarchy-appimage-remove` | `omarchy appimage remove` | Picker + remove launcher, icon, payload |

Conventions taken from the existing scripts:

- Payload lives in `~/Applications/` — matches the old install's muscle memory.
- Icons go to `~/.local/share/icons/hicolor/256x256/apps/`, then `gtk-update-icon-cache`.
- Launchers go to `~/.local/share/applications/<Name>.desktop`, then `update-desktop-database`.
- Interactive prompts use `gum`; the removal picker uses `omarchy-menu-select`.
- Removal honours `OMARCHY_REMOVE_NOTIFY=false` and otherwise calls
  `omarchy-notification-send -g`, so `omarchy-remove-launcher-entry` can
  suppress the duplicate toast the way it does for webapps and TUIs.
- Launching uses `exec setsid uwsm-app -- ...`, same as `omarchy-launch-webapp`.

**The one improvement over the webapp/tui scripts:** both of those have to ask
the user for an icon URL, because a URL or a shell command carries no metadata.
An AppImage does — `--appimage-extract` yields a `squashfs-root/` containing the
app's own `.desktop` and `.DirIcon`. So the install command can read `Name`,
`Icon`, `Categories` and `StartupWMClass` straight out of the bundle and prompt
for nothing but confirmation. Carrying `StartupWMClass` through matters on
Hyprland — it's what lets window rules and `omarchy launch or focus` match the
window.

## Reference implementation

### `omarchy-launch-appimage`

```bash
#!/bin/bash

# omarchy:summary=Launch an installed AppImage
# omarchy:args=<path-to-appimage> [args...]

set -e

APPIMAGE="${1-}"
shift || true

if [[ -z $APPIMAGE ]]; then
  echo "Usage: omarchy-launch-appimage <path-to-appimage> [args...]" >&2
  exit 1
fi

if [[ ! -x $APPIMAGE ]]; then
  omarchy-notification-send -g "AppImage missing" "$APPIMAGE"
  exit 1
fi

exec setsid uwsm-app -- "$APPIMAGE" "$@"
```

### `omarchy-appimage-install`

```bash
#!/bin/bash

# omarchy:summary=Install an AppImage and create a desktop launcher
# omarchy:args=[path-or-url] [name]

set -e

APPIMAGE_DIR="$HOME/Applications"
ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
DESKTOP_DIR="$HOME/.local/share/applications"

# --- helpers copied verbatim from omarchy-webapp-install ---

safe_icon_name() {
  printf '%s\n' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^[:alnum:]]\+/-/g; s/^-//; s/-$//'
}

require_plain_name() {
  # The name becomes a filename; a slash would put the launcher somewhere the
  # remove command cannot address.
  if [[ $1 == */* ]]; then
    echo "App name cannot contain '/': $1" >&2
    exit 1
  fi
}

desktop_string_escape() {
  # A raw newline would start a new key line and let a value inject a second Exec=.
  local value="$1"
  value=${value//\\/\\\\}
  value=${value//$'\t'/\\t}
  value=${value//$'\r'/\\r}
  value=${value//$'\n'/\\n}
  if [[ $value == " "* ]]; then
    value="\\s${value# }"
  fi
  printf '%s' "$value"
}

desktop_exec_arg() {
  # One double-quoted Exec argument per the freedesktop Exec spec.
  local escaped
  escaped=$(printf '%s' "$1" \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/`/\\`/g' -e 's/\$/\\$/g' -e 's/%/%%/g')
  printf '"%s"' "$escaped"
}

# --- preflight ---

if ! ldconfig -p 2>/dev/null | grep -q 'libfuse\.so\.2'; then
  echo -e "\e[33mWarning:\e[0m libfuse.so.2 is missing; most AppImages will not start."
  echo "         Install it with: omarchy pkg add fuse2"
fi

# --- input ---

if (( $# == 0 )); then
  echo -e "\e[32mLet's install an AppImage you can start with the app launcher.\n\e[0m"
  SOURCE=$(gum input --prompt "AppImage path or URL> " \
    --placeholder "~/Downloads/Foo.AppImage or https://example.com/Foo.AppImage")
  APP_NAME=""
  INTERACTIVE=true
else
  SOURCE="$1"
  APP_NAME="${2-}"
  INTERACTIVE=false
fi

if [[ -z $SOURCE ]]; then
  echo "You must provide an AppImage path or URL." >&2
  exit 1
fi

mkdir -p "$APPIMAGE_DIR" "$ICON_DIR" "$DESKTOP_DIR"

# --- fetch or stage the payload ---

if [[ $SOURCE =~ ^https?:// ]]; then
  FILENAME=$(basename "${SOURCE%%\?*}")
  [[ $FILENAME == *.AppImage ]] || FILENAME="$FILENAME.AppImage"
  TARGET="$APPIMAGE_DIR/$FILENAME"
  echo "Downloading $FILENAME..."
  curl -fL --progress-bar -o "$TARGET" "$SOURCE"
else
  SOURCE="${SOURCE/#\~/$HOME}"
  if [[ ! -f $SOURCE ]]; then
    echo "No such file: $SOURCE" >&2
    exit 1
  fi
  TARGET="$APPIMAGE_DIR/$(basename "$SOURCE")"
  if [[ $SOURCE != "$TARGET" ]]; then
    mv "$SOURCE" "$TARGET"
  fi
fi

chmod +x "$TARGET"

# --- read the AppImage's own metadata ---
#
# Full extract rather than a targeted --appimage-extract '<pattern>': .DirIcon is
# usually a symlink into usr/share/icons, so a pattern extract leaves it dangling.
# Costs a few seconds and roughly the bundle's size in $TMPDIR, then cleans up.
# Type-1 AppImages have no --appimage-extract at all and fall through to defaults.

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

BUNDLED_DESKTOP=""
if ( cd "$WORKDIR" && "$TARGET" --appimage-extract >/dev/null 2>&1 ); then
  BUNDLED_DESKTOP=$(find "$WORKDIR/squashfs-root" -maxdepth 1 -name '*.desktop' -type f | head -1)
fi

desktop_value() {
  if [[ -n $BUNDLED_DESKTOP ]]; then
    sed -n "s/^$1=//p" "$BUNDLED_DESKTOP" | head -1
  fi
}

if [[ -z $APP_NAME ]]; then
  APP_NAME=$(desktop_value Name)
fi
if [[ -z $APP_NAME ]]; then
  APP_NAME=$(basename "$TARGET" .AppImage)
fi
if [[ $INTERACTIVE == true ]]; then
  APP_NAME=$(gum input --prompt "Name> " --value "$APP_NAME")
fi

require_plain_name "$APP_NAME"

CATEGORIES=$(desktop_value Categories)
WM_CLASS=$(desktop_value StartupWMClass)
ICON_KEY=$(desktop_value Icon)

# --- icon ---

ICON_VALUE=$(safe_icon_name "$APP_NAME")
ICON_SRC=""

if [[ -d $WORKDIR/squashfs-root ]]; then
  if [[ -n $ICON_KEY ]]; then
    # Biggest matching PNG wins; file size is a good enough proxy for resolution.
    ICON_SRC=$(find "$WORKDIR/squashfs-root" -name "$ICON_KEY.png" -type f -printf '%s %p\n' 2>/dev/null \
      | sort -rn | head -1 | cut -d' ' -f2-)
  fi
  if [[ -z $ICON_SRC && -e $WORKDIR/squashfs-root/.DirIcon ]]; then
    ICON_SRC=$(readlink -f "$WORKDIR/squashfs-root/.DirIcon")
  fi
fi

if [[ -n $ICON_SRC && -f $ICON_SRC ]]; then
  EXT="${ICON_SRC##*.}"
  [[ $EXT == "$ICON_SRC" ]] && EXT="png"
  cp "$ICON_SRC" "$ICON_DIR/$ICON_VALUE.$EXT"
  gtk-update-icon-cache "$HOME/.local/share/icons/hicolor" &>/dev/null || true
else
  echo "No icon found inside the bundle; falling back to a generic one."
  ICON_VALUE="application-x-executable"
fi

# --- launcher ---

DESKTOP_FILE="$DESKTOP_DIR/$APP_NAME.desktop"
EXEC_COMMAND="omarchy-launch-appimage $(desktop_exec_arg "$TARGET") %U"

cat >"$DESKTOP_FILE" <<EOF
[Desktop Entry]
Version=1.0
Name=$(desktop_string_escape "$APP_NAME")
Comment=$(desktop_string_escape "$APP_NAME")
Exec=$(desktop_string_escape "$EXEC_COMMAND")
Terminal=false
Type=Application
Icon=$(desktop_string_escape "$ICON_VALUE")
StartupNotify=true
EOF

if [[ -n $CATEGORIES ]]; then
  printf 'Categories=%s\n' "$(desktop_string_escape "$CATEGORIES")" >>"$DESKTOP_FILE"
fi
if [[ -n $WM_CLASS ]]; then
  printf 'StartupWMClass=%s\n' "$(desktop_string_escape "$WM_CLASS")" >>"$DESKTOP_FILE"
fi

chmod +x "$DESKTOP_FILE"
update-desktop-database "$DESKTOP_DIR" &>/dev/null || true

echo -e "You can now find $APP_NAME using the app launcher (SUPER + SPACE)\n"
```

### `omarchy-appimage-remove`

```bash
#!/bin/bash

# omarchy:summary=Remove an AppImage desktop launcher
# omarchy:args=[name] [--keep-file]

set -e

ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
DESKTOP_DIR="$HOME/.local/share/applications"

KEEP_FILE=false
ARGS=()
for arg in "$@"; do
  if [[ $arg == "--keep-file" ]]; then
    KEEP_FILE=true
  else
    ARGS+=("$arg")
  fi
done

# Index rather than rebuilding a path from the displayed name, so a launcher
# installed before name validation is still addressable. Same reasoning as
# omarchy-webapp-remove.
APPS=()
APP_PATHS=()
while IFS= read -r -d '' file; do
  if grep -q '^Exec=.*omarchy-launch-appimage' "$file"; then
    APPS+=("$(basename "${file%.desktop}")")
    APP_PATHS+=("$file")
  fi
done < <(find "$DESKTOP_DIR" -name '*.desktop' -print0 2>/dev/null)

path_for_app() {
  local wanted="$1" i
  for i in "${!APPS[@]}"; do
    if [[ ${APPS[$i]} == "$wanted" ]]; then
      printf '%s\n' "${APP_PATHS[$i]}"
      return 0
    fi
  done
}

if (( ${#ARGS[@]} == 0 )); then
  if (( ${#APPS[@]} )); then
    mapfile -t SORTED < <(printf '%s\n' "${APPS[@]}" | sort)
    APP_NAME=$(omarchy-menu-select "Select AppImage to remove" "${SORTED[@]}" -- --width 520 --maxheight 520)
  else
    echo "No AppImages to remove."
    exit 1
  fi
else
  APP_NAME="${ARGS[*]}"
fi

if [[ -z $APP_NAME ]]; then
  echo "You must select an AppImage to remove."
  exit 1
fi

DESKTOP_FILE=$(path_for_app "$APP_NAME")
DESKTOP_FILE="${DESKTOP_FILE:-$DESKTOP_DIR/$APP_NAME.desktop}"

# Recover the payload path from the Exec line. TWO escaping layers went on at
# write time and both have to come off, innermost last:
#
#   1. desktop_exec_arg quoted the path      "  -> \"    $ -> \$    % -> %%
#   2. desktop_string_escape then ran over the whole Exec value and doubled
#      every backslash -- including the ones layer 1 had just added, so \"
#      became \\".
#
# Undoing only layer 1 does not leave a nearly-right path, it leaves a wrong
# one: the \" unescape pairs the SECOND backslash with the quote and consumes
# both, so a stray backslash survives that was never in the filename. The path
# then matches nothing, rm -f exits 0 on it, and the payload is silently left on
# disk while the launcher and icon go away. Within layer 2 and within layer 1,
# backslash goes last, or the earlier unescapes eat its escapes.
PAYLOAD=""
if [[ -f $DESKTOP_FILE ]]; then
  PAYLOAD=$(sed -n 's/^Exec=omarchy-launch-appimage "\(.*\)".*/\1/p' "$DESKTOP_FILE" | head -1)

  # Layer 2: desktop-entry string value.
  [[ $PAYLOAD == "\\s"* ]] && PAYLOAD=" ${PAYLOAD#\\s}"
  PAYLOAD=${PAYLOAD//\\\\/\\}

  # Layer 1: Exec argument quoting.
  PAYLOAD=${PAYLOAD//%%/%}
  PAYLOAD=${PAYLOAD//\\\"/\"}
  PAYLOAD=${PAYLOAD//\\\$/\$}
  PAYLOAD=${PAYLOAD//\\\`/\`}
  PAYLOAD=${PAYLOAD//\\\\/\\}
fi

icon_name=$(printf '%s\n' "$APP_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^[:alnum:]]\+/-/g; s/^-//; s/-$//')

rm -f "$DESKTOP_FILE"
rm -f "$ICON_DIR/$icon_name".*

if [[ $KEEP_FILE == false && -n $PAYLOAD && -f $PAYLOAD ]]; then
  rm -f "$PAYLOAD"
fi

if [[ ${OMARCHY_REMOVE_NOTIFY:-true} != "false" ]]; then
  omarchy-notification-send -g "AppImage removed" "$APP_NAME"
fi

update-desktop-database "$DESKTOP_DIR" &>/dev/null || true
```

## Installing

### Locally (no upstream changes)

Drop the three scripts in `~/.local/bin`, `chmod +x` them, confirm that
directory is on `$PATH`. They then work as `omarchy-appimage-install ...`
directly. **They will not work as `omarchy appimage install`** — the dispatcher
globs its own `/usr/share/omarchy/bin`, not `$PATH`.

Do not "fix" that by copying them into `/usr/share/omarchy/bin`. That directory
is owned by the `omarchy` package and `omarchy update` overwrites it.

Removal via the app launcher's right-click still degrades gracefully without the
upstream patch below: `omarchy-remove-launcher-entry` falls through to its
generic user-`.desktop` branch and deletes the launcher, just leaving the icon
and the `.AppImage` behind. `omarchy-appimage-remove` cleans up all three.

### Upstream (to get the `omarchy appimage ...` routes)

Two small patches beyond adding the scripts to `bin/`:

1. In `omarchy-remove-launcher-entry`, alongside the existing webapp and TUI
   branches:

   ```bash
   if [[ $exec_line =~ omarchy-launch-appimage ]]; then
     OMARCHY_REMOVE_NOTIFY=false omarchy-appimage-remove "$desktop_name"
     exit 0
   fi
   ```

2. In the `omarchy` dispatcher, for `omarchy --help` grouping:

   ```bash
   GROUP_DESCRIPTIONS[appimage]="AppImage installation and launchers"
   ```

   (Absence only means the group prints without a description; it isn't fatal.)

Worth expecting pushback on the PR. Packages-first is fairly load-bearing for
Omarchy, and the counter-argument — "it's in the AUR, use `omarchy pkg add`" —
covers most real cases.

## Known gaps / deferred decisions

- **Self-updating AppImages.** Apps that update in place and rename themselves
  break the hardcoded `Exec` path. Fix if it actually bites: keep the payload
  under its real name and point `Exec` at a stable symlink
  (`~/.local/share/omarchy-appimages/<slug>`), re-pointing the symlink on
  update. Not worth building until an app in daily use actually does it.
- **No update command.** There is no `omarchy appimage update`; re-running
  `install` against a new download replaces the launcher. `AppImageUpdate` /
  embedded zsync info is deliberately out of scope.
- **Type-1 AppImages** have no `--appimage-extract`, so they get the filename as
  the name and a generic icon. Acceptable — they're rare now.
- **SVG icons** land in the `256x256` hicolor directory, which is technically
  the wrong place for a scalable icon. Mirrors what `omarchy-webapp-install`
  already does with `install_user_icon`, so it's consistent rather than correct.
- **`~/Applications` is not XDG.** Chosen to match the old install's layout and
  AppImage convention generally, not because it's the tidiest option.

## Verification checklist

After implementing on the main install:

```bash
# 1. FUSE present
omarchy pkg add fuse2
ldconfig -p | grep libfuse.so.2

# 2. Install from a local file and from an https URL.
#    http is rejected. The digest is checked before the bundle is executed.
omarchy-appimage-install ~/Downloads/Foo.AppImage
omarchy-appimage-install --sha256=<64 lowercase hex> --confirm-exec \
  https://example.com/Bar.AppImage "Bar"

# 3. Launcher is well-formed and the escaping survived
desktop-file-validate ~/.local/share/applications/Foo.desktop
grep Exec= ~/.local/share/applications/Foo.desktop

# 4. Appears and launches from the app launcher (SUPER + SPACE)

# 5. Window matches the class the entry claims
hyprctl clients | grep -i class

# 6. Removal cleans launcher, icon and payload
omarchy-appimage-remove Foo
ls ~/Applications ~/.local/share/icons/hicolor/256x256/apps

# 7. Right-click remove in the app launcher also works (deletes at least the
#    .desktop without the upstream patch; everything with it)
```

Nothing in this spec is hardware-specific, so it transfers to the main install
as-is. The only environment assumption is that `~/.local/bin` is on `$PATH`.
