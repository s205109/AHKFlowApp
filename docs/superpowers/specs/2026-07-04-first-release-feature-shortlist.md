# First-Release Feature Shortlist — Spec (Ideation Only)

**Date:** 2026-07-04
**Status:** Awaiting user prioritization — **nothing here is approved for build.** Each item needs explicit user approval, then its own brainstorm/spec/plan cycle.
**Parent:** [First-Release Cleanup Roadmap](2026-07-04-first-release-cleanup-roadmap-design.md)

## Purpose

Ranked candidates for what (if anything) ships as a feature alongside the first release. Sources: 2026-07-04 audit (CLI surface gap, backlog 031 remainder), `docs/architecture/product-vision.md` §6 Future list, and onboarding-value reasoning. No UI design here (user applies Claude design separately); usability notes are findings only.

## Ranked shortlist

| # | Candidate | Value | Effort | Type |
|---|---|---|---|---|
| 1 | Finish winget community-feed submission | High — completes the shipped distribution story | S-M | Release task |
| 2 | Import existing `.ahk` hotstrings | High — killer onboarding for existing AHK users | M-L | Feature |
| 3 | CLI scope decision: complete verticals OR document hotstring-focus | Medium-High — product-story coherence | S (decide) / L (build) | Decision + feature |
| 4 | Data export/backup (JSON) | Medium — trust + migration safety | S-M | Feature |
| 5 | Hotkey blacklist (reserved Windows combos) | Medium — prevents footguns | M | Feature |
| 6 | First-run onboarding hints | Medium — first-five-minutes success | S-M | Feature |

## Details

### 1. Finish winget community-feed submission (S-M, release task)

The remainder of backlog 031: author the three manifests for the current release zip, `winget validate` + local `--manifest` install test, PR to `microsoft/winget-pkgs`, verify `winget install AHKFlow.CLI` from the community feed, update `docs/cli/windows-install.md` + `docs/cli/winget-submission.md`. Mostly external-process latency, little code. **Risk:** community review round-trips take days-weeks — start early if it's a release blocker (roadmap open question #2).

### 2. Import existing `.ahk` hotstrings (M-L)

Parse a user-supplied AutoHotkey v2 script (or paste box) for `::trigger::replacement` hotstring lines and bulk-create them into a chosen profile, with a preview/confirm step and per-line skip on parse failure. Every real AHK user already has a script — this converts them in minutes and is the strongest onboarding lever on the list. Scope guard: hotstrings only, v2 syntax only, no options-flag fidelity beyond what the domain model supports; anything unparseable is listed and skipped. **Deps:** none. **Risk:** AHK syntax variety — mitigate by explicit "simple hotstrings only" contract.

### 3. CLI scope decision (S to decide; L to build verticals)

The API supports hotkeys/categories/profiles/preferences; the CLI ships hotstrings + downloads + auth only. Options: (a) build `ahkflow hotkey|category|profile` command groups for parity (L — roughly triples CLI surface + tests); (b) declare v1 CLI = hotstrings + downloads, state it in README/docs/product-vision §6 already hints this (S). Recommendation: **(b) for first release**, revisit parity by demand. This is roadmap open question #1 — a decision either way removes the current ambiguity.

### 4. Data export/backup (JSON) (S-M)

One endpoint + UI button + CLI command exporting all of a user's hotstrings/hotkeys/profiles/categories as a single JSON document. Complements #2 (import) as the trust story: your data is never locked in. Could later serve as re-import format (not in scope). **Deps:** none. **Risk:** low; main cost is deciding the schema's stability promise.

### 5. Hotkey blacklist (M)

Validate new/updated hotkeys against a curated list of reserved Windows combos (Win+L, Ctrl+Alt+Del, …) — warn or block per severity. Already on product-vision's Future list. Value is protecting users from generating scripts that fight the OS. **Deps:** none. **Risk:** curation debate; keep list small and documented.

### 6. First-run onboarding hints (S-M)

Empty-state guidance on Hotstrings/Profiles/Downloads pages (e.g. "Create your first hotstring → assign a profile → download the script") using stock MudBlazor components — copy + flow only, no visual design work. Complements the README front door from plan C. **Deps:** plan C's Getting Started copy for consistent wording. **Risk:** none; small.

## Explicitly not on the list

- Runtime execution of `.ahk` scripts (permanent non-goal, AGENTS.md).
- Frontend visual redesign (user handles with Claude design later).
- Custom AHK script management beyond generated profile scripts (product-vision §6).
- Any backend/pattern rework (cleanup plans A-C own code health).

## Next step

User picks: which items (if any) are in the first release, and answers roadmap open questions #1/#2. Each approved item then gets its own brainstorm → spec → plan.
