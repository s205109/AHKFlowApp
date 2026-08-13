# 085 - Guard reads heredoc and here-string bodies as command text

## Metadata

- **Epic**: Agent guardrails
- **Type**: Feature
- **Interfaces**: CLI
- **Difficulty**: complex
- **Stage**: 2-design

## Summary

The guard's tokenizer does not understand a bash heredoc (`<<'EOF'`) or a PowerShell here-string
(`@'...'@`). It reads the body as ordinary command text. A commit message that contains
`| Remove-Item` is therefore classified as a real pipeline sink and refused, even though nothing
in the body runs.

## User story

As a developer writing a commit message that quotes a shell command, I want the guard to ignore
the text inside a heredoc or a here-string, so that describing a command is not treated the same
as running it.

## Acceptance criteria

- [ ] `git commit -F -` with a heredoc body containing `| Remove-Item` is allowed from a managed
      worktree
- [ ] The same holds for a PowerShell here-string body, including one whose text contains an
      apostrophe before the pipe
- [ ] A real `| Remove-Item` outside any heredoc or here-string is still refused
- [ ] A body containing `> file` or `rm -rf` is no longer read as a redirect or a delete either
- [ ] Tests cover each shape above, in `tests/AgentWorktreeGuard.Tests.ps1`

## Out of scope

- Running or expanding the body. The guard classifies text and never executes it.
- Parsing every shell quoting form. Heredoc and here-string are the two shapes that bite in
  practice.

## Notes / dependencies

- Found while committing [084](done/084-guard-fails-closed-on-pipeline-bound-move-sources.md). The
  guard refused its own commit: the message body described the bug it was fixing, and that
  description contained `| Move-Item -Destination ...`.
- **Pre-existing, widened by 084.** A body carrying `> file` or `rm -rf` already tripped the older
  tiers before 084 landed. The pipeline-sink rule 084 added made a plain English sentence enough
  to trip it, which is why it now needs fixing rather than documenting.
- The apostrophe case is the sharp edge. In `@'...'@` the tokenizer enters its single-quoted state
  at the opening `'`, and an apostrophe anywhere in the body ends that state early. Every `|`
  after it reads as a real separator.
- Recorded as an accepted limitation in
  [`docs/agents/cross-agent-git-guardrails.md`](../docs/agents/cross-agent-git-guardrails.md)
  until this is fixed. Remove that bullet when it is.
- Workaround today: pass a long message with `git commit -F <file>`.
- Related: [083](083-guard-classifies-link-targets-as-write-targets.md), the other open guard item.
