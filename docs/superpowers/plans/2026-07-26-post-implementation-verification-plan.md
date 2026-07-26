# Post-Implementation Verification — plan

## Context

Agents in this repo finish implementing a feature and report done without ever exercising it. Bugs
then get found by a review agent, or by you. The rule meant to prevent this exists but does not fire.

Three concrete reasons, all found by audit:

1. **The rule cancels itself.** `AGENTS.md:117` ends `…or when asking is clearly easier or faster.`
   Asking you is always faster for the agent, so the clause licenses skipping verification in every
   case the sentence was written to prevent. Git history shows a stronger draft (`Don't ask the user
   to test manually what you can verify yourself`) was added in `ae19f0d` and deleted minutes later
   by the dedupe commit `00216db`. The weak version survived.
2. **`dck-verify` never runs the app.** Its 7 phases are build, diagnostics, antipatterns, tests,
   security, format, diff. No runtime, no browser, no mention of Playwright or `AHKFlowApp.E2E.Tests`.
   An agent that runs "all 7 phases" prints `Verdict: READY` with zero runtime evidence. Its trigger
   is also strictly `before commit, push, or PR` — it never fires on "implementation finished".
3. **No routing rule exists.** Nothing anywhere branches on what surface changed to pick a
   verification mode. The strongest version of the rule lives in an untracked user memory file
   (`feedback_branch_completion_pr_default.md:17`) which Codex and Copilot never see, and it says
   *offer* a smoke pass, not *perform* one.

Compounding it: `AGENTS.md` stopped naming `AHKFlowApp.E2E.Tests` two days ago (`2e888e5`), so
"Playwright" in agent instructions now means only ad-hoc `playwright-cli` driving — while the repo
actually has 11 mature E2E flow classes. And five documents define five different pre-PR gates with
no cross-references.

**Outcome wanted:** verification happens as part of implementing, routed by surface, with a durable
test as the default artifact — so regressions are caught by the suite, not by a reviewer.

## Assets to reuse (do not build new)

| Asset | Path | Use |
|---|---|---|
| E2E flow suite | `tests/AHKFlowApp.E2E.Tests/*FlowTests.cs` (11 classes) | Template for new flow tests |
| E2E stack fixture | `tests/AHKFlowApp.E2E.Tests/Fixtures/StackFixture.cs` | API+SPA+browser, `ResetDataAsync()` per test |
| E2E test shape | `HotkeysCrudFlowTests.cs` | `[Collection(E2ETestCollection.Name)]`, `data-test` selectors, `.desktop-branch` scoping |
| Test slice runner | `scripts/test-fast.ps1` (`-Mode Fast\|Integration\|E2E\|Coverage`) | Every command in the routing table |
| Layer→slice routing | `docs/development/testing-workflow.md` | Becomes canonical gate owner |
| Manual-steps format | `AGENTS.md:119-125` | Absorbed, not rewritten |
| Skill parity tests | `tests/SkillParity.Tests.ps1`, `tests/CodexSkillsHashParity.Tests.ps1` | Verifies this plan's own `.agents/` edits |

## Task 1 — `AGENTS.md`: replace `## Manual Testing Requests`

Rename to `## Verification After Implementation`. Same slot in the file.

- **Trigger, stated explicitly:** fires when implementation of a feature, fix, or plan task
  completes — *before reporting it done*, not only before commit/push/PR.
- **Delete** the clause `or when asking is clearly easier or faster.`
- **Add the routing table** (below).
- **Add the three exemptions** and the refactor fence (below).
- **Absorb** the existing manual-steps checklist (preconditions / numbered steps / verbatim input /
  expected result / per-step feedback) as the sub-block for when manual steps *are* the answer.
- **Re-name `AHKFlowApp.E2E.Tests`** — it went missing in `2e888e5` and this rule depends on agents
  knowing it exists.
- **Link** `docs/development/testing-workflow.md` as the canonical gate.

Routing table — the default artifact is a **durable test**, ad-hoc driving is the fallback:

| Surface changed | Verification artifact | Command |
|---|---|---|
| Blazor UI flow, assertable | Add/extend a `*FlowTests.cs` in `tests/AHKFlowApp.E2E.Tests` | `pwsh .\scripts\test-fast.ps1 -Mode E2E` |
| UI, visual or exploratory only | Drive the running app with the `playwright-cli` skill, capture a screenshot | Worktree ports — read the worktree's `launchSettings.json` |
| API, use case, EF Core | Integration test (`Category=Integration` trait, or `API.Tests`) | `-Mode Integration` |
| CLI behavior | `CLI.Tests` integration flow | `-Mode Integration` |
| Emitted `.ahk` output | Emitter assertion on the generated text. Numbered manual steps for the user **only when the change emits a construct the repo has not shipped before** — new option flag, new escaping path, new action kind. Running `.ahk` is out of scope, so the assertion is the contract for already-proven constructs | `-Mode Fast`, plus manual steps for new constructs |
| Domain rule, validator | Unit test | `-Mode Fast` |
| Real Azure AD login, visual judgment call | Numbered manual steps for the user | — |

Exemptions — the only cases that skip runtime verification:

1. Docs, skills, or plan files only — no code compiled. Targeted text checks + diff review.
2. Internal-only change with no observable surface — no UI, no API contract, no emitted `.ahk`
   change, no schema change.
3. Pure refactor with no behavior change — **fenced**: to claim this the agent must name which
   existing tests cover the changed code and paste their fresh pass output. No named coverage, no
   exemption; runtime verification is required instead.

State the verdict either way. Naming an exemption is allowed; silence is not.

## Task 2 — `.agents/dck-verify/SKILL.md`: add the runtime phase

- **`description`** — add "after implementing a change" alongside `before commit, push, or PR`, so
  the skill fires at the point the gap exists.
- **New Phase 8 — Runtime / UI Verification.** Routes via the Task 1 table; for UI that means an
  E2E flow test run through `test-fast.ps1 -Mode E2E`, not an ad-hoc browser drive. Ends with the
  artifact named (test path, or screenshot, or the manual steps handed over).
- **`## 7-Phase Pipeline` → `## 8-Phase Pipeline`**; update the Phase Selection table:
  - `Feature, refactor, pre-PR` → All 8
  - `Bug fix` → **Phase 8 mandatory when the bug had an observable symptom** — re-run the original
    repro and show it gone. This is the exact gap that let the Win+Arrow snap fix ship twice without
    working. Non-observable/internal bugs stay on build, diagnostics, tests, diff.
  - `Skill/docs only` → exemption 1
- **Phase 4 (Tests)** — replace the raw `dotnet test` block with the `test-fast.ps1` modes and link
  `testing-workflow.md` as canonical. The skill currently never mentions `test-fast.ps1`,
  `run-coverage.ps1`, or coverage thresholds at all.
- **Final Report** — add a `Runtime` row. `Verdict: READY` is not allowed with `Runtime = SKIP`
  unless a named exemption appears in the Evidence cell.

## Task 3 — canonical pre-PR gate in `docs/development/testing-workflow.md`

The five competing definitions collapse into one. `testing-workflow.md` owns it.

- Add a `## Canonical pre-PR gate` section naming the one sequence, in order, with the commands it
  already documents.
- Point these four at it, deleting their local command lists:
  - `AGENTS.md:200` — `Run dotnet build + dotnet test before creating a PR`
  - `docs/development/coverage.md:3` — currently claims the title "Canonical local verification"
  - `.github/PULL_REQUEST_TEMPLATE.md` — its own 4-item checklist
  - `.agents/dck-verify/SKILL.md` — via the Task 2 Phase 4 edit

## Task 4 — unbreak the browser-verification path

The path Task 1 mandates is currently broken in two places.

- **`docs/development/playwright-setup.md:34-39`** hardcodes `5601`/`5600` as *the* URLs. Agents work
  in worktrees (mandatory for Git mutations, `AGENTS.md:203-207`) which use offset ports — following
  this doc hits the main checkout or a dead port. Mark the table main-checkout-only and point to the
  worktree's own `launchSettings.json`, matching `AGENTS.md:177-179`.
- **`.agents/playwright-cli/SKILL.md`** is 328 lines of vendored generic Playwright CLI reference with
  zero AHKFlowApp content and a generic trigger. Don't rewrite the vendored body — prepend a short
  project-context block: worktree offset ports, the no-auth test provider (`Auth:UseTestProvider=true`,
  always signed in as "Test User"), **prefer an E2E flow test over an ad-hoc drive**, and links to the
  `AGENTS.md` section plus `testing-workflow.md`. Update `description` to fire on project UI
  verification, not just "local web pages".
- **`.claude/CLAUDE.md:12-13`** duplicates the browser-verification rule that `ae19f0d` moved to
  `AGENTS.md` — the move left these behind. Collapse to one pointer at the new `AGENTS.md` section.
  Keep the "don't claim a capability is unavailable without checking `.claude/skills/`" half; it is
  a separate, still-useful guard.

## Task 5 — reactivate `dck-testing` as the test-writing skill

The plan mandates writing tests; the repo already has a 341-line templates skill that nothing loads
because it is named `REFERENCE.md` instead of `SKILL.md`. Its frontmatter is already valid
(`name: dck-testing`, description covering xUnit / WebApplicationFactory / Testcontainers / bUnit).

- **Rename** `.agents/dck-testing/REFERENCE.md` → `SKILL.md`.
- **Refresh the stale test-project list** (`REFERENCE.md:16-25`) — it predates `AHKFlowApp.E2E.Tests`,
  `AHKFlowApp.CLI.Tests`, and `AHKFlowApp.TestUtilities`, all of which exist now.
- **Add an E2E flow-test template** modeled on `tests/AHKFlowApp.E2E.Tests/HotkeysCrudFlowTests.cs`:
  `[Collection(E2ETestCollection.Name)]`, `StackFixture` injection, `ResetDataAsync()` in
  `InitializeAsync`, `data-test` selectors, and `.desktop-branch` scoping so a selector cannot match
  both the desktop and mobile branch. This is the artifact the Task 1 routing table demands most
  often, so the template carries the most weight.
- **Cross-link** to `testing-workflow.md` for which slice to run, and to the `AGENTS.md` section for
  when to write which kind of test.
- **Trim overlap** with `AGENTS.md` Testing — the skill keeps code templates, `AGENTS.md` keeps the
  principles. Don't restate the anti-patterns in both.

## Task 6 — dedupe the user memory

`feedback_branch_completion_pr_default.md:17` holds the strongest wording of this rule but says
*offer* a smoke pass at recommendation level "recommended". Once `AGENTS.md` says *do it*, the memory
contradicts the repo and only Claude Code can see it.

Slim it to the push+PR fact it is named for, and replace the smoke-pass paragraph with a pointer to
the `AGENTS.md` section. Keep the Debug-vs-Release gotcha — that one is a real trap and now also
lives in `AGENTS.md` Testing from commit `4a846d1`, so make the memory defer rather than restate.

## Not doing

- **Stop hook gate.** You chose docs-only. The pre-push hook already runs build+tests, your insights
  report flagged slow-hook friction, and a Stop hook cannot tell whether *UI* verification happened —
  it would give false assurance.
- **Consolidating the `AGENTS.md` Testing section into `testing-workflow.md`.** Tempting while
  reshuffling testing docs, but `AGENTS.md` is read unconditionally by every agent and the principles
  belong there. Only command detail moves out.

## Commits

Branch `docs/wt-verification-routing`, worktree `.claude/worktrees/verification-routing` — both
already created. This plan is already committed there as `7345fa2`
(`docs/superpowers/plans/2026-07-26-post-implementation-verification-plan.md`), so execution starts
at commit 2 below.

1. ~~plan doc~~ — landed, `7345fa2`
2. `docs: route verification by surface after implementation` — Task 1
3. `docs: add runtime phase to dck-verify` — Task 2
4. `docs: one canonical pre-PR gate` — Task 3
5. `docs: fix worktree ports + playwright-cli project context` — Task 4
6. `docs: reactivate dck-testing with E2E template` — Task 5

Task 6 (memory dedupe) is a user-config edit outside the repo, not a commit. Per the standing rule on
`~/.claude` changes, flag it for the user to commit in their own config repo.

Amend `7345fa2` if the answers below change the plan text, so the committed plan matches what ships.

Separate and unrelated: the `docs/wt-insights-rules` worktree from earlier this session holds
`4a846d1` (root-cause + smoke-test + laptop-key rules), still unpushed. `git worktree prune` also
needs running — the dead `wt-hotkey-type-filter` registration errors on every worktree creation.

## Verification

This plan's own changes are docs + skills only, so **exemption 1 applies** — and the exemption still
has to produce evidence:

1. `pwsh ./scripts/agents/setup-cross-agent-skills.ps1` — required after any `.agents/` change;
   expect a `[DONE]` line. Skips silently wrong without it.
2. `pwsh -NoProfile -File tests/SkillParity.Tests.ps1` and
   `pwsh -NoProfile -File tests/CodexSkillsHashParity.Tests.ps1` — prove the `dck-verify`,
   `playwright-cli`, and newly-activated `dck-testing` edits propagated to `.claude/skills/` and
   `.github/skills/`. `dck-testing` is the one that can actually fail here: it has never had a
   `SKILL.md`, so it has no symlink in either mirror yet.
3. `git diff --check` plus a read-through of each changed file.
4. Grep that no orphan cross-references remain: search for `clearly easier or faster`,
   `7-Phase`, and `Manual Testing Requests` — all three strings should be gone repo-wide.
5. Confirm `AHKFlowApp.E2E.Tests` appears in `AGENTS.md` again.

**Dogfood check:** after landing, the next UI change in this repo should produce a new or extended
`*FlowTests.cs` without being asked. If it does not, the rule still is not firing and the wording
needs another pass.

## Decisions locked

Nothing outstanding. Settled during planning:

- Frontend default artifact is an E2E flow test; `playwright-cli` driving only for visual/exploratory
  checks; manual steps only for real Azure AD, visual judgment, or an AHK runtime run.
- Docs-only enforcement — no Stop hook.
- Three exemptions, with the refactor one fenced by named covering tests plus fresh green output.
- `testing-workflow.md` owns the single canonical pre-PR gate; four other definitions link to it.
- `dck-testing` reactivated as the test-writing templates skill, refreshed with an E2E template.
- Manual AHK checklist only for constructs the repo has not emitted before.
- Phase 8 mandatory for bug fixes that had an observable symptom.

One risk worth naming: this plan fixes wording, and wording already failed once here — the strong
draft was deleted by a dedupe commit minutes after it landed. The dogfood check above is the only real
proof. If the next UI change does not produce a flow test unprompted, the fix did not take.
