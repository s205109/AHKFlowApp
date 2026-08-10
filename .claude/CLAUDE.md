The `ASD-STE100` output style governs chat text. **Plain English** in AGENTS.md governs text written into the repository: documentation, specs, plans, and app-facing strings. When short and easy-to-read conflict, choose easy-to-read. In commit messages, be extremely concise — sacrifice grammar for brevity.

@../AGENTS.md

# Claude Code Configuration

> Sections below are specific to Claude Code. Shared instructions are in AGENTS.md.

## Workflow Preferences

### Plan before you edit

Before any **non-trivial** task, run `superpowers:brainstorming`, write a plan, and use `mp-grilling`
to settle open questions. Do this before touching code, not after.

Only these are exempt. Everything else plans first:

- A one-file change that changes no behavior, no user-facing wording or name, and no interface
  that other code depends on
- Typo, comment, or formatting fixes
- Answering a question, or reading and reporting
- Running a command that changes nothing

Picking up a `backlog/` item is never trivial. Neither is any change to user-facing wording,
labels, or names — a wrong shared assumption about a word is cheap to catch up front and expensive
to undo later. Staying inside one file does not make such a change trivial. When a change matches
both the exemption list and this paragraph, this paragraph wins: plan first.

### Create the worktree before you write the plan

Create the worktree first. Do not start writing a plan in the main checkout and then move the work
afterwards. Use `scripts/new-worktree.ps1`, or the native `EnterWorktree` tool — that tool fires the
`WorktreeCreate` hook, which runs the same script for you.

Write and commit the planning documents from the **main checkout**, not from the worktree.
`docs/superpowers/` is a separate private repo (`AHKFlowApp-plans`). The public repo ignores the
path, so `git worktree add` never checks it out. `scripts/new-worktree.ps1` links the folder into
each worktree instead, so a worktree can **read** its spec and plan at the same relative path.
Treat that link as read-only: keep every plan write and plan commit in the main checkout, so the
plans repo has one place work happens. Follow this order:

1. Create the worktree, but stay in the main checkout for now.
2. Write and commit the spec and the plan there, under `docs/superpowers/specs/` and
   `docs/superpowers/plans/`. Commit from inside `docs/superpowers/`, never from the repo root.
   Target that repo with `git -C docs/superpowers commit`, not `cd docs/superpowers && git commit`.
   The agent Git guard reads the command before the shell runs the `cd`, so it still sees the main
   checkout and blocks the commit. `-C` shows it the real target, which is a different repository.
3. Switch fully into the worktree. Everything else — code, tests, docs, config — happens there and
   commits from there. The spec and plan stay readable at `docs/superpowers/` through the link.
4. If a review round changes the plan, go back to the main checkout to edit and commit it. The
   worktree sees the update straight away, because the link points at one shared working copy.

Step 2 does not apply to every plan. **Plans** in AGENTS.md lists the kinds that stay out of the
private repo: agent optimization, personal workflow tuning, agent housekeeping, and one-off
context or config cleanups. Those still get a plan. The plan just is not committed there.

### Other

- When asked to store instructions or rules, put them in CLAUDE.md (not memory files) unless explicitly told otherwise.
- Verifying finished work is governed by **Verification After Implementation** in AGENTS.md. Invoke the `playwright-cli` skill via the Skill tool when that routing calls for a browser drive.
- Before claiming a tool or capability is unavailable, check `.claude/skills/` and available skills. Never assume browser automation is missing — `playwright-cli` is installed.

## Out of Scope

- Runtime execution of AutoHotkey scripts — intentionally excluded (the app generates `.ahk` files, never runs them)

Pending features are tracked in `backlog/`.

## Project Configuration

- Rules (always loaded): `.claude/rules/`
- Skills (on demand): `.claude/skills/`
- Backlog: `backlog/` (repo root) — open items; completed items live in `done/`; items blocked on something outside this repository live in `blocked/`. The PR that finishes an item also moves its file into `done/` — see **Git Workflow** in AGENTS.md
- Frontend instructions: `src/Frontend/AHKFlowApp.UI.Blazor/CLAUDE.md`
- Private/local config: `.claude/CLAUDE.local.md` (gitignored)
- Documentation: `docs/` — architecture, azure, development guides
