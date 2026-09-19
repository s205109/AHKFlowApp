# A transition runs outside the entered worktree

`scripts/take-stage-transition.ps1` is a PowerShell script. A Claude Code session that has entered
a worktree cannot run PowerShell, so it calls the script through the exit and re-enter cycle:
`ExitWorktree` with `keep`, run the script with `-Worktree <absolute path>`, then `EnterWorktree`
with the same path.

This is surprising, and the surprise is worth writing down. The one script an agent runs at every
stage boundary is written in the one language that agent cannot call directly.

## What was measured

On 2026-09-19, inside `wt-automate-stage-transitions-and-2e3802a4`, this command was refused:

```
pwsh -NoProfile -Command "Write-Host 'pwsh works'"
```

The refusal read: "this command runs pwsh in a plain command; what it reads or is handed as shell
text cannot be shown not to run git". The same session ran `git commit` and `git push` without
complaint.

The refusal comes from the harness, not from this repository's guard. `AHKFLOW_GUARD_DISABLE=1`
and `AHKFLOW_ALLOW_MAIN=1` do not lift it.

## The alternative that was rejected

Writing the script in bash. An entered session runs bash freely, so the cycle would disappear and
a transition would cost one command instead of three.

It was rejected because of what the script reads. Acceptance criterion 2 of backlog 081 requires
the legal targets to come from `docs/development/workflow.md` at run time, not from a list copied
into the script. That reader already exists, in PowerShell: `Get-WorkflowStage`
(`scripts/process-workflow.common.ps1:156`, "function Get-WorkflowStage {") and
`Get-WorkflowStageTable` (`scripts/process-workflow.common.ps1:131`,
"function Get-WorkflowStageTable {").

A bash implementation needs its own parser for the same document. That is a second copy of the
process rules. Backlog 072 built a drift guard because copies of process rules drift, and the
item's own notes say a script is just another copy.

So the choice was between one cycle per transition and one more parser to keep in step. The cycle
costs a session three tool calls. The parser costs correctness, silently, the first time
`workflow.md` changes shape.

## What follows from this

The script takes `-Worktree` with an absolute path and addresses every git call with `git -C`. It
never reads the caller's working directory. That is what makes it safe to run from outside the
worktree it acts on.

Anyone tempted to rewrite this in bash should first move the `workflow.md` reader somewhere both
languages can share, or accept the second copy knowingly. Rewriting it without doing either
reintroduces exactly the drift backlog 081 exists to remove.

## Related

- [`0012-pickup-enters-the-worktree.md`](0012-pickup-enters-the-worktree.md) — why the session is
  entered in the first place, and the other costs entering carries.
- [`0006-process-source-lives-in-workflow-md.md`](0006-process-source-lives-in-workflow-md.md) —
  why `workflow.md` is the one place a process question is decided.
