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

The review is finished when every row reads `links-only`.

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
| 7 | Grill the design with `mp-grill-with-docs` | stage-2-design | `links-only` — was `conflicts`, fixed |
| 8 | Grill the draft plan with `mp-grilling` | stage-3-plan | `links-only` — split out of row 7 |
| 9 | Give a `trivial` change an inline plan | stage-4-execute | `links-only` — was `wrong stage`, fixed |

## Create the worktree before you write the plan

| # | Bullet begins | Links to | Verdict |
|---|---|---|---|
| 10 | Create the worktree first | stage-1-pickup | `links-only` |
| 11 | Prefer `scripts/new-worktree.ps1` over the native | stage-1-pickup | `links-only` — new, see the open question below |
| 12 | Write and commit the spec | stage-2-design | `links-only` — was `wrong stage`, fixed |
| 13 | Write and commit the plan | stage-3-plan | `links-only` — split out of row 12 |
| 14 | Switch into the worktree for code | stage-4-execute | `links-only` |
| 15 | Edit and commit a plan a grilling round changed | stage-3-plan | `links-only` — was `wrong stage`, fixed |
| 16 | Commit plans with `git -C docs/superpowers commit` | stage-3-plan | `links-only` — was `conflicts`, fixed |
| 17 | Write inside the worktree's `docs/superpowers/` link | stage-1-pickup | `links-only` |

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
`mp-grilling` before writing code. The mandatory rule in workflow.md is that `mp-grill-with-docs` is
the Design technique and `mp-grilling` runs later, on the draft plan. A session following
`.claude/CLAUDE.md` would have run the Plan technique at Design and never the Design one. The
two techniques now sit in two bullets, each anchored to the stage that owns it.

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

## Open question for workflow.md

**Row 11 records a gap this review is not allowed to close.** `workflow.md` says both the file
edit and the plans-repo commit run from the worktree, and cites the repository guard. That is
true of this repository's guard. It is not the whole picture for Claude Code: in a session
started with `-w`, `--worktree`, or the `EnterWorktree` tool, the harness's own isolation
refuses `Edit` and `Write` under `docs/superpowers/` and tells the agent to edit "the worktree
copy", which cannot exist for that path. `docs/agents/cross-agent-git-guardrails.md` records
the measurement and `backlog/blocked/058-native-edit-refusal-names-missing-worktree-copy.md`
tracks the upstream report.

So a session that follows `.claude/CLAUDE.md` and starts its worktree with `EnterWorktree`
cannot write the plan the same file tells it to write. `.claude/CLAUDE.md` now warns about it.
workflow.md still does not mention the case.

**This is a question for workflow.md, and it is open.** An alignment pass may not edit `workflow.md`;
changing workflow.md here would mean measuring alignment against a document the same pass moved.
Decide the wording at Design, in a round of its own.
