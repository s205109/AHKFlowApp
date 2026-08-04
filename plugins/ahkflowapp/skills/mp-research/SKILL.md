---
name: mp-research
description: Use when a technical question needs primary-source research, captured as a Markdown file in the repo.
---

<!--
AHKFlow adaptation of mattpocock/skills (MIT), pinned at commit 9603c1cc8118d08bc1b3bf34cf714f62178dea3b.
Update policy: manual-selective-merge — do not bulk-sync with upstream.
-->

Spin up a **background agent** to do the research, so you keep working while it reads.

Its job:

1. Investigate the question against **primary sources** — official docs, source code, specs, first-party APIs — not a secondary write-up of them. Follow every claim back to the source that owns it.
2. Write the findings to a single Markdown file, citing each claim's source.
3. Save it where the repo already keeps such notes; match the existing convention, and if there is none, put it somewhere sensible and say where.

## In this repo

**Check the repo before going outside it.** For AutoHotkey v2, the subset this app generates and parses is already written up in `docs/development/ahk-v2-syntax.md` at the repo root. Read it first. Research the official docs only for what sits outside that surface.

**AutoHotkey docs 403 automated fetchers.** `autohotkey.com` rejects `WebFetch`. The same pages are served from the source repo, so fetch them with `gh`. Run this in Git Bash:

```bash
gh api repos/AutoHotkey/AutoHotkeyDocs/contents/docs/Hotstrings.htm --jq .content | base64 -d
```

That repo's `v2` branch is the primary source for v2 syntax. `docs/development/ahk-v2-syntax.md:7` records the same fallback.

**Pin the version before citing a .NET or NuGet API.** Read the version this repo uses from `Directory.Packages.props`, then cite the documentation for that version. Never cite an external API from memory — the same rule **Plans** in `AGENTS.md` applies to plan drafts.

**Review the citations when the agent returns.** The main agent, not the background agent, checks each claim against its cited source. A citation the main agent cannot follow back to the source is treated as unproven, and marked so in the findings file.

**Verification.** A research pass writes only Markdown, so exemption 1 in **Verification After Implementation** applies: docs only, nothing compiled. Targeted text checks plus a diff read. Say so rather than staying silent.
