# Spec for omarchy-appimage-scripts

branch: claude/feature/omarchy-appimage-scripts

## Summary

Build three shell commands that give AppImages the same install / launch / remove
treatment Omarchy already gives web apps and TUIs, plus the packaging, linting and
test harness needed to develop and maintain them outside the Omarchy package tree.

- `omarchy-launch-appimage` — thin exec wrapper around a staged `.AppImage`. Its
  name on the `Exec=` line is the routing marker that lets Omarchy's existing
  `omarchy-remove-launcher-entry` dispatch removals back to our remove command.
- `omarchy-appimage-install` — accepts a local path or an HTTPS URL, stages the
  payload in `~/Applications/`, reads `Name` / `Icon` / `Categories` /
  `StartupWMClass` out of the bundle's own desktop entry, installs the icon, and
  writes a `.desktop` launcher.
- `omarchy-appimage-remove` — indexes launchers that carry the routing marker,
  offers a picker, and removes launcher, icon and payload together.

The design mirrors the existing `omarchy-webapp-*` trio deliberately; the one
behavioural improvement is that an AppImage carries its own metadata, so install
prompts for confirmation only rather than asking the user for an icon URL.

Full background, the reference implementation, and the reasoning behind each
convention live in `appimage-integration-spec.md` at the repo root. This spec
covers what to build and how to verify it, not how to write it.

Default install target is `~/.local/bin` (works as `omarchy-appimage-install ...`).
The `omarchy appimage ...` dispatcher routes only exist if the scripts live in
`/usr/share/omarchy/bin`, which is package-owned and overwritten by
`omarchy update` — so upstreaming is a separate, optional track.

## Recommended toolset

**Language: Bash 5 + coreutils. Nothing else.** This is not a default-by-inertia
choice — three things make it the only sensible one:

- Every script in `/usr/share/omarchy/bin` is Bash. A Rust or Go binary would not
  be mergeable upstream, and upstreaming is the only path to the
  `omarchy appimage ...` routes.
- The dispatcher discovers commands by globbing `omarchy-*` files and parsing
  `# omarchy:summary=` / `# omarchy:args=` comments out of the first 80 lines of
  each. A compiled binary cannot self-describe that way.
- Runtime dependencies are already present on a stock Omarchy box: `gum`, `curl`,
  `find`, `sed`, `gtk-update-icon-cache`, `update-desktop-database`,
  `omarchy-menu-select`, `omarchy-notification-send`. No build step, no install
  step beyond `chmod +x`.

Development tooling to add on top (all in the Arch `extra` repo):

| Tool | Version seen | Role |
|------|--------------|------|
| `shellcheck` | 0.11.0 | Lint. Non-negotiable given how much of this spec is quoting and escaping. |
| `shfmt` | 3.13.1 | Format. Match Omarchy's house style (2-space indent) so a future PR diff is clean. |
| `bats` | 1.14.0 | Test runner. Bash-native, no helper libraries needed. |
| `desktop-file-validate` | installed | Validate every generated launcher, in tests and in the manual checklist. |
| `jq` | installed | Menu extension rows are JSONC; useful for validating generated blocks in tests. |

Plus a `Makefile` with `lint`, `format`, `test`, `install` and `uninstall`
targets — make over `just`, only because `make` is already on the box and one
less dependency matters for a three-script project.

**The load-bearing test decision: do not test against real AppImages.** A real
type-2 AppImage needs FUSE, which Omarchy does not install by default and CI
containers cannot easily provide. Instead, generate fixture executables — small
scripts that respond to `--appimage-extract` by materialising a `squashfs-root/`
with a chosen desktop entry and icon, and to no arguments by recording that they
were launched. Everything the install command reads out of a bundle goes through
that one interface, so the fixtures exercise the real code path. Add a small
separate tier of optional tests, skipped unless FUSE is present, that run one
genuine AppImage end to end.

The same applies to the environment: tests point `HOME` at a temp directory and
prepend a stub directory to `PATH` holding fakes for `gum`, `omarchy-menu-select`,
`omarchy-notification-send`, `gtk-update-icon-cache`, `update-desktop-database`
and `curl`. No test may touch the real `~/Applications`, the real icon cache, or
the network.

CI, if wanted: GitHub Actions on an `archlinux:base-devel` container, installing
the four tools above and running `make lint test`. Optional for a personal repo,
cheap to add, and it is the thing that makes the upstream PR credible.

## Functional Requirements

**`omarchy-launch-appimage`**

- Takes a payload path as the first argument and forwards any remaining arguments
  to the AppImage.
- Errors with usage text and a non-zero exit when called with no argument.
- When the payload is missing or not executable, sends a desktop notification
  naming the path and exits non-zero, rather than failing silently from a launcher.
- Launches via `exec setsid uwsm-app --`, matching `omarchy-launch-webapp`, so the
  process detaches from the launcher and is placed correctly by the compositor.
- Carries `omarchy:summary` and `omarchy:args` metadata comments.

**`omarchy-appimage-install`**

- Accepts zero arguments (fully interactive via `gum`), one argument (source), or
  two (source and explicit name).
- Source may be a local path — with `~` expanded — or an `http`/`https` URL.
- Warns, but does not fail, when `libfuse.so.2` is absent, pointing at
  `omarchy pkg add fuse2`. The launcher it writes is valid either way.
- Downloads URLs to `~/Applications/`, appending `.AppImage` when the URL's
  basename lacks it, after stripping any query string.
- **Moves** local files into `~/Applications/` rather than copying them, so the
  payload has exactly one home and removal can delete it unambiguously. A move is
  a no-op when the source is already the target.
- When source and target share a filesystem — the common case, since `~/Downloads`
  and `~/Applications` are both under `$HOME` — the move is a rename: atomic and
  instant regardless of size. When they do not (a download in `/tmp`, an external
  drive), `mv` degrades to copy-then-unlink, which is neither. Stage those through
  a temporary name inside `~/Applications/` and rename into place, so an
  interrupted install never leaves a partial payload at the final path.
- Reports the move on stdout, naming source and destination. Relocating a file the
  user just downloaded is a surprise unless it is stated.
- Detects AppImage type from the magic bytes at offset 8 (`41 49 01` for type-1,
  `41 49 02` for type-2) rather than by attempting extraction and interpreting
  failure. A non-AppImage file is rejected before anything is moved or written.
- Extracts into a disk-backed temporary directory, not the default `/tmp`. On a
  stock Omarchy box `/tmp` is tmpfs, so extracting a large bundle spends its
  uncompressed size in RAM.
- Marks the payload executable.
- Extracts the bundle to a temp directory to read its own desktop entry. Full
  extract, not a pattern extract — `.DirIcon` is typically a symlink into
  `usr/share/icons` and a pattern extract leaves it dangling. Temp directory is
  removed on exit, including on failure.
- Resolves the app name in priority order: explicit argument, bundled `Name`,
  payload basename without extension. In interactive mode the resolved value is
  offered as an editable default.
- Rejects any name containing `/`, since the name becomes a filename the remove
  command must be able to address.
- Carries `Categories` and `StartupWMClass` through from the bundle when present,
  omitting the keys entirely when absent. `StartupWMClass` is what lets Hyprland
  window rules and `omarchy launch or focus` match the window.
- Installs the largest icon matching the bundle's `Icon` key into
  `~/.local/share/icons/hicolor/256x256/apps/`, falling back to `.DirIcon`, then
  to the generic `application-x-executable`, announcing the fallback.
- Escapes every value written into the launcher: desktop-entry string escaping on
  all values, and freedesktop `Exec` quoting on the payload path. The bundle's own
  desktop file is untrusted input in exactly the way a pasted URL is.
- Refreshes the icon cache and the desktop database, tolerating failure of either.
- Writes the launcher to `~/.local/share/applications/<Name>.desktop`, executable.
- Tells the user the app is now reachable from the app launcher.

**`omarchy-appimage-remove`**

- Accepts an optional name and an optional `--keep-file` flag, in any order.
- Builds its candidate list by scanning user launchers for an `Exec=` line
  containing `omarchy-launch-appimage`, keeping name and path side by side rather
  than reconstructing the path from the displayed name — so a launcher installed
  before name validation existed is still removable.
- With no name argument, presents the sorted list through `omarchy-menu-select`;
  exits with a message when there is nothing to remove.
- Recovers the payload path by reversing **both** escaping layers install applies,
  outermost first: the desktop-entry string escaping (which doubled every
  backslash, including the ones the Exec quoting had just added), then the Exec
  argument quoting. Backslash goes last within each layer. Undoing only the Exec
  layer does not leave a nearly-right path — the `\"` unescape pairs the second
  backslash with the quote, so a stray backslash survives and the path matches
  nothing.
- Removes launcher, icon and payload; `--keep-file` preserves the payload only.
- Honours `OMARCHY_REMOVE_NOTIFY=false` and otherwise sends a notification, so the
  upstream launcher-entry hook can suppress a duplicate toast.
- Refreshes the desktop database.

**Menu integration**

The Omarchy menu is the Quickshell `omarchy.menu` plugin, built from two JSONC
files: the package-owned default at
`/usr/share/omarchy/default/omarchy/omarchy-menu.jsonc`, and a user extension at
`~/.config/omarchy/extensions/omarchy-menu.jsonc`. The user file is the
integration point — it survives `omarchy update`; the default file does not.
Both are watched, so edits apply without restarting the shell, and
`omarchy menu refresh` forces a re-parse.

- Ship an `install.appimage` row that runs the install command through
  `omarchy-launch-floating-terminal-with-presentation`, exactly as `install.webapp`
  and `install.tui` do — the command is interactive `gum`, so it needs a terminal.
- Ship a `remove.appimage` row that calls `omarchy-appimage-remove` directly (its
  picker is `omarchy-menu-select`, not a TUI), guarded by a `when:` condition that
  greps user launchers for the `omarchy-launch-appimage` marker. The row stays
  hidden until at least one AppImage is installed, mirroring `remove.webapp`.
- Parents are inferred from the dotted id, so `install.appimage` needs no other
  declaration to appear under Install.
- Give both rows an `appimage` alias so they are reachable by menu search and by
  `omarchy menu summon install.appimage`.
- `make install` merges the two rows into the user extension file and
  `make uninstall` removes them, in both cases leaving any other rows in that file
  untouched. The file is JSONC with comments, so a parse-and-rewrite round trip
  would destroy the user's own content — use delimited block markers instead.

**Repo-level**

- `make install` symlinks or copies the three scripts into `~/.local/bin`;
  `make uninstall` reverses it. Neither writes to `/usr/share/omarchy`.
- The two upstream patches (a routing branch in `omarchy-remove-launcher-entry`
  and a group description in the `omarchy` dispatcher) are kept in the repo as
  documented diffs, not applied automatically.

## Possible edge cases

- **No FUSE.** The most likely first-run failure. Install must warn and continue;
  launch will fail with the dlopen error until `fuse2` is added.
- **Type-1 AppImages** have no `--appimage-extract`. Extraction fails, metadata is
  empty, and install must fall through to the filename and a generic icon rather
  than aborting.
- **A bundle with no desktop entry**, or one with several at the top level. Take
  the first deterministically; do not fail.
- **Hostile metadata.** A bundled `Name` containing a newline could inject a second
  `Exec=` line. A payload path containing `"`, `$`, `` ` ``, `\` or `%` must survive
  the write/read round trip — an unescape that misses a character, **or misses one
  of the two escaping layers**, silently leaves the payload on disk at removal
  time. `rm -f` exits 0 on a path that does not exist, so the failure is invisible:
  removal reports success and orphans the payload.
- **Name collisions.** Installing two AppImages that both call themselves the same
  thing overwrites the first launcher and orphans its payload.
- **Payload filename collisions.** A file of the same basename already sitting in
  `~/Applications/` — most likely the same app at a different version — is
  silently overwritten by the move, breaking any launcher pointing at it.
- **Large bundles on tmpfs.** A ~1 GB AppImage extracted under a tmpfs `/tmp`
  consumes its uncompressed size in RAM, which on a smaller machine is a hang
  rather than an error.
- **Re-running install against an already-installed source path** fails with "no
  such file", because the first run moved it. Correct, but the message should not
  be mystifying.
- **A source the user cannot move** — a read-only mount, or a file owned by
  another user — where the copy succeeds but the unlink does not.
- **Interrupted download.** A partial file left in `~/Applications/` and marked
  executable, with a launcher pointing at it.
- **Source already in `~/Applications/`.** The move must not delete the file.
- **URL with a query string or no `.AppImage` suffix**, and URLs that redirect to a
  differently named file.
- **Self-updating AppImages** that rename themselves in place, breaking the
  hardcoded `Exec` path. Out of scope for this build; see Open questions.
- **Icon sizing.** Icons are filed under the hicolor directory matching their real
  resolution (SVG under `scalable/`), so removal has to sweep every size directory
  rather than assuming `256x256`. An unrecognised or non-square size falls back to
  `256x256`.
- **Removal of a launcher whose payload is already gone** must still clean the
  launcher and icon.
- **A very large bundle** makes full extraction slow and consumes roughly its own
  size in `$TMPDIR`; the temp directory must be cleaned up even when install fails
  partway.
- **Menu row ordering.** User-added ids are appended after every default id, and
  re-declaring an existing id merges its fields without moving it. The AppImage
  rows therefore land at the bottom of the Install and Remove submenus rather than
  beside Web App and TUI, and that cannot be corrected from the extension file.
  Cosmetic; only upstreaming fixes it.
- **A user who already has an `omarchy-menu.jsonc` extension.** The install must
  merge into it, never overwrite it, and must be idempotent across re-runs.
- **Right-click remove from the app launcher without the upstream patch** deletes
  the `.desktop` via Omarchy's generic fallback and leaves icon and payload behind.
  This is accepted, documented behaviour, not a bug to work around.

## Acceptance Criteria

- Installing from a local path and from a URL both produce a launcher that appears
  in the app launcher under the app's own name and icon.
- After a local-path install the payload exists only in `~/Applications/`, with no
  copy left at the source, and the move is reported on stdout.
- A cross-filesystem install interrupted partway leaves no file at the final
  payload path.
- A file that is not an AppImage is rejected before it is moved or any launcher is
  written.
- Installing the 991 MB type-2 bundle already in `~/Downloads` does not spend its
  uncompressed size in RAM.
- `desktop-file-validate` passes on every generated launcher, including ones built
  from bundles with quotes, spaces or `%` in the name or path.
- The generated `Exec` line begins with `omarchy-launch-appimage` and quotes the
  payload path.
- `StartupWMClass` from the bundle appears in the launcher, and the running
  window's class matches it under `hyprctl clients`.
- A bundle whose `Name` contains a newline produces a single-line `Name=` key and
  exactly one `Exec=` key.
- `omarchy-appimage-remove <name>` leaves no launcher, no icon and no payload;
  with `--keep-file` the payload survives and nothing else does.
- A payload path containing `"`, `$`, `` ` `` and `%` is recovered exactly and
  deleted on removal.
- The remove picker lists only AppImage launchers, never web apps or TUIs.
- `OMARCHY_REMOVE_NOTIFY=false` suppresses the notification; the default sends one.
- Install on a box without `libfuse.so.2` prints the warning, exits zero, and
  writes a valid launcher.
- A type-1 bundle installs with the filename as its name and the generic icon, and
  exits zero.
- An Install > AppImage row appears in the Omarchy menu and opens the interactive
  install in a floating terminal.
- The Remove > AppImage row is hidden with no AppImages installed and appears once
  one is.
- `omarchy menu summon install.appimage` opens the menu at that row, and searching
  "appimage" finds both rows.
- `make uninstall` removes both rows and leaves any pre-existing user rows in
  `~/.config/omarchy/extensions/omarchy-menu.jsonc` byte-identical.
- `shellcheck` and `shfmt -d` are clean across all three scripts.
- No test run modifies anything outside its temp `HOME`.
- The full verification checklist at the end of `appimage-integration-spec.md`
  passes by hand on the main install.

## Open questions

- **Payload naming and self-updaters.** Point `Exec` at the real filename (simple,
  breaks when an app renames itself on update) or at a stable symlink under
  `~/.local/share/omarchy-appimages/<slug>` (one more moving part, survives
  self-update)? The background doc defers this until an app in daily use actually
  bites. Worth deciding before the first release rather than migrating launchers
  later.
- **Name collisions.** Overwrite silently, refuse, or prompt? Nothing in the
  reference implementation handles this today.
- **Download integrity.** No checksum or signature verification is specified.
  Accept, or offer an optional checksum argument?
- **Is `~/Applications` right?** Decided: yes, and the payload is moved there, not
  copied. It is the AppImage ecosystem convention (AppImageLauncher's default,
  and one of the directories `appimaged` watches), it matches the old install, and
  it keeps self-contained binaries somewhere the user can actually see and manage
  them. The XDG-correct alternative, `~/.local/share/omarchy-appimages/`, hides
  them for no practical gain. Leaving payloads in `~/Downloads` was never an
  option: it is a staging area users periodically clear, and a launcher pointing
  into it is a time bomb. Still open only in that changing it later means
  migrating every installed launcher.
- **Overwrite policy for a colliding payload filename.** Overwrite, refuse, or
  version the filename? Interacts with the name-collision question above.
- **Upstream or not.** The PR is worth expecting pushback on — "it's in the AUR,
  use `omarchy pkg add`" covers most real cases. Decide whether to build toward a
  PR (which raises the bar on tests and style) or keep this permanently local.
- **Should `make install` write to the user's menu extension file at all?**
  Editing it automatically is friendlier; printing a snippet to paste is safer for
  a file the user also hand-edits. Idempotent marker-delimited blocks make the
  automatic route defensible, but it is still a write into their config.
- **`--keep-file` discoverability.** Should the interactive picker path offer a
  keep-or-delete choice rather than requiring the flag up front?

## Testing guidelines

Create test files in the `./tests` folder, run with `bats`. Each test runs in a
temp `HOME` with a stub `PATH`; fixture AppImages are generated scripts that fake
`--appimage-extract`, so no test needs FUSE or the network. Keep it to these
cases — enough to cover the parts that actually break, not exhaustive.

`tests/launch.bats`

- No argument prints usage and exits non-zero.
- Missing payload notifies and exits non-zero rather than exiting silently.
- A present payload is invoked with extra arguments forwarded intact.

`tests/install.bats`

- Local path install: payload lands in `~/Applications`, is executable, launcher
  and icon exist, `desktop-file-validate` passes, and nothing remains at the
  source path.
- Installing a file already in `~/Applications` leaves it in place rather than
  deleting it.
- A non-AppImage file (wrong magic bytes) is rejected, exits non-zero, and is not
  moved.
- A cross-filesystem move — source on a different mount, simulated with a bind or
  a separate tmpdir — lands the payload whole, and an interrupted one leaves no
  file at the final path.
- Name, `Categories` and `StartupWMClass` are read from the bundle and appear in
  the launcher; a bundle lacking `Categories` produces no `Categories=` key.
- Explicit name argument overrides the bundled name.
- A bundle with no icon falls back to `application-x-executable`.
- A bundled `Name` containing a newline yields exactly one `Name=` and one `Exec=`.
- A payload path containing `"`, `$`, `` ` `` and `%` produces a launcher that
  validates and an `Exec` line that round-trips.
- A name containing `/` is rejected with a non-zero exit and no files written.
- Type-1 bundle (magic bytes `41 49 01`) installs with the filename and generic
  icon without attempting extraction.
- URL install against a stub `curl`: query string stripped, `.AppImage` appended
  when missing.
- Missing `libfuse.so.2` warns but still exits zero with a valid launcher.
- The temp extraction directory is gone after both a successful and a failed run.

`tests/remove.bats`

- Removes launcher, icon and payload for a named app.
- `--keep-file` keeps the payload and removes the rest, with the flag given both
  before and after the name.
- The payload path round-trips through install and remove for a name with shell
  metacharacters.
- The candidate list excludes a hand-written web app launcher.
- Removing with no AppImages installed exits non-zero with a message.
- A launcher whose payload is already deleted is still fully cleaned up.
- `OMARCHY_REMOVE_NOTIFY=false` sends no notification; unset sends one.

`tests/menu.bats`

- `make install` into an empty extension file produces rows that parse as JSON
  once comments are stripped.
- `make install` into a file that already holds a user row keeps that row and is
  idempotent when run twice.
- `make uninstall` restores the file to byte-identical its pre-install content.
- The `remove.appimage` guard condition is false with no AppImage launchers
  present and true with one.

`tests/lint.bats` (or a `make lint` step in CI)

- `shellcheck` and `shfmt -d` are clean on all three scripts.
