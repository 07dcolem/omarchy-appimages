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

## Expect pushback

Omarchy is packages-first, and the counter-argument — "it's in the AUR, use
`omarchy pkg add`" — covers most real cases. The gap is vendor-only builds, betas
and one-off tools that have no AUR package.
