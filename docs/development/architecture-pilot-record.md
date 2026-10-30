# Architecture pilot record (backlog 193)

This record holds the measures of the architecture pilot on the Lane pool,
`scripts/test-lanes.common.ps1`. The design is
`docs/superpowers/specs/2026-10-29-architecture-pilot-on-one-tested-module-design-193.md`, and the
plan is `docs/superpowers/plans/2026-10-29-architecture-pilot-on-one-tested-module-plan-193.md`.

The record stands alone. It copies each defect's sentence and patches from
`docs/development/architecture-pilot-inputs.json`, so it stays readable after a revert removes that
file.

## What was measured

- **Before commit**: `e98bfb465b66eaf5689c378de0cd280dac2c525a`. It holds the case start lines
  and the two .NET failure rows, and no refactor.
- **After commit**: `8b921bee0e87214d29d2ba14e986ac6d58120d50`. It holds the refactor, the check
  and the timing mode.
- **Measurement script**: `scripts/measure-architecture-pilot.ps1`, committed in `0b86d4ae`. Its
  own Suite is `tests/MeasureArchitecturePilot.Tests.ps1`.
- Each side ran from its own local clone under `.superpowers\193-pilot\`, never from the
  worktree. Each Suite ran in its own `pwsh` process inside a Windows job object, three Suites at
  a time. Each Suite ran as a Nested run with a private temporary Lane pool.

## The before record

### Time budgets

A SuiteSet with no patch ran on the before clone on 2026-10-30. A budget stands when the Suite took
at most 1.3 times it. Every budget stands, so no budget changed.

| Suite | Budget (s) | Took (s) | Ratio |
|---|---|---|---|
| CiPowerShellSuiteRunner.Tests.ps1 | 130.4 | 101.9 | 0.78 |
| CoverageRunnerProgress.Tests.ps1 | 56.9 | 52.5 | 0.92 |
| CoverageSliceSkip.Tests.ps1 | 26.3 | 20.1 | 0.76 |
| GateEvidence.Tests.ps1 | 33.8 | 27.9 | 0.83 |
| MeasureTestModes.Tests.ps1 | 68.9 | 62.4 | 0.91 |
| TestFastDotnetProgress.Tests.ps1 | 29.0 | 27.4 | 0.95 |
| TestFastPowerShellMode.Tests.ps1 | 27.3 | 29.8 | 1.09 |
| LaneFileLockPrimitive.Tests.ps1 | 7.0 | 5.2 | 0.74 |
| LanePool.Tests.ps1 | 27.7 | 23.4 | 0.84 |

### Test count

A case is Lane-related when it asserts a Lane behaviour of the module, of a caller, or of a Lane
fixture. A case that only sets a Lane variable, so that its child never reaches the real pool, is
an isolation case and is not counted. Each data row counts as one case. Every name below is a
PASS line of the before attempt's clean opening control.

One case needed a judgement. `Lane missing Worker results cannot produce a passing summary` in
`CiPowerShellSuiteRunner.Tests.ps1` sets the Lane variables only to isolate the pool. It asserts
only the run summary, so it is an isolation case.

`LaneFileLockPrimitive.Tests.ps1` prints 18 PASS lines. Its case
`Windows PowerShell 5.1 repeats native cases` runs 8 of its cases again in a child, so those 8
lines are part of that one case. The Suite counts as 10 cases.

**CiPowerShellSuiteRunner.Tests.ps1** (caller Suite, 11 cases)

- caller: Lane one runner admits exactly two of four Workers
- caller: Lane two checkout runners enforce one combined cap
- caller: Lane exclusive Suites acquire One and release it before the next Suite
- caller: Lane invalid opt-out fails before any Suite starts
- caller: Lane nested and off preserve incoming marker and never open pool files
- caller: Lane owner hardware query is once with adaptive sizing or explicit Workers
- caller: Lane acquisition failures produce named failures in exclusive and parallel execution
- caller: Lane acquisition uses changed capacity and excludes admission wait from Suite timing
- caller: Lane stopped runner settles children before unregistering and restores its marker
- caller: Lane registration failure returns nonzero and restores the owner marker
- caller: In-process calls isolate job summaries and restore environment after failure

**TestFastPowerShellMode.Tests.ps1** (caller Suite, 2 cases)

- caller: PowerShell wrapper delegates per-Suite admission and preserves an existing holder
- caller: PowerShell wrapper forwards all Lane settings and restores fixture environment

**TestFastDotnetProgress.Tests.ps1** (caller Suite, 5 cases)

- caller: Fast Lane route: owner
- caller: Fast Lane route: nested
- caller: Fast Lane route: repeat
- caller: Fast Lane route: failure
- caller: Cancellation releases Lane and checkout ownership in a surviving host

**CoverageRunnerProgress.Tests.ps1** (caller Suite, 6 cases)

- caller: Coverage Lane route: direct nested=False
- caller: Coverage Lane route: direct nested=True
- caller: Coverage Lane route: delegated nested=False
- caller: Coverage Lane route: delegated nested=True
- caller: Coverage Lane route: direct failure
- caller: Cancellation releases Lane and checkout ownership in a surviving host

**CoverageSliceSkip.Tests.ps1** (caller Suite, 1 cases)

- caller: Coverage wrapper leaves admission and marker ownership to its delegate

**MeasureTestModes.Tests.ps1** (caller Suite, 10 cases)

- caller: Timing waits before work and holds its share across every call
- caller: Soak waits before work and holds its share across every call
- caller: Whole blocks a competing acquirer through the parent checkout handoff
- caller: Nested harness preserves its marker without adding Lanes (soak=False)
- caller: Nested harness preserves its marker without adding Lanes (soak=True)
- caller: Same-host fail-build restores its marker and releases its Lanes and checkout
- caller: Same-host fail-fast restores its marker and releases its Lanes and checkout
- caller: Same-host fail-run.txt restores its marker and releases its Lanes and checkout
- caller: Same-host none restores its marker and releases its Lanes and checkout
- caller: Cancelled admission cleans up in a surviving runspace before any work starts

**GateEvidence.Tests.ps1** (caller Suite, 0 cases)

- none: its four Lane cases only isolate the pool (isolation cases)

**LanePool.Tests.ps1** (not a caller Suite, 34 cases)

- Role precedence and validation
- Ownership restores the prior marker
- Proposal and every share are stable
- Entry contention blocks until an acknowledged real-open failure clears
- Classifier accepts only the measured native code
- Missing parent throws and genuine contention returns null
- Empty and occupied pools keep stable capacity
- Partial acquisition failure releases entry and lanes
- Half shares compose at six and wait at odd capacities
- Stopping a runspace releases its partial share in the same host
- Hosted proposal avoids hardware discovery and local proposal queries once
- malformed capacity releases entry before retry and resizes only when empty
- missing capacity releases entry before retry and resizes only when empty
- unreadable capacity releases entry before retry and resizes only when empty
- Capacity 1 blocks One with proposal 1 until release
- Capacity 6 blocks Whole with proposal 2 until release
- Capacity 2 blocks One with proposal 6 until release
- One proposing two joins an occupied capacity six without resizing
- Killing a partial collector releases entry and its Lanes
- An early assertion still reaps a gated child and removes its pool
- Access failures throw without being classified as contention
- Interval Suite publishes complete monotonic endpoints and waits for release
- Always-successful open mutation fails the actual contention cases
- Advisory records announce peers once and ignore incomplete or stale files
- A failed sharing write retries on the next wait
- Concurrent Workers share one diagnostic decision
- Registration publication failure releases its record handle
- Owner lifecycle restores normal failed and nested marker state
- A killed advisory owner is no longer named
- A late peer is announced during entry retry before its Lane is released
- A late peer is announced during capacity retry before its Lane is released
- A late peer is announced during share retry before its Lane is released
- Stopped owner entry restores its marker and acquires again in the surviving runspace
- Unreadable advisory records cannot abort a valid reservation

**LaneFileLockPrimitive.Tests.ps1** (not a caller Suite, 10 cases)

- Another process cannot open a held Lane or entry lock
- Explicit release frees both files
- Holder stdin EOF releases both files
- A second handle in the same process is refused
- Another runspace is refused
- Killing a holder frees both files
- Missing parent differs from contention
- Generic injected IOException differs from contention
- Access denied differs from contention
- Windows PowerShell 5.1 repeats native cases

Caller count: 35. Total count: 79.

### Defects and before outcomes

The before attempt ran on 2026-10-30 at the before commit. Its opening control and its closing
control were both clean, and the closing control printed the same PASS names. So the attempt
status is `clean`, and every defect result counts.

An independent sub-agent gave each outcome by the rules of spec section 5.4. It did not write the
patches. Its reason sentences are copied here unchanged. In a patch, `\r\n` is a CRLF line end,
and an empty `replace` removes the text.

Before side: 12 Caught, 0 Missed, 0 Invalid, 0 Inconclusive.

#### M1 (module)

Sentence: A run rewrites capacity.txt while another run holds a Lane.

Before outcome: **Caught**. LanePool cases fail because an occupied pool's capacity.txt changed ("Occupied pool must retain two", "Occupied capacity changed", "Occupied six must remain six", the resize-only-when-empty retries never happen), and the CI changed-capacity case got the wrong capacity; other failures (admission caps, Coverage/Fast/Measure Lane counts) follow from the same rewrite and are not counted.

Failing cases that show the behaviour:

- `LanePool.Tests.ps1`: Empty and occupied pools keep stable capacity — "Occupied pool must retain two. (expected '2', got '6')"
- `LanePool.Tests.ps1`: malformed capacity releases entry before retry and resizes only when empty — "Timed out waiting for completed Lane signal 'C:\Users\btase\AppData\Local\Temp\p193-0c79a816\6\tmp\ahkflow-lane-pool-2a5900ad862949b0b9e4205be0c40742\capacity-wait'."
- `LanePool.Tests.ps1`: missing capacity releases entry before retry and resizes only when empty — "Timed out waiting for completed Lane signal 'C:\Users\btase\AppData\Local\Temp\p193-0c79a816\6\tmp\ahkflow-lane-pool-10a3960e46f94dd7be4a57fd1fd4560b\capacity-wait'."
- `LanePool.Tests.ps1`: unreadable capacity releases entry before retry and resizes only when empty — "Lane child exited before publishing 'C:\Users\btase\AppData\Local\Temp\p193-0c79a816\6\tmp\ahkflow-lane-pool-d2793e5b7b6841cd976035bbe49d501b\capacity-wait'."
- `LanePool.Tests.ps1`: Capacity 6 blocks Whole with proposal 2 until release — "Occupied capacity changed. (expected '6', got '2')"
- `LanePool.Tests.ps1`: Capacity 2 blocks One with proposal 6 until release — "Reservation must wait for a complete share."
- `LanePool.Tests.ps1`: One proposing two joins an occupied capacity six without resizing — "Occupied six must remain six. (expected '6', got '2')"
- `CiPowerShellSuiteRunner.Tests.ps1`: Lane acquisition uses changed capacity and excludes admission wait from Suite timing — "Handle must use the capacity recorded after startup."

Before patch:

```text
file:    scripts/test-lanes.common.ps1
find:        if (-not $held) {
replace:     if ($true) {
```

#### M2 (module)

Sentence: A Half share rounds down, so capacity 3 gives one Lane and capacity 1 gives none.

Before outcome: **Caught**. Both LanePool share cases fail because Half of capacity 1 gave 0 Lanes instead of 1, which is the rounding-down behaviour in the sentence.

Failing cases that show the behaviour:

- `LanePool.Tests.ps1`: Proposal and every share are stable — "Half differed. (expected '1', got '0')"
- `LanePool.Tests.ps1`: Half shares compose at six and wait at odd capacities — "Odd capacity 1 must expose one half. (expected '1', got '0')"

Before patch:

```text
file:    scripts/test-lanes.common.ps1
find:    [Math]::Ceiling($Capacity / 2.0)
replace: [Math]::Floor($Capacity / 2.0)
```

#### M3 (module)

Sentence: A run that starts while the ownership marker is set acts as an owner and takes Lanes.

Before outcome: **Caught**. LanePool 'Role precedence and validation' reports "A holder must select nested ... got 'owner'", the LanePool timeout names the hung case 'Owner lifecycle restores normal failed and nested marker state' (its nested Whole take waits as an owner), and nested routes in CI, Coverage, Measure, TestFast and the PowerShell wrapper take extra Lanes; the CI hardware-query failure is a side effect of the owner path and is not counted.

Failing cases that show the behaviour:

- `LanePool.Tests.ps1`: Role precedence and validation — "A holder must select nested. (expected 'nested', got 'owner')"
- `LanePool.Tests.ps1`: Owner lifecycle restores normal failed and nested marker state — "hung: START with no result"
- `CiPowerShellSuiteRunner.Tests.ps1`: Lane nested and off preserve incoming marker and never open pool files — "Running 1 PowerShell suite(s) from C:\Users\btase\AppData\Local\Temp\p193-ff68a11e\1\tmp\ahkflow-suiterepo-18dc1021e320495489817be720aa52d7\tests"
- `CoverageRunnerProgress.Tests.ps1`: Coverage Lane route: direct nested=True — "Expected exactly two of four Lanes during run-coverage.ps1 call 1."
- `CoverageRunnerProgress.Tests.ps1`: Coverage Lane route: delegated nested=True — "Expected exactly two of four Lanes during test-fast.ps1 call 1."
- `MeasureTestModes.Tests.ps1`: Nested harness preserves its marker without adding Lanes (soak=False) — "Timed out waiting for completed Lane signal 'C:\Users\btase\AppData\Local\Temp\p193-ff68a11e\2\tmp\measure-test-modes-e882bf303d6d4432b310cbc63f4ee4a1\stub\retry'."
- `MeasureTestModes.Tests.ps1`: Nested harness preserves its marker without adding Lanes (soak=True) — "Nested reservation changed: build held=4 holder=23876"
- `TestFastDotnetProgress.Tests.ps1`: Fast Lane route: nested — "Expected exactly two of four Lanes during test-fast.ps1 call 1."
- `TestFastPowerShellMode.Tests.ps1`: PowerShell wrapper delegates per-Suite admission and preserves an existing holder — "The wrapper must add no Half reservation."
- `TestFastPowerShellMode.Tests.ps1`: PowerShell wrapper forwards all Lane settings and restores fixture environment — "Missing nested status. Gate evidence: on"

Before patch:

```text
file:    scripts/test-lanes.common.ps1
find:    { return 'nested' }
replace: { return 'owner' }
```

#### M4 (module)

Sentence: AHKFLOW_TEST_LANES=off is ignored, so the run acts as an owner and takes Lanes.

Before outcome: **Caught**. LanePool reports "Opt-out must win ... got 'owner'", the CI off case opened the pool ("Unexpected pool open" in the log), and the PowerShell wrapper reports "Missing off status".

Failing cases that show the behaviour:

- `LanePool.Tests.ps1`: Role precedence and validation — "Opt-out must win. (expected 'off', got 'owner')"
- `LanePool.Tests.ps1`: Owner lifecycle restores normal failed and nested marker state — "Opt-out must take precedence. (expected 'off', got 'owner')"
- `CiPowerShellSuiteRunner.Tests.ps1`: Lane nested and off preserve incoming marker and never open pool files — "Running 1 PowerShell suite(s) from C:\Users\btase\AppData\Local\Temp\p193-5a11de8c\1\tmp\ahkflow-suiterepo-25eb35dfa4cc490ca07b1026b47e7ee0\tests"
- `TestFastPowerShellMode.Tests.ps1`: PowerShell wrapper forwards all Lane settings and restores fixture environment — "Missing off status. Gate evidence: on"

Before patch:

```text
file:    scripts/test-lanes.common.ps1
find:    -ieq 'off') { return 'off' }
replace: -ieq 'off') { return 'owner' }
```

#### M5 (module)

Sentence: A take that fails part-way keeps the Lanes it already opened.

Before outcome: **Caught**. Every failure is a partial or cancelled take whose lane-0.lock is still held by the process, which shows the Lanes opened before the failure were kept; LanePool 'Partial acquisition failure releases entry and lanes' passed, so the catch rests on the stop and cancellation paths.

Failing cases that show the behaviour:

- `LanePool.Tests.ps1`: Stopping a runspace releases its partial share in the same host — "The process cannot access the file 'C:\Users\btase\AppData\Local\Temp\p193-39a0d2d9\6\tmp\ahkflow-lane-pool-681e8e471e174eb78b4ba0af851dfcf1\lane-0.lock' because it is being used by another process."
- `LanePool.Tests.ps1`: Stopped owner entry restores its marker and acquires again in the surviving runspace — "The process cannot access the file 'C:\Users\btase\AppData\Local\Temp\p193-39a0d2d9\6\tmp\ahkflow-lane-pool-f7709d0ccf5f43e4ad13fa92c54840ed\lane-0.lock' because it is being used by another process."
- `CoverageRunnerProgress.Tests.ps1`: Cancellation releases Lane and checkout ownership in a surviving host — "The process cannot access the file 'C:\Users\btase\AppData\Local\Temp\p193-39a0d2d9\3\tmp\ahkflow-lane-pool-8ec5df1d40974171a67ea10028b8c24c\lane-0.lock' because it is being used by another process."
- `MeasureTestModes.Tests.ps1`: Cancelled admission cleans up in a surviving runspace before any work starts — "The process cannot access the file 'C:\Users\btase\AppData\Local\Temp\p193-39a0d2d9\2\tmp\ahkflow-lane-pool-9ce4ed2c526243fe9a9cf82ff69147bc\lane-0.lock' because it is being used by another process."
- `TestFastDotnetProgress.Tests.ps1`: Cancellation releases Lane and checkout ownership in a surviving host — "The process cannot access the file 'C:\Users\btase\AppData\Local\Temp\p193-39a0d2d9\5\tmp\ahkflow-lane-pool-d647de84413845ce94346ed5da12c984\lane-0.lock' because it is being used by another process."

Before patch:

```text
file:    scripts/test-lanes.common.ps1
find:            if (-not $completed) { foreach ($lane in $lanes) { $lane.Dispose() } }\r\n
replace: 
```

#### M6 (module)

Sentence: A run end leaves its record and lock file in runs/.

Before outcome: **Caught**. LanePool, CI and MeasureTestModes cases fail because run records and lock files stay in runs/ after a normal end or a cancellation ("must remove records", "must unregister", "must remove its advisory record").

Failing cases that show the behaviour:

- `LanePool.Tests.ps1`: Registration publication failure releases its record handle — "Failed publication must remove its files. (expected '0', got '1')"
- `LanePool.Tests.ps1`: Owner lifecycle restores normal failed and nested marker state — "Normal exit must remove records. (expected '0', got '2')"
- `LanePool.Tests.ps1`: Stopped owner entry restores its marker and acquires again in the surviving runspace — "Cancellation must remove its record and lock. (expected '0', got '2')"
- `CiPowerShellSuiteRunner.Tests.ps1`: Lane exclusive Suites acquire One and release it before the next Suite — "Runner completion must unregister."
- `CiPowerShellSuiteRunner.Tests.ps1`: Lane stopped runner settles children before unregistering and restores its marker — "Cancellation must unregister the run."
- `MeasureTestModes.Tests.ps1`: Same-host fail-build restores its marker and releases its Lanes and checkout — "Completion must remove its advisory record."
- `MeasureTestModes.Tests.ps1`: Same-host fail-fast restores its marker and releases its Lanes and checkout — "Completion must remove its advisory record."
- `MeasureTestModes.Tests.ps1`: Same-host fail-run.txt restores its marker and releases its Lanes and checkout — "Completion must remove its advisory record."
- `MeasureTestModes.Tests.ps1`: Same-host none restores its marker and releases its Lanes and checkout — "Completion must remove its advisory record."
- `MeasureTestModes.Tests.ps1`: Cancelled admission cleans up in a surviving runspace before any work starts — "Cancellation must remove its advisory record."

Before patch:

```text
file:    scripts/test-lanes.common.ps1
find:    foreach ($path in @($Run.RecordPath, $Run.LockPath)) {
replace: foreach ($path in @()) {
```

#### M7 (module)

Sentence: A run end removes the ownership marker instead of restoring its earlier value.

Before outcome: **Caught**. LanePool, Coverage, TestFast and MeasureTestModes cases fail because the marker was empty instead of its earlier value ("expected 'before', got ''", "must restore its marker").

Failing cases that show the behaviour:

- `LanePool.Tests.ps1`: Ownership restores the prior marker — "Ownership must restore the marker. (expected 'before', got '')"
- `LanePool.Tests.ps1`: Stopped owner entry restores its marker and acquires again in the surviving runspace — "Cancellation must restore the exact prior marker. (expected '  ', got '')"
- `CoverageRunnerProgress.Tests.ps1`: Coverage Lane route: direct nested=False — "The completed route must restore its marker. Child output: [1/6] restore        elapsed 0s  remaining unknown (6 units have no history)"
- `CoverageRunnerProgress.Tests.ps1`: Coverage Lane route: delegated nested=False — "The completed route must restore its marker. Child output: [1/6] restore        elapsed 0s  remaining unknown (6 units have no history)"
- `CoverageRunnerProgress.Tests.ps1`: Cancellation releases Lane and checkout ownership in a surviving host — "Cancellation must restore the exact marker in the surviving host."
- `TestFastDotnetProgress.Tests.ps1`: Fast Lane route: owner — "The completed route must restore its marker. Child output:"
- `TestFastDotnetProgress.Tests.ps1`: Fast Lane route: repeat — "The surviving host must restore its exact marker between runs."
- `TestFastDotnetProgress.Tests.ps1`: Cancellation releases Lane and checkout ownership in a surviving host — "Cancellation must restore the exact marker in the surviving host."
- `MeasureTestModes.Tests.ps1`: Same-host fail-build restores its marker and releases its Lanes and checkout — "Restore the exact previous marker in the same host."
- `MeasureTestModes.Tests.ps1`: Same-host fail-fast restores its marker and releases its Lanes and checkout — "Restore the exact previous marker in the same host."
- `MeasureTestModes.Tests.ps1`: Same-host fail-run.txt restores its marker and releases its Lanes and checkout — "Restore the exact previous marker in the same host."
- `MeasureTestModes.Tests.ps1`: Same-host none restores its marker and releases its Lanes and checkout — "Restore the exact previous marker in the same host."
- `MeasureTestModes.Tests.ps1`: Cancelled admission cleans up in a surviving runspace before any work starts — "Cancelled entry must restore its marker."

Before patch:

```text
file:    scripts/test-lanes.common.ps1
find:        else { $env:AHKFLOW_TEST_LANES_HOLDER = [string]$Previous }
replace:     else { Remove-Item Env:\AHKFLOW_TEST_LANES_HOLDER -ErrorAction SilentlyContinue }
```

#### M8 (module)

Sentence: A take keeps entry.lock open after it returns, so every later take waits for ever.

Before outcome: **Caught**. Many cases fail with entry.lock "being used by another process" after takes returned, and the LanePool timeout names the hung case 'Empty and occupied pools keep stable capacity', whose second take waits on the kept entry.lock; the CI timeout's hung case 'Lane missing Worker results cannot produce a passing summary' and the generic CI admission and Fast repeat timeouts follow from the same hang and are not counted.

Failing cases that show the behaviour:

- `LanePool.Tests.ps1`: Empty and occupied pools keep stable capacity — "hung: START with no result"
- `CoverageRunnerProgress.Tests.ps1`: Coverage Lane route: direct nested=True — "The process cannot access the file 'C:\Users\btase\AppData\Local\Temp\p193-5885657a\3\tmp\ahkflow-lane-pool-b0091ecffcbe4e23858d508080313fe9\entry.lock' because it is being used by another process."
- `CoverageRunnerProgress.Tests.ps1`: Coverage Lane route: delegated nested=True — "The process cannot access the file 'C:\Users\btase\AppData\Local\Temp\p193-5885657a\3\tmp\ahkflow-lane-pool-587aacf9bdb84af591b5147a91852d30\entry.lock' because it is being used by another process."
- `CoverageRunnerProgress.Tests.ps1`: Cancellation releases Lane and checkout ownership in a surviving host — "The process cannot access the file 'C:\Users\btase\AppData\Local\Temp\p193-5885657a\3\tmp\ahkflow-lane-pool-4c8291249fc5440d92060c5a92e050a0\entry.lock' because it is being used by another process."
- `TestFastDotnetProgress.Tests.ps1`: Fast Lane route: nested — "The process cannot access the file 'C:\Users\btase\AppData\Local\Temp\p193-5885657a\5\tmp\ahkflow-lane-pool-92a1f4752f4346e9af583fb71fbb5fac\entry.lock' because it is being used by another process."
- `TestFastDotnetProgress.Tests.ps1`: Cancellation releases Lane and checkout ownership in a surviving host — "The process cannot access the file 'C:\Users\btase\AppData\Local\Temp\p193-5885657a\5\tmp\ahkflow-lane-pool-0fce87566fec4bbabcf2c54b9bba7411\entry.lock' because it is being used by another process."
- `TestFastPowerShellMode.Tests.ps1`: PowerShell wrapper delegates per-Suite admission and preserves an existing holder — "The process cannot access the file 'C:\Users\btase\AppData\Local\Temp\p193-5885657a\7\tmp\ahkflow-lane-pool-6c47096917094e2d84eb58c99d32bb1e\entry.lock' because it is being used by another process."
- `MeasureTestModes.Tests.ps1`: Nested harness preserves its marker without adding Lanes (soak=False) — "The process cannot access the file 'C:\Users\btase\AppData\Local\Temp\p193-5885657a\2\tmp\ahkflow-lane-pool-3a9453b994ff436fb3d91bc57f4ce82b\entry.lock' because it is being used by another process."
- `MeasureTestModes.Tests.ps1`: Nested harness preserves its marker without adding Lanes (soak=True) — "The process cannot access the file 'C:\Users\btase\AppData\Local\Temp\p193-5885657a\2\tmp\ahkflow-lane-pool-242cf6a5eba3454aa4ed197f381fb38e\entry.lock' because it is being used by another process."
- `MeasureTestModes.Tests.ps1`: Same-host fail-build restores its marker and releases its Lanes and checkout — "The process cannot access the file 'C:\Users\btase\AppData\Local\Temp\p193-5885657a\2\tmp\ahkflow-lane-pool-d8631562076c4665827ce3ddc469867e\entry.lock' because it is being used by another process."
- `MeasureTestModes.Tests.ps1`: Same-host fail-fast restores its marker and releases its Lanes and checkout — "The process cannot access the file 'C:\Users\btase\AppData\Local\Temp\p193-5885657a\2\tmp\ahkflow-lane-pool-f9f3289e1f9649a8afac2880e499ffa4\entry.lock' because it is being used by another process."
- `MeasureTestModes.Tests.ps1`: Same-host fail-run.txt restores its marker and releases its Lanes and checkout — "The process cannot access the file 'C:\Users\btase\AppData\Local\Temp\p193-5885657a\2\tmp\ahkflow-lane-pool-55486747c4b24af8a38cc787a41ce97d\entry.lock' because it is being used by another process."
- `MeasureTestModes.Tests.ps1`: Same-host none restores its marker and releases its Lanes and checkout — "The process cannot access the file 'C:\Users\btase\AppData\Local\Temp\p193-5885657a\2\tmp\ahkflow-lane-pool-73c2bec3effb48eba407129d64afbd2a\entry.lock' because it is being used by another process."
- `MeasureTestModes.Tests.ps1`: Cancelled admission cleans up in a surviving runspace before any work starts — "The process cannot access the file 'C:\Users\btase\AppData\Local\Temp\p193-5885657a\2\tmp\ahkflow-lane-pool-9d243e97f18e48d0b593d1e9000fd6d8\entry.lock' because it is being used by another process."

Before patch:

```text
file:    scripts/test-lanes.common.ps1
find:            if ($null -ne $entry) { $entry.Dispose() }
replace:         if ($null -ne $entry) { $script:AhkFlowKeptEntry = $entry }
```

#### M9 (module)

Sentence: A Suite's Lane take reads the role again instead of using the role the run start captured, so an owner run's Suites take no Lane.

Before outcome: **Caught**. CI Lane cases fail because owner-run Suites took no Lane ("expected 2 starts, got 4", "A must hold both Lane locks", "An exclusive Suite needs exactly One Lane", "Both Suites must hold Lanes", acquisition failure did not fail the runner); the CI changed-capacity case (Enter never called) and the PowerShell wrapper's "must add no Half reservation" failure are not counted, and the wrapper failure hints the patch also changes a nested path.

Failing cases that show the behaviour:

- `CiPowerShellSuiteRunner.Tests.ps1`: Lane one runner admits exactly two of four Workers — "Admission cap violated: expected 2 starts, got 4."
- `CiPowerShellSuiteRunner.Tests.ps1`: Lane two checkout runners enforce one combined cap — "A must hold both Lane locks."
- `CiPowerShellSuiteRunner.Tests.ps1`: Lane acquisition failures produce named failures in exclusive and parallel execution — "Acquisition failure must fail the runner."
- `CiPowerShellSuiteRunner.Tests.ps1`: Lane exclusive Suites acquire One and release it before the next Suite — "An exclusive Suite needs exactly One Lane."
- `CiPowerShellSuiteRunner.Tests.ps1`: Lane stopped runner settles children before unregistering and restores its marker — "Both Suites must hold Lanes before cancellation."

Before patch:

```text
file:    scripts/run-powershell-suites.ps1
find:                if ($laneRun) {\r\n                $lanes = Enter-AhkFlowLanes
replace:             if ((Get-AhkFlowLaneRole) -eq 'owner') {\r\n                $lanes = Enter-AhkFlowLanes
file:    scripts/run-powershell-suites.ps1
find:                    if ($laneRun) {\r\n                    $lanes = Enter-AhkFlowLanes
replace:                 if ((Get-AhkFlowLaneRole) -eq 'owner') {\r\n                    $lanes = Enter-AhkFlowLanes
```

#### C1 (runner)

Sentence: In a parallel run, a Worker never gives its Suite's Lane back.

Before outcome: **Caught**. CI 'Lane stopped runner settles children before unregistering and restores its marker' fails with "Cancellation must release every Lane."; the CI admission case timed out waiting for a later Suite to start, which fits the missing give-back but its message is generic, so it is not counted.

Failing cases that show the behaviour:

- `CiPowerShellSuiteRunner.Tests.ps1`: Lane stopped runner settles children before unregistering and restores its marker — "Cancellation must release every Lane."

Before patch:

```text
file:    scripts/run-powershell-suites.ps1
find:                    Exit-AhkFlowLanes -Handle $lanes\r\n
replace: 
```

#### C2 (test-fast)

Sentence: test-fast.ps1 releases the checkout lock before it gives its Lanes back.

Before outcome: **Caught**. All three TestFast Lane routes fail on the fixture check "Lane ownership must release before checkout cleanup." (the failure route in its message, owner and repeat in the child output in the log at lines 40, 58 and 81), which is the reversed release order in the sentence.

Failing cases that show the behaviour:

- `TestFastDotnetProgress.Tests.ps1`: Fast Lane route: owner — ""
- `TestFastDotnetProgress.Tests.ps1`: Fast Lane route: repeat — "Lane child exited before publishing 'C:\Users\btase\AppData\Local\Temp\p193-d6db3a1a\5\tmp\test-fast-progress-05b2922ad4184b419d8d725a39fc7bc3\stub\after-1'. Child output:"
- `TestFastDotnetProgress.Tests.ps1`: Fast Lane route: failure — "Lane ownership must release before checkout cleanup. Child output:"

Before patch:

```text
file:    scripts/test-fast.ps1
find:        Exit-AhkFlowLaneRun -State $laneRun\r\n    Exit-AhkFlowTestRunLock -Handle $testRunLock
replace:     Exit-AhkFlowTestRunLock -Handle $testRunLock\r\n    Exit-AhkFlowLaneRun -State $laneRun
```

#### C3 (measure)

Sentence: measure-test-modes.ps1 never ends its Lane run, so its Lanes, its record and the marker stay until its process ends.

Before outcome: **Caught**. The four MeasureTestModes same-host cases, which check that the run restores its marker and releases its Lanes, fail because the run's runs\<pid>-<id>.lock file is still held by the process after the script returned.

Failing cases that show the behaviour:

- `MeasureTestModes.Tests.ps1`: Same-host fail-build restores its marker and releases its Lanes and checkout — "The process cannot access the file 'C:\Users\btase\AppData\Local\Temp\p193-073f2f6a\2\tmp\ahkflow-lane-pool-d513eec62d994477b4e4e535b5c81537\runs\34460-c770a46ab6ea4e2dbc95c94cd4739b8e.lock' because it is being used by another process."
- `MeasureTestModes.Tests.ps1`: Same-host fail-fast restores its marker and releases its Lanes and checkout — "The process cannot access the file 'C:\Users\btase\AppData\Local\Temp\p193-073f2f6a\2\tmp\ahkflow-lane-pool-5c252e9a2664421d8d2889ac38eebd97\runs\34460-97629f8e11de4265b3b129c3f2d35d9c.lock' because it is being used by another process."
- `MeasureTestModes.Tests.ps1`: Same-host fail-run.txt restores its marker and releases its Lanes and checkout — "The process cannot access the file 'C:\Users\btase\AppData\Local\Temp\p193-073f2f6a\2\tmp\ahkflow-lane-pool-afa4c1f08a6c4c379ac283827642cdaa\runs\34460-ff824e513a3443069b9d9aee9bfcec96.lock' because it is being used by another process."
- `MeasureTestModes.Tests.ps1`: Same-host none restores its marker and releases its Lanes and checkout — "The process cannot access the file 'C:\Users\btase\AppData\Local\Temp\p193-073f2f6a\2\tmp\ahkflow-lane-pool-e3e20ce5a29f4d1a93fa58414ac29830\runs\34460-3fb4c8571f24404ea4bff9b14a9bee99.lock' because it is being used by another process."

Before patch:

```text
file:    scripts/measure-test-modes.ps1
find:        Exit-AhkFlowLaneRun -State $laneState\r\n
replace: 
```

## The after record

### Test count

The after commit removes the cases that P5 of the plan marks "remove", and adds the check. The
Lane-related rule of the plan was applied to every case of the after tree. It finds exactly the 75
names that P5 lists, so there is no difference to explain. Each name below appears in the PASS
lines of the after opening control.

The four caller Suites that lost cases lost exactly those cases. Their other cases did not change:

- `CiPowerShellSuiteRunner.Tests.ps1`: 101 cases before, 100 after.
- `TestFastDotnetProgress.Tests.ps1`: 14 before, 12 after.
- `CoverageRunnerProgress.Tests.ps1`: 16 before, 13 after.
- `MeasureTestModes.Tests.ps1`: 36 before, 32 after.

The check, `No script or Suite outside the Lane pool files names an internal Lane function`, lives
in `LanePool.Tests.ps1` but counts as a caller case (spec section 5.1).

**CiPowerShellSuiteRunner.Tests.ps1** (caller Suite, 10 cases)

- caller: Lane one runner admits exactly two of four Workers
- caller: Lane exclusive Suites acquire One and release it before the next Suite
- caller: Lane invalid opt-out fails before any Suite starts
- caller: Lane nested and off preserve incoming marker and never open pool files
- caller: Lane owner hardware query is once with adaptive sizing or explicit Workers
- caller: Lane acquisition failures produce named failures in exclusive and parallel execution
- caller: Lane admission wait stays out of Suite timing
- caller: Lane stopped runner ends its run and restores its marker
- caller: Lane run-start failure returns nonzero before any Suite starts
- caller: In-process calls isolate job summaries and restore environment after failure

**TestFastPowerShellMode.Tests.ps1** (caller Suite, 2 cases)

- caller: PowerShell wrapper delegates per-Suite admission and preserves an existing holder
- caller: PowerShell wrapper forwards all Lane settings and restores fixture environment

**TestFastDotnetProgress.Tests.ps1** (caller Suite, 3 cases)

- caller: Fast Lane route: owner
- caller: Fast Lane route: failure
- caller: Cancellation releases Lane and checkout ownership in a surviving host

**CoverageRunnerProgress.Tests.ps1** (caller Suite, 3 cases)

- caller: Coverage Lane route: direct nested=False
- caller: Coverage Lane route: direct failure
- caller: Cancellation releases Lane and checkout ownership in a surviving host

**CoverageSliceSkip.Tests.ps1** (caller Suite, 1 cases)

- caller: Coverage wrapper leaves admission and marker ownership to its delegate

**MeasureTestModes.Tests.ps1** (caller Suite, 6 cases)

- caller: Timing waits before work and holds its share across every call
- caller: Soak waits before work and holds its share across every call
- caller: Whole blocks a competing acquirer through the parent checkout handoff
- caller: Same-host fail-build restores its marker and releases its Lanes and checkout
- caller: Same-host none restores its marker and releases its Lanes and checkout
- caller: Cancelled admission cleans up in a surviving runspace before any work starts

**GateEvidence.Tests.ps1** (caller Suite, 0 cases)

- none: its four Lane cases only isolate the pool (isolation cases)

**LanePool.Tests.ps1** (not a caller Suite, 40 cases)

- Role precedence and validation
- Ownership restores the prior marker
- Proposal and every share are stable
- Entry contention blocks until an acknowledged real-open failure clears
- Classifier accepts only the measured native code
- Missing parent throws and genuine contention returns null
- Empty and occupied pools keep stable capacity
- Partial acquisition failure releases entry and lanes
- Half shares compose at six and wait at odd capacities
- Stopping a runspace releases its partial share in the same host
- Hosted proposal avoids hardware discovery and local proposal queries once
- malformed capacity releases entry before retry and resizes only when empty
- missing capacity releases entry before retry and resizes only when empty
- unreadable capacity releases entry before retry and resizes only when empty
- Capacity 1 blocks One with proposal 1 until release
- Capacity 6 blocks Whole with proposal 2 until release
- Capacity 2 blocks One with proposal 6 until release
- One proposing two joins an occupied capacity six without resizing
- Killing a partial collector releases entry and its Lanes
- An early assertion still reaps a gated child and removes its pool
- Access failures throw without being classified as contention
- Interval Suite publishes complete monotonic endpoints and waits for release
- Always-successful open mutation fails the actual contention cases
- Advisory records announce peers once and ignore incomplete or stale files
- A failed sharing write retries on the next wait
- Concurrent Workers share one diagnostic decision
- Registration publication failure releases its record handle
- Owner lifecycle restores normal failed and nested marker state
- A killed advisory owner is no longer named
- A late peer is announced during entry retry before its Lane is released
- A late peer is announced during capacity retry before its Lane is released
- A late peer is announced during share retry before its Lane is released
- Stopped owner entry restores its marker and acquires again in the surviving runspace
- Unreadable advisory records cannot abort a valid reservation
- A Share One owner run registers and takes ownership but holds no Lane
- A Suite Lane take in an owner run holds one Lane after the marker is set
- A Suite Lane take in a Nested run holds nothing
- A Suite Lane take in an opted-out run holds nothing
- The module loads in Windows PowerShell 5.1
- caller (the check): No script or Suite outside the Lane pool files names an internal Lane function

**LaneFileLockPrimitive.Tests.ps1** (not a caller Suite, 10 cases)

- Another process cannot open a held Lane or entry lock
- Explicit release frees both files
- Holder stdin EOF releases both files
- A second handle in the same process is refused
- Another runspace is refused
- Killing a holder frees both files
- Missing parent differs from contention
- Generic injected IOException differs from contention
- Access denied differs from contention
- Windows PowerShell 5.1 repeats native cases

Caller count: 26. Total count: 75.

- **Caller count**: 35 before, 26 after. It falls by 9, which is 25.7 percent.
- **Total count**: 79 before, 75 after. It falls by 4, which is 5.1 percent.

### Defects and after outcomes

The after attempt ran on 2026-10-30 at the after commit. Its opening control and its closing
control were both clean, and the closing control printed the same PASS names. So the attempt
status is `clean`, and every defect result counts.

Before the run, an independent sub-agent checked both patches of each defect against its
sentence (spec section 5.3). It found that every patch gives the wrong behaviour in its sentence,
and that neither side's patch is easier to catch. It found no problem, so no patch was rewritten.
Each defect below shows its after patch. The before section shows its before patch.

A second independent sub-agent gave each after outcome by the rules of spec section 5.4. It did
not write the patches. Its reason sentences are copied here unchanged.

After side: 12 Caught, 0 Missed, 0 Invalid, 0 Inconclusive.

#### M1 (module)

Sentence: A run rewrites capacity.txt while another run holds a Lane.

After outcome: **Caught**. Four LanePool cases fail because an occupied pool's capacity.txt changed (expected 2 got 6, expected 6 got 2).

Failing cases that show the behaviour:

- `LanePool.Tests.ps1`: Empty and occupied pools keep stable capacity — "Occupied pool must retain two. (expected '2', got '6')"
- `LanePool.Tests.ps1`: Capacity 6 blocks Whole with proposal 2 until release — "Occupied capacity changed. (expected '6', got '2')"
- `LanePool.Tests.ps1`: Capacity 2 blocks One with proposal 6 until release — "Occupied capacity changed. (expected '2', got '6')"
- `LanePool.Tests.ps1`: One proposing two joins an occupied capacity six without resizing — "Occupied six must remain six. (expected '6', got '2')"

After patch:

```text
file:    scripts/test-lanes.common.ps1
find:        if (-not $held) {
replace:     if ($true) {
```

#### M2 (module)

Sentence: A Half share rounds down, so capacity 3 gives one Lane and capacity 1 gives none.

After outcome: **Caught**. Half gives 0 instead of 1 at odd capacity 1, which is the rounding down in the sentence.

Failing cases that show the behaviour:

- `LanePool.Tests.ps1`: Proposal and every share are stable — "Half differed. (expected '1', got '0')"
- `LanePool.Tests.ps1`: Half shares compose at six and wait at odd capacities — "Odd capacity 1 must expose one half. (expected '1', got '0')"

After patch:

```text
file:    scripts/test-lanes.common.ps1
find:    [Math]::Ceiling($Capacity / 2.0)
replace: [Math]::Floor($Capacity / 2.0)
```

#### M3 (module)

Sentence: A run that starts while the ownership marker is set acts as an owner and takes Lanes.

After outcome: **Caught**. With the marker set the role is 'owner' instead of 'nested', and the LanePool timeout is the nested Whole take in 'Owner lifecycle...' (START with no result, tests/LanePool.Tests.ps1:501) waiting for Lanes its owner holds.

Failing cases that show the behaviour:

- `LanePool.Tests.ps1`: Role precedence and validation — "A holder must select nested. (expected 'nested', got 'owner')"
- `LanePool.Tests.ps1`: Owner lifecycle restores normal failed and nested marker state — "timed out; START line with no result"
- `TestFastPowerShellMode.Tests.ps1`: PowerShell wrapper delegates per-Suite admission and preserves an existing holder — "The wrapper must add no Half reservation."
- `TestFastPowerShellMode.Tests.ps1`: PowerShell wrapper forwards all Lane settings and restores fixture environment — "Missing nested status. Gate evidence: on"

After patch:

```text
file:    scripts/test-lanes.common.ps1
find:    { return 'nested' }
replace: { return 'owner' }
```

#### M4 (module)

Sentence: AHKFLOW_TEST_LANES=off is ignored, so the run acts as an owner and takes Lanes.

After outcome: **Caught**. With AHKFLOW_TEST_LANES=off the role is 'owner' instead of 'off', and an opted-out Suite take returns a Lane handle.

Failing cases that show the behaviour:

- `LanePool.Tests.ps1`: Role precedence and validation — "Opt-out must win. (expected 'off', got 'owner')"
- `LanePool.Tests.ps1`: Owner lifecycle restores normal failed and nested marker state — "Opt-out must take precedence. (expected 'off', got 'owner')"
- `LanePool.Tests.ps1`: A Suite Lane take in an opted-out run holds nothing — "The take must return a handle only in an owner run. (expected '0', got '1')"
- `TestFastPowerShellMode.Tests.ps1`: PowerShell wrapper forwards all Lane settings and restores fixture environment — "Missing off status. Gate evidence: on"

After patch:

```text
file:    scripts/test-lanes.common.ps1
find:    -ieq 'off') { return 'off' }
replace: -ieq 'off') { return 'owner' }
```

#### M5 (module)

Sentence: A take that fails part-way keeps the Lanes it already opened.

After outcome: **Caught**. After a take is stopped part-way, lane-0.lock stays open, so the partial Lane is kept; the injected-exception case 'Partial acquisition failure releases entry and lanes' still passes.

Failing cases that show the behaviour:

- `LanePool.Tests.ps1`: Stopping a runspace releases its partial share in the same host — "The process cannot access the file 'C:\Users\btase\AppData\Local\Temp\p193-44fc6bcd\6\tmp\ahkflow-lane-pool-ae2f4a59b8d04b4da53aa022939278a3\lane-0.lock' because it is being used by another process."
- `LanePool.Tests.ps1`: Stopped owner entry restores its marker and acquires again in the surviving runspace — "The process cannot access the file 'C:\Users\btase\AppData\Local\Temp\p193-44fc6bcd\6\tmp\ahkflow-lane-pool-818d83141cc243e8889ff2e2f285cc6f\lane-0.lock' because it is being used by another process."
- `CoverageRunnerProgress.Tests.ps1`: Cancellation releases Lane and checkout ownership in a surviving host — "The process cannot access the file 'C:\Users\btase\AppData\Local\Temp\p193-44fc6bcd\3\tmp\ahkflow-lane-pool-e0057f36d29b47c7afc5c84e9b401a03\lane-0.lock' because it is being used by another process."
- `MeasureTestModes.Tests.ps1`: Cancelled admission cleans up in a surviving runspace before any work starts — "The process cannot access the file 'C:\Users\btase\AppData\Local\Temp\p193-44fc6bcd\2\tmp\ahkflow-lane-pool-5220e66d3b974c3bb78f1f9d857f97ea\lane-0.lock' because it is being used by another process."
- `TestFastDotnetProgress.Tests.ps1`: Cancellation releases Lane and checkout ownership in a surviving host — "The process cannot access the file 'C:\Users\btase\AppData\Local\Temp\p193-44fc6bcd\5\tmp\ahkflow-lane-pool-d1c8199b30c94f0bad01bd9cac7f2219\lane-0.lock' because it is being used by another process."

After patch:

```text
file:    scripts/test-lanes.common.ps1
find:            if (-not $completed) { foreach ($lane in $lanes) { $lane.Dispose() } }\r\n
replace: 
```

#### M6 (module)

Sentence: A run end leaves its record and lock file in runs/.

After outcome: **Caught**. The run end leaves files in runs/ (expected 0 got 2), and runner and measure completion fail to unregister or remove the advisory record.

Failing cases that show the behaviour:

- `LanePool.Tests.ps1`: Registration publication failure releases its record handle — "Failed publication must remove its files. (expected '0', got '1')"
- `LanePool.Tests.ps1`: Owner lifecycle restores normal failed and nested marker state — "Normal exit must remove records. (expected '0', got '2')"
- `LanePool.Tests.ps1`: Stopped owner entry restores its marker and acquires again in the surviving runspace — "Cancellation must remove its record and lock. (expected '0', got '2')"
- `LanePool.Tests.ps1`: A Share One owner run registers and takes ownership but holds no Lane — "The run end must remove its record. (expected '0', got '2')"
- `CiPowerShellSuiteRunner.Tests.ps1`: Lane one runner admits exactly two of four Workers — "Runner completion must unregister."
- `CiPowerShellSuiteRunner.Tests.ps1`: Lane admission wait stays out of Suite timing — "Runner completion must unregister."
- `CiPowerShellSuiteRunner.Tests.ps1`: Lane exclusive Suites acquire One and release it before the next Suite — "Runner completion must unregister."
- `CiPowerShellSuiteRunner.Tests.ps1`: Lane stopped runner ends its run and restores its marker — "Cancellation must unregister the run."
- `MeasureTestModes.Tests.ps1`: Same-host fail-build restores its marker and releases its Lanes and checkout — "Completion must remove its advisory record."
- `MeasureTestModes.Tests.ps1`: Same-host none restores its marker and releases its Lanes and checkout — "Completion must remove its advisory record."
- `MeasureTestModes.Tests.ps1`: Cancelled admission cleans up in a surviving runspace before any work starts — "Cancellation must remove its advisory record."

After patch:

```text
file:    scripts/test-lanes.common.ps1
find:    foreach ($path in @($Run.RecordPath, $Run.LockPath)) {
replace: foreach ($path in @()) {
```

#### M7 (module)

Sentence: A run end removes the ownership marker instead of restoring its earlier value.

After outcome: **Caught**. The marker is empty after the run ends instead of its earlier value ('before' or '  ').

Failing cases that show the behaviour:

- `LanePool.Tests.ps1`: Ownership restores the prior marker — "Ownership must restore the marker. (expected 'before', got '')"
- `LanePool.Tests.ps1`: Stopped owner entry restores its marker and acquires again in the surviving runspace — "Cancellation must restore the exact prior marker. (expected '  ', got '')"
- `LanePool.Tests.ps1`: A Share One owner run registers and takes ownership but holds no Lane — "The run end must restore the exact marker. (expected '  ', got '')"
- `CoverageRunnerProgress.Tests.ps1`: Coverage Lane route: direct nested=False — "The completed route must restore its marker. Child output: [1/6] restore        elapsed 0s  remaining unknown (6 units have no history)"
- `CoverageRunnerProgress.Tests.ps1`: Cancellation releases Lane and checkout ownership in a surviving host — "Cancellation must restore the exact marker in the surviving host."
- `MeasureTestModes.Tests.ps1`: Same-host fail-build restores its marker and releases its Lanes and checkout — "Restore the exact previous marker in the same host."
- `MeasureTestModes.Tests.ps1`: Same-host none restores its marker and releases its Lanes and checkout — "Restore the exact previous marker in the same host."
- `MeasureTestModes.Tests.ps1`: Cancelled admission cleans up in a surviving runspace before any work starts — "Cancelled entry must restore its marker."
- `TestFastDotnetProgress.Tests.ps1`: Fast Lane route: owner — "The completed route must restore its marker. Child output:"
- `TestFastDotnetProgress.Tests.ps1`: Cancellation releases Lane and checkout ownership in a surviving host — "Cancellation must restore the exact marker in the surviving host."

After patch:

```text
file:    scripts/test-lanes.common.ps1
find:        else { $env:AHKFLOW_TEST_LANES_HOLDER = [string]$Previous }
replace:     else { Remove-Item Env:\AHKFLOW_TEST_LANES_HOLDER -ErrorAction SilentlyContinue }
```

#### M8 (module)

Sentence: A take keeps entry.lock open after it returns, so every later take waits for ever.

After outcome: **Caught**. Five cases report entry.lock still in use after the take returned, the runner never admits a second Worker, and LanePool hangs in the first case that makes a second take ('Empty and occupied pools...' has START with no result).

Failing cases that show the behaviour:

- `LanePool.Tests.ps1`: Empty and occupied pools keep stable capacity — "timed out; START line with no result"
- `CiPowerShellSuiteRunner.Tests.ps1`: Lane one runner admits exactly two of four Workers — "Runner never reached 2 starts."
- `CoverageRunnerProgress.Tests.ps1`: Cancellation releases Lane and checkout ownership in a surviving host — "The process cannot access the file 'C:\Users\btase\AppData\Local\Temp\p193-3181e1f5\3\tmp\ahkflow-lane-pool-dd912191970f4c43a081decbd56d1d9a\entry.lock' because it is being used by another process."
- `MeasureTestModes.Tests.ps1`: Same-host fail-build restores its marker and releases its Lanes and checkout — "The process cannot access the file 'C:\Users\btase\AppData\Local\Temp\p193-3181e1f5\2\tmp\ahkflow-lane-pool-f7b96534e6e4406f9557b1c480ced266\entry.lock' because it is being used by another process."
- `MeasureTestModes.Tests.ps1`: Same-host none restores its marker and releases its Lanes and checkout — "The process cannot access the file 'C:\Users\btase\AppData\Local\Temp\p193-3181e1f5\2\tmp\ahkflow-lane-pool-98f9fb6c836d4af29108839f4b101b33\entry.lock' because it is being used by another process."
- `MeasureTestModes.Tests.ps1`: Cancelled admission cleans up in a surviving runspace before any work starts — "The process cannot access the file 'C:\Users\btase\AppData\Local\Temp\p193-3181e1f5\2\tmp\ahkflow-lane-pool-0e346e5d85234f089a9c462493aaf4de\entry.lock' because it is being used by another process."
- `TestFastDotnetProgress.Tests.ps1`: Cancellation releases Lane and checkout ownership in a surviving host — "The process cannot access the file 'C:\Users\btase\AppData\Local\Temp\p193-3181e1f5\5\tmp\ahkflow-lane-pool-4517012a774248d3aa334e8fd692cc5d\entry.lock' because it is being used by another process."

After patch:

```text
file:    scripts/test-lanes.common.ps1
find:            if ($null -ne $entry) { $entry.Dispose() }
replace:         if ($null -ne $entry) { $script:AhkFlowKeptEntry = $entry }
```

#### M9 (module)

Sentence: A Suite's Lane take reads the role again instead of using the role the run start captured, so an owner run's Suites take no Lane.

After outcome: **Caught**. A Suite take in an owner run returns no handle (expected 1 got 0), and the runner's Suites hold no Lanes.

Failing cases that show the behaviour:

- `LanePool.Tests.ps1`: A Suite Lane take in an owner run holds one Lane after the marker is set — "The take must return a handle only in an owner run. (expected '1', got '0')"
- `CiPowerShellSuiteRunner.Tests.ps1`: Lane one runner admits exactly two of four Workers — "Lane locks must match admission."
- `CiPowerShellSuiteRunner.Tests.ps1`: Lane exclusive Suites acquire One and release it before the next Suite — "An exclusive Suite needs exactly One Lane."
- `CiPowerShellSuiteRunner.Tests.ps1`: Lane stopped runner ends its run and restores its marker — "Both Suites must hold Lanes before cancellation."

After patch:

```text
file:    scripts/test-lanes.common.ps1
find:        if ($null -eq $State -or $State.Role -ne 'owner') { return $null }
replace:     if ($null -eq $State -or (Get-AhkFlowLaneRole) -ne 'owner') { return $null }
```

#### C1 (runner)

Sentence: In a parallel run, a Worker never gives its Suite's Lane back.

After outcome: **Caught**. In the parallel runner the later Workers never start because the Lanes were not given back, and lane-0.lock stays held.

Failing cases that show the behaviour:

- `CiPowerShellSuiteRunner.Tests.ps1`: Lane one runner admits exactly two of four Workers — "Timed out waiting for completed Lane signal 'C:\Users\btase\AppData\Local\Temp\p193-5bc7ce22\1\tmp\ahkflow-suiterepo-a9aa505398874380847defdb0dbca92b\tests\suite-1.start'."
- `CiPowerShellSuiteRunner.Tests.ps1`: Lane stopped runner ends its run and restores its marker — "The process cannot access the file 'C:\Users\btase\AppData\Local\Temp\p193-5bc7ce22\1\tmp\ahkflow-lane-pool-09b1dcb10d83461484d3407e7070765b\lane-0.lock' because it is being used by another process."

After patch:

```text
file:    scripts/run-powershell-suites.ps1
find:                    Exit-AhkFlowSuiteLane -Handle $lane\r\n
replace: 
```

#### C2 (test-fast)

Sentence: test-fast.ps1 releases the checkout lock before it gives its Lanes back.

After outcome: **Caught**. test-fast.ps1 fails with 'Lane ownership must release before checkout cleanup', which is the wrong order in the sentence.

Failing cases that show the behaviour:

- `TestFastDotnetProgress.Tests.ps1`: Fast Lane route: failure — "Lane ownership must release before checkout cleanup. Child output:"

After patch:

```text
file:    scripts/test-fast.ps1
find:        Exit-AhkFlowLaneRun -State $laneRun\r\n    Exit-AhkFlowTestRunLock -Handle $testRunLock
replace:     Exit-AhkFlowTestRunLock -Handle $testRunLock\r\n    Exit-AhkFlowLaneRun -State $laneRun
```

#### C3 (measure)

Sentence: measure-test-modes.ps1 never ends its Lane run, so its Lanes, its record and the marker stay until its process ends.

After outcome: **Caught**. After measure-test-modes.ps1 returns, its runs/ record lock is still held in the same host, so the Lane run was never ended.

Failing cases that show the behaviour:

- `MeasureTestModes.Tests.ps1`: Same-host fail-build restores its marker and releases its Lanes and checkout — "The process cannot access the file 'C:\Users\btase\AppData\Local\Temp\p193-2e2f2351\2\tmp\ahkflow-lane-pool-bcbbcaeb89b544078c6a000009dee5fc\runs\37524-3ab3da3893cc44e78252d9d0e5b9fcf7.lock' because it is being used by another process."
- `MeasureTestModes.Tests.ps1`: Same-host none restores its marker and releases its Lanes and checkout — "The process cannot access the file 'C:\Users\btase\AppData\Local\Temp\p193-2e2f2351\2\tmp\ahkflow-lane-pool-28731c18606a43cbaaa092743e226155\runs\37524-0d4e753e155540cbbe42890d67cb1ddd.lock' because it is being used by another process."

After patch:

```text
file:    scripts/measure-test-modes.ps1
find:        Exit-AhkFlowLaneRun -State $laneState\r\n
replace: 
```

## Timing

The timing ran on 2026-10-30 with `-Mode Timing`: one warm-up pass of each side, then A B B A B A
A B. Each pass ran every Suite once, alone, in the order of the inputs file. The expected cases of
each side were the PASS names of its clean opening control.

Every pass, in the order it ran. Times are seconds. A is the before commit and B the after commit.

| Suite | warm-A | warm-B | 1-A | 2-B | 3-B | 4-A | 5-B | 6-A | 7-A | 8-B |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| CiPowerShellSuiteRunner | 86.8 | 76.1 | 82.5 | 75.7 | 76.6 | 81.8 | 76.4 | 81.6 | 82.8 | 75.4 |
| CoverageRunnerProgress | 39.7 | 27.6 | 37.7 | 27.5 | 27.7 | 37.5 | 28.7 | 39.0 | 37.6 | 27.0 |
| CoverageSliceSkip | 17.6 | 16.2 | 16.2 | 16.3 | 16.6 | 16.4 | 15.9 | 16.1 | 16.7 | 16.4 |
| GateEvidence | 22.9 | 22.0 | 22.0 | 22.3 | 22.0 | 22.3 | 22.6 | 22.2 | 22.3 | 21.8 |
| MeasureTestModes | 54.3 | 45.5 | 49.8 | 44.8 | 44.3 | 50.1 | 44.8 | 51.5 | 50.5 | 44.6 |
| TestFastDotnetProgress | 22.9 | 15.4 | 21.7 | 15.6 | 15.5 | 21.3 | 15.2 | 22.6 | 20.8 | 15.1 |
| TestFastPowerShellMode | 23.7 | 23.4 | 23.2 | 23.6 | 22.7 | 23.2 | 22.7 | 23.1 | 22.8 | 23.5 |
| LaneFileLockPrimitive | 3.7 | 3.8 | 4.0 | 3.8 | 3.9 | 3.8 | 4.0 | 3.8 | 3.8 | 4.2 |
| LanePool | 20.1 | 28.7 | 20.8 | 30.2 | 29.3 | 20.0 | 30.0 | 20.0 | 20.3 | 30.4 |
| **Pass** | **291.69** | **258.60** | **277.97** | **259.87** | **258.43** | **276.36** | **260.36** | **279.92** | **277.62** | **258.46** |

Rejected passes: 0. The contention check passed at the start and the end of every pass.

- Before (the four timed passes): fastest 4-A at 276.36 s, slowest 6-A at 279.92 s.
- After (the four timed passes): fastest 3-B at 258.43 s, slowest 5-B at 260.36 s.

The four pairs of neighbours, each with its fall: the before time minus the after time, as a percentage of the before time.

- 1-A and 2-B: before 277.97 s, after 259.87 s, fall 6.51 percent.
- 3-B and 4-A: before 276.36 s, after 258.43 s, fall 6.49 percent.
- 5-B and 6-A: before 279.92 s, after 260.36 s, fall 6.99 percent.
- 7-A and 8-B: before 277.62 s, after 258.46 s, fall 6.90 percent.

Median fall: 6.71 percent. Every fall is under 10 percent, so section 5.5 of the spec gives **Not faster**.

## Verdict

**Negative.**

Every defect is valid on both sides, so the verdict can be worked out (spec section 5.6). The
three targets:

1. **No defect is lost**: holds. All 12 defects are Caught before and Caught after.
2. **Fewer**: holds. The caller count falls by 25.7 percent, against a bar of 25 percent. Beside
   it, the total count falls by 5.1 percent.
3. **Faster**: does not hold. All four falls are under 10 percent. The median fall is 6.71
   percent. Section 5.5 gives Not faster.

The verdict takes the first outcome that applies. Not faster is a Negative condition, so the
verdict is Negative. The after tests are faster, by about 18 seconds a pass, but not by the 10
percent the spec set as the target.

The saved time comes from the four caller Suites that lost cases. Compared over the timed passes,
`CoverageRunnerProgress` runs about 10 seconds faster. `TestFastDotnetProgress`,
`MeasureTestModes` and `CiPowerShellSuiteRunner` each run about 6 seconds faster. `LanePool` runs
about 9 seconds slower, because of the new run interface cases and the check.

Per spec section 6.3, the code is reverted. This record, the backlog item and the two
`CONTEXT.md` terms stay.

## The Stryker.NET answer

This answer was fixed in spec section 6.2, before any data existed.

- **Not next.** This pilot measures the value of deliberate defect injection for the PowerShell
  tests. It injects 12 hand-made defects into PowerShell, and Stryker.NET mutates C#. So it cannot
  judge Stryker.NET. Whether Stryker.NET is worth trying stays a decision for backlog 194, the
  .NET test audit.
- The gaps below say whether the defects exposed gaps in the PowerShell tests. Backlog 194 can use
  them as one input.
- Nothing is installed without the user's yes.

## Gaps

The before tests caught all 12 defects, and so did the after tests. Neither side missed a defect,
so the pilot shows no gap in the PowerShell tests of the Lane pool.
