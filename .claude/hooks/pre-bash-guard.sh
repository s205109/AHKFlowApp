#!/usr/bin/env bash
# Pre-Bash Guard — Block destructive operations
# Inspects the Bash tool command before execution via CLAUDE_TOOL_INPUT.
# Exit 2 = block the command, exit 0 = allow.

COMMAND="${CLAUDE_TOOL_INPUT}"

# ── Destructive git operations ──────────────────────────────────────

if echo "$COMMAND" | grep -qE 'git\s+push\s+.*--force|git\s+push\s+-f\b'; then
  echo "BLOCKED: Force push detected. Use regular push or discuss with the user first."
  exit 2
fi

if echo "$COMMAND" | grep -qE 'git\s+reset\s+--hard'; then
  echo "BLOCKED: git reset --hard will discard all uncommitted changes. Discuss with the user first."
  exit 2
fi

if echo "$COMMAND" | grep -qE 'git\s+clean\s+-[a-zA-Z]*f'; then
  echo "BLOCKED: git clean -f will permanently delete untracked files. Discuss with the user first."
  exit 2
fi

if echo "$COMMAND" | grep -qE 'git\s+checkout\s+\.'; then
  echo "BLOCKED: git checkout . will discard all unstaged changes. Discuss with the user first."
  exit 2
fi

# ── Dangerous file operations ───────────────────────────────────────

if echo "$COMMAND" | grep -qE 'rm\s+-[a-zA-Z]*r[a-zA-Z]*f|rm\s+-[a-zA-Z]*f[a-zA-Z]*r'; then
  # Allow rm -rf on safe targets (node_modules, bin, obj, TestResults, .vs)
  if echo "$COMMAND" | grep -qE 'rm\s+-rf\s+(node_modules|bin|obj|TestResults|\.vs|/tmp)'; then
    : # safe, fall through to exit 0
  else
    echo "WARNING: rm -rf detected in a project directory. Verify the target path is intentional."
    exit 2
  fi
fi

# ── dotnet run without launch settings check ────────────────────────

if echo "$COMMAND" | grep -qE 'dotnet\s+run\b'; then
  echo "WARNING: dotnet run detected. Ensure launchSettings.json exists and the correct profile is selected."
  # Allow but warn — exit 0 so it proceeds
fi

exit 0
