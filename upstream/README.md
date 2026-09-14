# Upstream patches

Two small changes to the `omarchy` package that this project needs to be fully
integrated. They are **not applied automatically** — `/usr/share/omarchy` is owned
by the `omarchy` package and `omarchy update` overwrites it. They are kept here as
documented diffs for a pull request.

Both were generated against Omarchy 4.0.3-1.

| Patch | File | What it does |
|-------|------|--------------|
| `0001-route-appimage-removal.patch` | `bin/omarchy-remove-launcher-entry` | Routes removal of an AppImage launcher to `omarchy-appimage-remove` |
| `0002-appimage-group-description.patch` | `bin/omarchy` | Gives the `appimage` command group a description in `omarchy --help` |

Apply with, from the root of an Omarchy checkout:

    patch -p1 < upstream/0001-route-appimage-removal.patch

## What works without them

**Patch 1 is a graceful degradation, not a hard requirement.** Without it,
right-click → remove in the app launcher falls through
`omarchy-remove-launcher-entry`'s generic user-`.desktop` branch, which deletes the
launcher but leaves the icon and the `.AppImage` payload behind.
`omarchy-appimage-remove` cleans up all three either way.

**Patch 2 is cosmetic.** Without it the `appimage` group still works; it just
prints without a description in `omarchy --help`.

Neither patch is needed for `omarchy-appimage-install` and friends to run from
`~/.local/bin`. What *does* require upstreaming is the `omarchy appimage ...`
dispatch form: the dispatcher globs its own `/usr/share/omarchy/bin`, not `$PATH`,
so the routes only exist if the scripts live in that package-owned directory.

## Why the launchers carry X-AppImage-Payload

Generated launchers record the payload path twice: in `Exec`, fully quoted and
escaped per the freedesktop spec because that is how the app is launched, and in
an `X-AppImage-Payload` key that removal and collision checks read back.

The duplication is deliberate. Recovering the path from `Exec` means undoing two
escaping layers — Exec argument quoting, then desktop-entry string escaping on
top, which doubles every backslash the first layer produced — in that exact
order. Getting it wrong does not yield a nearly-right path: the `\"` unescape
pairs the second backslash with the quote and consumes both, so the result
matches nothing, `rm -f` exits 0 on it, and removal reports success while
orphaning a payload that can be hundreds of megabytes. That bug shipped once in
this project's own reference implementation.

The dedicated key goes through string escaping only, and install rejects tab, CR
and LF in the payload path, so the reverse is two lines with no ordering
constraint.

The cost is that removal only understands launchers this tool wrote. That is
acceptable here — it writes all of them, and the `Exec` marker still identifies
them for `omarchy-remove-launcher-entry` routing.

## Security model

An AppImage's embedded `.desktop` file is attacker-controlled input: the user may
have downloaded the bundle from anywhere. Everything read out of it — `Name`,
`Comment`, `Categories`, `StartupWMClass`, `MimeType`, `Icon` — is treated as
hostile and is escaped on the way into the generated launcher.

Two layers stop desktop-entry injection, and both are load-bearing:

- `desktop_value()` reads each key with `sed -n 's/^KEY=//p' | head -1`, so no
  recovered value can contain a raw newline.
- `desktop_string_escape()` escapes backslash first, then tab, CR, LF and a
  leading space. Every value written to the launcher passes through it.

Without these, a bundle shipping `Comment=hi<LF>Exec=curl … | sh` would inject a
second `Exec=` key. They are copied verbatim from `omarchy-webapp-install`, which
solves the same problem for pasted URLs — please don't simplify them.

**Executing the bundle is deliberately trusted.** Reading metadata means running
the AppImage's own runtime with `--appimage-extract`. That is not a weakness in
this code: the user asked to install and run that binary, and it will run as them
either way. It does mean a hostile bundle has code execution as the user *before*
anything here parses its metadata, which bounds what the rest of this section can
usefully defend against.

**Nothing here runs as root.** The scripts contain no `sudo`. The
`# omarchy:requires-sudo=true` marker on `omarchy-remove-launcher-entry` is
dispatcher metadata used for the command listing; the actual caller runs it
detached as the user with shell-quoted arguments, so the routing patch in
`0001` does not create an escalation path.

**Known and accepted:** a bundle can ship `.DirIcon` as a symlink pointing outside
itself, so the icon copy will place any file the user can read into
`~/.local/share/icons/hicolor/<size>/apps/<name>.<ext>` (`cp` preserves the source
mode). This is not treated as a vulnerability because it grants nothing the
bundle's own runtime did not already have. It is recorded here so it is a
documented limitation rather than a surprise.

Paths are constrained rather than sanitised where possible: the payload is always
`~/Applications/$(basename …)`, so a crafted filename or URL cannot escape the
directory; `require_plain_name` rejects `/` and control characters in the app
name, which becomes a launcher filename; and the icon sweep on removal derives its
glob from a name already reduced to `[[:alnum:]-]`.

## Expect pushback

Omarchy is packages-first, and the counter-argument — "it's in the AUR, use
`omarchy pkg add`" — covers most real cases. The gap is vendor-only builds, betas
and one-off tools that have no AUR package.
