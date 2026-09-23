# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
