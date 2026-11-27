# shellcheck shell=bash
# Unit tests: relup's functions called directly (the script is sourced, main does not run).

test_version_compare() {
    load_relup
    assert_eq "$(version_norm v1.2.3+45)" 1.2.3 "version_norm"
    assert_true  version_ge 1.10.0 1.9.0
    assert_false version_ge 1.9.0 1.10.0
    assert_true  version_ge v2.0 2.0
    assert_true  version_ge 1.19.0+65 1.19.0          # build metadata ignored
    assert_true  version_ge 1.19.0 1.19.0+65
    assert_true  version_ge 3.0.0 2.0.0               # newer installed counts as up to date
    assert_false version_ge none 1.0
    assert_false version_ge unknown 1.0
    assert_false version_ge 1.0 none
    assert_false version_ge "?" 1.0
}

test_parse_conf_reads_data_and_never_runs_it() {
    load_relup
    cat > "$T/x.conf" <<'EOF'
# a comment
   # an indented comment

NAME='Hello World'
REPO="acme/tool"
TAG_PREFIX=  v
DEST_DIR='~/apps'
ASSET_REGEX='$(touch PWNED)`touch PWNED2`'
EVIL='x'
this is not a setting
EOF
    local NAME="" REPO="" TAG_PREFIX="" DEST_DIR="" ASSET_REGEX="" err
    err=$(parse_conf "$T/x.conf" "$APP_KEYS" 2>&1 >/dev/null)
    parse_conf "$T/x.conf" "$APP_KEYS" 2>/dev/null
    assert_eq "$NAME" "Hello World" NAME
    assert_eq "$REPO" "acme/tool" REPO
    assert_eq "$TAG_PREFIX" "v" TAG_PREFIX
    assert_eq "$DEST_DIR" "$HOME/apps" "DEST_DIR (~ expanded)"
    # shellcheck disable=SC2016  # the literal text is the point
    assert_eq "$ASSET_REGEX" '$(touch PWNED)`touch PWNED2`' "ASSET_REGEX kept literally"
    assert_missing "$T/PWNED"
    assert_missing "$T/PWNED2"
    [[ -z ${EVIL:-} ]] || fail "an unknown key was set"
    [[ $err == *"ignoring unknown setting 'EVIL'"* ]] || fail "no warning for EVIL: $err"
    [[ $err == *"cannot parse line: this is not a setting"* ]] || fail "no warning for bad line: $err"
}

test_load_app_validation() {
    load_relup
    local conf
    check_bad() {  # check_bad <expected-message> KEY=value...
        local want=$1; shift
        app_conf bad "$@"
        if output=$(load_app bad 2>&1); then fail "load_app accepted a config with: $*"; fi
        [[ $output == *"$want"* ]] || fail "expected '$want', got: $output"
    }
    conf=(REPO=acme/tool ASSET_REGEX=x INSTALL=rpm PKG=tool)
    app_conf good "${conf[@]}"
    assert_true load_app good
    check_bad "REPO must look like owner/repo" REPO=acme ASSET_REGEX=x
    check_bad "ASSET_REGEX is empty" REPO=acme/tool
    check_bad "INSTALL 'deb' is not supported" REPO=acme/tool ASSET_REGEX=x INSTALL=deb
    check_bad "INSTALL 'rpm;rm' is not supported" REPO=acme/tool ASSET_REGEX=x 'INSTALL=rpm;rm'
    check_bad "SOURCE 'gitlab' is not supported" REPO=acme/tool ASSET_REGEX=x SOURCE=gitlab
    check_bad "VERIFY_CHECKSUM must be" REPO=acme/tool ASSET_REGEX=x VERIFY_CHECKSUM=maybe
    check_bad "PKG is missing" REPO=acme/tool ASSET_REGEX=x 'PKG=-rf'
    check_bad "DEST_DIR must be an absolute path" REPO=acme/tool ASSET_REGEX=x INSTALL=binary DEST_DIR=bin
    check_bad "BIN_NAME is missing" REPO=acme/tool ASSET_REGEX=x INSTALL=binary 'BIN_NAME=../x'
    if output=$(load_app '../etc/passwd' 2>&1); then fail "load_app accepted a path as an id"; fi
}

test_build_asset_regex() {
    load_relup
    local re
    re=$(build_asset_regex brave-browser-1.85.118-1.x86_64.rpm 1.85.118)
    assert_eq "$re" '^brave-browser-[0-9][0-9.]*-1\.x86_64\.rpm$' "brave regex"
    jq -en --arg re "$re" '"brave-browser-1.86.2-1.x86_64.rpm" | test($re)' >/dev/null || fail "regex misses the next version"
    jq -en --arg re "$re" '"brave-browser-1.86.2-1.aarch64.rpm" | test($re) | not' >/dev/null || fail "regex matches another arch"
    # the version appears inside a longer number: kept literally
    assert_eq "$(build_asset_regex app-1.2.3.AppImage 1.2)" '^app-1\.2\.3\.AppImage$' "longer number"
    assert_eq "$(build_asset_regex tool-linux-amd64 "")" '^tool-linux-amd64$' "no version"
    assert_eq "$(build_asset_regex 'a+b(1.0).rpm' 1.0)" '^a\+b\([0-9][0-9.]*\)\.rpm$' "special characters"
}

test_parse_repo_input() {
    load_relup
    assert_true parse_repo_input "https://github.com/brave/brave-browser/releases"
    assert_eq "$W_REPO|$W_TAG|$W_USER" "brave/brave-browser||" "releases URL"
    assert_true parse_repo_input "github.com/ente-io/ente/releases/tag/auth-v4.4.4"
    assert_eq "$W_REPO|$W_TAG" "ente-io/ente|auth-v4.4.4" "tag URL"
    assert_true parse_repo_input "  owner/repo.git  "
    assert_eq "$W_REPO" "owner/repo" "owner/repo.git with spaces"
    assert_true parse_repo_input "https://www.github.com/a/b?tab=readme#top"
    assert_eq "$W_REPO" "a/b" "query and fragment"
    assert_true parse_repo_input "someuser"
    assert_eq "$W_USER|$W_REPO" "someuser|" "username only"
    assert_false parse_repo_input "bad user!/x"
    assert_false parse_repo_input "-oops/x"
    assert_false parse_repo_input "a/b c"
}

test_derived_names() {
    load_relup
    assert_eq "$(default_name_from_asset LocalSend-1.19.0-linux-x86-64.rpm)" "LocalSend"
    assert_eq "$(default_name_from_asset brave-browser-1.85.118-1.x86_64.rpm)" "Brave Browser"
    assert_eq "$(default_name_from_asset tool-linux-amd64)" "Tool"
    assert_eq "$(default_name_from_asset Obsidian-1.7.7.AppImage)" "Obsidian"
    assert_eq "$(slugify "Brave Browser")" "brave-browser"
    assert_eq "$(slugify "  Ente Auth!! ")" "ente-auth"
    assert_eq "$(clean_value "it's"$'\n'"two")" "its two" "clean_value"
}

test_extract_hash() {
    load_relup
    local a b
    a=$(printf 'a%.0s' {1..64}); b=$(printf 'b%.0s' {1..64})
    printf '%s  tool-1.0.rpm\n%s *other-1.0.rpm\n' "$a" "$b" > "$T/SUMS"
    assert_eq "$(extract_hash "$T/SUMS" tool-1.0.rpm 0)" "$a" "first line"
    assert_eq "$(extract_hash "$T/SUMS" other-1.0.rpm 0)" "$b" "binary-mode marker"
    assert_eq "$(extract_hash "$T/SUMS" missing.rpm 0)" "" "not listed"
    printf '%s\n' "$a" > "$T/side.sha256"     # sidecar with only a hash in it
    assert_eq "$(extract_hash "$T/side.sha256" tool-1.0.rpm 1)" "$a" "sidecar"
    assert_eq "$(extract_hash "$T/side.sha256" tool-1.0.rpm 0)" "" "bare hash only trusted from a sidecar"
}

# A checksum list often names files whose names contain each other (a binary and its archive,
# its .sig, its .zsync). The line for the exact file must be used, wherever it is in the list.
test_extract_hash_uses_exact_file_name() {
    load_relup
    local a b
    a=$(printf 'a%.0s' {1..64}); b=$(printf 'b%.0s' {1..64})
    printf '%s  tool-linux-amd64.tar.gz\n%s  tool-linux-amd64\n' "$a" "$b" > "$T/checksums.txt"
    assert_eq "$(extract_hash "$T/checksums.txt" tool-linux-amd64 0)" "$b" "hash for tool-linux-amd64"
    assert_eq "$(extract_hash "$T/checksums.txt" tool-linux-amd64.tar.gz 0)" "$a" "hash for the archive"
    printf 'SHA256 (tool-linux-amd64.sig) = %s\nSHA256 (tool-linux-amd64) = %s\n' "$a" "$b" > "$T/bsd.txt"
    assert_eq "$(extract_hash "$T/bsd.txt" tool-linux-amd64 0)" "$b" "BSD style"
    printf '%s  ./dist/tool-linux-amd64.zsync\n%s  ./dist/tool-linux-amd64\n' "$a" "$b" > "$T/paths.txt"
    assert_eq "$(extract_hash "$T/paths.txt" tool-linux-amd64 0)" "$b" "with a folder in front"
}

test_set_conf_value() {
    load_relup
    printf "# comment\nPKG='old'\nNAME='X'\n" > "$T/a.conf"
    chmod 600 "$T/a.conf"
    set_conf_value "$T/a.conf" PKG "new'name"
    set_conf_value "$T/a.conf" BIN_NAME tool
    assert_eq "$(cat "$T/a.conf")" "# comment"$'\n'"PKG='newname'"$'\n'"NAME='X'"$'\n'"BIN_NAME='tool'" "rewritten file"
    assert_eq "$(stat -c %a "$T/a.conf")" 600 "permissions"
}

test_looks_like_program() {
    load_relup
    fake_elf 1 > "$T/elf"; fake_script 1 > "$T/sh"; printf 'PK\003\004zip' > "$T/zip"; : > "$T/empty"
    assert_true  looks_like_program "$T/elf"
    assert_true  looks_like_program "$T/sh"
    assert_false looks_like_program "$T/zip"
    assert_false looks_like_program "$T/empty"
}

test_wizard_file_filtering() {
    load_relup
    asset_names() { asset_rows "$1" "$2" | cut -f1 | tr '\n' ' '; }
    W_RELEASE=$(jq -nc '{assets: [ $ARGS.positional[] | {name: ., size: 100, url: ("https://x/" + .)} ]}' --args \
        app-1.0-1.x86_64.rpm app-1.0-1.aarch64.rpm app-1.0-linux-x86_64.AppImage app-1.0-linux-aarch64.AppImage \
        app-1.0-windows-x64.exe app-1.0-darwin-arm64.dmg app-1.0-linux-x86_64.tar.gz SHA256SUMS \
        app-1.0-linux-x86_64.AppImage.sig app-1.0-linux-x86_64.AppImage.zsync app-1.0.deb)
    assert_eq "$(asset_names rpm "")" "app-1.0-1.x86_64.rpm app-1.0-1.aarch64.rpm " "rpm files"
    assert_eq "$(asset_names binary "")" "app-1.0-linux-x86_64.AppImage app-1.0-linux-aarch64.AppImage " "single-file programs"
    assert_eq "$(asset_names binary 'x86[_-]64|amd64|x64')" "app-1.0-linux-x86_64.AppImage " "host arch"

    # no file says "linux": other operating systems are dropped by name instead
    W_RELEASE=$(jq -nc '{assets: [ $ARGS.positional[] | {name: ., size: 100, url: ("https://x/" + .)} ]}' --args \
        tool-amd64 tool-darwin-amd64 tool-windows-amd64.exe tool.sh.sha256 install.sh)
    assert_eq "$(asset_names binary "")" "tool-amd64 install.sh " "no linux in names"
}

test_checksum_candidates() {
    load_relup
    LATEST_NAME=app.AppImage
    LATEST_JSON=$(jq -nc '{assets: [
        {name: "app.AppImage", size: 5000000, url: "u/app.AppImage"},
        {name: "SHA256SUMS", size: 300, url: "u/SHA256SUMS"},
        {name: "SHA256SUMS.sig", size: 300, url: "u/SHA256SUMS.sig"},
        {name: "huge-checksums.txt", size: 3000000, url: "u/huge-checksums.txt"},
        {name: "app.AppImage.sha256", size: 80, url: "u/app.AppImage.sha256"} ]}')
    assert_eq "$(checksum_candidates | tr '\n' ' ')" "u/app.AppImage.sha256 u/SHA256SUMS " "candidates, sidecar first"
}

test_fmt_size() {
    load_relup
    assert_eq "$(fmt_size 1)" "1 KB"
    assert_eq "$(fmt_size 49152)" "48 KB"
    assert_eq "$(fmt_size $((150 * 1048576 + 5)))" "150 MB"
}
