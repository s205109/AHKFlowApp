# 182 - NuGet audit fails restore on cryptography advisories

## Metadata

- **Epic**: Developer workflow
- **Type**: Bug
- **Interfaces**: none (package versions only)
- **Difficulty**: moderate
- **Stage**: 1-pickup

## Summary

Since 2026-10-13, restore fails in every checkout, `main` included. NuGet audit reports five new
advisories against `System.Security.Cryptography.Pkcs` and `System.Security.Cryptography.Xml`.
`TreatWarningsAsErrors` turns the warnings NU1902 and NU1903 into errors. So no project builds, no
test runs, and the Claude pre-commit format hook refuses every commit, because `dotnet format`
cannot restore.

## User story

As a contributor, I want restore to pass with NuGet audit still on, so that I can build, test, and
commit again.

## Acceptance criteria

- [ ] `dotnet restore AHKFlowApp.slnx` passes with NuGet audit on.
- [ ] `dotnet list AHKFlowApp.slnx package --vulnerable --include-transitive` reports no
      vulnerable package in any project.
- [ ] No `NoWarn`, `WarningsNotAsErrors`, or `NuGetAudit` setting in the repository silences NU1902
      or NU1903.
- [ ] `dotnet format AHKFlowApp.slnx --verify-no-changes` exits 0 on a clean tree, so the Claude
      pre-commit format hook lets commits through again.

## Out of scope

- Changing how NuGet audit or `TreatWarningsAsErrors` are configured.
- Packages other than these two, unless restore still names one after the fix.

## Notes / dependencies

- The advisories, all published on 2026-10-13: GHSA-846f-f764-76mx (high) and
  GHSA-2fmv-rv2c-59x7 (moderate) against `System.Security.Cryptography.Pkcs`, and
  GHSA-7hqp-7c5m-4vq6, GHSA-c399-9853-6jmj, and GHSA-r955-8q5j-3h83 (all high) against
  `System.Security.Cryptography.Xml`. Each names 10.0.13 as the first fixed 10.0 version. Whether
  10.0.13 is on nuget.org was not checked on 2026-10-14.
- The vulnerable versions restore resolved on 2026-10-14: Pkcs 9.0.4 through
  `AHKFlowApp.Application` and `AHKFlowApp.Infrastructure`, Pkcs 10.0.6 through `AHKFlowApp.API`,
  Pkcs 10.0.10 through `AHKFlowApp.TestUtilities` and `AHKFlowApp.Application.Tests`, and Xml
  10.0.10, which `Directory.Packages.props` pins.
- Precedent: commit `bd5140cc`, "Fixed vulnerable NuGet packages", pinned
  `System.Security.Cryptography.Xml` in `Directory.Packages.props` and referenced it from three
  test projects. Pkcs is only a transitive dependency today, so it needs the same treatment or
  central transitive pinning.
- Backlog 181 waits on this item. Its plan uses `-p:NuGetAudit=false` for local test runs only;
  its stage push needs this fix on `main`.
- Found by the backlog 181 planning session on 2026-10-14.
- Spec: none yet.
- Plan: none yet.
