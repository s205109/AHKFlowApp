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

- Classify the change by Difficulty before you touch code. `complex` and `to-be-determined` go to Design, `moderate` to Plan, `trivial` straight to Execute — see [workflow.md#stage-1-pickup](../docs/development/workflow.md#stage-1-pickup).
- A change is `trivial` only when all three predicates of the source's trivial test are provably false. Read the test there; it carries the exemptions — see [workflow.md#stage-1-pickup](../docs/development/workflow.md#stage-1-pickup).
- Repository documentation is not app-facing text, so a docs-only change can stay `trivial` — see [workflow.md#stage-1-pickup](../docs/development/workflow.md#stage-1-pickup).
- Picking up a `backlog/` item is never `trivial` — see [workflow.md#stage-1-pickup](../docs/development/workflow.md#stage-1-pickup).
- Closing an item whose work already merged is not a pickup: tick the boxes, set `Stage: 9-ship`, and `git mv` it into `backlog/done/` inside a housekeeping round, with no new item and no dedicated worktree — see [workflow.md#stage-1-pickup](../docs/development/workflow.md#stage-1-pickup).
- Any change to app-facing wording, labels, or names is never `trivial`, even inside one file — see [workflow.md#stage-1-pickup](../docs/development/workflow.md#stage-1-pickup).
- Grill the design with `mp-grilling` and `mp-domain-modeling` together before you write code, not after. `/mp-grill-with-docs` is the human's shortcut for the same pair, and an agent cannot call it — see [workflow.md#stage-2-design](../docs/development/workflow.md#stage-2-design).
- Grill the draft plan with `mp-grilling`, then run the fabrication check — see [workflow.md#stage-3-plan](../docs/development/workflow.md#stage-3-plan).
- Give a `trivial` change an inline plan of at most ten lines in chat: files, change, verification artifact, difficulty verdict. Trivial work skips Plan, so the inline plan is what Execute enters on — see [workflow.md#stage-4-execute](../docs/development/workflow.md#stage-4-execute).

### Create the worktree before you write the plan

- Create the worktree first, with `scripts/new-worktree.ps1`. Never start a plan in the main checkout and move the work later — see [workflow.md#stage-1-pickup](../docs/development/workflow.md#stage-1-pickup).
- Prefer `scripts/new-worktree.ps1` over the native `EnterWorktree` tool while a plan or spec is being written: in a `-w` session Claude Code's own isolation refuses `Edit` and `Write` under `docs/superpowers/`, and no worktree copy of that path can exist. Details and the measurement: [`docs/agents/cross-agent-git-guardrails.md`](../docs/agents/cross-agent-git-guardrails.md) — see [workflow.md#stage-1-pickup](../docs/development/workflow.md#stage-1-pickup).
- Write and commit the spec from the worktree, under `docs/superpowers/specs/` — see [workflow.md#stage-2-design](../docs/development/workflow.md#stage-2-design).
- Write and commit the plan from the worktree, under `docs/superpowers/plans/` — see [workflow.md#stage-3-plan](../docs/development/workflow.md#stage-3-plan).
- Switch into the worktree for code, tests, docs, and config, and commit them there — see [workflow.md#stage-4-execute](../docs/development/workflow.md#stage-4-execute).
- Edit and commit a plan a grilling round changed from the worktree. The guard allows writes inside `docs/superpowers/` — see [workflow.md#stage-3-plan](../docs/development/workflow.md#stage-3-plan).
- Commit plans with `git -C docs/superpowers commit`, which names the repository the commit belongs to — see [workflow.md#stage-3-plan](../docs/development/workflow.md#stage-3-plan).
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
