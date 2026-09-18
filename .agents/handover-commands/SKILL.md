---
name: handover-commands
description: Use when handing the human a command to run, writing a pull request title or description, or ending a turn that used a tool.
---

# Handover commands

Three rules cover what an agent hands back to the human: the commands it asks them to run, the
pull request, and the end of a turn. `docs/development/workflow.md` holds each rule. This skill
quotes each one word for word, then shows how to follow it.

`tests/HandoverRules.Tests.ps1` fails when a quote here stops matching `workflow.md`. To change
a rule, edit `workflow.md` first, then the quote.

## Commands that run from any directory

<!-- rule: workflow.md#handed-over-commands -->
> `CONTEXT.md` defines a Handed-over command and a Directory-bound command. A command shown only
> to explain a past failure is not handed over, so these rules do not apply to it.
>
> - A handed-over command runs from any directory. It is never a Directory-bound command.
> - Every line names its own target: `git -C <absolute path>`, `gh --repo s205109/AHKFlowApp`,
>   the tool's own project or file option, and an absolute path for every script and file.
> - A handed-over command never contains `cd` or `Set-Location`. It never contains
>   `Push-Location` or `pushd` without `Pop-Location` or `popd` on the same line. The human
>   often copies one line, and a line that relied on an earlier one then fails on its own. A
>   directory change also leaves their terminal in another folder.
> - A tool with no directory option gets one line that returns to where it started:
>   `Push-Location <absolute path>; <command>; Pop-Location`.
> - A handed-over command never starts with `!`. That prefix belongs to the Claude Code prompt,
>   and a real shell reads it as an operator. In bash, `! true && echo ran` prints nothing: bash
>   runs the first command, reads its success as failure, and skips the rest. In PowerShell 7,
>   `! git --version` fails to parse, and nothing on the line runs.

### Find the absolute path

- Use the checkout the command belongs to. In a worktree, that is the path
  `scripts/new-worktree.ps1` printed, not the main checkout.
- Write the path out in full. A variable such as `$repo` is empty in the human's shell.

### Rewrite recipes

The same work, first as a Directory-bound command, then in the form that runs from anywhere:

```powershell
cd C:\Dev\segocom-github\AHKFlowApp
git status
gh pr view 419
```

```powershell
git -C C:\Dev\segocom-github\AHKFlowApp status
gh pr view 419 --repo s205109/AHKFlowApp
```

One target option per tool:

- `git`: `git -C <absolute path> <subcommand>`.
- `gh`: `--repo s205109/AHKFlowApp`. Without it, `gh` reads the repository from the current
  directory.
- `dotnet`: pass the project or folder by absolute path, as in
  `dotnet test C:\Dev\segocom-github\AHKFlowApp\tests\AHKFlowApp.API.Tests`. For `dotnet run`
  and `dotnet ef`, use `--project` and `--startup-project` with absolute paths.
- `docker compose`: `-f <absolute path to docker-compose.yml>`.
- `npm`: `--prefix <absolute path>`.
- A repository script: `pwsh -NoProfile -File <absolute path to the script>`. Some scripts read
  the current directory, for example to run `git` without `-C`. When you are not sure, use the
  one-line `Push-Location` form below.

A tool with no directory option, in PowerShell:

```powershell
Push-Location C:\Dev\segocom-github\AHKFlowApp; <command>; Pop-Location
```

The same line in bash, when bash is required:

```bash
pushd /c/Dev/segocom-github/AHKFlowApp && <command>; popd
```

### The `!` prefix

Claude Code's own instructions suggest `! <command>` for an interactive step, such as a login.
In this repository, hand over the plain command. When you need its output, ask the human to
paste it back.

## Pull request title and description

<!-- rule: workflow.md#pull-request-title-and-sessions -->
> - A pull request title carries its backlog number in words, such as `(backlog 071)`.
> - A pull request description carries a `Sessions:` line. Under it goes one bullet per agent
>   session that pushed to the branch: `- <session id> (<agent>, <stage at its first push>)`. A
>   session adds its bullet once, at its first push, and never edits it, so a later push costs
>   nothing. The list lets a reader find the transcript behind a decision. The Pickup session is
>   rarely the one that made it.
> - In Claude Code the session id is `CLAUDE_CODE_SESSION_ID`. When that is empty, use the
>   transcript file name without `.jsonl`. An agent with no session id writes `none`. A pull
>   request that no agent pushed to carries no `Sessions:` line.

A title and a `Sessions:` list, after two sessions pushed. The newest bullet comes first, because
the command below inserts it right under `Sessions:`.

```text
feat: commands skill and recap rules (backlog 075)
```

```text
Sessions:
- c613ef50-3547-49db-8275-411fd71ea30b (Claude Code, 3-plan)
- bc4780b4-288a-4f3e-8f20-dba06003327f (Claude Code, 1-pickup)
```

- Read your own id with `printenv CLAUDE_CODE_SESSION_ID` in your shell tool. This command is
  yours to run, not one to hand over.
- At Pickup, write the `Sessions:` line and your bullet into the body you pass to
  `gh pr create`.
- A later session adds its bullet with one command, so the description never enters your
  context. Replace the pull request number, the session id, and the stage:

  ```bash
  gh pr view 419 --repo s205109/AHKFlowApp --json body --jq .body | sed '/^Sessions:\r\?$/a - <session id> (Claude Code, <stage>)' | gh pr edit 419 --repo s205109/AHKFlowApp --body-file -
  ```

  Then check that the bullet landed. `sed` changes nothing when the description has no
  `Sessions:` line, so this check is not optional:

  ```bash
  gh pr view 419 --repo s205109/AHKFlowApp --json body --jq .body | grep -c "<session id>"
  ```

  Expect `1`.
- A housekeeping round serves no single item, so its title carries no backlog number.

## Ending a turn

<!-- rule: workflow.md#next-step-line -->
> - A turn that used a tool ends with a Next-step line: a line that starts `Next:` and names one
>   or two concrete steps, or a line that starts `Nothing pending.` The final message leads with
>   its Recap, one sentence that states the result. A turn with no tool call needs neither.
> - The steps may follow `Next:` on the same line, or sit in one or two list items below it.
>   Markup around the marker does not matter, so `**Next:**` counts as `Next:`.

A concrete step names an action and its object: "push the branch", "run the Gate", "answer
question 2 in the plan". "Continue" is not a step.

Three endings that pass:

```text
The suite passes, and the hook refuses a turn with no Next-step line.

Next: run the Gate, then mark the pull request ready.
```

```text
All twelve findings were checked against the source. None needs a change.

Nothing pending.
```

```text
The plan is committed.

Next:
- push the branch
- review the plan
```

Three endings that fail:

- "Let me know how you want to proceed." It names no step.
- A `Next steps` heading with a paragraph under it. The marker is `Next:`.
- A `Next:` line with a closing sentence after it. The Next-step line comes last.

In Claude Code, a `Stop` hook refuses the first stop of a turn that used a tool and has no
Next-step line. It says why. Add the line and end the turn. It never refuses twice.
