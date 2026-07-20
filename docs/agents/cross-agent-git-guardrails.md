# Cross-Agent Git Guardrails

Local Claude Code, Codex, and GitHub Copilot agent sessions must not mutate Git state in the
human-owned main checkout of this repository. Agents may still **read, edit, build, test, and
format** in main — this is a Git-mutation guard, not a filesystem sandbox.

## What "managed" means

A Git mutation is allowed only from a **managed linked worktree**, which is all three of:

1. a **linked** worktree (its `--git-dir` differs from the repository's `--git-common-dir`);
2. located as a **direct child** of `<main>/.claude/worktrees` or `<main>/.worktrees`;
3. carrying a **valid** `scripts/.env.worktree` manifest — every required key present exactly
   once, the three ports numeric, the API/UI URLs carrying the manifest ports, DB/compose values
   non-empty, and `AHKFLOW_ROOT` resolving back to the worktree root.

The supported way to create one is `scripts/new-worktree.ps1` or the agent `WorktreeCreate` tool.

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
  { Action = Allow|Warn|Deny, Rule, Message }

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
| `AHKFLOW_ALLOW_MAIN=1` | Overrides the **location** rule only (turns a location Deny into a warned Allow). Force-push, destructive-Git, and dangerous-file rules still apply. |

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

A human's own shell is never subject to the `PreToolUse` guard at all — it is an agent hook. Main
checkout maintenance (`git worktree remove`, `git branch -D`) is simply run directly.
| `AHKFLOW_GUARD_DISABLE=1` | Emergency kill switch. Short-circuits the **entire** command guard before strict mode, module loading, stdin parsing, or Git probes, and warns loudly. Never set it persistently. |

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
  quoting, `git -C`, leading `NAME=value` prefixes, and directory changes (`cd`, `chdir`, `pushd`,
  `Set-Location`) are covered; hostile obfuscation is out of scope.
- A directory change the guard cannot expand literally (`cd $HOME`, `cd -`, bare `cd`) makes a
  following mutation untargetable, so it is denied with `agent-unresolved-git-target`. Read-only
  Git after such a `cd` is unaffected. Pass an explicit `git -C <path>` to be classified normally.
- `commit --no-verify` and `--git-dir`/`--work-tree` targeting cannot be safely inferred, so a
  mutating invocation using `--git-dir`/`--work-tree` is denied outright (unless `AHKFLOW_ALLOW_MAIN=1`).

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

## Diagnosing a denial without disabling hooks globally

The stderr diagnostic names the resolved adapter and rule, e.g.
`[agent-guard:Claude] deny [agent-main-git-mutation]`. To act on it:

1. If the command genuinely belongs in a worktree, create one with `scripts/new-worktree.ps1` and
   re-run it there.
2. For a one-off intentional main mutation, prefix with `AHKFLOW_ALLOW_MAIN=1` (a warning is
   printed; destructive rules still apply).
3. Only for a broken hook, use the emergency recovery procedure below.

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
