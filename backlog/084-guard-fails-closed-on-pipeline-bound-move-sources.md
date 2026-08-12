# 084 - Guard fails closed on pipeline-bound move sources

## Metadata

- **Epic**: Agent guardrails
- **Type**: Feature
- **Interfaces**: CLI

## Summary

`Move-Item` and `Remove-Item` can take the paths they act on from the pipeline instead of from
their own arguments. The guard reads arguments only, so a move whose source arrives by pipeline
reports no source at all. `Get-Item <main>\README.md | Move-Item -Destination <allowed>\README.md`
is allowed today, and it deletes a tracked file in the main checkout.

## User story

As a developer whose main checkout is protected from agent sessions, I want a move that names no
source in its own arguments to be refused, so that piping a path into it cannot bypass the
source check that a written-out path gets.

## Acceptance criteria

- [ ] `Get-Item <main>/seed.txt | Move-Item -Destination <managed>/seed.txt` is refused from a
      managed worktree
- [ ] The same holds for `Get-ChildItem ... | Move-Item` and for `... | Remove-Item`
- [ ] A move that names its source in its own arguments keeps working unchanged
- [ ] A pipeline whose sink is a read-only command is unaffected
- [ ] Tests cover each shape above, in `tests/AgentWorktreeGuard.Tests.ps1`

## Out of scope

- Resolving what the upstream command would actually emit. The guard classifies text, never runs
  it, and must keep doing so.

## Notes / dependencies

- Found during review of PR #289 (backlog 076). Verified as **pre-existing**, not introduced by
  that branch: the same command is allowed at merge-base `2cba6963` when the destination is the
  session's own worktree, so the plans-repo exception did not open it.
- The obvious fix — deny any `Move-Item`/`Remove-Item` segment that is a pipeline sink and names
  no source — needs a false-positive review first. `Get-ChildItem *.tmp | Remove-Item` scoped
  entirely inside a worktree is a normal thing to write, and it would start failing. Decide
  whether the guard denies outright or resolves the pipeline's own segment first.
- Deferred from PR #289 deliberately: it needs pipeline-aware classification, a new capability
  rather than a fix to the work that branch did.
- Related: [083](083-guard-classifies-link-targets-as-write-targets.md), the other deferred
  finding from the same review.
