# 200 - Test Results check cannot read a large trx file

## Metadata

- **Epic**: Testing infrastructure
- **Type**: Bug
- **Interfaces**: none (CI)
- **Difficulty**: to-be-determined
- **Stage**: 0-intake

> **Iceboxed. This is an observation, not a plan.** The check is not required, and every test it
> counts still passes. It becomes worth doing if the check becomes required, or if a real test
> failure is missed because the check is always red.

## Summary

On some pull requests the `Test Results` check reports failure while every test passes. The
reporter cannot read one `.trx` file, because one text node in it is too long.

## User story

As a reviewer reading a pull request, I want the `Test Results` check to be green when every
test passes, so that a red check always means a failing test.

## Acceptance criteria

- [ ] The `Test Results` check reads every `.trx` file that CI writes, with no parse error.
- [ ] The root cause, meaning which test writes the long text node, is written into this item.

## Out of scope

- Changing which checks branch protection requires.

## Notes / dependencies

- Seen on PR #460, at commits `2041cf4b` and `2c082284`. The check title read
  "1 parse errors, 3 799 pass". The annotation said: "Resource limit exceeded: Text node too long,
  try XML_PARSE_HUGE".
- PR #453 at `d1e7c5f7` shows the same error, so the cause is older than PR #460. The push run on
  `main` at `81016936` showed no error.
- The reporter is `EnricoMi/publish-unit-test-result-action/linux@v2` in
  `.github/workflows/ci.yml`. It reads `TestResults/**/*.trx`.
- A likely cause is one test that writes a very large output, kept whole in the `.trx`. This is
  not proven.
- The required checks are `build-test`, `powershell-suites`, `bicep-lint`,
  `codex-skills-hash-parity`, `repo-invariants` and `shipping-pr-closes-item`. `Test Results` is
  not one of them.
- Spec: none — iceboxed.
- Plan: none — iceboxed.
