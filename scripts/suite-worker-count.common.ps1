# How many suites may run at once when nobody says. Backlog 145.
#
# The measurement behind the number: on an eight-core laptop, six workers finished the same 56
# suites in the same wall clock as eight. The last two workers waited on the disk and on process
# starts and returned nothing, while the machine became hard to use. So on a developer's machine
# the default is 75% of the physical cores.
#
# Physical cores, never [Environment]::ProcessorCount. That property counts hardware threads. The
# measured machine reports 16 for its 8 cores, and 75% of 16 is 12 - more than the old default,
# and the opposite of what this change is for.
#
# The ceiling of eight is the number this repository has run with for months. Nobody has measured
# a machine larger than eight cores, so the rule stops there rather than guessing.
#
# -AllProcessors is the GitHub Actions rule. The 75% exists to keep a laptop usable while the
# suites run, and nobody is using a hosted runner while it works. A runner should finish and stop,
# so it takes every processor it has. That is also what CI did before backlog 145, which is why
# the job is no slower than it was.
# The raw 75% share, before any bound is applied. Get-DefaultSuiteWorkerCount applies the bounds
# and Get-DefaultSuiteWorkerReason explains which one bit, so both read the share from here and the
# 0.75 lives in exactly one place.
function Get-PhysicalCoreShare {
    param([int] $PhysicalCoreCount)

    return [int] [Math]::Floor($PhysicalCoreCount * 0.75)
}

function Get-DefaultSuiteWorkerCount {
    param(
        [int] $PhysicalCoreCount,
        [int] $LogicalProcessorCount = [Environment]::ProcessorCount,
        [switch] $AllProcessors
    )

    if ($AllProcessors) {
        return [Math]::Max(1, $LogicalProcessorCount)
    }

    # A machine whose core count we cannot read is a machine we know nothing about. The one number
    # known to be safe there is the number it has been running with all along, which is the rule
    # this function replaces. A smaller guess would slow a run for no measured reason.
    if ($PhysicalCoreCount -lt 1) {
        return [Math]::Max(1, [Math]::Min($LogicalProcessorCount, 8))
    }

    # Capped by the processors as well as by the ceiling. The two readers behind $PhysicalCoreCount
    # describe the machine: Win32_Processor and /proc/cpuinfo both count hardware that exists, and
    # neither knows about process affinity or a container CPU limit. [Environment]::ProcessorCount
    # does know: .NET reports the processors available to this process. So a machine can honestly
    # report 8 cores while this run may use 2, and 75% of 8 would then start six workers on two
    # processors. Backlog 145 review, finding 1.
    $share = Get-PhysicalCoreShare -PhysicalCoreCount $PhysicalCoreCount
    return [Math]::Max(1, [Math]::Min([Math]::Min($share, $LogicalProcessorCount), 8))
}

# Says, in one short phrase, how the default reached its number. The run prints it after 'default:'
# on the Workers line.
#
# It names a bound only when a bound decided the answer. Printing '75% of 16 physical cores' beside
# a worker count of 8 invites the reader to check the arithmetic and conclude the run is broken.
# Backlog 145 review, finding 4.
function Get-DefaultSuiteWorkerReason {
    param(
        [int] $PhysicalCoreCount,
        [int] $LogicalProcessorCount = [Environment]::ProcessorCount
    )

    if ($PhysicalCoreCount -lt 1) {
        # The fallback rule is the logical processor count with a ceiling of eight. Name whichever
        # of the two set the number, the same way the measured branch below does. A fixed "capped
        # at eight" misleads on a machine with fewer than eight logical processors, where the count
        # equals the processor count and the ceiling never bit. Backlog 145 review, finding 4.
        $fallback = Get-DefaultSuiteWorkerCount -PhysicalCoreCount $PhysicalCoreCount -LogicalProcessorCount $LogicalProcessorCount

        if ($fallback -eq 8) {
            return "physical cores unreadable, $LogicalProcessorCount logical processors capped at the ceiling of eight"
        }

        if ($fallback -eq $LogicalProcessorCount) {
            return "physical cores unreadable, $LogicalProcessorCount available processors"
        }

        return "physical cores unreadable, $LogicalProcessorCount logical processors raised to the floor of one"
    }

    $noun = if ($PhysicalCoreCount -eq 1) { 'physical core' } else { 'physical cores' }
    $rule = "75% of $PhysicalCoreCount $noun"

    $share = Get-PhysicalCoreShare -PhysicalCoreCount $PhysicalCoreCount
    $count = Get-DefaultSuiteWorkerCount -PhysicalCoreCount $PhysicalCoreCount -LogicalProcessorCount $LogicalProcessorCount

    if ($count -eq $share) {
        return $rule
    }

    if ($count -gt $share) {
        return "$rule is $share, raised to the floor of one"
    }

    # Both bounds can be below the share at once. Name the one that equals the answer, and prefer
    # the processor limit: it is the surprising one, and the ceiling is documented everywhere else.
    if ($count -eq $LogicalProcessorCount) {
        return "$rule is $share, capped at $LogicalProcessorCount available processors"
    }

    return "$rule is $share, capped at the ceiling of eight"
}

# Counts physical cores in the text of /proc/cpuinfo. Kept apart from the file read so a Windows
# host can test the Linux rule against a fixture string.
#
# Linux lists one block per hardware thread. Two threads on one core share a core id and a
# physical id, so the number of distinct pairs is the number of physical cores. The core id alone
# is not enough: core 0 exists on every socket.
#
# Text that names no pair returns zero, which the caller reads as unknown. An ARM board is the
# common case: it lists processors and no core id, and nothing in the file says how many physical
# cores sit behind them. Guessing there would be worse than falling back.
function ConvertFrom-ProcCpuInfoCoreCount {
    param([string] $Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return 0 }

    $pairs = [System.Collections.Generic.HashSet[string]]::new()
    $physicalId = $null
    $coreId = $null

    # A trailing empty line is appended so the last block is recorded even when the file ends
    # without one. Splitting on blank lines instead would drop a block whose file ends abruptly.
    foreach ($line in (($Text -split "`r?`n") + @(''))) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            if ($null -ne $physicalId -and $null -ne $coreId) {
                [void] $pairs.Add("$physicalId/$coreId")
            }

            $physicalId = $null
            $coreId = $null
            continue
        }

        if ($line -match '^\s*physical id\s*:\s*(\S+)\s*$') { $physicalId = $Matches[1] }
        elseif ($line -match '^\s*core id\s*:\s*(\S+)\s*$') { $coreId = $Matches[1] }
    }

    return $pairs.Count
}

# -Query and -ReadCpuInfo below are test seams. Each defaults to the real machine, so a caller
# never passes one. A test does, because the real machine always answers: without a stand-in there
# is no way to reach the catch blocks, and 'returns zero rather than throwing' would be a promise
# nothing checks. Backlog 145 review, finding 2.
function Get-WindowsPhysicalCoreCount {
    param([scriptblock] $Query = { Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop })

    try {
        # NumberOfCores is per processor package, so a two-socket machine needs the sum.
        $sum = (& $Query | Measure-Object -Property NumberOfCores -Sum).Sum
        if ($null -ne $sum -and $sum -ge 1) { return [int] $sum }
    } catch {
        # A locked-down machine can refuse the CIM query. Unknown, not fatal.
    }

    return 0
}

function Get-LinuxPhysicalCoreCount {
    param([scriptblock] $ReadCpuInfo = { Get-Content -LiteralPath '/proc/cpuinfo' -Raw -ErrorAction Stop })

    try {
        $text = & $ReadCpuInfo
    } catch {
        return 0
    }

    return (ConvertFrom-ProcCpuInfoCoreCount -Text $text)
}

# The machine's physical core count, or zero when it cannot be read. Never throws: a run must not
# fail because a machine would not answer a question about itself.
#
# This counts hardware that exists. It is not the number of processors this run may use, which
# affinity and container limits can lower. Get-DefaultSuiteWorkerCount caps by that separately.
#
# macOS returns zero. Get-CurrentSuitePlatform above throws on macOS before a run reaches here, so
# that path is only reachable from a test that calls this function directly.
function Get-PhysicalCoreCount {
    if ([System.IO.Path]::DirectorySeparatorChar -eq '\') {
        return (Get-WindowsPhysicalCoreCount)
    }

    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Linux)) {
        return (Get-LinuxPhysicalCoreCount)
    }

    return 0
}
