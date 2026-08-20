# Merge proof may come from GitHub

A worktree is removed only when its branch's own work reached the base. Local git proves that
when the branch SHA is a non-first parent of a merge commit on the base. A rebase merge leaves no
merge commit and rewrites the SHA, so no local fact ties the branch to the base at all. This
repository has `allow_rebase_merge: true`, so that case is live.

When local git cannot prove the merge, the decision asks GitHub: a merged pull request whose
`headRefOid` the branch's own ref log recorded. GitHub is consulted last, and only then.

## Considered options

Patch identity was rejected. `git cherry` and `git range-diff` compare the text of a change, and
backlog 095 removed exactly that approach after it answered wrongly three ways: it normalises
whitespace, it skips merge commits, and it ignores author, message, signature, and empty-commit
intent.

Matching a merged pull request by head branch name was rejected. Branch names repeat here — pull
requests 321 and 322 share one head — so a name match would let a recreated worktree inherit an
older merge and lose live work. The SHA binding is what makes the signal safe.

Letting a merged pull request satisfy the whole rule was rejected. It answers one question, "did
this reach the base", and cannot answer the two that protect work: whether the branch ever
committed anything of its own, and whether removing it would discard commits a `git reset` dropped.

## Consequences

The removal decision now depends on a tool outside git. That dependency is one-directional: an
unusable `gh` — missing, unauthenticated, offline, rate-limited — can only cost a removal, never
cause one. The decision falls back to local git and logs why, and the worktree stays.

The lookup is bounded. One bulk call per run, cached, capped at the 100 most recent merged pull
requests, under the timeout the base fetch already uses. A pull request merged before that window
is not found and its worktree is kept, which is the safe direction.

Tests never call GitHub. The decision takes a lookup delegate, fixtures pass a fake, and one
fixture parses real captured output so the parser stays honest about the shape GitHub returns.
