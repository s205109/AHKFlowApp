# 074 - Process wave 4 - CI routing for config-only changes

## Metadata

- **Epic**: Development process
- **Type**: Process / CI
- **Interfaces**: none (CI workflows, pre-push hook)
- **Difficulty**: complex
- **Stage**: 3-plan
- **Depends on**: 078-ci-config-only-route

## Summary

Wave 4 of the development process. CI and the pre-push hook build and test the .NET side even
when a branch has no Code change. This wave adds seven exclusions to the shared path filter,
`.github/code-paths-filter.yml`. It also makes the pre-push hook read that filter, so a push
with no Code change skips the build and the fast tests.

## User story

As a contributor, I want CI and my push to skip the .NET build and tests when my branch has no
Code change, so that CI spends no runner minutes, and my push spends no build time, on a change
the .NET build cannot see.

## Acceptance criteria

- [ ] The 074 spec replaces the 078 spec. It extends the shared path filter instead of building
      a new router. This item ships that design.
- [ ] CI and the pre-push hook both skip the .NET build and tests when every changed path
      matches an exclusion.
- [ ] Fixture tests prove each new exclusion, and prove both the skip and the run path of the
      pre-push hook.
- [ ] A Check fails when `ci.yml` or the pre-push hook stops reading
      `.github/code-paths-filter.yml`.

## Out of scope

- Routing the `powershell-suites` CI job. It takes about nine minutes on every pull request, so
  it sets the waiting time. The 074 spec records the measurement.
- A workflow linter. Every workflow file keeps counting as code, so the full .NET checks still
  run on a workflow change.
- Skipping the Gate's build and format steps.

## Notes / dependencies

- Spec: `docs/superpowers/specs/2026-09-15-ci-config-only-route-design-074.md` (private plans
  repo). It replaces `docs/superpowers/specs/2026-08-14-ci-config-only-route-design.md`.
- Plan: `docs/superpowers/plans/2026-09-16-ci-config-only-route-plan-074.md`
- Spec carrier for the replaced design: `backlog/done/078-ci-config-only-route.md`, closed
  2026-08-14.
- Parent spec: `docs/superpowers/specs/2026-08-10-development-process-design-071.md`
  §2 (P6) and §13.
- Reworded at Design on 2026-09-15. The 078 spec came before backlogs 119 and 141, which
  shipped `.github/code-paths-filter.yml`. By then 31 of the last 60 merged pull requests
  already skipped the .NET checks in CI. The 078 router would have added 2 more. Seven new
  exclusions add 10, with a much smaller change. So the item changed in five places:
  - The user story said the wait was the .NET build. The wait is the `powershell-suites` job,
    which this item does not change. The story now names runner minutes and push time.
  - Criterion 1 named the 078 design, which this item no longer ships.
  - Criterion 2 said "local gate". The Gate is the five steps before a pull request goes ready.
    The local caller here is the pre-push hook.
  - Criterion 3 said "the route". No router exists in this design.
  - Criterion 4 compared two allowlists. There is one filter file, so the Check proves that
    both callers read it.
- Target: fewer runner minutes and less pre-push time on branches with no Code change. That is
  a direction, not a percentage: backlog 072 has no established baseline yet.
