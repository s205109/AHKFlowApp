# 143 - Non-serializable theory data collapses cases in Test Explorer

## Metadata

- **Epic**: Developer workflow
- **Type**: Chore
- **Interfaces**: none — test code only
- **Difficulty**: moderate
- **Stage**: 9-ship

## Summary

Four theories take a whole object as their theory argument. xUnit cannot serialize those
arguments, so all their cases share one test id. Visual Studio Test Explorer shows one row for
each of the four, a developer cannot re-run a single case, and every case name in the TRX is a
full record dump. Pass a fixture id instead of the object.

## User story

As a developer, I want each theory case to be its own row in Test Explorer, so that I can re-run
one failing case and read its name without wading through a record dump.

## Background

`LegacyHotkeyFixture` is a plain record (`tests/AHKFlowApp.TestUtilities/Fixtures/LegacyHotkeyFixtures.cs:14`, "public sealed record LegacyHotkeyFixture(").
It does not implement `IXunitSerializable`. `HotkeySnapshot` is the same kind of record (`src/Backend/AHKFlowApp.Application/DTOs/HistorySnapshots.cs:86`, "public sealed record HotkeySnapshot(").

xUnit writes the theory arguments into the test id. When the arguments do not serialize, every
case of that theory reports under one id. The cases still run, and a failure still reaches the
console and the TRX, so this is not a correctness defect. What is lost is the per-case row.

Four theory methods are affected. The four citations below record the tree as it stood when this
item was filed. The fix changed every one of those signatures, so each carries
`citation-check:ignore`.

- (`tests/AHKFlowApp.Application.Tests/Services/LegacyHotkeyDefinitionConverterTests.cs:13`, "public void ToTyped_LegacyPair_MatchesFixtureExpectation(LegacyHotkeyFixture f)") <!-- citation-check:ignore records the pre-fix tree; the parameter is now a string -->
- (`tests/AHKFlowApp.Application.Tests/Services/LegacyHotkeySnapshotConverterTests.cs:17`, "public void ToDefinition_LegacySnapshot_ConvertsViaSameRules(LegacyHotkeyFixture f)") <!-- citation-check:ignore records the pre-fix tree; the parameter is now a string -->
- (`tests/AHKFlowApp.Application.Tests/Services/LegacyHotkeySnapshotConverterTests.cs:37`, "public void ToDefinition_TypedSnapshot_PassesEveryKindThrough(HotkeySnapshot typed)") <!-- citation-check:ignore records the pre-fix tree; the parameter is now a HotkeyActionKind -->
- (`tests/AHKFlowApp.Application.Tests/Services/LegacyHotkeySnapshotConverterTests.cs:164`, "public void Serialize_TypedSnapshot_RoundTripsLosslessly(HotkeySnapshot typed)") <!-- citation-check:ignore records the pre-fix tree; the parameter is now a HotkeyActionKind -->

Measured on the TRX from the Fast run of 2026-08-29,
`TestResults/test-fast/Fast/AHKFlowApp.Application.Tests/AHKFlowApp.Application.Tests.trx`:

- 1749 result rows share 1059 distinct test ids, so 690 rows are folded away.
- The two fixture-driven theories contribute 340 rows each, the two snapshot theories 7 each.
  That is 694 rows under 4 ids, which is the whole 690.

The same run listed through discovery shows the effect directly. `dotnet vstest
AHKFlowApp.Application.Tests.dll --ListFullyQualifiedTests` returns 1025 names, one per test
method, with no theory expanded.

The fixture record already carries a name field
(`tests/AHKFlowApp.TestUtilities/Fixtures/LegacyHotkeyFixtures.cs:15`, "string Name,"), and the
fixture list is built once (`tests/AHKFlowApp.TestUtilities/Fixtures/LegacyHotkeyFixtures.cs:67`, "public static IReadOnlyList<LegacyHotkeyFixture> All { get; } = Build();").
Whether `Name` is unique across every generated fixture is not established and must be checked first. `Build()`
generates entries from key catalogs, so a collision is possible.

Prefer the id over `IXunitSerializable`. The interface needs hand-written `Serialize` and
`Deserialize` on the record, and it keeps the long display names.

xUnit ships analyzer rules for this case, xUnit1044 and xUnit1045. Neither is suppressed in this
repository, and the build passes with `TreatWarningsAsErrors`, so they run below warning level
today. Raising xUnit1045 to a warning would stop new cases appearing.

## Acceptance criteria

- [x] Every theory in `tests/AHKFlowApp.Application.Tests/Services/` takes only serializable
      arguments. No theory parameter is a `LegacyHotkeyFixture` or a `HotkeySnapshot`.
  - The two fixture theories take a `string` name. The two snapshot theories take a
    `HotkeyActionKind`. Three more theories outside `Services/` were re-keyed too — see Outcome.
- [x] `LegacyHotkeyFixtures` exposes a lookup from a stable id to a fixture, and a test asserts
      that the ids of `LegacyHotkeyFixtures.All` are unique.
  - `AllNames` and `ByName`, backed by an ordinal dictionary.
    `LegacyHotkeyFixturesTests.AllNames_AreUnique` guards it. The test was proved to fail: a
    duplicate name was injected on purpose and it failed naming the duplicate.
- [x] `dotnet vstest` discovery on `AHKFlowApp.Application.Tests.dll` lists one name per theory
      case for those four methods, not one name per method.
  - True, but **not with the command this item named**. `--ListFullyQualifiedTests` reports one
    fully-qualified method name per method and never expands theory data, for any theory. Measured
    with `--ListTests`, which reports display names: 1401 names on `main` against 2103 on the
    branch. `ToTyped_LegacyPair_MatchesFixtureExpectation` went from 1 name to 340.
- [x] A TRX from `pwsh ./scripts/test-fast.ps1 -Mode Fast` has as many distinct test ids as
      result rows for `AHKFlowApp.Application.Tests`.
  - 1749 result rows, 1749 distinct ids. The item measured 1749 rows under 1059 ids before.
- [x] The four theories assert the same things they assert today. The pass count for the project
      does not drop.
  - 1749 passed, the same total as before. Every assertion was kept; only the signature and the
    first line of each body changed.
- [x] xUnit1045 is set to `warning` in `.editorconfig`, and the build stays green.
  - Set, **and so is xUnit1044**, which is the rule that actually fires here. The two are the
    reverse of the way this item read them: xUnit1044 catches a type known not to serialize, which
    is what a sealed record is, and xUnit1045 catches one that might not, meaning an interface or
    an unsealed type. xUnit1045 alone would have changed nothing. Proved by mutation: a
    `TheoryData<LegacyHotkeyFixture>` added on purpose failed the build with
    `error xUnit1044`.

## Outcome

**Seven theories changed, not four.** The item's Out of scope section asked for the remaining
object-argument cases to be found and filed, and allowed fixing them "with saying so". This is the
saying so.

`AHKFlowApp.UI.Blazor.Tests` has none. A scan of every `[Theory]` in `tests/` found that all of
its theories already take strings, ints, bools, or enums. The scan also found that this repository
uses `TheoryData<>` for every theory data source, with no `ClassData` and no `MemberData` that
returns `IEnumerable<object[]>`, so xUnit1044 is a complete guard here rather than a partial one.

The three real ones were elsewhere, and all three are now keyed by `HotkeyActionKind`:

- `HotkeysEndpointsTests.KindPayloads` in `AHKFlowApp.API.Tests`
- `RestoreCommandTests.TypedActions` in `AHKFlowApp.Application.Tests/History/`
- `RevertCommandTests.TypedActionCases` in the same folder

The two in `History/` carry `[Trait("Category", "Integration")]`, which is the only reason the
Fast-run measurement in this item never saw them.

Fixing them was not optional. Every project builds with `TreatWarningsAsErrors`, so raising the
analyzer to `warning` and keeping the build green cannot both be true while a violation remains.
The alternative was three `#pragma` suppressions plus a follow-up item, which would have left the
same collapse alive in the Integration and API slices.

The Integration slice now reports result rows equal to distinct test ids in all four of its
projects: API 239, Application 354, CLI 25, Infrastructure 26, with zero failures.

## Out of scope
- Any change to what the four theories check, or to the fixture data itself.
- Making the Visual Studio count equal the `dotnet test` count for its own sake. The count is a
  symptom. The per-case row is the goal.

## Notes / dependencies

- Found on 2026-09-07 while explaining why Test Explorer showed 2934 tests and `dotnet test`
  showed 3642. The 708 gap is this collapse plus a little drift.
- The behaviour is documented by xUnit at https://xunit.net/docs/theory-data-stability-in-vs and
  in the rule pages for xUnit1044 and xUnit1045.
- Verified that no failure is hidden by the collapse. A scratch reproduction with four cases, the
  failing one in the middle, produced one test id, four result rows, and outcomes of one failed
  and three passed. The console reported the failure.
- Spec: none — the defect and its fix are both small and named above.
- Plan: `docs/superpowers/plans/2026-09-07-serializable-theory-ids-plan-143.md`
