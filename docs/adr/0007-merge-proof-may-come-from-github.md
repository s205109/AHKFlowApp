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

### A reset the branch then redid does not count as a discard

The reset rule above is narrowed by one case. A person who resets backwards and then writes the
dropped commit again has rewritten history by hand. That is what `git rebase` and
`git commit --amend` do, and this repository has never protected the originals those two strand.

So a dropped commit stops keeping the worktree only when all three of these hold:

1. The reset moved backwards: the position it moved to is an ancestor of the position it moved
   from.
2. After that reset, the branch created a commit whose subject line and author identity both equal
   the dropped commit's.
3. That commit has the reset target as an ancestor.

The question is asked of each dropped commit on its own. A branch that drops two commits and redoes
one of them keeps its worktree.

Predicate 2 compares character for character. The comparison is ordinal and case-sensitive, because
PowerShell's own `-eq` and `-ne` fold case, and a rule that folds case reads
`fix: preserve US settings` and `fix: preserve us settings` as one commit.

Only commits the branch itself created count, and a ref-log subject does not establish that on its
own. A fast-forward run with `GIT_REFLOG_ACTION=commit` writes `commit: Fast-forward` while the
branch only adopted another branch's tip, and that donor commit can carry the dropped commit's
subject and author. So each candidate entry is checked against the object it points at: git records
the new commit's own first message line after the action prefix, which a fast-forward cannot
produce.

That closes the shape a caller can reach through `GIT_REFLOG_ACTION`. It does not make ref-log text
trustworthy. `git update-ref -m` writes arbitrary text, so a caller who spells the donor's message
exactly still passes. Ref-log text carries no authentication, which is the limit this repository
already accepts for signals 1 and 2, and backlog 096 records it.

Subject and author are commit metadata, not patch text, so this reintroduces nothing backlog 095
removed. The rule also never compares the dropped commit against the base. It asks only what the
branch itself did next.

The cost is one case. Reset a commit away, then write a different commit that reuses its subject
line under the same author, and the second reads as the redo of the first. Removal then deletes the
ref log that held the dropped commit, and only `git fsck --lost-found` reaches it afterwards. That
needs a person to reuse a subject line for unrelated work in the same branch, after a reset.

Accepting any commit made after the reset was rejected. It is simpler, and an existing test
disproves it: a branch that reset away a unique merge resolution and then committed unrelated work
would have been removed.

## Consequences

The removal decision now depends on a tool outside git. That dependency is one-directional: an
unusable `gh` — missing, unauthenticated, offline, rate-limited — can only cost a removal, never
cause one. The decision falls back to local git and logs why, and the worktree stays.

The proof is a SHA, so it also marks a boundary in the branch's history. Work the branch made after
that point is reachable from the tip and from no proof, and it keeps the worktree alive. Ancestry
used to provide that protection as a side effect: a branch that gained commits after its merge
stopped being an ancestor of the base. The rule that replaces ancestry has to state it.

The lookup is bounded. One bulk call per run, cached, capped at the 100 most recent merged pull
requests, under the timeout the base fetch already uses. A pull request merged before that window
is not found and its worktree is kept, which is the safe direction. That miss is permanent: no
later run widens the window.

Tests never call GitHub. The decision takes a lookup delegate, fixtures pass a fake, and one
fixture parses real captured output so the parser stays honest about the shape GitHub returns.
