Be concise in all interactions. For documentation and app-facing text, follow **Plain English** in AGENTS.md — when short and easy-to-read conflict, choose easy-to-read. In commit messages, be extremely concise — sacrifice grammar for brevity.

@../AGENTS.md

# Claude Code Configuration

> Sections below are specific to Claude Code. Shared instructions are in AGENTS.md.

## Workflow Preferences

### Plan before you edit

Before any **non-trivial** task, run `superpowers:brainstorming`, write a plan, and use `mp-grilling`
to settle open questions. Do this before touching code, not after.

Only these are exempt. Everything else plans first:

- A change confined to a single file
- Typo, comment, or formatting fixes
- Answering a question, or reading and reporting
- Running a command that changes nothing

Picking up a `.claude/backlog/` item is never trivial. Neither is any change to user-facing wording,
labels, or names — a wrong shared assumption about a word is cheap to catch up front and expensive
to undo later.

### Create the worktree before you write the plan

Create the worktree first, then switch fully into it, and only then write the plan. Use
`scripts/new-worktree.ps1` or the `WorktreeCreate` tool. Do not start writing a plan in the main
checkout and move the work afterwards.

One exception, because the file system forces it. Worktrees have **no `docs/superpowers/` folder** —
it is a separate private repo (`AHKFlowApp-plans`), the public repo ignores the path, and
`git worktree add` does not create it. So:

- **The plan file** is written and committed in `docs/superpowers/plans/` in the **main checkout**.
  Commit from inside `docs/superpowers/`, never from the repo root.
- **Everything else** — code, tests, docs, config — happens in the worktree and commits from there.

### Other

- When asked to store instructions or rules, put them in CLAUDE.md (not memory files) unless explicitly told otherwise.
- Verifying finished work is governed by **Verification After Implementation** in AGENTS.md. Invoke the `playwright-cli` skill via the Skill tool when that routing calls for a browser drive.
- Before claiming a tool or capability is unavailable, check `.claude/skills/` and available skills. Never assume browser automation is missing — `playwright-cli` is installed.

## Out of Scope

- Runtime execution of AutoHotkey scripts — intentionally excluded (the app generates `.ahk` files, never runs them)

Pending features are tracked in `.claude/backlog/`.

## Project Configuration

- Rules (always loaded): `.claude/rules/`
- Skills (on demand): `.claude/skills/`
- Backlog: `.claude/backlog/` — open items; completed items live in `done/`
- Frontend instructions: `src/Frontend/AHKFlowApp.UI.Blazor/CLAUDE.md`
- Private/local config: `.claude/CLAUDE.local.md` (gitignored)
- Documentation: `docs/` — architecture, azure, development guides
