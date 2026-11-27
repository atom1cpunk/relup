# relup: project guide for Claude

Read this file at the start of every session. It carries the context from the claude.ai conversation where relup was designed and built, so keep it current as decisions change.

## What relup is

A single-file Bash tool (`relup`) that keeps programs installed by hand up to date from their GitHub release pages. It has an interactive menu and plain commands (`add`, `list`, `check`, `update <id>|--all`, `edit`, `remove`, `config`). Author: Dmitry Goldshmidt, GPLv3. Repo: `atom1cpunk/relup`.

- Current code version: **0.3.0** (`TOOL_VERSION` in the script), released 2026-11-27. Tagged releases: `v0.2.0`, `v0.2.1`, `v0.3.0`. The next version is 0.3.1 (see the roadmap).
- Target system: Fedora (bash 4.4+, `curl`, `jq`, `sha256sum`, `rpm`, `dnf`). The `gh` CLI is installed and logged in.
- The tool was renamed from `ghup` to `relup` before the first commit. The name may change again, so never hard-code it: use `TOOL_NAME` / `TOOL_VERSION`.

## Files

- `relup`: the whole program.
- `README.md`, `CHANGELOG.md` (Keep a Changelog format), `LICENSE` (GPLv3), `docs/*.png` (README screenshots).
- `tests/`: `run.sh` (runner, plain Bash, no bats), `lib.sh` (fresh fake HOME per test, fixture builders, assertions), `test_*.sh`, and `mocks/` with fake `curl` (pretend GitHub served from files, ETags, rate limit, offline), `rpm` (pretend rpm database) and `sudo` (fake `dnf`; anything else runs as the user). Only these three are mocked; the real `jq` is used.
- `.claude/settings.json` + `.claude/hooks/check-relup.sh`: a Claude Code hook that runs `bash -n` and `shellcheck` (minus the 5 known notes) after every edit of `relup` and reports problems back to Claude.
- `.github/workflows/tests.yml`: GitHub Actions runs `bash -n`, shellcheck and `tests/run.sh` on every push and pull request (Ubuntu runner; its shellcheck may be older than Fedora's).
- User data (not in the repo): `~/.config/relup/settings.conf`, `~/.config/relup/apps.d/<id>.conf` (one per tracked program), cache `~/.cache/relup/`, state `~/.local/state/relup/installed/<id>`.

## Design rules (do not break these without asking)

- **Config files are data, never code.** They are read by `parse_conf` with a whitelist of keys. No `source`, no `eval`.
- **`confirm` vs `confirm_strict`.** `-y` answers `confirm` only. No input (EOF) answers either one with "no", never by exiting. Uninstalling, replacing a config and installing a download with no published checksum always ask (`confirm_strict`). Per-program `VERIFY_CHECKSUM='skip'` is the unattended route.
- **Every question has a way out.** In the menu (`IN_MENU=1`), `_confirm`, `ask_choice` and `ask_number` accept `b` (sets `BACK_TO_MENU`, the job unwinds as "no" and the menu skips the pause) and `q` (exit). Outside the menu, `ask_choice` takes `q` as cancel. Use these helpers, not bare `ask`, for any new question. Slow steps use `progress` / `progress_done` (terminal only; `warn`/`err` clear the line first).
- **`set -euo pipefail` is on.** `main` only runs when the script is executed (not when sourced), so tests can `source ./relup` and call functions.
- **Plug-in style install methods.** A method `<m>` provides `installed_version_<m>`, `install_<m>`, `uninstall_<m>`, `install_command_<m>`, `uninstall_command_<m>`, `describe_target_<m>`, and optionally `installed_date_<m>` and `package_name_<m>`. Today: `rpm` (dnf) and `binary` (AppImage, executable, script copied into `BIN_DIR`). Release sources work the same way: `<source>_releases` (only `github` exists). A new method or source must also be added to `INSTALL_METHODS` / `RELEASE_SOURCES`; `load_app` accepts only names listed there.
- **Choosing a release.** Up to 3 pages (300 releases) are searched; drafts and prereleases are skipped; `TAG_PREFIX` separates products in shared repos (`auth-v`, `desktop-v`); the first release with a file matching `ASSET_REGEX` wins.
- **Versions.** `version_norm` strips a leading `v` and `+build` metadata; `version_ge` uses `sort -V`. "Installed is the same or newer than latest" counts as up to date, so nothing is ever downgraded. This is not full semver; the tool relies on GitHub's prerelease flag. "none" and "unknown" never count as versions.
- **Checksums.** Order: the digest GitHub lists for the file, then a checksum file in the same release (files over 2 MB ignored). A mismatch always blocks the install. This does not detect a compromised release, and there is no GPG verification.
- **rpm installs are verified afterwards.** The installed version is re-queried; "dnf did nothing" is reported as a failure. The real package name is read from the downloaded rpm and written back into the config if the config was wrong.
- **Binary installs** copy next to the target and `mv` over it (safe for a running program), refuse anything that isn't ELF/AppImage/script, use `sudo` only if the folder isn't writable, and record what was installed in the state file. A file relup didn't install is identified by comparing its SHA-256 with the GitHub digests of the matching file in recent releases (`identify_by_checksum`, fed by `find_latest`'s `.known` list, which costs no extra API request); on a match the state file is written. Never run an unknown binary to learn its version.
- **GitHub API.** Answers are cached with ETags; the token comes from `GITHUB_TOKEN`, or from `gh auth token` when `USE_GH_AUTH=yes`, and is passed to curl on stdin (`-H @-`), never on its command line. When rate limited, the last saved answer is used. Conditional (304) answers are free of the rate limit only when authenticated.
- **settings.conf.** Active lines are the user's choices and are never rewritten. New files have every setting commented out (`#KEY=default`), so untouched settings follow the code's defaults. `add_missing_settings` appends settings missing from an older file, commented out, and says so once. `settings_doc` holds each setting's explanation and default: add new settings there and to `SETTINGS_KEYS`, and keep its defaults equal to the ones at the top of the script (a test checks this).
- **Data from GitHub is untrusted.** Never put a value from GitHub's answers or the cache into `(( ))`, `[[ -lt ]]` and the like without first checking it is digits: Bash runs `$(...)` hidden in an array index there.
- **The wizard should need almost no typing.** Names and package names are derived automatically; one confirmation before saving.

## What has and hasn't been verified on real systems

- Up to **0.2.1**: run by the user on real Fedora with real `jq`, `dnf` and GitHub (Brave, Ente Auth, Bitwarden, LocalSend all worked).
- **0.3.0**: before release the user ran a live test on real Fedora (2026-11-27), which found the Caligula case (a hand-installed single file shown as `unknown`), fixed before release. GitHub's per-asset `digest` field was confirmed live (it matched Caligula's real file). Not individually confirmed: reading the package name from a partial rpm download, and `USE_GH_AUTH` with the real `gh`.
- The automated tests in `tests/` (rebuilt 2026-11-26, using the real `jq`) cover all of the above against the fake `curl`/`rpm`/`sudo`. They found and fixed two bugs: `extract_hash` took the first line *containing* the file name, and a question with no input exited 0 halfway through `update --all`. An Opus review of the 0.3.0 branch (2026-11-27) found no checksum bypass or config-as-code path; its findings 1-5 were fixed with tests. Left for 0.3.1: version strings written differently (`1.0` vs `1.0.0`, `-1` suffix) never count as up to date; HTTP 401 (expired token) gives no hint; repository descriptions in the wizard are not stripped of control characters. Tests are not a substitute for the live check: real rpm header reads, GitHub's `digest` field and `USE_GH_AUTH` (needs the real `gh`) are still untested.

## Working conventions

- Run `bash -n relup`, `shellcheck relup` and `tests/run.sh` after changes, and add a test for each fix or new behaviour. `shellcheck relup` currently reports 5 known, harmless notes (SC2088, SC2174, SC2034 x2, SC2018/2019).
- Never commit tokens. Never move or delete a published tag, and don't overwrite assets on an existing release.
- Update `README.md` and `CHANGELOG.md` whenever behaviour changes.
- Release steps: bump `TOOL_VERSION`, update the README status line and the CHANGELOG, commit and push, then `gh release create vX.Y.Z relup --target main --title "relup X.Y.Z" --notes-file <notes>`.
- Explain things plainly. Ask before large or irreversible changes, and say what you ran and what the result was.

## Roadmap

Next (0.3.1): the three audit leftovers above, and detection of already-installed programs beyond the checksum match (copies elsewhere in `PATH`, rpm packages with a different name such as Brave's `brave-origin`, Flatpaks). Also bump `actions/checkout` to v5 (v4 runs on a deprecated Node.js). Later: archives (`.tar.gz`), `.deb` and Flatpak install types, logging, pin/skip a version, keeping the previous version for rollback, parallel status checks. GitLab support is deliberately deferred.
