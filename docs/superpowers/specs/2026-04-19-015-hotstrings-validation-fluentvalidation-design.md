# 015 — Hotstrings validation (FluentValidation)

## Context

Backlog item `.claude/backlog/015-hotstrings-validation-fluentvalidation.md`.

Basic validators already exist inline in the command/query files:

- `CreateHotstringCommandValidator` — `Trigger` NotEmpty + MaxLength(50); `Replacement` NotEmpty + MaxLength(4000).
- `UpdateHotstringCommandValidator` — identical rules.
- `ListHotstringsQueryValidator` — `Page` 1..10_000; `PageSize` 1..200.

Enforcement is wired:

- `ValidationBehavior<TRequest,TResponse>` (MediatR `IPipelineBehavior`) throws `FluentValidation.ValidationException` on failure.
- `GlobalExceptionMiddleware` catches it and writes RFC 9457 ProblemDetails with `title = "Validation failed"`, `status = 400`, and an `errors` extension dict keyed by property name.

CLI is out of scope per `AGENTS.md` (`src/Tools/AHKFlowApp.CLI` planned but not created). Backlog item 015 predates that scope decision; the CLI acceptance criterion is deferred to backlog item 029.

## Goal

Close backlog 015 for the API. Harden hotstring validation so it (a) catches invisible-whitespace bugs, (b) exposes stable error messages, (c) is fully covered by unit and integration tests including the ProblemDetails shape.

## Validation rules

### `CreateHotstringCommand` / `UpdateHotstringCommand`

Both validators apply the same DTO rules via shared extension methods on the rule builder (`HotstringRules` static class) to remove duplication.

| Field         | Rule                                         | Message                                                  |
|---------------|----------------------------------------------|----------------------------------------------------------|
| `Trigger`     | NotEmpty                                     | `Trigger is required.`                                   |
| `Trigger`     | MaximumLength(50)                            | `Trigger must be 50 characters or fewer.`                |
| `Trigger`     | No leading/trailing whitespace               | `Trigger must not have leading or trailing whitespace.`  |
| `Trigger`     | No `\n`, `\r`, `\t`                          | `Trigger must not contain line breaks or tabs.`          |
| `Replacement` | NotEmpty                                     | `Replacement is required.`                               |
| `Replacement` | MaximumLength(4000)                          | `Replacement must be 4000 characters or fewer.`          |
| `ProfileId`   | When provided, `!= Guid.Empty`               | `ProfileId must not be an empty GUID.`                   |

`CascadeMode.Stop` per-rule-chain so a null/empty trigger doesn't also raise the whitespace error — one failure per rule chain is enough and reduces noise.

Unicode in `Trigger` is explicitly allowed (German/French/Dutch accented characters are common triggers). No ASCII-only rule.

### `ListHotstringsQuery`

No rule changes. Already has `Page` and `PageSize` range checks.

### Out of scope for this item

- AHK-syntax rules (e.g., disallowing `::`, `;`) — belong to the script-generation layer (backlog 021+).
- Localization of messages.
- Duplicate-trigger-per-profile — already enforced in the handler via DB unique constraint + pre-check.

## Code layout

Keep validators inline with their command/query classes (existing convention, matches MediatR pipeline discovery via `RegisterServicesFromAssembly`). Add one private helper for the shared DTO rules:

```csharp
// In AHKFlowApp.Application.Validation.HotstringRules (new internal static class)
internal static class HotstringRules
{
    public static IRuleBuilderOptions<T, string> ValidTrigger<T>(this IRuleBuilder<T, string> rb) => ...;
    public static IRuleBuilderOptions<T, string> ValidReplacement<T>(this IRuleBuilder<T, string> rb) => ...;
    public static IRuleBuilderOptions<T, Guid?> ValidOptionalProfileId<T>(this IRuleBuilder<T, Guid?> rb) => ...;
}
```

Both validators call these extension methods. Messages live in one place.

## Tests

### Unit (`AHKFlowApp.Application.Tests/Hotstrings/`)

Expand existing `CreateHotstringCommandValidatorTests` and `UpdateHotstringCommandValidatorTests` to cover:

- Valid input succeeds.
- Empty/whitespace trigger fails (already present for Create; add whitespace case to Update).
- Trigger length boundary: length 50 succeeds, 51 fails.
- Trigger with leading space, trailing space, embedded `\n`, `\r`, `\t` — each fails with the whitespace/control-char message.
- Unicode trigger (e.g., `"dür"`) succeeds.
- Empty replacement fails.
- Replacement length boundary: 4000 succeeds, 4001 fails.
- `ProfileId = Guid.Empty` fails.
- `ProfileId = null` succeeds.
- `ProfileId = Guid.NewGuid()` succeeds.

Assertion style: existing pattern (`ValidationResult` + `Should().Contain(e => e.PropertyName == ...)`).

### Integration (`AHKFlowApp.API.Tests/Hotstrings/HotstringsEndpointsTests.cs`)

One new test:

```csharp
Post_InvalidBody_ReturnsProblemDetailsWithErrors
```

Asserts:

- `response.StatusCode == 400`
- `Content-Type` starts with `application/problem+json`
- Body deserializes to `ProblemDetails` with `Title == "Validation failed"`, `Status == 400`, non-empty `Detail`
- `errors` extension contains keys `Input.Trigger` and `Input.Replacement`

Existing `Post_InvalidBody_Returns400` stays — it covers the raw status-code path without coupling to body shape.

## Non-goals

- Refactoring validator discovery/registration (already done in `DependencyInjection.cs`).
- Changing `ValidationBehavior` or middleware.
- Touching CLI (no CLI yet).

## Acceptance

All four in-scope backlog acceptance criteria pass:

- [x] Hotstring create/update DTOs validated with FluentValidation.
- [x] Validation enforced by the API (via MediatR pipeline + middleware).
- [x] Unit tests cover all validator rules and edge cases.
- [x] Integration tests verify validation errors surface as Problem Details from the API.

CLI criterion deferred to backlog 029.
