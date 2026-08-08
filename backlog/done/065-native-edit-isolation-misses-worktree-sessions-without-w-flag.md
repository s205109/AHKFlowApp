# 065 - Native Edit isolation misses worktree sessions started without `-w`

## Metadata

- **Epic**: Agent tooling
- **Type**: Bug
- **Interfaces**: UI | API | CLI (none — agent tooling only)

## Summary

Claude Code's native `Edit`/`Write` isolation and this repository's own Bash write guard disagree
about what counts as "a session inside a worktree".

| Guard | Decides from | Covers |
|---|---|---|
| Claude Code native isolation | a session flag set by `-w` / `--worktree` / `EnterWorktree` | `Edit`, `Write` |
| Repository guard (backlog 054) | the `cwd` in the hook payload | `Bash` writes |

A Claude session started **directly inside a worktree directory**, without `-w` and without
`EnterWorktree`, never gets the native isolation flag. It can therefore `Edit` and `Write` files in
the human-owned main checkout. The repository guard still blocks that session's Bash writes,
because it reads `cwd`. So the two halves of the protection disagree, and `Edit` is the open half.

## Evidence

Observed on Claude Code 2.1.224, 2026-08-07, both runs launched from the main checkout.

**Probe A — no `-w`, cwd is a worktree.** The edit succeeded.

```bash
cd "C:/Dev/segocom-github/AHKFlowApp/.claude/worktrees/058-native-edit-refusal"
printf '%s' "Use the Edit tool ONCE to change 'probe target' to 'PROBE-A-EDITED' in C:\Dev\segocom-github\AHKFlowApp\probe-058-main.txt ..." \
  | claude -p --permission-mode acceptEdits --add-dir "C:/Dev/segocom-github/AHKFlowApp" --allowed-tools Edit Read
```

Result:

> The file C:\Dev\segocom-github\AHKFlowApp\probe-058-main.txt has been updated successfully.

Reading the file back from the main checkout confirmed the new content, `PROBE-A-EDITED`.

**Probe A2 — the same case with no `--add-dir` at all.** Probe A granted the main checkout
explicitly, so on its own it could not tell whether that grant was what made the write possible.
The official recipe for working in a worktree by hand does not pass the flag
(https://code.claude.com/docs/en/worktrees), so the untested case was the one that matters. It was
run separately, with `Write` rather than `Edit` so the target did not have to exist first:

```bash
cd "C:/Dev/segocom-github/AHKFlowApp/.claude/worktrees/058-native-edit-refusal"
printf '%s' "Use the Write tool ONCE to create the file C:\Dev\segocom-github\AHKFlowApp\probe-063-writetest.log ..." \
  | claude -p --permission-mode acceptEdits --allowed-tools Write Read
```

Result:

> File created successfully at: C:\Dev\segocom-github\AHKFlowApp\probe-063-writetest.log

The target was a `*.log` path, ignored by `.gitignore:110`, so the write left the main checkout's
git status clean. A matching `Read` of `C:\Dev\segocom-github\AHKFlowApp\.git\HEAD` — a path that
cannot exist inside a linked worktree — returned `ref: refs/heads/main`, which confirms the main
checkout is inside the session's allowed directories with no grant.

So `--add-dir` is not what opens the hole. The defect stands without it.

**Probe B — same edit, same target, with `-w`.** The edit was refused.

> This session is isolated in the worktree
> C:\Dev\segocom-github\AHKFlowApp\.claude\worktrees\probe058b. Edit the worktree copy of this
> file instead of the shared-checkout path.

**Probe A again, but through Bash.** With the shell `cwd` inside the worktree, the repository guard
denied the same write:

> [agent-guard:Claude] deny [agent-worktree-main-write]
> BLOCKED: this session is isolated in a worktree, so it cannot write into the main checkout at
> C:\Dev\segocom-github\AHKFlowApp\probe-058-main.txt

Same session, same target path, opposite outcomes depending on which tool made the write.

## Why this is its own item

Found while probing `backlog/blocked/058-native-edit-refusal-names-missing-worktree-copy.md`.
058 is about the **wording** of a refusal that does fire. This item is about a case where **no
refusal fires at all**. Different defect, different fix, and 058 stays closable on its own scope.
058 is now blocked, because its only remaining step is an upstream report. This item is not
blocked by that, and stays open.

`docs/agents/cross-agent-git-guardrails.md` used to record that `Edit` and `Write` are "not covered
by this repository at all — Claude Code's own worktree isolation covers them for Claude sessions".
That sentence was true only for `-w` and `EnterWorktree` sessions. It was corrected when this item
was filed, so the documentation already describes the gap. The gap itself is still open.

## Blocking question: answered — a hook can win here

Can a repository `PreToolUse` hook on `Edit|Write` deny the write? Answered on 2026-08-07, while
probing 058. **Yes, for the sessions this item covers.**

A `PreToolUse` hook on `Edit|Write` that denies with its own message was supplied to a session
through `--settings`. Without `-w`, that hook denied the `Edit`:

> PreToolUse:Edit hook error: PROBE-C-HOOK-DENY: this refusal came from a repo PreToolUse hook, not
> the harness.

The same hook produced nothing once `-w` was added, because the harness refusal takes precedence
there. That half is 058, and it is not fixable in this repository. This item is the half a hook can
close, because no harness check applies to it at all.

Method and full output:
`docs/superpowers/specs/2026-08-07-worktree-edit-isolation-precedence-design.md`.

So this item is designable now. It needs a plan before implementation, because it changes the guard.

## Acceptance criteria

- [x] The precedence question above is answered, with the observed message recorded (shared with
      058 — answering it once serves both)
- [x] `docs/agents/cross-agent-git-guardrails.md` corrected — the claim that native isolation covers
      `Edit`/`Write` for Claude sessions holds only for `-w` and `EnterWorktree` sessions
- [x] A session started inside a worktree without `-w` cannot `Edit` or `Write` into the main
      checkout, and the refusal names the real reason and a real next step
- [x] The `docs/superpowers` case reuses the wording already shipped at
      `scripts/agents/agent-worktree-guard.common.ps1:1647`, which never tells the agent to look for
      a worktree copy
- [x] A test covers the gap, in the style of the existing cases in `tests/AgentWorktreeGuard.Tests.ps1`

## Out of scope

- The refusal wording for the case that already fires. That is 058.
- The Bash write hole. That is 054, already merged.
- Codex and Copilot. Neither has native worktree isolation, so neither has this gap.

## Notes / dependencies

- Shared its blocking question with 058. Answered once, for both, on 2026-08-07.
- Probe method and full output:
  `docs/superpowers/specs/2026-08-07-worktree-edit-isolation-precedence-design.md`
- Backlog 054 design: `docs/superpowers/specs/2026-08-06-worktree-guard-bash-writes-design.md`
- 054 already guards Bash writes from a worktree using the hook payload `cwd`. The fix here is the
  same rule applied to `Edit` and `Write`, so it should reuse 054's path resolution rather than
  grow a second copy.
- Closed by `docs/superpowers/specs/2026-08-07-worktree-edit-write-isolation-design.md` and
  `docs/superpowers/plans/2026-08-07-worktree-edit-write-isolation.md`
- Reusing 054's path resolution exposed three defects in it, all fixed on the same branch: a symlink
  whose target is relative was resolved against the hook process's working directory rather than the
  directory holding the link; a link that was the last path component indexed past the end of an
  array, which throws under the entrypoint's strict mode; and a path the PowerShell host cannot
  parse threw instead of reporting itself unresolved. Each of the three reached the entrypoint's
  catch, which allows the write. They affected the Bash rule too, so 054 is now stricter as well.
- The real-session probe that proves the fix is recorded in the pull request that closes this item.
  Three runs, all from `.claude/worktrees/065-edit-write-isolation` with no `-w`, on Claude Code
  2.1.225: a `Write` into the main checkout was denied, a `Write` into `docs/superpowers` was denied
  with the plans wording, and a `Write` inside the worktree succeeded.
