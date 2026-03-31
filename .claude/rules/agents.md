---
alwaysApply: true
description: >
  Guidelines for subagent usage, model selection, and skill loading.
---

# Agent & Tool Usage Rules

- Use subagents for parallel research, exploration, and independent tasks. One task per subagent.
- Don't use subagents for trivial, single-step tasks.
- Use Sonnet for routine tasks (formatting, simple refactors, test generation, boilerplate).
- Use Opus for complex architecture decisions, design reviews, and multi-system analysis.
- Check `.claude/skills/` for relevant skills before starting implementation.

| Need | Tool / Approach |
|---|---|
| Find type definition | csharp-lsp plugin or Grep |
| Check public API surface | csharp-lsp plugin |
| Verify no regressions | `dotnet build` + `dotnet test` |
| Parallel research | Subagent |
| Architecture decision | Opus |
| Routine refactor | Sonnet |
