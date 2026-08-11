# The AHKFlowApp development process

This file describes how work moves through this repository. Work walks eleven stages. Each
stage has five edges. One durable record says where a piece of work stands.

**This file is canonical.** When `AGENTS.md`, `.claude/CLAUDE.md`, a skill, or any other
document disagrees with this file about the process, this file wins. Fix the other
document.

Artifact: (recorded by Task 6)

Related files:

- Which tests to run, and the canonical pre-PR gate:
  [`testing-workflow.md`](testing-workflow.md)
- What an agent may and may not do in the main checkout:
  [`cross-agent-git-guardrails.md`](../agents/cross-agent-git-guardrails.md)
- The same process drawn as a decision tree: [`workflow.html`](workflow.html)
- One printable page: [`ahkflow-workflow-cheatsheet.html`](ahkflow-workflow-cheatsheet.html)
  and [`ahk-workflow.pdf`](ahk-workflow.pdf)

---

## 1. The stage spine

Stage names are fixed. The exit strings below are canonical. They appear word for word in
`workflow.html`, in the cheatsheet, and in this table. A check compares all three.

| # | Stage | Exit condition |
|---|---|---|
| 0 | Intake | Item filed with the script, Difficulty set |
| 1 | Pickup | Location chosen by Difficulty, base confirmed and stated, PR route in place |
| 2 | Design | Spec committed, terms and ADRs written, plain summary confirmed |
| 3 | Plan | Plan committed, grilled, fabrication-checked |
| 4 | Execute | All planned work committed, tracking current, stage push done |
| 5 | Simplify | Simplification applied or verdict 'nothing to simplify' stated |
| 6 | Verify | Verification artifact green, gate green, verdict stated |
| 7 | Document | Docs updated or verdict 'nothing to document' stated |
| 8 | Review | All review threads resolved, gate re-green |
| 9 | Ship | Records closed, PR ready, CI green, merged |
| 10 | Cleanup | Worktree gone, branch deleted, memory updated |

### The bug gate at Design entry

A bug item enters Design only with a stated root cause and evidence. Evidence is a
`file:line`, a log line, or a repro command with its actual output. No evidence, no Design
entry. This turns the AGENTS.md Debugging rule into a gate.

### What the exit strings mean

- **PR route in place.** Tracked work opens its draft pull request at the Pickup push. A
  housekeeping round's route is the round pull request, opened at round close.
- **Tracking current.** For tracked work: plan tasks ticked plus the progress file. For a
  housekeeping round: the commit log.
- **Records closed.** For tracked work: boxes ticked, the item moved to `backlog/done/`,
  the progress file deleted. For a housekeeping round: nothing extra.
- **Terms and ADRs written.** Design pins glossary terms in `CONTEXT.md` and writes the
  ADRs the design needs. Wave 1 of the process is a bootstrap exception: those two files
  are frozen, so its terms and ADR are filed in the wave-2 backlog item instead.
- **The plain summary** is at most ten lines, and the human confirms understanding before
  the plan is written.
- **Stage push done.** Execute makes two local commits per task and pushes once, when the
  stage completes.

---

## 2. The unit contract — tracked item or housekeeping round

The two units walk the same spine with different records. Every edge in section 3 reads
through this table.

| Mechanic | Tracked item | Housekeeping round |
|---|---|---|
| Intake | Once per item. The success edge fires when the item is filed | Once per round, at its first change. The not-applicable edge fires: no item is filed. Later changes in the same round take no Intake edge |
| Durable stage record | The `Stage` field in the backlog item | Before the round pull request exists: the round worktree and its commit log. From the round pull request onward: a `Stage: N-name` line in its body. Simplify, Verify, Document, and Review are verdict-only and leave no commit, so the body is the only record that survives a cleared context |
| First push | At Pickup. It opens the draft pull request | At Execute close. It opens the round pull request |
| Resume | Read the `Stage` field, re-run that stage's entry check | Read the round pull request body's `Stage:` line, re-run that stage's entry check. Before the pull request exists, read the round worktree's commit log |
| Blocked | The item moves to `backlog/blocked/` with the unblock note | Two kinds. A single change that blocks is filed as its own item, leaves the round, and moves to `backlog/blocked/`; the round continues. A round-level blocker belongs to no single change: file an item naming the round pull request and the blocker, move that item to `backlog/blocked/`, and stop the round |
| Records at Ship | Boxes ticked, item moved to `backlog/done/`, progress file deleted | Nothing extra |

### The housekeeping round is the stage-machine unit for trivial work

One round walks Intake once (not applicable, because a round has no item), then Pickup,
then Execute, then the verdict stages, then Review, Ship, and Cleanup. Changes accumulate
inside Execute with one commit each. The round closes when a few have gathered. Then it
pushes for the first time and opens the round pull request.

A single trivial change is Execute-internal. It takes no stage edges of its own.

A change that grows in importance does not close the round. It is reclassified and leaves
before the round pushes. Move its files into the new worktree, or cherry-pick its commit
there and drop it from the round's unpushed history.

The post-merge sweep removes the round worktree. The next round starts fresh.

### Writing the round's `Stage:` line

`gh pr edit --body-file` replaces the whole body. So a transition must read the body,
change one line, and write all of it back. Never hand `--body-file` a file that holds only
the Stage line. That deletes the rest of the description.

The round pull request is created at Execute close with a `Stage: 5-simplify` line in its
body. Exactly one such line exists from then on.

```powershell
$pr   = <round PR number>
$next = '<N-name>'                      # e.g. 6-verify
$rx   = '(?m)^Stage: [^\r\n]+'          # CRLF-safe: does not eat the carriage return

$body = gh pr view $pr --repo s205109/AHKFlowApp --json body -q .body
$hits = ([regex]::Matches($body, $rx)).Count
if ($hits -ne 1) { throw "PR $pr body: expected 1 Stage line, found $hits" }

$tmp = New-TemporaryFile
($body -replace $rx, "Stage: $next") | Set-Content $tmp.FullName -Encoding utf8
gh pr edit $pr --repo s205109/AHKFlowApp --body-file $tmp.FullName
Remove-Item $tmp.FullName

gh pr view $pr --repo s205109/AHKFlowApp --json body -q .body | Select-String -Pattern $rx
```

The read-back is the check, and it is part of the transition. It must print
`Stage: <N-name>` once. If it prints nothing, or the old value, the transition did not
happen. The round is still at its previous stage.

---

## 3. The eleven stages

Every stage node carries eight fields: Entry, Who, Technique, Action, Exit, Next, Context,
Review. Then five edges: success, failure, blocked, not applicable, resume.

**Edge target tokens.** Every edge has exactly one target token:

| Token | Meaning |
|---|---|
| a stage id, such as `6-verify` | go to that stage |
| `2-design/3-plan/4-execute` | the Difficulty split: `complex` to Design, `moderate` to Plan, `trivial` to Execute |
| `stay` | re-enter or remain in this stage |
| `terminal` | no next stage |
| `blocked/` | the item moves to `backlog/blocked/` |
| `none` | this edge cannot occur for this stage; the row says why |

**Shared rules.** A skipped stage is never entered and takes no edge. A stage's
not-applicable edge is used only after entry: the stage is entered and found empty, or
reclassification at entry shows the stage does not apply. The verdict is stated out loud
either way.

The blocked edge fires only for the AGENTS.md test: progress depends on something outside
this repository. A wait on the human, or on anything inside the repository, is not an edge.
The stage is simply still in progress.

The two-commit protocol applies to tracked plan work. Trivial housekeeping has no plan and
no progress file: one commit per change.

Where an edge table's Condition column says "exit condition met", the condition is the
stage's Exit field above it.

<a id="stage-0-intake"></a>

### Stage 0 — Intake

- **Entry** — friction, idea, or bug arrives
- **Who** — Sonnet, default effort
- **Technique** — `scripts/new-backlog-item.ps1`
- **Action** — file the item, set Difficulty; for bugs, attach root-cause evidence or mark it `to-be-determined`
- **Exit** — Item filed with the script, Difficulty set
- **Next** — `1-pickup`
- **Context** — safe to clear
- **Review** — not reviewed

| Edge | Condition | Target |
|---|---|---|
| success | filed, Difficulty set | 1-pickup |
| failure | missing Difficulty or summary; complete the item | stay |
| blocked | cannot specify without an external answer; file what is known with the unblock note | blocked/ |
| not applicable | a housekeeping round needs no item — taken once per round, at its first change; the round's commits are the record; say so | 1-pickup |
| resume | item sat idle; revise Difficulty once | 1-pickup |

<a id="stage-1-pickup"></a>

### Stage 1 — Pickup

- **Entry** — item chosen
- **Who** — Sonnet, default effort
- **Technique** — `scripts/new-worktree.ps1` (`-BaseRef` for stacked work), or the housekeeping worktree
- **Action** — choose the execution location by Difficulty: a dedicated worktree for `moderate` and `complex`, the housekeeping worktree for `trivial`. Confirm branch and base, and state both. For a tracked item: stamp Stage, push, open the draft pull request. For a housekeeping round: no item, so no Stage stamp and no push here. The round worktree is the pointer, and the route is the round pull request opened at Execute close
- **Exit** — Location chosen by Difficulty, base confirmed and stated, PR route in place
- **Next** — `2-design/3-plan/4-execute`
- **Context** — safe to clear
- **Review** — not reviewed

| Edge | Condition | Target |
|---|---|---|
| success | location chosen, base stated, PR in place; jump by Difficulty | 2-design/3-plan/4-execute |
| failure | wrong base discovered; recreate the worktree with `-BaseRef` | stay |
| blocked | prerequisite outside the repository; for a round, the one blocked change is filed as its own item and only that item moves | blocked/ |
| not applicable | cannot occur: every item chooses a location | none |
| resume | worktree exists; re-confirm branch and base, then continue at the recorded Stage for a tracked item, or from the round's commit log and PR state for a round | stay |

<a id="stage-2-design"></a>

### Stage 2 — Design

- **Entry** — Difficulty `complex` or `to-be-determined`; bugs enter only with root-cause evidence
- **Who** — `--model opus --effort xhigh`
- **Technique** — `mp-grill-with-docs`
- **Action** — grill the design, write the spec, pin glossary terms and ADRs, write the plain summary of at most 10 lines, and get the human's confirmation
- **Exit** — Spec committed, terms and ADRs written, plain summary confirmed
- **Next** — `3-plan`
- **Context** — keep; it feeds the plan
- **Review** — spec reviewed before Plan

| Edge | Condition | Target |
|---|---|---|
| success | exit condition met | 3-plan |
| failure | spec rejected; revise with the objections | stay |
| blocked | external decision or platform gap | blocked/ |
| not applicable | reclassification at entry: no spec needed; set Difficulty `moderate`, say so; a reclassified `trivial` continues through Plan's not-applicable edge | 3-plan |
| resume | re-read spec and review state, continue grilling or submit | stay |

<a id="stage-3-plan"></a>

### Stage 3 — Plan

- **Entry** — spec approved, or `moderate` item picked
- **Who** — `--model opus --effort xhigh`
- **Technique** — `superpowers:writing-plans`, then `mp-grilling` on the draft, then the fabrication check
- **Action** — write the plan; every task lists its completion criteria and every surface that must change
- **Exit** — Plan committed, grilled, fabrication-checked
- **Next** — `4-execute`
- **Context** — clear before Execute; the plan carries the line numbers
- **Review** — plan reviewed before execution

| Edge | Condition | Target |
|---|---|---|
| success | exit condition met | 4-execute |
| failure | grilling or fabrication check fails; revise | stay |
| blocked | plan exposes an external dependency | blocked/ |
| not applicable | reclassification at entry: `trivial`; inline plan of at most 10 lines in chat; say so | 4-execute |
| resume | plan exists; if execution started, take Plan's success edge and use Execute's resume there; else re-read and submit | stay |

<a id="stage-4-execute"></a>

### Stage 4 — Execute

- **Entry** — plan committed, or inline plan stated
- **Who** — `--model sonnet --effort high`
- **Technique** — `superpowers:executing-plans` inline, or subagent-driven when `complex` plus four or more independent tasks; state the choice
- **Action** — work the tasks. For tracked plan work: two local commits per task boundary, the deliverable then the progress line, with `PLAN-PROGRESS.md` kept current. For a housekeeping round: one commit per change, no progress file, and the round closes when a few changes have gathered. One push when the stage completes. 'Tracking' means the plan plus the progress file for tracked work, and the commit log for a round
- **Exit** — All planned work committed, tracking current, stage push done
- **Next** — `5-simplify`
- **Context** — safe to clear at any task boundary
- **Review** — not yet reviewed

| Edge | Condition | Target |
|---|---|---|
| success | exit condition met | 5-simplify |
| failure | a task's check is red; root cause unclear → `superpowers:systematic-debugging` before the next edit | stay |
| blocked | external blocker mid-run; commit the checkpoint with the unblock note | blocked/ |
| not applicable | cannot occur: every item executes something | none |
| resume | tracked work: read `PLAN-PROGRESS.md`, continue at the first task without a progress line, never redo a committed task; a round: read the commit log, continue committing | stay |

<a id="stage-5-simplify"></a>

### Stage 5 — Simplify

- **Entry** — tasks done
- **Who** — Sonnet, default effort
- **Technique** — `/simplify` (`code-simplifier`)
- **Action** — fold duplication, delete dead code; the gate must stay green
- **Exit** — Simplification applied or verdict 'nothing to simplify' stated
- **Next** — `6-verify`
- **Context** — safe to clear
- **Review** — not yet reviewed

| Edge | Condition | Target |
|---|---|---|
| success | exit condition met | 6-verify |
| failure | simplification broke the gate; revert or fix | stay |
| blocked | external blocker | blocked/ |
| not applicable | entered and found empty — docs-only or trivial; say 'nothing to simplify' | 6-verify |
| resume | re-run `/simplify` on the diff; it is repeatable | stay |

<a id="stage-6-verify"></a>

### Stage 6 — Verify

- **Entry** — code settled
- **Who** — Sonnet, default effort
- **Technique** — the AGENTS.md Verification routing table (`dck-verify`)
- **Action** — produce the verification artifact the table names, and run the gate. A wait on the human for manual steps keeps the stage in progress; it is not an edge. Under an AGENTS.md exemption, the exemption's own work is the artifact and the gate. For exemption 1 that is targeted text checks plus diff review. Name the exemption, state the verdict, and take the success edge
- **Exit** — Verification artifact green, gate green, verdict stated
- **Next** — `7-document`
- **Context** — safe to clear after green
- **Review** — not yet reviewed

| Edge | Condition | Target |
|---|---|---|
| success | exit condition met | 7-document |
| failure | red; carry the failing output back | 4-execute |
| blocked | verification depends on something outside the repository | blocked/ |
| not applicable | cannot occur: AGENTS.md requires a verdict either way, and an exemption is itself verification work — targeted checks plus diff review — so an exempt change takes the success edge with the exemption named | none |
| resume | re-run the verification commands; they are reproducible | stay |

<a id="stage-7-document"></a>

### Stage 7 — Document

- **Entry** — behaviour, vocabulary, or a rule moved — or the check that none did
- **Who** — Sonnet, default effort
- **Technique** — docs edit plus `CONTEXT.md` and skill updates
- **Action** — update docs, README, and skills; or state the verdict
- **Exit** — Docs updated or verdict 'nothing to document' stated
- **Next** — `8-review`
- **Context** — safe to clear
- **Review** — not yet reviewed

| Edge | Condition | Target |
|---|---|---|
| success | exit condition met | 8-review |
| failure | docs found contradicting the change; fix | stay |
| blocked | external doc dependency | blocked/ |
| not applicable | entered, nothing moved — 'nothing to document'; the verdict is mandatory, silence is not | 8-review |
| resume | diff docs against the change, continue | stay |

<a id="stage-8-review"></a>

### Stage 8 — Review

- **Entry** — work presentable, pushed at the last stage boundary, pull request still draft
- **Who** — `--model opus --effort high`; Codex locally posts to the same pull request threads
- **Technique** — `custom-review-findings` (PR mode)
- **Action** — review lands as pull request threads. Verify, fix, reply, resolve. A wait on the reviewer keeps the stage in progress; it is not an edge
- **Exit** — All review threads resolved, gate re-green
- **Next** — `9-ship`
- **Context** — keep until threads resolved
- **Review** — reviewed; state it in the recap

| Edge | Condition | Target |
|---|---|---|
| success | exit condition met | 9-ship |
| failure | findings need code changes; then Simplify, Verify, Document again as needed | 4-execute |
| blocked | a finding depends on something outside the repository | blocked/ |
| not applicable | cannot occur: every pull request — a tracked item's or a round's — is reviewed | none |
| resume | fetch unresolved threads, continue with `custom-review-findings` | stay |

<a id="stage-9-ship"></a>

### Stage 9 — Ship

- **Entry** — review closed
- **Who** — Sonnet, default effort
- **Technique** — `gh pr ready`, then merge
- **Action** — close the records, flip the pull request to ready, wait for CI, merge. Tracked work: tick the item's boxes, `git mv` it to `backlog/done/`, delete `PLAN-PROGRESS.md`, set `Stage: 9-ship`. A round: nothing extra
- **Exit** — Records closed, PR ready, CI green, merged
- **Next** — `10-cleanup`
- **Context** — keep until the pull request description is final; safe after merge
- **Review** — reviewed

Ship flips the pull request to ready and closes the records before CI runs. So both
non-success edges must undo what Ship already did.

Failure converts the pull request back to draft
(`gh pr ready <number> --undo --repo s205109/AHKFlowApp`). It returns to a pre-Review
stage, and Review's entry condition is a draft pull request. Without the undo, that path is
shut. Blocked keeps the ready pull request, because it resumes at Ship, and Ship needs a
ready pull request.

Both edges push whenever they make a commit. Ship's success is the only Ship transition
that never pushes: the merge carries it.

A round has no item, no progress file, and nothing extra to close at Ship. Its non-success
edges restore no records. They rewrite the `Stage:` line in the round pull request body
instead, and they push only if the recovery work itself makes a commit.

| Edge | Condition | Target |
|---|---|---|
| success | merged; no push — the merge carries it | 10-cleanup |
| failure | CI red after ready; convert the PR back to draft first. Tracked item: `git mv` the item back out of `backlog/done/`, restore `PLAN-PROGRESS.md`, set `Stage: 6-verify` — one commit — then push. A round: rewrite the PR body's `Stage:` line to `6-verify`; no records to restore, no transition commit, so no push. Start recovery only after that | 6-verify |
| blocked | merge depends on something outside the repository, such as a required-check outage; the PR stays ready. Tracked item: restore `PLAN-PROGRESS.md`, `git mv` the item from `backlog/done/` to `backlog/blocked/` with the unblock note, keep `Stage: 9-ship`, commit, push. A round has no item: file one naming the round PR and the blocker, move that item to `backlog/blocked/`, and leave the round PR body at `Stage: 9-ship` | blocked/ |
| not applicable | cannot occur: everything ships through a pull request | none |
| resume | `gh pr view` for the live state, continue from ready-flip or merge | stay |

<a id="stage-10-cleanup"></a>

### Stage 10 — Cleanup

- **Entry** — pull request merged
- **Who** — Sonnet, default effort
- **Technique** — worktree removal scripts, then session end
- **Action** — remove the worktree and branch, clear context, update memory. A local holder process, such as a second terminal in the folder, is a failure to retry, not a blocked edge
- **Exit** — Worktree gone, branch deleted, memory updated
- **Next** — `terminal`; the `done/` location plus the merged pull request are the durable record, and the Stage field is never written after merge
- **Context** — clear freely
- **Review** — reviewed

All three exit conditions are checked, never the worktree alone. The removal script has a
documented outcome that removes the worktree and keeps the branch
(`scripts/remove-worktree-local-dev.ps1:921`, "worktree removed; branch preserved").

Both git checks name the main checkout with `-C`, and the branch check accepts exit code 1
only. Cleanup deletes the worktree folder, so the session may be left in no repository at
all. There `git show-ref` exits 128 for every ref, including refs that still exist. Exit 1
means the branch is absent. Any other non-zero code is a failed check, not a deleted
branch. The removal script scopes its own check the same way
(`scripts/remove-worktree-local-dev.ps1:911`).

| Edge | Condition | Target |
|---|---|---|
| success | all three confirmed — `git -C <main-checkout> worktree list` shows no entry, `git -C <main-checkout> show-ref --verify --quiet refs/heads/<branch>` exits 1, memory updated | terminal |
| failure | removal attempt failed — a holder process or a lock; name the holder, follow the removal log's manual guidance, retry | stay |
| blocked | removal depends on something outside the repository, such as an upstream tooling bug. The work already merged, so the original item stays in `backlog/done/`: file a new item naming the merged PR, the worktree path, the blocker, and what would unblock it, and move that new item to `backlog/blocked/` | blocked/ |
| not applicable | cannot occur: Cleanup is entered only after a merge, and a round mid-flight never reaches it | none |
| resume | re-check all three; worktree present → continue removal; worktree absent but branch still there → delete the branch; both gone but memory not written → update memory; all three done → take the success edge | stay |

---

## 4. The current-stage field

One line in the backlog item, above the acceptance boxes:

```
Stage: 4-execute
```

Values run from `0-intake` to `10-cleanup`. This section governs tracked items. A
housekeeping round has no item, so it writes the same value into its round pull request
body instead, in the same transition that would write an item's field. See section 2 for
the read-modify-write command sequence.

**Writer rule.** Whoever completes a stage transition — normally the agent — updates the
field in the same commit that completes the stage. A failure edge sets the field back to
the target stage. A blocked item keeps its last stage; the move to `backlog/blocked/` plus
the unblock note carry the rest.

The field lives in the work branch during a task. The draft pull request is the live
pointer from `main`. If branch name, pull request state, and field disagree, the field
wins. The others are evidence.

**Two-repo transitions (Design, Plan).** Commits are ordered. First the artifact to the
private plans repo (`git -C docs/superpowers commit`), then the Stage-field update to the
public work branch. The public Stage commit is the authoritative transition marker.

**Push boundaries.** Push at every pre-merge stage completion that has a live branch and a
transition commit — stages 1 to 8. A tracked item's Pickup push is the first push and opens
the draft pull request, so the pull request exists from stage 1 and can point at stages 2
and 3. A housekeeping round's first push comes at Execute close and opens the round pull
request. Ship success ends through the merge, and Cleanup runs after it. Neither pushes,
and after the merge the branch is gone.

**Ship failure and Ship blocked undo what Ship already did.** Both happen pre-merge on a
live branch. For a tracked item: `git mv` the item back out of `backlog/done/`, restore
`PLAN-PROGRESS.md`, then set the Stage the edge names. One commit carries the restore and
the Stage; then push. Recovery starts only after that push, so the pull request never shows
an item closed while its work reopens. For a housekeeping round there is nothing to
restore: rewrite the `Stage:` line in the round pull request body, and push only if the
recovery work itself makes a commit.

**Before the draft pull request exists** — stage 0 to early stage 1 — the number-prefixed
worktree is the live pointer. `git worktree list` or `ls .claude/worktrees/` finds it, and
the worktree's copy of the backlog item carries the Stage field.

**Terminal rule.** The Ship pull request sets `Stage: 9-ship` in the same change that moves
the item to `backlog/done/`. After the merge, the field is never written again. Cleanup
completion is observable, not recorded: the worktree is gone and the branch is deleted. For
any item in `backlog/done/`, the folder supersedes the field.

**A blocker found during Cleanup** has no field to write and no item to move. The work
merged, so the original item stays in `backlog/done/`. File a new item with
`scripts/new-backlog-item.ps1` naming the merged pull request, the worktree path, the
blocker, and what would unblock it. Move that new item to `backlog/blocked/`.

---

## 5. Difficulty and the trivial path

`Difficulty: trivial | moderate | complex | to-be-determined` lives in the backlog item.
Set it at filing. Revise it once at pickup.

Difficulty decides where Pickup jumps and which artifacts the work needs:

| Difficulty | Pickup jumps to | Artifacts |
|---|---|---|
| `complex` | [Design](#stage-2-design) | Spec, then plan, then execution |
| `to-be-determined` | [Design](#stage-2-design) | Design decides the real value first |
| `moderate` | [Plan](#stage-3-plan) | Plan, then execution. No spec |
| `trivial` | [Execute](#stage-4-execute) | Inline plan of at most 10 lines in chat |

A skipped stage is never entered and takes no edge.

### The trivial test

A change is trivial when all three predicates are provably false from the planned change:

1. More than one file changes. A backlog-item tick does not count, and a pure typo or
   format fix may span files.
2. An interface other code depends on changes.
3. App-facing text changes — Blazor UI labels, CLI help and output, error messages.
   Repository documentation is not app-facing text, so a docs-only change can stay trivial.

Undecidable predicate: ask one line naming it. All decidable: act without asking.

The inline plan is at most ten lines in chat: files, change, verification artifact,
difficulty verdict. Commits go to the housekeeping worktree.

### When a predicate flips mid-work

Stop. Re-run the full classification. The result may be `moderate`, `complex`, or
`to-be-determined` — never an automatic `moderate`. Then move to a dedicated worktree with
the artifacts that value needs.

The reclassified change leaves its round before the round pushes. A round never grows a
non-trivial member.

- Not yet committed: move the files into the new worktree and continue there.
- Already committed in the round: cherry-pick that commit into the new worktree's branch
  (`git -C <new> cherry-pick <sha>`), then drop it from the round branch. The round branch
  is unpushed, so drop the commit itself: `git -C <round> rebase --onto <sha>^ <sha>`.

A revert would not achieve that. The original commit stays in the history the round pushes,
and the revert adds a second one.

Two named exceptions leave the change as two commits in the round: the rebase conflicts
with a later round commit, or the growth is found after the round pull request is already
open. In both, revert instead (`git -C <round> revert --no-edit <sha>`), say which
exception applied, and read the round's one-commit-per-change rule against the final pull
request diff rather than the commit log. File the item with
`scripts/new-backlog-item.ps1` and start it at [Pickup](#stage-1-pickup). The round keeps
its remaining changes and closes normally.

---

## 6. Linking convention

- Backlog items track planned work. GitHub issues track external reports and discussion.
- An issue that becomes work gets a backlog item that references the issue.
- Every spec and every plan carries a backlog number.
- When design starts before an item exists, [Intake](#stage-0-intake) runs first: file the
  item, then design.
- A pull request body may use a closing keyword for a GitHub issue. It must never use a
  bare `#N` for a backlog number — GitHub would link that to an unrelated issue or pull
  request.
- A pull request title carries its backlog number in words, such as `(backlog 071)`.
- Specs live in `docs/superpowers/specs/`. Plans live in `docs/superpowers/plans/`. That
  folder is a separate private repository, so commit from inside it with
  `git -C docs/superpowers commit`.

---

## 7. Mandatory rules

These rules are fixed. They are not left to the judgement of the session.

- **Bug gate at Design entry.** No root-cause evidence, no [Design](#stage-2-design) entry.
- **`mp-grill-with-docs` is the Design technique.** `mp-grilling` runs again on the draft
  plan, before the fabrication check.
- **Plain design summary.** Every spec gets a plain-English summary of at most 10 lines,
  and the human confirms understanding before the plan is written.
- **Completion criteria per plan task.** Every task lists each surface that must change.
  "90 percent done" is the named failure this prevents.
- **Execution mode rule.** Difficulty `complex` plus four or more independent plan tasks
  means subagent-driven execution (`superpowers:subagent-driven-development`). Otherwise
  execution is inline. The session decides and states the choice in the recap.
- **Progress file.** [Execute](#stage-4-execute) keeps `PLAN-PROGRESS.md` at the work-branch
  root. One line per task: the task number; the deliverable commit SHA, or the literal `-`
  when the task made no deliverable commit; the tests state; deferrals. It is committed at
  every task boundary and removed in the Ship commit.
- **No automatic CI watching.** After a push, agents do not watch CI, unless asked, or
  unless they state a specific reason to doubt the result.
- **Plan mode is out of the process.** A session that finds itself in plan mode says so and
  asks to exit before stage work. A plan-mode block on a requested action must produce a
  prompt, never a silent skip.
- **Session default.** `claude --model sonnet --permission-mode auto`. The per-stage model
  and effort values are in each stage's Who field.

### Safe to clear context

Three rules, from two documented incidents:

1. Keep context between [Design](#stage-2-design) and [Plan](#stage-3-plan). It holds
   line-level knowledge the spec only summarizes.
2. Clear it between [Plan](#stage-3-plan) and [Execute](#stage-4-execute). The plan carries
   the line numbers.
3. Never clear between Ship start and pull-request-open. That context writes the pull
   request description.

---

## 8. Four walkthroughs

Each walkthrough names every stage entered, every edge taken, and the Stage value at each
point.

### 8.1 A housekeeping round

The round is the stage-machine unit for trivial work. The exemplar change inside it is a
wrong command fixed in a doc.

0 Intake **not applicable**, taken once for the whole round at its first change. There is
no item, so the verdict is stated in chat. The three later changes take no Intake edge.
→ 1 Pickup success: the housekeeping worktree is created or reused, base `main` confirmed.
No Stage stamp and no push, because a round has no item. The route is the round pull
request, opened at Execute close. It jumps directly to Execute per the shared rule.
→ 4 Execute success: each change gets an inline plan of at most 10 lines in chat and one
immediate commit, with no progress file. After a few changes gather, the round closes,
pushes for the first time, and opens the round pull request with `Stage: 5-simplify` in its
body. Every transition from here rewrites that line.
→ 5 Simplify not applicable ("nothing to simplify")
→ 6 Verify **success**: exemption 1 named for the docs-only content; the targeted text
checks and the diff review are the artifact
→ 7 Document not applicable ("nothing to document" — the changes *are* docs)
→ 8 Review success: the round pull request is reviewed
→ 9 Ship success: records closed, which is nothing extra for a round; pull request ready,
CI green, merged
→ 10 Cleanup success: the post-merge sweep removes the round worktree, and the next round
starts fresh.

Field: none — no item exists. Before the pull request, the round worktree and its commit
log are the record. From the pull request onward, the `Stage:` line in its body.

Blocked: a single blocked change is filed as its own item and leaves. A blocker that stops
the whole round gets its own item naming the round pull request, moved to
`backlog/blocked/`.

### 8.2 Moderate bug fix, verification fails once

0 Intake success: bug item filed with `file:line` evidence, Difficulty `moderate`; field
`1-pickup`
→ 1 Pickup success: worktree, base stated, draft pull request; verdict "moderate: no spec";
jumps directly to Plan; field `3-plan`
→ 3 Plan success: field `4-execute`
→ 4 Execute success: field `5-simplify`
→ 5 Simplify success: duplication folded; field `6-verify`
→ 6 Verify **failure**: integration test red; field back to `4-execute`
→ 4 Execute success: fix committed; field `5-simplify`
→ 5 Simplify not applicable ("nothing to simplify"); field `6-verify`
→ 6 Verify success: field `7-document`
→ 7 Document success: README updated; field `8-review`
→ 8 Review success: field `9-ship`
→ 9 Ship success: merged; item in `done/`, field frozen at `9-ship`
→ 10 Cleanup success: terminal.

### 8.3 Complex feature, review sends it back

0 Intake success: Difficulty `complex`; field `1-pickup`
→ 1 Pickup success: worktree, base stated, draft pull request; field `2-design`
→ 2 Design success: spec committed, terms and ADRs written, summary confirmed; field
`3-plan`
→ 3 Plan success: field `4-execute`
→ 4 Execute success: field `5-simplify`
→ 5 Simplify success: field `6-verify`
→ 6 Verify success: field `7-document`
→ 7 Document success: docs updated; field `8-review`
→ 8 Review **failure**: three findings need code; field `4-execute`
→ 4 Execute success: fixes committed; field `5-simplify`
→ 5 Simplify not applicable ("nothing to simplify" — the fixes were minimal); field
`6-verify`
→ 6 Verify success: field `7-document`
→ 7 Document not applicable ("nothing to document"); field `8-review`
→ 8 Review success: threads resolved; field `9-ship`
→ 9 Ship success: merged; field frozen at `9-ship`
→ 10 Cleanup success: terminal.

### 8.4 Configuration-only change

The `.pr_agent.toml` case.

0 Intake success: Difficulty `moderate`; field `1-pickup`
→ 1 Pickup success: worktree, base stated, draft pull request; verdict "moderate: no
spec"; field `3-plan`
→ 3 Plan success: field `4-execute`
→ 4 Execute success: two config files changed; field `5-simplify`
→ 5 Simplify not applicable ("nothing to simplify"); field `6-verify`
→ 6 Verify success: the artifact today is the **full** gate. Targeted TOML and YAML checks
exist only as manual steps, and CI runs the whole .NET build for this pull request. The fix
is the wave-4 backlog item; field `7-document`
→ 7 Document not applicable ("nothing to document"); field `8-review`
→ 8 Review success: field `9-ship`
→ 9 Ship success: merged; field frozen at `9-ship`
→ 10 Cleanup success: terminal.

---

## 9. The fresh-session test

This test measures whether this document alone tells a session where a piece of work
stands. Re-run it whenever the process changes. It is repeatable.

### How to run it

1. Pick the subjects. Use at least one idle backlog item, one active backlog item, and one
   housekeeping round.
2. Dispatch one read-only subagent per subject. Each subagent may read this repository. It
   may not use the conversation.
3. Use the prompt below word for word. Do not name this file in the prompt. Finding it is
   part of the test.
4. Judge each answer against this document.

### The item prompt

Substitute the absolute path of the item file in the worktree.

> Read `<absolute item path in the worktree>`. Using only files you find in this
> repository, name: (1) the item's current stage, (2) every legal next action from that
> stage. Cite the repository file that told you. Do not use any conversation context.

### The round-resume prompt

A housekeeping round has no item, so its record is pasted into the prompt rather than read
from a path.

> A housekeeping round in this repository was interrupted. Its pull request body contains
> the line `Stage: 6-verify`, its branch has four commits, and its worktree still exists.
> Using only files you find in this repository, name: (1) the round's current stage,
> (2) every legal next action from that stage, (3) which record you must read to resume a
> round, and why the commit log alone is not enough. Cite the repository file that told
> you. Do not use any conversation context.

### How to judge

An item subject passes when all three hold:

- The named stage matches the item's `Stage` field.
- The named actions match that stage's five edges in section 3.
- The cited file is `docs/development/workflow.md`.

The round subject passes when it names `6-verify` from the pull request body, lists
Verify's four legal edges, and says the verdict-only stages leave no commit — so the pull
request body, not the commit log, carries the round's stage.

### How to classify a failure

The responsible source differs. Classify before you fix.

| What happened | Responsible source | Fix |
|---|---|---|
| The answer contradicts this file although the file is clear | Agent execution | Rerun once as-is before changing anything |
| The `Stage` field itself is wrong or missing | The backlog item | Fix the item |
| The agent never found this file | The discovery path | Fix the index line in `AGENTS.md` |
| This file is ambiguous or silent | This file | Fix this file |

Fix the responsible source, then rerun that subject. Repeat until every subject passes.
Report pass or fail per subject in the recap.
