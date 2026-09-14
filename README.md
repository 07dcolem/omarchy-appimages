# AppImage integration for Omarchy

Gives AppImages the same install / launch / remove treatment Omarchy already
gives web apps and TUIs.

| Command | What it does |
|---------|--------------|
| `omarchy-appimage-install [path-or-url] [name] [--replace]` | Stage the payload, read the bundle's own metadata, write a launcher |
| `omarchy-appimage-remove [name] [--keep-file]` | Remove launcher, icon and payload together |
| `omarchy-launch-appimage <path> [args...]` | Thin exec wrapper; what the launcher's `Exec=` points at |

Run with no arguments, `omarchy-appimage-install` lists the AppImages sitting in
`~/Downloads`, `~/Desktop` and `~`, newest first — type to narrow, Enter to pick.
Choose "Enter a path or URL..." (or press Esc) to type one instead, which is also
how you install from a URL. The name, comment, icon,
categories, `StartupWMClass` and `MimeType` all come out of the AppImage itself, so
unlike the web app and TUI installers it never asks you for an icon URL.

## Upgrading

Installing an app that is already installed asks whether to replace it, naming
both versions when the bundles declare `X-AppImage-Version`:

    Replace the installed "Ledger Wallet" 4.17.1 with 4.19.0?

Answering yes repoints the launcher and **deletes the previous payload**, which
matters because a new version usually ships under a different filename — without
that, the old one is orphaned in `~/Applications` forever.

Non-interactively the collision is refused unless you pass `--replace`, so a
script never silently overwrites an installed app.

## Prerequisite: FUSE 2

Omarchy does not install `fuse2`, and type-2 AppImages — essentially all of them —
need it:

```bash
omarchy pkg add fuse2
```

Install still works without it and writes a valid launcher; the app just will not
start until FUSE is present. The install command warns when `libfuse.so.2` is
missing.

## Install

```bash
make install
```

Symlinks the three scripts into `~/.local/bin` (make sure that is on your `$PATH`)
and adds **Install → AppImage** and **Remove → AppImage** rows to the Omarchy menu.
`make uninstall` reverses both.

The menu rows go into `~/.config/omarchy/extensions/omarchy-menu.jsonc`, which
survives `omarchy update`. They are wrapped in marker comments, so adding and
removing them leaves the rest of that file byte-identical. Use `NO_MENU=1` to skip
the menu entirely, or `BINDIR=` / `MENU_FILE=` to point somewhere else.

Nothing here writes to `/usr/share/omarchy` — that tree is owned by the `omarchy`
package and is overwritten on update. That is also why `omarchy appimage install`
does not work as a dispatcher route: the dispatcher globs its own package-owned
`bin/`, not `$PATH`. See [`upstream/`](upstream/) for the patches that would change
that.

## Where things go

| What | Where |
|------|-------|
| Payload | `~/Applications/` (moved, not copied) |
| Icon | `~/.local/share/icons/hicolor/<size>/apps/`, by the icon's real resolution |
| Launcher | `~/.local/share/applications/<Name>.desktop` |

Installing **moves** the `.AppImage` rather than copying it, so the payload has
exactly one home and removal can delete it unambiguously. The move is reported on
stdout.

## Development

```bash
omarchy pkg add shellcheck shfmt bats
make lint
make test
```

The suite needs neither FUSE nor network access. Fixture AppImages are tiny
compiled ELF stubs — a fake AppImage has to be a real ELF, because the type magic
lives at offset 8, which inside a `#!` script falls in the middle of the
interpreter path. Every test runs against a throwaway `HOME` with a stubbed
`PATH`, and teardown fails the test if anything escaped into the real home
directory.

For the end-to-end checklist against a live system, run `/verify-appimage` in
Claude Code.

## Known gaps

- **Self-updating AppImages** that rename themselves in place break the launcher's
  hardcoded `Exec` path. The fix, if it ever bites, is a stable symlink.
- **No update command.** Re-running install against a new download replaces the
  launcher.
- **Type-1 AppImages** have no `--appimage-extract`, so they get the filename and a
  generic icon.
- **No update command.** `X-AppImage-Version` is recorded and used when replacing
  an install, but nothing checks upstream for a newer build.
- **Menu row ordering** puts the AppImage rows at the bottom of Install and Remove
  rather than beside Web App and TUI. User-added ids are appended after all default
  ids and cannot be reordered from the extension file.
