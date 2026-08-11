@../AGENTS.md

Be concise in all interactions.

Your chat replies follow the `ASD-STE100` output style (user level).
Text written into this repository — docs, specs, plans, app-facing strings — follows
**Plain English** in AGENTS.md. Commit messages are exempt from both: be extremely
concise, sacrifice grammar for brevity.

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

Create the worktree first. Never start a plan in the main checkout and move the work later.
Use `scripts/new-worktree.ps1`, or the native `EnterWorktree` tool. That tool fires the
`WorktreeCreate` hook, which runs the same script.

Order of work:

1. Create the worktree. Stay in the main checkout.
2. Write and commit the spec and the plan from the main checkout, under
   `docs/superpowers/specs/` and `docs/superpowers/plans/`.
3. Switch into the worktree. Code, tests, docs, and config happen there and commit there.
4. If a review round changes the plan, edit and commit it from the worktree. Backlog 076 allows
   writes inside `docs/superpowers/`. Commit with `git -C docs/superpowers commit`, as below.

Why the split: `docs/superpowers/` is a separate private repo (`AHKFlowApp-plans`). The public
repo ignores the path, so `git worktree add` never checks it out. `scripts/new-worktree.ps1`
links the folder into each worktree instead. A worktree can read its spec and plan at the same
relative path. Writes inside that folder are allowed from a worktree; the folder itself must not be
renamed or deleted.

Commit plans with `git -C docs/superpowers commit`. Never use `cd docs/superpowers && git commit`.
The agent Git guard reads the command before the shell runs the `cd`, so it still sees the main
checkout and blocks the commit. `-C` shows it the real target.

Step 2 has exceptions. **Plans** in AGENTS.md lists the kinds that stay out of the private repo:
agent optimization, personal workflow tuning, agent housekeeping, and one-off context or config
cleanups. These plans may be skipped. If you write one, keep it out of the private repo.

### Other

- When asked to store an instruction or a rule, put it in CLAUDE.md or `.claude/rules/`.
  Do not put it in an auto memory file unless I ask for one in that turn. Auto memory is on by
  default and writes notes Claude chooses itself; it is not a place for instructions I gave you.
  Toggle it from `/memory`.
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
