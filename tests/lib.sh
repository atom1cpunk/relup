# shellcheck shell=bash
# Shared helpers for the relup tests: a fresh fake HOME per test, fixture builders and assertions.
# The real jq, sha256sum, coreutils etc. are used; only curl, rpm and sudo are mocked (tests/mocks).

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$TESTS_DIR/.." && pwd)
RELUP="$ROOT/relup"

# ---------- environment ----------
setup_env() {
    T=$(mktemp -d "${TEST_TMP_ROOT:?}/t.XXXXXX")
    export HOME="$T/home"
    export XDG_CONFIG_HOME="$T/config" XDG_CACHE_HOME="$T/cache" XDG_STATE_HOME="$T/state"
    export TMPDIR="$T/tmp"
    export MOCK_GH="$T/gh" MOCK_RPMDB="$T/rpmdb" MOCK_LOG="$T/curl.log" MOCK_SUDO_LOG="$T/sudo.log"
    unset GITHUB_TOKEN VISUAL EDITOR MOCK_DNF_NOOP MOCK_SUDO_UNLOCK
    CONF_DIR="$XDG_CONFIG_HOME/relup"; APPS="$CONF_DIR/apps.d"; BIN="$HOME/.local/bin"
    DL="$T/dl"; STATE="$XDG_STATE_HOME/relup/installed"
    mkdir -p "$HOME" "$TMPDIR" "$MOCK_GH/api" "$MOCK_GH/web" "$MOCK_RPMDB" "$DL" "$APPS" "$BIN"
    : > "$MOCK_LOG"; : > "$MOCK_SUDO_LOG"
    export PATH="$TESTS_DIR/mocks:$BIN:${ORIG_PATH:?}"
    cd "$T" || exit 1
    write_settings
}

write_settings() {  # write_settings [CACHE=yes|no]
    cat > "$CONF_DIR/settings.conf" <<EOF
DOWNLOAD_DIR=$DL
CLEAR_SCREEN=no
BIN_DIR=~/.local/bin
CACHE=${1:-yes}
USE_GH_AUTH=no
EOF
}

load_relup() {  # source the script to call its functions directly
    # shellcheck source=../relup
    source "$RELUP"
    set +e   # keep -u and pipefail from relup, but let assertions report failures themselves
    parse_conf "$SETTINGS_FILE" "$SETTINGS_KEYS"
}

# ---------- running ----------
status=0; output=""
run() { status=0; output=$("$@" 2>&1) || status=$?; }
cli() { bash "$RELUP" "$@"; }

# ---------- fixtures ----------
api_set() {  # api_set <api-path> <json> [etag]   (an ETag is made up when none is given)
    local key
    key=$(printf '%s' "$1" | sed 's#[/?&=]#_#g')
    printf '%s' "$2" > "$MOCK_GH/api/$key.json"
    printf '%s' "${3:-\"$(printf '%s' "$2" | sha256sum | cut -c1-16)\"}" > "$MOCK_GH/api/$key.etag"
}

fake_rpm() { printf 'FAKERPM\nNAME=%s\nVERSION=%s\n' "$1" "$2"; }
fake_elf() { printf '\177ELF fake program %s\n' "$1"; }
fake_script() { printf '#!/bin/sh\necho %s\n' "$1"; }
sha_of() { printf '%s' "$1" | sha256sum | cut -d' ' -f1; }

# mk_asset <owner/repo> <tag> <name> <content> [digest: auto|none|sha256:...]  -> GitHub asset JSON
mk_asset() {
    local repo=$1 tag=$2 name=$3 content=$4 dmode=${5:-auto} f url size digest=""
    url="https://github.com/${repo}/releases/download/${tag}/${name}"
    f="$MOCK_GH/web/${url#https://}"
    mkdir -p "${f%/*}"
    printf '%s' "$content" > "$f"
    size=$(stat -c %s "$f")
    case $dmode in
        auto) digest="sha256:$(sha256sum "$f" | cut -d' ' -f1)" ;;
        none) digest="" ;;
        *)    digest=$dmode ;;
    esac
    jq -nc --arg n "$name" --arg u "$url" --argjson s "$size" --arg d "$digest" \
        '{name: $n, browser_download_url: $u, size: $s} + (if $d == "" then {} else {digest: $d} end)'
}

# mk_release <tag> [--draft] [--pre] [--date YYYY-MM-DD] [asset-json...]  -> GitHub release JSON
mk_release() {
    local tag=$1 draft=false pre=false date=2026-11-20
    shift
    while (($#)); do
        case $1 in
            --draft) draft=true ;;
            --pre)   pre=true ;;
            --date)  date=$2; shift ;;
            *) break ;;
        esac
        shift
    done
    printf '%s\n' "$@" | jq -sc --arg t "$tag" --argjson d "$draft" --argjson p "$pre" --arg dt "${date}T10:00:00Z" \
        '{tag_name: $t, draft: $d, prerelease: $p, published_at: $dt, assets: [.[] | select(. != null)]}'
}

# set_releases <owner/repo> [--page N] [release-json...]
set_releases() {
    local repo=$1 path
    shift
    path="repos/${repo}/releases?per_page=100"
    if [[ ${1:-} == --page ]]; then
        if (($2 > 1)); then path+="&page=$2"; fi
        shift 2
    fi
    api_set "$path" "$(printf '%s\n' "$@" | jq -sc '[.[] | select(. != null)]')"
}

rpm_installed() { printf '%s %s\n' "$2" "${3:-1764000000}" > "$MOCK_RPMDB/$1"; }   # rpm_installed <pkg> <version>
rpm_version() { if [[ -f $MOCK_RPMDB/$1 ]]; then cut -d' ' -f1 "$MOCK_RPMDB/$1"; else echo none; fi; }

app_conf() {  # app_conf <id> KEY=value...
    local id=$1 kv
    shift
    : > "$APPS/$id.conf"
    for kv in "$@"; do printf "%s='%s'\n" "${kv%%=*}" "${kv#*=}" >> "$APPS/$id.conf"; done
}

# A typical rpm program: acme/<id>, tags v<version>, file <id>-<version>-1.x86_64.rpm, package <id>
std_rpm_app() {  # std_rpm_app <id> <latest-version> [digest-mode]
    local id=$1 ver=$2
    set_releases "acme/$id" \
        "$(mk_release "v$ver" "$(mk_asset "acme/$id" "v$ver" "$id-$ver-1.x86_64.rpm" "$(fake_rpm "$id" "$ver")" "${3:-auto}")")" \
        "$(mk_release "v0.9.0" --date 2026-01-01 "$(mk_asset "acme/$id" v0.9.0 "$id-0.9.0-1.x86_64.rpm" "$(fake_rpm "$id" 0.9.0)")")"
    app_conf "$id" NAME="$id" SOURCE=github REPO="acme/$id" TAG_PREFIX=v \
        'ASSET_REGEX=^'"$id"'-[0-9][0-9.]*-1\.x86_64\.rpm$' INSTALL=rpm PKG="$id" VERIFY_CHECKSUM=auto
}

# A typical single-file program: acme/<id>, file <id>-<version>-linux-x86_64.AppImage
std_bin_app() {  # std_bin_app <id> <latest-version> [content]
    local id=$1 ver=$2
    set_releases "acme/$id" \
        "$(mk_release "v$ver" "$(mk_asset "acme/$id" "v$ver" "$id-$ver-linux-x86_64.AppImage" "${3:-$(fake_elf "$ver")}")")"
    app_conf "$id" NAME="$id" SOURCE=github REPO="acme/$id" TAG_PREFIX=v \
        'ASSET_REGEX=^'"$id"'-[0-9][0-9.]*-linux-x86_64\.AppImage$' INSTALL=binary BIN_NAME="$id" VERIFY_CHECKSUM=auto
}

api_requests() { grep -c '^https://api.github.com/' "$MOCK_LOG" || true; }
download_requests() { grep -v '^https://api.github.com/' "$MOCK_LOG" || true; }

# ---------- assertions ----------
fail() {
    printf 'FAIL: %b\n' "$*"
    if [[ -n $output ]]; then printf -- '--- output of the last command (exit %s) ---\n%s\n---\n' "$status" "$output"; fi
    exit 1
}
assert_eq()       { [[ $1 == "$2" ]] || fail "${3:-value}: expected [$2], got [$1]"; }
assert_status()   { [[ $status -eq $1 ]] || fail "expected exit status $1, got $status"; }
assert_failed()   { [[ $status -ne 0 ]] || fail "expected a non-zero exit status"; }
assert_true()     { "$@" || fail "expected success: $*"; }
assert_false()    { ! "$@" || fail "expected failure: $*"; }
assert_contains() { [[ $output == *"$1"* ]] || fail "output should contain: $1"; }
assert_not_contains() { [[ $output != *"$1"* ]] || fail "output should not contain: $1"; }
assert_line()     { grep -Eq -- "$1" <<< "$output" || fail "no output line matches: $1"; }
assert_file_contains() { grep -Fq -- "$2" "$1" 2>/dev/null || fail "$1 should contain: $2\n$(cat "$1" 2>/dev/null)"; }
assert_file_lacks()    { ! grep -Fq -- "$2" "$1" 2>/dev/null || fail "$1 should not contain: $2"; }
assert_exists()   { [[ -e $1 ]] || fail "missing: $1"; }
assert_missing()  { [[ ! -e $1 ]] || fail "should not exist: $1"; }
assert_no_sudo()  { [[ ! -s $MOCK_SUDO_LOG ]] || fail "sudo should not have run, but ran:\n$(cat "$MOCK_SUDO_LOG")"; }

# run_tty <command...>: like run, but inside a pseudo-terminal, for output that only appears in a
# terminal (progress lines, colours). Needs python3; tests call skip_without_python first.
run_tty() {
    status=0
    output=$(python3 -I -c '
import os, pty, sys
pid, fd = pty.fork()
if pid == 0:
    os.execvp(sys.argv[1], sys.argv[1:])
out = b""
while True:
    try:
        chunk = os.read(fd, 4096)
    except OSError:
        break
    if not chunk:
        break
    out += chunk
_, st = os.waitpid(pid, 0)
sys.stdout.write(out.decode("utf-8", "replace"))
sys.exit(os.waitstatus_to_exitcode(st))
' "$@") || status=$?
}
skip_without_python() { command -v python3 >/dev/null || { echo "skipped: python3 not installed"; exit 0; }; }
