#!/usr/bin/env bash
# Pre-Bash Guard - fast candidate-token shim for Claude and GitHub Copilot.
#
# Reads the native PreToolUse payload from stdin. Commands that cannot match a git, rm, or
# dotnet rule exit here without paying PowerShell startup; candidates are forwarded to the
# shared policy core in scripts/agents/invoke-agent-worktree-guard.ps1.
#
# The optional first argument is an explicit adapter override (Codex uses it). Without one,
# Copilot is inferred from a top-level "toolArgs" key and Claude is assumed otherwise.
# Exit 2 = block the command, exit 0 = allow.

if [[ "${AHKFLOW_GUARD_DISABLE:-}" == "1" ]]; then
  echo "WARNING: AHKFLOW_GUARD_DISABLE=1; all agent command guardrails are disabled." >&2
  exit 0
fi

ADAPTER="${1:-Auto}"
INPUT=$(cat)
COMMAND=""
PARSED=0

# Held in single-quoted variables: an inline backtick in a [[ =~ ]] pattern would be taken as
# command substitution before the match ever happens.
#
# Both boundaries are "not an identifier character" rather than an enumerated delimiter list. An
# enumerated list has to predict every character that can precede an executable, and it will miss
# some: quotes and path separators are not delimiters, so "git" commit, 'git' commit, and
# "C:\Program Files\Git\cmd\git.exe" commit all escaped the old [[:space:];&|()`] class and exited
# here without ever reaching policy. The PowerShell core parses all three correctly - only this
# prefilter was wrong, which is the worst place for it to be. Keep this a conservative superset:
# a false positive costs one PowerShell start, a false negative silently disables the guard.
CANDIDATE_PATTERN='(^|[^A-Za-z0-9_.-])(git(\.exe)?|rm|dotnet)([^A-Za-z0-9_.-]|$)'

# Conservative superset of CANDIDATE_PATTERN, applied to the raw payload so the common case
# never pays for a jq process at all.
#
# Only the trailing boundary is checked. A leading-delimiter check cannot be used here: JSON
# encoders escape shell metacharacters, and Windows PowerShell's ConvertTo-Json emits
# "cd f&&git commit" - the character preceding the token is then a hex digit, not a
# delimiter. The trailing class still rejects the common false positive ("segocom-github", where
# 'git' is followed by 'h'), and any real token is followed by a space, quote, or backslash.
# A false positive only costs one jq call; a false negative would silently disable the guard.
RAW_CANDIDATE_PATTERN='(git(\.exe)?|rm|dotnet)([^A-Za-z0-9_.-]|$)'

shopt -s nocasematch

if [[ ! "$INPUT" =~ $RAW_CANDIDATE_PATTERN ]]; then
  exit 0
fi

if command -v jq >/dev/null 2>&1; then
  COMMAND=$(printf '%s' "$INPUT" | jq -er '
    if has("toolArgs") then
      (.toolArgs | fromjson | .command // empty)
    else
      (.tool_input.command // empty)
    end
  ' 2>/dev/null) && PARSED=1
fi

if [[ $PARSED -eq 1 ]]; then
  # Match only the extracted command, never the raw payload: a cwd containing "segocom-github"
  # must not drag a noncandidate command onto the slow path.
  if [[ ! "$COMMAND" =~ $CANDIDATE_PATTERN ]]; then
    exit 0
  fi

  if [[ "$ADAPTER" == "Auto" ]]; then
    if printf '%s' "$INPUT" | jq -e 'has("toolArgs")' >/dev/null 2>&1; then
      ADAPTER="Copilot"
    else
      ADAPTER="Claude"
    fi
  fi
fi

# jq missing, empty input, or a parse failure: forward as Auto so the PowerShell entrypoint
# performs the same payload-shape inference. Correctness must not depend on jq.

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if command -v pwsh >/dev/null 2>&1; then
  POWERSHELL=(pwsh -NoProfile -NonInteractive)
elif command -v powershell.exe >/dev/null 2>&1; then
  POWERSHELL=(powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass)
else
  echo "WARNING: agent guard could not find PowerShell; allowing command." >&2
  exit 0
fi

printf '%s' "$INPUT" |
  "${POWERSHELL[@]}" -File \
    "$SCRIPT_DIR/../../scripts/agents/invoke-agent-worktree-guard.ps1" \
    -Adapter "$ADAPTER"
