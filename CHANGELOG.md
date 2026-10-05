# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.1.7 - 2026-10-04

### Changed

- The panel switch says "Set AppImage File Association". A double-click still opens the panel, and the file does not run until Install or Update.
- Plugin version is 0.1.7.

## 0.1.6 - 2026-10-04

### Added

- The panel has a switch for opening `application/vnd.appimage` files. It is off when the setting is missing, including a fresh install and an upgrade. A double-click opens the panel, and the file does not run until Install or Update.
- Turning the switch off restores the previous handler only if this plugin is still the default. A handler another tool took is left alone. Disabling or removing the plugin does that same restore, and only deletes the opener this plugin added.

### Changed

- Plugin version is 0.1.6.

## 0.1.5 - 2026-10-04

### Changed

- The preview reads a type-2 filesystem in place with `unsquashfs -o`. It does not copy the bundle, and a large local file is not rejected before its header is read.
- A URL download stays capped at 500 MiB. That limit applies only to the download.
- Confirm names the reason a preview could not be read, including on an update. A type-1 AppImage, a symlink, a missing root desktop entry, and an embedded filesystem whose size is out of range each say so.
- When `X-AppImage-Version` is missing, confirm shows a version from the filename and says so. The desktop `Version=` key is not used.
- When a bundle has more than one root desktop file, the preview prefers one that is not `NoDisplay=true`, then one whose `Exec` names `AppRun`, then the alphabetical name.
- Plugin version is 0.1.5.

## 0.1.4 - 2026-10-04

### Changed

- The panel names a missing `python`, `squashfs-tools`, or `fuse2` package and shows the `omarchy pkg add` command, including on an update confirm. `fuse3` does not provide `libfuse.so.2`.
- The preview also needs `/usr/bin/python3` (`omarchy pkg add python`). Without `python` or `squashfs-tools`, confirm uses the filename and still does not run the file.
- Plugin version is 0.1.4.

## 0.1.3 - 2026-10-04

### Security

- The install preview reads a type-2 AppImage's name and version from the embedded filesystem. Dropping or picking a file no longer runs it. The file runs when you confirm Install or Update.
- `--inspect` does not mark the file executable and does not run `--appimage-extract`.

### Changed

- That preview uses `unsquashfs` (`omarchy pkg add squashfs-tools`). Without it, confirm uses the filename and still does not run the file.
- Plugin version is 0.1.3.

## 0.1.2 - 2026-09-26

### Added

- Dropping or adding a newer AppImage of an installed app asks to update it. Confirming replaces the launcher and retires the previous payload when the new file has a different name.
- `omarchy-appimage-install --inspect` reports that match without moving the file or marking it executable.

### Changed

- Enter on the confirm step follows the button: Update when the app is already installed, Install otherwise.

## 0.1.1 - 2026-09-23

### Security

- URL installs accept only `https://`. `http://` and every other scheme are rejected, and redirects cannot leave HTTPS.
- A URL install requires a SHA-256 digest (`--sha256=<64 lowercase hex>` or `OMARCHY_APPIMAGE_SHA256`) before any execution of the downloaded AppImage. A mismatch deletes the staging file and does not mark it executable.
- `curl` uses TLS 1.2 or newer, a 15 second connect timeout, a 120 second total timeout, and a 500 MiB size cap. The download is written only to a private `mktemp` file under a `0700` directory created with `umask 077`.
- The bundle is not marked executable and `--appimage-extract` does not run until the digest matches and execution is confirmed. Interactive installs ask with the URL, destination name, size, and digest. Non-interactive installs require `--confirm-exec`.

### Changed

- Non-interactive URL installs take `--sha256=<hex>` and `--confirm-exec`. Interactive installs ask for a missing digest. Local path installs are unchanged.
- Plugin version is 0.1.1.

### Removed

- Removed root `CLAUDE.md` and the `.claude/` directory from the published tree. Developer notes now live in `CONTRIBUTING.md` and `docs/development.md`.

## 0.1.0 - 2026-09-22

### Added

- Initial marketplace listing: install, list, open, and remove AppImages from the bar and the CLI.
