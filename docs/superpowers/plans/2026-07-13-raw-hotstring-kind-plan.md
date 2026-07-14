# Plan: Raw hotstring kind — spec finalization & next steps

**Date:** 2026-07-13
**Spec:** [2026-07-13-raw-hotstring-kind-design.md](../specs/2026-07-13-raw-hotstring-kind-design.md)
**Status:** Implemented. Spec finalized → [implementation plan](2026-07-13-raw-hotstring-kind-implementation-plan.md) executed (P0–P14) on `worktree-feature-wt-raw-hotstring-kind`; review findings fixed in follow-up (`2c33830`).

## Context

Brainstorming session concluded: replace the Script hotstring kind with a **Raw** kind
that stores an entire AHK v2 hotstring definition verbatim (e.g.
`:K1000 SE*:ftw::for the win`), preserving exotic option flags the structured fields
can't express. Full design in the spec above.

## Steps

1. ~~Write spec to `docs/superpowers/specs/`~~ — done, self-reviewed
2. ~~Create branch~~ — done: work lives on the worktree branch
   `worktree-feature-wt-raw-hotstring-kind` (PR branch per `feature/wt-` convention at
   PR time)
3. ~~Commit spec + this plan~~ — done (`5f4da7b`, review fixes in follow-up commits)
4. ~~User reviews spec (review gate)~~ — done
5. ~~Invoke superpowers:writing-plans for the detailed implementation plan~~ — done
   ([implementation plan](2026-07-13-raw-hotstring-kind-implementation-plan.md)), then
   executed P0–P14

## Approved decision checklist (spec must keep capturing these)

1. Raw **replaces** Script — new enum value 4; `Script = 3` retired (legacy snapshot conversion only)
2. Storage: `Replacement` = verbatim definition (column → `nvarchar(max)`); `Trigger` server-derived (client-trigger validation gated to non-Raw kinds); option flag columns ignored for Raw; window context stays active
3. EF migration: widen `Replacement` + rewrite `Kind=3` rows to emitted form with `Kind=4`; SQL mirrors option building **and** trigger escaping; byte-identical generated scripts; no down-migration; shared golden fixtures (option matrix, backtick/`;` triggers, CRLF/blank-edged bodies, 4,000-char body) guard migration + history composer + dialog compose
4. New pure `RawHotstringDefinitionParser` (Application/Services)
5. `AddRawKindRules` (8 structural rules; multi-definition → "paste one at a time", no Import referral) + option flags validated against known AHK v2 set incl. `S`/`S0` but **not** `X0` (no documented off-form); longest-match goldens `SE*`/`S0`/`SI`/`SP`; Raw trigger ≤ 40 (AHK's limit; structured kinds keep 50); documented restricted subset (naive brace count on brace bodies only, no escaped tab/newline triggers, OTB braces and continuation sections rejected with actionable messages)
6. Emitter Raw branch returns `Replacement` verbatim; save-time trim + CRLF→LF only; `#HotIf` grouping and preview pipeline unchanged
7. Dialog: Raw = monospace textarea + server-authoritative parsed summary (`HotstringPreviewDto.RawSummary`); trigger/options fields hidden; kind-switch compose/decompose with discard-options confirmation; "Switch to Raw" suggestion
8. Lists: derived trigger fills columns; mobile shows "Raw" chip, suppresses option checkmarks; CLI changed explicitly (own enum) + minimal `--raw` creation
9. Desktop grid: promote inline draft/edit row to full dialog via `Tune` action button; cancel restores inline state; Add still defaults to inline Text draft
10. Errors: existing ValidatingUseCase → ProblemDetails; conflict handling unchanged; restore/revert convert legacy `Kind=3` snapshots via shared composer
11. Tests: TDD parser/validator; emitter round-trip; migration equivalence via shared golden fixtures + max-length row (Testcontainers); legacy-snapshot restore/revert; API integration; bUnit dialog + promote; E2E `RawHotstringFlowTests`
12. Docs & API contract: `docs/cli/hotstrings.md` rewritten for `--raw` + Raw kind; OpenAPI history example Script→Raw; `Script = 3` XML-documented as rejected legacy
13. Out of scope: Raw in bulk Import (follow-up backlog), CLI Raw UX beyond `--raw` create, semantic AHK validation / full lexer, OTB/continuation-section support

## Verification

- Spec + plan committed on `worktree-feature-wt-raw-hotstring-kind`
- Spec content matches every item in the checklist above
