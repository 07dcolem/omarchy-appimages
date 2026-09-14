---
name: verify-appimage
description: Run the end-to-end verification checklist for the omarchy-appimage-* scripts on this machine — install from a path or URL, validate the generated launcher, check the window class, then remove and confirm nothing is left behind. Takes an optional AppImage path or URL.
disable-model-invocation: true
---

Run the acceptance checklist for the `omarchy-appimage-*` scripts against the real
system. This makes real changes to `$HOME` — it is the manual gate the automated
`bats` suite deliberately cannot cover.

Subject: `$ARGUMENTS` if given. Otherwise look for an `.AppImage` in `~/Downloads`
and ask which to use if there is more than one. Stop and ask if there are none.

Before starting, confirm the three scripts are on `$PATH`. If they are not, say so
and stop — there is nothing to verify yet.

Report each step as pass or fail with the actual output. Do not stop at the first
failure; run the whole list, then summarise. Never edit the scripts to make a step
pass during a verification run — report the failure and let the user decide.

## 1. Preflight

- `ldconfig -p | grep libfuse.so.2`. If absent, note that launch steps will fail
  and that the fix is `omarchy pkg add fuse2`. Continue anyway — install must still
  succeed and produce a valid launcher without FUSE.
- Record the subject's size and its magic bytes at offset 8
  (`od -An -tx1 -j8 -N3`): `41 49 01` is type-1, `41 49 02` is type-2. Type-1 is
  expected to fall back to the filename and a generic icon.

## 2. Install

- Install from the local path. Confirm the payload is now in `~/Applications/`,
  is executable, and that **nothing remains at the source path** (install moves,
  it does not copy).
- Confirm the move was reported on stdout.
- If the user supplied a URL, install from that too and confirm any query string
  was stripped and `.AppImage` appended when missing.

## 3. Launcher

- `desktop-file-validate` the generated `.desktop`. Must be clean.
- Print the `Exec=` line. It must begin with `omarchy-launch-appimage` and the
  payload path must be quoted.
- Confirm exactly one `Name=` and one `Exec=` key.
- Confirm `Icon=` resolves to a real file under
  `~/.local/share/icons/hicolor/256x256/apps/`, or is the documented
  `application-x-executable` fallback.
- Confirm `StartupWMClass` and `Categories` are present when the bundle supplied
  them, and absent rather than empty when it did not.

## 4. Launch and window class

- Ask the user to launch it from the app launcher (SUPER + SPACE) — do not launch
  it yourself, since a GUI app started from this session is awkward to clean up.
- Once it is running, compare `hyprctl clients -j` against the `StartupWMClass`
  the launcher claims. A mismatch means Hyprland window rules and
  `omarchy launch or focus` will not match the window.
- Ask the user to close it before continuing.

## 5. Menu integration

- Confirm an Install > AppImage row exists in
  `~/.config/omarchy/extensions/omarchy-menu.jsonc`.
- Confirm the Remove > AppImage row's `when:` guard now evaluates true (it should
  have been false before anything was installed).

## 6. Remove

- Run `omarchy-appimage-remove <name>`.
- Confirm all three are gone: the `.desktop`, the icon, and the payload in
  `~/Applications/`.
- Re-run install, then `omarchy-appimage-remove <name> --keep-file`, and confirm
  the payload survives while launcher and icon do not.
- Confirm `OMARCHY_REMOVE_NOTIFY=false` suppresses the notification.

## 7. Right-click removal

- Ask the user to install once more and remove via the app launcher's right-click.
- Without the upstream patch, expect the `.desktop` to be deleted and the icon and
  payload to remain — that is documented behaviour, not a failure. With the patch
  applied, expect a full cleanup.

## Finally

Summarise pass/fail per section. For each failure, point at the specific
requirement in `_specs/omarchy-appimage-scripts.md` it violates. Then clean up any
leftovers the run created, listing what you removed.
