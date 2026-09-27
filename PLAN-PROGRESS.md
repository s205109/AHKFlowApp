# Progress — backlog 160, one home for emitted runtime helpers

Plan: `docs/superpowers/plans/2026-09-26-one-home-for-emitted-runtime-helpers-plan-160.md`

Base revision: `362d7ce`.

One line per finished task, written after its deliverable commit.

## Baseline

Recorded in the plan on 2026-09-26, in this worktree at `3392cb2`:

```
git diff --quiet 362d7ce -- src tests && echo "src+tests unchanged since 362d7ce"
src+tests unchanged since 362d7ce
```

```
dotnet test tests/AHKFlowApp.Application.Tests/AHKFlowApp.Application.Tests.csproj --configuration Release --filter "FullyQualifiedName~AhkScriptGeneratorTests|FullyQualifiedName~GetHotstringPreviewQueryHandlerTests|FullyQualifiedName~GetHotkeyPreviewQueryTests|FullyQualifiedName~AhkHotstringRoundTripTests"
Passed!  - Failed:     0, Passed:   116, Skipped:     0, Total:   116, Duration: 275 ms - AHKFlowApp.Application.Tests.dll (net10.0)
```

Transient byte test, expected SHA-256
`D9ADCC9FF2EF1DC840EFE66D9745F8A9CBF45D649E4436D2E2BFED87FEF0DB98`.

## Tasks

- [x] Task 1 — `-`. Byte baseline in place. On unchanged code (`src+tests unchanged since
      362d7ce` printed again) the byte-baseline assertion passed:
      `Passed!  - Failed:     0, Passed:     1, Skipped:     0, Total:     1, Duration: 123 ms`.
      The session started a Docker daemon (`dockerd`) in the container, so Task 3 runs the Docker
      checks itself.
- [x] Task 2 — `de52b82`. `RuntimeHelpers.cs` and `DefinitionWrapping.cs` (both CRLF) own the
      helper, the helper decision, the Description lines, and the `#HotIf` wrapping. The
      Application build had 0 warnings, and the solution build had 0 warnings. Tests:
      `Passed!  - Failed:     0, Passed:   117, Skipped:     0, Total:   117, Duration: 248 ms`
      (116 baseline plus the byte test, whose byte-baseline assertion passed). The three
      acceptance searches printed nothing.

      **Not in the plan: stale citations.** The move broke six filing-time evidence citations in
      the backlog item, which `check-citation-freshness.ps1` failed. Each now carries
      `citation-check:ignore` with the reason, and the repository check passes again. The plan
      itself cites the base tree in 31 places, and those now fail the pre-push plan check. See
      the end of this file.

      **Not in the plan: the stage field.** The item still read `3-plan`. `867e5b3` stamps
      `4-execute` by hand, because `take-stage-transition.ps1` needs `gh`.
- [x] Task 3 — `315a615`. The 11-row parity theory and the one comment line in
      `ListHotstringsQuery.cs`. The byte test passed one last time
      (`Passed!  - Failed:     0, Passed:     1, Skipped:     0, Total:     1, Duration: 104 ms`),
      then it was deleted. The committed `tests/` diff holds the theory and the one comment at
      `GetHotkeyPreviewQueryTests.cs:101`, and the row count printed `11`. The Fast slice passed:
      Application 1749, CLI 185, UI.Blazor 960, Domain 44, TestUtilities 14, 0 failed.

      Docker checks, run by this session against the committed file. The session started
      `dockerd` in the container, so no checkpoint push was needed.

      - `main`'s copy of the class: `Passed!  - Failed:     0, Passed:    27, Skipped:     0, Total:    27`
      - Before the mutation: `Passed!  - Failed:     0, Passed:    38, Skipped:     0, Total:    38, Duration: 2 s`
      - Mutation (`>=` to `>`), theory alone: `Failed!  - Failed:     3, Passed:     8, Skipped:     0, Total:    11`.
        The three failing cases, as predicted:
        `kind: Text, delivery: Auto, asciiChars: 200, supplementaryChars: 0, trailingSpaces: 0`,
        `kind: Text, delivery: Auto, asciiChars: 199, supplementaryChars: 0, trailingSpaces: 1`,
        `kind: Text, delivery: Auto, asciiChars: 0, supplementaryChars: 100, trailingSpaces: 0`.
      - After `git checkout --` restored the file (`git status --short` printed nothing):
        `Passed!  - Failed:     0, Passed:    38, Skipped:     0, Total:    38, Duration: 2 s`

## Resolved: the plan's own citations

The plan cites the base tree `362d7ce` on purpose ("Line numbers in the tasks are those of the
base commit"). After Task 2, those citations failed tiers 1 and 2 of
`check-citation-freshness.ps1`, which the pre-push hook runs on this branch's plan. On
2026-09-27, against `a49ae75`, the check reported 38 problems.

The human decided on 2026-09-27: freeze the plan now, before Ship. Plans repository commit
`68c7745` adds `citation-check:ignore-file` and a comment saying why. The same check then
reported no problem. Stage 9 still confirms the freeze.

## Simplify

Verdict: simplification applied, in `1ae3f1b`. `/simplify` ran four read-only review agents:
reuse, simplification, efficiency, and altitude.

- Fixed: both preview handlers repeated the same order of helpers, wrapping, and join.
  `DefinitionWrapping.PreviewSnippet` now owns that order, and each handler makes one call.
  Three of the four agents found this.
- Fixed: one 153-character line in the `EmitContextGroups` XML summary is wrapped again.
- Skipped: rewording the comment in `ListHotstringsQuery.cs` that names the parity test.
  Grilling Q8 settled that the line names the test.
- Skipped: efficiency. The agent found no real waste.

Evidence: the byte test hash was still `D9ADCC9F…`, and 117 of 117 tests passed. The build had
0 warnings. `dotnet format --verify-no-changes` was clean on the four edited files. The three
acceptance searches printed nothing.

The commit was made while the item still read `4-execute`. The transition to `5-simplify`
(`38ac944`) came after it.

## Verify

Verification artifact: exemption 3 of AGENTS.md, pure refactor with named coverage. Fresh pass
output at `96c5310`, 2026-09-27:

- Fast, the four covering classes: `Passed!  - Failed:     0, Passed:   116, Skipped:     0, Total:   116`
- Integration, Application (`AhkScriptGeneratorIntegrationTests`, `RawContinuationRoundTripTests`,
  `ListHotstringsQueryHandlerTests` with the 11 parity rows):
  `Passed!  - Failed:     0, Passed:    41, Skipped:     0, Total:    41`
- Integration, API (`HotstringPreviewEndpointsTests`, `HotkeyPreviewEndpointsTests`):
  `Passed!  - Failed:     0, Passed:    19, Skipped:     0, Total:    19`
- Byte test after Simplify: hash still `D9ADCC9F…`, 117 of 117 with the Fast classes.

The Gate, run locally in the cloud container:

1. Build: `0 Warning(s)`, `0 Error(s)`.
2. Format: `dotnet format AHKFlowApp.slnx --verify-no-changes` exit 0.
3. PowerShell suites: 54 of 56 passed on the first run.
   - `BacklogStaleOpen.Tests.ps1` failed because the clone was shallow. After
     `git fetch --unshallow`, the suite passed on its own.
   - `WorktreeRemovalLog.Tests.ps1` failed: "Four writers of 25 lines must produce 100 lines,
     got 97". The same suite fails the same way on the base `362d7ce` in this container, and this
     branch changes no script and no suite. It is not this branch's failure.
4. Coverage: every project except E2E passed under coverage. API 239, Application 2114, CLI 210,
   Domain 44, Infrastructure 26, TestUtilities 14, UI.Blazor 960, all with 0 failed.
   - The E2E fixture could not install its browser here: `Playwright browser installation failed
     (exit 1)`, 66 of 79 failed. `Microsoft.Playwright` 1.59.0 asks for a newer Chromium than the
     container has, and the container's rules forbid `playwright install`.
   - The first coverage run failed earlier, because `reportgenerator` was missing. It was
     installed with `dotnet tool install -g dotnet-reportgenerator-globaltool`.
   - The run stopped at the failed E2E project, so the local coverage thresholds were not checked.
5. `git diff --check origin/main...HEAD`: exit 0.

CI on the same head, `96c5310`: all 7 checks passed. `build-test` runs the E2E tests with
coverage, every other test with coverage, and the per-assembly coverage thresholds.
`powershell-suites` runs the suites on Linux, including `WorktreeRemovalLog.Tests.ps1`.

Verdict: the artifact is green. Locally, Gate steps 1, 2, and 5 are green. Steps 3 and 4 are green
except for the parts this container cannot run, and CI ran those parts green on the same commit.

The human accepted CI's green run on `96c5310` for the parts of Gate steps 3 and 4 that this
container cannot run, on 2026-09-27. Verify exits on its success edge.

## Review round 1 (2026-09-27)

The `code-review` skill reviewed PR #423 at high effort and reported 9 findings. `gh` is not in the
container, so the skill did not post them. The human chose the outcomes, and one summary comment on
the PR records them.

Recovery tasks. Each needs a code or record change, so Review takes the failure edge to Execute:

- [ ] R1 (finding 1): add a lasting test for the preview order. The byte test was transient, and no
      committed test combines ClipboardPaste with a Window context and a Description. Assert that
      the snippet is the helper, then the `#HotIf` open line, then the comment, then the
      definition, then the close line.
- [ ] R2 (finding 3): `HeaderPresetCatalog.cs` still cites `AhkScriptGenerator.cs:93-96` for the
      bare `#HotIf` close. Point it at `DefinitionWrapping` instead.
- [ ] R3 (finding 2): the `NeededBy` summary says it returns every helper the definitions call. It
      only sees definitions the app emits, and it does not read a Raw definition's text. Say so.
- [ ] R4 (finding 9): criterion 4's evidence in the backlog item points at `PLAN-PROGRESS.md`, which
      Ship deletes. Write the three failing case names into the item instead.
- [ ] R5 (finding 6): `RuntimeHelpers.cs` holds the helper name twice. Build the helper text from
      `ClipboardPasteName` in one constant interpolated raw string. The byte test must keep its hash.
- [ ] R6 (finding 7): `PreviewSnippet` takes three string parameters next to each other. Use named
      arguments at the two call sites, so a swap cannot compile silently.

Declined, with the reason in the PR comment:

- Finding 4: `EmitContextGroups` writes only the first global group. That code exists unchanged on
  `main`, and the validators keep ContextMatchType and ContextValue both set or both null.
- Finding 5: `InWindowContext` uses `value!`. The same null-forgiving use exists on `main`, under the
  same validator rule.
- Finding 8: the helper's CRLF line breaks. Grilling Q10 settled that a follow-up item handles them
  after Ship, because fixing them changes the output.

## Failure edge to 4-execute (2026-09-27)

**Red evidence:**

```
code-review (high) on PR #423: 9 findings; 6 need code or record changes (no preview-order test; stale HeaderPresetCatalog comment; NeededBy summary overclaims; item evidence points at PLAN-PROGRESS.md; helper name held twice; loose PreviewSnippet string parameters).
```

**Recovery task:** R1 to R6 under 'Review round 1' in PLAN-PROGRESS.md

