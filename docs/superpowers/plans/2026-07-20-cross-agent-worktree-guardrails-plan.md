# Cross-Agent Main-Tree Git Guardrails Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent local Claude Code, Codex, and GitHub Copilot agent sessions from mutating Git state in the human-owned main checkout while preserving read-only Git inspection and ordinary edit/build/test/format workflows there.

**Architecture:** Keep the existing Bash hook as a fast candidate-token shim for Claude and Copilot, invoking one PowerShell policy core only for commands that may contain `git`, `rm`, or `dotnet` safety rules. Codex on Windows invokes that same entrypoint in one PowerShell process because an unqualified Bash executable is not portable across Windows agent installations. Thin adapters normalize native `PreToolUse` payloads, and an agent-scoped `pre-commit` hook provides a narrow backstop after merge. Within this AHKFlowApp repository, Git mutations are allowed only in a linked worktree under an approved managed-worktree directory with a valid `scripts/.env.worktree` manifest; explicit safety denials run before the location bypass.

**Tech Stack:** Windows PowerShell 5.1, PowerShell 7, Git hooks, Claude Code project hooks, Codex project hooks, GitHub Copilot hooks, and the repository's existing worktree automation.

## Global Constraints

- Version 1 is a **Git-mutation guard**, not a general filesystem sandbox. Agents may inspect, edit, build, test, and format in main; this accepted tradeoff means an agent can still dirty the main working tree.
- Scope the location rule to the AHKFlowApp repository that owns the hook. Git commands targeting an unrelated repository or initializing a repository outside the AHKFlowApp root remain allowed; the existing destructive-command safety rules still apply.
- Treat this as accidental-misuse protection, not hostile-process isolation. Shell wrappers, aliases, disabled/untrusted hooks, `git commit --no-verify`, and `git -c core.hooksPath=...` remain possible bypasses.
- Never create guard-test commits in the real AHKFlowApp main checkout. Every mutation test must use a disposable repository under `[System.IO.Path]::GetTempPath()`.
- Human shells remain unrestricted. Shared Git-hook enforcement activates only when a recognized agent marker is present.
- `AHKFLOW_ALLOW_MAIN=1` bypasses only the managed-worktree location rule and must emit a visible warning. It must not bypass force-push, destructive Git, or dangerous-file-operation rules.
- `AHKFLOW_GUARD_DISABLE=1` is an emergency, session-scoped kill switch for the entire `PreToolUse` entrypoint. It must short-circuit before strict mode, module loading, stdin parsing, or Git probes and emit a loud warning.
- Parse failures and unexpected errors in adapter normalization or location classification fail open with a warning. Only an explicit safety-rule match or a safety-rule evaluation failure fails closed.
- Do not add `reference-transaction`. It fires for fetch, reset, and other human ref writes and is too blunt for this guardrail.
- Do not add an agent launcher in version 1. `scripts/new-worktree.ps1` plus the existing `WorktreeCreate` hook already provide the supported creation path.
- Do not expand hook coverage to Edit, Write, `apply_patch`, MCP tools, or a shell-command allowlist in version 1.
- Keep `feature/wt-agent-worktree-only-enforcement` and its worktree until this replacement is implemented, verified, and judged to supersede it. Cleanup is a separate post-verification decision, not an implementation-plan task.
- Implement and commit only from `feature/wt-cross-agent-worktree-guardrails` in its managed worktree.

---

## Settled Decisions

| Review question | Decision | Rationale |
| --- | --- | --- |
| Git mutations only, or full write block? | Git mutations only. | This preserves the old plan's deliberate scope and avoids a brittle shell allowlist. Reads, edits, builds, tests, formatters, redirects, and unknown non-Git commands remain allowed in main. |
| `reference-transaction` in or out? | Out. | It affects fetch and every ref transaction, risks breaking human Git workflows, and still is not a hostile-process boundary. |
| Does Codex support project hooks? | Yes, use Bash-matched `PreToolUse` only. | Codex CLI 0.144.5 reports `hooks stable true`, and the official hook contract supports trusted repository `.codex/hooks.json` files, Bash matchers, stdin payloads, and deny responses. |
| Is Copilot using a Claude-only hook? | No. | `.github/hooks/hooks.json` already invokes the same `.claude/hooks/pre-bash-guard.sh` used by Claude. Both integrations currently fail for the same input-transport reason. |
| Should `--no-verify` be claimed as blocked? | No. | The `pre-commit` hook is a backstop, not an unskippable control. A temporary-repository test must prove and document that `--no-verify` bypasses it. |
| Should `AHKFLOW_ALLOW_MAIN=1` be a full bypass? | No. | It is a location override. Existing destructive-operation protections still apply. |
| How can a broken hook be recovered? | `AHKFLOW_GUARD_DISABLE=1` exits before all guard code. | This prevents strict-mode, parser, regex, or Git-probe defects from bricking every Bash call. Documentation also gives a manual config-edit recovery path. |
| Replace Bash with PowerShell on every call? | No for Claude/Copilot; accept one PowerShell process for Codex on Windows. | Claude/Copilot noncandidate commands exit through the existing Bash shim. Codex avoids a second wrapper process and has a recorded 650 ms warm-p50 budget. |
| How is the Codex Windows hook path expanded? | Run `pwsh -Command` and resolve the Git root inside that process; verify a real trusted-session denial from a subdirectory. | This avoids relying on Codex to expand `$(...)` or on whichever `bash` happens to be first on Windows `PATH`. |
| Which policy copy does `pre-commit` use? | The absolute main-owned `core.hooksPath` and main policy copy are authoritative after merge. | This follows the existing `pre-push` model. Feature-branch commits are protected only by `PreToolUse`; old worktrees intentionally receive the current main policy. |
| Change Claude's Git permission allowlist? | No. | The hook remains the single policy source; duplicating mutation rules in `permissions.deny` would create drift. |

Official adapter references:

- Codex hooks: <https://learn.chatgpt.com/docs/hooks>
- GitHub Copilot hooks: <https://docs.github.com/en/copilot/reference/hooks-reference>

## Verified Baseline

- `.claude/hooks/pre-bash-guard.sh` currently reads `COMMAND="${CLAUDE_TOOL_INPUT}"` instead of stdin JSON.
- A synthetic stdin payload containing `git reset --hard` exits 0 today, while the same command supplied through `CLAUDE_TOOL_INPUT` exits 2. The current destructive guard is therefore ineffective for the native stdin path.
- `.claude/hooks/pre-commit-format.ps1` and `pre-commit-changelog.ps1` already parse `.tool_input.command` from stdin and establish the repository's working pattern.
- Claude has four project Bash `PreToolUse` commands; the user's global configuration adds another. Replace the existing guard entry rather than adding another fan-out entry.
- `.github/hooks/hooks.json` points Copilot `preToolUse` at the same Bash guard. Correct the shared payload handling; do not describe this as removing a Claude-specific integration.
- The repository has no `.codex/hooks.json` today.
- `scripts/new-worktree.ps1` creates direct children of `.claude/worktrees` by default and also permits direct children of `.worktrees`.
- `scripts/setup-worktree-local-dev.ps1` writes `scripts/.env.worktree` with these keys:

  `AHKFLOW_API_PORT`, `AHKFLOW_UI_PORT`, `AHKFLOW_API_URL`, `AHKFLOW_UI_URL`,
  `AHKFLOW_DB_NAME`, `AHKFLOW_SQL_PORT`, `AHKFLOW_COMPOSE_PROJECT`, and `AHKFLOW_ROOT`.

- `scripts/worktree-git.common.ps1` already owns `Resolve-GitPath` and `Test-LinkedWorktree`. Reuse them rather than introducing competing linkage logic.
- Every tracked test path uses lowercase `tests/`. The Windows checkout masks path-case mistakes that would create a second directory on case-sensitive runners.
- `.github/workflows/ci.yml` hardcodes the PowerShell suite list in `worktree-powershell-tests`; new suites will not run in CI unless added there.
- The live `core.hooksPath` is the absolute main-checkout `.githooks` directory. Existing `pre-push.ps1` already documents that hooks therefore execute from main for every worktree and must resolve the active worktree separately.
- In this checkout, invoking unqualified `bash -c` from a linked-worktree subdirectory resolves to a shell that cannot interpret the Windows worktree `.git` path. Codex `commandWindows` must use PowerShell explicitly.
- `scripts/agents/setup-cross-agent-skills.ps1` installs `.githooks` through `core.hooksPath`. Implementation must validate behavior, not require one literal config string.
- `jq --version` reports `jq-1.8.1`, and `Get-Command jq` resolves to `~/AppData/Local/Microsoft/WinGet/Links/jq.exe`; the Bash fast path is available in the verified Windows environment. The missing-`jq` fallback remains required for other installations.
- The planned fast-path expression routes `git commit`, an indented `git commit`, `cd f&&git commit`, and uppercase `GIT commit` to PowerShell under Git Bash. `[[:space:]]` already covers leading whitespace; only the backtick-wrapped form needs the delimiter-class correction in Task 1.

## File Structure

### Create

- `scripts/agents/agent-worktree-guard.common.ps1` — payload normalization, existing safety checks, direct-Git parsing, managed-worktree classification, and the single policy decision function.
- `scripts/agents/invoke-agent-worktree-guard.ps1` — thin Claude/Codex/Copilot input-output adapter entrypoint.
- `.codex/hooks.json` — trusted project `PreToolUse` registration for Bash only.
- `.githooks/pre-commit` — POSIX shim matching the existing `pre-push` style.
- `.githooks/pre-commit.ps1` — agent-scoped commit backstop using the shared classifier.
- `tests/AgentWorktreeGuard.Tests.ps1` — payload, safety-rule, command-detection, classifier, adapter, bypass, and latency-regression tests.
- `tests/AgentPreCommitHook.Tests.ps1` — end-to-end temporary-repository tests for the Git-hook backstop.
- `docs/agents/cross-agent-git-guardrails.md` — behavior, adapter contract, setup/trust requirements, bypass, and accepted limitations.

### Modify

- `.claude/hooks/pre-bash-guard.sh` — parse stdin, infer Copilot from the native `toolArgs` payload shape, honor the emergency kill switch, exit quickly for noncandidate commands, and forward candidate payloads plus an optional explicit adapter to PowerShell.
- `.github/workflows/ci.yml` — add both new lowercase `tests/*.Tests.ps1` suites to the existing Windows PowerShell job.
- `AGENTS.md` — add the human-main/agent-worktree Git rule and scoped bypass wording.
- `.agents/worktrees/SKILL.md` — teach all synchronized agent surfaces how the guard classifies a managed worktree and how to recover from a denial.

### Retain unchanged

- `.github/hooks/hooks.json` — keep Copilot's proven bare `.claude/hooks/pre-bash-guard.sh` command byte-identical; adapter selection comes from the payload instead of unverified command-string argument parsing.

### Generated/synchronized outputs

- Do not edit generated skill copies by hand. Run `scripts/agents/setup-cross-agent-skills.ps1` after editing `.agents/worktrees/SKILL.md`, then include only the tracked changes that the repository's synchronization process intentionally produces.

---

## Task 1: Restore native stdin handling without losing destructive safeguards

**Files:**

- Create: `scripts/agents/agent-worktree-guard.common.ps1`
- Create: `scripts/agents/invoke-agent-worktree-guard.ps1`
- Create: `tests/AgentWorktreeGuard.Tests.ps1`
- Modify: `.claude/hooks/pre-bash-guard.sh`
- Verify unchanged: `.github/hooks/hooks.json`

- [ ] **Step 1: Capture the existing hook latency before changing its implementation**

Run 5 warmups and 20 measurements for a noncandidate command and a Git candidate. Compute the median explicitly; `Measure-Object -Average` is not p50. The current hook does not read stdin, so force an equivalent `cat >/dev/null` drain before sourcing it; otherwise the baseline omits work that the replacement must perform.

```powershell
function Get-Median {
    param([double[]]$Values)

    $sorted = @($Values | Sort-Object)
    $middle = [int][Math]::Floor($sorted.Count / 2)
    if ($sorted.Count % 2 -eq 1) {
        return $sorted[$middle]
    }

    return ($sorted[$middle - 1] + $sorted[$middle]) / 2
}

$payloads = @{
    Fast = @{
        hook_event_name = 'PreToolUse'
        tool_name = 'Bash'
        tool_input = @{ command = 'rg -n "Goal" README.md' }
        cwd = (Get-Location).Path
    } | ConvertTo-Json -Compress -Depth 4
    Candidate = @{
        hook_event_name = 'PreToolUse'
        tool_name = 'Bash'
        tool_input = @{ command = 'git status --short' }
        cwd = (Get-Location).Path
    } | ConvertTo-Json -Compress -Depth 4
}

$baselineCommand = 'cat >/dev/null; source .claude/hooks/pre-bash-guard.sh'

foreach ($name in $payloads.Keys) {
    1..5 | ForEach-Object {
        $payloads[$name] | bash -c $baselineCommand | Out-Null
    }

    $samples = 1..20 | ForEach-Object {
        (Measure-Command {
            $payloads[$name] | bash -c $baselineCommand | Out-Null
        }).TotalMilliseconds
    }

    [pscustomobject]@{
        Path = $name
        P50Milliseconds = Get-Median $samples
        MaximumMilliseconds = ($samples | Measure-Object -Maximum).Maximum
    }
}
```

Record the measurements in the implementation handoff. Do not add a generated benchmark artifact to the repository.

- [ ] **Step 2: Write failing native-payload regression cases**

Build table-driven tests in `tests/AgentWorktreeGuard.Tests.ps1`:

```powershell
$payloadCases = @(
    @{
        Name = 'Claude snake-case payload'
        Adapter = 'Claude'
        Payload = @{
            hook_event_name = 'PreToolUse'
            tool_name = 'Bash'
            tool_input = @{ command = 'git reset --hard' }
            cwd = $tempRepo
        }
    },
    @{
        Name = 'Codex snake-case payload'
        Adapter = 'Codex'
        Payload = @{
            hook_event_name = 'PreToolUse'
            tool_name = 'shell_command'
            tool_input = @{ command = 'git reset --hard' }
            cwd = $tempRepo
        }
    },
    @{
        Name = 'Copilot camel-case payload with JSON toolArgs'
        Adapter = 'Copilot'
        Payload = @{
            toolName = 'bash'
            toolArgs = (@{ command = 'git reset --hard' } | ConvertTo-Json -Compress)
            cwd = $tempRepo
        }
    }
)
```

Assert that each adapter normalizes to:

```text
ToolName = shell
Command  = git reset --hard
Cwd      = <normalized temporary repository path>
```

Also assert:

- `AHKFLOW_GUARD_DISABLE=1` exits 0 with a warning before input parsing or policy loading;
- a parseable shell payload with a missing or empty command warns and allows;
- a parseable Copilot non-shell tool payload is allowed without policy evaluation;
- completely malformed JSON warns and allows;
- a thrown location-classification exception warns and allows;
- an explicit safety match denies, and a thrown safety-rule evaluation fails closed;
- the optional `CLAUDE_TOOL_INPUT` fallback is used only when Claude stdin is empty and has its own regression test;
- piping a native Copilot payload through the bare `.claude/hooks/pre-bash-guard.sh` path selects the Copilot output contract without an adapter argument, including when the PowerShell entrypoint receives `Adapter=Auto` because `jq` is unavailable.

Run:

```powershell
pwsh -NoProfile -File tests/AgentWorktreeGuard.Tests.ps1
```

Expected before implementation: non-zero because the shared entrypoint does not exist and the existing stdin case is not blocked.

- [ ] **Step 3: Define the normalized contract and decision shape**

In `agent-worktree-guard.common.ps1`, expose PowerShell 5.1-compatible functions with these responsibilities:

```powershell
ConvertFrom-AgentHookInput -Adapter <Claude|Codex|Copilot> -InputJson <string>
Get-AgentCommandSafetyDecision -Command <string>
Get-AgentWorktreeGuardDecision -Command <string> -Cwd <string> -ProtectedRepoRoot <string> -AllowMain <bool>
ConvertTo-AgentHookOutput -Adapter <Claude|Codex|Copilot> -Decision <object>
```

Every policy result must use one object shape:

```powershell
[pscustomobject]@{
    Action  = 'Allow' # Allow | Warn | Deny
    Rule    = 'none'
    Message = ''
}
```

Keep adapter-specific JSON and exit-code behavior out of policy functions.

- [ ] **Step 4: Port and regression-test every existing safety rule**

Port the current behavior without broadening it:

| Command | Expected |
| --- | --- |
| `git push --force` / `git push -f` | Deny |
| `git reset --hard` | Deny |
| `git clean -f`, including combined flags | Deny |
| `git checkout .` | Deny |
| unsafe `rm -rf` / `rm -fr` | Deny |
| `rm -rf node_modules`, `bin`, `obj`, `TestResults`, `.vs`, or `/tmp` | Allow |
| `dotnet run` | Warn and allow |
| unrelated command | Allow |

Safety rules run before worktree-location logic. Add these precedence tests:

```text
AHKFLOW_ALLOW_MAIN=1 + git commit --allow-empty  => Warn/Allow
AHKFLOW_ALLOW_MAIN=1 + git reset --hard         => Deny
location classifier throws                     => Warn/Allow
safety-rule evaluator throws                    => Deny
AHKFLOW_GUARD_DISABLE=1 + git reset --hard      => Warn/Allow
```

- [ ] **Step 5: Implement the thin adapter entrypoint**

The first executable statement after the parameter block must be the emergency short-circuit. Give `Adapter` a safe default so parameter binding does not prevent recovery:

```powershell
[CmdletBinding()]
param(
    [ValidateSet('Auto', 'Claude', 'Codex', 'Copilot')]
    [string]$Adapter = 'Auto'
)

if ($env:AHKFLOW_GUARD_DISABLE -eq '1') {
    [Console]::Error.WriteLine(
        'WARNING: AHKFLOW_GUARD_DISABLE=1; all agent command guardrails are disabled.'
    )
    exit 0
}

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
```

Then:

1. read all stdin once with `[Console]::In.ReadToEnd()`;
2. when `Adapter=Auto`, select `Copilot` if the parsed top-level object has `toolArgs`; otherwise select `Claude`. Codex always supplies its explicit override;
3. normalize only the native payload;
4. evaluate explicit safety rules in a fail-closed `try/catch`;
5. evaluate repository identity and location in a separate fail-open `try/catch`;
6. map the result to the resolved agent's native response;
7. write diagnostics to stderr without echoing the entire payload or stack trace.

Output mapping:

| Adapter | Allow/warn | Deny |
| --- | --- | --- |
| Claude | exit 0; write warning text when present | write reason to stderr, exit 2 |
| Codex | exit 0 with no JSON for allow; emit `systemMessage` for warn | emit `hookSpecificOutput` with `hookEventName=PreToolUse`, `permissionDecision=deny`, and `permissionDecisionReason` |
| Copilot | exit 0 with no JSON for allow; emit native allow JSON plus reason for warn | emit native `permissionDecision=deny` plus `permissionDecisionReason` |

Do not place policy regexes or path decisions in the adapter switch.

- [ ] **Step 6: Turn the existing Bash hook into the fast, recoverable shim**

Retain `.claude/hooks/pre-bash-guard.sh` and its existing Claude and Copilot registrations. The optional first argument remains an explicit override for Codex. Without an argument, the shim extracts either `toolArgs` or `tool_input`, infers Copilot from a top-level `toolArgs` key for candidate commands, and otherwise uses Claude. If `jq` is missing, input is empty, or parsing fails, forward with `Adapter=Auto` so the PowerShell entrypoint performs the same payload-shape inference and correctness does not depend on `jq`.

```bash
#!/usr/bin/env bash

if [[ "${AHKFLOW_GUARD_DISABLE:-}" == "1" ]]; then
  echo "WARNING: AHKFLOW_GUARD_DISABLE=1; all agent command guardrails are disabled." >&2
  exit 0
fi

ADAPTER="${1:-Auto}"
INPUT=$(cat)
COMMAND=""
PARSED=0

if command -v jq >/dev/null 2>&1; then
  COMMAND=$(printf '%s' "$INPUT" | jq -er '
    if has("toolArgs") then
      (.toolArgs | fromjson | .command // empty)
    else
      (.tool_input.command // empty)
    end
  ' 2>/dev/null)
  [[ $? -eq 0 ]] && PARSED=1
fi

if [[ $PARSED -eq 1 ]]; then
  shopt -s nocasematch
  if [[ ! "$COMMAND" =~ (^|[[:space:]\;\&\|\(\)\`])(git(\.exe)?|rm|dotnet)([[:space:]]|$) ]]; then
    exit 0
  fi

  if [[ "$ADAPTER" == "Auto" ]]; then
    if printf '%s' "$INPUT" | jq -e 'has("toolArgs")' >/dev/null 2>&1; then
      ADAPTER="Copilot"
    else
      ADAPTER="Claude"
    fi
  fi
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if command -v pwsh >/dev/null 2>&1; then
  POWERSHELL=(pwsh -NoProfile -NonInteractive)
elif command -v powershell.exe >/dev/null 2>&1; then
  POWERSHELL=(powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass)
else
  echo "WARNING: agent guard could not find PowerShell; allowing command." >&2
  exit 0
fi

printf '%s' "$INPUT" |
  "${POWERSHELL[@]}" -File \
    "$SCRIPT_DIR/../../scripts/agents/invoke-agent-worktree-guard.ps1" \
    -Adapter "$ADAPTER"
```

Add regression cases proving the raw payload's `cwd` containing `segocom-github` does not force the PowerShell path when the extracted command is noncandidate, the Windows PowerShell fallback works, and a missing host warns and allows. Probe `git commit`, an indented `git commit`, `cd f&&git commit`, uppercase `GIT commit`, and a backtick-wrapped `` `git commit` ``; every case must reach PowerShell. Also prove a Copilot `toolArgs` payload selects Copilot through the bare hook path with no positional argument.

Keep `.github/hooks/hooks.json` byte-identical. Its existing native registration remains:

```json
{
  "type": "command",
  "bash": ".claude/hooks/pre-bash-guard.sh",
  "comment": "Block destructive bash commands"
}
```

Run `git diff --exit-code -- .github/hooks/hooks.json`; expected: exit 0 with no output. This avoids assuming that Copilot shell-interprets a command-plus-argument string.

Do not edit Claude's Git permission allowlist. The existing hook remains the single source of truth.

- [ ] **Step 7: Re-run tests under both supported PowerShell hosts**

```powershell
pwsh -NoProfile -File tests/AgentWorktreeGuard.Tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/AgentWorktreeGuard.Tests.ps1
```

Expected: both exit 0.

- [ ] **Step 8: Measure the replacement hook**

Repeat the same warmup and sample counts against the retained shim's direct stdin invocation. The replacement drains stdin itself; compare it with Step 1's forced-drain baseline. Acceptance budgets:

- noncandidate warm p50: no more than 40 ms above baseline and no more than 100 ms absolute when `jq` is available;
- Git-candidate warm p50: no more than 650 ms absolute;
- exactly one Claude project guard registration remains.

If a budget fails, the task is not complete: keep the Bash fast path, remove avoidable subprocesses, and repeat the measurement. Do not replace this with a PowerShell-on-every-call design.

- [ ] **Step 9: Commit the input fix**

```powershell
git add scripts/agents/agent-worktree-guard.common.ps1 `
  scripts/agents/invoke-agent-worktree-guard.ps1 `
  tests/AgentWorktreeGuard.Tests.ps1 `
  .claude/hooks/pre-bash-guard.sh
git commit -m "fix: read agent hook payloads from stdin"
```

---

## Task 2: Detect direct Git mutations and validate managed worktrees

**Files:**

- Modify: `scripts/agents/agent-worktree-guard.common.ps1`
- Modify: `scripts/agents/invoke-agent-worktree-guard.ps1`
- Modify: `tests/AgentWorktreeGuard.Tests.ps1`
- Create: `.codex/hooks.json`

- [ ] **Step 1: Add a disposable Git fixture**

The test creates its own main checkout and linked worktrees:

```powershell
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'ahkflow-agent-guard-' + [guid]::NewGuid().ToString('N')
)
$main = Join-Path $testRoot 'repo'
$managed = Join-Path $main '.claude\worktrees\valid'
$unmanaged = Join-Path $testRoot 'unmanaged'
$unrelated = Join-Path $testRoot 'unrelated'

git init --initial-branch=main $main
git init --initial-branch=main $unrelated
git -C $main config user.name 'Agent Guard Test'
git -C $main config user.email 'agent-guard@example.invalid'
Set-Content -LiteralPath (Join-Path $main 'seed.txt') -Value 'seed'
git -C $main add seed.txt
git -C $main commit -m 'test: seed temporary repository'
git -C $main worktree add -b feature/wt-valid $managed
git -C $main worktree add -b feature/wt-unmanaged $unmanaged
```

Use `try/finally`. Resolve and verify `$testRoot` remains beneath `[System.IO.Path]::GetTempPath()` before cleanup.

- [ ] **Step 2: Write failing direct-Git detection tests**

Use this regex only to locate a direct Git invocation and its tail start. Leading whitespace is part of the start alternative:

```regex
(?im)(?:^\s*|[;&|()]\s*)(?:&\s*)?git(?:\.exe)?\s+
```

From the regex match end, scan one character at a time with `None`, `SingleQuoted`, `DoubleQuoted`, and `Escaped` states; `Escaped` stores whether to return to `None` or `DoubleQuoted`. A backslash enters `Escaped` only from those two states, the next character is literal, and a backslash inside `SingleQuoted` remains literal. Stop at newline, `;`, `&`, or `|` only in `None` state; preserve separators inside quotes or escapes. Apply the same escape rules while tokenizing so the standard shell idiom `'O'\''Brien'` remains balanced. Treat a genuinely unbalanced quote as an explicit `ambiguous-git-command` safety denial, not as an internal location error. Then tokenize the complete tail so `-C "path with spaces;and separators"` stays one argument. This is intentionally not a complete shell parser.

Assert these commands contain a mutation:

```text
git add .
git commit -m test
  git commit -m indented
git switch -c fix/wt-test
git checkout -b fix/wt-test
git branch fix/wt-test
git merge topic
git rebase main
git push
git reset HEAD^
git restore file.txt
git clean -fd
git stash
git tag v1.0.0
git worktree add <path>
git config core.hooksPath disabled
git update-ref refs/heads/test HEAD
git status; git commit -m test
git status && git branch fix/wt-test
git -C "<main>" commit -m test
git -C "C:\some;path" commit -m test
git stash push
git notes add -m note HEAD
git bisect start
git apply patch.diff
git init .
```

Assert these do not:

```text
git status
git log -1
git diff
git show HEAD
git branch --show-current
git branch --list
git tag --list
git worktree list
git config --get core.hooksPath
git remote -v
git fetch
git stash list
git stash show
git notes list
git notes show HEAD
git bisect log
git apply --check patch.diff
git log --author='O'\''Brien'
rg -n "Backend|Frontend" README.md
Get-Content README.md
dotnet build
dotnet test
dotnet format
git status > status.txt
pwsh -NoProfile -File scripts/new-worktree.ps1 -Name test
pwsh -NoProfile -File scripts/remove-worktree-local-dev.ps1 -WorktreePath test
```

Assert the malformed command below is denied by the quote-safety rule rather than reported as a parsed mutation:

```text
git -C "C:\unbalanced;path commit -m test
Action = Deny
Rule   = ambiguous-git-command
```

Unknown non-Git commands and unknown Git subcommands remain allowed. Record that limitation instead of replacing mutation detection with an allowlist.

- [ ] **Step 3: Implement the mutation decision table**

Treat these Git subcommands as mutating:

```text
add am checkout cherry-pick clean commit gc maintenance merge mv pull push
rebase repack replace reset restore revert rm sparse-checkout switch
update-index update-ref
```

Handle conditional commands as follows:

| Command | Read-only forms | Mutating forms |
| --- | --- | --- |
| `branch` | no args, `--show-current`, `--list` and display filters | create/delete/move/copy/rename or any positional branch target |
| `tag` | no args, `--list` and query filters | create/delete/sign/force or a positional tag without `--list` |
| `worktree` | `list` | add/move/remove/repair/prune/lock/unlock |
| `config` | `--get*`, `--list`, `--show-*`, `--get-regexp` | set/add/unset/rename/remove/replace or name plus value |
| `remote` | no args, `-v`, `show`, `get-url` | add/remove/rename/set-url/set-head/prune/update |
| `submodule` | `status`, `summary` | add/deinit/update/set-branch/set-url/sync/absorbgitdirs |
| `reflog` | `show`, default display | delete/expire |
| `stash` | `list`, `show` | default push, push/save/pop/apply/drop/clear/create/store/branch |
| `notes` | no args, `list`, `show` | add/append/copy/edit/merge/prune/remove |
| `bisect` | `log`, `view` | start/good/bad/reset/skip/run/replay |
| `apply` | `--check`, `--stat`, `--numstat`, `--summary` without `--apply` | every form that applies to the worktree or index |
| `init` | explicit target outside the protected AHKFlowApp root | no target, `.`, or a target inside the protected root |

`git fetch` is an explicit allowed exception even though it updates remote-tracking refs. It is needed for inspection and is one reason `reference-transaction` is excluded.

- [ ] **Step 4: Define and test managed-worktree classification**

Add:

```powershell
Get-ManagedWorktreeState -Cwd <path> -ProtectedRepoRoot <path>
```

It returns one of:

```text
NotRepository
OutsideProtectedRepository
MainCheckout
ManagedWorktree
UnmanagedWorktree
InvalidManifest
```

Apply this state-to-action mapping only after detecting a Git mutation and after explicit safety rules:

| State | Base action |
| --- | --- |
| `NotRepository`, `OutsideProtectedRepository` | Allow |
| `ManagedWorktree` | Allow |
| `MainCheckout`, `UnmanagedWorktree`, `InvalidManifest` | Deny |

`AHKFLOW_ALLOW_MAIN=1` changes a location-based `Deny` to `Warn` as defined in Step 6; it never overrides an earlier safety denial. In particular, `git init` in an unrelated empty temporary directory returns `NotRepository` and is allowed, while `git init .` beneath the protected checkout resolves to `MainCheckout` and is denied.

Classification order:

1. Resolve the protected repository's absolute `--git-common-dir` from `ProtectedRepoRoot`.
2. Resolve the effective target's `--show-toplevel`, `--git-dir`, and `--git-common-dir` through Git.
3. Return `OutsideProtectedRepository` when the target common directory differs case-insensitively from the protected common directory.
4. Reuse `Resolve-GitPath` and `Test-LinkedWorktree` from `scripts/worktree-git.common.ps1`.
5. Require a linked worktree for targets inside the protected repository.
6. Resolve the main checkout from the absolute protected common Git directory.
7. Require the worktree root to be a **direct child** of either:

   - `<main>/.claude/worktrees`
   - `<main>/.worktrees`

8. Require `<worktree>/scripts/.env.worktree`.
9. Parse exactly one value per required manifest key.
10. Require `AHKFLOW_ROOT` to resolve case-insensitively to the same worktree root.
11. Require all three ports to parse as integers, API/UI URLs to equal the manifest ports, and DB/compose values to be non-empty.

Use this fixture for the valid case:

```text
AHKFLOW_API_PORT=5602
AHKFLOW_UI_PORT=5603
AHKFLOW_API_URL=http://localhost:5602
AHKFLOW_UI_URL=http://localhost:5603
AHKFLOW_DB_NAME=AHKFlowApp_valid
AHKFLOW_SQL_PORT=14330
AHKFLOW_COMPOSE_PROJECT=ahkflow-valid
AHKFLOW_ROOT=<absolute managed worktree root>
```

Add negative tests for missing manifest, missing key, duplicate key, nonnumeric port, URL/port mismatch, wrong root, nested location, sibling-prefix collision, and linked worktree outside both approved parents.

- [ ] **Step 5: Resolve the effective Git target before classification**

For every detected invocation:

- start from the hook payload's `cwd`;
- derive `ProtectedRepoRoot` from the checked-in entrypoint location, never from the command target;
- apply each literal `git -C <path>` in order;
- resolve relative `-C` paths against the preceding effective directory;
- classify the effective directory, not the hook process directory;
- deny a mutating invocation that uses `--git-dir` or `--work-tree` unless `AHKFLOW_ALLOW_MAIN=1`, because the target cannot be safely inferred by the simple tokenizer;
- if one chained command contains multiple Git invocations, deny when any mutation targets a non-managed location.

Tests must prove:

| Starting location | Command target | Expected |
| --- | --- | --- |
| main | main | Deny |
| managed worktree | same managed worktree | Allow |
| managed worktree | main through `git -C` | Deny |
| main | managed worktree through `git -C` | Allow |
| unmanaged linked worktree | itself | Deny |
| approved directory, bad manifest | itself | Deny |
| managed worktree | explicit `--git-dir` or `--work-tree` | Deny |
| protected main | unrelated repository through `git -C` | Allow |
| protected main | `git init <outside-temp-path>` | Allow |
| protected main | `git init .` | Deny |

- [ ] **Step 6: Apply bypass and message semantics**

For a location denial with `AHKFLOW_ALLOW_MAIN=1`:

- return `Warn`, not silent `Allow`;
- name the overridden rule and effective repository path;
- preserve earlier destructive-rule denials;
- never print secrets or the full environment.

If repository discovery, path normalization, manifest parsing, or Git probing throws unexpectedly, return `Warn/Allow` with `Rule=location-guard-error`. Tests must inject each failure without weakening explicit safety denials.

Use one denial message across adapters:

```text
BLOCKED: agent Git mutations are allowed only in a managed linked worktree.
Current target: <normalized path>
Create one with scripts/new-worktree.ps1 or the agent WorktreeCreate tool.
Read-only Git and ordinary edit/build/test commands are unaffected.
Override the location check with AHKFLOW_ALLOW_MAIN=1.
```

- [ ] **Step 7: Register Codex's Bash-only project hook**

Create `.codex/hooks.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash -c '\"$(git rev-parse --show-toplevel)/.claude/hooks/pre-bash-guard.sh\" Codex'",
            "commandWindows": "pwsh -NoProfile -NonInteractive -Command \"& (Join-Path ((git rev-parse --show-toplevel).Trim()) 'scripts/agents/invoke-agent-worktree-guard.ps1') -Adapter Codex\""
          }
        ]
      }
    ]
  }
}
```

Do not add `apply_patch`, Edit, Write, or MCP matchers. Codex commands run with the session `cwd`, so both command variants resolve the repository root inside an explicit shell process. Document that Codex reviews project hooks when a repository becomes trusted.

- [ ] **Step 8: Run focused policy and adapter tests**

```powershell
pwsh -NoProfile -File tests/AgentWorktreeGuard.Tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/AgentWorktreeGuard.Tests.ps1
Get-Content -LiteralPath .codex/hooks.json -Raw | ConvertFrom-Json | Out-Null
codex features list
```

Expected:

- both test hosts exit 0;
- JSON parsing exits 0;
- Codex reports `hooks` enabled and stable;
- representative Claude, Codex, and Copilot allow/warn/deny fixtures match their native contracts.

- [ ] **Step 9: Prove Codex path expansion and denial in a real trusted session**

From the managed worktree, derive the main checkout and then launch Codex from the `docs` subdirectory:

```powershell
$commonDir = (git rev-parse --path-format=absolute --git-common-dir).Trim()
$mainCheckout = Split-Path -Parent $commonDir
$mainCheckout
codex -C docs
```

Inside that Codex session:

1. run `/hooks`;
2. review and trust the exact project hook hash;
3. ask Codex to run this nonmutating probe, replacing `<main-checkout>` with the printed path:

   ```text
   Run exactly this shell command and report the hook result:
   git -C "<main-checkout>" add --dry-run .
   ```

Expected: the tool call is denied with the shared `BLOCKED: agent Git mutations...` message. A normal Git dry-run result is a failure because it proves registration without proving command execution or path expansion.

Also measure 5 warmups plus 20 direct synthetic invocations of the decoded `commandWindows` value. Warm p50 must be at most 650 ms. This is the accepted Windows Codex startup budget; do not add an extra Bash wrapper around PowerShell.

- [ ] **Step 10: Commit the primary guard**

```powershell
git add scripts/agents/agent-worktree-guard.common.ps1 `
  scripts/agents/invoke-agent-worktree-guard.ps1 `
  tests/AgentWorktreeGuard.Tests.ps1 `
  .codex/hooks.json
git commit -m "feat: guard agent git mutations in main"
```

---

## Task 3: Add the agent-scoped pre-commit backstop

**Files:**

- Create: `.githooks/pre-commit`
- Create: `.githooks/pre-commit.ps1`
- Create: `tests/AgentPreCommitHook.Tests.ps1`
- Modify if shared helpers are required: `scripts/agents/agent-worktree-guard.common.ps1`
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Write failing end-to-end tests in disposable repositories**

Follow `tests/PrePushHook.Tests.ps1` for assertions, process invocation, and cleanup. Copy the in-development `pre-commit` pair, `agent-worktree-guard.common.ps1`, and `worktree-git.common.ps1` into the same relative layout inside each temporary repository, then set that repository's `core.hooksPath` to its copied `.githooks` directory. This makes the disposable repository—not the real AHKFlowApp checkout—the protected repository identity.

Create real temporary commits for this matrix:

| Context | Environment | Expected |
| --- | --- | --- |
| temporary main | no agent marker | commit succeeds |
| temporary main | `CLAUDECODE=1` | commit fails |
| temporary main | nonempty `CLAUDE_CODE_ENTRYPOINT` | commit fails |
| temporary main | nonempty `CODEX_THREAD_ID` | commit fails |
| temporary main | `AHKFLOW_AGENT_SESSION=1` | commit fails |
| valid managed worktree | agent marker | commit succeeds |
| unmanaged linked worktree | agent marker | commit fails |
| approved location with invalid manifest | agent marker | commit fails |
| temporary main | agent marker plus `AHKFLOW_ALLOW_MAIN=1` | commit succeeds and warning is visible |
| temporary main | agent marker plus `--no-verify` | commit succeeds, proving the documented bypass |

Do not use arbitrary `CODEX_*` or `COPILOT_*` wildcard detection; humans may legitimately have configuration variables with those prefixes.

Run:

```powershell
pwsh -NoProfile -File tests/AgentPreCommitHook.Tests.ps1
```

Expected before implementation: non-zero because `.githooks/pre-commit` does not exist.

- [ ] **Step 2: Add the shim in the existing hook style**

Copy only the host-selection pattern from `.githooks/pre-push`:

1. locate `pre-commit.ps1` beside the shim;
2. prefer `pwsh`;
3. fall back to `powershell.exe`;
4. preserve the PowerShell script's exit code;
5. fail visibly if neither host exists.

- [ ] **Step 3: Implement the PowerShell backstop**

`pre-commit.ps1` must:

1. exit 0 immediately when no recognized agent marker is present;
2. resolve the repository being committed with `git rev-parse --show-toplevel`;
3. derive `ProtectedRepoRoot` from the parent of the hook-owning `.githooks` directory and use `$PSScriptRoot` to load that root's policy copy, never to infer the active worktree;
4. call `Get-ManagedWorktreeState` for the repository being committed;
5. allow `ManagedWorktree`;
6. deny main, unmanaged, and invalid worktrees with the shared message;
7. honor `AHKFLOW_ALLOW_MAIN=1` with a warning and exit 0;
8. warn and exit 0 on an unexpected policy-loading or location-classification error so a main-policy/worktree-version mismatch cannot brick Git.

This backstop does not protect the Task 3 implementation commits: the configured main `.githooks` directory has no `pre-commit` until the feature is merged. Temporary-repository tests point `core.hooksPath` at the in-development hook, while the already-active `PreToolUse` layer remains the implementation-time protection. After merge, old worktrees intentionally execute main's current policy rather than their branch's older copy.

Recognized markers:

```text
AHKFLOW_AGENT_SESSION=1
CLAUDECODE=1
CLAUDE_CODE_ENTRYPOINT=<nonempty>
CODEX_THREAD_ID=<nonempty>
```

Copilot does not have a verified, stable child-process environment marker in scope for version 1. Its primary protection is the native `preToolUse` adapter; users who need the Git-hook backstop can launch the session with `AHKFLOW_AGENT_SESSION=1`.

- [ ] **Step 4: Verify human and bypass behavior under both hosts**

```powershell
pwsh -NoProfile -File tests/AgentPreCommitHook.Tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/AgentPreCommitHook.Tests.ps1
pwsh -NoProfile -File tests/PrePushHook.Tests.ps1
```

Expected: all exit 0. The `--no-verify` case must be reported as an accepted bypass, never described as blocked.

- [ ] **Step 5: Add both guard suites to CI**

Modify the existing `worktree-powershell-tests` run block in `.github/workflows/ci.yml`:

```yaml
- name: Run worktree PowerShell tests
  shell: pwsh
  run: |
    ./tests/AgentWorktreeGuard.Tests.ps1
    ./tests/AgentPreCommitHook.Tests.ps1
    ./tests/WorktreePowerShellHost.Tests.ps1
    ./tests/WorktreeMergedCleanup.Tests.ps1
    ./tests/WorktreeRemoveHook.Tests.ps1
    ./tests/WorktreeLocalDevSetup.Tests.ps1
    ./tests/SkillParity.Tests.ps1
    ./tests/PrePushHook.Tests.ps1
```

Run the same eight commands locally from the repository root. Expected: all exit 0.

- [ ] **Step 6: Commit the backstop and CI coverage**

```powershell
git add .githooks/pre-commit `
  .githooks/pre-commit.ps1 `
  tests/AgentPreCommitHook.Tests.ps1 `
  scripts/agents/agent-worktree-guard.common.ps1 `
  .github/workflows/ci.yml
git commit -m "feat: add agent pre-commit worktree guard"
```

---

## Task 4: Document the rule and adapter contract

**Files:**

- Create: `docs/agents/cross-agent-git-guardrails.md`
- Modify: `AGENTS.md`
- Modify: `.agents/worktrees/SKILL.md`
- Regenerate through the setup script: tracked cross-agent skill copies, if any

- [ ] **Step 1: Write the operational documentation**

`docs/agents/cross-agent-git-guardrails.md` must state:

- main is human-owned for Git mutations, but agents may still read, edit, build, test, and format there;
- managed means linked plus approved direct-child location plus valid manifest;
- the supported creation route is `scripts/new-worktree.ps1` or `WorktreeCreate`;
- `AHKFLOW_ALLOW_MAIN=1` overrides location only and warns;
- `AHKFLOW_GUARD_DISABLE=1` disables the entire command guard only for emergency recovery and emits a warning;
- project hook trust and setup requirements for Claude, Codex, and Copilot;
- `jq` is an optional Claude/Copilot fast-path dependency; missing `jq` falls back to PowerShell;
- why `reference-transaction` and a general shell allowlist are out;
- why `commit --no-verify` and command wrappers remain accepted gaps;
- why the absolute main-owned `core.hooksPath` makes main's policy authoritative for old worktrees after merge;
- how to run the focused tests;
- how to diagnose a denial without disabling hooks globally.

Include this recovery procedure:

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

- [ ] **Step 2: Record the future-adapter contract verbatim**

Include:

```text
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

- [ ] **Step 3: Update contributor and skill guidance**

In `AGENTS.md` under Git Workflow, add:

```text
The AHKFlowApp main checkout is human-owned for Git mutations. Agents may
inspect, edit, build, test, and format there, but must branch, add, commit,
merge, rebase, and push for this repository only from a managed linked
worktree. Use scripts/new-worktree.ps1 or the WorktreeCreate tool.
AHKFLOW_ALLOW_MAIN=1 is an explicit location override; destructive-command
protections still apply.
```

In `.agents/worktrees/SKILL.md`, add:

- the three managed-worktree checks;
- exact recovery commands after a denial;
- the scoped bypass;
- the emergency kill switch and manual config-edit recovery;
- the authoritative-main Git-hook version-skew behavior;
- the instruction to edit the `.agents` source, not synchronized copies.

- [ ] **Step 4: Synchronize and verify cross-agent skill copies**

```powershell
pwsh -NoProfile -File scripts/agents/setup-cross-agent-skills.ps1
pwsh -NoProfile -File tests/SkillParity.Tests.ps1
pwsh -NoProfile -File tests/CodexSkillsHashParity.Tests.ps1
```

Expected: all exit 0. Review every generated tracked change; do not commit unrelated cache or local configuration.

- [ ] **Step 5: Commit documentation**

```powershell
git add AGENTS.md `
  .agents/worktrees/SKILL.md `
  docs/agents/cross-agent-git-guardrails.md `
  plugins/ahkflowapp
git commit -m "docs: explain cross-agent git guardrails"
```

If `plugins/ahkflowapp` has no tracked synchronization changes, omit it from `git add`.

---

## Task 5: Run focused and repository-wide verification

**Files:**

- Verify only; fix failures in the task that introduced them.

- [ ] **Step 1: Run all guard tests under PowerShell 7 and Windows PowerShell 5.1**

```powershell
pwsh -NoProfile -File tests/AgentWorktreeGuard.Tests.ps1
pwsh -NoProfile -File tests/AgentPreCommitHook.Tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/AgentWorktreeGuard.Tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/AgentPreCommitHook.Tests.ps1
```

Expected: all exit 0, all test repositories are under the system temp directory, and cleanup leaves no fixture worktrees.

- [ ] **Step 2: Run existing worktree and hook regression suites**

```powershell
pwsh -NoProfile -File tests/WorktreePowerShellHost.Tests.ps1
pwsh -NoProfile -File tests/WorktreeLocalDevSetup.Tests.ps1
pwsh -NoProfile -File tests/WorktreeMergedCleanup.Tests.ps1
pwsh -NoProfile -File tests/WorktreeRemoveHook.Tests.ps1
pwsh -NoProfile -File tests/PrePushHook.Tests.ps1
```

Expected: all exit 0. These tests, rather than live cleanup commands, prove `new-worktree.ps1` and `remove-worktree-local-dev.ps1` remain usable.

- [ ] **Step 3: Validate native hook configuration and representative payloads**

```powershell
Get-Content -LiteralPath .claude/settings.json -Raw | ConvertFrom-Json | Out-Null
Get-Content -LiteralPath .github/hooks/hooks.json -Raw | ConvertFrom-Json | Out-Null
Get-Content -LiteralPath .codex/hooks.json -Raw | ConvertFrom-Json | Out-Null
codex features list
codex doctor
```

Expected:

- all JSON parses;
- exactly one project guard registration exists per agent;
- Claude and Copilot both reference the retained bare `pre-bash-guard.sh` fast shim, `.github/hooks/hooks.json` is unchanged, and the bare-path Copilot payload test proves `toolArgs` selects the Copilot contract;
- Codex's matcher is Bash only;
- Codex `commandWindows` invokes one explicit PowerShell process and does not contain a literal `-File "$(git ...)"` path;
- the focused test has exercised native Claude, Codex, and Copilot payloads.

Retain the trusted-session deny evidence from Task 2; `codex features list` or `/hooks` registration alone is insufficient.

- [ ] **Step 4: Run cross-agent setup and parity checks**

```powershell
pwsh -NoProfile -File scripts/agents/setup-cross-agent-skills.ps1
pwsh -NoProfile -File tests/SkillParity.Tests.ps1
pwsh -NoProfile -File tests/CodexSkillsHashParity.Tests.ps1
```

Expected: all exit 0.

Confirm CI names both new suites with their tracked lowercase paths:

```powershell
rg -n 'tests/(AgentWorktreeGuard|AgentPreCommitHook)\.Tests\.ps1' .github/workflows/ci.yml
```

Expected: exactly two matching command lines.

- [ ] **Step 5: Run the repository Release gate**

```powershell
dotnet restore
dotnet build --configuration Release --no-restore
dotnet test --configuration Release --no-build --verbosity normal
dotnet format --verify-no-changes --no-restore
```

Expected: all exit 0.

- [ ] **Step 6: Run final repository hygiene checks**

```powershell
git diff --check
git status --short
git log --oneline -4

$commonDir = (git rev-parse --path-format=absolute --git-common-dir).Trim()
$mainCheckout = Split-Path -Parent $commonDir
git -C $mainCheckout status --short

git worktree list --porcelain |
    Select-String 'agent-worktree-guard'
git branch --list feature/wt-agent-worktree-only-enforcement
```

Expected:

- `git diff --check` exits 0;
- the feature worktree has only intentional changes before the final commit and is clean afterward;
- the main checkout status is empty;
- the obsolete worktree and branch still exist pending an explicit post-verification cleanup decision;
- the commit sequence is:

  1. `fix: read agent hook payloads from stdin`
  2. `feat: guard agent git mutations in main`
  3. `feat: add agent pre-commit worktree guard`
  4. `docs: explain cross-agent git guardrails`

## Post-Merge Smoke Gate

Run this after the feature is merged into main and before deleting the old plan branch or worktree. It verifies the real absolute `core.hooksPath` rather than the test-local hook path:

```powershell
$commonDir = (git rev-parse --path-format=absolute --git-common-dir).Trim()
$mainCheckout = Split-Path -Parent $commonDir
$hooksPath = (git -C $mainCheckout config --path core.hooksPath).Trim()
if (-not [System.IO.Path]::IsPathRooted($hooksPath)) {
    $hooksPath = Join-Path $mainCheckout $hooksPath
}
$preCommit = Join-Path $hooksPath 'pre-commit.ps1'

if (-not (Test-Path -LiteralPath $preCommit)) {
    throw "Merged pre-commit hook not found at $preCommit"
}

$priorMarker = $env:AHKFLOW_AGENT_SESSION
try {
    Remove-Item Env:AHKFLOW_AGENT_SESSION -ErrorAction SilentlyContinue
    Push-Location $mainCheckout
    & pwsh -NoProfile -File $preCommit
    if ($LASTEXITCODE -ne 0) { throw 'Human main smoke should allow.' }

    $env:AHKFLOW_AGENT_SESSION = '1'
    & pwsh -NoProfile -File $preCommit
    if ($LASTEXITCODE -eq 0) { throw 'Agent main smoke should deny.' }
}
finally {
    Pop-Location
    if ($null -eq $priorMarker) {
        Remove-Item Env:AHKFLOW_AGENT_SESSION -ErrorAction SilentlyContinue
    }
    else {
        $env:AHKFLOW_AGENT_SESSION = $priorMarker
    }
}
```

Then call the same main-owned policy from the still-retained managed implementation worktree:

```powershell
$managedWorktree = Join-Path $mainCheckout '.claude\worktrees\cross-agent-worktree-guardrails'
if (-not (Test-Path -LiteralPath (Join-Path $managedWorktree 'scripts\.env.worktree'))) {
    throw "Managed smoke worktree is unavailable: $managedWorktree"
}

$priorMarker = $env:AHKFLOW_AGENT_SESSION
try {
    $env:AHKFLOW_AGENT_SESSION = '1'
    Push-Location $managedWorktree
    & pwsh -NoProfile -File $preCommit
    if ($LASTEXITCODE -ne 0) { throw 'Agent managed-worktree smoke should allow.' }
}
finally {
    Pop-Location
    if ($null -eq $priorMarker) {
        Remove-Item Env:AHKFLOW_AGENT_SESSION -ErrorAction SilentlyContinue
    }
    else {
        $env:AHKFLOW_AGENT_SESSION = $priorMarker
    }
}
```

Expected: exit 0. This confirms that the main-owned hook classifies the active worktree rather than `$PSScriptRoot`.

## Risks and Accepted Limitations

- Project hooks can be untrusted, disabled, time out, or change schema. Trust checks and native-payload tests reduce drift but do not make them mandatory OS controls.
- `AHKFLOW_GUARD_DISABLE=1` disables safety and location checks by design. It is an emergency recovery control, must warn, and must not be set persistently.
- Adapter parse errors and unexpected location-policy errors fail open to preserve shell availability. Loud warnings and the `pre-commit` backstop reduce, but do not eliminate, that enforcement gap.
- `pre-commit` does not run for branch creation, index changes, `--no-verify`, or a replaced `core.hooksPath`. It is deliberately a narrow backstop.
- The absolute main-owned `core.hooksPath` means Task 3 implementation commits do not exercise the backstop before merge. After merge, every worktree—including an older branch—loads main's current policy copy. Temporary-repository tests and the post-merge smoke gate cover those two phases explicitly.
- No `reference-transaction` hook means direct ref writes not recognized by the primary parser can escape enforcement.
- A wrapper such as `pwsh -File custom-script.ps1` can perform child Git commands that the outer `PreToolUse` payload does not expose. This is also why calling `new-worktree.ps1` and `remove-worktree-local-dev.ps1` does not self-lock.
- Copilot's shared Git backstop depends on `AHKFLOW_AGENT_SESSION=1` until a stable native session marker is verified. Its project `preToolUse` hook remains the primary layer.
- Main-tree edits, builds, tests, and formatters are intentionally allowed and can create or modify files. The guard prevents Git mutation, not a dirty working tree.
- The simple command tokenizer is not a complete Bash or PowerShell parser. Tests cover representative chains, redirects, quoting, and `git -C`; hostile obfuscation is out of scope.
- Claude and Copilot retain a Bash fast path; only candidate commands start PowerShell. Windows Codex accepts one PowerShell startup per Bash tool call with a 650 ms warm-p50 budget.
- The old plan is retained until this implementation passes all verification, so recovery does not depend only on reflog.

## Unresolved Questions

None. Recovery, latency budgets, Codex Windows execution, Copilot payload-shape selection, CI coverage, repository scope, and post-merge Git-hook authority are settled above.
