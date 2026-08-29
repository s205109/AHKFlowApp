# Process alignment checklist

`workflow.md` is the source. `.claude/CLAUDE.md` carries rules that point into it. This file
records one judgement per rule, because no script can decide whether two sentences say the
same thing in different words.

Re-run this review whenever either file changes. Bullet numbers move as the file changes, so
each row names the words the bullet starts with rather than a line number.

| Verdict | Meaning |
|---|---|
| `links-only` | The bullet states a rule and defers to the stage for the narrative. Correct. |
| `restates` | The bullet repeats something the linked stage also says. Rewrite it to defer. |
| `conflicts` | The bullet and the linked stage disagree. `workflow.md` wins; fix the bullet. |
| `wrong stage` | The bullet is right, but its anchor names a stage that does not own the rule. |

The review is finished when every row reads `links-only`. Every live row does. Row 11 is struck
through: backlog 118 deleted the bullet it tracked, and the gap it recorded is closed. Rows 18
to 22 are the bullets backlog 118 added.

**The test used here.** A bullet may say what to do in one sentence. It may not carry the
reasoning from `workflow.md`, its worked examples, or a second copy of a stage's narrative. A rule is
rule content; the "why" behind it belongs to the stage. A bullet must also link to the stage
that **owns** the rule — an anchor that merely points somewhere plausible hides drift instead
of catching it.

## Plan before you edit

| # | Bullet begins | Links to | Verdict |
|---|---|---|---|
| 1 | Classify the change by Difficulty | stage-1-pickup | `links-only` — was `conflicts`, fixed |
| 2 | A change is `trivial` only when | stage-1-pickup | `links-only` — was `restates`, fixed |
| 3 | Repository documentation is not app-facing | stage-1-pickup | `links-only` |
| 4 | Picking up a `backlog/` item is never | stage-1-pickup | `links-only` — was `restates`, fixed |
| 5 | Closing an item whose work already merged | stage-1-pickup | `links-only` |
| 6 | Any change to app-facing wording | stage-1-pickup | `links-only` |
| 7 | Grill the design with `mp-grilling` and `mp-domain-modeling` | stage-2-design | `links-only` — was `conflicts`, then renamed by backlog 109 |
| 8 | Grill the draft plan with `mp-grilling` | stage-3-plan | `links-only` — split out of row 7 |
| 9 | Give a `trivial` change an inline plan | stage-4-execute | `links-only` — was `wrong stage`, fixed |

## Create the worktree before you write the plan

| # | Bullet begins | Links to | Verdict |
|---|---|---|---|
| 10 | Create the worktree first | stage-1-pickup | `links-only` — backlog 118 added the entry step |
| 11 | ~~Prefer `scripts/new-worktree.ps1` over the native~~ | — | removed by backlog 118. The route now uses both, in order |
| 12 | Write the spec from inside the worktree | stage-2-design | `links-only` — was `wrong stage`, fixed |
| 13 | Write the plan from inside the worktree | stage-3-plan | `links-only` — split out of row 12 |
| 14 | Write and commit code, tests, docs | stage-4-execute | `links-only` |
| 15 | Edit a plan a grilling round changed | stage-3-plan | `links-only` — was `wrong stage`, fixed |
| 16 | Commit plans with `git -C docs/superpowers commit` | stage-3-plan | `links-only` — was `conflicts`, fixed |
| 17 | Write inside the worktree's `docs/superpowers/` link | stage-1-pickup | `links-only` |
| 18 | Both steps are needed, and in that order | stage-1-pickup | `links-only` — new in backlog 118 |
| 19 | Enter with `path` | stage-1-pickup | `links-only` — new in backlog 118 |
| 20 | Step outside the worktree to commit | stage-3-plan | `links-only` — new in backlog 118 |
| 21 | Write a plan or a spec without the native | stage-3-plan | `links-only` — new in backlog 118 |
| 22 | Keep shell commands short | stage-4-execute | `links-only` — new in backlog 118 |

## What changed, and why

**Row 1 omitted a Difficulty value.** The bullet routed `complex`, `moderate` and `trivial`
and said nothing about `to-be-determined`, which the Difficulty table in workflow.md sends to Design.
A session reading only `.claude/CLAUDE.md` had no route for it.

**Row 2 stated the trivial test more strictly than workflow.md does.** It read "all three
predicates are provably false: more than one file changes, ...". workflow.md exempts a
backlog-item tick from the file-count predicate, and says a pure typo or format fix may span
files. The bullet now names the test and sends the reader to it, so the exemptions have one
home.

**Row 4 repeated the reasoning in workflow.md.** The bullet carried the justification from workflow.md for
why a filed item is never `trivial`. The rule stayed; the reasoning went back to the stage.

**Row 7 named the wrong Design technique.** It said to run `superpowers:brainstorming` and
`mp-grilling` before writing code. The Design technique is `mp-grilling` with
`mp-domain-modeling`, run together, and `mp-grilling` runs again later on the draft plan. A
session following `.claude/CLAUDE.md` would have run the Plan technique at Design and never
the Design one. The two techniques now sit in two bullets, each anchored to the stage that
owns it. Backlog 109 later renamed the Design technique from `mp-grill-with-docs` to the pair
of skills it wraps, because an agent cannot call the wrapper.

**Rows 9, 12 and 15 pointed at the wrong stage.** The inline plan for trivial work was
anchored to Plan, which trivial work skips — Execute's entry is "plan committed, or inline plan
stated", so Execute owns it. The spec-and-plan bullet was anchored to Design alone, although
the plan belongs to Plan; it is now two bullets. The plan-edit-after-review bullet was anchored
to Review, but a review round that changes a plan is the Plan-stage grilling; Review sends any
finding needing a change back to Execute.

**Row 16 gave a false reason.** It said `cd docs/superpowers && git commit` is blocked because
the guard reads the command before the shell runs the `cd`. The guard tracks directory changes,
including `cd`, `pushd` and `Set-Location`. Measured against the policy directly:

```
cd docs/superpowers && git commit -m x   ACTION=Allow RULE=none
git -C docs/superpowers commit -m x      ACTION=Allow RULE=none
```

The `git -C` form is still the one to use, because it names the repository the commit belongs
to and does not depend on where the shell happens to be. The false claim about the guard is
gone.

## Closed question for workflow.md

**Row 11 recorded a gap this review was not allowed to close. Backlog 118 closed it.**

The gap was this. `workflow.md` said both the file edit and the plans-repository commit run from
the worktree, and cited this repository's guard. That was true of this repository's guard. It was
not the whole picture for Claude Code: in a session started with `-w`, `--worktree`, or the
`EnterWorktree` tool, the harness's own isolation refuses `Edit` and `Write` under
`docs/superpowers/` and tells the agent to edit "the worktree copy", which cannot exist for that
path. So a session that entered its worktree could not write the plan the same file told it to
write.

Backlog 118 measured the case again on Claude Code `2.1.251`, found the refusal unchanged, and
found it wider than recorded: the harness also refuses every command that sends git into
`docs/superpowers/`. It then made entering the worktree part of Pickup and wrote both facts into
`workflow.md` and `.claude/CLAUDE.md`, with the route around them. The decision and its
consequences are in `docs/adr/0012-pickup-enters-the-worktree.md`.

`backlog/blocked/058-native-edit-refusal-names-missing-worktree-copy.md` stays blocked. Its
remaining step is the report to Anthropic, which is a separate piece of work.
