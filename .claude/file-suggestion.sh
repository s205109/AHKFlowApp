#!/usr/bin/env bash
# Supplies the file list for @-mentions in Claude Code.
#
# Why this exists: the built-in file picker does not list files under
# docs/superpowers/. That folder holds a second, private git repository
# (AHKFlowApp-plans), and the built-in picker skips nested repositories.
# Setting "respectGitignore": false was not enough on its own.
#
# Contract (see .claude/settings.json -> fileSuggestion):
#   stdin  - JSON, for example {"query": "2026-07-2"}
#   stdout - one file path per line, relative to the project root
#   env    - CLAUDE_PROJECT_DIR, same variables that hooks receive
#
# Ignore rules come from .ignore, never from .gitignore. That is deliberate.
# It is why .ignore repeats the build-output folders such as bin/ and obj/.

set -uo pipefail

root="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$root" 2>/dev/null || exit 0

query=$(jq -r '.query // ""' 2>/dev/null)

# --no-ignore-vcs drops .gitignore but keeps .ignore.
# The .git glob covers the nested repository under docs/superpowers/ too.
list_files() {
  rg --files --hidden --no-ignore-vcs --glob '!**/.git/**' 2>/dev/null | tr '\\' '/'
}

if [ -z "$query" ]; then
  list_files | head -30
else
  list_files | fzf --filter="$query" 2>/dev/null | head -30
fi
