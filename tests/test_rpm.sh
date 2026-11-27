# shellcheck shell=bash
# The rpm install method: status, installs and upgrades through (fake) sudo dnf, checksums,
# verification after installing, and correcting the package name.

test_check_shows_each_state() {
    std_rpm_app current 2.0.0; rpm_installed current 2.0.0+5      # build metadata ignored
    std_rpm_app newer 2.0.0;   rpm_installed newer 3.0.0          # never "updated" backwards
    std_rpm_app old 2.0.0;     rpm_installed old 1.0.0
    std_rpm_app absent 2.0.0
    run cli check
    assert_status 0
    assert_line '^1 +absent +none +2\.0\.0 +2026-11-20 +- +not installed$'
    assert_line '^2 +current +2\.0\.0\+5 +2\.0\.0 .*up to date$'
    assert_line '^3 +newer +3\.0\.0 +2\.0\.0 .*up to date$'
    assert_line '^4 +old +1\.0\.0 +2\.0\.0 .*update available$'
}

test_install_new_program() {
    std_rpm_app tool 2.0.0
    run cli -y update tool
    assert_status 0
    assert_contains "Checksum OK (sha256, from the digest GitHub lists for this file)"
    assert_contains "tool is now at 2.0.0"
    assert_file_contains "$MOCK_SUDO_LOG" "dnf install -y $DL/relup."
    assert_eq "$(rpm_version tool)" 2.0.0 "installed version"
    [[ -z $(ls -A "$DL") ]] || fail "temporary download folder left behind: $(ls -A "$DL")"
}

test_upgrade_existing_program() {
    std_rpm_app tool 2.0.0
    rpm_installed tool 1.0.0
    run cli -y update tool
    assert_status 0
    assert_file_contains "$MOCK_SUDO_LOG" "dnf upgrade -y "
    assert_eq "$(rpm_version tool)" 2.0.0 "installed version"
}

test_update_asks_before_proceeding() {
    std_rpm_app tool 2.0.0
    rpm_installed tool 1.0.0
    run cli update tool <<< "n"
    assert_contains "Proceed? [y/N]"
    assert_contains "Skipped tool."
    assert_no_sudo
}

test_up_to_date_program_is_left_alone() {
    std_rpm_app tool 2.0.0
    rpm_installed tool 3.0.0
    run cli -y update tool
    assert_status 0
    assert_contains "tool is already up to date"
    assert_no_sudo
    [[ -z $(download_requests) ]] || fail "something was downloaded"
}

test_digest_mismatch_blocks_install() {
    std_rpm_app tool 2.0.0 "sha256:$(printf '0%.0s' {1..64})"
    rpm_installed tool 1.0.0
    run cli -y update tool
    assert_failed
    assert_contains "CHECKSUM MISMATCH for tool-2.0.0-1.x86_64.rpm"
    assert_no_sudo
    assert_eq "$(rpm_version tool)" 1.0.0 "installed version"
}

# Releases without GitHub digests but with a checksum file
release_with_checksum_file() {  # release_with_checksum_file <sums-file-name> <sums-content-template>
    local r=acme/tool rpmc
    rpmc=$(fake_rpm tool 2.0.0)
    set_releases $r "$(mk_release v2.0.0 \
        "$(mk_asset $r v2.0.0 tool-2.0.0-1.x86_64.rpm "$rpmc" none)" \
        "$(mk_asset $r v2.0.0 "$1" "${2//HASH/$(sha_of "$rpmc")}" none)")"
    app_conf tool REPO=$r TAG_PREFIX=v 'ASSET_REGEX=^tool-.*\.rpm$' PKG=tool
}

test_checksum_file_is_used_without_digest() {
    release_with_checksum_file SHA256SUMS "$(printf 'f%.0s' {1..64})  tool-2.0.0-1.aarch64.rpm
HASH  tool-2.0.0-1.x86_64.rpm"
    run cli -y update tool
    assert_status 0
    assert_contains "Checksum OK (sha256, from SHA256SUMS)"
    assert_eq "$(rpm_version tool)" 2.0.0 "installed version"
}

test_sidecar_checksum_file() {
    release_with_checksum_file tool-2.0.0-1.x86_64.rpm.sha256 "HASH"
    run cli -y update tool
    assert_status 0
    assert_contains "Checksum OK (sha256, from tool-2.0.0-1.x86_64.rpm.sha256)"
}

test_checksum_file_mismatch_blocks_install() {
    release_with_checksum_file SHA256SUMS "$(printf 'e%.0s' {1..64})  tool-2.0.0-1.x86_64.rpm"
    run cli -y update tool
    assert_failed
    assert_contains "CHECKSUM MISMATCH"
    assert_no_sudo
}

test_no_checksum_question_is_not_answered_by_y() {
    std_rpm_app tool 2.0.0 none
    run cli -y update tool <<< "n"
    assert_contains "No checksum is published for tool-2.0.0-1.x86_64.rpm"
    assert_contains "Install it anyway? [y/N]"
    assert_no_sudo
    assert_eq "$(rpm_version tool)" none "installed version"
}

test_no_checksum_installs_when_user_agrees() {
    std_rpm_app tool 2.0.0 none
    run cli -y update tool <<< "y"
    assert_status 0
    assert_eq "$(rpm_version tool)" 2.0.0 "installed version"
}

test_verify_skip_installs_unattended() {
    std_rpm_app tool 2.0.0 none
    printf "VERIFY_CHECKSUM='skip'\n" >> "$APPS/tool.conf"
    run cli -y update tool
    assert_status 0
    assert_contains "Checksum verification is turned off for tool."
    assert_eq "$(rpm_version tool)" 2.0.0 "installed version"
}

test_verify_required_refuses_unverifiable_download() {
    std_rpm_app tool 2.0.0 none
    printf "VERIFY_CHECKSUM='required'\n" >> "$APPS/tool.conf"
    run cli -y update tool
    assert_failed
    assert_contains "VERIFY_CHECKSUM=required — not installing"
    assert_no_sudo
}

test_dnf_doing_nothing_is_a_failure() {
    std_rpm_app tool 2.0.0
    rpm_installed tool 1.0.0
    export MOCK_DNF_NOOP=1
    run cli -y update tool
    assert_failed
    assert_contains "Nothing changed: tool is still at 1.0.0 after the install command."
}

test_install_that_registers_nothing_is_a_failure() {
    std_rpm_app tool 2.0.0
    export MOCK_DNF_NOOP=1
    run cli -y update tool
    assert_failed
    assert_contains "'tool' is not installed according to rpm"
}

test_wrong_package_name_is_corrected() {
    std_rpm_app tool 2.0.0
    app_conf tool REPO=acme/tool TAG_PREFIX=v 'ASSET_REGEX=^tool-.*x86_64\.rpm$' PKG=tool-wrong
    run cli -y update tool
    assert_status 0
    assert_contains "This file is the package 'tool' (the config said 'tool-wrong'); config corrected."
    assert_file_contains "$APPS/tool.conf" "PKG='tool'"
    assert_eq "$(rpm_version tool)" 2.0.0 "installed version"
}

test_wrong_package_name_already_current_installs_nothing() {
    std_rpm_app tool 2.0.0
    rpm_installed tool 2.0.0
    app_conf tool REPO=acme/tool TAG_PREFIX=v 'ASSET_REGEX=^tool-.*x86_64\.rpm$' PKG=tool-wrong
    run cli -y update tool
    assert_status 0
    assert_contains "tool is already at 2.0.0"
    assert_file_contains "$APPS/tool.conf" "PKG='tool'"
    assert_no_sudo
}

test_update_all() {
    std_rpm_app aaa 2.0.0; rpm_installed aaa 1.0.0
    std_rpm_app bbb 2.0.0; rpm_installed bbb 2.0.0
    std_rpm_app ccc 3.1.0; rpm_installed ccc 3.0.0
    std_rpm_app ddd 1.0.0                                # not installed: not part of "update all"
    run cli -y update --all
    assert_status 0
    assert_contains "Will update: aaa ccc"
    assert_eq "$(rpm_version aaa)/$(rpm_version bbb)/$(rpm_version ccc)/$(rpm_version ddd)" "2.0.0/2.0.0/3.1.0/none" "versions"
}

test_update_all_reports_failures() {
    std_rpm_app aaa 2.0.0 "sha256:$(printf '0%.0s' {1..64})"; rpm_installed aaa 1.0.0
    std_rpm_app bbb 2.0.0; rpm_installed bbb 1.0.0
    run cli -y update --all
    assert_failed
    assert_contains "Failed: aaa"
    assert_eq "$(rpm_version bbb)" 2.0.0 "bbb still updated"
}

# Unattended run (cron, -y, no terminal): one program without a checksum must not stop the
# others from being updated, and the run must not report success.
test_update_all_unattended_continues_past_unverifiable_program() {
    std_rpm_app aaa 2.0.0 none; rpm_installed aaa 1.0.0
    std_rpm_app bbb 2.0.0;      rpm_installed bbb 1.0.0
    run cli -y update --all       # stdin is /dev/null
    assert_eq "$(rpm_version bbb)" 2.0.0 "bbb updated"
    assert_eq "$(rpm_version aaa)" 1.0.0 "aaa left alone"
    assert_contains "No answer (no input); taking that as no."
    assert_contains "Failed: aaa"
    assert_failed
}

test_update_one_unattended_unverifiable_program_fails() {
    std_rpm_app aaa 2.0.0 none; rpm_installed aaa 1.0.0
    run cli -y update aaa
    assert_failed
    assert_contains "aaa: not updated."
    assert_no_sudo
}

test_unattended_proceed_question_counts_as_no() {
    std_rpm_app tool 2.0.0; rpm_installed tool 1.0.0
    run cli update tool           # no -y, no input
    assert_contains "Skipped tool."
    assert_no_sudo
}

test_remove_uninstall_asks_even_with_y() {
    std_rpm_app tool 2.0.0; rpm_installed tool 2.0.0
    run cli -y remove tool <<< $'1\nn'
    assert_contains "This will run: sudo dnf remove -y tool. Continue? [y/N]"
    assert_contains "Cancelled."
    assert_exists "$APPS/tool.conf"
    assert_no_sudo
    run cli -y remove tool <<< $'1\ny'
    assert_status 0
    assert_file_contains "$MOCK_SUDO_LOG" "dnf remove -y tool"
    assert_eq "$(rpm_version tool)" none "installed version"
    assert_missing "$APPS/tool.conf"
}

test_remove_stop_tracking_keeps_program() {
    std_rpm_app tool 2.0.0; rpm_installed tool 2.0.0
    run cli remove tool <<< $'2\ny'
    assert_status 0
    assert_contains "No longer tracking tool."
    assert_missing "$APPS/tool.conf"
    assert_eq "$(rpm_version tool)" 2.0.0 "still installed"
    assert_no_sudo
}
