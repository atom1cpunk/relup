# relup

*Update programs installed from GitHub releases, one at a time or all at once.*

An interactive Bash tool that keeps programs you installed by hand up to date, straight from their GitHub releases.

If you download `.rpm` packages, AppImages or single executables from GitHub release pages instead of using a package repository, `relup` remembers where each one came from, tells you when a newer release exists, and updates one program or all of them in a single step. It can even keep itself up to date.

> **Status:** early development (v0.3.0). It installs **`.rpm` packages via `dnf`** (Fedora, RHEL and relatives) and **single-file programs** (AppImages, executables, scripts). Archives such as `.tar.gz`, other package formats and other sources are planned, see the [roadmap](#roadmap).

## Features

- **Guided setup with almost no typing.** Paste a GitHub URL, type `owner/repo`, or enter a username to browse their repositories. `relup` works out the file pattern, the display name and the package name by itself, detects whether the program is already installed, and asks for one confirmation before saving.
- **Two kinds of programs.** System packages (`.rpm`, installed with `dnf`) and [single-file programs](#single-file-programs) (AppImages, executables, scripts, installed into a folder like `~/.local/bin`).
- **Preview before you act.** `relup update --all --dry-run` shows each file, its size, whether a checksum exists and the exact command that would run, without downloading or installing anything.
- **Gentle on GitHub's rate limit.** Answers are cached with their ETag, and you can reuse your `gh` login. See [rate limits and caching](#github-rate-limits-and-caching).
- **Update one or all.** Interactive menu or plain commands. The menu stays at the top of a cleared screen, and after each job you choose between returning to it or quitting.
- **Dates.** Shows each release's date and when each program was installed or last upgraded.
- **Checksum verification** before anything is installed (see [Checksums](#checksums)).
- **Works with shared repositories** that publish several products (for example `desktop-v…` and `web-v…` tags in the same repo).
- **Plain-text config**: one small file per program, easy to read and edit.
- **No code in config files.** They are parsed as data and never executed.

## Requirements

- Bash 4.4 or newer
- `curl`, `jq` and `sha256sum`
- For `.rpm` programs: `rpm` and `dnf`, with `sudo` access
- For single-file programs: nothing extra; `sudo` is only used if the install folder isn't writable by you

On Fedora: `sudo dnf install curl jq` (the rest is normally already present).

## Install

```bash
git clone https://github.com/atom1cpunk/relup.git
cd relup
install -m 755 relup ~/.local/bin/relup     # make sure ~/.local/bin is in your PATH
```

## Quick start

```bash
relup
```

On first run, `relup` offers to add your first program. For example, enter:

```
https://github.com/brave/brave-browser/releases
```

Every question shows its default in brackets (press Enter to accept it), and you can type `q` at any question to cancel. You then pick a release and, when the release has both an `.rpm` and an AppImage or executable, which kind you want. After that come your CPU architecture (only if the file names mention one) and the file to track (only if several match). `relup` reads the package name from the file's header, checks whether you already have the program installed, shows a short summary and asks once before saving. If the program isn't installed yet, it offers to install it.

Once you are tracking programs, running `relup` opens the main menu:

<p align="center">
  <img src="docs/menu.png" alt="The relup main menu: check for updates, update one or all programs, list, add, edit, uninstall, settings" width="720">
</p>

After each job, `relup` waits so you can read the output, then lets you return to the menu (Enter) or quit (`q`).

## Commands

| Command | What it does |
|---|---|
| `relup` | Open the interactive menu |
| `relup add [URL\|owner/repo]` | Start tracking a program (guided) |
| `relup list` | List tracked programs, installed versions and install dates (works offline) |
| `relup check` | Compare installed vs. latest version (with release and install dates) for every program |
| `relup update <id>` | Update one program |
| `relup update --all` | Update every program that has a newer release |
| `relup update <id> --dry-run` | Show what an update would do, without downloading or installing (also works with `--all`; short form `-n`) |
| `relup edit <id>` | Edit a program's config in `$VISUAL` / `$EDITOR` |
| `relup remove <id>` | Uninstall a program and/or stop tracking it |
| `relup config` | Edit `relup`'s own settings |
| `relup --help`, `relup --version` | Help and version |

Add `-y` / `--yes` to answer yes to ordinary confirmation prompts. Uninstalling, replacing a config and installing a download that has no published checksum always ask, even with `-y`. For a program you trust that publishes no checksum, set `VERIFY_CHECKSUM='skip'` in its config to update it unattended.

When there is no input to answer a question (for example `relup -y update --all` run from cron), the answer counts as **no**. `relup` skips that program, carries on with the others, and exits with an error status so the skipped program doesn't go unnoticed.

### Checking for updates

`relup check` (or option 1 in the menu) compares what you have installed with the latest release of every tracked program:

<p align="center">
  <img src="docs/check.png" alt="relup check output: a table of tracked programs with installed version, latest version, release date, install date and status" width="720">
</p>

- **RELEASED** is the date the latest release was published on GitHub.
- **INSTALLED ON** is when the package was installed or last upgraded.
- Build suffixes are ignored when comparing, so `1.19.0+65` installed counts as up to date against a `1.19.0` release (as with `localsend` above).

### Previewing an update

`relup update --all --dry-run` (or `relup update <id> --dry-run`, short form `-n`) shows what would happen and changes nothing:

```
Relup: 0.2.1 -> 0.3.0  (released 2026-11-27)
  File:      relup (48 KB)
  From:      https://github.com/atom1cpunk/relup/releases/download/v0.3.0/relup
  Checksum:  sha256 digest published by GitHub
  Would run: install -m 755 <downloaded relup> /home/you/.local/bin/relup
```

Nothing is downloaded or installed, and no prompts appear. It also tells you how a missing checksum would be handled (`none published; you would be asked before installing`), which makes it a quick way to test a new program's configuration. A dry run may still refresh the local GitHub cache.

## Single-file programs

Some projects publish one runnable file instead of a package: an AppImage, a static executable or a script. `relup` installs these by copying the file into a folder (`BIN_DIR`, by default `~/.local/bin`) and marking it executable.

- **Which files qualify.** AppImages, Linux executables and scripts: files with no extension, or one such as `.AppImage`, `.sh`, `.run` or `.bin`. The wizard hides archives (`.tar.gz`, `.zip`), packages for other systems, update packages such as `.mar`, checksum and signature files, and builds for other operating systems. When a release has both an `.rpm` and an AppImage, it asks which you want.
- **Safe replacement.** The new file is installed next to the old one and then renamed over it, so a program that is running can be replaced. A file that isn't an ELF binary, AppImage or script (for example an archive with an unlucky name) is refused before anything is touched.
- **Remembering the version.** There is no package database for single files, so `relup` records what it installed in `~/.local/state/relup/installed/<id>`. If a file is already at the destination but `relup` didn't put it there, its version shows as `unknown` and the first update replaces it. `sudo` is only used when the install folder isn't writable by you.
- **Make sure the folder is in your `PATH`.** `relup` warns when it isn't.

A single-file program's config looks like this:

```ini
NAME='LocalSend'
SOURCE='github'
REPO='localsend/localsend'
TAG_PREFIX='v'
ASSET_REGEX='^LocalSend-[0-9][0-9.]*-linux-x86-64\.AppImage$'
INSTALL='binary'
BIN_NAME='localsend'
VERIFY_CHECKSUM='auto'
```

### Keeping relup itself up to date

`relup` is a single script, so it can track its own releases:

```bash
relup add atom1cpunk/relup
```

It reads its own version from the installed script, so it knows where it stands from the start. After it updates itself, restart it to run the new version.

## Configuration

Files live in `~/.config/relup/` (or `$XDG_CONFIG_HOME/relup/`):

```
~/.config/relup/
├── settings.conf        relup's own settings
└── apps.d/
    ├── brave-browser.conf
    └── enteauth.conf    one file per tracked program
```

Two more folders hold data that `relup` can recreate: `~/.cache/relup/` (saved GitHub answers) and `~/.local/state/relup/installed/` (what was installed, for single-file programs). Both honour `XDG_CACHE_HOME` and `XDG_STATE_HOME`.

### Program config

`relup add` writes these for you, but you can edit them by hand (`relup edit <id>`):

```ini
NAME='Ente Auth'
SOURCE='github'
REPO='ente-io/ente'
TAG_PREFIX='auth-v'
ASSET_REGEX='(x86_64|amd64).*\.rpm$'
INSTALL='rpm'
PKG='enteauth'
VERIFY_CHECKSUM='auto'
```

| Key | Meaning |
|---|---|
| `NAME` | Display name used in tables and messages. Filled in automatically; change it freely. |
| `SOURCE` | Where releases come from (`github` only, for now) |
| `REPO` | GitHub `owner/repo` |
| `TAG_PREFIX` | Only releases whose tag starts with this are considered. Separates products in shared repos (`auth-v`, `desktop-v`). May be empty. |
| `ASSET_REGEX` | Regular expression the release file name must match |
| `INSTALL` | How the file is installed: `rpm` (system package, via `dnf`) or `binary` (a single file copied into a folder) |
| `PKG` | Package name as known to `rpm` (check with `rpm -q <name>`). It can differ from the release file's name (e.g. `LocalSend-….rpm` contains the package `localsend_app`); `relup` checks the downloaded file and offers to correct it. |
| `BIN_NAME` | `binary` only. Name of the installed command (default: the program's id) |
| `DEST_DIR` | `binary` only, optional. Absolute path of the folder to install into, instead of `BIN_DIR` from the settings |
| `VERIFY_CHECKSUM` | `auto`, `required` or `skip` (see below) |

`PKG` applies to `rpm` programs only. A `binary` program has `BIN_NAME` instead; see [single-file programs](#single-file-programs) for an example.

Rules: one `KEY='value'` per line, `#` comments on their own line, no inline comments.

### Settings

`relup config` opens `~/.config/relup/settings.conf`. In a new file every setting is commented out (`#CACHE=yes`) and uses the built-in default shown after the `=`. To change a setting, remove the `#` and edit the value. A setting you have set this way is never changed by `relup`, while commented-out settings follow the built-in default even if a later version changes it.

When a new version of `relup` adds settings that your file doesn't have yet, they are added at the end, commented out and with their explanation, and `relup` tells you once. Nothing you set is changed.

| Key | Meaning | Default |
|---|---|---|
| `DOWNLOAD_DIR` | Where downloads are staged before installing. A temporary subfolder is created and removed afterwards. | `/tmp` |
| `CLEAR_SCREEN` | `yes` or `no`. Clear the screen before each menu and job. Set to `no` to keep earlier output on screen. | `yes` |
| `BIN_DIR` | Folder where single-file programs are installed | `~/.local/bin` |
| `CACHE` | `yes` or `no`. Keep GitHub's answers between runs (see [caching](#github-rate-limits-and-caching)) | `yes` |
| `USE_GH_AUTH` | `yes` or `no`. Reuse your GitHub CLI login (`gh auth login`) for API requests | `no` |

## How a release is chosen

For each program, `relup` reads the repository's recent releases, up to 300 (skipping drafts and prereleases), keeps those whose tag starts with `TAG_PREFIX`, and takes the newest one that has a file matching `ASSET_REGEX`. The version is the tag with the prefix (and a leading `v`) removed, and it is compared with the version `rpm` reports for `PKG`. Build metadata after a `+` (for example `1.19.0+65`) is ignored in the comparison, and an installed version that is the same or newer than the latest release counts as up to date, so nothing is ever "updated" backwards.

Versions are compared number by number, the way `sort -V` does. This is not full semantic versioning: suffixes such as `-rc1` are not ranked as pre-releases, so `relup` relies on GitHub's own pre-release flag to skip those releases. If a project tags release candidates without flagging them, or uses an unusual scheme, check how it compares before trusting `relup update --all` with it. After each install, `relup` re-checks the installed version, so a package manager that quietly does nothing is reported as a failure.

## Checksums

Before installing, `relup` tries to verify the download, in this order:

1. The SHA-256 digest GitHub lists for the file in the release.
2. A checksum file attached to the same release (`<file>.sha256`, `SHA256SUMS`, `checksums.txt` and similar). The line for exactly that file name is used, so `tool` and `tool.tar.gz` in the same list are never confused.

If the checksum does not match, the file is **not** installed. If the release publishes no checksum, `relup` warns and asks before installing (`VERIFY_CHECKSUM='auto'`, and `-y` does not answer for you), refuses (`required`), or skips the check (`skip`). Checksum files larger than 2 MB are ignored.

Note that the checksum comes from the same release as the download. It catches corrupted or swapped files, but it cannot detect a release that was compromised at the source. `relup` does not verify GPG signatures.

## GitHub rate limits and caching

Without authentication, GitHub allows 60 API requests per hour, and each program costs at least one request per check. `relup` saves every answer together with its ETag in `~/.cache/relup/`, and next time only asks GitHub whether anything has changed. Per GitHub's documentation, an unchanged (`304`) answer **doesn't count against your rate limit when the request is authenticated**. Without a token it still counts, although it is faster. So if you track more than a handful of programs, authenticate in one of two ways:

1. Set a personal access token (no special scopes are needed for public repositories):

   ```bash
   export GITHUB_TOKEN=ghp_your_token_here
   ```

2. If you use the GitHub CLI, set `USE_GH_AUTH=yes` in `settings.conf` to reuse its login (`gh auth login`), so there is no token to manage. The token is only ever sent to `api.github.com`. `GITHUB_TOKEN` wins if both are set.

If you do run out of requests, `relup` falls back to the last saved answer and tells you so, instead of failing. Set `CACHE=no` to turn the cache off; it is always safe to delete `~/.cache/relup/`. Never commit a token to a repository.

## Tests

```bash
tests/run.sh               # run every test
tests/run.sh checksum      # only tests whose name contains "checksum"
tests/run.sh -v            # also show the output of passing tests
```

The tests need only `bash`, `jq` and coreutils. They use the real `jq` but replace `curl`, `rpm` and `sudo` with small fakes (in `tests/mocks/`): a pretend GitHub served from files, a pretend rpm database, and a `sudo dnf` that only updates that database. Each test runs in its own temporary home folder, so your real configuration, installed programs and the network are never touched.

## Roadmap

- GitLab as a second release source
- More install types (archives such as `.tar.gz`, `.deb`, Flatpak)
- Logging
- Pin / skip a version
- Keep the previous version for rollback
- Checking several programs in parallel

## Security notes

`relup` runs `sudo dnf install`, `upgrade` and `remove` on `.rpm` files, and copies single-file programs into a folder (using `sudo` only if that folder isn't writable), in both cases from the repositories you configure. Only track projects you trust. With `USE_GH_AUTH=yes`, `relup` borrows your `gh` login for read-only GitHub API requests.

## License

Copyright (C) 2026 Dmitry Goldshmidt

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. See [LICENSE](LICENSE) or <https://www.gnu.org/licenses/>.
