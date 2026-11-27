# shellcheck shell=bash
# The interactive menu: "b" goes back to the menu and "q" quits at every question, and slow
# steps show a live status line in a terminal.

menu_count() { grep -c '— GitHub release updater' <<< "$output" || true; }

test_menu_pick_program_back_and_quit() {
    std_rpm_app tool 2.0.0; rpm_installed tool 1.0.0
    run cli <<< $'2\nb\nq'
    assert_status 0
    assert_contains "Program number (or id) (b = menu, q = quit): "
    assert_eq "$(menu_count)" 2 "menus shown"
    assert_not_contains "Press Enter"
    run cli <<< $'2\nq'
    assert_status 0
    assert_eq "$(menu_count)" 1 "menus shown"
    assert_no_sudo
}

test_menu_pick_program_asks_again() {
    std_rpm_app tool 2.0.0; rpm_installed tool 1.0.0
    run cli <<< $'2\n9\nnope\nb\nq'
    assert_contains "Please enter a number from 1 to 1, or a program id."
    assert_eq "$(grep -c 'Please enter' <<< "$output")" 2 "re-asks"
}

test_menu_yes_no_questions_offer_back() {
    std_rpm_app tool 2.0.0; rpm_installed tool 1.0.0
    run cli <<< $'2\n1\nb\nq'                      # "Proceed?" for one program
    assert_contains "Proceed? [y/N, b = menu, q = quit] "
    assert_eq "$(menu_count)" 2 "menus shown"
    assert_not_contains "Press Enter"
    run cli <<< $'3\nb\nq'                         # "Proceed with all?"
    assert_contains "Proceed with all? [y/N, b = menu, q = quit] "
    assert_eq "$(menu_count)" 2 "menus shown"
    assert_no_sudo
}

test_menu_back_stops_update_all() {
    std_rpm_app aaa 2.0.0 none; rpm_installed aaa 1.0.0
    std_rpm_app bbb 2.0.0;      rpm_installed bbb 1.0.0
    run cli <<< $'3\ny\nb\nq'                      # back at aaa's "Install it anyway?"
    assert_contains "Install it anyway? [y/N, b = menu, q = quit]"
    assert_eq "$(rpm_version bbb)" 1.0.0 "bbb not updated after going back"
    assert_eq "$(menu_count)" 2 "menus shown"
}

test_menu_remove_back_and_quit() {
    std_rpm_app tool 2.0.0; rpm_installed tool 2.0.0
    run cli <<< $'7\n1\nb\nq'                      # back at "1) uninstall / 2) stop tracking"
    assert_contains "Choice (b = menu, q = quit): "
    assert_not_contains "c) Cancel"
    assert_exists "$APPS/tool.conf"
    run cli <<< $'7\n1\n1\nq'                      # quit at the uninstall confirmation
    assert_status 0
    assert_contains "Continue? [y/N, b = menu, q = quit]"
    assert_exists "$APPS/tool.conf"
    assert_no_sudo
}

test_menu_add_back_and_quit() {
    std_rpm_app tool 2.0.0
    run cli <<< $'5\nb\nq'
    assert_contains "GitHub URL, owner/repo or username (b = menu, q = quit): "
    assert_eq "$(menu_count)" 2 "menus shown"
    run cli <<< $'5\nacme/tool\n1\n1\nq'            # quit at the wizard's confirmation
    assert_status 0
    assert_contains "Track this program? [Y/n, b = menu, q = quit]"
    assert_eq "$(ls "$APPS")" "tool.conf" "no new config"
}

test_menu_first_run_back() {
    run cli <<< $'b\nq'
    assert_contains "Add your first program now? [Y/n, b = menu, q = quit]"
    assert_not_contains "Press Enter"
    assert_eq "$(menu_count)" 1 "menus shown"
}

test_command_line_choices_still_cancel_with_q() {
    std_rpm_app tool 2.0.0; rpm_installed tool 2.0.0
    run cli remove tool <<< 'q'
    assert_contains "Choice (q to cancel): "
    assert_contains "Cancelled."
    assert_exists "$APPS/tool.conf"
    run cli remove tool <<< $'1\nb'               # outside the menu "b" is just "no"
    assert_contains "Continue? [y/N] "
    assert_exists "$APPS/tool.conf"
    assert_no_sudo
}

test_progress_line_in_terminal() {
    skip_without_python
    std_rpm_app aaa 2.0.0
    std_rpm_app bbb 2.0.0
    run_tty bash "$RELUP" check
    assert_status 0
    assert_contains "Checking for updates 1/2: aaa..."
    assert_contains "Checking for updates 2/2: bbb..."
    assert_contains $'\r\e[K'                     # the line is cleared before the table
    assert_contains "PROGRAM"
}

test_progress_line_gives_way_to_warnings() {
    skip_without_python
    std_rpm_app aaa 2.0.0
    app_conf aaa REPO=acme/aaa TAG_PREFIX=nomatch 'ASSET_REGEX=x' PKG=aaa
    run_tty bash "$RELUP" check
    assert_contains $'aaa...\r\e[K'               # cleared, so the error starts on a clean line
    assert_contains "aaa: no release found"
}

test_no_progress_line_without_terminal() {
    std_rpm_app aaa 2.0.0
    run cli check
    assert_not_contains "Checking for updates"
    assert_not_contains $'\e['
}
