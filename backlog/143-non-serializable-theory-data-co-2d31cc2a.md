# 143 - Non-serializable theory data collapses cases in Test Explorer

## Metadata

- **Epic**: Developer workflow
- **Type**: Chore
- **Interfaces**: none — test code only
- **Difficulty**: moderate
- **Stage**: 0-intake

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

Four theory methods are affected:

- (`tests/AHKFlowApp.Application.Tests/Services/LegacyHotkeyDefinitionConverterTests.cs:13`, "public void ToTyped_LegacyPair_MatchesFixtureExpectation(LegacyHotkeyFixture f)")
- (`tests/AHKFlowApp.Application.Tests/Services/LegacyHotkeySnapshotConverterTests.cs:17`, "public void ToDefinition_LegacySnapshot_ConvertsViaSameRules(LegacyHotkeyFixture f)")
- (`tests/AHKFlowApp.Application.Tests/Services/LegacyHotkeySnapshotConverterTests.cs:37`, "public void ToDefinition_TypedSnapshot_PassesEveryKindThrough(HotkeySnapshot typed)")
- (`tests/AHKFlowApp.Application.Tests/Services/LegacyHotkeySnapshotConverterTests.cs:164`, "public void Serialize_TypedSnapshot_RoundTripsLosslessly(HotkeySnapshot typed)")

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

- [ ] Every theory in `tests/AHKFlowApp.Application.Tests/Services/` takes only serializable
      arguments. No theory parameter is a `LegacyHotkeyFixture` or a `HotkeySnapshot`.
- [ ] `LegacyHotkeyFixtures` exposes a lookup from a stable id to a fixture, and a test asserts
      that the ids of `LegacyHotkeyFixtures.All` are unique.
- [ ] `dotnet vstest` discovery on `AHKFlowApp.Application.Tests.dll` lists one name per theory
      case for those four methods, not one name per method.
- [ ] A TRX from `pwsh ./scripts/test-fast.ps1 -Mode Fast` has as many distinct test ids as
      result rows for `AHKFlowApp.Application.Tests`.
- [ ] The four theories assert the same things they assert today. The pass count for the project
      does not drop.
- [ ] xUnit1045 is set to `warning` in `.editorconfig`, and the build stays green.

## Out of scope

- The two object-argument cases in `AHKFlowApp.UI.Blazor.Tests`. Check for them and file what you
  find; do not fix them here without saying so.
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
- Plan: none — filed at intake. A plan is written when somebody picks the item up.
