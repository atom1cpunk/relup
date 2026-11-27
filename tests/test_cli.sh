# shellcheck shell=bash
# Command line handling, --dry-run, list, settings, and the "add" wizard.

test_version_and_help() {
    run cli --version
    assert_eq "$output" "relup $(sed -n 's/^TOOL_VERSION="\(.*\)"$/\1/p' "$RELUP")" "--version"
    run cli --help
    assert_status 0
    assert_contains "update --all"
    assert_contains "--dry-run"
}

test_bad_arguments_are_rejected() {
    run cli check extra
    assert_status 1
    assert_contains "Unexpected argument: extra"
    run cli update a b
    assert_status 1
    assert_contains "Unexpected argument: b"
    run cli frobnicate
    assert_status 1
    assert_contains "Unknown command: frobnicate"
    run cli -n list
    assert_status 1
    assert_contains "--dry-run only applies to 'update'"
}

test_update_needs_a_target() {
    std_rpm_app tool 2.0.0
    run cli update
    assert_status 1
    assert_contains "Usage: relup update <id> | --all"
    run cli update nope
    assert_failed
    assert_contains "Unknown program: nope"
}

test_no_programs_yet() {
    run cli check
    assert_status 0
    assert_contains "No programs tracked yet."
}

test_settings_file_created_on_first_run() {
    rm "$CONF_DIR/settings.conf"
    run cli list
    assert_status 0
    for key in DOWNLOAD_DIR CLEAR_SCREEN BIN_DIR CACHE USE_GH_AUTH; do
        assert_file_contains "$CONF_DIR/settings.conf" "${key}="
    done
}

test_list_works_offline() {
    std_rpm_app tool 2.0.0; rpm_installed tool 1.0.0
    touch "$MOCK_GH/offline"
    run cli list
    assert_status 0
    assert_line '^1 +tool +tool +acme/tool +1\.0\.0 '
    [[ ! -s $MOCK_LOG ]] || fail "list contacted the network:\n$(cat "$MOCK_LOG")"
}

test_list_flags_broken_config() {
    app_conf broken REPO=nonsense
    run cli list
    assert_line '^1 +broken +\(config has errors, try: relup edit broken\)$'
}

test_unsafe_config_file_name_is_skipped() {
    std_rpm_app tool 2.0.0
    printf "REPO='acme/x'\n" > "$APPS/bad name.conf"
    run cli list
    assert_status 0
    assert_contains "Ignoring $APPS/bad name.conf"
    assert_line '^1 +tool '
    assert_not_contains "bad name  "
}

test_dry_run_changes_nothing() {
    std_rpm_app tool 2.0.0
    run cli update tool --dry-run
    assert_status 0
    assert_contains "tool: not installed -> 2.0.0  (released 2026-11-20)"
    assert_contains "File:      tool-2.0.0-1.x86_64.rpm (1 KB)"
    assert_contains "From:      https://github.com/acme/tool/releases/download/v2.0.0/tool-2.0.0-1.x86_64.rpm"
    assert_contains "Checksum:  sha256 digest published by GitHub"
    assert_contains "Would run: sudo dnf install -y $DL/relup.XXXXXX/tool-2.0.0-1.x86_64.rpm"
    assert_contains "Dry run: nothing was downloaded or installed."
    [[ -z $(download_requests) ]] || fail "dry run downloaded:\n$(download_requests)"
    assert_no_sudo
    assert_eq "$(rpm_version tool)" none "installed version"
}

test_dry_run_explains_checksum_situation() {
    std_rpm_app aaa 2.0.0 none; rpm_installed aaa 1.0.0
    std_rpm_app bbb 2.0.0 none; rpm_installed bbb 1.0.0
    printf "VERIFY_CHECKSUM='required'\n" >> "$APPS/bbb.conf"
    run cli update --all -n
    assert_status 0
    assert_contains "Would run: sudo dnf upgrade -y"
    assert_contains "none published; you would be asked before installing"
    assert_contains "none published; the install would be refused (VERIFY_CHECKSUM=required)"
    assert_not_contains "Proceed with all?"
    [[ -z $(download_requests) ]] || fail "dry run downloaded something"
}

# ---------- the add wizard ----------

test_add_rpm_program() {
    local r=acme/tool
    set_releases $r "$(mk_release v2.0.0 \
        "$(mk_asset $r v2.0.0 tool-2.0.0-1.x86_64.rpm "$(fake_rpm tool-bin 2.0.0)")" \
        "$(mk_asset $r v2.0.0 tool-2.0.0-1.aarch64.rpm "$(fake_rpm tool-bin 2.0.0)")")"
    # release 1, this machine's architecture, track it, don't install now
    run cli add https://github.com/acme/tool/releases <<< $'1\n1\ny\nn'
    assert_status 0
    assert_contains "Which build do you want?"
    assert_contains "Package:     tool-bin   [not installed]"
    local f="$APPS/tool.conf"
    assert_exists "$f"
    assert_file_contains "$f" "NAME='Tool'"
    assert_file_contains "$f" "REPO='acme/tool'"
    assert_file_contains "$f" "TAG_PREFIX='v'"
    assert_file_contains "$f" "ASSET_REGEX='^tool-[0-9][0-9.]*-1\.x86_64\.rpm\$'"
    assert_file_contains "$f" "INSTALL='rpm'"
    assert_file_contains "$f" "PKG='tool-bin'"
    grep -q $'\t0-524287\t' "$MOCK_LOG" || fail "package name not read from the start of the file:\n$(cat "$MOCK_LOG")"
    assert_contains "Proceed? [y/N]"
    assert_no_sudo
    run cli check
    assert_line '^1 +tool +none +2\.0\.0 .*not installed$'
}

test_add_detects_installed_program() {
    local r=acme/tool
    set_releases $r "$(mk_release v2.0.0 "$(mk_asset $r v2.0.0 tool-2.0.0.rpm "$(fake_rpm tool-bin 2.0.0)")")"
    rpm_installed tool-bin 2.0.0
    run cli add acme/tool <<< $'1\ny'
    assert_status 0
    assert_contains "Package:     tool-bin   [installed: 2.0.0, since"
    assert_contains "-> up to date"
    assert_not_contains "Which build"           # no architecture in the file name
}

test_add_chooses_single_file_over_rpm() {
    local r=localsend/localsend
    set_releases $r "$(mk_release v1.19.0 \
        "$(mk_asset $r v1.19.0 LocalSend-1.19.0-linux-x86-64.rpm "$(fake_rpm localsend_app 1.19.0)")" \
        "$(mk_asset $r v1.19.0 LocalSend-1.19.0-linux-x86-64.AppImage "$(fake_elf 1.19.0)")" \
        "$(mk_asset $r v1.19.0 LocalSend-1.19.0-linux-x86-64.tar.gz "tgz")" \
        "$(mk_asset $r v1.19.0 LocalSend-1.19.0-windows-x86-64.exe "exe")")"
    # release 1, kind 2 (single file), this machine's architecture, track it, install now
    run cli add localsend/localsend <<< $'1\n2\n1\ny\ny'
    assert_status 0
    assert_contains "This release has two kinds of files you could install"
    local f="$APPS/localsend.conf"
    assert_file_contains "$f" "NAME='LocalSend'"
    assert_file_contains "$f" "ASSET_REGEX='^LocalSend-[0-9][0-9.]*-linux-x86-64\.AppImage\$'"
    assert_file_contains "$f" "INSTALL='binary'"
    assert_file_contains "$f" "BIN_NAME='localsend'"
    assert_file_lacks "$f" "PKG="
    assert_eq "$(cat "$BIN/localsend")" "$(fake_elf 1.19.0)" "installed file"
}

test_add_zen_browser_finds_appimage() {
    local r=zen-browser/desktop name args=()
    for name in linux-aarch64.mar linux.mar macos.mar windows.mar zen-aarch64.AppImage zen-aarch64.AppImage.zsync \
                zen-x86_64.AppImage.zsync zen.installer.exe zen.linux-x86_64.tar.xz zen.macos-universal.dmg; do
        args+=("$(mk_asset $r 1.24.3b "$name" "other file")")
    done
    args+=("$(mk_asset $r 1.24.3b zen-x86_64.AppImage "$(fake_elf 1.24.3b)")")
    set_releases $r "$(mk_release 1.24.3b "${args[@]}")"
    # release 1, this machine's architecture, track it, don't install now
    run cli add https://github.com/zen-browser/desktop/releases <<< $'1\n1\ny\nn'
    assert_status 0
    assert_not_contains "No file in that release mentions that architecture"
    assert_not_contains ".mar"
    assert_contains "File: zen-x86_64.AppImage"
    assert_file_contains "$APPS/zen.conf" "ASSET_REGEX='^zen-x86_64\.AppImage\$'"
    assert_file_contains "$APPS/zen.conf" "TAG_PREFIX=''"
    assert_file_contains "$APPS/zen.conf" "INSTALL='binary'"
    run cli check
    assert_line '^1 +zen +none +1\.24\.3b .*not installed$'
}

test_add_can_be_cancelled_at_every_question() {
    local r=acme/tool
    set_releases $r "$(mk_release v2.0.0 \
        "$(mk_asset $r v2.0.0 tool-2.0.0-1.x86_64.rpm "$(fake_rpm tool 2.0.0)")" \
        "$(mk_asset $r v2.0.0 tool-2.0.0-linux-x86_64.AppImage "$(fake_elf 2)")" \
        "$(mk_asset $r v2.0.0 tool-2.0.0-linux-arm64.AppImage "$(fake_elf 2)")")"
    local answers
    for answers in 'q' $'1\nq' $'1\n2\nq'; do       # release, kind, architecture
        run cli add acme/tool <<< "$answers"
        assert_contains "(q to cancel)"
        assert_contains "Cancelled."
        assert_missing "$APPS/tool.conf"
    done
    run cli add <<< 'q'                            # the first question too
    assert_contains "Cancelled."
    assert_no_sudo
}

test_add_asks_again_after_invalid_number() {
    local r=acme/tool
    set_releases $r "$(mk_release v2.0.0 "$(mk_asset $r v2.0.0 tool-2.0.0.AppImage "$(fake_elf 2)")")"
    run cli add acme/tool <<< $'7\nabc\n1\ny\nn'
    assert_status 0
    assert_contains "Please enter a number from 1 to 1, or q to cancel."
    assert_exists "$APPS/tool.conf"
}

test_add_without_installable_files() {
    local r=acme/src
    set_releases $r "$(mk_release v1.0.0 "$(mk_asset $r v1.0.0 src-1.0.0.tar.gz "tgz")" "$(mk_asset $r v1.0.0 src-1.0.0.zip "zip")")"
    run cli add acme/src <<< $'1'
    assert_failed
    assert_contains "Nothing in this release can be installed"
    assert_contains "  src-1.0.0.tar.gz"
    assert_missing "$APPS/src.conf"
}

test_add_uses_tag_from_url() {
    local r=acme/tool
    set_releases $r \
        "$(mk_release v2.0.0 "$(mk_asset $r v2.0.0 tool-2.0.0.AppImage "$(fake_elf 2)")")" \
        "$(mk_release v1.0.0 "$(mk_asset $r v1.0.0 tool-1.0.0.AppImage "$(fake_elf 1)")")"
    run cli add https://github.com/acme/tool/releases/tag/v1.0.0 <<< $'y\nn'
    assert_status 0
    assert_contains "Using release v1.0.0 from the URL."
    assert_contains "File:        tool-1.0.0.AppImage"
}

test_add_browse_user_repos() {
    api_set "users/acme/repos?per_page=100&sort=pushed" \
        '[{"name":"old","description":"archived","archived":true},{"name":"tool","description":"A tool","archived":false}]'
    local r=acme/tool
    set_releases $r "$(mk_release v2.0.0 "$(mk_asset $r v2.0.0 tool-2.0.0.AppImage "$(fake_elf 2)")")"
    run cli add acme <<< $'1\n1\ny\nn'
    assert_status 0
    assert_line '^ +1\) tool +A tool$'
    assert_not_contains "archived"
    assert_exists "$APPS/tool.conf"
}

test_add_replacing_config_asks_even_with_y() {
    local r=acme/tool
    set_releases $r "$(mk_release v2.0.0 "$(mk_asset $r v2.0.0 tool-2.0.0.AppImage "$(fake_elf 2)")")"
    app_conf tool REPO=acme/other 'ASSET_REGEX=x'
    run cli -y add acme/tool <<< $'1\ny\nn'
    assert_contains "tool.conf already exists and would be replaced"
    assert_contains "Replace the existing tool.conf? [y/N]"
    assert_contains "Cancelled."
    assert_file_contains "$APPS/tool.conf" "REPO='acme/other'"
}
