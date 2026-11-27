# shellcheck shell=bash
# The "binary" install method: AppImages, executables and scripts copied into a folder.

test_binary_install_records_state() {
    std_bin_app cli 1.2.0
    run cli -y update cli
    assert_status 0
    assert_contains "cli is now at 1.2.0"
    assert_exists "$BIN/cli"
    [[ -x $BIN/cli ]] || fail "$BIN/cli is not executable"
    assert_eq "$(cat "$BIN/cli")" "$(fake_elf 1.2.0)" "installed file"
    assert_file_contains "$STATE/cli" "VERSION='1.2.0'"
    assert_file_contains "$STATE/cli" "FILE='$BIN/cli'"
    assert_file_contains "$STATE/cli" "INSTALLED_ON='$(date +%F)'"
    assert_no_sudo
    run cli list
    assert_line "^1 +cli +cli +acme/cli +1\.2\.0 +$(date +%F)$"
    run cli check
    assert_line '^1 +cli +1\.2\.0 +1\.2\.0 .*up to date$'
}

test_binary_upgrade_replaces_file() {
    std_bin_app cli 1.2.0
    run cli -y update cli
    std_bin_app cli 1.3.0
    run cli -y update cli
    assert_status 0
    assert_eq "$(cat "$BIN/cli")" "$(fake_elf 1.3.0)" "installed file"
    assert_file_contains "$STATE/cli" "VERSION='1.3.0'"
    [[ -z $(find "$BIN" -name '*-new') ]] || fail "temporary file left in $BIN"
}

test_binary_script_is_accepted() {
    std_bin_app cli 1.2.0 "$(fake_script hello)"
    run cli -y update cli
    assert_status 0
    assert_eq "$("$BIN/cli")" "hello" "running the installed script"
}

test_binary_refuses_non_program() {
    std_bin_app cli 1.2.0 $'PK\003\004 this is a zip'
    printf 'old\n' > "$BIN/cli"
    run cli -y update cli
    assert_failed
    assert_contains "doesn't look like a program"
    assert_eq "$(cat "$BIN/cli")" "old" "existing file untouched"
    assert_missing "$STATE/cli"
}

test_binary_existing_file_has_unknown_version() {
    std_bin_app cli 1.2.0
    fake_elf 0.1 > "$BIN/cli"
    run cli check
    assert_line '^1 +cli +unknown +1\.2\.0 .*update available$'
    run cli -y update cli
    assert_status 0
    assert_file_contains "$STATE/cli" "VERSION='1.2.0'"
}

test_binary_state_for_other_path_is_ignored() {
    std_bin_app cli 1.2.0
    run cli -y update cli
    printf "BIN_NAME='cli2'\n" >> "$APPS/cli.conf"   # now installs elsewhere
    fake_elf 0.1 > "$BIN/cli2"
    run cli list
    assert_line '^1 +cli .* unknown '
}

test_binary_dest_dir_not_writable_uses_sudo() {
    std_bin_app cli 1.2.0
    mkdir -p "$T/opt/bin"; chmod 555 "$T/opt/bin"
    printf "DEST_DIR='%s'\n" "$T/opt/bin" >> "$APPS/cli.conf"
    export MOCK_SUDO_UNLOCK="$T/opt/bin"
    run cli -y update cli -n
    assert_contains "Would run: sudo install -m 755 <downloaded cli-1.2.0-linux-x86_64.AppImage> $T/opt/bin/cli"
    run cli -y update cli
    assert_status 0
    assert_contains "isn't writable by you; using sudo"
    assert_file_contains "$MOCK_SUDO_LOG" "install -m 755"
    assert_file_contains "$MOCK_SUDO_LOG" "mv -f $T/opt/bin/cli.relup-new $T/opt/bin/cli"
    assert_eq "$(cat "$T/opt/bin/cli")" "$(fake_elf 1.2.0)" "installed file"
    assert_contains "is not in your PATH"
}

test_binary_checksum_skips_sidecar_of_archive() {
    local r=acme/mytool bin tgz
    bin=$(fake_elf 1.0); tgz="archive bytes"
    set_releases $r "$(mk_release v1.0.0 \
        "$(mk_asset $r v1.0.0 mytool "$bin" none)" \
        "$(mk_asset $r v1.0.0 mytool.tar.gz "$tgz" none)" \
        "$(mk_asset $r v1.0.0 mytool.tar.gz.sha256 "$(sha_of "$tgz")  mytool.tar.gz" none)" \
        "$(mk_asset $r v1.0.0 SHA256SUMS "$(sha_of "$tgz")  mytool.tar.gz
$(sha_of "$bin")  mytool" none)")"
    app_conf mytool REPO=$r TAG_PREFIX=v 'ASSET_REGEX=^mytool$' INSTALL=binary BIN_NAME=mytool
    run cli -y update mytool
    assert_status 0
    assert_contains "Checksum OK (sha256, from SHA256SUMS)"
    assert_eq "$(cat "$BIN/mytool")" "$bin" "installed file"
}

test_binary_remove() {
    std_bin_app cli 1.2.0
    run cli -y update cli
    run cli -y remove cli <<< $'1\ny'
    assert_status 0
    assert_contains "This will run: rm $BIN/cli. Continue?"
    assert_missing "$BIN/cli"
    assert_missing "$STATE/cli"
    assert_missing "$APPS/cli.conf"
}

test_self_tracking_reads_own_version() {
    local mine
    mine=$(sed -n 's/^TOOL_VERSION="\(.*\)"$/\1/p' "$RELUP")
    cp "$RELUP" "$BIN/relup"
    set_releases atom1cpunk/relup "$(mk_release v9.9.9 "$(mk_asset atom1cpunk/relup v9.9.9 relup "$(sed "s/^TOOL_VERSION=.*/TOOL_VERSION=\"9.9.9\"/" "$RELUP")")")"
    app_conf relup REPO=atom1cpunk/relup TAG_PREFIX=v 'ASSET_REGEX=^relup$' INSTALL=binary BIN_NAME=relup
    run cli check
    assert_line "^1 +relup +${mine//./\\.} +9\.9\.9 .*update available$"
    run cli -y update relup
    assert_status 0
    assert_contains "Restart relup to run the new version."
    assert_file_contains "$BIN/relup" 'TOOL_VERSION="9.9.9"'
}
