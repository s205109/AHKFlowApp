# 109 - Design technique names a skill the agent cannot invoke

## Metadata

- **Epic**: Development process
- **Type**: Bug
- **Interfaces**: none (docs, skills, agent instructions)
- **Difficulty**: moderate
- **Stage**: 3-plan

## Summary

Stage 2 Design names `mp-grill-with-docs` as its technique, but that skill sets
`disable-model-invocation: true`, so an agent cannot call it. The agent falls
back to `mp-grilling`, which runs the interview and silently skips the
domain-modeling half. That half is where Design's exit condition "Terms and ADRs
written" comes from.

## User story

As an agent walking Stage 2 Design, I want the technique to name skills I can
actually call, so the glossary terms and the ADRs get written instead of being
skipped without anybody noticing.

## Evidence

- (`.agents/mp-grill-with-docs/SKILL.md:4`, "disable-model-invocation: true") sets
  that flag. The skill therefore never appears in an agent's skill list.
- (`.agents/mp-grill-with-docs/SKILL.md:12`, "session, using the") is the whole
  body: "Run a `/mp-grilling` session, using the `/mp-domain-modeling` skill." It
  is a wrapper over two other skills and adds nothing else.
- (`docs/development/workflow.md:335`, "mp-grill-with-docs") sets the Stage 2
  Technique. (`docs/development/workflow.md:872`, "is the Design technique")
  repeats it as a mandatory rule.
- (`.claude/CLAUDE.md:27`, "before you write code, not after") repeats it a third
  time.
- `.agents/mp-grilling/SKILL.md` mentions no docs, no ADRs, and no `CONTEXT.md`,
  so nothing in it routes an agent to the domain-modeling half.
- `.agents/mp-domain-modeling/SKILL.md` sets no `disable-model-invocation`, so an
  agent can call it directly.
- Observed on 2026-08-17 while picking up backlog 105: the session reported the
  technique as unreachable and asked which skill to substitute.

## The repo already has the answer

(`.agents/mp-triage/SKILL.md:81`, "run the `/mp-grilling` and `/mp-domain-modeling` skills together") states the model-invocable form: "run the
`/mp-grilling` and `/mp-domain-modeling` skills together — grill it into shape a
round of questions at a time, sharpening domain terms and updating
`CONTEXT.md`/ADRs inline as decisions land."

The proposed fix is to make Stage 2 name that pair, and keep
`/mp-grill-with-docs` as the human's one-word shortcut for the same pair. No
skill changes its invocation flag.

## Acceptance criteria

- [ ] Stage 2 Design names a technique an agent can call. Every place that
      states the technique agrees: (`docs/development/workflow.md:335`, "mp-grill-with-docs"),
      (`docs/development/workflow.md:872`, "is the Design technique"),
      (`docs/development/workflow.html:227`, "mp-grill-with-docs"),
      and (`.claude/CLAUDE.md:27`, "before you write code, not after").
- [ ] `/mp-grill-with-docs` keeps working as the human's shortcut, and its
      `disable-model-invocation` flag is unchanged.
- [ ] (`docs/agents/domain.md:11`, "reached via") and
      `docs/development/process-alignment-checklist.md` (lines 39 and 72) are
      updated to match.
- [ ] `scripts/check-process-parity.ps1` passes.
- [ ] The workflow PDF is regenerated with `scripts/update-workflow-pdf.ps1` when
      the change touches a string the PDF carries, or the item states why no
      regeneration is needed.
- [ ] The mirrored copies under `plugins/ahkflowapp/skills/` stay consistent with
      `.agents/`, or the item states why they do not need a change.

## Out of scope

- Removing `disable-model-invocation` from any skill.
- Rewriting `mp-grilling` or `mp-domain-modeling` themselves.
- The other four skills that carry the same flag: `mp-grill-me`, `mp-handoff`,
  `mp-triage`, `mp-wait-what`. Only Stage 2 Design names an unreachable one.

## Notes / dependencies

- Found while picking up backlog 105, in PR #320. Not fixed there: 105 is about
  a stalled PR-Agent model call and must not carry a process-file change.
- The same session used `mp-grilling` plus `mp-domain-modeling` together for
  105's Design, which is the behaviour this item makes official.
- Spec: none — the decision is already made, so Design is not needed.
- Plan: `docs/superpowers/plans/2026-08-19-design-technique-agent-invocable-plan-109.md`
