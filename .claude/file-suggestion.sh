#!/usr/bin/env bash
# Supplies the file list for @-mentions in Claude Code.
#
# Why this exists: the built-in file picker does not list files under
# docs/superpowers/. That folder holds a second, private git repository
# (AHKFlowApp-plans), and the built-in picker appears to skip nested
# repositories. Setting "respectGitignore": false was not enough on its own.
#
# Tools:
#   rg  - required. Without ripgrep this script can produce no list at all.
#   jq  - optional. Reads the query out of the JSON on stdin. Without it the
#         query is read with sed instead.
#   fzf - optional. Ranks results by fuzzy match. Without it the script falls
#         back to a case-insensitive substring match. Less clever, but it
#         never hands back an empty picker.
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

payload=$(cat)

if command -v jq >/dev/null 2>&1; then
  query=$(printf '%s' "$payload" | jq -r '.query // ""' 2>/dev/null)
else
  query=$(printf '%s' "$payload" | sed -n 's/.*"query"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
fi

# --no-ignore-vcs drops .gitignore but keeps .ignore.
# The .git glob covers the nested repository under docs/superpowers/ too.
# --follow is what makes docs/superpowers show up in an agent worktree: there it is a
# directory symlink back to the main checkout (see scripts/new-worktree.ps1), and rg does
# not descend into symlinked directories without this flag. .ignore denies the pre-existing
# skill-mirror symlinks (.claude/skills/, .github/skills/, .github/AGENTS.md) so --follow
# does not also duplicate every skill file and AGENTS.md in the suggestion list.
list_files() {
  rg --files --hidden --no-ignore-vcs --follow --glob '!**/.git/**' 2>/dev/null | tr '\\' '/'
}

if [ -z "$query" ]; then
  list_files | head -30
elif command -v fzf >/dev/null 2>&1; then
  list_files | fzf --filter="$query" 2>/dev/null | head -30
else
  list_files | grep -i -F -- "$query" | head -30
fi
