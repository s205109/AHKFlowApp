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
- **After commit**: not yet taken.
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

Not yet taken.

## Timing

Not yet taken.

## Verdict

Not yet worked out.

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

The before tests caught all 12 defects. They missed none, so the before side shows no gap.
