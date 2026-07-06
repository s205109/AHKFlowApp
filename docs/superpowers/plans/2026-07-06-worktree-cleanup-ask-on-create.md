# Ask to clean up merged worktrees after Claude-native worktree creation

## Context

`scripts/cleanup-merged-worktrees.ps1` already detects worktrees whose branch is
merged into `main` and clean, and offers to remove them — but only for a human
running `scripts/new-worktree.ps1` directly in a terminal (interactive `y/n`, or
`-Cleanup`/`-c` to skip the prompt). When Claude Code creates a worktree natively in
response to a conversation (the `EnterWorktree` tool, which fires the `WorktreeCreate`
hook to run `new-worktree.ps1`), cleanup runs in report-only mode: it logs eligible
candidates to stderr and never prompts or removes. The user wants that native path to
also ask — only when eligible worktrees actually exist.

This gap is structural, not a bug: confirmed against official Claude Code docs that
`WorktreeCreate` hooks may output **only** the literal worktree path on stdout, with no
`additionalContext`/JSON envelope (unlike `SessionStart`, `UserPromptSubmit`, etc.), and
hook subprocesses have no controlling terminal — they cannot block on user input the
way `AskUserQuestion` can. So the prompt can't live in the hook or the PowerShell
script; it has to live at the assistant-behavior layer: an instruction in the
`worktrees` skill telling Claude to re-check and ask, as a normal follow-up tool call,
right after it creates a worktree.

Scope, confirmed with the user:
- Covers only in-conversation "ask Claude to create/work in a worktree." `claude
  --worktree <name>` CLI-flag session bootstrap is explicitly **out of scope** — there's
  no conversation turn yet for a skill to act in, and building a heuristic
  `SessionStart`-based check for that was rejected as unnecessary complexity.
- Instructions go **only** in `.agents/worktrees/SKILL.md` (the existing source of
  truth for worktree behavior). `.agents/dck-workflow-mastery/SKILL.md` already just
  points to the `worktrees` skill for all worktree specifics and stays untouched, to
  avoid two copies drifting apart.

No script logic changes are needed. `Invoke-MergedWorktreeCleanup`'s `-IsHook` branch
(`scripts/cleanup-merged-worktrees.ps1:165-168`) already does exactly "detect, log
eligible worktrees to stderr, never remove" — regardless of who invokes it. Called
directly by the assistant via a normal Bash tool call (not as an actual Claude Code
hook subprocess), its output is visible to the model, unlike a real hook's stderr. This
plan reuses that switch as a detect-only primitive rather than adding a new one.

## A gap found during review — must be handled in the wording

`EnterWorktree` shifts the session's cwd into the **new** worktree. If the detection
command is run without `-RepoRoot`, `cleanup-merged-worktrees.ps1`'s entrypoint default
(`scripts/cleanup-merged-worktrees.ps1:199-200`, `$RepoRoot = ($PSScriptRoot/..)`)
resolves to the **new worktree**, not the main checkout — breaking the "always exclude
the main checkout" comparison in `Get-EligibleMergedWorktrees` (line 92). Since `main`
is trivially "merged into main" and normally clean, the **main checkout itself** could
show up as a false-positive cleanup candidate, and a "yes" would try to remove it.
`-ExcludePath` only protects the newly created worktree — it does not protect the real
main checkout when `-RepoRoot` is wrong.

Fix: the assistant must always compute the main checkout root as the grandparent of
the new worktree's path (worktrees are enforced as direct children of
`.claude\worktrees\` or `.worktrees\` by `Assert-WorktreeLocation` in
`new-worktree.ps1`) and pass it explicitly as `-RepoRoot` on every call. Do this in
PowerShell itself (`Split-Path -Parent` twice), not bash `dirname` — the new worktree
path may contain Windows-style backslashes, and doing the math in the same `pwsh
-Command` call that invokes the script avoids any Git-Bash path-separator ambiguity.

## The change

Insert a new subsection into `.agents/worktrees/SKILL.md`, immediately after the
existing "Cleanup of merged worktrees on create" section's last paragraph (ends
"...lock-safe folder delete.") and before the "## Removing" heading. Leave everything
else in the file untouched.

```markdown
#### Claude Code native creation: ask afterward

Applies only when *you* create a brand-new worktree in direct response to a
conversational request, via `EnterWorktree` with `name` (entering an *existing*
worktree with `path` never triggers this). Does not apply to `claude --worktree
<name>` session bootstrap — there's no conversation turn yet to ask in.

`EnterWorktree` fires the `WorktreeCreate` hook above, whose stdout must stay exactly
the new worktree's path — it cannot prompt, and its stderr never reaches you. Right
after `EnterWorktree` returns the new worktree's absolute path, re-run detection
yourself as a normal Bash call so its output *is* visible to you:

```bash
pwsh -NoProfile -Command "$newPath = '<new-worktree-absolute-path>'; $mainRoot = Split-Path -Parent (Split-Path -Parent $newPath); & (Join-Path $mainRoot 'scripts\cleanup-merged-worktrees.ps1') -RepoRoot $mainRoot -IsHook -ExcludePath $newPath"
```

**Always pass `-RepoRoot` explicitly, computed as shown.** The script's own default
resolves relative to its own location, which — since `EnterWorktree` already moved you
into the new worktree — would target the wrong checkout and could misidentify `main`
itself as a cleanup candidate.

- No `cleanup: eligible merged worktree: ...` line (just `cleanup: no merged
  worktrees eligible for cleanup.`) — stay silent, do not ask.
- One or more `cleanup: eligible merged worktree: <path> [<branch>]` lines — ask via
  `AskUserQuestion`, listing what was found, e.g. "Found N merged worktree(s) ready to
  clean up: `<path>` [`<branch>`], ... . Remove them now?" with options `Yes, remove
  them` / `No, leave them`.
  - **Yes:** re-run with `-Cleanup` instead of `-IsHook`:

    ```bash
    pwsh -NoProfile -Command "$newPath = '<new-worktree-absolute-path>'; $mainRoot = Split-Path -Parent (Split-Path -Parent $newPath); & (Join-Path $mainRoot 'scripts\cleanup-merged-worktrees.ps1') -RepoRoot $mainRoot -Cleanup -ExcludePath $newPath"
    ```

  - **No:** leave them; don't run the removal command.
```

## Critical files

- `.agents/worktrees/SKILL.md` — the only content edit (source of truth; `.claude/skills/worktrees` and `.github/skills/worktrees` are symlinks to it and pick up the change automatically).
- `plugins/ahkflowapp/skills/worktrees/SKILL.md` — hard link to the same file; needs re-sync, not a hand edit.
- Reused, unchanged: `scripts/cleanup-merged-worktrees.ps1` (`-IsHook`, `-Cleanup`, `-ExcludePath`, `-RepoRoot`), `scripts/new-worktree.ps1` (for context only, not touched).

## Steps

1. Edit `.agents/worktrees/SKILL.md` — insert the block above.
2. Re-sync the plugin hard link: `pwsh -NoProfile -File scripts/agents/setup-copilot-symlinks.ps1`. Expect exit 0, output ending `[DONE] .claude/skills and .github/skills symlink to active .agents/* skills; Codex plugin skills hard-link to the same SKILL.md files`.
3. Hash-verify: `pwsh -NoProfile -Command "if ((Get-FileHash .agents/worktrees/SKILL.md).Hash -ne (Get-FileHash plugins/ahkflowapp/skills/worktrees/SKILL.md).Hash) { throw 'SKILL.md copies differ' } else { 'SKILL.md copies match' }"`. Expect `SKILL.md copies match`.
4. Sanity-check the symlinks weren't disturbed: `pwsh -NoProfile -File scripts/agents/check-symlinks.ps1 -Path .claude/skills/worktrees -NoRecurse` and same for `.github/skills/worktrees`. Expect `LinkType = SymbolicLink`, target `.agents\worktrees`.
5. Read the edited file back to confirm heading levels (`###` → `####`) and fenced code blocks are balanced.

## Verification

This is docs-only — no automated test covers SKILL.md prose, and none needs to. End-to-end verification is manual: in a real conversation, ask Claude to create a new worktree in a repo state with at least one other merged+clean worktree present, and confirm:
- Claude runs the detection command after `EnterWorktree` returns, finds the eligible worktree(s), and asks via `AskUserQuestion` before doing anything else.
- Answering "No" leaves all worktrees intact.
- Answering "Yes" removes only the eligible ones (verify via `git worktree list` before/after) and never touches the main checkout or the just-created worktree.
- In a repo state with zero eligible worktrees, Claude creates the worktree and says nothing about cleanup — no question asked.

## Unresolved questions

None — scope and skill placement confirmed with user; script name existence and `-RepoRoot` default behavior verified directly against the repo.
