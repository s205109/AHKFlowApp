# 112 - Stale citations in the plans repository block every push

## Metadata

- **Epic**: Development process
- **Type**: Bug
- **Interfaces**: none (repo tooling)
- **Difficulty**: moderate
- **Stage**: 4-execute

## Summary

The pre-push hook runs the citation check over the private plans repository and throws when it
reports anything. That repository already fails, so the hook fails on every branch. Everybody pushes
with `SKIP_PUSH_HOOK=1`, which also skips the plan and workflow parity check that runs beside it.

## User story

As a person pushing a branch, I want the pre-push hook to pass when my own work is clean, so that
skipping it stops being the normal way to push.

## Detail

The hook runs two checks over `docs/superpowers` and throws on either
(`scripts/pre-push-quick-checks.ps1:47`, "    Write-Step 'Checking citations in the private plans repository'")
and
(`scripts/pre-push-quick-checks.ps1:71`, "    Write-Step 'Checking the plans against the source'").

Measured twice on 2026-08-21 with the command below: 55 problems in the morning, 62 a few hours
later. The count rises on its own, because the plans repository is shared across every worktree and
the files these plans cite keep moving.

```bash
pwsh ./scripts/check-citation-freshness.ps1 -ScanRoot ./docs/superpowers -ResolveRoot . -NoAdoptionTier
```

The 62 problems sat in ten files, all finished work:

| File | Problems |
|---|---|
| `plans/2026-08-20-worktree-sweep-reflog-forgery-plan-096.md` | 11 |
| `plans/2026-08-21-friction-recall-interval-plan-102.md` | 10 |
| `plans/2026-08-20-cleanup-event-identity-plan-103.md` | 10 |
| `plans/2026-08-19-leftover-branch-after-worktree-gone-plan-099.md` | 10 |
| `specs/2026-08-19-worktree-merged-rule-design-098.md` | 8 |
| `plans/2026-08-19-worktree-merged-rule-plan-098.md` | 7 |
| `plans/2026-08-20-acceptance-tick-timing-plan-100.md` | 3 |
| `specs/2026-08-20-acceptance-tick-timing-design-100.md` | 1 |
| `specs/2026-08-15-citation-freshness-check-design-096.md` | 1 |
| `plans/2026-08-19-detect-unclosed-merged-item-plan-106.md` | 1 |

The public repository's own citations are clean, and `tests/CitationFreshness.Tests.ps1` keeps them
that way in CI. CI never sees the plans repository, because the public repository ignores it
(`.gitignore:473`, "docs/superpowers"). Pre-push is the only gate that reaches it, and that gate is
the one being skipped.

Not every problem can be repaired by writing a new line number. Some citations quote text the source
has since deleted. Backlog 093 hit exactly that and suppressed six of them with
`citation-check:ignore` and a reason on the same line. Deciding repair against suppression, one
citation at a time, is the work here.

## Acceptance criteria

- [ ] `pwsh ./scripts/check-citation-freshness.ps1 -ScanRoot ./docs/superpowers -ResolveRoot . -NoAdoptionTier` reports no problem in any shipped plan or spec, and no problem in any plan this branch owns. Every remaining problem names a live branch, and the recap lists them
  - Revised at plan review on 2026-08-21. The original text asked the full scan to report `every citation checks out`. That is unreachable by design, not by neglect: the same plan files score 82 problems from this worktree and 104 from the backlog-110 worktree, and the two disagree about which files are broken. A plan another branch is writing cites lines that are right there and wrong here, so no line number satisfies both
- [ ] `git push` completes with the pre-push hook enabled, without `SKIP_PUSH_HOOK=1` and without `--no-verify`
- [ ] Every citation that quotes text the source no longer holds carries `citation-check:ignore` with the reason on the same line, rather than a line number that happens to exist
- [ ] The repository records what keeps the count from growing back, or states that nothing does and why

## Out of scope

- The public repository's citations. They pass today, and `tests/CitationFreshness.Tests.ps1`
  already gates them
- The checker itself. `scripts/check-citation-freshness.ps1` reports correctly; the citations are
  what is wrong
- The content of the finished plans and specs. Only their citations change. Do not rewrite the
  reasoning around them

## Notes / dependencies

- Found on 2026-08-21 while writing the plan for backlog 110. That plan has to skip the push hook
  because of this, and says so in its task 7
- The last acceptance box is the one that matters most. Repairing 62 citations once, with nothing
  stopping the next 62, buys a few days. Look at whether the check can run per-branch on changed
  files, or whether finished plans should be exempt once their item ships
- Backlog 097 built the checker and is done. This item is the debt that built up behind it
- Spec: none — `moderate` goes straight to Plan
- Plan: `docs/superpowers/plans/2026-08-21-stale-plans-citations-plan-112.md`
- The plan revises the first acceptance box. Measurement showed the full-corpus scan cannot be
  clean for everybody at once: the same plans score 82 problems from this worktree and 104 from
  the backlog-110 worktree, and the two disagree about which files are broken. A plan another
  branch is writing cites lines that are right on that branch and wrong here. Box 1 as written
  asks for something no repair can deliver; the plan says what to deliver instead
