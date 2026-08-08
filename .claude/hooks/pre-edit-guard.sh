#!/usr/bin/env bash
# Pre-Edit Guard - fast cwd prefilter for Claude Edit, Write, and NotebookEdit tool calls.
#
# Reads the native PreToolUse payload from stdin. A managed worktree always lives directly under
# <main>/.claude/worktrees or <main>/.worktrees, so its path always carries the "worktrees"
# segment. A payload whose cwd does not carry it cannot be a worktree session, so it exits here
# without paying PowerShell startup. Everything else is forwarded to the shared policy core in
# scripts/agents/invoke-agent-worktree-guard.ps1, which makes the real decision.
#
# Exit 2 = block. Exit 0 = allow.

if [[ "${AHKFLOW_GUARD_DISABLE:-}" == "1" ]]; then
  echo "WARNING: AHKFLOW_GUARD_DISABLE=1; all agent command guardrails are disabled." >&2
  exit 0
fi

INPUT=$(cat)

shopt -s nocasematch

# Conservative superset, applied to the raw payload so the common case never pays for a jq
# process at all. Same discipline as pre-bash-guard.sh: a false positive costs one PowerShell
# start, a false negative silently disables the guard. An edited file whose own path contains
# "worktrees" costs one wasted start in a main session, which is the accepted direction of error.
WORKTREE_SESSION_PATTERN='worktrees'

if [[ ! "$INPUT" =~ $WORKTREE_SESSION_PATTERN ]]; then
  exit 0
fi

# Narrow the match to cwd when jq is available, so the wasted start above is avoided too.
# Correctness must not depend on jq: a parse failure forwards.
if command -v jq >/dev/null 2>&1; then
  CWD=$(printf '%s' "$INPUT" | jq -er '.cwd // empty' 2>/dev/null) || CWD=""
  if [[ -n "$CWD" ]] && [[ ! "$CWD" =~ $WORKTREE_SESSION_PATTERN ]]; then
    exit 0
  fi
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if command -v pwsh >/dev/null 2>&1; then
  POWERSHELL=(pwsh -NoProfile -NonInteractive)
elif command -v powershell.exe >/dev/null 2>&1; then
  POWERSHELL=(powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass)
else
  echo "WARNING: agent guard could not find PowerShell; allowing edit." >&2
  exit 0
fi

printf '%s' "$INPUT" |
  "${POWERSHELL[@]}" -File \
    "$SCRIPT_DIR/../../scripts/agents/invoke-agent-worktree-guard.ps1" \
    -Adapter Claude
