# 015 — Hotstrings validation (FluentValidation) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden hotstring Create/Update validation with richer rules, stable messages, and complete test coverage (unit + integration ProblemDetails shape).

**Architecture:** Shared rule extension methods in a new internal static class `HotstringRules` (Application layer). Validators stay inline with their command records. Error messages are hardcoded strings in the extension methods — one source of truth. ValidationBehavior + GlobalExceptionMiddleware are already wired; no changes.

**Tech Stack:** .NET 10, FluentValidation, MediatR, xUnit, FluentAssertions, `WebApplicationFactory` + Testcontainers.

**Branch:** `feature/015-hotstrings-validation` (already created; spec already committed).

**Spec:** `docs/superpowers/specs/2026-04-19-015-hotstrings-validation-fluentvalidation-design.md`

---

## File Structure

**New files:**
- `src/Backend/AHKFlowApp.Application/Validation/HotstringRules.cs` — extension methods `ValidTrigger`, `ValidReplacement`, `ValidOptionalProfileId` on `IRuleBuilder`. Single owner of rule definitions and messages.

**Modified files:**
- `src/Backend/AHKFlowApp.Application/Commands/Hotstrings/CreateHotstringCommand.cs` — validator calls extension methods.
- `src/Backend/AHKFlowApp.Application/Commands/Hotstrings/UpdateHotstringCommand.cs` — same.
- `tests/AHKFlowApp.Application.Tests/Hotstrings/CreateHotstringCommandValidatorTests.cs` — expanded edge cases.
- `tests/AHKFlowApp.Application.Tests/Hotstrings/UpdateHotstringCommandValidatorTests.cs` — brought to parity with Create.
- `tests/AHKFlowApp.API.Tests/Hotstrings/HotstringsEndpointsTests.cs` — one new ProblemDetails-shape test.

**Not modified:** `ValidationBehavior`, `GlobalExceptionMiddleware`, `ListHotstringsQueryValidator`, DTOs, handlers, controllers, DI.

---

## Task 1: Create `HotstringRules` extension methods (TDD)

**Files:**
- Create: `src/Backend/AHKFlowApp.Application/Validation/HotstringRules.cs`
- Test (existing, will be expanded): `tests/AHKFlowApp.Application.Tests/Hotstrings/CreateHotstringCommandValidatorTests.cs`

Rationale: the rules live in extension methods but are exercised via the validator that consumes them. TDD through the validator tests — the extension methods are implementation detail.

- [ ] **Step 1.1: Add the new edge-case tests to `CreateHotstringCommandValidatorTests`**

Replace the file contents with the expanded version below. Keep the existing passing tests, add new ones for every rule in the spec.

```csharp
using AHKFlowApp.Application.Commands.Hotstrings;
using AHKFlowApp.Application.DTOs;
using FluentAssertions;
using FluentValidation.Results;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

public sealed class CreateHotstringCommandValidatorTests
{
    private readonly CreateHotstringCommandValidator _sut = new();

    private static CreateHotstringCommand Cmd(
        string trigger = "btw",
        string replacement = "by the way",
        Guid? profileId = null)
        => new(new CreateHotstringDto(trigger, replacement, profileId));

    [Fact]
    public void Validate_WithValidInput_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd());

        result.IsValid.Should().BeTrue();
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public void Validate_WithEmptyOrWhitespaceTrigger_Fails(string trigger)
    {
        ValidationResult result = _sut.Validate(Cmd(trigger: trigger));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Input.Trigger");
    }

    [Fact]
    public void Validate_WithTriggerAt50Chars_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd(trigger: new string('x', 50)));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_WithTriggerAt51Chars_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(trigger: new string('x', 51)));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Trigger" &&
            e.ErrorMessage == "Trigger must be 50 characters or fewer.");
    }

    [Theory]
    [InlineData(" btw")]
    [InlineData("btw ")]
    [InlineData(" btw ")]
    public void Validate_WithTriggerLeadingOrTrailingWhitespace_Fails(string trigger)
    {
        ValidationResult result = _sut.Validate(Cmd(trigger: trigger));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Trigger" &&
            e.ErrorMessage == "Trigger must not have leading or trailing whitespace.");
    }

    [Theory]
    [InlineData("bt\nw")]
    [InlineData("bt\rw")]
    [InlineData("bt\tw")]
    public void Validate_WithTriggerContainingControlChars_Fails(string trigger)
    {
        ValidationResult result = _sut.Validate(Cmd(trigger: trigger));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Trigger" &&
            e.ErrorMessage == "Trigger must not contain line breaks or tabs.");
    }

    [Theory]
    [InlineData("dür")]
    [InlineData("café")]
    [InlineData("niño")]
    public void Validate_WithUnicodeTrigger_Succeeds(string trigger)
    {
        ValidationResult result = _sut.Validate(Cmd(trigger: trigger));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_WithEmptyReplacement_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(replacement: ""));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Input.Replacement");
    }

    [Fact]
    public void Validate_WithReplacementAt4000Chars_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd(replacement: new string('x', 4000)));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_WithReplacementAt4001Chars_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(replacement: new string('x', 4001)));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Replacement" &&
            e.ErrorMessage == "Replacement must be 4000 characters or fewer.");
    }

    [Fact]
    public void Validate_WithEmptyGuidProfileId_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(profileId: Guid.Empty));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.ProfileId" &&
            e.ErrorMessage == "ProfileId must not be an empty GUID.");
    }

    [Fact]
    public void Validate_WithNullProfileId_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd(profileId: null));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_WithValidProfileId_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd(profileId: Guid.NewGuid()));

        result.IsValid.Should().BeTrue();
    }
}
```

- [ ] **Step 1.2: Run the tests to confirm the new ones fail**

Run:
```bash
dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~CreateHotstringCommandValidatorTests" --configuration Release
```

Expected: the new tests fail. Specifically the whitespace, control-char, Guid.Empty, 50/4000-boundary tests. The original four tests still pass.

Note: if `Validate_WithEmptyOrWhitespaceTrigger_Fails` fails for the `"   "` case, that's expected — FluentValidation's `NotEmpty()` lets whitespace-only strings through. The new leading-whitespace rule we add in step 1.3 will catch it.

- [ ] **Step 1.3: Create `HotstringRules.cs` with extension methods**

```csharp
using FluentValidation;

namespace AHKFlowApp.Application.Validation;

internal static class HotstringRules
{
    public const int TriggerMaxLength = 50;
    public const int ReplacementMaxLength = 4000;

    public static IRuleBuilderOptions<T, string> ValidTrigger<T>(this IRuleBuilder<T, string> rb) =>
        rb.Cascade(CascadeMode.Stop)
          .NotEmpty().WithMessage("Trigger is required.")
          .MaximumLength(TriggerMaxLength).WithMessage($"Trigger must be {TriggerMaxLength} characters or fewer.")
          .Must(t => t is not null && t.Length == t.Trim().Length)
              .WithMessage("Trigger must not have leading or trailing whitespace.")
          .Must(t => t is not null && t.IndexOfAny(['\n', '\r', '\t']) < 0)
              .WithMessage("Trigger must not contain line breaks or tabs.");

    public static IRuleBuilderOptions<T, string> ValidReplacement<T>(this IRuleBuilder<T, string> rb) =>
        rb.Cascade(CascadeMode.Stop)
          .NotEmpty().WithMessage("Replacement is required.")
          .MaximumLength(ReplacementMaxLength).WithMessage($"Replacement must be {ReplacementMaxLength} characters or fewer.");

    public static IRuleBuilderOptions<T, Guid?> ValidOptionalProfileId<T>(this IRuleBuilder<T, Guid?> rb) =>
        rb.Must(id => id is null || id != Guid.Empty)
          .WithMessage("ProfileId must not be an empty GUID.");
}
```

- [ ] **Step 1.4: Rewire `CreateHotstringCommandValidator` to call the extensions**

Modify `src/Backend/AHKFlowApp.Application/Commands/Hotstrings/CreateHotstringCommand.cs`. Replace the validator class only — leave the record and handler alone. Add the `using` for the new namespace.

```csharp
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Application.Validation;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using FluentValidation;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Hotstrings;

public sealed record CreateHotstringCommand(CreateHotstringDto Input) : IRequest<Result<HotstringDto>>;

public sealed class CreateHotstringCommandValidator : AbstractValidator<CreateHotstringCommand>
{
    public CreateHotstringCommandValidator()
    {
        RuleFor(x => x.Input.Trigger).ValidTrigger();
        RuleFor(x => x.Input.Replacement).ValidReplacement();
        RuleFor(x => x.Input.ProfileId).ValidOptionalProfileId();
    }
}
```

(Handler class is unchanged — keep it as it is in the current file.)

- [ ] **Step 1.5: Run the tests to verify they all pass**

Run:
```bash
dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~CreateHotstringCommandValidatorTests" --configuration Release
```

Expected: all tests pass (the original 4 plus the new ones).

- [ ] **Step 1.6: Commit**

```bash
git add src/Backend/AHKFlowApp.Application/Validation/HotstringRules.cs \
        src/Backend/AHKFlowApp.Application/Commands/Hotstrings/CreateHotstringCommand.cs \
        tests/AHKFlowApp.Application.Tests/Hotstrings/CreateHotstringCommandValidatorTests.cs
git commit -m "feat(015): shared HotstringRules + expanded create validator tests"
```

---

## Task 2: Bring `UpdateHotstringCommandValidator` to parity

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/Commands/Hotstrings/UpdateHotstringCommand.cs`
- Modify: `tests/AHKFlowApp.Application.Tests/Hotstrings/UpdateHotstringCommandValidatorTests.cs`

- [ ] **Step 2.1: Expand `UpdateHotstringCommandValidatorTests`**

Replace the file with the version below. Mirrors Create's coverage but through an `UpdateHotstringCommand` with a random `Id`.

```csharp
using AHKFlowApp.Application.Commands.Hotstrings;
using AHKFlowApp.Application.DTOs;
using FluentAssertions;
using FluentValidation.Results;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

public sealed class UpdateHotstringCommandValidatorTests
{
    private readonly UpdateHotstringCommandValidator _sut = new();

    private static UpdateHotstringCommand Cmd(
        string trigger = "btw",
        string replacement = "by the way",
        Guid? profileId = null)
        => new(Guid.NewGuid(), new UpdateHotstringDto(trigger, replacement, profileId, true, true));

    [Fact]
    public void Validate_WithValidInput_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd());

        result.IsValid.Should().BeTrue();
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public void Validate_WithEmptyOrWhitespaceTrigger_Fails(string trigger)
    {
        ValidationResult result = _sut.Validate(Cmd(trigger: trigger));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Input.Trigger");
    }

    [Fact]
    public void Validate_WithTriggerAt50Chars_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd(trigger: new string('x', 50)));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_WithTriggerAt51Chars_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(trigger: new string('x', 51)));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Trigger" &&
            e.ErrorMessage == "Trigger must be 50 characters or fewer.");
    }

    [Theory]
    [InlineData(" btw")]
    [InlineData("btw ")]
    public void Validate_WithTriggerLeadingOrTrailingWhitespace_Fails(string trigger)
    {
        ValidationResult result = _sut.Validate(Cmd(trigger: trigger));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Trigger" &&
            e.ErrorMessage == "Trigger must not have leading or trailing whitespace.");
    }

    [Theory]
    [InlineData("bt\nw")]
    [InlineData("bt\rw")]
    [InlineData("bt\tw")]
    public void Validate_WithTriggerContainingControlChars_Fails(string trigger)
    {
        ValidationResult result = _sut.Validate(Cmd(trigger: trigger));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Trigger" &&
            e.ErrorMessage == "Trigger must not contain line breaks or tabs.");
    }

    [Fact]
    public void Validate_WithUnicodeTrigger_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd(trigger: "dür"));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_WithEmptyReplacement_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(replacement: ""));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Input.Replacement");
    }

    [Fact]
    public void Validate_WithReplacementAt4000Chars_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd(replacement: new string('x', 4000)));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_WithReplacementAt4001Chars_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(replacement: new string('x', 4001)));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Replacement" &&
            e.ErrorMessage == "Replacement must be 4000 characters or fewer.");
    }

    [Fact]
    public void Validate_WithEmptyGuidProfileId_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(profileId: Guid.Empty));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.ProfileId" &&
            e.ErrorMessage == "ProfileId must not be an empty GUID.");
    }

    [Fact]
    public void Validate_WithNullProfileId_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd(profileId: null));

        result.IsValid.Should().BeTrue();
    }
}
```

- [ ] **Step 2.2: Run the update tests — confirm new ones fail**

Run:
```bash
dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~UpdateHotstringCommandValidatorTests" --configuration Release
```

Expected: new tests fail (old `NotEmpty`/`MaximumLength`-only validator doesn't have whitespace, control-char, or Guid.Empty rules).

- [ ] **Step 2.3: Rewire `UpdateHotstringCommandValidator`**

Modify `src/Backend/AHKFlowApp.Application/Commands/Hotstrings/UpdateHotstringCommand.cs`. Replace the validator block; keep the handler unchanged. Add the `using`.

```csharp
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Application.Validation;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using FluentValidation;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Hotstrings;

public sealed record UpdateHotstringCommand(Guid Id, UpdateHotstringDto Input) : IRequest<Result<HotstringDto>>;

public sealed class UpdateHotstringCommandValidator : AbstractValidator<UpdateHotstringCommand>
{
    public UpdateHotstringCommandValidator()
    {
        RuleFor(x => x.Input.Trigger).ValidTrigger();
        RuleFor(x => x.Input.Replacement).ValidReplacement();
        RuleFor(x => x.Input.ProfileId).ValidOptionalProfileId();
    }
}
```

(Leave the existing `UpdateHotstringCommandHandler` class untouched.)

- [ ] **Step 2.4: Run the update tests — confirm all pass**

Run:
```bash
dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~UpdateHotstringCommandValidatorTests" --configuration Release
```

Expected: all tests pass.

- [ ] **Step 2.5: Run the full Application test project as a regression check**

Run:
```bash
dotnet test tests/AHKFlowApp.Application.Tests --configuration Release
```

Expected: all tests pass.

- [ ] **Step 2.6: Commit**

```bash
git add src/Backend/AHKFlowApp.Application/Commands/Hotstrings/UpdateHotstringCommand.cs \
        tests/AHKFlowApp.Application.Tests/Hotstrings/UpdateHotstringCommandValidatorTests.cs
git commit -m "feat(015): update validator uses shared HotstringRules + full edge coverage"
```

---

## Task 3: Integration test for ProblemDetails shape

**Files:**
- Modify: `tests/AHKFlowApp.API.Tests/Hotstrings/HotstringsEndpointsTests.cs`

- [ ] **Step 3.1: Add `Post_InvalidBody_ReturnsProblemDetailsWithErrors`**

Append this test to the class (before `Dispose`). It complements — does not replace — the existing `Post_InvalidBody_Returns400` which just checks the status code.

```csharp
[Fact]
public async Task Post_InvalidBody_ReturnsProblemDetailsWithErrors()
{
    using HttpClient client = CreateAuthed();
    var dto = new CreateHotstringDto("", "");

    HttpResponseMessage response = await client.PostAsJsonAsync("/api/v1/hotstrings", dto);

    response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    response.Content.Headers.ContentType!.MediaType.Should().Be("application/problem+json");

    using JsonDocument doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
    JsonElement root = doc.RootElement;

    root.GetProperty("title").GetString().Should().Be("Validation failed");
    root.GetProperty("status").GetInt32().Should().Be(400);
    root.GetProperty("detail").GetString().Should().NotBeNullOrWhiteSpace();

    JsonElement errors = root.GetProperty("errors");
    errors.TryGetProperty("Input.Trigger", out _).Should().BeTrue("validation errors should be keyed by DTO property path");
    errors.TryGetProperty("Input.Replacement", out _).Should().BeTrue();
}
```

Add the `System.Text.Json` using at the top of the file:

```csharp
using System.Text.Json;
```

- [ ] **Step 3.2: Run the new test**

Run:
```bash
dotnet test tests/AHKFlowApp.API.Tests --filter "FullyQualifiedName~Post_InvalidBody_ReturnsProblemDetailsWithErrors" --configuration Release
```

Expected: pass. If `Content-Type` assertion fails, the server may return `application/problem+json; charset=utf-8` — the `.MediaType` property strips the parameters, so the `Be("application/problem+json")` assertion should hold. If it still fails, downgrade to `StartWith("application/problem+json")`.

- [ ] **Step 3.3: Run the full API test project**

Run:
```bash
dotnet test tests/AHKFlowApp.API.Tests --configuration Release
```

Expected: all tests pass (including the existing `Post_InvalidBody_Returns400`, `Post_DuplicateTrigger_Returns409`, etc.).

- [ ] **Step 3.4: Commit**

```bash
git add tests/AHKFlowApp.API.Tests/Hotstrings/HotstringsEndpointsTests.cs
git commit -m "test(015): assert ProblemDetails shape for invalid hotstring body"
```

---

## Task 4: Full-build regression + close out backlog item

**Files:**
- Modify: `.claude/backlog/015-hotstrings-validation-fluentvalidation.md`

- [ ] **Step 4.1: Full solution build and test**

Run:
```bash
dotnet build --configuration Release
dotnet test --configuration Release --no-build
```

Expected: build succeeds, all tests pass. If anything fails, stop and diagnose — do not move on.

- [ ] **Step 4.2: Format check**

Run:
```bash
dotnet format --verify-no-changes
```

If this fails, run `dotnet format` and re-run the verify command. Then stage the formatting changes and add them to the next commit.

- [ ] **Step 4.3: Update backlog item — mark acceptance criteria**

Edit `.claude/backlog/015-hotstrings-validation-fluentvalidation.md`. Replace the "Acceptance criteria" section with:

```markdown
## Acceptance criteria

- [x] Hotstring create/update DTOs are validated with FluentValidation.
- [x] Validation is enforced by the API.
- [ ] CLI surfaces validation failures in a user-friendly way. _(Deferred to backlog 029 — CLI not yet scaffolded; see AGENTS.md "Out of Scope".)_
- [x] Unit tests cover all validator rules and edge cases.
- [x] Integration tests verify validation errors surface as Problem Details from the API.
```

- [ ] **Step 4.4: Commit backlog update**

```bash
git add .claude/backlog/015-hotstrings-validation-fluentvalidation.md
git commit -m "docs(015): tick acceptance criteria; CLI deferred to 029"
```

- [ ] **Step 4.5: Push branch and open PR**

```bash
git push -u origin feature/015-hotstrings-validation
gh pr create --title "feat: harden hotstring validation (015)" --body "$(cat <<'EOF'
## Summary
- Shared `HotstringRules` extension methods centralize Trigger/Replacement/ProfileId rules with stable error messages
- Reject triggers with leading/trailing whitespace or embedded `\n`/`\r`/`\t`; reject `Guid.Empty` ProfileId
- Unicode triggers remain valid
- Integration test asserts RFC 9457 ProblemDetails shape (title, status, errors dict keyed by DTO property path)

## Test plan
- [x] `dotnet test tests/AHKFlowApp.Application.Tests` — all pass (expanded validator tests)
- [x] `dotnet test tests/AHKFlowApp.API.Tests` — all pass (new ProblemDetails shape test)
- [x] `dotnet format --verify-no-changes`
- [x] `dotnet build --configuration Release`

Closes backlog item 015 for the API. CLI criterion deferred to backlog 029.
EOF
)"
```

---

## Self-review

**Spec coverage:**
- Shared rule extensions → Task 1.3 creates `HotstringRules.cs`.
- Trigger rules (NotEmpty, MaxLength(50), no leading/trailing whitespace, no `\n`/`\r`/`\t`) → Task 1.3 + tests 1.1/2.1.
- Replacement rules (NotEmpty, MaxLength(4000)) → Task 1.3 + tests.
- `ProfileId` not `Guid.Empty` when provided → Task 1.3 + tests.
- `CascadeMode.Stop` per rule chain → Task 1.3 uses `.Cascade(CascadeMode.Stop)` on Trigger and Replacement chains.
- Validators stay inline; both call extensions → Tasks 1.4 + 2.3.
- Unicode allowed → Tests in 1.1 + 2.1.
- Integration test for ProblemDetails shape → Task 3.1.
- CLI deferred → Task 4.3 documents it in the backlog item.

**Placeholder scan:** No TBDs, TODOs, "similar to Task N", or "implement later". Every code step shows full code.

**Type/name consistency:** `ValidTrigger`, `ValidReplacement`, `ValidOptionalProfileId` referenced identically in Tasks 1.3, 1.4, 2.3. Error message strings identical between `HotstringRules.cs` and the test assertions. `TriggerMaxLength`/`ReplacementMaxLength` constants used only internally by `HotstringRules` — test assertions hardcode the resulting numbers (50/4000) to match the spec-facing contract.

---

## Unresolved questions

None.
