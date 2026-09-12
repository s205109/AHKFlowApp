# An E2E page is opened only through the diagnosed helper

No test in `tests/AHKFlowApp.E2E.Tests` calls `NewPageAsync`. Every First page load goes through
`FirstPageLoad.OpenAsync`, which waits for the App shell, the Boot error screen, or the Startup
error screen, and throws a message carrying the whole diagnosis when none of them arrives.

A `[Fact]` in that same project reads the project's own source and fails a file that breaks the
rule. A class that must open a page without diagnosis carries an inert attribute,
`OpensPagesWithoutDiagnosis`, with a reason string. `BootFailureFlowTests` is the only class that
carries it today.

The reason is that a bare Playwright timeout says nothing. Twice now a CI failure has cost a person
an afternoon of reading logs from a different process to learn that the app never started. The
helper that collects the evidence was written after the first time, and was used by 2 test methods
out of many when the second time happened.

## Considered options

**A base class that every test class inherits, reporting during disposal.** Rejected. The xUnit
version this repository uses tells a test class nothing about its own result, so the base class
would have to guess from the page state, and it could only write to test output. The reader then
meets the bare timeout first and the diagnosis second, which is the exact failure this decision is
about. It also touches every test class anyway, because each one needs an output helper in its
constructor, so it saves no work.

**Both, the helper and a base class.** Rejected. Two mechanisms producing one report, each able to
rot without the other noticing.

**Leaving the helper optional and documenting it.** Rejected. That is the state that produced the
second failure. The helper already existed and was already documented.

**A Pester suite for the check, in `tests/powershell-suites.json`.** Rejected, though it is where
every other convention check in this repository lives. `.githooks/pre-push.ps1` runs the Fast slice
and not the PowerShell suites, so the suite would stay silent until CI. The person who breaks this
rule is writing an E2E test and running the E2E slice, and that is the moment to tell them.

**Making it impossible instead of checked, by not handing tests a browser context.** Rejected. The
tests that break the boot on purpose need the raw context for fault injection, so an escape hatch
would exist anyway, and the escape hatch then needs the same check.

## Consequences

**The check reads source as text.** It is the only C# test in this repository that does. A rename
of `NewPageAsync` by Playwright would make the check pass while checking nothing, and only a
failing conversion would reveal it. The test that proves the check fails an offender is what keeps
this honest.

**The exemption is read per file.** Every file in the project holds exactly one test class today.
The check asserts that fact rather than assuming it, so a file that grows a second class fails
loudly instead of being exempted silently.

**The helper owns the window before navigation, so it has to sell it back.** A test that must watch
network traffic caused by the first page load cannot register the watch itself: the page does not
exist until inside the helper, and by the time the helper returns the response may already have
arrived. `OpenAsync` therefore takes the API paths to wait for and registers them between creating
the page and navigating. That ordering is a contract, not an implementation detail, and a
regression test asserts it. Any future need for a pre-navigation subscription — a console listener,
a route, a dialog handler — hits the same wall and needs the same treatment.

**Two waits, two budgets.** `OpenAsync` caps the App shell wait at its own budget, and the test's
own wait afterwards keeps Playwright's default. This is not new: a test that navigates and then
waits for a selector already has two budgets. It does mean the helper's budget is not a cap on the
whole test.

**The app gained two test markers.** `MudLayout` carries the App shell marker and `StartupError`
carries its own marker and reason. The E2E suite now depends on both, so removing either breaks
tests rather than silently weakening the diagnosis. That is the intended trade.

**A new failure screen must be added in three places.** The screen itself, the race inside
`OpenAsync`, and the sentence in the report. Nothing enforces this. A screen that is added and not
wired up is reported as "nothing reported a failure", which is the blind spot this decision closed
for the Startup error screen and can reopen for the next one.
