@../AGENTS.md

Be concise in all interactions.

Your chat replies follow the `Plain English` output style (user level).
Text written into this repository — docs, specs, plans, app-facing strings — follows
**Plain English** in AGENTS.md. Commit messages are exempt from both: be extremely
concise, sacrifice grammar for brevity.

# Claude Code Configuration

> Sections below are specific to Claude Code. Shared instructions are in AGENTS.md.

## Workflow Preferences

The canonical process is [`docs/development/workflow.md`](../docs/development/workflow.md).
The lines below are rules; each links to the stage that owns the narrative.

### Plan before you edit

- Classify the change by Difficulty before you touch code. A `backlog/` pickup is never `trivial`, and neither is a change to app-facing wording, labels, or names — see [Stage 1](../docs/development/workflow.md#stage-1-pickup).
- Grill a design with `mp-grilling` and `mp-domain-modeling` together, before any code. Only the human can run `/mp-grill-with-docs` — see [Stage 2](../docs/development/workflow.md#stage-2-design).
- Grill a draft plan with `mp-grilling`, then run the fabrication check — see [Stage 3](../docs/development/workflow.md#stage-3-plan).
- Give a `trivial` change an inline plan in chat, at most ten lines long — see [Stage 4](../docs/development/workflow.md#stage-4-execute).

### Create the worktree before you write the plan

- Create the worktree with `scripts/new-worktree.ps1`, then enter it with `EnterWorktree` and the `path` the script printed. Never create one with `EnterWorktree` and a `name` — see [Stage 1](../docs/development/workflow.md#stage-1-pickup).
- In an entered session, Claude Code refuses git into `docs/superpowers/`, and the `Edit` and `Write` tools there. Write a plan or spec from the shell. To commit it, use `ExitWorktree` with `keep`, run the two commands from **Plans** in AGENTS.md, then use `EnterWorktree` with the same `path` — see [Stage 3](../docs/development/workflow.md#stage-3-plan).
- Inside a worktree, write every path in full. The guard refuses a write it cannot expand, such as a path with a shell variable. In an entered session, also avoid loops and `$(...)` — see [Stage 4](../docs/development/workflow.md#stage-4-execute).
- Never rename or delete the worktree's `docs/superpowers/` link. It is the separate plans repository — see [Stage 1](../docs/development/workflow.md#stage-1-pickup).

### Other

- When asked to store an instruction or a rule, put it in CLAUDE.md or `.claude/rules/`.
  Do not put it in an auto memory file unless I ask for one in that turn. Auto memory is on by
  default and writes notes Claude chooses itself; it is not a place for instructions I gave you.
  Toggle it from `/memory`.
- Verifying finished work is governed by **Verification After Implementation** in AGENTS.md. Invoke the `playwright-cli` skill via the Skill tool when that routing calls for a browser drive.
- Before claiming a tool or capability is unavailable, check `.claude/skills/` and available skills. Never assume browser automation is missing — `playwright-cli` is installed.

### Watch a background run

- A background command must let its output reach stdout. Never redirect a run's output to another
  file and echo only an exit code. The task output file is the log the human tails.
- Hand over the watch command with the full absolute path of `scripts/watch-task.ps1`, in the
  checkout the run belongs to. For example
  `pwsh C:\Dev\segocom-github\AHKFlowApp\scripts\watch-task.ps1`. Never hand over the temporary
  task-output path.
- Write the absolute path even though it is longer. Several worktrees are usually open at once,
  and each holds its own copy of the script, so `./scripts/watch-task.ps1` does not say which
  checkout to run it from. The reader should never have to work that out.

## Out of Scope

- Runtime execution of AutoHotkey scripts — intentionally excluded (the app generates `.ahk` files, never runs them)

Pending features are tracked in `backlog/`.

## Project Configuration

- Rules (always loaded): `.claude/rules/`
- Skills (on demand): `.claude/skills/`
- Backlog: `backlog/` (repo root) — open items; completed items live in `done/`; items blocked on something outside this repository live in `blocked/`; items that are possible today and not worth doing live in `icebox/`. The PR that finishes an item also moves its file into `done/` — see **Git Workflow** in AGENTS.md
- Frontend instructions: `src/Frontend/AHKFlowApp.UI.Blazor/CLAUDE.md`
- Private/local config: `.claude/CLAUDE.local.md` (gitignored)
- Documentation: `docs/` — architecture, azure, development guides
