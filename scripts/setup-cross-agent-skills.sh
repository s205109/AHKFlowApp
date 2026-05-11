#!/usr/bin/env bash
# setup-cross-agent-skills.sh
#
# Sets up repo-local Claude skill symlinks that point at .agents/.
# .claude/skills/ becomes a real directory containing one symlink per skill
# back to .agents/<skill>. Everything stays inside the repo — no user-folder changes.

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)
AGENTS_ROOT="$REPO_ROOT/.agents"
CLAUDE_ROOT="$REPO_ROOT/.claude"
CLAUDE_SKILLS="$REPO_ROOT/.claude/skills"

# --- Ensure .agents/ exists ---
if [ ! -d "$AGENTS_ROOT" ]; then
    echo "Error: .agents does not exist in the repo." >&2
    exit 1
fi

echo "[OK] .agents/ exists."

AGENTS_SKILLS="$AGENTS_ROOT/skills"
if [ -e "$AGENTS_SKILLS" ] || [ -L "$AGENTS_SKILLS" ]; then
    if [ -L "$AGENTS_SKILLS" ]; then
        rm "$AGENTS_SKILLS"
        echo "[FIX] Removed stale .agents/skills symlink."
    elif [ -d "$AGENTS_SKILLS" ]; then
        if find "$AGENTS_SKILLS" -mindepth 1 -maxdepth 1 ! -type l -print -quit | grep -q .; then
            echo "Error: .agents/skills exists but should not. Remove it manually, then re-run." >&2
            exit 1
        fi

        rm -rf "$AGENTS_SKILLS"
        echo "[FIX] Removed stale .agents/skills directory."
    else
        echo "Error: .agents/skills exists but should not. Remove it manually, then re-run." >&2
        exit 1
    fi
fi

# --- Ensure .claude/skills/ is a real directory ---
if [ -e "$CLAUDE_SKILLS" ] || [ -L "$CLAUDE_SKILLS" ]; then
    if [ -L "$CLAUDE_SKILLS" ]; then
        rm "$CLAUDE_SKILLS"
        echo "[FIX] Removed old .claude/skills symlink."
    else
        echo "[OK] .claude/skills/ already exists."
    fi
fi

mkdir -p "$CLAUDE_ROOT"
mkdir -p "$CLAUDE_SKILLS"

for skill_dir in "$AGENTS_ROOT"/*; do
    [ -d "$skill_dir" ] || continue

    skill_name=$(basename "$skill_dir")
    if [ "$skill_name" = "skills" ]; then
        continue
    fi

    link_path="$CLAUDE_SKILLS/$skill_name"
    if [ -e "$link_path" ] || [ -L "$link_path" ]; then
        if [ -L "$link_path" ]; then
            resolved=$(cd "$(dirname "$link_path")" && cd "$(readlink "$link_path")" && pwd)
            if [ "$resolved" = "$skill_dir" ]; then
                echo "[OK] .claude/skills/$skill_name already points to .agents/$skill_name."
                continue
            fi

            rm "$link_path"
            echo "[FIX] Replaced old symlink for $skill_name."
        else
            echo "Error: .claude/skills/$skill_name exists but is not a symlink. Remove it manually, then re-run." >&2
            exit 1
        fi
    fi

    (
        cd "$CLAUDE_SKILLS"
        ln -s "../../.agents/$skill_name" "$skill_name"
    )
done

echo "[DONE] .claude/skills contains symlinks to .agents/*"
