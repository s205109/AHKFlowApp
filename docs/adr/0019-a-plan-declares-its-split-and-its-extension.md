# A plan declares its split and its extension

Every Plan carries a `## Split` section near its top, holding three fields: an estimate in work
sessions, the task at which the user story closes, and a verdict on splitting once the Plan meets
the split trigger. A Plan meets the split trigger when the estimate is more than two sessions, or
when fifteen or more of its lines name a test-run command. A Plan at the trigger must carry a real
split evaluation, and a written reason when no split is taken.

The trigger is deliberately **not** a task count. That needs explaining, because a task count is
the first rule anybody proposes.

## Why not a task count

Backlog item 146 is the case this rule exists for. It carried 7 acceptance criteria and 8 tasks,
ran four days, merged once at the end, and took `main` in twice. One acceptance criterion needed
seven of its eight tasks.

The obvious rule is to fail a `complex` item whose plan carries more than three tasks. Measurement
against the repository refuses it. Across 209 committed plans, 168 carry numbered tasks, and their
median is 6. A threshold of three reports a problem for 145 of those 168.

Worse, it cannot catch 146. At 8 tasks, 146 sits exactly on the `complex` median, and at 699 lines
it is the second-shortest `complex` plan in the repository. Any threshold low enough to catch 146
fires on the middle of the population: more than 7 tasks flags 13 of the 18 `complex` plans. A
check that fails the healthy majority is switched off inside a week.
`scripts/check-shipped-plan-ticked.ps1` already records that reasoning for its own scope
(`scripts/check-shipped-plan-ticked.ps1:4`, "Fails the push when this branch ships").

Weaker evidence agrees. Over the last 15 shipped items, task count matches the number of commits
that touched the item's own file at r = 0.40, and plan length at r = 0.50. The proxy is rough and
the sample small, so this only supports the placement of 146 above.

## What the cost really was

Two things, and batch size is neither.

The first is an Extension nobody could see. 146's Task 5 of 8 closed the user story. Tasks 6 and 7
extended one acceptance criterion to a second surface and cost two further sessions. The plan
never said where the user story ended. Only 2 of 67 numbered plans mention the user story at all,
so this was invisible by convention, not by accident.

The second is a verification loop. 146 built a machine-wide lock for local test runs, so proving
it meant running the suites repeatedly from two checkouts. One serial pass over the PowerShell
suites costs at least 845 seconds. That sum covers the suites with a measured baseline in
`tests/powershell-suites.json`, and six suites have none yet. A plan that re-runs the suites
twenty times spends over four hours in test wall clock before anybody thinks.

That second cost can be read from the plan text. Counting the lines that name a test-run command,
across 67 numbered plans, gives p50 = 3, p75 = 7, p85 = 15, p90 = 20. Item 146 scores 19. A
threshold of fifteen catches it and stays quiet on 55 of the 67 plans, 82%. That is precisely what
the task count could not do.

## Considered options

**A task count threshold.** Rejected. It fires on the median, flags 13 of the 18 `complex` plans at
any threshold low enough to catch 146, and misses the actual cost driver. Measured, not assumed.

**Plan length in lines.** Rejected. 146 is the second-shortest `complex` plan in the repository, so
the rule would have passed it.

**The pull request map, Approach A of backlog item 157.** Deferred, not rejected. It joins each
pull request to the tasks it ships and the criteria it closes. Two independent reviews found the
same weakness: a map makes a large batch visible without making it smaller. 157 takes the limit
first and leaves the map for later, which is the third option that item offers.

**A check in hosted CI.** Impossible, not merely rejected. The plans repository is ignored by this
repository (`.gitignore:473`, "docs/superpowers") and no workflow clones it. So the check runs at
pre-push, from the same quick-check script that already runs a plan-reading check
(`scripts/pre-push-quick-checks.ps1:205`, "check-shipped-plan-ticked.ps1"). A Pester suite proves
the logic on fixtures, and that suite does run in CI. The pair copies an existing one
(`scripts/pre-push-quick-checks.ps1:185`, "covers the rule against fixtures").

**A hard refusal with no override.** Rejected. Both halves of the trigger rest on judgement: the
estimate is written by the person who benefits from a low number, and fifteen is calibrated on 67
plans. A rule that cannot be answered in writing gets disabled rather than obeyed. The written
reason keeps the signal and costs one paragraph.

**Restricting the rule to `complex`.** Rejected. Shipped items run 54 moderate to 24 complex, and
the longest moderate plan is longer than 12 of the 18 `complex` plans. The trigger gates the rule;
Difficulty does not.

## Consequences

A plan that reaches Execute without a Split record is refused at the push. The estimate stays a
guess until enough items record one, and fifteen stays calibrated on 67 plans, so both numbers are
expected to move. The Extension field is the part that would have caught 146, and it costs one line
per plan.
