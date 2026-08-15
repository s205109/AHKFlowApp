# Process alignment checklist

`workflow.md` is the canon. `.claude/CLAUDE.md` carries rules that point into it. This file
records one judgement per rule, because no script can decide whether two sentences say the
same thing in different words.

Re-run this review whenever either file changes.

| Verdict | Meaning |
|---|---|
| `links-only` | The bullet states a rule and defers to the stage for the narrative. Correct. |
| `restates` | The bullet repeats something the linked stage also says. Rewrite it to defer. |
| `conflicts` | The bullet and the linked stage disagree. `workflow.md` wins; fix the bullet. |

The review is finished when every row reads `links-only`.

**The test used here.** A bullet may say what to do in one sentence. It may not carry the
canon's reasoning, its worked examples, or a second copy of a stage's narrative. A rule is
rule content; the "why" behind it belongs to the stage.

## Plan before you edit

| # | Bullet begins | Links to | Verdict |
|---|---|---|---|
| 1 | Classify the change by Difficulty | stage-1-pickup | `links-only` |
| 2 | A change is `trivial` only when | stage-1-pickup | `links-only` |
| 3 | Repository documentation is not app-facing | stage-1-pickup | `links-only` |
| 4 | Picking up a `backlog/` item is never | stage-1-pickup | `links-only` — was `restates`, fixed |
| 5 | Closing an item whose work already merged | stage-1-pickup | `links-only` |
| 6 | Any change to app-facing wording | stage-1-pickup | `links-only` |
| 7 | Run `superpowers:brainstorming` | stage-2-design | `links-only` — was `conflicts`, fixed |
| 8 | Give a `trivial` change an inline plan | stage-3-plan | `links-only` |

## Create the worktree before you write the plan

| # | Bullet begins | Links to | Verdict |
|---|---|---|---|
| 9 | Create the worktree first | stage-1-pickup | `links-only` |
| 10 | Write and commit the spec and the plan | stage-2-design | `links-only` — was `conflicts`, fixed |
| 11 | Switch into the worktree for code | stage-4-execute | `links-only` |
| 12 | Edit and commit a plan a review round changed | stage-8-review | `links-only` |
| 13 | Commit plans with `git -C docs/superpowers commit` | stage-3-plan | `links-only` |
| 14 | Write inside the worktree's `docs/superpowers/` link | stage-1-pickup | `links-only` |

## What changed, and why

**Row 4 repeated the canon's reasoning.** The bullet read "Picking up a `backlog/` item is
never `trivial`: `trivial` classifies work that runs as a housekeeping round, and a round
files no item". The clause after the colon is the canon's own justification, in the same
words as `workflow.md` section "The Difficulty jump". The rule stayed; the reasoning went
back to the stage.

**Row 7 named the wrong Design technique.** The bullet said to run `superpowers:brainstorming`
and `mp-grilling` before writing code. The canon says `mp-grill-with-docs` is the Design
technique, and `mp-grilling` runs later, on the draft plan, before the fabrication check. A
session following `.claude/CLAUDE.md` would have run the Plan technique at Design and never
run the Design one. The bullet now names both techniques at the stages that own them.

**Row 10 contradicted the canon outright.** The bullet said to write and commit the spec and
the plan "from the main checkout". The canon says both the file edit and the plans-repo
commit run from the worktree, because the guard gates only commands that could change the
protected checkout, and the plans repository is a different repository. Row 12 of the same
file already said "from the worktree", so `.claude/CLAUDE.md` disagreed with itself as well
as with the canon. The bullet now says the worktree.

No canon change was needed. Nothing in these 14 rows made `workflow.md` look wrong.
