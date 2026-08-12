@../AGENTS.md

Be concise in all interactions.

Your chat replies follow the `ASD-STE100` output style (user level).
Text written into this repository — docs, specs, plans, app-facing strings — follows
**Plain English** in AGENTS.md. Commit messages are exempt from both: be extremely
concise, sacrifice grammar for brevity.

# Claude Code Configuration

> Sections below are specific to Claude Code. Shared instructions are in AGENTS.md.

## Workflow Preferences

The canonical process is [`docs/development/workflow.md`](../docs/development/workflow.md).
The lines below are rules; each links to the stage that owns the narrative.

### Plan before you edit

- Classify the change by Difficulty before you touch code. `complex` goes to Design, `moderate` to Plan, `trivial` straight to Execute — see [workflow.md#stage-1-pickup](../docs/development/workflow.md#stage-1-pickup).
- A change is `trivial` only when all three predicates are provably false: more than one file changes, an interface other code depends on changes, app-facing text changes — see [workflow.md#stage-1-pickup](../docs/development/workflow.md#stage-1-pickup).
- Repository documentation is not app-facing text, so a docs-only change can stay `trivial` — see [workflow.md#stage-1-pickup](../docs/development/workflow.md#stage-1-pickup).
- Picking up a `backlog/` item is never `trivial`: `trivial` classifies work that runs as a housekeeping round, and a round files no item — see [workflow.md#stage-1-pickup](../docs/development/workflow.md#stage-1-pickup).
- Any change to app-facing wording, labels, or names is never `trivial`, even inside one file — see [workflow.md#stage-1-pickup](../docs/development/workflow.md#stage-1-pickup).
- Run `superpowers:brainstorming` and `mp-grilling` before you write code, not after — see [workflow.md#stage-2-design](../docs/development/workflow.md#stage-2-design).
- Give a `trivial` change an inline plan of at most ten lines in chat: files, change, verification artifact, difficulty verdict — see [workflow.md#stage-3-plan](../docs/development/workflow.md#stage-3-plan).

### Create the worktree before you write the plan

- Create the worktree first, with `scripts/new-worktree.ps1` or the native `EnterWorktree` tool. Never start a plan in the main checkout and move the work later — see [workflow.md#stage-1-pickup](../docs/development/workflow.md#stage-1-pickup).
- Write and commit the spec and the plan from the main checkout, under `docs/superpowers/specs/` and `docs/superpowers/plans/` — see [workflow.md#stage-2-design](../docs/development/workflow.md#stage-2-design).
- Switch into the worktree for code, tests, docs, and config, and commit them there — see [workflow.md#stage-4-execute](../docs/development/workflow.md#stage-4-execute).
- Edit and commit a plan a review round changed from the worktree. The guard allows writes inside `docs/superpowers/` — see [workflow.md#stage-8-review](../docs/development/workflow.md#stage-8-review).
- Commit plans with `git -C docs/superpowers commit`. Never use `cd docs/superpowers && git commit`: the guard reads the command before the shell runs the `cd`, so it still sees the main checkout and blocks the commit — see [workflow.md#stage-3-plan](../docs/development/workflow.md#stage-3-plan).
- Write inside the worktree's `docs/superpowers/` link, but never rename or delete the folder itself. It is a separate private repo that `scripts/new-worktree.ps1` links into each worktree — see [workflow.md#stage-1-pickup](../docs/development/workflow.md#stage-1-pickup).

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
