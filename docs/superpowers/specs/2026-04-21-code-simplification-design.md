# Code simplification (design)

## Context

The codebase is still small, which makes this a good time to simplify it before early structure hardens into long-term maintenance cost.

The current architecture is directionally sound: controller-based ASP.NET Core API, MediatR in the application layer, EF Core in infrastructure, Blazor WebAssembly on the frontend, and a healthy test surface across API, application, infrastructure, UI, and E2E layers.

The risk is not that the codebase is already deeply overengineered. The risk is that small pockets of ceremony accumulate faster than domain complexity:

- startup and composition code in `src\Backend\AHKFlowApp.API\Program.cs` is dense and mixes several concerns inline,
- some abstractions are very thin and may only rename framework concepts without creating a meaningful seam,
- the frontend API client layer contains repeated request/result plumbing,
- tests include helpers and fixtures that may be useful, but should be pruned where they obscure intent more than they improve reuse.

This first code-focused spec should simplify code in `src\` and noisy supporting code in `tests\`, while preserving the boundaries that still clearly support testability, clarity, or architecture.

## Goal

Reduce low-value complexity in the codebase without destabilizing the architectural boundaries that are already serving the project well.

Success means:

1. Common code paths are easier to read end-to-end.
2. Thin abstractions that do not add real value are removed or collapsed.
3. Startup, HTTP client, and test helper code becomes shorter and more obvious.
4. Any patterns kept or introduced are lightweight and reduce code rather than multiply it.
5. Small structure changes inside `src\` and `tests\` are allowed when they improve discoverability, but broad repo layout work stays out of scope.

Non-goals:

- redesigning the project’s Clean Architecture baseline,
- changing deployment or documentation workflows in this spec,
- chasing coverage percentages as the main objective,
- rewriting stable code just to make it look different.

## Options considered

### Option 1 - Targeted simplification *(chosen)*

Remove low-value indirection, simplify hotspots, and allow small internal structure cleanup while preserving the boundaries that still clearly help with testing or architecture.

Pros:

- Delivers meaningful simplification without destabilizing the whole codebase.
- Fits the current repo maturity: enough code exists to trim ceremony, but not so much that a broad rewrite is justified.
- Keeps the cleanup focused on readability, not ideology.

Cons:

- Requires judgment calls on which abstractions still pay for themselves.
- Some inconsistencies may remain temporarily if they are lower-value than the main hotspots.

### Option 2 - Conservative cleanup only

Focus mainly on naming, formatting, short methods, and tiny refactors while preserving nearly all current abstractions and structure.

Pros:

- Lowest change risk.
- Easy to review.

Cons:

- Would leave the main sources of friction in place.
- Likely to disappoint the stated goal of making the code more concise.

### Option 3 - Aggressive abstraction collapse

Collapse most wrappers, interfaces, and intermediate layers unless they are absolutely required at runtime.

Pros:

- Maximum immediate reduction in moving parts.

Cons:

- Too risky for an early codebase that is still settling.
- Likely to erase boundaries that still support testing and future feature growth.
- Creates needless churn before the scripts and docs passes.

**Decision: Option 1.**

## Design

### Simplification principles

This cleanup should follow a few strict principles:

- Prefer deleting code over moving code when the behavior is redundant.
- Prefer one obvious flow over multiple small indirections.
- Keep abstractions only when they create a real boundary, not when they merely wrap a framework type.
- Keep explicit mappings and explicit behavior where they improve correctness or readability.
- Avoid introducing new patterns unless they remove duplication and make the code easier to explain.

In short: concise, but not clever.

### Cleanup category 1 - Startup and composition

`Program.cs` is a likely simplification hotspot because it currently mixes:

- bootstrap logging,
- conditional Application Insights setup,
- controller and ProblemDetails configuration,
- service registration,
- development-only database migration logic,
- request pipeline setup,
- development-only browser launch behavior.

The goal is not to hide all of this behind many extension methods. The goal is to make the composition root easier to scan.

The preferred direction is:

- keep `Program.cs` as the composition root,
- extract only cohesive setup blocks that materially improve readability,
- keep behavior discoverable near startup rather than scattering it across many files.

Good candidates are small, single-purpose setup methods or extensions for areas that already have a natural boundary, such as API/OpenAPI setup or development-only startup behavior. Poor candidates are wrappers that just move a few lines without clarifying anything.

### Cleanup category 2 - Abstraction pruning

The codebase should review interfaces and wrappers with a high bar:

- keep them when they protect a meaningful application boundary,
- remove them when they only rename a concrete framework dependency without real substitution value.

Likely review targets include thin abstractions such as development environment wrappers and other one-property or one-method interfaces that exist only to pass framework state through a layer.

This does **not** mean removing all abstractions. Some seams are still justified:

- current-user access is a real boundary between HTTP context and application logic,
- database access boundaries may still be justified if they meaningfully isolate the application layer from infrastructure details,
- service abstractions that materially simplify testing or keep layers clean should remain.

The rule is selective pruning, not a purity exercise.

### Cleanup category 3 - Frontend service simplification

The Blazor client layer should aim for a small, easy-to-follow shape:

- page code should call clear client methods,
- shared HTTP and error handling should not be duplicated,
- the number of service interfaces should stay proportional to the actual complexity.

The likely target is the request/result plumbing around `AhkFlowAppApiHttpClient` and `HotstringsApiClient`. This area may benefit from a small shared helper or a modest facade pattern, but only if it removes duplication without obscuring status handling or error mapping.

What to avoid:

- adding a generic service hierarchy,
- introducing a large base class just to share a few lines,
- splitting the API client surface into many tiny interfaces without need.

### Cleanup category 4 - Mapping and DTO friction

The project should keep explicit mapping rather than introducing mapper libraries.

However, explicit mapping should still feel lightweight. This cleanup should review:

- duplicate DTO shapes between frontend and backend where the duplication adds maintenance noise,
- mapping helpers that are justified versus ones that are too trivial to carry their own indirection cost,
- places where small mapping or response-shape cleanup would make the code easier to follow.

The goal is not necessarily to unify all DTOs across the app, but to reduce friction where duplication no longer pays for the separation.

### Cleanup category 5 - Test code simplification

Test code is part of the codebase and should also stay concise.

This spec should allow pruning or simplifying:

- builders that do not save meaningful repetition,
- fixtures that hide test setup more than they clarify it,
- helper layers that make tests harder to read than inline setup would.

At the same time, this cleanup should preserve helpers that clearly improve integration and end-to-end testing, especially where infrastructure setup is expensive or repetitive.

The desired outcome is tests that read more directly while retaining the support code that materially reduces boilerplate.

### Cleanup category 6 - Small internal structure cleanup

This spec may include small structure changes inside `src\` and `tests\` when they simplify the code:

- moving a file to a more obvious folder,
- co-locating tightly related classes,
- removing folders that contain only one trivial concept if the nesting adds noise.

This spec should not do broad repo-layout work. That remains a separate follow-on effort for scripts and documentation.

## Likely first-pass targets

Based on the current code shape, likely early targets include:

- `src\Backend\AHKFlowApp.API\Program.cs`
- `src\Backend\AHKFlowApp.Application\Abstractions\IDevEnvironment.cs`
- `src\Backend\AHKFlowApp.API\DevEnvironment.cs`
- `src\Frontend\AHKFlowApp.UI.Blazor\Services\AhkFlowAppApiHttpClient.cs`
- `src\Frontend\AHKFlowApp.UI.Blazor\Services\HotstringsApiClient.cs`
- test helpers or builders that are only lightly used or add indirection without enough payoff

These are review targets, not automatic deletions. Each should be kept, simplified, or removed based on whether it reduces cognitive load in practice.

## Lightweight patterns allowed

This cleanup may use a few lightweight patterns where they reduce code and improve clarity:

- **composition root cleanup** for startup wiring,
- **small, cohesive extension methods** for setup blocks with a real boundary,
- **facade-style client surface** in the frontend if it collapses duplicate HTTP plumbing,
- **single source of truth helpers** where multiple code paths are currently manually repeating the same transformation or status mapping.

Patterns that should be avoided in this pass:

- repository pattern,
- mapper frameworks,
- generic base hierarchies,
- speculative abstractions for future features.

## Risks and mitigations

### Risk: oversimplifying useful seams

Some abstractions may look thin but still protect an important architectural or testing boundary.

Mitigation: require each abstraction review to answer a simple question: what concrete cost do we pay if this seam disappears? If the answer is meaningful, keep it.

### Risk: replacing explicit code with hidden indirection

Startup cleanup in particular can become worse if code is pushed into many extension methods that hide behavior.

Mitigation: only extract cohesive blocks that make `Program.cs` easier to scan, and keep behavior discoverable.

### Risk: test readability regresses

Removing helpers too aggressively can lead to repeated setup noise.

Mitigation: simplify helpers selectively and optimize for direct, readable tests rather than minimal helper count.

## Testing and validation

This spec is about simplification, not only appearance, so implementation should validate behavior rather than assume safe refactors.

Validation should focus on:

- existing build and test workflows continuing to pass,
- no user-visible API behavior changing unintentionally,
- frontend pages and API client behavior preserving current error handling semantics,
- simplified tests remaining readable and representative of real behavior.

Coverage improvement may happen as a byproduct where tests need to be clarified or added around changed code, but coverage thresholds are not the primary driver of this spec.

## Follow-on specs enabled by this design

After this spec, the next logical specs are:

1. Repo simplification and file layout.
2. Script standardization and PowerShell v5 compatibility.
3. Local install and deployment experience.
4. Azure deployment automation and preflight checks.
5. Minimal documentation cleanup and cross-surface alignment.
