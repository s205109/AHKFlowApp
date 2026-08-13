# Cross-Agent Git Guardrails

The human works directly in the main checkout of this repository. They do not want an agent
changing state under them — especially the branch they are standing on. Local Claude Code, Codex,
and GitHub Copilot agent sessions gate every Git command the same way. The test: could it change
the human's HEAD, index, or working tree in the main checkout? A command that cannot is allowed
even from main. Most commands that can need a managed linked worktree, or an in-session approval
prompt. See "Location tiers" below for the full breakdown. A session running **in main** may still
**read, edit, build, test, and format** there — this is a Git-mutation guard, not a filesystem
sandbox. A session running in a managed worktree is different: it may read main, but a shell
command that writes there is refused. See "Worktree write isolation" below.

## What "managed" means

Most Git mutations are allowed only from a **managed linked worktree**, which is all three of:

1. a **linked** worktree (its `--git-dir` differs from the repository's `--git-common-dir`);
2. located as a **direct child** of `<main>/.claude/worktrees` or `<main>/.worktrees`;
3. carrying a **valid** `scripts/.env.worktree` manifest — every required key present exactly
   once, the three ports numeric, the API/UI URLs carrying the manifest ports, DB/compose values
   non-empty, and `AHKFLOW_ROOT` resolving back to the worktree root.

The supported way to create one is `scripts/new-worktree.ps1`, or the agent's native `EnterWorktree`
tool — that tool fires the `WorktreeCreate` hook, which runs the same script.
A raw `git worktree add` run by an agent is Tier 2 — allowed even from main, with no prompt (see
"Location tiers" below). It skips the manifest and no-auth setup that `scripts/new-worktree.ps1`
performs, though, so the resulting worktree would still fail the managed check. Use the script, or
the `EnterWorktree` tool, whose child Git calls the payload never exposes to the guard.

This "managed worktree" requirement applies only to Tier 1a and Tier 1b operations (see "Location
tiers" below). Tier 2 operations never need a managed worktree — for example `git worktree prune`,
or a safe `git branch -d` on an already-merged branch. They run from main with no prompt.

## How enforcement works

| Layer | Where | Scope |
| --- | --- | --- |
| `PreToolUse` command guard | `.claude/hooks/pre-bash-guard.sh` → `scripts/agents/invoke-agent-worktree-guard.ps1` | Primary. Every agent Bash/shell tool call. |
| `PreToolUse` file-edit guard | `.claude/hooks/pre-edit-guard.sh` → `scripts/agents/invoke-agent-worktree-guard.ps1` | Claude `Edit`, `Write`, and `NotebookEdit` tool calls. |
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

**Tier 1a — Ask.** The rule: every currently-guarded Git subcommand that is not on the Tier 2 list
above, and is not `commit`, falls in Tier 1a. This is the complement of two closed sets, so the
rule cannot go stale the way a hand-typed list can — a subcommand this rule misses cannot exist by
construction.

For example, Tier 1a covers `checkout`, `reset`, `stash`, `push`, `tag` create/delete, and
`worktree move`/`repair`, plus roughly two dozen more. This is a sample for readability, not the
full list. For the full, authoritative set, read `$script:AgentGuardMutatingSubcommands` and the
conditional-subcommand `switch` inside `Test-AgentGitMutation`, both in
`scripts/agents/agent-worktree-guard.common.ps1`.

`push` stays in Tier 1a on purpose: TEST auto-deploys on push to `main`. An unprompted push could
trigger a live deployment. That is a risk on top of the HEAD/index/working-tree test.

Every Tier 1a operation needs an in-session approval prompt to run from main.

**Tier 1b — hard denial, no prompt, ever.** `git commit` is the only Git-mutation subcommand here.
`commit` can never become a prompt. A `PreToolUse` approval happens before the command runs. The
separate `.githooks/pre-commit` backstop runs after, and it has no way to know a prompt was
approved. An approved-then-backstop-blocked commit would be worse than today's outright denial, so
`commit` stays a hard denial regardless of location. This dominates the whole chained command, not
just the `commit` segment: `git add . && git commit -m x` is denied outright, even though `git add`
alone would only need a prompt.

Two more hard denials exist outside the tier system entirely. This change does not touch them: a
destructive-command safety-rule match (force-push, `reset --hard`, `clean -f`, `checkout .`, a
dangerous `rm -rf`), and an unparseable `ambiguous-git-command`. Neither was ever gated by
location logic.

### Worktree write isolation

Separate from the Git tiers. When the session's working directory is a **managed worktree**, a
write that resolves under the main checkout is denied, with rule `agent-worktree-main-write`. Two
kinds of write are covered: a shell command that writes, moves, or deletes a path, and a Claude
`Edit`, `Write`, or `NotebookEdit` tool call.

The two kinds share the path rules below and the same refusal text. They differ in what has to be
parsed. A shell command needs a command line taken apart first, so every limit further down this
section applies to it. A tool call carries one literal path, so none of those limits apply: there
is no redirect to find, no chained `cd` to track, and no shell to expand `$`, `%`, or a backtick,
which are ordinary characters in a Windows file name. The path is classified exactly as the tool
will open it, with no quote stripping and no whitespace trimming. A `~` still fails closed, because
nothing in the payload says which home directory it means. So does a path the PowerShell host
cannot parse at all — Windows PowerShell 5.1 rejects a `"` in a path where pwsh 7 accepts it.

Symlinks are followed before classification, and a relative link target is resolved against the
directory holding the link. That matters because a link inside a worktree can point at
`..\..\..\README.md`, and following it lands in the main checkout.

Allowed anyway:

- Anything inside the session's own worktree.
- Anything outside the protected checkout.
- Build output and third-party content, matched on any path component: `bin`, `obj`, `TestResults`,
  `.vs`, `node_modules`.
- `<main>\.claude\worktrees\worktree-removal.log`, by exact path.
- Anything **strictly inside** `<main>\docs\superpowers\`, the private plans repository. The public
  repo git-ignores that path and links it into every worktree, so a write there cannot change a
  tracked file or enter a public commit. The root itself stays refused: every worktree links to it.
  A move from elsewhere in main into it stays refused too, because a move reports both endpoints.
  Deletes there are ordinary deletes — `rm -rf` is denied inside it exactly as it is everywhere.

Two paths are refused before any of the allowances above are read: `<main>\.git` and
`<main>\docs\superpowers\.git`. A repository's metadata is not an ordinary file inside it, and
destroying it destroys the repository with all history that was never pushed. The order matters:
a branch may be named `bin` or `obj`, and `.git\worktrees` holds one directory per managed
worktree, so a ref or metadata path can carry a build-output component. Read later, the
build-output allowance would clear it.

A **sibling** worktree is refused. It is another agent's checkout, so writing into it breaks the
same isolation the rule exists to protect.

Write targets are found from unquoted redirects, from a per-command destination table, and from
nested `sh -c` / `pwsh -Command` arguments to a depth of 2. `cp`, `mv`, `install`, and `ln` are
read for `-t` and `--target-directory` as well, because that option moves the destination off the
last argument.

`mv`, `Move-Item`, and `Rename-Item` report their **source** as well as their destination, because
a move deletes the path it reads. `cp`, `install`, `ln`, and `Copy-Item` report the destination
only. So moving a file out of main is refused wherever it is going, a worktree included.

`Move-Item`, `Rename-Item`, and `Remove-Item` can take the paths they delete from the pipeline
instead of from their own arguments. The guard reads the command text and never runs it, so it
cannot know which paths arrive that way. A segment that follows an unquoted `|` and names no
source of its own is therefore denied:

```powershell
Get-Item <main>\README.md | Move-Item -Destination .\README.md   # denied
Get-ChildItem *.tmp | Remove-Item                                # denied
Remove-Item *.tmp                                                # allowed
```

The second line is denied even though it stays inside the worktree. Nothing in the text says
where `Get-ChildItem` looks, so the guard cannot tell it apart from the first line. Write the
paths out as arguments, or with `-Path`, and the command is classified normally.

A source that IS written out keeps working under a pipe: `Get-Content list.txt | Remove-Item
-Path a.txt` is classified on `a.txt`. `Move-Item` and `Rename-Item` need **two** operands before
the source counts as written out, because PowerShell binds a single positional to `-Path` and
leaves the piped input unbound. Sinks that delete nothing they receive — `Copy-Item`,
`Set-Content`, `Select-Object` — are unaffected, wherever the pipeline reads from. `||` is bash's
OR, not a pipe, so it never triggers this.

Every built-in alias of the three sinks is matched: `ri`, `rd`, `rmdir`, `del`, `erase`, and `rm`
for `Remove-Item`; `mi`, `move`, and `mv` for `Move-Item`; `rni` and `ren` for `Rename-Item`.
PowerShell resolves each one to the same cmdlet, so `Get-Item <main>\README.md | ri` deletes the
file exactly as `| Remove-Item` does. `rm` and `mv` are on the list for that reason, even though
coreutils `rm` reads no path from standard input — a bash pipeline into it deletes nothing, so
denying it costs nothing. This is the one place the guard reads aliases; everywhere else it still
classifies the command word as written.

A target the guard cannot expand is denied, because the guard cannot tell where it lands. That
covers a leading `~`, and a variable, a percent expansion, a command substitution, or a backtick
**anywhere** in the path. A leading literal prefix does not rescue it: `./scripts/$DEST` reaches
main when `DEST` is `../../../../README.md`. A glob is different — a glob cannot match `..` or a
rooted path, so the literal prefix before it decides, and `rm -rf ./obj/*` stays allowed.

The same rule applies to nesting past the depth limit. An inner command the guard never scanned
is not an inner command that writes nothing, so a third level of `sh -c` is denied outright.

A directory change the guard cannot expand — `cd "$MAIN_ROOT"` — makes every later **relative**
write in the same chain untargetable, so those are denied too. Later absolute writes still
classify exactly, and a later resolved `cd` restores tracking.

`AHKFLOW_ALLOW_MAIN=1` downgrades this to a warned allow, as it does for the location rules.

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
`Deny` for a subagent call, on every adapter that can detect it. In practice, `agent_id` is
extracted only from the non-Copilot payload branch (see the adapter contract above), so on Copilot
this downgrade can never fire — a Copilot subagent call is never detected as one, and instead
surfaces as whatever Copilot's own `Ask` handling decides (see "Adapter matrix for `Ask`" above).
It is unclear whether a subagent's permission prompt reaches the human the same way a main-thread
prompt does. A blocked subagent should report back that the command needs a retry from the main
thread, where it gets a real prompt.

### Measured latency

Warm p50 over 20 runs after 5 warmups, Windows 11 / PowerShell 7:

| Path | p50 |
| --- | --- |
| Shim, noncandidate command (exits in Bash) | ~54 ms |
| Shim, read-only Git candidate | ~725 ms |
| Shim, mutating Git candidate | ~975 ms |
| Codex direct PowerShell, mutating Git candidate | ~630 ms |
| Shim, worktree session, noncandidate read (exits in Bash after two `jq` calls) | ~267 ms |
| Shim, worktree session, write candidate | ~1256 ms |

The two worktree-session rows were measured later, on a different day. A main-checkout noncandidate
re-measured at ~72 ms in that same run, against the ~54 ms above, so read the two sets as separate
baselines rather than comparing them directly.

The floor is process startup: ~260 ms for `pwsh` itself, plus ~200–340 ms more when Git Bash is
the one spawning it. Only *candidate* commands pay this. Making the Git paths faster would mean
either duplicating policy into Bash (rejected — it would drift from the PowerShell core) or
starting PowerShell for every command (rejected — it would cost the ~54 ms common case ~500 ms).

A worktree session pays more than a main-checkout session even for a read. Its `cwd` contains the
`worktrees` segment, so the raw prefilter cannot exit early and the shim runs `jq` twice before
deciding. A main-checkout session never matches that pattern and keeps its original cost.

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
- `git commit --no-verify`, a replaced `core.hooksPath`, and shell aliases remain bypasses. This is
  also why calling `new-worktree.ps1` / `remove-worktree-local-dev.ps1` does not self-lock.
- The guard now reads past `rtk`, including its leading global options and its pass-through
  subcommands (`proxy`, `run`, `err`, `summary`, `test`).
- A wrapper can still hide the command inside a quoted string. The tokenizer keeps a quoted string
  as one token, so the guard cannot classify the git word inside it. `sh -c '...'` and
  `rtk run "..."` bypass the guard this way.
- The tokenizer skips a heredoc body and a here-string body, but it is never told which shell will
  run the command. A bash command whose line ends in `@'` therefore has the text below it skipped
  as a here-string body, although bash has no here-strings. That text is invisible to the guard
  today as well, because the tokenizer swallows it into one quoted string, so this opens no new
  gap. It only makes the result the same every time.
- `pwsh -File custom.ps1` bypasses the guard for a different reason: it runs git from inside a
  script file, not from a quoted string. The guard only reads the command line the hook reports,
  not any file that command line points to.
- Tests pin two smaller gaps here instead of fixing them. A wrapper option can consume the next
  token as its value, for example `rtk --out foo git commit`. rtk has no such option today. A
  `NAME=value` assignment placed after the wrapper also bypasses the guard, for example
  `rtk FOO=1 git commit -m x`.
- An externally registered command-rewriting `PreToolUse` hook can quietly turn the guard off. This
  differs from a person knowingly typing a wrapper, because the hook runs on every command by
  default, not only when someone chooses to type it. `rtk hook claude` is one example; the
  transparent-wrapper list is the mitigation.
- The transparent-wrapper list is hard-coded and narrow on purpose. Any wrapper that is not on the
  list hides its child git calls exactly as before.
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
- **Writes** into main are guarded, in one direction only: a session whose working directory is a
  managed worktree cannot write, move, or delete a path resolving under the main checkout. This
  covers shell commands and Claude `Edit`, `Write`, and `NotebookEdit` tool calls. A main-checkout
  session is unaffected and may still edit, build, test, and format there.
- Claude Code has its own worktree isolation for `Edit` and `Write`, and it reads a session flag
  rather than the working directory. It fires only for a session started with `-w`, `--worktree`, or
  the `EnterWorktree` tool. This repository's guard reads the working directory instead, so the two
  now overlap rather than leave a gap. In a `-w` session the harness refusal wins; in every other
  worktree session this repository's refusal is the one that fires.
- Codex and Copilot file-edit tool calls are **not** covered. Their tool names and payload shapes are
  not verified here, and neither agent has native worktree isolation. Their shell commands are
  covered as before.
- The write scan reads a denylist of write commands, not an allowlist of safe ones. A writer
  outside that list — `del`, `python -c`, a compiled tool — is not detected. Same trade-off the
  Git mutation rule already makes.
- `pwsh -File script.ps1` is still unread. The guard classifies the command line the hook reports,
  never a file that command line points at.
- In a `-w` session, Claude Code's own `Edit`/`Write` refusal wins, and it tells the agent to edit
  "the worktree copy of this file". For `docs/superpowers` no worktree copy can exist, because
  `.gitignore` excludes the path and `scripts/worktree-plans.common.ps1` links it in instead. That
  text belongs to the harness and cannot be changed here. This was measured, not assumed: a
  `PreToolUse` hook on `Edit|Write` that denies with its own message is silenced in a `-w` session —
  the harness refusal takes precedence. The same hook denies normally once `-w` is dropped, which
  proves it was loaded. What was measured is which refusal reaches the agent, not the harness's
  internal execution order. Method and output:
  `docs/superpowers/specs/2026-08-07-worktree-edit-isolation-precedence-design.md`. Tracked in
  `backlog/blocked/058-native-edit-refusal-names-missing-worktree-copy.md`, which is blocked: the
  only remaining step is a report to Anthropic, and that report has not been filed. Confirmed on
  Claude Code `2.1.224`. Until it changes upstream, treat the refusal text as wrong for
  `docs/superpowers` and do not go looking for a worktree copy of a plan or spec. This applies to a
  `-w` session only. Outside one, a write inside `docs/superpowers` is now allowed outright, so no
  refusal fires at all. Only the plans root itself is still refused there.

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

Both also run under Windows PowerShell 5.1 and in the `powershell-suites` CI job. Run every
PowerShell suite at once with `pwsh -NoProfile -File scripts/run-powershell-suites.ps1`.

## Diagnosing a denial or approval prompt without disabling hooks globally

The stderr diagnostic names the resolved adapter, action, and rule, e.g.
`[agent-guard:Claude] ask [agent-main-git-mutation]` or
`[agent-guard:Claude] deny [agent-main-git-mutation]`. To act on it:

1. If the command triggered an approval prompt, decide right there: approve it to run in main now,
   or create a worktree with `scripts/new-worktree.ps1` and re-run the command there instead.
2. If the command was denied outright by the location guard (rule `agent-main-git-mutation` and
   similar), with no prompt at all, several different cases land here, including:
   - **`git commit`.** `commit` never prompts, no matter where it runs from. Create a worktree
     with `scripts/new-worktree.ps1` and re-run it there (or set `AHKFLOW_ALLOW_MAIN=1` in
     advance — see item 3 below).
   - **Any other guarded operation, run by a subagent.** A Task/Agent-tool call would normally get
     `Ask`, but the guard downgrades that to a hard `Deny` when the call comes from a subagent
     rather than the main conversation thread (see "Subagents never see `Ask`" above). Retry the
     same command from the main thread — it gets a real prompt there — or run it from a managed
     worktree instead, which never produces a prompt in the first place.
   - **Any other guarded operation, run from Codex, or from Copilot without an interactive user.**
     Both adapters would normally get `Ask` too, but neither can show a real prompt there: Codex's
     hook contract does not support `ask` yet, so the guard renders every `Ask`-tier decision as
     `deny` for Codex instead; Copilot does emit a real `ask`, but in cloud or pipe mode — with no
     interactive user to answer it — Copilot itself degrades that to a deny (see "Adapter matrix
     for `Ask`" above). Retrying does not help here, since the cause is the adapter, not the
     caller. Create a managed worktree, or set `AHKFLOW_ALLOW_MAIN=1` in advance for the session
     (see item 3 below) — the prompt itself is never available in this case, by design.

   This list is not exhaustive — other combinations of adapter and caller may hard-deny the same
   way. A denial from a different rule (force-push, `git reset --hard`, an unparseable command, and
   the like) is a destructive-command safety rule, not a location rule. A worktree will not change
   its outcome — discuss the command with the user instead.
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
