#!/usr/bin/env bash
# Runs the relup test suite.
#
#   tests/run.sh               run every test
#   tests/run.sh <pattern>     run only tests whose name contains <pattern>
#   tests/run.sh -v ...        also show the output of passing tests
#
# Each test_* function runs in its own subshell with a fresh fake HOME, config, cache and state
# folders, and with tests/mocks first in PATH (fake curl, rpm and sudo). Nothing touches the
# real system, the network, or your real relup config.
set -uo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
verbose=0
if [[ ${1:-} == -v ]]; then verbose=1; shift; fi
filter=${1:-}

for cmd in jq sha256sum; do
    command -v "$cmd" >/dev/null || { echo "The tests need the real '$cmd' installed." >&2; exit 2; }
done

export ORIG_PATH=$PATH
TEST_TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/relup-tests.XXXXXX")
export TEST_TMP_ROOT
trap 'chmod -R u+w "$TEST_TMP_ROOT" 2>/dev/null; rm -rf "$TEST_TMP_ROOT"' EXIT

if [[ -t 1 ]]; then G=$'\e[32m' R=$'\e[31m' Z=$'\e[0m'; else G="" R="" Z=""; fi
pass=0 failed=()

for file in "$TESTS_DIR"/test_*.sh; do
    mapfile -t names < <(bash -c 'source "$1"; declare -F' _ "$file" | awk '$3 ~ /^test_/ { print $3 }')
    for name in "${names[@]}"; do
        [[ -z $filter || $name == *"$filter"* ]] || continue
        log="$TEST_TMP_ROOT/$name.log"
        (
            # shellcheck source=lib.sh
            source "$TESTS_DIR/lib.sh"
            # shellcheck disable=SC1090
            source "$file"
            setup_env
            "$name"
        ) < /dev/null > "$log" 2>&1
        rc=$?
        if ((rc == 0)); then
            pass=$((pass + 1))
            printf '%sok%s    %s\n' "$G" "$Z" "$name"
            if ((verbose)); then sed 's/^/      /' "$log"; fi
        else
            failed+=("$name")
            printf '%sFAIL%s  %s  (%s)\n' "$R" "$Z" "$name" "$(basename "$file")"
            sed 's/^/      /' "$log"
        fi
    done
done

echo
echo "${pass} passed, ${#failed[@]} failed"
if ((${#failed[@]})); then
    printf '  %s\n' "${failed[@]}"
    exit 1
fi
