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
`9603c1cc8118d08bc1b3bf34cf714f62178dea3b` — the baseline for future selective merges:

- `mp-grilling`, `mp-grill-me`, `mp-domain-modeling`, `mp-grill-with-docs`, `mp-handoff`,
  `mp-triage`, `mp-setup-matt-pocock-skills`

Adapted, not vendored unchanged (same fork policy as `dck-*`): internal cross-skill references
are rewritten to the `mp-` folder names, `mp-setup-matt-pocock-skills`'s triage-installed
detection targets `mp-triage` instead of upstream's literal `triage`, and long descriptions
are trimmed to this repo's 140-char skill-description budget. Each `SKILL.md` carries a header
comment recording the pinned commit and update policy (manual-selective-merge).

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
