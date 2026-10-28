# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root, or
- **`CONTEXT-MAP.md`** at the repo root if it exists — it points at one `CONTEXT.md` per context. Read each one relevant to the topic.
- **`docs/adr/`** — read ADRs that touch the area you're about to work in. In multi-context repos, also check `src/<context>/docs/adr/` for context-scoped decisions.
- **ADR numbers** — nothing checks an ADR number across branches. Before you number a new ADR,
  fetch, then list the numbers on every remote branch:
  `git fetch --quiet origin`
  `git branch -r --format='%(refname:short)' | ForEach-Object { git ls-tree -r --name-only $_ -- docs/adr } | Sort-Object -Unique`
  The list reads remote-tracking branches, which are only as new as the last fetch. If the fetch
  fails, the list is out of date, so do not count it as a check.
  When two branches still pick the same number, the branch that pushed first keeps it.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/mp-domain-modeling` skill (run with `/mp-grilling` at Design, or through the `/mp-grill-with-docs` shortcut) creates them lazily when terms or decisions actually get resolved.

## File structure

Single-context repo (most repos):

```
/
├── CONTEXT.md
├── docs/adr/
│   ├── 0001-event-sourced-orders.md
│   └── 0002-postgres-for-write-model.md
└── src/
```

Multi-context repo (presence of `CONTEXT-MAP.md` at the root):

```
/
├── CONTEXT-MAP.md
├── docs/adr/                          ← system-wide decisions
└── src/
    ├── ordering/
    │   ├── CONTEXT.md
    │   └── docs/adr/                  ← context-specific decisions
    └── billing/
        ├── CONTEXT.md
        └── docs/adr/
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal — either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/mp-domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (event-sourced orders) — but worth reopening because…_
