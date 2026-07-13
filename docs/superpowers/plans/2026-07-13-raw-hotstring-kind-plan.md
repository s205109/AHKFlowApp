# Plan: Raw hotstring kind — spec finalization & next steps

**Date:** 2026-07-13
**Spec:** [2026-07-13-raw-hotstring-kind-design.md](../specs/2026-07-13-raw-hotstring-kind-design.md)
**Status:** Spec written; awaiting user review, then detailed implementation plan (superpowers:writing-plans)

## Context

Brainstorming session concluded: replace the Script hotstring kind with a **Raw** kind
that stores an entire AHK v2 hotstring definition verbatim (e.g.
`:K1000 SE*:ftw::for the win`), preserving exotic option flags the structured fields
can't express. Full design in the spec above.

## Steps

1. ~~Write spec to `docs/superpowers/specs/`~~ — done, self-reviewed
2. Create branch `feature/raw-hotstring-kind` from `main`
3. Commit spec + this plan: `docs: raw hotstring kind design spec`
4. User reviews spec (review gate)
5. Invoke superpowers:writing-plans for the detailed implementation plan

## Approved decision checklist (spec must keep capturing these)

1. Raw **replaces** Script — new enum value 4; `Script = 3` retired (legacy snapshot conversion only)
2. Storage: `Replacement` = verbatim definition (column → `nvarchar(max)`); `Trigger` server-derived (client-trigger validation gated to non-Raw kinds); option flag columns ignored for Raw; window context stays active
3. EF migration: widen `Replacement` + rewrite `Kind=3` rows to emitted form with `Kind=4`; byte-identical generated scripts; no down-migration; 4,000-char-body test
4. New pure `RawHotstringDefinitionParser` (Application/Services)
5. `AddRawKindRules` (8 structural rules; multi-definition → "paste one at a time", no Import referral) + option flags validated against known AHK v2 set incl. `S`/`S0`; documented restricted subset (naive brace count on brace bodies only, no escaped tab/newline triggers)
6. Emitter Raw branch returns `Replacement` verbatim; save-time trim + CRLF→LF only; `#HotIf` grouping and preview pipeline unchanged
7. Dialog: Raw = monospace textarea + server-authoritative parsed summary (`HotstringPreviewDto.RawSummary`); trigger/options fields hidden; kind-switch compose/decompose with discard-options confirmation; "Switch to Raw" suggestion
8. Lists: derived trigger fills columns; mobile shows "Raw" chip, suppresses option checkmarks; CLI changed explicitly (own enum) + minimal `--raw` creation
9. Desktop grid: promote inline draft/edit row to full dialog via `Tune` action button; cancel restores inline state; Add still defaults to inline Text draft
10. Errors: existing ValidatingUseCase → ProblemDetails; conflict handling unchanged; restore/revert convert legacy `Kind=3` snapshots via shared composer
11. Tests: TDD parser/validator; emitter round-trip; migration equivalence + max-length row (Testcontainers); legacy-snapshot restore/revert; API integration; bUnit dialog + promote; E2E `RawHotstringFlowTests`
12. Out of scope: Raw in bulk Import (follow-up backlog), CLI Raw UX beyond `--raw` create, semantic AHK validation / full lexer

## Verification

- Spec + plan committed on `feature/raw-hotstring-kind`
- Spec content matches every item in the checklist above
