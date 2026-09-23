# Plan: Omarchy AppImage Integration Scripts

## Context

Omarchy has first-class launcher generation for web apps and TUIs but nothing for
AppImages, leaving vendor-only builds and betas with no install/launch/remove path.
This builds the missing third trio as standalone Bash scripts installable to
`~/.local/bin`, with a test harness that runs without FUSE or network so the work
stays maintainable and credible as an upstream PR.

## Decisions taken to unblock implementation

The spec leaves several questions open. Build against these; revisit only if a
real app breaks them.

- **`Exec` points at the real payload filename**, not a stable symlink. The
  self-updater problem is deferred until an app in daily use actually renames
  itself.
- **App name collision** (a launcher of that name already exists): refuse with a
  message suggesting an explicit name argument. Silent overwrite orphans the
  previous payload.
- **Payload filename collision**: if the colliding file in `~/Applications/` is
  referenced by an existing AppImage launcher, refuse and point at
  `omarchy-appimage-remove`; if unreferenced, overwrite it.
- **`make install` does write the menu rows**, using marker-delimited idempotent
  blocks, with a `NO_MENU=1` escape for users who prefer to paste them by hand.
- **`--keep-file` stays a flag.** The picker does not gain a keep-or-delete prompt.

## Architectural constraint discovered in the source

`/usr/share/omarchy/bin` has **no shared shell library**. `omarchy-webapp-install`
and `omarchy-tui-install` each carry their own verbatim copy of `safe_icon_name`.
Do not factor the escaping and icon helpers into a sourced `lib/` file — each
script must be self-contained and runnable from `$PATH` alone, or it is not
upstreamable. Duplication between the three scripts is correct here.

## Files to Create

| File | Purpose |
|------|---------|
| `bin/omarchy-launch-appimage` | Exec wrapper; the `Exec=` routing marker |
| `bin/omarchy-appimage-install` | Stage payload, read bundle metadata, write launcher |
| `bin/omarchy-appimage-remove` | Index launchers, pick, remove launcher + icon + payload |
| `menu/appimage-rows.jsonc` | The two menu rows, wrapped in begin/end markers |
| `Makefile` | `lint` `format` `test` `install` `uninstall` targets |
| `tests/helpers/harness.bash` | Temp `HOME`, stub `PATH`, per-test setup and teardown |
| `tests/helpers/fixtures.bash` | Generates fake AppImages with chosen metadata and magic bytes |
| `tests/helpers/stubs/` | Fakes for `gum`, `curl`, `omarchy-menu-select`, `omarchy-notification-send`, `gtk-update-icon-cache`, `update-desktop-database` |
| `tests/launch.bats` | Launch wrapper cases |
| `tests/install.bats` | Install cases, including escaping and cross-filesystem |
| `tests/remove.bats` | Removal, `--keep-file`, round-trip, notification suppression |
| `tests/menu.bats` | Menu row merge, idempotency, byte-identical uninstall |
| `tests/lint.bats` | `shellcheck` and `shfmt -d` gate |
| `upstream/0001-route-appimage-removal.patch` | Documented diff for `omarchy-remove-launcher-entry` |
| `upstream/0002-appimage-group-description.patch` | Documented diff for the `omarchy` dispatcher |
| `upstream/README.md` | What each patch does and why it is not auto-applied |
| `.github/workflows/ci.yml` | `make lint test` on an `archlinux:base-devel` container |
| `README.md` | Install, usage, and the `fuse2` prerequisite |

## Files to Modify

| File | Change |
|------|--------|
| `~/.config/omarchy/extensions/omarchy-menu.jsonc` | Written at runtime by `make install`, not by the repo. Marker-delimited block appended; everything else left untouched |

The repo is new, so there is nothing else to modify. `docs/development.md` records
the conventions this plan follows.

## Implementation Steps

### 1. Scaffold the repo and Makefile

Create `bin/`, `tests/helpers/stubs/`, `menu/`, `upstream/`. Write the `Makefile`
with the five targets. `lint` runs `shellcheck` then `shfmt -d -i 2` over `bin/*`;
`format` runs `shfmt -w -i 2`; `test` runs `bats tests/`. Each target must fail
loudly with an install hint when its tool is missing, rather than reporting a
false pass. Leave `install` and `uninstall` as stubs until step 8.

### 2. Write `bin/omarchy-launch-appimage`

The smallest script and a dependency of everything else, since its name is the
string the launcher and the remove command both key on. Follow the header shape of
`/usr/share/omarchy/bin/omarchy-launch-webapp`: shebang, blank line,
`omarchy:summary` and `omarchy:args` comments, blank line. Take the payload as
`$1`, shift, validate presence and executability, notify via
`omarchy-notification-send -g` and exit non-zero on failure, then
`exec setsid uwsm-app --` with the payload and remaining arguments.

### 3. Build the test harness before the larger scripts

`tests/helpers/harness.bash` provides setup that points `HOME` at a `bats`-provided
temp dir, creates `Applications`, `.local/share/applications` and the hicolor icon
path inside it, and prepends `tests/helpers/stubs/` plus the repo `bin/` to `PATH`.
Teardown removes the temp tree. Each stub records its invocation to a log file
under the temp `HOME` so tests can assert a notification was or was not sent, and
the `curl` stub copies a fixture instead of reaching the network. Add an assertion
in teardown that the real `~/Applications` was never created.

`tests/helpers/fixtures.bash` generates fake AppImages: an executable script whose
first bytes are patched to carry the right magic at offset 8, which materialises a
`squashfs-root/` containing a chosen `.desktop` and icon when invoked with
`--appimage-extract`, and logs the call when invoked with no arguments. Parameterise
it over name, categories, `StartupWMClass`, icon presence, and type-1 versus
type-2, so every install test builds the bundle it needs from one generator.

### 4. Write `bin/omarchy-appimage-install` — validation and staging

Copy `safe_icon_name`, `require_plain_name`, `desktop_string_escape` and
`desktop_exec_arg` verbatim from `omarchy-webapp-install`, including their
comments. Then, in order: warn when `ldconfig -p` shows no `libfuse.so.2` and
continue; resolve arguments into source and optional name across the zero/one/two
argument forms, prompting with `gum` only in the zero-argument case; expand a
leading `~`; branch on `http`/`https` versus local path.

For a URL, strip the query string, append `.AppImage` when the basename lacks it,
and download with `curl -fL --progress-bar` to a temporary name inside
`~/Applications/`. For a local path, verify existence, then read the magic bytes at
offset 8 and reject anything that is not `41 49 01` or `41 49 02` before touching
the filesystem. Stage through a temporary name in `~/Applications/` and rename into
place so an interrupted transfer never lands at the final path; skip the move
entirely when source and target resolve to the same file. Apply the payload
collision rule from the decisions section. Report the move on stdout, then
`chmod +x`.

### 5. Finish install — metadata, icon, launcher

Only for type-2, extract with `--appimage-extract` into a temp directory created
under a disk-backed base (derive it from `~/.cache`, not `$TMPDIR`, since `/tmp` is
tmpfs on Omarchy) and register a trap that removes it on any exit. Take the first
top-level `.desktop` deterministically. Resolve the name as explicit argument, then
bundled `Name`, then payload basename; offer it as an editable `gum` default in
interactive mode; run `require_plain_name`; apply the name collision rule.

Pull `Categories`, `StartupWMClass` and `Icon` from the bundle. Select the icon as
the largest file matching the `Icon` key, then `.DirIcon` resolved through
`readlink -f`, then the `application-x-executable` fallback with a printed notice.
Install it the way `install_user_icon` in `omarchy-webapp-install` does, then
refresh the icon cache tolerantly.

Write the launcher with every value through `desktop_string_escape` and the payload
through `desktop_exec_arg`, `Exec` beginning with `omarchy-launch-appimage`. Append
`Categories` and `StartupWMClass` only when non-empty. `chmod +x` the launcher,
refresh the desktop database tolerantly, print the app-launcher hint.

### 6. Write `bin/omarchy-appimage-remove`

Follow the indexing pattern in `omarchy-webapp-remove`: two parallel arrays built
from a `find -print0` loop filtered by an `Exec=` grep for the routing marker, plus
a lookup that maps a chosen name back to its indexed path. Declare both arrays
explicitly — the upstream script declares only one and relies on `set -u` being
off. Parse `--keep-file` out of the arguments positionally so it may appear before
or after the name. With no name, sort and present through `omarchy-menu-select`
with the same width arguments the webapp version uses; exit non-zero with a message
when the index is empty.

Recover the payload path from the `Exec` line by reversing **both** layers install
applies. Undo the desktop-entry string escaping first (it doubled every backslash,
including those the Exec quoting added), then the Exec argument quoting: the
doubled `%`, then `"`, `$` and backtick, unescaping backslash **last** within each
layer.
Remove launcher and icon unconditionally, payload unless `--keep-file`, tolerating
an already-missing payload. Send the notification unless `OMARCHY_REMOVE_NOTIFY` is
`false`, then refresh the desktop database.

### 7. Write the tests

Implement `tests/launch.bats`, `tests/install.bats`, `tests/remove.bats` and
`tests/lint.bats` against the case lists in the spec's Testing guidelines. Two
deserve care: the shell-metacharacter case must round-trip a payload path
containing `"`, `$`, backtick and `%` through install and back out through remove
and assert the payload is actually deleted, since that is the failure the escaping
exists to prevent; and the cross-filesystem case should point the source at a
separate temp directory and additionally assert that a transfer killed partway
leaves nothing at the final path.

### 8. Menu rows and the `install` / `uninstall` targets

Write `menu/appimage-rows.jsonc` containing the `install.appimage` and
`remove.appimage` rows with `appimage` aliases, wrapped in begin and end marker
comments. Model the rows on `install.webapp` and `remove.webapp` at lines 190 and
281 of `/usr/share/omarchy/default/omarchy/omarchy-menu.jsonc`: install goes
through `omarchy-launch-floating-terminal-with-presentation`, remove is called
directly and carries a `when:` grep guard for the routing marker.

`make install` symlinks the three scripts into `~/.local/bin` and, unless
`NO_MENU=1`, appends the marker block to the user extension file when its markers
are not already present — creating the file only if absent. `make uninstall`
removes the symlinks and deletes the marker block, leaving surrounding content
byte-identical. Neither target may write anywhere under `/usr/share/omarchy`. Then
write `tests/menu.bats` against these targets.

### 9. Record the upstream patches

Generate the two diffs against the installed sources and commit them under
`upstream/` without applying them. The routing branch goes in
`omarchy-remove-launcher-entry` immediately after the existing TUI branch and
before the `is_user_desktop_file` fallback, matching the shape of the webapp and
TUI branches. The group description goes in the `omarchy` dispatcher's
`GROUP_DESCRIPTIONS` block, alphabetically between `agent` and `audio`. Document in
`upstream/README.md` that removal degrades gracefully without the first patch — the
generic fallback deletes the launcher and leaves icon and payload behind.

### 10. CI and README

Add the GitHub Actions workflow running `make lint test` in an
`archlinux:base-devel` container with `shellcheck`, `shfmt`, `bats` and
`desktop-file-utils` installed. Write the `README.md` covering the `fuse2`
prerequisite, `make install`, the three commands, and the note that
`omarchy appimage ...` dispatcher routes require upstreaming.

## Verification

Automated, from the repo root:

- `make lint` — `shellcheck` and `shfmt -d -i 2` clean across `bin/*`.
- `make test` — the full `bats` suite. Confirm it passes with FUSE absent and with
  the network unreachable; neither should matter.
- Confirm no test created a real `~/Applications` or touched the real icon cache.

Manual, on the live system, after `make install`:

- Run `/verify-appimage` — the project skill walks the full end-to-end checklist:
  install from a path and a URL, `desktop-file-validate` the launcher, inspect the
  `Exec` line, check the window class against `hyprctl clients`, exercise removal
  with and without `--keep-file`, and confirm right-click removal from the app
  launcher behaves as documented.
- Use the 991 MB `~/Downloads/LM-Studio-0.3.8-4-x64.AppImage` as the large-bundle
  subject and watch memory during extraction to confirm the disk-backed temp
  directory is in use.
- Open the Omarchy menu and confirm Install > AppImage appears, that Remove >
  AppImage is hidden until something is installed, and that `omarchy menu summon
  install.appimage` routes correctly.
- Run `make uninstall` and confirm the menu extension file is byte-identical to its
  pre-install state.
