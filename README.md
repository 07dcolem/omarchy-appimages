# AppImages

Omarchy shell plugin that installs, lists, and removes AppImages on this machine. It is not a Gear Lever clone, and it does not touch Flatpak. An installed app shows up in the Omarchy launcher because the plugin writes a normal XDG desktop file.

Plugin id: `07dcolem.appimages`

## Install

Once this repo is public:

```bash
omarchy plugin add https://github.com/07dcolem/omarchy-appimages.git --enable --yes
omarchy bar put 07dcolem.appimages
```

Today the checkout is local. Copy it into the directory Omarchy loads. Do not symlink the checkout into `~/.config/omarchy/plugins/`.

```bash
rsync -a --delete --exclude .git \
  ~/src/omarchy-appimages/ \
  ~/.config/omarchy/plugins/07dcolem.appimages/
omarchy plugin validate ~/.config/omarchy/plugins/07dcolem.appimages
omarchy plugin enable 07dcolem.appimages
omarchy bar put 07dcolem.appimages
```

`omarchy plugin enable` records the plugin in `~/.config/omarchy/shell.json`. `omarchy bar put` places the widget. The manifest's default section is the right side of the bar. If the icon does not appear, `omarchy restart shell` reloads the shell. `omarchy plugin list` shows whether it is enabled.

## Usage

The bar icon is labeled AppImages and is a drop target. Hold a file on it and the panel opens. Drop an `.AppImage` on the icon or on the panel, or use Add and pick a file. The confirm step shows the filename, the destination `~/Applications/<name>.AppImage`, and a sha256 when the hash finishes. Install moves the file. It does not copy it.

After that, Super+Space finds the app.

Each row can open the app or remove it. Remove deletes the launcher, the icon, and the file in `~/Applications`. Keep file leaves the payload and still removes the launcher and icon.

Esc closes the panel. Enter on a row launches that app. Enter on the confirm step installs.

The command line does the same work. Pass a path and the tools stay non-interactive:

```bash
~/.config/omarchy/plugins/07dcolem.appimages/bin/omarchy-appimage-install ~/Downloads/Example.AppImage
~/.config/omarchy/plugins/07dcolem.appimages/bin/omarchy-appimage-list
~/.config/omarchy/plugins/07dcolem.appimages/bin/omarchy-appimage-remove "Example"
```

`--keep-file` on remove leaves the payload. `--replace` on install upgrades a launcher that already uses that name.

## v0.1

This release installs, lists, opens, and removes. It does not check for updates, watch GitHub or GitLab, keep older versions side by side, fetch in the background, or send update notifications.

## Dependencies

Running an AppImage needs FUSE. Type-2 bundles, which are almost all of them, need `libfuse.so.2` from `fuse2`. `fuse3` provides `fusermount3`.

```bash
omarchy pkg add fuse2
```

The installer reads the bundle's name, comment, icon, and categories by running its `--appimage-extract`. That step needs `libfuse.so.2` for a real AppImage. `squashfs-tools` provides `unsquashfs` if you want to inspect a bundle by hand:

```bash
omarchy pkg add squashfs-tools
```

Install still writes a launcher when FUSE is missing. The panel warns that starting the app may fail.

## License

MIT. See [LICENSE](LICENSE).

## Attribution

Install, launch, and remove logic in bin/ is adapted from
https://github.com/kabe2007/omarchy-appimage-integration
by Juan I. de Elizalde (GitHub: kabe2007), licensed under the MIT License.

Copyright (c) 2026 Juan I. de Elizalde
Copyright (c) 2026 07dcolem

This plugin is not affiliated with or endorsed by Juan I. de Elizalde.
The MIT license text is in LICENSE. That notice and the copyright lines
above must be preserved in copies and substantial portions of this software.
