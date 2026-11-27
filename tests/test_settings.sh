# shellcheck shell=bash
# settings.conf: written with every setting commented out, and upgraded by adding new settings
# (commented out) without ever changing a value the user set.

active_settings() { grep -Ev '^[[:space:]]*(#|$)' "$CONF_DIR/settings.conf" || true; }

test_new_settings_file_has_everything_commented_out() {
    rm "$CONF_DIR/settings.conf"
    run cli list
    assert_status 0
    assert_eq "$(active_settings)" "" "active lines in a new settings.conf"
    local key
    for key in DOWNLOAD_DIR CLEAR_SCREEN BIN_DIR CACHE USE_GH_AUTH; do
        assert_file_contains "$CONF_DIR/settings.conf" "#${key}="
    done
    assert_not_contains "New settings were added"
    assert_not_contains "ignoring"
}

test_commented_defaults_match_the_built_in_ones() {
    rm "$CONF_DIR/settings.conf"
    run cli list
    # the values shown after "#KEY=" must be the ones the script really uses
    local key shown
    for key in DOWNLOAD_DIR CLEAR_SCREEN BIN_DIR CACHE USE_GH_AUTH; do
        shown=$(sed -n "s/^#${key}=//p" "$CONF_DIR/settings.conf")
        if [[ $shown == \~/* ]]; then shown="$HOME/${shown#\~/}"; fi
        assert_eq "$shown" "$(bash -c 'source "$1"; printf "%s" "${!2}"' _ "$RELUP" "$key")" "documented default of $key"
    done
}

test_defaults_apply_when_commented_out() {
    rm "$CONF_DIR/settings.conf"
    std_bin_app cli 1.2.0
    run cli update cli -n
    assert_status 0
    assert_contains "Would run: install -m 755 <downloaded cli-1.2.0-linux-x86_64.AppImage> $HOME/.local/bin/cli"
}

test_old_settings_file_gets_new_settings_without_changes() {
    cat > "$CONF_DIR/settings.conf" <<EOF
# relup settings (written by 0.2.1)
DOWNLOAD_DIR=$DL
CLEAR_SCREEN=no
EOF
    local before
    before=$(cat "$CONF_DIR/settings.conf")
    run cli list
    assert_status 0
    assert_contains "New settings were added to $CONF_DIR/settings.conf (commented out, nothing changed): BIN_DIR CACHE USE_GH_AUTH."
    [[ $(cat "$CONF_DIR/settings.conf") == "$before"* ]] || fail "existing lines were changed:\n$(cat "$CONF_DIR/settings.conf")"
    assert_eq "$(active_settings)" "DOWNLOAD_DIR=$DL"$'\n'"CLEAR_SCREEN=no" "active lines"
    assert_file_contains "$CONF_DIR/settings.conf" "# ---- Added by relup "
    assert_file_contains "$CONF_DIR/settings.conf" "#BIN_DIR=~/.local/bin"
    assert_file_contains "$CONF_DIR/settings.conf" "#USE_GH_AUTH=no"
    # second run: nothing more to add, no notice, no duplicates
    run cli list
    assert_not_contains "New settings were added"
    assert_eq "$(grep -c '^#CACHE=' "$CONF_DIR/settings.conf")" 1 "CACHE lines"
}

test_user_values_are_kept() {
    cat > "$CONF_DIR/settings.conf" <<EOF
DOWNLOAD_DIR=$DL
CLEAR_SCREEN=no
BIN_DIR=$T/mybin
CACHE=no
USE_GH_AUTH=no
EOF
    std_bin_app cli 1.2.0
    run cli update cli -n
    assert_contains "$T/mybin/cli"
    assert_not_contains "New settings were added"
}

test_setting_commented_out_by_user_is_not_added_again() {
    cat > "$CONF_DIR/settings.conf" <<EOF
DOWNLOAD_DIR=$DL
CLEAR_SCREEN=no
# BIN_DIR=/opt/bin
#CACHE=no
USE_GH_AUTH=no
EOF
    run cli list
    assert_not_contains "New settings were added"
    assert_eq "$(grep -c 'BIN_DIR' "$CONF_DIR/settings.conf")" 1 "BIN_DIR lines"
}

test_unknown_setting_is_left_in_place() {
    printf 'OLD_SETTING=1\n' >> "$CONF_DIR/settings.conf"
    run cli list
    assert_contains "ignoring unknown setting 'OLD_SETTING'"
    assert_file_contains "$CONF_DIR/settings.conf" "OLD_SETTING=1"
}

test_read_only_settings_file_is_not_touched() {
    printf 'DOWNLOAD_DIR=%s\nCLEAR_SCREEN=no\n' "$DL" > "$CONF_DIR/settings.conf"
    chmod 444 "$CONF_DIR/settings.conf"
    run cli list
    assert_status 0
    assert_not_contains "New settings were added"
    assert_eq "$(wc -l < "$CONF_DIR/settings.conf")" 2 "lines"
}

test_menu_shows_new_settings_notice() {
    printf 'DOWNLOAD_DIR=%s\nCLEAR_SCREEN=no\n' "$DL" > "$CONF_DIR/settings.conf"
    std_rpm_app tool 2.0.0
    run cli <<< 'q'
    assert_contains "relup "
    assert_contains "New settings were added"
}
