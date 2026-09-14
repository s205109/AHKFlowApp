# Plan 146 progress

Plan: `docs/superpowers/plans/2026-09-13-test-runs-share-a-lane-pool-plan-146.md`

Stage: 4-execute. Starting commit: `108072baa5ff097c33cc1bc7d044134d24fd6ba7`.
Draft proof PR: https://github.com/s205109/AHKFlowApp/pull/415

| Task | Status | Deliverable | Evidence / remaining work |
|---|---|---|---|
| 1 Native locking proof | Hosted proof pending | `61e60671` | Windows 7/5.1 and Docker Linux pass; hosted platforms remain required. |
| 2 Sizing extraction | Pending | Pending | Independent of Task 1 under the revised plan. |
| 3 Pool and harness | Gated | Pending | Task 1 and Task 2 must pass first. |
| 4 Advisory records | Gated | Pending | Requires Task 3. |
| 5 Suite admission | Gated | Pending | Requires Task 4. |
| 6 .NET reservations | Gated | Pending | Requires pool lifecycle and wrapper proof. |
| 7 Timing and soak | Gated | Pending | Requires pool lifecycle. |
| 8 Documentation | Gated | Pending | Requires measured implementation contract. |

## Decisions

- The revised plan explicitly permits Task 2 before Task 1 passes. The older backlog dependency sentence is superseded.
- The existing worktree matches the plan branch. Its base is `main` at `7c41079d`, as recorded by the plan.
- Task 1's early proof push updates the existing draft PR. It does not authorize readiness or complete Execute.
- Admission correctness and machine responsiveness remain separate claims. User-observed responsiveness is still unverified.

## Platform preparation

The required Docker image was absent and has now been pulled.
Image: `mcr.microsoft.com/dotnet/sdk:10.0`.
Digest: `sha256:2fa828c68761b1b8c23d7662dc134421b9d3b59fe1425fdbc80804e390cdb24d`.
Initial host inspection: PowerShell `7.6.6`, runtime `.NET 10.0.12`, LocalApplicationData `/root/.local/share`.
The native `/tmp` filesystem is `overlay`. Lock fixtures must use that native filesystem.
These environment observations do not prove locking.

## Remaining verification

All implementation tests, hosted proof, full PowerShell suite set, five-step Gate, and two-checkout measurements remain open.

## Task 1 local proof

Command: `pwsh -NoProfile -File tests/LaneFileLockPrimitive.Tests.ps1`.
Result: PASS, exit 0; measured wall time 3.254 seconds (manifest baseline 3.3).
Windows host: PowerShell 7.6.5, .NET 10.0.11, Microsoft Windows 10.0.26200, NTFS.
Legacy child: PowerShell 5.1.26100.9444, .NET Framework 4.8.9345.0, same OS and filesystem.
LocalApplicationData: `C:\Users\btase\AppData\Local`.

Docker command: run the same suite from a read-only `/proof` mount in the SDK image above.
Result: PASS, exit 0; PowerShell 7.6.6, .NET 10.0.12, Ubuntu 24.04.5 LTS, native `/tmp` on overlay.
LocalApplicationData: `/root/.local/share`.
Linux registration is provisional until hosted proof passes. Removing it does not satisfy the gate.

| Native case | Windows 7 / 5.1 | Docker Linux |
|---|---|---|
| Child contention, Lane | System.IO.IOException, -2147024864, 0x80070020 | System.IO.IOException, 11, 0x0000000B |
| Child contention, entry | System.IO.IOException, -2147024864, 0x80070020 | System.IO.IOException, 11, 0x0000000B |
| Same-process contention, Lane | System.IO.IOException, -2147024864, 0x80070020 | System.IO.IOException, 11, 0x0000000B |
| Same-process contention, entry | System.IO.IOException, -2147024864, 0x80070020 | System.IO.IOException, 11, 0x0000000B |
| Other-runspace contention, Lane | System.IO.IOException, -2147024864, 0x80070020 (7 only) | System.IO.IOException, 11, 0x0000000B |
| Other-runspace contention, entry | System.IO.IOException, -2147024864, 0x80070020 (7 only) | System.IO.IOException, 11, 0x0000000B |
| Missing parent | System.IO.DirectoryNotFoundException, -2147024893, 0x80070003 | Same |
| Generic injected I/O | System.IO.IOException, -2146232800, 0x80131620 | Same |
| Directory opened as file | System.UnauthorizedAccessException, -2147024891, 0x80070005 | Same |
| Explicit holder release | Both files reopened successfully | Both files reopened successfully |
| Forced holder kill | Both files reopened successfully | Both files reopened successfully |

Initial Linux run failed its access-denied assertion because the test unwrapped native inner exceptions.
The observed chain was MethodInvocationException, UnauthorizedAccessException (0x80070005), IOException (13).
The correction unwraps PowerShell invocation wrappers only. The complete Linux rerun passed.
This preserves the API exception rather than conflating it with a native inner error.

Initial Release build passed: zero warnings, zero errors, elapsed 38.23 seconds.
Hosted observations, runner image versions, tested commit, and run URL remain pending.

Task 1 review fixes: stdin EOF now releases both handles. The new regression failed before the fix and passed afterward.
Cleanup now fails visibly if a child cannot be terminated/reaped or its readers cannot settle.
The final Windows rerun passed in 3.684 seconds; manifest baseline updated to 3.7 seconds.
The final Docker rerun passed, including EOF and all-children-reaped-readers-settled outcomes.
Focused re-review approved both fixes. Hosted proof is still pending.
