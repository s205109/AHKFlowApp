export const meta = {
  name: 'test-audit',
  description: 'Audit PowerShell Suites or .NET test Candidate groups case by case, then try to refute every REMOVE and MERGE (backlogs 188 and 194)',
  whenToUse: 'Pass args { worktree, suites: ["X.Tests.ps1", ...] } for PowerShell, or args { worktree, kind: "dotnet", groups: [...], timings } for .NET. At most five Suites or groups per run.',
  phases: [
    { title: 'Audit', detail: 'one read-only auditor per Suite or Candidate group, in parallel' },
    { title: 'Refute', detail: 'one medium-effort refuter per Suite or group with claims to refute, one at a time' },
  ],
}

const W = args && args.worktree
if (!W) throw new Error('Pass args.worktree: the absolute path of the worktree to audit.')
const KIND = (args && args.kind) || 'powershell'
if (KIND !== 'powershell' && KIND !== 'dotnet') throw new Error(`args.kind must be 'powershell' or 'dotnet', not '${KIND}'.`)
const DOTNET = KIND === 'dotnet'
const RESEARCH = W + '\\docs\\superpowers\\specs\\2026-10-18-speed-up-the-development-cycle-research-188\\'
const REPORT = (args && args.report) || RESEARCH + (DOTNET ? 'dotnet-tests.md' : 'powershell-suites.md')
const TIMINGS = args && args.timings
const RUN = (suite) => `pwsh -NoProfile -WorkingDirectory ${W} -Command "& ./scripts/run-powershell-suites.ps1 -Suite ${suite}; exit $LASTEXITCODE"`
const RUN_TEST = (project) => `dotnet test ${W}\\${project} --configuration Release --filter "<filter>"`
// Lean settings, chosen at stop S5 of backlog 188 to spend fewer tokens than its batch 1 (1.72 M).
const MIN_SAVED = 0.5
// .NET mode refutes every MERGE the auditor returns (backlog 194, spec D6).
const MIN_MERGE_SAVED = DOTNET ? MIN_SAVED : 1

const units = DOTNET ? (args.groups || []) : (args.suites || [])
if (DOTNET && (units.length === 0 || units.length > 5)) throw new Error('Pass args.groups with one to five Candidate groups.')
if (!DOTNET && (units.length === 0 || units.length > 5)) throw new Error('Pass args.suites with one to five Suite file names.')
const unitName = (u) => (DOTNET ? u.name : u)

const AUDIT_SCHEMA = {
  type: 'object',
  properties: {
    suite: { type: 'string' },
    cases: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          name: { type: 'string' },
          verdict: { type: 'string', enum: ['KEEP', 'REWORK', 'MERGE', 'REMOVE', 'SPEED UP'] },
          evidence: { type: 'string' },
          secondsSaved: { type: 'number' },
        },
        required: ['name', 'verdict', 'evidence', 'secondsSaved'],
      },
    },
  },
  required: ['suite', 'cases'],
}

const verdictProperties = {
  name: { type: 'string' },
  claim: { type: 'string' },
  upheld: { type: 'boolean' },
  evidence: { type: 'string' },
}
if (DOTNET) {
  verdictProperties.auditedTestFailed = { type: 'boolean' }
  verdictProperties.behaviourGone = { type: 'boolean' }
}

const REFUTE_SCHEMA = {
  type: 'object',
  properties: {
    suite: { type: 'string' },
    verdicts: {
      type: 'array',
      items: {
        type: 'object',
        properties: verdictProperties,
        required: Object.keys(verdictProperties),
      },
    },
    worktreeClean: { type: 'boolean' },
  },
  required: ['suite', 'verdicts', 'worktreeClean'],
}

const auditPrompt = (suite) => `You audit one PowerShell test Suite for backlog 188. You are read-only: do not edit, create or delete any file, and do not run any test.

Repository worktree: ${W} (always use absolute paths under it).
Suite: ${W}\\tests\\${suite}
Read the Suite, every script it dot-sources or calls under ${W}\\scripts, and the Suite's section in the research report ${REPORT} (sections 4 and 5 hold measured costs per case group). Start with the case groups that cost the most time.

Give every test case one verdict:
- KEEP: it catches a defect no other case catches, at a fair cost. One line of evidence is enough.
- REWORK: worth keeping, but it should test the behaviour differently.
- MERGE: it checks what another case in this Suite (or another Suite) already checks; name that case.
- REMOVE: it catches no defect that another test does not already catch, or it tests a feature that no longer exists. Name the test that still catches the regression, or the behaviour that is gone.
- SPEED UP: keep the check, but make it cheaper; say how (for example a shared fixture, fewer git repos, a smaller sleep).
REMOVE, MERGE and SPEED UP need case-level evidence with file:line. secondsSaved is your estimate from the report's measured costs.
Return only the cases you would change and that save at least ${MIN_SAVED} s. Leave out every KEEP and every smaller change. Keep each evidence to two sentences.
Leave tests\\WorktreeRemoveHook.Tests.ps1 alone (backlog 068 is open).`

const refutePrompt = (suite, claims) => `You are the refuter for one PowerShell test Suite in backlog 188. An auditor claims some cases can be removed or merged. Your job is to DISPROVE each claim if you can.

Repository worktree: ${W}. Your shell starts in the main checkout, so always name files by absolute path under the worktree, and never edit anything outside it.
Suite: ${W}\\tests\\${suite}

Claims to test (JSON):
${JSON.stringify(claims, null, 2)}

Method: load the dotnet-test:test-value-evidence skill with the Skill tool and apply its method to PowerShell. For each claim:
1. Find the defect the case guards against. Put that bug back into the script under test, or switch the feature off, with the smallest edit.
2. Find the Suites that name the changed script: search ${W}\\tests for the script's file name.
3. Run those Suites one at a time, with the case under audit removed or skipped in your mind, and read which cases fail. Command per Suite:
   ${RUN('<Suite file name>')}
4. upheld = true when another case still fails on the bug (or the behaviour is truly gone), so removing or merging loses nothing. upheld = false when only the audited case catches it. Evidence names the failing case, or says that nothing else failed.
5. Restore the script at once: git -C ${W} checkout -- <path>. Never commit, stash, reset or push.

Before you return, run git -C ${W} status --porcelain and set worktreeClean to true only when it prints nothing. Leave tests\\WorktreeRemoveHook.Tests.ps1 alone.`

const timingsLine = TIMINGS
  ? `Timings file: ${TIMINGS}. It lists every test with its median duration over five counted runs of today's tree. Read secondsSaved from it, never from the report.`
  : 'No timings file was passed. Estimate secondsSaved from the measured costs in the report, and say so in the evidence.'

const dotnetAuditPrompt = (g) => `You audit one Candidate group of .NET tests for backlog 194. You are read-only: do not edit, create or delete any file, and do not run any test.

Repository worktree: ${W} (always use absolute paths under it).
Test project: ${W}\\${g.project}
Test classes in this group: ${g.classes.join(', ')}
Read each class, the fixtures it uses, and the app code it exercises. Read this project's part of the research report ${REPORT}. Its line numbers describe an older tree, so check every claim against today's code.
${timingsLine}

Candidates from the triage (re-check each one; they are leads, not verdicts):
${g.candidates.map((c) => '- ' + c).join('\n')}

Give each test one verdict:
- KEEP: it catches a defect no other test catches, at a fair cost.
- REWORK: worth keeping, but it should test the behaviour differently.
- MERGE: another test already checks the same thing; name that test. A MERGE moves the absorbed test's assertions into the other test.
- REMOVE: no defect is lost, because another test still catches it, or the feature is gone.
- SPEED UP: keep every assertion, but make the test cheaper; say how (for example a shared page, a shorter wait, a moved Collection).
A change that drops an assertion, or a step that an assertion depends on, is never a SPEED UP. It is a REMOVE or a MERGE.
Each REMOVE and MERGE names the test that still catches the defect, with file:line. Each SPEED UP says how, with file:line.
Name every test as Class.Method. Return only the changes that save at least ${MIN_SAVED} s. Leave out every KEEP and every smaller change. Keep each evidence to three sentences.`

const dotnetRefutePrompt = (g, claims) => `You are the refuter for one Candidate group of .NET tests in backlog 194. An auditor claims some tests can be removed or merged. Your job is to DISPROVE each claim if you can.

Repository worktree: ${W}. Your shell starts in the main checkout, so always name files by absolute path under the worktree, and never edit anything outside it.
Test project: ${W}\\${g.project}
No API or UI of this worktree may run while you work: a running app locks the Release build.

Claims to test (JSON):
${JSON.stringify(claims, null, 2)}

The test command. Use this one form for every run, with the project of the test you run:
   ${RUN_TEST(g.project)}
The filter is FullyQualifiedName~<Class>.<Method>. Never add --no-build: the build must carry your change into the app. With no shared connection string, a SQL-backed test starts its own SQL Server container. Do not set one.
Run nothing in parallel. Run one command at a time.

Method: load the dotnet-test:test-value-evidence skill with the Skill tool and apply its method. For each claim, in order:
1. Find the defect the audited test guards against. Put that defect back with the smallest edit to the app code, or switch the feature off.
2. Run the audited test. The audited test must fail first. If it passes, your edit is not the defect it guards against: undo it and try another edit. Set auditedTestFailed to true only when the audited test failed on your edit.
3. Run the tests the auditor names as still catching the defect, one at a time.
4. upheld = true when at least one of them fails on the same edit, or when the behaviour is really gone. upheld = false when only the audited test catches it. upheld may be true with auditedTestFailed false only when the behaviour is gone. Then set behaviourGone to true, and the evidence must say so. Otherwise set behaviourGone to false.
5. Restore the file at once: git -C ${W} checkout -- <path>. Then build Release again: dotnet build ${W}\\${g.project} --configuration Release. Never commit, stash, reset or push.

A failure counts only when its message names the changed behaviour. An E2E timeout on an unrelated step is a flaky result: run that test once more, and say so in the evidence.
Evidence names the edit (file:line), the failing tests and their messages, or says that nothing else failed.

Before you return, run git -C ${W} status --porcelain and set worktreeClean to true only when it prints nothing.`

phase('Audit')
// Barrier on purpose: refuters edit files in the shared worktree, so every auditor must finish reading first.
const audits = (await parallel(units.map((u) => () =>
  agent(DOTNET ? dotnetAuditPrompt(u) : auditPrompt(u), { label: `audit:${unitName(u)}`, phase: 'Audit', schema: AUDIT_SCHEMA })
    .then((a) => (a ? { unit: u, ...a } : null))
))).filter(Boolean)
log(`${audits.length} of ${units.length} audits returned`)

phase('Refute')
const refutes = []
for (const a of audits) {
  const name = unitName(a.unit)
  const claims = a.cases.filter((c) => c.verdict === 'REMOVE' || (c.verdict === 'MERGE' && c.secondsSaved >= MIN_MERGE_SAVED))
  const skipped = a.cases.filter((c) => c.verdict === 'MERGE' && c.secondsSaved < MIN_MERGE_SAVED).length
  if (skipped > 0) log(`${name}: ${skipped} MERGE claims under ${MIN_MERGE_SAVED} s not refuted`)
  if (claims.length === 0) {
    log(`${name}: no REMOVE or MERGE claims to refute, no refuter`)
    continue
  }
  // One refuter at a time: they share one worktree, its Release build and its Lane pool.
  const prompt = DOTNET ? dotnetRefutePrompt(a.unit, claims) : refutePrompt(a.unit, claims)
  const r = await agent(prompt, { label: `refute:${name}`, phase: 'Refute', schema: REFUTE_SCHEMA, effort: 'medium' })
  if (!r) {
    log(`${name}: refuter returned nothing; its claims stay unrefuted`)
    continue
  }
  if (DOTNET) {
    // A claim is upheld only when the audited test failed, or when the behaviour is gone.
    for (const v of r.verdicts.filter((v) => v.upheld && !v.auditedTestFailed && !v.behaviourGone)) {
      v.upheld = false
      v.unverified = true
      log(`${name}: ${v.name} was upheld, but its audited test never failed and the behaviour is not gone. It is unverified, not upheld.`)
    }
  }
  refutes.push(r)
  // The next refuter would test against this refuter's leftover edit, so the run stops here.
  if (!r.worktreeClean) {
    log(`${name}: the refuter left the worktree changed. The run stops; the groups after it were not refuted. Check git status before anything else.`)
    return { kind: KIND, audits, refutes, interrupted: name }
  }
}

return { kind: KIND, audits, refutes }
