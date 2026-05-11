#!/usr/bin/env bash
# setup-cross-agent-skills.sh
#
# Sets up .agents/skills/ as the canonical skills folder in the repo.
# .claude/skills/ becomes a folder-level symlink to .agents/skills/ so Claude Code
# reads them. Everything stays inside the repo — no user-folder changes.

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)
AGENTS_ROOT="$REPO_ROOT/.agents"
AGENTS_SKILLS="$REPO_ROOT/.agents/skills"
CLAUDE_SKILLS="$REPO_ROOT/.claude/skills"

# --- Ensure .agents/skills/ exists and exposes repo skills ---
if [ ! -d "$AGENTS_ROOT" ]; then
    echo "Error: .agents does not exist in the repo." >&2
    exit 1
fi

mkdir -p "$AGENTS_SKILLS"
echo "[OK] .agents/skills/ exists."

for skill_dir in "$AGENTS_ROOT"/*; do
    [ -d "$skill_dir" ] || continue

    skill_name=$(basename "$skill_dir")
    if [ "$skill_name" = "skills" ]; then
        continue
    fi

    link_path="$AGENTS_SKILLS/$skill_name"
    if [ -e "$link_path" ] || [ -L "$link_path" ]; then
        if [ -L "$link_path" ]; then
            echo "[OK] .agents/skills/$skill_name already exists as a symlink."
            continue
        fi

        echo "Error: .agents/skills/$skill_name exists but is not a symlink. Remove it manually, then re-run." >&2
        exit 1
    fi

    (
        cd "$AGENTS_SKILLS"
        ln -s "../$skill_name" "$skill_name"
    )
done

# --- Create .claude/skills/ as a folder-level symlink ---
if [ -e "$CLAUDE_SKILLS" ] || [ -L "$CLAUDE_SKILLS" ]; then
    if [ -L "$CLAUDE_SKILLS" ]; then
        echo "[OK] .claude/skills already exists as a symlink. Nothing to do."
        exit 0
    fi
    echo "Error: .claude/skills exists but is not a symlink. Remove it manually, then re-run." >&2
    exit 1
fi

# Relative target: from .claude/ go up one level then into .agents/skills
mkdir -p "$REPO_ROOT/.claude"
cd "$REPO_ROOT/.claude"
ln -s "../.agents/skills" "skills"

echo "[DONE] .claude/skills -> .agents/skills (repo-local, relative symlink)"
