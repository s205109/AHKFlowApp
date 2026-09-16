# Plan 146 progress

Plan: `docs/superpowers/plans/2026-09-13-test-runs-share-a-lane-pool-plan-146.md`

Stage: 4-execute. Starting commit: `108072baa5ff097c33cc1bc7d044134d24fd6ba7`.
Draft proof PR: https://github.com/s205109/AHKFlowApp/pull/415

| Task | Status | Deliverable | Evidence / remaining work |
|---|---|---|---|
| 1 Native locking proof | Complete | `61e60671`, recovery `5e57459a` | Windows 7/5.1, Docker Linux, and hosted Windows/Linux pass; observations below. |
| 2 Sizing extraction | Complete | `e27ae4ba` | Windows 7/5.1 and Docker Linux pass; exact rule and caller behavior retained. |
| 3 Pool and harness | Complete | e4c0cab1 | Windows and Linux: all 23 cases passed; independent source review approved. |
| 4 Advisory records | Complete | `707ac3e2`, fix `41b7b220` | Windows and Linux: all 34 cases passed; independent re-review approved all fixes. |
| 5 Suite admission | Complete | `1b57d01e`, test fix `369434c9` | Four requested groups pass; real two-checkout cap and four mutations proved. |
| 6 .NET reservations | Complete | `bb282e1c`, test fix `55926ca2` | Seven Windows groups pass; gated Fast and Coverage routes hold Half. |
| 7 Timing and soak | Complete | `72806457`, test fix `d966f0e7` | Whole timing and Half soak pass; handoff continuity mutation fails. |
| 8 Documentation | In progress | Pending | Describing the verified reservation contract and repairing owned citations. |

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

## Task 1 first hosted proof and recovery

Run: https://github.com/s205109/AHKFlowApp/actions/runs/34882631260
Tested commit: `569dbc6b115055cabcc9a5db035e577ed0be42be`.
Hosted Linux primitive: PASS, 3.9 seconds. The surrounding invariants job failed on two record checks.
Runner image: ubuntu-24.04 / ubuntu24, version 20260907.300.1.
Host: PowerShell 7.6.5, .NET 10.0.11, ext4.
All six process/same-process/runspace contention observations were System.IO.IOException, 11, 0x0000000B.
Missing parent: System.IO.DirectoryNotFoundException, -2147024893, 0x80070003.
Injected I/O: System.IO.IOException, -2146232800, 0x80131620.
Access denied: System.UnauthorizedAccessException, -2147024891, 0x80070005.
Explicit release, stdin EOF, and forced kill each reopened both files. Cleanup reaped all children and settled readers.
Windows and Codex parity jobs were skipped because repository invariants failed. Task 1 remains pending.

Recovery task: normalize this item's Plan bullet and preserve existing manifest citation positions.
BacklogPlanPointer rejected the existing suffix `. Eight tasks.` after the path.
CitationFreshness rejected two historical public citations because the inserted manifest row moved their targets.
The correction puts new manifest entries at the end and puts explanatory plan text in its own bullet.
Fresh BacklogPlanPointer run passed after correction. Full citation check is pending.

Recovery validation: BacklogPlanPointer and RepoInvariantsCiJob pass. The public citation checker passes.
Task 2 private citation repair passed both owned files with adoption checking from private base 45afd09c.
Private citation commit: 6df8a53. Existing manifest citation positions are preserved by appending new entries.
Recovery deliverable: `5e57459a` (Plan pointer and expected invariant set). Manifest placement correction accompanies Task 2 registration before the corrective proof push.

## Task 2 evidence

Deliverable: e27ae4ba. Private citation commit: 6df8a53.
Red: new extraction suite failed because the shared helper did not exist.
Green Windows runner results: SuiteWorkerCount 1.4s; CiPowerShellSuiteRunner 91.4s;
SuiteRunnerLinux 9.5s; CodexParityCiJob 0.8s. All passed.
RepoInvariantsCiJob passed after the Task 1 expected-list correction.
Windows PowerShell 5.1 direct loading and physical-core dispatch passed.
Docker Linux: PowerShell 7.6.6 / .NET 10.0.12; final SuiteWorkerCount suite passed.
The Linux run explicitly skips the Windows PowerShell 5.1-only check.

Review found slash-based detection incorrectly included macOS. The correction uses precise Linux detection and preserves unsupported-platform zero.
The new regression failed before correction and passed afterward. The final Linux rerun also passed.
The reviewer's scoped re-review was interrupted by an account usage limit.
Controller inspection confirmed the Windows-first branch, precise Linux branch, and final zero fallback.
This local adjudication closes the specific finding; final whole-branch review remains required.

Task 1 hosted Windows proof remains pending. No Task 3 admission implementation has started.

Corrective run: https://github.com/s205109/AHKFlowApp/actions/runs/34883904297
Tested commit: b4e93b2a9bebb2291aa34af77a9be9b2e980f360.
Repository invariants passed. Its primitive observations match the first hosted Linux table exactly.
Linux OS: Ubuntu 24.04.5 LTS; LocalApplicationData: /home/runner/.local/share; temporary filesystem: ext4.
Codex parity passed on the identical ubuntu-24.04 image version 20260907.300.1.
Both jobs use /usr/bin/pwsh and resolve the suite host to /opt/microsoft/powershell/7/pwsh.
The pinned image's software record lists PowerShell 7.6.5:
https://github.com/actions/runner-images/blob/ubuntu24/20260907.300/images/ubuntu/Ubuntu2404-Readme.md
Neither job installs or alters PowerShell. The matching immutable image and executable establish the same bundled runtime as the measured .NET 10.0.11 host.
The Codex parity selection remains focused on parity. No duplicate primitive invocation was added there.
Windows proof remains pending until its current suite job finishes and its observations are saved.

## Task 1 completed hosted proof

Corrective CI run 34883904297 passed every job at b4e93b2a9bebb2291aa34af77a9be9b2e980f360.
Windows primitive passed in 8.2 seconds. SuiteWorkerCount also passed in hosted Windows (2.8 seconds).
Windows image: win25-vs2026, version 20260907.229.1; OS: Microsoft Windows 10.0.26100; filesystem: NTFS.
PowerShell host: 7.6.5 / .NET 10.0.11.
Native legacy child: PowerShell 5.1.26100.33296 / .NET Framework 4.8.9337.0, same OS and filesystem.
Each Windows Lane and entry contention case returned System.IO.IOException, -2147024864, 0x80070020.
This includes separate-process and same-process cases on both hosts, and both runspace cases on PowerShell 7.
Missing parent on both hosts: System.IO.DirectoryNotFoundException, -2147024893, 0x80070003.
Generic injected I/O on both hosts: System.IO.IOException, -2146232800, 0x80131620.
Access denied on both hosts: System.UnauthorizedAccessException, -2147024891, 0x80070005.
Both hosts reopened both files after explicit release, stdin EOF, and forced kill.
Both hosts printed successful child reaping and reader settlement. The 5.1 run explicitly skipped the runspace case.

Task 1 is complete. Linux registration is now verified, not provisional.
Observed supported contention pairs: Windows IOException/0x80070020; Linux IOException/0x0000000B.
Unknown I/O values and missing-parent/access failures must remain errors.
Task 3 may now begin. No readiness, full local Gate, or resource-responsiveness claim is made.


## Task 3 verification

Deliverable: e4c0cab1. Windows: all 23 cases passed in 15.3 seconds.
Docker Linux: all 23 cases passed with the previously recorded SDK 10 image.
The always-successful-open mutation failed both real contention cases, as required.
Same-host runspace cancellation released entry and partial Lanes.
Windows PowerShell 5.1 loaded the production helper and returned proposal 6 and Half(5) = 3.
Independent source review approved Task 3 with no blocking findings.
The suite is registered for Windows and Linux with measured baseline 15.3 seconds.
Task 4 remains in progress. Final Gate and whole-branch review remain pending.

## Current Windows host refresh

The current host is PowerShell 7.6.6 on .NET 10.0.12 and Microsoft Windows 10.0.26200.
The Task 1 native primitive rerun passed under PowerShell 7 and Windows PowerShell 5.1.
It reproduced every recorded contention code and completed all cleanup checks.
The saved log is `task-1-current-windows.log` in this plan's ignored SDD workspace.

## Task 4 verification

Deliverable: `707ac3e2`; review fix: `41b7b220`.
The initial review found a missing Linux share-retry observation, a lost diagnostic after an output failure,
and unbounded cancellation cleanup in the new tests.
The fix adds a failing-first output retry regression and bounded asynchronous teardown.
Windows and Docker Linux then passed all 34 LanePool cases.
Windows PowerShell 5.1 loaded the production module and resolved the owner lifecycle command.
The complete Linux log includes entry, capacity, and share retry cases.
The scoped re-review marked all three findings addressed and found no new important breakage.
Task 5 may now integrate the runner. Final Gate and whole-branch review remain pending.

## Task 5 verification

Deliverable: `1b57d01e`; review fix: `369434c9`.
One runner with four Workers held exactly two Lanes in a capacity-two pool.
With Lane admission off, the same fixture reached a peak of four.
Two copied checkouts and two real runners shared one pool and reached a combined peak of two.
Both blocked Workers acknowledged real acquisition waits before the first runner released its Suites.
The unchanged cap proof rejected an acquisition-bypass mutation.
Null and cloned Worker run-state mutations also failed, as did silent sharing and early cleanup mutations.
The final Windows run passed 103 runner cases, 34 LanePool cases, 9 Linux-runner fixture cases,
and 5 wrapper cases. It includes registration failure, cancellation ordering, and bounded child reaping.
Independent re-review marked all four findings addressed and approved Task 5.
Task 6 may now reserve Half for .NET routes. Final Gate and Linux portable-suite runs remain pending.

## Task 6 verification

Deliverable: `bb282e1c`; review fix: `55926ca2`.
Fast, direct Coverage, and delegated Coverage each hold exactly two of four Lanes during gated work.
Nested wrappers preserve their marker and add no reservation. A real checkout-lock contender remains refused.
Two Fast calls in one surviving host each reserve Half and restore the exact marker between calls.
Cancellation after a real failed Lane open releases both checkout and Lane handles; a fresh reservation then succeeds.
The coverage-tooling filter names both new helpers, with thirteen exact entries and recursive graph checks.
Seven requested Windows suites passed 115 cases. Four cleanup mutations failed.
Review then found that recorded Coverage phases were checked without requiring the threshold phase.
The fix requires each phase, and deleting the threshold call now fails direct and delegated route tests.
CoverageRunnerProgress passed 15 cases and TestFastDotnetProgress passed 13 after the fix.
Independent re-review closed the finding. Full Gate and Linux portable-suite runs remain pending.

## Task 7 verification

Deliverable: `72806457`; review fix: `d966f0e7`.
Timing holds Whole across build, warm-up, counted calls, and its checkout-lock handoff.
Soak holds Half across build and all three repetitions. Nested sessions add no Lanes.
Forced contention starts no measured call before admission.
Build, invocation, and cancellation failures release records and handles in a surviving host.
The final Windows runs passed 34 MeasureTestModes cases and 34 LanePool cases.
Changing timing Whole to Half failed five cases.
Review found the first test did not observe continuity at the exact checkout handoff.
A new gate and competing Lane acquirer now cover that interval.
A temporary exit/re-enter mutation fails while the parent hands checkout to Fast.
Independent re-review closed the finding. Full Gate, portable Linux runs, and two-checkout measurements remain pending.
