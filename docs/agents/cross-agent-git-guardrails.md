# Cross-Agent Git Guardrails

The human works directly in the main checkout of this repository. They do not want an agent
changing state under them — especially the branch they are standing on. Local Claude Code, Codex,
and GitHub Copilot agent sessions gate every Git command the same way. The test: could it change
the human's HEAD, index, or working tree in the main checkout? A command that cannot is allowed
even from main. Most commands that can need a managed linked worktree, or an in-session approval
prompt. See "Location tiers" below for the full breakdown. Agents may still **read, edit, build,
test, and format** in main — this is a Git-mutation guard, not a filesystem sandbox.

## What "managed" means

A Git mutation is allowed only from a **managed linked worktree**, which is all three of:

1. a **linked** worktree (its `--git-dir` differs from the repository's `--git-common-dir`);
2. located as a **direct child** of `<main>/.claude/worktrees` or `<main>/.worktrees`;
3. carrying a **valid** `scripts/.env.worktree` manifest — every required key present exactly
   once, the three ports numeric, the API/UI URLs carrying the manifest ports, DB/compose values
   non-empty, and `AHKFLOW_ROOT` resolving back to the worktree root.

The supported way to create one is `scripts/new-worktree.ps1`, or the agent's native `EnterWorktree`
tool — that tool fires the `WorktreeCreate` hook, which runs the same script.
A raw `git worktree add` run by an agent is itself a guarded mutation — denied from main — and it
skips the manifest and no-auth setup, so the result would fail the managed check anyway. Use the
tool, whose child Git calls the payload never exposes to the guard.

This "managed worktree" requirement applies only to Tier 1a and Tier 1b operations (see "Location
tiers" below). Tier 2 operations never need a managed worktree — for example `git worktree prune`,
or a safe `git branch -d` on an already-merged branch. They run from main with no prompt.

## How enforcement works

| Layer | Where | Scope |
| --- | --- | --- |
| `PreToolUse` command guard | `.claude/hooks/pre-bash-guard.sh` → `scripts/agents/invoke-agent-worktree-guard.ps1` | Primary. Every agent Bash/shell tool call. |
| `pre-commit` backstop | `.githooks/pre-commit` → `.githooks/pre-commit.ps1` | Narrow. Agent-marked commits only, after merge. |

The Bash hook is a fast candidate-token filter: a command that cannot contain `git`, `rm`, or
`dotnet` exits without starting PowerShell. Candidates go to the shared policy core in
`scripts/agents/agent-worktree-guard.common.ps1`, which normalizes the native payload, runs the
ported destructive-command rules, then classifies the effective Git target's location.

### Adapter contract

```
Adapter input:
  Native PreToolUse JSON on stdin.

Normalized input:
  { ToolName, Command, Cwd }

Policy input:
  Command + Cwd + ProtectedRepoRoot + AHKFLOW_ALLOW_MAIN.

Policy output:
  { Action = Allow|Warn|Deny|Ask, Rule, Message }

Adapter output:
  The agent's native allow/warn/deny response.

Rule:
  AHKFLOW_GUARD_DISABLE short-circuits before this contract.
  Adapters normalize payloads and responses only.
  Path classification, mutation detection, bypass precedence, and messages live
  in scripts/agents/agent-worktree-guard.common.ps1.
```

- **Claude** registers the bare `.claude/hooks/pre-bash-guard.sh`.
- **Copilot** registers the same shim in `.github/hooks/hooks.json` under `bash`, plus a
  `powershell` entry that calls the PowerShell entrypoint directly with `-Adapter Copilot`.
  Copilot selects `bash` on Unix and `powershell` on Windows, so a `bash`-only entry would leave
  the guard inactive on Windows entirely. On the `bash` path the adapter is still *inferred* from
  a top-level `toolArgs` key rather than a command argument.
- **Codex** registers `.codex/hooks.json` with a Bash matcher only. On Windows the `commandWindows`
  variant runs one explicit PowerShell process and resolves the repository root inside it. Codex
  reviews project hooks when a repository becomes trusted.

### Location tiers

The location rule sorts every mutating Git invocation into one of three tiers. The test: could
this command change the human's HEAD, index, or working tree in the main checkout?

**Tier 2 — always allowed, even from main, no worktree, no prompt.** None of these can touch the
human's HEAD, index, or working tree:

- `git worktree prune`, in any form.
- `git worktree add <path> <branch>` — unless it carries `--force`/`-f`, or `-B`. `-B` is git's
  own force spelling for `worktree add`: it resets an existing branch's tip, which is not the same
  as the safe `-b`.
- `git worktree remove <path>` — unless `--force`/`-f`.
- `git worktree list` — already read-only, unaffected by this change.
- `git branch -d`/`--delete <name>` — unless it carries any force spelling, including bare `-D`
  (git treats `-D` as `-d --force` combined — it is not the same flag as `-d`) or a clustered
  short option such as `-df`/`-fd`.
- A plain `git branch <name>` create — only when it carries zero flags at all.
- `git remote prune <name>`.
- `git fetch` — already unguarded before this change, still unaffected.

**Tier 1a — Ask.** Everything else that is currently guarded and is not `commit`: `checkout`,
`switch`, `restore`, `reset`, `stash`, `add`, `mv`, `rm`, `merge`, `rebase`, `pull`,
`cherry-pick`, `revert`, `push` (kept in this tier on purpose — TEST auto-deploys on push to
`main`, so an unprompted push could trigger a live deployment, a risk on top of the
HEAD/index/working-tree test), `tag` create/delete, `config` writes, `gc`/`repack`/`maintenance`,
`reflog expire`/`delete`, `worktree add`/`remove` with `--force`/`-f`/`-B`, `worktree
move`/`repair`/`lock`/`unlock` in every form, `branch -D`/`-m`/`-M`/`-f`/`-u`/`--set-upstream-to`,
and any `-d` carrying a force flag. These need an in-session approval prompt to run from main.

**Tier 1b — hard denial, no prompt, ever.** `git commit` is the only Git-mutation subcommand here.
`commit` can never become a prompt. A `PreToolUse` approval happens before the command runs. The
separate `.githooks/pre-commit` backstop runs after, and it has no way to know a prompt was
approved. An approved-then-backstop-blocked commit would be worse than today's outright denial, so
`commit` stays a hard denial regardless of location.

Two more hard denials exist outside the tier system entirely. This change does not touch them: a
destructive-command safety-rule match (force-push, `reset --hard`, `clean -f`, `checkout .`, a
dangerous `rm -rf`), and an unparseable `ambiguous-git-command`. Neither was ever gated by
location logic.

**Adapter matrix for `Ask`.** Each adapter renders `Ask` differently:

- **Claude** sets `hookSpecificOutput.permissionDecision = "ask"` and exits 0, which escalates to
  a real permission prompt in the session.
- **Copilot** also sends `permissionDecision = "ask"`. Without an interactive user — cloud or pipe
  mode — Copilot degrades that to a deny, which is safe.
- **Codex never receives `ask`.** Codex's hook contract marks `ask` "parsed but not supported
  yet." It treats an unsupported value as a failed hook run. A failed hook run lets the tool call
  proceed, so Codex fails *open* on it. The guard renders every `Ask`-tier decision as `deny` on
  Codex instead. Codex agents get a hard denial where Claude and Copilot agents get a prompt; that
  is deliberate, not a gap.
- An unrecognized decision action fails closed (denies) on every adapter.

**Subagents never see `Ask`.** A Task/Agent-tool call carries `agent_id` in Claude's hook payload
only when it originates inside a subagent. The guard reads that field and downgrades an `Ask` to
`Deny` for a subagent call, on every adapter. It is unclear whether a subagent's permission
prompt reaches the human the same way a main-thread prompt does. A blocked subagent should report
back that the command needs a retry from the main thread, where it gets a real prompt.

### Measured latency

Warm p50 over 20 runs after 5 warmups, Windows 11 / PowerShell 7:

| Path | p50 |
| --- | --- |
| Shim, noncandidate command (exits in Bash) | ~54 ms |
| Shim, read-only Git candidate | ~725 ms |
| Shim, mutating Git candidate | ~975 ms |
| Codex direct PowerShell, mutating Git candidate | ~630 ms |

The floor is process startup: ~260 ms for `pwsh` itself, plus ~200–340 ms more when Git Bash is
the one spawning it. Only *candidate* commands pay this. Making the Git paths faster would mean
either duplicating policy into Bash (rejected — it would drift from the PowerShell core) or
starting PowerShell for every command (rejected — it would cost the ~54 ms common case ~500 ms).

## Setup and trust

- Claude picks up `.claude/settings.json` automatically.
- Copilot loads `.github/hooks/hooks.json` automatically.
- Codex loads `.codex/hooks.json` once the repository is **trusted** (`/hooks` shows and confirms
  the hook hash).
- `jq` is an optional Claude/Copilot fast-path dependency. If it is missing, the shim forwards the
  payload with `Adapter=Auto` and the PowerShell entrypoint performs the same inference — behavior
  is identical, only slightly slower.

## Bypasses

| Switch | Effect |
| --- | --- |
| `AHKFLOW_ALLOW_MAIN=1` | Overrides the **location** rule for every tier, including `commit` (turns a location Deny, or what would otherwise be an Ask prompt, into a warned Allow). Force-push, destructive-Git, and dangerous-file rules still apply. |
| `AHKFLOW_GUARD_DISABLE=1` | Emergency kill switch. Short-circuits the **entire** command guard before strict mode, module loading, stdin parsing, or Git probes, and warns loudly. Never set it persistently. |

`AHKFLOW_ALLOW_MAIN=1` is no longer the main way to handle a one-off main-checkout mutation. For
everything except `commit`, the in-session approval prompt handles that now — see "Location
tiers" above. Set `AHKFLOW_ALLOW_MAIN=1` instead when you expect several main-checkout mutations
in one session and do not want to approve each one. It is also the only way through when the
mutation is `commit`, which never prompts.

### Where `AHKFLOW_ALLOW_MAIN=1` has to be set

For the `PreToolUse` guard it must be in the **environment the agent session inherits**, set before
the session starts:

```powershell
$env:AHKFLOW_ALLOW_MAIN = '1'   # then launch the agent from this terminal
```

An inline `AHKFLOW_ALLOW_MAIN=1 git ...` prefix **does not work**. The guard runs in its own
process and inspects the command as text; the prefix only ever reaches the child `git` process.
An agent cannot self-apply the override — by design, relaxing the location rule is the human's
call.

The `pre-commit` backstop behaves differently: git spawns it and passes its own environment down,
so there an inline `AHKFLOW_ALLOW_MAIN=1 git commit ...` does take effect.

A human's own shell is never subject to the `PreToolUse` guard at all — it is an agent hook. A
human's own shell can still run main-checkout maintenance directly — for example `git branch -D`.
An agent running the same command would need a prompt or override.

## Accepted limitations

- Project hooks can be untrusted, disabled, or time out. These are accidental-misuse guards, not OS
  controls.
- `reference-transaction` is intentionally **not** used: it fires for fetch, reset, and every human
  ref write, and is too blunt for this guardrail.
- No general shell-command allowlist. Unknown non-Git commands and unknown Git subcommands are
  allowed; mutation detection is a denylist, not an allowlist.
- `git commit --no-verify`, a replaced `core.hooksPath`, shell aliases, and wrappers such as
  `pwsh -File custom.ps1` (whose child Git calls the outer payload never exposes) remain bypasses.
  This is also why calling `new-worktree.ps1` / `remove-worktree-local-dev.ps1` does not self-lock.
- Adapter parse errors and unexpected location-policy errors **fail open** with a warning; only an
  explicit safety-rule match (or a safety-rule evaluation fault) **fails closed**.
- Main-tree edits, builds, tests, and formatters are allowed and can dirty the working tree. The
  guard prevents Git mutation, not a dirty tree.
- The command tokenizer is not a full Bash/PowerShell parser. Representative chains, redirects,
  quoting, `git -C`, leading `NAME=value` prefixes, quoted and path-qualified executables
  (`"git"`, `/usr/bin/git`, `"C:\Program Files\Git\cmd\git.exe"`), and directory changes (`cd`,
  `chdir`, `pushd`/`popd`, `Set-Location`) are covered; hostile obfuscation is out of scope.
- Directory tracking models the shell: a `cd` to a path that does not exist **fails**, so the
  guard leaves the effective directory unchanged rather than believing the move happened, and
  `pushd`/`popd` are tracked as a stack. Both matter because a mutation after a failed `cd` still
  executes wherever the shell actually is.
- A directory change the guard cannot expand literally (`cd $HOME`, `cd -`, bare `cd`) makes a
  following mutation untargetable, so it is denied with `agent-unresolved-git-target`. Read-only
  Git after such a `cd` is unaffected. Pass an explicit `git -C <path>` to be classified normally.
- `commit --no-verify` and `--git-dir`/`--work-tree` targeting cannot be safely inferred, so a
  mutating invocation using `--git-dir`/`--work-tree` is denied outright (unless `AHKFLOW_ALLOW_MAIN=1`).
- File edits in main are not guarded by this mechanism at all. An `Edit`/`Write` tool call can
  change the human's files under them the same way a Git mutation can, but this guard only covers
  Git commands. Closing that gap is separate work, not part of this change.

## Version-skew and authoritative main

`core.hooksPath` is the absolute main-checkout `.githooks` directory, so after merge **every**
worktree — including an older branch — runs main's current policy copy. Feature-branch commits
before merge are protected only by the `PreToolUse` layer; the `pre-commit` backstop begins after
merge. Both phases are covered by the temporary-repository tests and the post-merge smoke gate.

## Running the tests

```powershell
pwsh -NoProfile -File tests/AgentWorktreeGuard.Tests.ps1
pwsh -NoProfile -File tests/AgentPreCommitHook.Tests.ps1
```

Both also run under Windows PowerShell 5.1 and in the `worktree-powershell-tests` CI job.

## Diagnosing a denial or approval prompt without disabling hooks globally

The stderr diagnostic names the resolved adapter, action, and rule, e.g.
`[agent-guard:Claude] ask [agent-main-git-mutation]` or
`[agent-guard:Claude] deny [agent-main-git-mutation]`. To act on it:

1. If the command triggered an approval prompt, decide right there: approve it to run in main now,
   or create a worktree with `scripts/new-worktree.ps1` and re-run the command there instead.
2. If the command was denied outright by the location guard (rule `agent-main-git-mutation` and
   similar), it needs a worktree. This is always `git commit`, the one subcommand that never
   prompts. Create a worktree with `scripts/new-worktree.ps1` and re-run it there. A denial from a
   different rule (force-push, `git reset --hard`, an unparseable command, and the like) is a
   destructive-command safety rule, not a location rule. A worktree will not change its outcome —
   discuss the command with the user instead.
3. Expect several main-checkout mutations this session and do not want to approve each one? Set
   `AHKFLOW_ALLOW_MAIN=1` in the session environment before starting the agent (see "Where
   `AHKFLOW_ALLOW_MAIN=1` has to be set" — an inline prefix does **not** reach the `PreToolUse`
   guard). It is also the only way through for `git commit`, which never prompts. A warning is
   printed; destructive rules still apply.
4. Only for a broken hook, use the emergency recovery procedure below.

### Emergency recovery

```text
1. In a human-owned PowerShell terminal, set:
   $env:AHKFLOW_GUARD_DISABLE = '1'
2. Start a new agent session from that terminal and repair the hook.
3. If a shell-script syntax error prevents the kill switch from running, edit
   .claude/settings.json by hand outside the agent and temporarily remove the
   pre-bash-guard.sh PreToolUse object.
4. For the equivalent Copilot or Codex failure, edit .github/hooks/hooks.json
   or .codex/hooks.json by hand.
5. Re-enable the hook only after both guard suites pass, then remove the
   AHKFLOW_GUARD_DISABLE environment variable.
```
