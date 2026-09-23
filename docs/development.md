# Development

Three Bash commands (`omarchy-launch-appimage`, `omarchy-appimage-install`,
`omarchy-appimage-remove`) install, launch, and remove AppImages. The shell
plugin UI is `BarWidget.qml`, `Panel.qml`, and `Model.js`.

- `bin/` — the three scripts.
- `menu/` — the menu rows, and the marker-based merge tool that installs them.
- `tests/` — the `bats` suite, run via `make test`.
- `upstream/` — the two Omarchy patches, kept as documented diffs, plus the
  security model and the rationale for `X-AppImage-Payload`.
- `appimage-integration-spec.md` — background and the reference the scripts
  were built from. Read it before changing install or removal behaviour.
- `_specs/omarchy-appimage-scripts.md` — requirements, edge cases, and the
  test plan.

The `Makefile` carries `lint`, `format`, `test`, `install`, and `uninstall`.

## Never write to these paths

- `/usr/share/omarchy/**` is owned by the `omarchy` package and is overwritten by
  `omarchy update`. Never install scripts there, and never patch the menu file
  there. Local installs go to `~/.local/bin`.
- Menu rows go in `~/.config/omarchy/extensions/omarchy-menu.jsonc` — the
  user-owned, update-safe extension file. It is JSONC with comments the user
  wrote, so merge into it with delimited markers; never parse-and-rewrite it.

## Bash house style

Matches `/usr/share/omarchy/bin`.

- `#!/bin/bash`, blank line, `# omarchy:` metadata comments, blank line, `set -e`.
  Use plain `set -e`. Do not use `set -euo pipefail`.
- Two-space indent. Line continuations lead with the pipe (`| tr ...`).
- `UPPER_SNAKE` for globals, `lower_snake` for functions.
- The `# omarchy:summary=` and `# omarchy:args=` comments are load-bearing: the
  `omarchy` dispatcher parses them out of the first 80 lines to build routes and
  help text. Do not drop or reformat them.
- `shellcheck` and `shfmt -d` must be clean. `make lint` runs both.

## Correctness rules

- **Bundle metadata is untrusted input.** An AppImage's own `.desktop` file is
  attacker-controlled. Every value written into a launcher goes through
  desktop-entry string escaping, and the payload path through freedesktop `Exec`
  quoting. A raw newline in a `Name` injects a second `Exec=` line. Do not
  simplify the two escaping helpers.
- **Never read the payload path back out of `Exec`.** Removal and collision
  checks read `X-AppImage-Payload`, which only goes through desktop-entry string
  escaping. Install rejects tab, CR, and LF in the path.
- **`Exec=` must start with the absolute path of `omarchy-launch-appimage`.**
  That name is the routing marker Omarchy's remover sniffs. Pointing `Exec`
  straight at the `.AppImage` breaks removal. The plugin directory is not on
  `$PATH`.
- **Detect AppImage type from magic bytes at offset 8** (`41 49 01` type-1,
  `41 49 02` type-2), not by attempting `--appimage-extract` and reading failure.
- **`/tmp` is tmpfs on Omarchy.** Extract to a disk-backed temp dir under
  `~/.cache`, not `$TMPDIR`.
- Payloads live in `~/Applications/` (moved, not copied), launchers in
  `~/.local/share/applications/`, icons under `~/.local/share/icons/hicolor/`
  in the size directory matching their real resolution (SVG in `scalable/`,
  unrecognised sizes fall back to `256x256`). Removal must sweep every size
  directory, not just one.

## URL installs

`omarchy-appimage-install` accepts a local path or an `https://` URL.

- Reject `http://` and any other scheme before `curl` runs. Redirects must stay
  on HTTPS (`--proto =https` and `--proto-redir =https`).
- Require a SHA-256 of 64 lowercase hex digits via `--sha256=<hex>` or
  `OMARCHY_APPIMAGE_SHA256`. Interactive runs ask when it is missing.
  Non-interactive runs fail. Do not add a flag that skips verification.
- Stage with `mktemp` in a `0700` directory under `~/Applications` and
  `umask 077`. Do not use a predictable `.$FILENAME.download.$$` name.
- `curl` must pass `--fail`, `--location`, `--tlsv1.2`, `--connect-timeout 15`,
  `--max-time 120`, and `--max-filesize 524288000` (500 MiB), and write only to
  the staging file.
- Compare the digest only after both sides are 64 lowercase hex digits. On
  mismatch, delete the staging file and exit nonzero. Do not `chmod +x` and do
  not run the file.
- `require_appimage` may read magic bytes after the digest matches. It does not
  execute the file.
- Do not `chmod +x` and do not run `--appimage-extract` until the digest matches
  and execution is confirmed. Interactive: `gum confirm` showing the URL,
  destination basename, size, and digest. Non-interactive: `--confirm-exec`.
  The later replace confirmation still happens. Local path installs do not ask
  this question.
- The cleanup trap must delete a failed or partial staging file.
- The panel and the bar drop target pass local paths only. They do not download
  URLs. Do not make the plugin run `omarchy pkg add`.

## Testing

- `bats`, run via `make test`.
- No test may touch the real `$HOME`, the real icon cache, or the network.
  Point `HOME` at a temp dir and prepend a stub `PATH` with fakes for `gum`,
  `curl`, `omarchy-menu-select`, `omarchy-notification-send`,
  `gtk-update-icon-cache`, and `update-desktop-database`.
- No test may require FUSE. Fixtures are generated ELF stubs that fake
  `--appimage-extract` by materialising a `squashfs-root/`.

## Manual verification

This checklist changes the real `$HOME`. The bats suite deliberately does not.

Subject: an `.AppImage` path, or an `https://` URL plus its SHA-256. Stop if
neither is available. Confirm the three scripts are on `$PATH` before starting.
Report each step as pass or fail. Do not edit the scripts to force a pass.

1. `ldconfig -p | grep libfuse.so.2`. If it is absent, install can still write a
   launcher; launch will fail until `omarchy pkg add fuse2`. Record the magic
   bytes at offset 8 (`od -An -tx1 -j8 -N3`).
2. Install from a local path. The payload moves to `~/Applications/`, is
   executable, and the source path is gone.
3. For a URL, install with `--sha256=<hex>` and `--confirm-exec`. `http://`
   must be rejected before any download. A wrong digest must delete the staging
   file and must not execute it. A missing `--confirm-exec` must not execute it.
4. `desktop-file-validate` the launcher. `Exec=` begins with
   `omarchy-launch-appimage` and quotes the payload. Exactly one `Name=` and one
   `Exec=`. `Icon=` resolves under `~/.local/share/icons/hicolor/` or is
   `application-x-executable`.
5. Ask the user to launch from Super+Space, compare `hyprctl clients -j` with
   `StartupWMClass`, then close the app.
6. `omarchy-appimage-remove <name>` removes the launcher, the icon, and the
   payload. `--keep-file` leaves the payload. `OMARCHY_REMOVE_NOTIFY=false`
   suppresses the notification.

Keep the two upstream patches in `upstream/` current as documented diffs. Do not
apply them to the system automatically.
