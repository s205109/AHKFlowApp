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
- Closing an item whose work already merged is not a pickup: tick the boxes, set `Stage: 9-ship`, and `git mv` it into `backlog/done/` inside a housekeeping round, with no new item and no dedicated worktree. The tick stays here, and not at Document as `AGENTS.md` otherwise requires, because the work already merged and Stage 7 never runs on this path — see [workflow.md#stage-1-pickup](../docs/development/workflow.md#stage-1-pickup).
- Any change to app-facing wording, labels, or names is never `trivial`, even inside one file — see [workflow.md#stage-1-pickup](../docs/development/workflow.md#stage-1-pickup).
- Grill the design with `mp-grilling` and `mp-domain-modeling` together before you write code, not after. `/mp-grill-with-docs` is the human's shortcut for the same pair, and an agent cannot call it — see [workflow.md#stage-2-design](../docs/development/workflow.md#stage-2-design).
- Grill the draft plan with `mp-grilling`, then run the fabrication check — see [workflow.md#stage-3-plan](../docs/development/workflow.md#stage-3-plan).
- Give a `trivial` change an inline plan of at most ten lines in chat: files, change, verification artifact, difficulty verdict. Trivial work skips Plan, so the inline plan is what Execute enters on — see [workflow.md#stage-4-execute](../docs/development/workflow.md#stage-4-execute).

### Create the worktree before you write the plan

- Create the worktree first, with `scripts/new-worktree.ps1`. Then switch the session into it with the native `EnterWorktree` tool, passing the `path` the script printed. Never start a plan in the main checkout and move the work later — see [workflow.md#stage-1-pickup](../docs/development/workflow.md#stage-1-pickup).
- Both steps are needed, and in that order. The script sets up the manifest, the ports, and the no-auth config. Entering is what makes the location durable: a resumed session comes back to the worktree, and this repository's own worktree write guard starts working because it reads the working directory — see [workflow.md#stage-1-pickup](../docs/development/workflow.md#stage-1-pickup).
- Enter with `path`. Never create a worktree with `EnterWorktree` and a `name`. That route runs the same script through the `WorktreeCreate` hook, but it cannot pass `-Title`, which keeps the worktree name equal to the backlog item's, and it cannot pass `-BaseRef`, which stacks work on an unmerged branch. It also leaves a worktree the exit prompt offers to delete. Reasons in full: [`docs/adr/0012-pickup-enters-the-worktree.md`](../docs/adr/0012-pickup-enters-the-worktree.md) — see [workflow.md#stage-1-pickup](../docs/development/workflow.md#stage-1-pickup).
- Step outside the worktree to commit a plan or a spec. Once the session is entered, Claude Code refuses every command that sends git into `docs/superpowers/`, because that folder links back to the main checkout. `AHKFLOW_ALLOW_MAIN=1` does not lift it — the refusal is the harness, not this repository. Use `ExitWorktree` with `keep`, commit, then `EnterWorktree` with the same `path` — see [workflow.md#stage-3-plan](../docs/development/workflow.md#stage-3-plan).
- Write a plan or a spec without the native `Edit` and `Write` tools. They are refused under `docs/superpowers/`, and the refusal names a worktree copy that cannot exist. Write the file from the shell, or write it somewhere else and copy it in — see [workflow.md#stage-3-plan](../docs/development/workflow.md#stage-3-plan).
- Keep shell commands short and write every path out in full inside an entered worktree. Claude Code refuses a command it cannot verify stays inside the worktree, which includes loops and command substitution. This repository's guard refuses a write whose target path it cannot expand, which includes a shell variable — see [workflow.md#stage-4-execute](../docs/development/workflow.md#stage-4-execute).
- Write the spec from inside the worktree, under `docs/superpowers/specs/`, and commit it with the step-outside cycle — see [workflow.md#stage-2-design](../docs/development/workflow.md#stage-2-design).
- Write the plan from inside the worktree, under `docs/superpowers/plans/`, and commit it with the step-outside cycle — see [workflow.md#stage-3-plan](../docs/development/workflow.md#stage-3-plan).
- Write and commit code, tests, docs, and config from inside the worktree. Only the plans repository needs the step outside — see [workflow.md#stage-4-execute](../docs/development/workflow.md#stage-4-execute).
- Edit a plan a grilling round changed from inside the worktree. Writing there is allowed. Committing it is not, so it takes the same step-outside cycle as the first commit — see [workflow.md#stage-3-plan](../docs/development/workflow.md#stage-3-plan).
- Commit plans with `git -C docs/superpowers commit`, which names the repository the commit belongs to. Run it from the main checkout, after `ExitWorktree` with `keep` — see [workflow.md#stage-3-plan](../docs/development/workflow.md#stage-3-plan).
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
