# The AHKFlowApp development process

This file describes how work moves through this repository. Work walks eleven stages. Each
stage has five edges. One durable record says where a piece of work stands.

**This file is canonical.** When `AGENTS.md`, `.claude/CLAUDE.md`, a skill, or any other
document disagrees with this file about the process, this file wins. Fix the other
document.

Artifact: https://claude.ai/code/artifact/29e1af46-2c4d-409c-9b18-ca2acc5eb497

Related files:

- Which tests to run, and the Gate:
  [`testing-workflow.md`](testing-workflow.md)
- What an agent may and may not do in the main checkout:
  [`cross-agent-git-guardrails.md`](../agents/cross-agent-git-guardrails.md)
- The same process drawn as a decision tree: [`workflow.html`](workflow.html)
- One printable page: [`ahkflow-workflow-cheatsheet.html`](ahkflow-workflow-cheatsheet.html)
  and [`ahk-workflow.pdf`](ahk-workflow.pdf)

---

## 1. The stage spine

Stage names are fixed. The exit strings below are canonical. They appear word for word in
`workflow.html`, in the cheatsheet, in this table, and in the stage blocks in section 3.
`scripts/check-process-parity.ps1` compares all of them and fails on any difference. Change
an exit string in every place in the same commit, and regenerate the PDF with
`scripts/update-workflow-pdf.ps1`.

| # | Stage | Exit condition |
|---|---|---|
| 0 | Intake | Item filed with the script, summary written, Difficulty set |
| 1 | Pickup | Location chosen by Difficulty, base confirmed and stated, PR route in place |
| 2 | Design | Spec committed, terms and ADRs written, plain summary confirmed |
| 3 | Plan | Plan committed, grilled, fabrication-checked |
| 4 | Execute | All planned work committed, tracking current, stage push done |
| 5 | Simplify | Simplification applied or verdict 'nothing to simplify' stated |
| 6 | Verify | Verification artifact green, gate green, verdict stated |
| 7 | Document | Docs updated or verdict 'nothing to document' stated |
| 8 | Review | Review received, all threads resolved, gate re-green |
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
- **Stage push done.** Execute pushes once, when the stage completes. Tracked plan work
  makes two local commits per task before that push. A housekeeping round makes one commit
  per change.

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

**Record the decision to close before pushing.** Between the push and a successful
`gh pr create` the round has no durable marker, and its commit log looks exactly like a
round still accumulating changes — so a session that dies in that window resumes by
committing more work instead of finishing the close. Make the decision visible first with an
empty marker commit — `git commit --allow-empty -m "chore: close round, opening PR"`. The
flag is required: an ordinary `git commit` refuses an unchanged tree. Round resume therefore
checks the upstream branch and the pull request state before it reads the commit log, and
retries `gh pr create` when the marker is present and no pull request exists.

A single trivial change is Execute-internal. It takes no stage edges of its own.

A change that grows in importance does not close the round. It is reclassified and leaves
before the round pushes. Commit it in the round, cherry-pick that commit into the new
worktree, and drop it from the round's unpushed history — the guard refuses a direct write
into a sibling worktree, so there is no file-move shortcut. The full route is in section 5.

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

# -join is not cosmetic. PowerShell captures multiline native output as System.Object[],
# and [regex]::Matches on an array matches nothing, so the check below would always throw.
$body = (gh pr view $pr --repo s205109/AHKFlowApp --json body -q .body) -join "`n"
$hits = ([regex]::Matches($body, $rx)).Count
if ($hits -ne 1) { throw "PR $pr body: expected 1 Stage line, found $hits" }

$tmp = New-TemporaryFile
($body -replace $rx, "Stage: $next") | Set-Content $tmp.FullName -Encoding utf8
gh pr edit $pr --repo s205109/AHKFlowApp --body-file $tmp.FullName
Remove-Item $tmp.FullName

gh pr view $pr --repo s205109/AHKFlowApp --json body -q .body | Select-String -Pattern $rx
```

`Select-String` on the last line takes pipeline input line by line, so it needs no join.
Only the `[regex]::Matches` calls do.

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
- **Technique** — `scripts/new-worktree.ps1 -Title`, then `scripts/new-backlog-item.ps1`
- **Action** — file the item where the work will run (see below), set Difficulty; for bugs, attach root-cause evidence or mark it `to-be-determined`
- **Exit** — Item filed with the script, summary written, Difficulty set
- **Next** — `1-pickup`
- **Context** — safe to clear
- **Review** — not reviewed

| Edge | Condition | Target |
|---|---|---|
| success | filed, the template placeholder summary replaced with a real one, Difficulty set | 1-pickup |
| failure | missing Difficulty or summary; complete the item | stay |
| blocked | cannot specify without an external answer; file what is known with the unblock note | blocked/ |
| not applicable | a housekeeping round needs no item — taken once per round, at its first change; the round's commits are the record; say so | 1-pickup |
| resume | item sat idle; revise Difficulty once, then re-check the whole exit condition — a placeholder summary keeps it here, and only a complete item takes the success edge | stay |

**Where Intake writes the file.** A new backlog item written into the main checkout cannot
reach a worktree by itself. `git worktree add` builds the new tree from a commit, and
`scripts/new-worktree.ps1` copies only the entries listed in `.worktreeinclude`, which lists
none — the file holds comments only. An agent also cannot commit on `main`. So an uncommitted
new backlog item in main is stranded.

**The route: create the worktree from the title, then file the backlog item inside it.**
The worktree is named from the title, not from the number, so nothing has to know the number
before the worktree exists. `scripts/new-backlog-item.ps1` then assigns the next free number
as it writes the file, inside the worktree, and the file is committed on the work branch.
No commit lands on `main`.

```powershell
# 1. From the main checkout. Most backlog items are features, so pass -BranchName as well:
#    -Title alone gives the branch the 'fix/' prefix, which is the fallback, not a guess
#    at your intent.
pwsh ./scripts/new-worktree.ps1 -Title "Downloads page row stays disabled" `
     -BranchName feature/wt-downloads-page-row-stays-disabled

#    For a fix, -Title alone is enough:
#    pwsh ./scripts/new-worktree.ps1 -Title "Downloads page row stays disabled"

# 2. From the new worktree, with the same title.
pwsh ./scripts/new-backlog-item.ps1 -Title "Downloads page row stays disabled"
# then edit the new file:
#   - replace the placeholder Summary with a real one
#   - add "- **Difficulty**: moderate | complex | to-be-determined"
#   - change "- **Stage**: 0-intake" to "- **Stage**: 1-pickup"
git add backlog/<NNN>-<slug>.md
git commit -m "chore: file backlog <NNN> <title>"
```

Pass the same title to both commands. Both slug it with the same rule
(`scripts/slug.common.ps1`), so the worktree name matches the backlog item file name, which
is what the pre-PR discovery rule below relies on. The template already carries `Stage`, so that
edit is a change of value rather than a new line (backlog 087). Backlog 072 adds `Difficulty` to
the template, which removes the second edit as well.

**Two sessions can still pick the same number**, because the number is assigned when the file
is written and neither session can see the other's unmerged branch. The duplicate check in
`Get-BacklogProblem` catches it, and the `powershell-suites` CI job runs on every pull
request — but not at once. Both pull requests stay green while both branches are unmerged,
because each checkout holds only its own file. The duplicate appears when the first branch
merges and the second refreshes against it.

The repair is `git mv` on one file plus its heading. The branch, the worktree, and the pull
request all keep their names, because none of them carries the number.

A housekeeping round files no backlog item at all, so none of this applies to it.

<a id="stage-1-pickup"></a>

### Stage 1 — Pickup

- **Entry** — item chosen
- **Who** — Sonnet, default effort
- **Technique** — `scripts/new-worktree.ps1 -BaseRef` to recreate the worktree when the base was wrong, or the housekeeping worktree
- **Action** — choose the execution location by Difficulty: a dedicated worktree for `moderate` and `complex`, the housekeeping worktree for `trivial`. Confirm branch and base, and state both. For a tracked item: push the branch, open the draft pull request, and **only then** stamp the Stage the Difficulty jump names — publishing the next Stage before the pull request exists would claim an exit condition that is still false. Until that stamp lands the item keeps `Stage: 1-pickup`, and the worktree is the pointer. For a housekeeping round: no item, so no Stage stamp and no push here. The round worktree is the pointer, and the route is the round pull request opened at Execute close
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

**The worktree is not optional.** `.githooks/pre-commit` refuses a commit on `main` for every
session, so trivial work needs the housekeeping worktree exactly as tracked work needs its own.
`AHKFLOW_ALLOW_MAIN=1` is the deliberate escape.

**Pickup makes two pushes, and they are different things.** The first publishes the branch
so `gh pr create` has something to open a pull request against; nothing is stamped yet. The
second carries the Stage transition commit after the pull request exists. Without that
second push the remote item still reads `Stage: 1-pickup` while the local branch has moved
on, and the remote is what a reader from `main` sees.

That leaves a window: a session that dies between the Stage commit and the second push
resumes at Design, Plan or Execute and never goes back for the push, so the remote still
reads `1-pickup`.

A check inside Pickup's resume cannot close this. After the crash the field already says
Design, Plan or Execute, resume follows the field, and Pickup is never re-entered.

**So every resume compares the field on the remote against the field locally**, before doing
anything else:

```powershell
git -C <worktree> fetch --quiet
# Find the item wherever it legitimately lives, rather than assuming backlog/.
git -C <worktree> ls-tree -r --name-only "origin/<branch>" |
  Select-String -Pattern "/<NNN>-<slug>\.md$"
git -C <worktree> show "origin/<branch>:<that path>" |
  Select-String -Pattern '(?m)^- \*\*Stage\*\*: '
```

A different Stage value means the last transition was never published: push, then continue
from the field.

**Look the path up; do not hard-code `backlog/`.** Ship moves the item to `backlog/done/`
and a blocked transition moves it to `backlog/blocked/`, both correctly. A check that only
reads `backlog/<item>.md` would find nothing there and call a properly pushed transition
unpublished. The item missing from **every** location on the remote is the real signal that
nothing was pushed.

This compares **the field**, not commit divergence, which is what makes it safe: Execute's
own task commits leave the branch ahead without touching the field, so they raise no false
alarm, and a worktree with no upstream fails the `origin/<branch>` lookup outright rather
than reporting a spurious match. A housekeeping round has no item and no field — its record
is the pull request body, checked the same way with `gh pr view`.

Do not generalise this to other stages by reading `git status -sb`. Being ahead does not
mean the transition is unpublished: Execute's own task commits leave the branch ahead by
design, a worktree created with `worktree add -b`
(`scripts/worktree-git.common.ps1:82`) has no upstream at all until the first push, and the
remote-tracking ref is stale without a fetch. A housekeeping round has no Stage commit to
compare — its record is the pull request body.

**The draft pull request opens before any gate has run, and that is deliberate.** The pull
request exists from Pickup so it can point at the work through Design and Plan. It is a
**draft**, which is not a request to merge. The five-step Gate in
[`testing-workflow.md`](testing-workflow.md#canonical-pre-pr-gate) is therefore a
**pre-ready** gate: it runs at [Verify](#stage-6-verify), and it must be green before
[Ship](#stage-9-ship) flips the pull request to ready. Read every rule that says "before you
create a PR" as "before you mark it ready". <!-- gate-wording:ignore -->

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
| not applicable | reclassification at entry: no spec needed; set Difficulty `moderate` and say so. `trivial` is not available here — a filed item is never trivial | 3-plan |
| resume | re-read spec and review state, continue grilling or submit | stay |

<a id="stage-3-plan"></a>

### Stage 3 — Plan

- **Entry** — spec approved, or `moderate` item picked
- **Who** — `--model opus --effort xhigh`
- **Technique** — `superpowers:writing-plans`, then `mp-grilling` on the draft, then the fabrication check
- **Action** — write the plan; every task lists its completion criteria and every surface that must change; write the plan's path back into the item as a `- Plan:` bullet
- **Exit** — Plan committed, grilled, fabrication-checked
- **Next** — `4-execute`
- **Context** — clear before Execute; the plan carries the line numbers
- **Review** — plan reviewed before execution

**Two homes for a plan.** A plan about the product or the repository goes to
`docs/superpowers/plans/` and carries the backlog number of the item it serves.
A plan about the way you or your agents work goes to
`docs/superpowers/personal/plans/` and carries no number, because no backlog
item owns it. `docs/superpowers/personal/README.md` states the rules. The split
enforces itself: `scripts/backlog.common.ps1` rejects a `- Plan:` pointer that
holds a folder, so a backlog item cannot name a personal plan.

| Edge | Condition | Target |
|---|---|---|
| success | exit condition met | 4-execute |
| failure | grilling or fabrication check fails; revise | stay |
| blocked | plan exposes an external dependency | blocked/ |
| not applicable | cannot occur for a filed item: every tracked item gets a committed plan, however small the work. Only a housekeeping round skips Plan, and a round never enters it | none |
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
- **Action** — produce the verification artifact the table names, then run the five-step Gate in [`testing-workflow.md`](testing-workflow.md#canonical-pre-pr-gate). A wait on the human for manual steps keeps the stage in progress; it is not an edge. An AGENTS.md exemption replaces the **artifact** only — for exemption 1, targeted text checks plus diff review stand in for a test. The gate still runs. It runs on a docs-only branch too, because CI skips its .NET steps there, so the local gate is the only .NET check that branch gets. Name the exemption, state the verdict, and take the success edge
- **Exit** — Verification artifact green, gate green, verdict stated
- **Next** — `7-document`
- **Context** — safe to clear after green
- **Review** — not yet reviewed

| Edge | Condition | Target |
|---|---|---|
| success | exit condition met | 7-document |
| failure | red; before the transition, record the failing command, its output, and a named recovery task — in `PLAN-PROGRESS.md` for tracked work, in the round pull request body for a round, which has no progress file — so Execute resume has something to find | 4-execute |
| blocked | verification depends on something outside the repository | blocked/ |
| not applicable | cannot occur: AGENTS.md requires a verdict either way, and an exemption replaces only the artifact while the gate still runs, so an exempt change takes the success edge with the exemption named | none |
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
- **Technique** — two halves. **Producing** the review: a reviewer session, or Codex, reads the branch and posts threads. `custom-review-findings` cannot do this half — it only consumes findings. **Handling** the review: `custom-review-findings` (PR mode)
- **Action** — ask a reviewer for the review, then handle what comes back. Reply and resolve every thread. A wait on the reviewer keeps the stage in progress; it is not an edge. Fix inside Review only what needs no code change: a reply, a wording fix in the pull request, a resolved misunderstanding. Any finding that needs a code change takes the failure edge to Execute; do not fix it here
- **Exit** — Review received, all threads resolved, gate re-green
- **Next** — `9-ship`
- **Context** — keep until threads resolved
- **Review** — reviewed; state it in the recap

| Edge | Condition | Target |
|---|---|---|
| success | exit condition met | 9-ship |
| failure | findings need code changes; record them as named recovery tasks first — in `PLAN-PROGRESS.md`, or the round pull request body — because Execute resume reads those, never the review threads; then Simplify, Verify, Document again as needed | 4-execute |
| blocked | a finding depends on something outside the repository | blocked/ |
| not applicable | cannot occur: every pull request — a tracked item's or a round's — is reviewed | none |
| resume | fetch unresolved threads, continue with `custom-review-findings` | stay |

<a id="stage-9-ship"></a>

### Stage 9 — Ship

- **Entry** — review closed
- **Who** — Sonnet, default effort
- **Technique** — `gh pr ready`, then merge
- **Action** — close the records, **push**, then flip the pull request to ready, wait for CI, merge. Tracked work: tick the item's boxes, `git mv` it to `backlog/done/`, delete `PLAN-PROGRESS.md`, set `Stage: 9-ship` — one commit, pushed before the ready flip. A round: nothing extra to close, so nothing to push
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

**Every Ship transition that makes a commit pushes it, success included.** GitHub merges
the remote pull request head, not your local branch. A closure commit that stays local is
not in what gets merged, so the merged `main` would carry the work without the records that
close it — and Cleanup then deletes the worktree holding the only copy. Push the closure
commit before the ready flip. The merge adds nothing after that.

**A check now confirms the closure commit happened.**
`tests/BacklogStaleOpen.Tests.ps1` sweeps `backlog/` on every CI run. It fails an item that
reads Stage `4-execute` or later, whose newest `- **Stage**:` change is already merged into
the base branch, and whose stamp sits more than twelve first-parent commits behind that
branch's tip. Work in flight stays silent, because its stamps have not merged yet. An item
that ships over several pull requests stays silent too, because each pull request moves the
stage and restarts the count. The check reads the item's own Stage line and the commit
graph. It never reads a pull request title, which can name the wrong item: #312 is titled
"backlog 096" and did item 097's work.

The same check has a second, simpler arm: an item that reads `Stage: 9-ship` while it still
sits in `backlog/` fails at once, with no merge test and no counting. Ship writes that stage
and moves the file in one commit, so the two can only disagree when the move was forgotten.

A round has no item, no progress file, and nothing extra to close at Ship. Its non-success
edges restore no records. They rewrite the `Stage:` line in the round pull request body
instead, and they push only if the recovery work itself makes a commit.

**One exception to "nothing extra": a round-level blocker item.** If the round filed one
because it **could not merge**, that item is real tracked work and it does not close itself.
When the round finally merges, `git mv` that item into `backlog/done/`, tick its boxes, and
include it in the same closure commit Ship pushes.

A blocker filed because the worktree **could not be removed** cannot use that route: Cleanup
runs after the merge, so the pull request that would have carried the closure commit is
already merged and its branch is gone. Close that item the way Cleanup's own blocked edge
says — it stays in `backlog/blocked/` until the removal succeeds, and then a housekeeping
round moves it to `backlog/done/` as one of its own changes.
Otherwise it sits in `backlog/` forever describing a blocker that cleared.

| Edge | Condition | Target |
|---|---|---|
| success | closure commit pushed when there is one, then CI green and merged | 10-cleanup |
| failure | CI red after ready; convert the PR back to draft first. Tracked item: `git mv` the item back out of `backlog/done/`, restore `PLAN-PROGRESS.md`, set `Stage: 6-verify` — one commit — then push. A round: rewrite the PR body's `Stage:` line to `6-verify`; no records to restore, no transition commit, so no push. Start recovery only after that | 6-verify |
| blocked | merge depends on something outside the repository, such as a required-check outage; the PR stays ready. Tracked item: restore `PLAN-PROGRESS.md`, `git mv` the item from `backlog/done/` to `backlog/blocked/` with the unblock note, keep `Stage: 9-ship`, commit, push. A round has no item: file one naming the round PR and the blocker, move that item to `backlog/blocked/`, **commit and push it** — an unpushed blocker exists only on one machine — and leave the round PR body at `Stage: 9-ship` | blocked/ |
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

**Merge with a merge commit, not a rebase merge.** The removal script decides a worktree is
merged with `git merge-base --is-ancestor HEAD <base>`
(`scripts/remove-worktree-local-dev.ps1:368`, "'merge-base', '--is-ancestor', 'HEAD', $BaseRef").
A rebase merge rewrites the commits, so the
branch head that was merged is not an ancestor of the base and removal is refused even though
the work landed. This repository has rebase merging enabled (`allow_rebase_merge: true`), so it
is a live trap, not a theoretical one. The sweep already decides by reachability instead
(backlog 095), so the two disagree; backlog 098 makes the removal script use the same rule.
Until then, Ship uses a merge commit for any branch whose worktree you expect Cleanup to remove.

**No pull is needed first.** The base both scripts decide against is the remote-tracking branch
`origin/main`, fetched at the start of the run
(`scripts/worktree-git.common.ps1:185`, "function Resolve-MergedBaseRef {"). `gh pr merge` merges on GitHub
and advances no local ref, and that no longer hides the merge. The fetch updates one
remote-tracking ref: it never touches local `main`, so a worktree session may run it under the
guard.

**A base that could not be refreshed removes nothing.** When the fetch fails, the cached
`origin/main` may hold a merge the remote has since dropped, so both scripts report what they see
and stop: the sweep prints the eligible worktrees and removes none, and the removal hook preserves
the worktree. Removal resumes on the next run that reaches the remote.

**The session that starts Cleanup usually cannot finish it.** The removal hook spawns a
detached watcher that outlives `claude.exe` and can only delete the worktree after that
process exits (`scripts/remove-worktree-local-dev.ps1:9-28`). So the session that triggers
removal cannot run the three success checks below — the folder is still locked while it is
alive.

Cleanup therefore ends in one of two ways, and the session says which:

1. **Synchronous.** Removal runs from a session outside the worktree — the main checkout,
   or any shell not standing in the folder. That session runs all three checks itself and
   takes the success edge.
2. **Deferred to the watcher.** The session triggers removal, **updates memory before it
   ends** — that is the one exit condition no later session can reconstruct — states that
   the watcher owns the worktree and branch, and ends. A later session confirms the other
   two only if something is left behind.

   Memory comes first because the watcher's success path removes both the worktree and the
   branch (`scripts/remove-worktree-local-dev.ps1:922`, "'branch', '-d', '--', $branchName"). After a clean run there is no
   worktree, no branch, and no marker, so a later session has nothing to find and nothing to
   act on — which is correct, because nothing is left to do. The leftover check below exists
   for the partial-failure cases only.

   That needs a trigger, and the merged pull request cannot be one: it looks identical
   before and after the checks, and a housekeeping round has no `done/` item at all. The
   durable trigger is the leftover itself — but it must be **either** leftover, not only the
   worktree. The watcher prunes the worktree
   (`scripts/remove-worktree-local-dev.ps1:916`, "'worktree', 'prune', '-v'") before it deletes
   the branch, and has a documented outcome that stops in between, logging
   (`scripts/remove-worktree-local-dev.ps1:997`, "worktree removed; branch preserved").
   Checking the worktree alone would miss exactly that case.

   Two leftovers are possible and **one check does not find both**.

   *Worktree still present.* Run `pwsh .\scripts\cleanup-merged-worktrees.ps1` and finish
   what it reports. Use its eligibility rule rather than a hand-rolled one.

   *Branch still present, worktree already gone.* That sweep cannot see this case: it
   enumerates `git worktree list`
   (`scripts/cleanup-merged-worktrees.ps1:292`, "worktree list --porcelain"), and the
   watcher prunes the worktree
   (`scripts/remove-worktree-local-dev.ps1:916`, "'worktree', 'prune', '-v'") **before** it
   deletes the branch, then may stop with
   (`scripts/remove-worktree-local-dev.ps1:997`, "worktree removed; branch preserved"). So the
   exact partial failure the deferred route exists for is
   invisible to it. Until backlog 099 scripts this, check it directly: a local branch other
   than `main`, merged into `main`, with no registered worktree, whose tip differs from
   `main`'s tip.

   The tip comparison is what makes it usable. `git branch --merged main` alone lists `main`
   itself and every branch freshly cut from `main` with no commits of its own — permanently
   "merged", so it reports leftovers forever and teaches the reader to ignore it. Requiring
   the tip to differ from `main`'s keeps only branches that contributed commits now merged.
   Verified on this repository: the sweep-based list plus that predicate reports zero, while
   `git branch --merged main` reports `main`.

Neither route lets a session claim success it did not observe. All three exit conditions
are checked, never the worktree alone. The removal script has a
documented outcome that removes the worktree and keeps the branch
(`scripts/remove-worktree-local-dev.ps1:997`, "worktree removed; branch preserved").

Both git checks name the main checkout with `-C`, and the branch check accepts exit code 1
only. Cleanup deletes the worktree folder, so the session may be left in no repository at
all. There `git show-ref` exits 128 for every ref, including refs that still exist. Exit 1
means the branch is absent. Any other non-zero code is a failed check, not a deleted
branch. The removal script scopes its own check the same way
(`scripts/remove-worktree-local-dev.ps1:922`, "'branch', '-d', '--', $branchName").

| Edge | Condition | Target |
|---|---|---|
| success | all three confirmed — `git -C <main-checkout> worktree list` shows no entry, `git -C <main-checkout> show-ref --verify --quiet refs/heads/<branch>` exits 1, memory updated | terminal |
| failure | removal attempt failed — a holder process or a lock; name the holder, follow the removal log's manual guidance, retry | stay |
| blocked | removal depends on something outside the repository, such as an upstream tooling bug. The work already merged, so the original item stays in `backlog/done/`. File a new item naming the merged PR, the worktree path, the blocker, and what would unblock it, and move it to `backlog/blocked/` — but **file it from the main checkout or a housekeeping round, never inside the worktree being removed**. Writing it there leaves the tree dirty, and committing it moves HEAD off `main`'s ancestry; the removal script rejects both (`scripts/remove-worktree-local-dev.ps1:688`, "Test-WorktreeMergedIntoMain -WorktreeFull $worktreeFull -BaseRef $baseRef") and (`scripts/remove-worktree-local-dev.ps1:693`, "Test-WorktreeClean -WorktreeFull $worktreeFull"), so filing the blocker in place would itself prevent the removal from ever succeeding | blocked/ |
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

**Coming back out of `backlog/blocked/`.** Every blocked edge moves an item in; nothing
moves it back, so the move out is a step of its own and it comes **before** the resume
edge. When the external condition the unblock note names has cleared:

Run it in **the checkout that owns the item**. That is the worktree once Pickup has made
one; for an item blocked at Intake, before any worktree exists, the item is on `main`, so
this is a main-checkout step and an agent hands it to the human.

```powershell
git -C <checkout> mv backlog/blocked/<NNN>-<slug>.md backlog/<NNN>-<slug>.md
# now remove the unblock note from the file, keeping the Stage field exactly as it was
git -C <checkout> add backlog/<NNN>-<slug>.md
git -C <checkout> commit -m "chore: unblock <NNN>, <what cleared>"
```

The `git add` is not optional. `git mv` stages the rename with the file's contents as they
were, so an edit made afterwards stays unstaged and the commit would record the old unblock
note.

Then take the resume edge of the stage the field already names. The folder is the durable
record of blocked-ness, so an item left in `backlog/blocked/` still reads as blocked no
matter what its Stage field says. A round-level blocker's item comes back the same way, and
the round continues from its pull request body's `Stage:` line.

The field lives in the work branch during a task. The draft pull request is the live
pointer from `main`. If branch name, pull request state, and field disagree, the field
wins. The others are evidence.

**Two-repo transitions (Design, Plan).** Commits are ordered. First the artifact to the
private plans repo (`git -C docs/superpowers commit`), then the Stage-field update to the
public work branch. The public Stage commit is the authoritative transition marker.

**Both the plans-repo commit and the file edit run from the worktree.** Measured, not
assumed: `git -C <path>/docs/superpowers commit` is allowed from a worktree session, through
the symlink or the absolute path, because the guard gates commands that could change the
*protected checkout's* HEAD, index, or working tree — and the plans repo is a different
repository. `Edit`, `Write`, and shell writes under that path are allowed for the same reason
(`agent-worktree-guard.common.ps1:2041-2066`).

Two paths stay refused. The folder root itself, because renaming or deleting `docs/superpowers`
breaks the link every worktree depends on. And `docs/superpowers/.git`, because destroying it
destroys history that was never pushed.

So Design and Plan finish inside the worktree: write the artifact there, then commit it with
`git -C docs/superpowers commit`.

**Push boundaries.** Push at every pre-merge stage completion that has a live branch and a
transition commit — stages 1 to 9. A tracked item's Pickup push is the first push and opens
the draft pull request, so the pull request exists from stage 1 and can point at stages 2
and 3. A housekeeping round's first push comes at Execute close and opens the round pull
request. **Ship pushes too**: its closure commit must reach the remote before the ready
flip, because the merge takes the remote head. Only Cleanup runs after the merge, and it
never pushes: by then the branch is gone.

**Ship failure and Ship blocked undo what Ship already did.** Both happen pre-merge on a
live branch. For a tracked item: `git mv` the item back out of `backlog/done/`, restore
`PLAN-PROGRESS.md`, then set the Stage the edge names. One commit carries the restore and
the Stage; then push. Recovery starts only after that push, so the pull request never shows
an item closed while its work reopens. For a housekeeping round there is nothing to
restore: rewrite the `Stage:` line in the round pull request body, and push only if the
recovery work itself makes a commit.

**Before the draft pull request exists** — stage 0 to early stage 1 — the worktree is the
live pointer. `git worktree list` or `ls .claude/worktrees/` finds it, and its name is the
backlog item's slug, so `wt-downloads-page-row-stays-disabled` pairs with
`NNN-downloads-page-row-stays-disabled.md`. The worktree's copy of that file carries the
Stage field. When a worktree was named with `-Name` rather than `-Title` the names may not
pair, so read the `backlog/` folder inside the worktree instead.

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

**A filed backlog item is never `trivial`.** `trivial` classifies work that runs as a
housekeeping round, and a round files no item — that is the whole of its unit contract in
section 2. So the `trivial` row above describes unfiled work only. Picking up an item from
`backlog/` means its Difficulty is `moderate`, `complex`, or `to-be-determined`; if the work
turns out to be trivial in size, it is still tracked work and still gets a plan. The
reverse also holds: when a change inside a round grows past the trivial test, it leaves the
round and becomes a filed item, which is why it cannot stay `trivial`.

**Closing an item whose work already merged is not a pickup.** The rule above governs work
that still has to be done. When the pull request merged and [Ship](#stage-9-ship) never closed
the records — the boxes are unticked, or the file never moved to `backlog/done/` — nothing is
left to execute, so there is no pickup to classify. Ticking the boxes, setting
`Stage: 9-ship`, and running `git mv` into `backlog/done/` is trivial work, and a housekeeping
round carries it like any other trivial change.

It gets no new backlog item. The Git Workflow rule in `AGENTS.md` forbids a separate pull
request to mark an item done, and filing an item for the closure produces exactly that pull
request under another name. It gets no dedicated worktree either, for the same reason every
other trivial change does not.

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

- Not yet committed: **commit it in the round first**, then use the cherry-pick route
  below. A worktree session cannot write into a sibling worktree — the guard refuses it
  outright — so there is no direct file move between them. Committing first is what makes
  the change reachable from the other worktree at all.
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
- Every project spec and every project plan carries a backlog number, in its file name and in its heading:
  `docs/superpowers/specs/YYYY-MM-DD-<topic>-design-NNN.md` and
  `docs/superpowers/plans/YYYY-MM-DD-<topic>-plan-NNN.md`. Existing files keep their names.
- A personal spec or plan lives under `docs/superpowers/personal/` and carries no backlog
  number: `docs/superpowers/personal/plans/YYYY-MM-DD-<topic>-plan.md`. No backlog item
  names it.
- Every backlog item names its plan. The item carries a `- Plan:` bullet under
  `## Notes / dependencies`, holding a path under `docs/superpowers/plans/`, or
  `none — <reason>`. `tests/BacklogPlanPointer.Tests.ps1` checks it for `backlog/` and
  `backlog/blocked/` from `4-execute` onward. It cannot check that the file exists, because
  `.gitignore:473` keeps `docs/superpowers/` out of this repository.
- When design starts before an item exists, [Intake](#stage-0-intake) runs first: file the
  item, then design.
- A pull request body may use a closing keyword for a GitHub issue. It must never use a
  bare `#N` for a backlog number — GitHub would link that to an unrelated issue or pull
  request.
- A pull request title carries its backlog number in words, such as `(backlog 071)`.
- Specs live in `docs/superpowers/specs/`. Plans live in `docs/superpowers/plans/`. That
  folder is a separate private repository, so commit from inside it with
  `git -C docs/superpowers commit`.

### What a session without the plans repository can see

The stage is not in the plan. The stage is in the backlog item, and the backlog item is
public. A session with no plans repository still reads the stage correctly.

What such a session cannot read is the plan's content. `tests/BacklogPlanPointer.Tests.ps1`
checks that the `- Plan:` pointer exists. It cannot check the target, because `.gitignore`
keeps `docs/superpowers/` out of this repository.

The failure mode is a session that knows its stage and cannot see its instructions. This is
a finding, not a gap this item closes.

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
3. Keep context from Ship start until the pull request description is final. The draft pull
   request already exists from Pickup, so this is not about opening it — it is about the
   description, the recap, and the closure records, all of which Ship writes from context it
   cannot reconstruct afterwards.

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
