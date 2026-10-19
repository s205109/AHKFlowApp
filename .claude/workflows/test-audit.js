export const meta = {
  name: 'test-audit',
  description: 'Audit PowerShell Suites case by case, then try to refute every REMOVE and MERGE (backlog 188)',
  whenToUse: 'Pass args { suites: ["X.Tests.ps1", ...] }, at most five Suites per run.',
  phases: [
    { title: 'Audit', detail: 'one read-only auditor per Suite, in parallel' },
    { title: 'Refute', detail: 'one refuter per Suite with REMOVE or MERGE claims, one at a time' },
  ],
}

const W = 'C:\\Dev\\segocom-github\\AHKFlowApp\\.claude\\worktrees\\wt-speed-up-the-development-cycle'
const REPORT = W + '\\docs\\superpowers\\specs\\2026-10-18-speed-up-the-development-cycle-research-188\\powershell-suites.md'
const RUN = (suite) => `pwsh -NoProfile -WorkingDirectory ${W} -Command "& ./scripts/run-powershell-suites.ps1 -Suite ${suite}; exit $LASTEXITCODE"`
const suites = (args && args.suites) || []
if (suites.length === 0 || suites.length > 5) throw new Error('Pass args.suites with one to five Suite file names.')

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

const REFUTE_SCHEMA = {
  type: 'object',
  properties: {
    suite: { type: 'string' },
    verdicts: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          name: { type: 'string' },
          claim: { type: 'string' },
          upheld: { type: 'boolean' },
          evidence: { type: 'string' },
        },
        required: ['name', 'claim', 'upheld', 'evidence'],
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
REMOVE, MERGE and SPEED UP need case-level evidence with file:line. secondsSaved is your estimate from the report's measured costs; use 0 for KEEP.
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

phase('Audit')
// Barrier on purpose: refuters edit scripts in the shared worktree, so every auditor must finish reading first.
const audits = (await parallel(suites.map((suite) => () =>
  agent(auditPrompt(suite), { label: `audit:${suite}`, phase: 'Audit', schema: AUDIT_SCHEMA })
))).filter(Boolean)
log(`${audits.length} of ${suites.length} audits returned`)

phase('Refute')
const refutes = []
for (const a of audits) {
  const claims = a.cases.filter((c) => c.verdict === 'REMOVE' || c.verdict === 'MERGE')
  if (claims.length === 0) {
    log(`${a.suite}: no REMOVE or MERGE claims, no refuter`)
    continue
  }
  // One refuter at a time: they share one worktree and its Lane pool.
  const r = await agent(refutePrompt(a.suite, claims), { label: `refute:${a.suite}`, phase: 'Refute', schema: REFUTE_SCHEMA })
  if (r) refutes.push(r)
  else log(`${a.suite}: refuter returned nothing; its claims stay unrefuted`)
}

return { audits, refutes }
