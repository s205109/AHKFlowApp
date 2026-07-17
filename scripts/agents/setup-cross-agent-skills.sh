#!/usr/bin/env bash
# setup-cross-agent-skills.sh
#
# Sets up repo-local cross-agent skill symlinks that point at active .agents/ skills.
# .claude/skills/ and .github/skills/ become real directories containing one symlink
# per immediate .agents/<skill>/ directory. The repo-local Codex plugin
# skills folder mirrors each skill directory with hard-linked files (SKILL.md plus
# companion files such as templates and agents/openai.yaml) because Codex plugin
# installation ignores symlinks. Reference docs, disabled dirs, and plugin packaging
# are ignored.

set -euo pipefail

case "$(uname -s 2>/dev/null || echo unknown)" in
    MINGW*|MSYS*|CYGWIN*)
        echo "Error: setup-cross-agent-skills.sh is not supported on Windows Git Bash." >&2
        echo "Run scripts/agents/setup-cross-agent-skills.ps1 from PowerShell instead." >&2
        exit 1
        ;;
esac

compute_codex_skills_hash() {
    # Deterministic content hash of the Codex skills payload. Hashes git blob OIDs
    # (git hash-object applies clean filters) so line-ending differences between
    # platforms/checkouts don't change the version. Must stay in sync with
    # Get-CodexSkillsHash in setup-cross-agent-skills.ps1: ordinal-sorted forward-slash
    # skills-root-relative paths, SHA-256 over "<blob-oid>  <path>\n" lines.
    # Args: [skills_dir] [git_prefix] — default to the real Codex payload; the
    # regression test passes a temp payload so it can hash spaced filenames.
    local skills_dir="${1:-$CODEX_PLUGIN_SKILLS}"
    local git_prefix="${2:-plugins/ahkflowapp/skills/}"
    (
        cd "$skills_dir"
        local paths_file
        paths_file=$(mktemp)
        find . -type f | sed 's|^\./||' | LC_ALL=C sort > "$paths_file"
        # git hash-object --stdin-paths resolves paths relative to the repo root,
        # so prefix the skills-root-relative names when feeding git.
        # paste joins each blob OID to its path with a single space; convert that
        # first delimiter to two spaces without tokenizing the path — a blob OID
        # never contains a space, so the first space is always the delimiter, and
        # paths containing spaces are preserved in full (must match the PowerShell
        # "<blob-oid>  <path>" format).
        paste -d' ' \
            <(sed "s|^|$git_prefix|" "$paths_file" | git hash-object --stdin-paths) \
            "$paths_file" |
            sed 's/ /  /'
        rm -f "$paths_file"
    ) | sha256sum | cut -c1-12
}

# Side-effect-free entry point for the regression test: print the hash of an
# arbitrary payload and exit before any repo mutation (hooks, symlinks, etc.).
if [ "${1:-}" = "--print-codex-hash" ]; then
    compute_codex_skills_hash "${2:-}" "${3:-}"
    exit 0
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
AGENTS_ROOT="$REPO_ROOT/.agents"
CLAUDE_ROOT="$REPO_ROOT/.claude"
CLAUDE_SKILLS="$REPO_ROOT/.claude/skills"
GITHUB_SKILLS="$REPO_ROOT/.github/skills"
CODEX_PLUGIN_SKILLS="$REPO_ROOT/plugins/ahkflowapp/skills"

# --- Install committed git hooks via core.hooksPath ---
if [ -d "$REPO_ROOT/.githooks" ]; then
    current_hooks_path=$(git config core.hooksPath 2>/dev/null || true)
    normalized_current=$(printf '%s' "$current_hooks_path" | tr '\\' '/' | sed 's:/*$::' | tr '[:upper:]' '[:lower:]')

    case "$normalized_current" in
        .githooks)
            echo "[OK] core.hooksPath = .githooks"
            ;;
        ""|.git/hooks|*/.git/hooks)
            git config core.hooksPath .githooks
            echo "[FIX] Set core.hooksPath = .githooks (enables committed hooks)"
            ;;
        *)
            echo "[WARN] core.hooksPath is '$current_hooks_path' — committed hooks at .githooks/ inactive. To enable: git config core.hooksPath .githooks"
            ;;
    esac
fi

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

is_active_skill() {
    local name="$1"
    case "$name" in
        skills|plugins|skills.disabled|disabled|reference|references)
            return 1
            ;;
    esac

    [ -f "$AGENTS_ROOT/$name/SKILL.md" ]
}

# --- Description budget guardrail ---
max_desc_len=140
bloated=""
for skill_dir in "$AGENTS_ROOT"/*; do
    [ -d "$skill_dir" ] || continue
    skill_name=$(basename "$skill_dir")
    is_active_skill "$skill_name" || continue

    desc=$(grep -m1 '^description:' "$skill_dir/SKILL.md" 2>/dev/null | sed -E 's/^description:[[:space:]]*//')
    desc_len=${#desc}
    if [ "$desc_len" -gt "$max_desc_len" ]; then
        bloated="$bloated
       $skill_name: $desc_len chars"
    fi
done
if [ -n "$bloated" ]; then
    echo "[WARN] Skill descriptions over $max_desc_len chars (context budget):$bloated"
fi

sync_skill_link_directory() {
    local link_root="$1"
    local display_name="$2"
    local target_prefix="$3"
    local replace_existing_dirs="$4"

    if [ -e "$link_root" ] || [ -L "$link_root" ]; then
        if [ -L "$link_root" ]; then
            rm "$link_root"
            echo "[FIX] Removed old $display_name symlink."
        elif [ -d "$link_root" ]; then
            echo "[OK] $display_name already exists."
        else
            echo "Error: $display_name exists but is not a directory. Remove it manually, then re-run." >&2
            exit 1
        fi
    fi

    mkdir -p "$link_root"

    for existing_link in "$link_root"/*; do
        [ -e "$existing_link" ] || [ -L "$existing_link" ] || continue

        existing_name=$(basename "$existing_link")
        if is_active_skill "$existing_name"; then
            continue
        fi

        if [ -f "$existing_link" ] && [ ! -L "$existing_link" ] && [ "$existing_name" = "README.md" ]; then
            continue
        fi

        if [ -L "$existing_link" ]; then
            rm "$existing_link"
            echo "[FIX] Removed stale $display_name/$existing_name link."
        elif [ "$replace_existing_dirs" = "true" ] && [ -d "$existing_link" ]; then
            rm -rf "$existing_link"
            echo "[FIX] Replaced copied $display_name/$existing_name directory."
        else
            echo "Error: $display_name/$existing_name is not an active skill symlink. Remove it manually, then re-run." >&2
            exit 1
        fi
    done

    for skill_dir in "$AGENTS_ROOT"/*; do
        [ -d "$skill_dir" ] || continue

        skill_name=$(basename "$skill_dir")
        if ! is_active_skill "$skill_name"; then
            continue
        fi

        link_path="$link_root/$skill_name"
        if [ -e "$link_path" ] || [ -L "$link_path" ]; then
            if [ -L "$link_path" ]; then
                target=$(readlink "$link_path" || true)
                resolved=""
                if [ -n "$target" ]; then
                    resolved=$({ cd "$(dirname "$link_path")" && cd "$target" && pwd; } 2>/dev/null || true)
                fi

                if [ "$resolved" = "$skill_dir" ]; then
                    echo "[OK] $display_name/$skill_name already points to .agents/$skill_name."
                    continue
                fi

                rm "$link_path"
                echo "[FIX] Replaced old symlink for $display_name/$skill_name."
            elif [ "$replace_existing_dirs" = "true" ] && [ -d "$link_path" ]; then
                rm -rf "$link_path"
                echo "[FIX] Replaced copied $display_name/$skill_name directory."
            else
                echo "Error: $display_name/$skill_name exists but is not a symlink. Remove it manually, then re-run." >&2
                exit 1
            fi
        fi

        (
            cd "$link_root"
            ln -s "$target_prefix/$skill_name" "$skill_name"
        )
    done
}

sync_codex_plugin_skill_directory() {
    local link_root="$1"
    local display_name="$2"

    if [ -e "$link_root" ] || [ -L "$link_root" ]; then
        if [ -L "$link_root" ]; then
            rm "$link_root"
            echo "[FIX] Removed old $display_name symlink."
        elif [ -d "$link_root" ]; then
            echo "[OK] $display_name already exists."
        else
            echo "Error: $display_name exists but is not a directory. Remove it manually, then re-run." >&2
            exit 1
        fi
    fi

    mkdir -p "$link_root"

    for existing_entry in "$link_root"/*; do
        [ -e "$existing_entry" ] || [ -L "$existing_entry" ] || continue

        existing_name=$(basename "$existing_entry")
        if ! is_active_skill "$existing_name"; then
            rm -rf "$existing_entry"
            echo "[FIX] Removed stale $display_name/$existing_name."
            continue
        fi

        if [ -L "$existing_entry" ]; then
            rm "$existing_entry"
            echo "[FIX] Replaced directory symlink $display_name/$existing_name."
        fi
    done

    for skill_dir in "$AGENTS_ROOT"/*; do
        [ -d "$skill_dir" ] || continue

        skill_name=$(basename "$skill_dir")
        if ! is_active_skill "$skill_name"; then
            continue
        fi

        skill_link_dir="$link_root/$skill_name"
        rm -rf "$skill_link_dir"

        (
            cd "$skill_dir"
            find . -type f -print | while IFS= read -r rel; do
                rel="${rel#./}"
                mkdir -p "$skill_link_dir/$(dirname "$rel")"
                ln "$skill_dir/$rel" "$skill_link_dir/$rel"
            done
        )
    done
}

update_codex_plugin_version() {
    local plugin_json="$REPO_ROOT/plugins/ahkflowapp/.codex-plugin/plugin.json"
    if [ ! -f "$plugin_json" ]; then
        echo "[WARN] $plugin_json not found — skipping Codex plugin version bump."
        return
    fi

    local hash current base new_version
    hash=$(compute_codex_skills_hash)
    current=$(sed -nE 's/.*"version":[[:space:]]*"([^"]+)".*/\1/p' "$plugin_json" | head -1)
    if [ -z "$current" ]; then
        echo "[WARN] No version field in plugin.json — skipping Codex plugin version bump."
        return
    fi

    base=${current%%+*}
    new_version="$base+codex.$hash"
    if [ "$new_version" = "$current" ]; then
        echo "[OK] Codex plugin version $current matches skills content."
        return
    fi

    sed -i -E "s|(\"version\":[[:space:]]*\")[^\"]+(\")|\1$new_version\2|" "$plugin_json"
    echo "[FIX] Codex plugin version bumped to $new_version — commit plugin.json."
}

update_codex_installed_plugin() {
    if ! command -v codex >/dev/null 2>&1; then
        echo "[OK] Codex CLI not on PATH — skipping installed plugin refresh."
        return
    fi

    echo "[..] Refreshing installed Codex plugin cache (codex plugin add ahkflowapp@ahkflowapp-local)..."
    if codex plugin add 'ahkflowapp@ahkflowapp-local' --json >/dev/null 2>&1; then
        echo "[OK] Codex plugin cache refreshed. Start a new Codex session to pick up skill changes."
    else
        echo "[WARN] 'codex plugin add ahkflowapp@ahkflowapp-local' failed (is the ahkflowapp-local marketplace registered?). Run it manually to refresh the Codex plugin cache."
    fi
}

mkdir -p "$CLAUDE_ROOT"

sync_skill_link_directory "$CLAUDE_SKILLS" ".claude/skills" "../../.agents" false
sync_skill_link_directory "$GITHUB_SKILLS" ".github/skills" "../../.agents" false
sync_codex_plugin_skill_directory "$CODEX_PLUGIN_SKILLS" "plugins/ahkflowapp/skills"
update_codex_plugin_version
update_codex_installed_plugin

echo "[DONE] .claude/skills and .github/skills symlink to active .agents/* skills; Codex plugin skills mirror the same skill directories with hard-linked files"
