# Repo simplification and file layout (design)

## Context

The repository already has a reasonable top-level shape, but it has started to drift in a few ways that make it harder to understand and maintain:

- Runnable scripts live mostly under `scripts\`, but `docs\scripts\create-github-issues.ps1` introduces a second script location.
- Some documentation still refers to removed or superseded paths such as `scripts\azure\...`, while current operational entrypoints use `scripts\deploy.ps1`, `scripts\update.ps1`, and related root-level scripts.
- The repo contains multiple instruction surfaces (`README.md`, `docs\`, `AGENTS.md`, `.github\`, `.claude\`) that describe overlapping workflows. They are useful, but they can drift if they do not point to the same canonical paths and commands.

The goal of this first spec is to simplify the repository structure without broad behavioral changes. It should establish a clearer layout that later script and documentation cleanup work can build on.

## Goal

Make the repository easier to navigate by giving scripts, documentation, and tool-specific instructions one clear home each.

Success means:

1. Every runnable script lives under one canonical `scripts\` folder.
2. `docs\` contains documentation only, not operational scripts.
3. `README.md`, `docs\`, `AGENTS.md`, `.github\`, and `.claude\` reference the same canonical paths and workflow names.
4. Stale references to removed structures such as `scripts\azure\...` are either updated or explicitly marked as historical content in archived design material.

Non-goals:

- Redesigning the application architecture.
- Changing deployment behavior in this spec.
- Rewriting all documentation content in one pass.
- Introducing a heavy taxonomy of script subfolders before the script count justifies it.

## Options considered

### Option 1 - One flat canonical `scripts\` folder *(chosen)*

Keep all runnable scripts in the existing root `scripts\` folder. Move stray scripts into it. Documentation points to those scripts instead of embedding or hosting them.

Pros:

- Smallest change from current reality.
- Easiest rule for contributors: "if it runs, it lives in `scripts\`."
- Lowest churn while the repo is still early-stage.

Cons:

- The folder may become busy later if script count grows significantly.

### Option 2 - Canonical `scripts\` folder with immediate subfolders by purpose

Reorganize now into `scripts\deploy\`, `scripts\dev\`, `scripts\tooling\`, and similar categories.

Pros:

- Better long-term scaling if the script inventory grows rapidly.
- Slightly clearer categorization at a glance.

Cons:

- Premature structure for the current repo size.
- Creates more rename churn now, with little immediate user value.

### Option 3 - Keep split script locations but document ownership rules

Allow both `scripts\` and `docs\scripts\` as long as the distinction is documented.

Pros:

- Minimal file movement.

Cons:

- Preserves the ambiguity that this cleanup is meant to remove.
- Makes discoverability and maintenance worse over time.

**Decision: Option 1.**

## Design

### Repository ownership rules

The repository should use these simple ownership boundaries:

- `scripts\` - all runnable scripts, whether for deployment, local setup, maintenance, coverage, or tooling.
- `docs\` - human-readable guidance only. Documentation may describe scripts, but must not be the canonical home for them.
- `docs\deployment\` - deployment and environment setup guidance.
- `docs\development\` - contributor setup, local development, testing, and tooling guidance.
- `docs\architecture\` - enduring architecture and system-shape documentation.
- `docs\superpowers\` - AI-generated specs and plans; useful as project history, but not the primary end-user documentation surface.
- `.github\` - GitHub-specific automation, templates, and instructions only.
- `.claude\` - Claude-specific overlays, local tooling, and backlog artifacts only.

This keeps the repo easy to explain: code in `src\` and `tests\`, scripts in `scripts\`, docs in `docs\`, platform-specific overlays in `.github\` and `.claude\`.

### Canonical script rule

Every runnable script should live under `scripts\`.

That includes:

- deployment and teardown helpers,
- local development helpers,
- setup/bootstrap scripts,
- maintenance/tooling helpers such as issue creation or coverage generation.

`docs\scripts\` should be removed as an active location. The current `docs\scripts\create-github-issues.ps1` should move to `scripts\create-github-issues.ps1`, and all references should be updated to point there.

This is a lightweight **single source of truth** pattern for operational entrypoints: one script location, one canonical path, many docs that reference it.

### Documentation layering

Documentation should be intentionally layered instead of duplicated:

- `README.md` should stay short and answer: what this project is, what is required to run it locally, and where to go next.
- `docs\deployment\` should hold deployment-specific details, including Azure and local container-based deployment guidance.
- `docs\development\` should hold contributor workflows such as local setup, GitHub setup, testing, and coverage.
- `AGENTS.md` should remain contributor/agent guidance for coding conventions and repo rules, but should not become the only place where operational workflows are documented.

When a process needs both concise guidance and deeper guidance, `README.md` should link to the detailed doc instead of repeating it.

### Alignment rules for `.github`, `.claude`, and docs

This spec includes layout and alignment rules now, while deferring broader content cleanup to a later documentation-focused spec.

The alignment rule is:

1. Operational paths and script names are canonical in the repo tree itself.
2. Human-facing docs (`README.md`, `docs\`) should reference those canonical paths directly.
3. Tool-specific instruction files (`AGENTS.md`, `.github\copilot-instructions.md`, `.claude\CLAUDE.md`, related backlog notes) should reference the same paths and should not invent alternate structure descriptions.
4. Historical design docs under `docs\superpowers\` may mention old structures, but current user-facing docs must not.

This means current drift such as references to `scripts\azure\...` should be removed from live docs. Historical specs and plans may remain as historical artifacts unless they are actively misleading a current workflow.

### What this spec changes vs what it leaves for later

This spec should drive:

- moving stray scripts into `scripts\`,
- removing active duplicate script locations,
- updating current docs and instruction surfaces to reflect one canonical layout,
- defining ownership boundaries for repo surfaces.

This spec should not yet decide:

- whether `scripts\` eventually needs `deploy\`, `dev\`, or `tooling\` subfolders,
- how Azure deployment scripts should be functionally redesigned,
- how local deployment should be packaged for Raspberry Pi or other Docker hosts,
- how preflight checks and prerequisite validation should work inside `deploy.ps1`.

Those are valid next specs, but they depend on this simplified layout first.

## Planned file-level outcomes

Expected outcomes from implementing this spec:

- Move `docs\scripts\create-github-issues.ps1` to `scripts\create-github-issues.ps1`.
- Update `docs\development\github-setup.md` and any related references to point at the canonical script path.
- Audit current user-facing docs for references to old `scripts\azure\...` structure and replace them with current supported workflows.
- Update `README.md`, `AGENTS.md`, `.github\` guidance, and `.claude\` guidance where needed so they describe the same layout.
- Leave historical `docs\superpowers\specs\` and `docs\superpowers\plans\` content intact unless a specific file is being reused as active guidance.

## Risks and mitigations

### Risk: over-structuring too early

Adding many new folders now could make the repo look cleaner on paper while making it harder to remember where things go.

Mitigation: keep the rule simple now - one `scripts\` folder - and only introduce subfolders later if script volume creates real pain.

### Risk: hidden references to old paths

Docs and instruction files may still reference outdated paths even after the obvious files are updated.

Mitigation: include a targeted cross-reference pass across `README.md`, `docs\`, `AGENTS.md`, `.github\`, and `.claude\` as part of implementation.

### Risk: historical specs confuse contributors

Older design docs may still mention removed structures.

Mitigation: treat `docs\superpowers\` as historical design record, not canonical runtime documentation, and avoid linking current onboarding docs to outdated historical specs.

## Testing and validation

This structural cleanup does not require new testing tools.

Validation for implementation should focus on:

- all moved scripts remaining invocable from their new canonical paths,
- all user-facing documentation pointing to valid paths,
- no active documentation continuing to describe deprecated folder layouts.

## Follow-on specs enabled by this design

After this spec, the next logical specs are:

1. Script standardization and PowerShell v5 compatibility.
2. Local install and deployment experience, including Docker-first local hosting guidance.
3. Azure `deploy.ps1` improvements, including prerequisite checks and workflow triggering.
4. Minimal documentation cleanup and prerequisite clarity.
5. Cross-surface consistency audit for repo guidance and automation instructions.
