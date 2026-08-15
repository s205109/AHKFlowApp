# 096 - File line citations go stale unchecked

## Metadata

- **Epic**: Development process
- **Type**: Tooling
- **Interfaces**: none (repo process)
- **Difficulty**: moderate
- **Stage**: 3-plan

## Summary

This repository proves claims with `file:line` citations, and nothing checks that a citation still
points at what it claims. A commit that edits a file shifts every line below the edit, so citations
written in that same commit are wrong the moment it lands.

## User story

As a session reading a citation in a plan, a comment, or a backlog item, I want the cited line to
still hold the text the citation claims, so that I can trust the proof instead of re-deriving it.

## Detail

The rule that creates the exposure is in `AGENTS.md`: "Prove every identifier defined in this
repository with the `file:line` that defines it." Citations are therefore everywhere — plans,
backlog items, script comments, and test comments. Nothing checks them after they are written.

**The incident.** Backlog 087 (pull request #303) hit this inside a single commit. Commit
`b2e30e5e` replaced a two-line sentence in `docs/development/workflow.md` with a three-line one.
The file went from 1013 to 1014 lines, so everything below the edit shifted by one. The same commit
wrote six citations against the pre-edit numbering:

- `scripts/backlog.common.ps1` cited `workflow.md:481`; the Ship action had moved to 482
- `tests/BacklogNumbering.Tests.ps1` cited `workflow.md:633-641`; section 4 had moved to 634-642
- `tests/BacklogNumbering.Tests.ps1` cited `workflow.md:648`; the blocked-item rule had moved to 649
- `backlog/087` cited `workflow.md:481` twice and `workflow.md:720-723` once

A reviewer caught all six by hand. Commit `d6f8fbac` fixed them.

**A seventh was already stale, and shows this is not only a same-commit problem.** Item 087 cited
`workflow.md:257` for the rule that an item keeps `Stage: 1-pickup`. That was true when 087 was
filed. The line drifted to 255 on `main` before the branch existed, through somebody else's edit.
No commit that touched item 087 also touched `workflow.md`, so no same-commit check would have
found it.

**Two failure modes, not one.** They need different checks:

1. **Self-inflicted.** One commit edits a file and cites it. Findable at commit time.
2. **Third-party drift.** Somebody edits `workflow.md`; citations to it elsewhere in the repo go
   stale, and the commit that broke them touches none of the citing files.

**This is not what the backlog 072 drift guard does.** That guard checks that top-level bullets in
the process sections carry a `docs/development/workflow.md#stage-N-name` anchor and that the anchor
exists (`backlog/072-process-wave-2-parity-drift-guard-templates.md:61`). Anchors are stable across
line shifts, which is exactly why that guard cannot see this defect. The two are complementary.

**A line number alone cannot be checked.** `workflow.md:482` is checkable only against an
expectation of what line 482 should say. So the item has to settle a notation before it can settle
a check — see the open questions below.

## Acceptance criteria

- [ ] The repository-wide count of `file:line` citations is measured and written down, split by
      whether the cited path resolves to a file in this repository. No baseline is inherited; the
      one attempt made while filing this item produced zero and was wrong
- [ ] A check finds a citation whose cited line no longer holds what the citation claims, and it
      runs in CI on every pull request
- [ ] The check covers both failure modes above, or the item states which one it covers and why
      the other is out of scope
- [ ] A fixture proves both directions: a drifted citation fails the check, and an accurate one
      passes
- [ ] A citation on a line the pull request adds or edits must use the checkable notation. An
      unchanged citation is grandfathered, so no bulk rewrite is needed
- [ ] `AGENTS.md` says how to write a citation so the check can verify it, and the rule that
      demands `file:line` proof points at that notation

## Out of scope

- Changing the rule that claims need proof. The proof stays; only its durability changes
- Rewriting existing citations in bulk. Whatever notation this item settles applies going forward,
  and the check's first run decides how much of the back catalogue is worth fixing
- The anchor guard in backlog 072. Different mechanism, different failure

## Notes / dependencies

- Found in review of pull request #303 (backlog 087)
- Related: `backlog/072-process-wave-2-parity-drift-guard-templates.md` — anchor existence, not
  line accuracy
- The plan for 087 is `docs/superpowers/plans/2026-08-13-backlog-template-stage-field-plan.md`. It
  still carries the pre-shift numbers on purpose: it is the evidence for the root cause above
- Spec: `docs/superpowers/specs/2026-08-15-citation-freshness-check-design-096.md`
- Plan: `docs/superpowers/plans/2026-08-15-citation-freshness-check-plan-096.md`

## Baseline, measured 2026-08-15

Scan of every file from `git ls-files`, matching `path.ext:N` and `path.ext:N-M`:

| Repository | Files | Citation-shaped | Path resolves | Does not resolve | Line past end of file |
|---|---|---|---|---|---|
| This one | 1451 | 257 | 109 | 148 | 0 |
| Private plans repo | 232 | 1980 | 1312 | 668 | 13 |

One citation here already carries an expected phrase, and it is stale: `docs/development/workflow.md:615`
cites line 921 of `scripts/remove-worktree-local-dev.ps1` for text that sits on line 937.

## Unresolved questions

The spec settles notation, expectation location, and scope. What is left:

- Tier 2 stays optional. No way to detect a "new" citation, so no way to force a phrase on one.
- Private plans repo is gitignored, so CI never sees it. Local run only — who runs it, when?
- Fix the 13 out-of-range plan citations now, or leave them?
