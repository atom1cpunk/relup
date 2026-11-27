#!/usr/bin/env bash
# Claude Code hook (PostToolUse on Edit|Write): after Claude edits the relup script, check its
# syntax and run shellcheck. Problems go back to Claude (exit 2, message on stderr) so they are
# fixed straight away. Edits to any other file are ignored.
f=$(jq -r '.tool_input.file_path // .tool_response.filePath // empty')
[[ -n $f && $(basename -- "$f") == relup && -f $f ]] || exit 0

if ! out=$(bash -n "$f" 2>&1); then
    printf 'bash -n found a syntax error in %s:\n%s\n' "$f" "$out" >&2
    exit 2
fi

command -v shellcheck >/dev/null || exit 0
# The five known, harmless notes listed in CLAUDE.md are left out; anything else is reported.
if ! out=$(shellcheck -e SC2088,SC2174,SC2034,SC2018,SC2019 "$f" 2>&1); then
    printf 'shellcheck found problems in %s:\n%s\n' "$f" "$out" >&2
    exit 2
fi
exit 0
