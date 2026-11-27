# Changelog

All notable changes to `relup` are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). While the version is below 1.0, a minor version (0.x.0) can change behaviour.

## [0.3.0] - unreleased

### Added
- **Single-file programs.** A new `binary` install type for AppImages, executables and scripts. Files are installed into `BIN_DIR` (default `~/.local/bin`), replaced safely while running, and refused if they are not an ELF binary, AppImage or script. What was installed is recorded in `~/.local/state/relup/installed/`. `sudo` is only used when the folder isn't writable.
- **relup can track and update itself** (`relup add atom1cpunk/relup`). It reads its own installed version from the script and reminds you to restart after an update.
- **`update --dry-run` / `-n`.** Shows each file, its size, source, how it would be verified and the exact command that would run, without downloading or installing.
- **ETag cache** for GitHub API answers (`~/.cache/relup/`). Unchanged answers are fast, and free of the rate limit when authenticated. If the rate limit is exhausted, the last saved answer is used and the user is told. Old cache entries are pruned after 30 days.
- **`USE_GH_AUTH=yes`** setting: reuse the GitHub CLI login for API requests (`GITHUB_TOKEN` still takes precedence).
- **Settings** `BIN_DIR`, `CACHE` and `CLEAR_SCREEN` (turn off screen clearing).
- **New settings reach existing settings files.** When `settings.conf` lacks settings added by a newer version, they are appended commented out with their explanation, and you are told once. Values you have set are never changed.
- Program config keys `BIN_NAME` and `DEST_DIR` for single-file programs.
- **Recognising single-file programs you installed yourself.** When a file relup didn't install is already at the destination, its SHA-256 is compared with the checksums GitHub publishes for recent releases. A match gives its version, which is remembered, so a program you downloaded by hand counts as installed (and up to date, if it is the latest) instead of `unknown` with an offer to install it. A copy that matches nothing is still `unknown`, and relup now asks "Replace … with X?" instead of "Proceed?".
- When a release has both an `.rpm` and an AppImage or executable, the wizard asks which kind to track. It hides archives, packages for other systems, checksum and signature files, and other operating systems' builds.
- Automated tests (`tests/run.sh`), using the real `jq` with fake `curl`, `rpm` and `sudo`.

### Fixed
- **Security:** a file size in GitHub's answer (or in the local cache) was used in shell arithmetic without checking that it is a number, and Bash can run commands hidden in such a value. Sizes are now checked to be digits before use.
- **Security:** the GitHub token was passed to `curl` on its command line, where other users on the same computer can see it (for example with `ps`). It is now passed on `curl`'s standard input.
- A one-line checksum file for another file (for example `tool.tar.gz.sha256` next to `tool`) was used for the wrong file and caused a false checksum mismatch. Such files are now skipped and the next checksum source is tried.
- A program config whose `SOURCE` or `INSTALL` happened to name an internal function (for example `SOURCE='get'`) passed validation and made `relup check` hang. Only the real values (`github`; `rpm`, `binary`) are accepted.
- Without `-y` and with no input, `relup update` and `update --all` printed "Skipped" and exited successfully, so a cron job without `-y` silently did nothing. They now fail with a message suggesting `-y`.
- Cache entries in use were deleted every 30 days, because an unchanged (304) answer didn't refresh their age.
- A checksum list that names several similar files (for example `tool-linux-amd64` and `tool-linux-amd64.tar.gz`) could give the hash of the wrong file, so a good download was refused as a checksum mismatch. The line for exactly that file name is now used (also in BSD style and with a folder in front of the name).
- The wizard missed AppImages whose name doesn't say "linux" (e.g. `zen-x86_64.AppImage`) when another file did (e.g. `linux.mar`), and offered unknown formats such as Firefox-style `.mar` update packages as programs. AppImages now always count as Linux files, and only files with no extension or a program extension (`.AppImage`, `.sh`, `.run`, `.bin`, ...) are offered.
- The program name derived from a file like `zen-x86_64.AppImage` was "Zen X86" instead of "Zen".
- With no input to answer a question (an unattended `relup -y update --all`, e.g. from cron), `relup` exited at the first question, such as "install a download without a checksum?", skipped every remaining program and still reported success. Now no input counts as "no": that program is skipped, the rest are updated, and the run ends with an error status.

### Changed
- A new `settings.conf` has every setting commented out, so untouched settings follow the built-in defaults even if a later version changes them. Existing files keep their values; comment a line out to go back to following the default.
- The wizard no longer asks about architecture when no file name mentions one.
- Every wizard question shows "q to cancel", and an invalid answer asks again instead of ending the wizard.
- In the interactive menu, every question (choosing a program, the uninstall choices, the wizard, yes/no questions) accepts `b` to go straight back to the menu and `q` to quit, and says so. Choosing a program asks again after an invalid answer. The uninstall menu's `c) Cancel` option is replaced by these.
- Checking and updating show a live status line (`Checking for updates 2/5: brave-browser...`) instead of a blank screen while GitHub is asked about each program. It is only shown in a terminal.
- The uninstall confirmation shows the exact command that will run.
- `--help` documents the new options, folders and environment variables.

## [0.2.1] - 2026-11-25

### Fixed
- Releases are searched across up to 300 entries, so a product in a busy shared repository is no longer missed when its newest release falls past the first page.
- Checksum files larger than 2 MB are ignored and never downloaded.
- Program config files with unsafe names are skipped with a warning instead of breaking list handling.
- Config edits no longer use `sed`, and editors with arguments (for example `code -w`) work.
- The release-file pattern generated when adding a program no longer generalises part of a longer number.
- Stray command-line arguments (for example `relup check extra`) are rejected.

### Changed
- `-y` no longer answers the "no checksum published, install anyway?" question. For a program you trust that publishes no checksum, set `VERIFY_CHECKSUM='skip'` in its config to update it unattended.

## [0.2.0] - 2026-11-24

First public release.

### Added
- Guided setup from a GitHub URL, `owner/repo` or username, with the package name read from the RPM header so installed programs are detected.
- Update one program or all of them, with release and install dates.
- Checksum verification before installing (GitHub's digest, or a checksum file in the release).
- Interactive menu, `--help`, and plain-text per-program config files that are parsed as data, never executed.
- Support for `.rpm` packages installed with `dnf`.

[0.3.0]: https://github.com/atom1cpunk/relup/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/atom1cpunk/relup/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/atom1cpunk/relup/releases/tag/v0.2.0
