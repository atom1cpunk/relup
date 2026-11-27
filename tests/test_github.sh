# shellcheck shell=bash
# GitHub API handling: choosing a release, the ETag cache, rate limits, authentication.

test_latest_release_skips_drafts_prereleases_and_other_products() {
    local r=acme/ente
    set_releases "$r" \
        "$(mk_release auth-v9.0.0 --draft "$(mk_asset $r auth-v9.0.0 ente-auth-9.0.0-x86_64.rpm "$(fake_rpm enteauth 9.0.0)")")" \
        "$(mk_release auth-v8.0.0 --pre "$(mk_asset $r auth-v8.0.0 ente-auth-8.0.0-x86_64.rpm "$(fake_rpm enteauth 8.0.0)")")" \
        "$(mk_release desktop-v7.0.0 "$(mk_asset $r desktop-v7.0.0 ente-7.0.0-x86_64.rpm "$(fake_rpm ente 7.0.0)")")" \
        "$(mk_release auth-v6.0.0 "$(mk_asset $r auth-v6.0.0 ente-auth-6.0.0.dmg "mac")")" \
        "$(mk_release auth-v5.0.0 --date 2026-10-01 "$(mk_asset $r auth-v5.0.0 ente-auth-5.0.0-x86_64.rpm "$(fake_rpm enteauth 5.0.0)")")"
    app_conf enteauth REPO=$r TAG_PREFIX=auth-v 'ASSET_REGEX=x86_64.*\.rpm$' PKG=enteauth
    rpm_installed enteauth 4.0.0
    run cli check
    assert_status 0
    assert_line '^1 +enteauth +4\.0\.0 +5\.0\.0 +2026-10-01 +[0-9]{4}-[0-9]{2}-[0-9]{2} +update available$'
}

test_latest_release_found_on_page_two() {
    local r=acme/mono page1
    # page 1: 100 releases of another product in the same repo
    page1=$(jq -nc '[range(100) | {tag_name: "web-v\(1000 - .).0", draft: false, prerelease: false,
                     published_at: "2026-11-01T00:00:00Z",
                     assets: [{name: "web-\(1000 - .).0.zip", browser_download_url: "https://x/y", size: 1}]}]')
    api_set "repos/$r/releases?per_page=100" "$page1"
    set_releases $r --page 2 "$(mk_release cli-v2.5.0 "$(mk_asset $r cli-v2.5.0 cli-2.5.0.rpm "$(fake_rpm cli 2.5.0)")")"
    app_conf cli REPO=$r TAG_PREFIX=cli-v 'ASSET_REGEX=^cli-.*\.rpm$' PKG=cli
    run cli check
    assert_line '^1 +cli +none +2\.5\.0 .*not installed$'
    grep -q 'page=2' "$MOCK_LOG" || fail "page 2 was not requested"
    ! grep -q 'page=3' "$MOCK_LOG" || fail "page 3 was requested although page 2 matched"
}

test_short_page_stops_the_search() {
    std_rpm_app tool 2.0.0
    app_conf tool REPO=acme/tool TAG_PREFIX=nomatch-v 'ASSET_REGEX=\.rpm$' PKG=tool
    run cli check
    assert_contains "tool: no release found with a file matching ASSET_REGEX"
    assert_eq "$(api_requests)" 1 "API requests"
}

test_invalid_asset_regex_is_reported() {
    std_rpm_app tool 2.0.0
    app_conf tool REPO=acme/tool TAG_PREFIX=v 'ASSET_REGEX=(unclosed' PKG=tool
    run cli check
    assert_contains "could not evaluate ASSET_REGEX"
    assert_line '^1 +tool .*error$'
}

test_unknown_repo_is_reported() {
    app_conf ghost REPO=acme/ghost 'ASSET_REGEX=\.rpm$' PKG=ghost
    run cli check
    assert_contains "Not found on GitHub: repos/acme/ghost/releases"
    assert_line '^1 +ghost .*error$'
}

test_etag_cache_makes_second_request_conditional() {
    std_rpm_app tool 2.0.0
    run cli check
    assert_status 0
    ! grep -qi 'if-none-match' "$MOCK_LOG" || fail "first request was conditional"
    : > "$MOCK_LOG"
    run cli check
    assert_status 0
    grep -qi 'if-none-match: "' "$MOCK_LOG" || fail "second request did not send If-None-Match:\n$(cat "$MOCK_LOG")"
    assert_line '^1 +tool +none +2\.0\.0 '      # 304 answered from the cache
}

test_cache_picks_up_changes() {
    std_rpm_app tool 2.0.0
    run cli check
    std_rpm_app tool 2.1.0          # new release: new body, new ETag
    run cli check
    assert_line '^1 +tool +none +2\.1\.0 '
}

test_rate_limit_falls_back_to_cache() {
    std_rpm_app tool 2.0.0
    run cli check
    touch "$MOCK_GH/ratelimit"
    run cli check
    assert_contains "API limit was reached; using the last saved data for repos/acme/tool/releases"
    assert_line '^1 +tool +none +2\.0\.0 '
}

test_rate_limit_without_cache_is_an_error() {
    std_rpm_app tool 2.0.0
    touch "$MOCK_GH/ratelimit"
    run cli check
    assert_contains "GitHub refused the request (API rate limit?"
    assert_line '^1 +tool .*error$'
}

test_cache_can_be_turned_off() {
    write_settings no
    std_rpm_app tool 2.0.0
    run cli check
    run cli check
    ! grep -qi 'if-none-match' "$MOCK_LOG" || fail "a conditional request was sent with CACHE=no"
    [[ -z $(find "$XDG_CACHE_HOME" -type f 2>/dev/null) ]] || fail "cache files were written with CACHE=no"
}

test_old_cache_entries_are_pruned() {
    mkdir -p "$XDG_CACHE_HOME/relup"
    touch -d '40 days ago' "$XDG_CACHE_HOME/relup/old.json"
    touch "$XDG_CACHE_HOME/relup/new.json"
    run cli list
    assert_missing "$XDG_CACHE_HOME/relup/old.json"
    assert_exists "$XDG_CACHE_HOME/relup/new.json"
}

test_token_sent_to_api_only() {
    std_rpm_app tool 2.0.0
    export GITHUB_TOKEN=secret-token-123
    run cli -y update tool
    assert_status 0
    grep '^https://api.github.com/' "$MOCK_LOG" | grep -q 'Authorization: Bearer secret-token-123' \
        || fail "API request without the token:\n$(cat "$MOCK_LOG")"
    ! download_requests | grep -q secret-token-123 || fail "token sent to a download host:\n$(cat "$MOCK_LOG")"
    [[ -n $(download_requests) ]] || fail "no download happened"
}

test_no_token_no_auth_header() {
    std_rpm_app tool 2.0.0
    run cli check
    ! grep -qi authorization "$MOCK_LOG" || fail "an Authorization header was sent without a token"
}

test_network_failure_is_reported() {
    std_rpm_app tool 2.0.0
    touch "$MOCK_GH/offline"
    run cli check
    assert_contains "Could not reach GitHub (network problem?)"
    assert_line '^1 +tool .*error$'
}
