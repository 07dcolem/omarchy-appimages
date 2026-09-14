# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Three Bash commands (`omarchy-launch-appimage`, `omarchy-appimage-install`,
`omarchy-appimage-remove`) that give AppImages the install/launch/remove treatment
Omarchy already gives web apps and TUIs.

- `bin/` — the three scripts.
- `menu/` — the menu rows, and the marker-based merge tool that installs them.
- `tests/` — the `bats` suite, run via `make test`.
- `upstream/` — the two Omarchy patches, kept as documented diffs, plus the
  security model and the rationale for `X-AppImage-Payload`.
- `appimage-integration-spec.md` — background, discovered Omarchy internals, and
  the reference implementation the scripts were built from. Read this before
  touching them.
- `_specs/omarchy-appimage-scripts.md` — the build spec: requirements, edge cases,
  acceptance criteria, test plan.

The `Makefile` carries `lint` / `format` / `test` / `install` / `uninstall`.

**This is being built toward an upstream Omarchy PR.** House style and the
dispatcher contract below are requirements, not preferences.

## Never write to these paths

- `/usr/share/omarchy/**` is owned by the `omarchy` package and is overwritten by
  `omarchy update`. Never install scripts there, never patch the menu file there.
  Local installs go to `~/.local/bin`.
- Menu rows go in `~/.config/omarchy/extensions/omarchy-menu.jsonc` — the
  user-owned, update-safe extension file. It is JSONC with comments the user
  wrote, so merge into it with delimited markers; never parse-and-rewrite it.

## Bash house style (matches `/usr/share/omarchy/bin`)

- `#!/bin/bash`, blank line, `# omarchy:` metadata comments, blank line, `set -e`.
  Use plain `set -e` — the webapp/tui family does not use `set -euo pipefail`.
- Two-space indent. Line continuations lead with the pipe (`| tr ...`).
- `UPPER_SNAKE` for globals, `lower_snake` for functions.
- The `# omarchy:summary=` and `# omarchy:args=` comments are load-bearing: the
  `omarchy` dispatcher parses them out of the first 80 lines to build routes and
  help text. Do not drop or reformat them.
- `shellcheck` and `shfmt -d` must be clean.

## Correctness rules that are easy to get wrong

- **Bundle metadata is untrusted input.** An AppImage's own `.desktop` file is
  attacker-controlled in exactly the way a pasted URL is. Every value written into
  a launcher goes through desktop-entry string escaping, and the payload path
  through freedesktop `Exec` quoting. A raw newline in a `Name` injects a second
  `Exec=` line. The two escaping helpers in the reference implementation are
  copied verbatim for this reason — do not "simplify" them.
- **Never read the payload path back out of `Exec`.** `Exec` carries it fully
  quoted and escaped because the spec requires that for launching, but recovering
  it means undoing two escaping layers in a fixed order, and getting that wrong
  silently orphans the payload. Removal and collision checks read the dedicated
  `X-AppImage-Payload` key instead, which only ever goes through desktop-entry
  string escaping. Install rejects tab, CR and LF in the path so that reverse
  stays a two-line operation.
- **`Exec=` must start with `omarchy-launch-appimage`.** That name is the routing
  marker Omarchy's `omarchy-remove-launcher-entry` sniffs to dispatch removals.
  Pointing `Exec` straight at the `.AppImage` breaks removal.
- **Detect AppImage type from magic bytes at offset 8** (`41 49 01` type-1,
  `41 49 02` type-2), not by attempting `--appimage-extract` and reading failure.
- **`/tmp` is tmpfs on Omarchy.** Extracting a large bundle there spends its
  uncompressed size in RAM. Extract to a disk-backed temp dir.
- Payloads live in `~/Applications/` (moved, not copied), launchers in
  `~/.local/share/applications/`, icons under `~/.local/share/icons/hicolor/`
  in the size directory matching their real resolution (SVG in `scalable/`,
  unrecognised sizes fall back to `256x256`). Removal must sweep every size
  directory, not just one.

## Testing

- `bats`, run via `make test`.
- **No test may touch the real `$HOME`, the real icon cache, or the network.**
  Point `HOME` at a temp dir and prepend a stub `PATH` with fakes for `gum`,
  `curl`, `omarchy-menu-select`, `omarchy-notification-send`,
  `gtk-update-icon-cache` and `update-desktop-database`.
- **No test may require FUSE.** Fixtures are generated scripts that fake
  `--appimage-extract` by materialising a `squashfs-root/`. Tests against a real
  AppImage are a separate tier, skipped when FUSE is absent.

## Repo conventions

- Feature branches are `claude/feature/<slug>`, created by the `/spec` skill
  alongside a spec file in `_specs/`.
- Keep the two upstream patches described at the end of
  `appimage-integration-spec.md` (the `omarchy-remove-launcher-entry` routing
  branch and the dispatcher group description) current as documented diffs. Do not
  apply them to the system automatically.
