# Attribution

Portions of the skills in this directory are adapted from `codewithmukesh/dotnet-claude-kit`.

The following skills are vendored from `dotnet/skills` (© Microsoft, MIT), lightly unchanged
except where noted:

- `dn-test-gap-analysis`, `dn-test-anti-patterns`, `dn-assertion-quality` (from the `dotnet-test` plugin)
- `dn-analyzing-dotnet-performance` (from the `dotnet-diag` plugin)
- `dn-use-js-interop` (from the `dotnet-blazor` plugin)

Guidance from `dotnet/skills` `optimizing-ef-core-queries` (from the `dotnet-data` plugin) was
merged into `dck-ef-core` rather than vendored as a separate skill.

Upstream license notice (`codewithmukesh/dotnet-claude-kit`):

```text
MIT License

Copyright (c) 2025 Mukesh Murugan

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

Upstream license notice (`dotnet/skills`):

```text
MIT License

Copyright (c) .NET Foundation and Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## mattpocock/skills

The following skills are adapted from `mattpocock/skills` (MIT), pinned at commit
`6acc160e4e0cd062dbbbd7a1b26ae92855edf07e` — the baseline for future selective merges:

- `mp-grilling`, `mp-grill-me`, `mp-domain-modeling`, `mp-grill-with-docs`, `mp-handoff`,
  `mp-triage`, `mp-prototype`, `mp-research`

Adapted, not vendored unchanged (same fork policy as `dck-*`): internal cross-skill references
are rewritten to the `mp-` folder names, and long descriptions are trimmed to this repo's
140-char skill-description budget. Each `SKILL.md` carries a header comment recording the pinned
commit and update policy (manual-selective-merge).

Upstream's `setup-matt-pocock-skills` was vendored as `mp-setup-matt-pocock-skills`, run once, and
then deleted. It is a one-time bootstrapper: it asks which issue tracker, which triage labels, and
which domain-doc layout the repo uses, then writes the answers to `docs/agents/issue-tracker.md`,
`docs/agents/triage-labels.md`, and `docs/agents/domain.md`. Those three files are the lasting
artifact and they stay. The skill itself had no second job, so keeping it only spent a slot in every
agent's skill list. Restore it from git history if the repo ever changes issue tracker.

`mp-prototype` and `mp-research` are adapted further than the other six, because upstream names
concrete tools this repo does not have. In `mp-prototype`'s `UI.md`, the JavaScript examples are
replaced with their Blazor equivalents — `[SupplyParameterFromQuery]` and `NavigationManager` for
the variant switch, `IWebAssemblyHostEnvironment.IsDevelopment()` for the production gate (not the
`DEBUG` compilation symbol, which would hide the switcher during the Release smoke test `AGENTS.md`
requires). `LOGIC.md` gets an appended "In this repo" section instead of inline edits. It covers two
things upstream cannot know: the pure module it tells you to write is JavaScript, but this app is
.NET and Blazor, so the module is translated into C# rather than lifted as-is; and `playwright-cli`
refuses a `file:` URL, so the demo is served over HTTP before any agent drives it. In `mp-research`,
an "In this repo" section is appended covering the AutoHotkey docs 403 fallback, version-pinned
API citations, and citation review. Upstream prose is otherwise left intact, so a future selective
merge still lines up.

Where an upstream rewrite introduces a new term, the adaptation explains the term in plain words
rather than rewriting the sentence around it. `AGENTS.md` **Plain English** asks for exactly that —
keep the term exact, explain it once. Rewriting upstream prose would break the merge alignment this
pin exists to protect. `mp-grilling` carries such a gloss for "design tree" and "frontier".

Upstream license notice (`mattpocock/skills`):

```text
MIT License

Copyright (c) 2026 Matt Pocock

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
