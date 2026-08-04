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

**Read the internal reference for context, then verify against the primary source.** For AutoHotkey v2, `docs/development/ahk-v2-syntax.md` at the repo root describes the subset this app generates and parses. Read it first — it tells you which corner of AHK the question lives in, and what this app already assumes. It does not settle the question. That file calls itself a working reference and names the official v2 docs as authoritative (`docs/development/ahk-v2-syntax.md:3-8`), so treat it as orientation, never as the citation. Every claim in your findings file cites the primary source, including claims the internal reference happens to agree with. A disagreement between the two is itself a finding worth reporting.

**AutoHotkey docs 403 automated fetchers.** `autohotkey.com` rejects `WebFetch`. The same pages are served from the source repo, so fetch them with `gh`. Run this in Git Bash:

```bash
gh api "repos/AutoHotkey/AutoHotkeyDocs/contents/docs/Hotstrings.htm?ref=v2" --jq .content | base64 -d
```

`?ref=v2` is not optional. That repository's default branch is `v1`, so leaving it off silently returns **v1** documentation for a v2 question — the worst kind of wrong answer, because it looks right. Note the form: `-f ref=v2` does not work here, because `-f` turns the request into a POST and the endpoint answers 404. Use the query string, or `-X GET -f ref=v2`.

**Pin the version before citing a .NET or NuGet API.** Read the version this repo uses from `Directory.Packages.props`, then cite the documentation for that version. Never cite an external API from memory — the same rule **Plans** in `AGENTS.md` applies to plan drafts.

**Review the citations when the agent returns.** The main agent, not the background agent, checks each claim against its cited source. A citation the main agent cannot follow back to the source is treated as unproven, and marked so in the findings file.

**Verification.** A research pass writes only Markdown, so exemption 1 in **Verification After Implementation** applies: docs only, nothing compiled. Targeted text checks plus a diff read. Say so rather than staying silent.
