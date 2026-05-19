# Header Template Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the bare default profile header with a richer one and add token substitution so headers can include `{ProfileName}`, `{AppVersion}`, `{HotstringCount}`, `{HotkeyCount}`, `{GeneratedAt[:format]}`. All formatting uses `CultureInfo.InvariantCulture`. `{{` / `}}` escape to literal braces.

**Architecture:** A new `HeaderTokenRenderer` service performs token substitution. `AhkScriptGenerator` gains a dependency on it (plus `TimeProvider` and a new `IAppVersionProvider`) and renders the profile's `HeaderTemplate` and `FooterTemplate` through the renderer before emitting them. No schema changes; only new code paths.

**Tech Stack:** .NET 10, MediatR, xUnit, FluentAssertions, NSubstitute, `Microsoft.Extensions.Time.Testing.FakeTimeProvider`.

**Spec:** `docs/superpowers/specs/2026-05-19-header-template-improvements-design.md`

---

## File Structure

### Create

- `src/Backend/AHKFlowApp.Application/Abstractions/IAppVersionProvider.cs` — interface returning the running app's informational version.
- `src/Backend/AHKFlowApp.Infrastructure/Services/AssemblyAppVersionProvider.cs` — reads `AssemblyInformationalVersionAttribute`.
- `src/Backend/AHKFlowApp.Application/Services/HeaderTokenRenderer.cs` — pure substitution + escape logic.
- `tests/AHKFlowApp.Application.Tests/Services/HeaderTokenRendererTests.cs`
- `tests/AHKFlowApp.Infrastructure.Tests/Services/AssemblyAppVersionProviderTests.cs`

### Modify

- `src/Backend/AHKFlowApp.Domain/Constants/DefaultProfileTemplates.cs` — replace `Header` constant with the richer multiline template containing tokens.
- `src/Backend/AHKFlowApp.Application/Services/AhkScriptGenerator.cs` — inject `HeaderTokenRenderer`, `TimeProvider`, `IAppVersionProvider`; render header/footer through the renderer.
- `src/Backend/AHKFlowApp.Application/DependencyInjection.cs` — register `HeaderTokenRenderer`. The `TimeProvider.System` is already registered by Microsoft.Extensions; verify.
- `src/Backend/AHKFlowApp.API/Program.cs` (or the relevant Infrastructure DI module) — register `IAppVersionProvider`.
- `tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorTests.cs` — extend with header/footer token-substitution coverage. (Inspect the file location — if it lives under a different path, adapt; same for the test name.)

---

## Conventions

- `AhkScriptGenerator` is registered as `AddSingleton<AhkScriptGenerator>()` (`DependencyInjection.cs:20`). Keep that lifetime.
- `HeaderTokenRenderer` is stateless and pure — `AddSingleton`.
- `IAppVersionProvider` reads an assembly attribute once; `AddSingleton`.
- Use `string.Create` or `StringBuilder` for the renderer — avoid LINQ. Generated scripts are emitted often enough that a tight allocation budget is worthwhile.
- All formatting calls explicitly pass `CultureInfo.InvariantCulture`. **Never** rely on `Thread.CurrentThread.CurrentCulture`.

---

## Task 1: `IAppVersionProvider` + Implementation + Tests

**Files:**
- Create: `src/Backend/AHKFlowApp.Application/Abstractions/IAppVersionProvider.cs`
- Create: `src/Backend/AHKFlowApp.Infrastructure/Services/AssemblyAppVersionProvider.cs`
- Create: `tests/AHKFlowApp.Infrastructure.Tests/Services/AssemblyAppVersionProviderTests.cs`

- [ ] **Step 1: Failing test**

```csharp
// tests/AHKFlowApp.Infrastructure.Tests/Services/AssemblyAppVersionProviderTests.cs
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Infrastructure.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Infrastructure.Tests.Services;

public sealed class AssemblyAppVersionProviderTests
{
    [Fact]
    public void GetVersion_ReturnsNonEmptyString()
    {
        IAppVersionProvider sut = new AssemblyAppVersionProvider();

        string version = sut.GetVersion();

        version.Should().NotBeNullOrWhiteSpace();
        version.Should().NotBe("0.0.0"); // sanity — MinVer should produce something more specific
    }
}
```

- [ ] **Step 2: Run — expect build fail**

```bash
dotnet test tests/AHKFlowApp.Infrastructure.Tests --filter "FullyQualifiedName~AssemblyAppVersionProviderTests"
```

Expected: BUILD FAILS.

- [ ] **Step 3: Implement**

```csharp
// src/Backend/AHKFlowApp.Application/Abstractions/IAppVersionProvider.cs
namespace AHKFlowApp.Application.Abstractions;

public interface IAppVersionProvider
{
    string GetVersion();
}
```

```csharp
// src/Backend/AHKFlowApp.Infrastructure/Services/AssemblyAppVersionProvider.cs
using System.Reflection;
using AHKFlowApp.Application.Abstractions;

namespace AHKFlowApp.Infrastructure.Services;

public sealed class AssemblyAppVersionProvider : IAppVersionProvider
{
    // Read the informational version once. MinVer writes this attribute at build time.
    private static readonly string s_version = ResolveVersion();

    public string GetVersion() => s_version;

    private static string ResolveVersion()
    {
        Assembly asm = typeof(AssemblyAppVersionProvider).Assembly;
        string? info = asm.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion;
        if (!string.IsNullOrWhiteSpace(info))
        {
            // Strip git-sha trailer that MinVer sometimes appends: "1.2.3+abc1234"
            int plus = info.IndexOf('+');
            return plus >= 0 ? info[..plus] : info;
        }

        return asm.GetName().Version?.ToString() ?? "0.0.0";
    }
}
```

- [ ] **Step 4: Tests pass**

```bash
dotnet test tests/AHKFlowApp.Infrastructure.Tests --filter "FullyQualifiedName~AssemblyAppVersionProviderTests"
```

- [ ] **Step 5: Commit**

```bash
git add src/Backend/AHKFlowApp.Application/Abstractions/IAppVersionProvider.cs \
        src/Backend/AHKFlowApp.Infrastructure/Services/AssemblyAppVersionProvider.cs \
        tests/AHKFlowApp.Infrastructure.Tests/Services/AssemblyAppVersionProviderTests.cs
git commit -m "feat: IAppVersionProvider + AssemblyAppVersionProvider"
```

---

## Task 2: `HeaderTokenRenderer` — Substitution Logic

**Files:**
- Create: `src/Backend/AHKFlowApp.Application/Services/HeaderTokenRenderer.cs`
- Create: `tests/AHKFlowApp.Application.Tests/Services/HeaderTokenRendererTests.cs`

This is the core of the spec. Tests come first.

- [ ] **Step 1: Tests — start with the simple cases**

```csharp
// tests/AHKFlowApp.Application.Tests/Services/HeaderTokenRendererTests.cs
using System.Globalization;
using System.Threading;
using AHKFlowApp.Application.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Services;

public sealed class HeaderTokenRendererTests
{
    private static readonly DateTimeOffset s_fixedTime =
        DateTimeOffset.Parse("2026-05-19T14:35:42Z", CultureInfo.InvariantCulture);

    private static HeaderTokenRenderer NewSut() => new();

    private static HeaderTokenRenderer.Context Ctx(
        string profileName = "Work",
        string appVersion = "1.2.3",
        int hotstrings = 12,
        int hotkeys = 12,
        DateTimeOffset? generatedAt = null) =>
        new(profileName, appVersion, hotstrings, hotkeys, generatedAt ?? s_fixedTime);

    [Fact]
    public void Substitutes_ProfileName()
    {
        NewSut().Render("Hello {ProfileName}", Ctx()).Should().Be("Hello Work");
    }

    [Fact]
    public void Substitutes_AppVersion()
    {
        NewSut().Render("v{AppVersion}", Ctx(appVersion: "9.9.9")).Should().Be("v9.9.9");
    }

    [Fact]
    public void Substitutes_HotstringCount_HotkeyCount()
    {
        NewSut().Render("{HotstringCount}h {HotkeyCount}k", Ctx(hotstrings: 7, hotkeys: 4))
            .Should().Be("7h 4k");
    }

    [Fact]
    public void Substitutes_GeneratedAt_DefaultFormat_o()
    {
        // The "o" (round-trip) format for the fixed UTC instant is deterministic.
        string expected = s_fixedTime.ToString("o", CultureInfo.InvariantCulture);
        NewSut().Render("at {GeneratedAt}", Ctx()).Should().Be($"at {expected}");
    }

    [Fact]
    public void Substitutes_GeneratedAt_CustomFormat()
    {
        NewSut().Render("{GeneratedAt:yyyy-MM-dd HH:mm}", Ctx())
            .Should().Be("2026-05-19 14:35");
    }

    [Fact]
    public void Preserves_UnknownTokens()
    {
        NewSut().Render("{Nope} {ProfileName}", Ctx()).Should().Be("{Nope} Work");
    }

    [Fact]
    public void EscapesLiteralBraces_DoubledOpenAndClose()
    {
        NewSut().Render("{{not a token}}", Ctx()).Should().Be("{not a token}");
    }

    [Fact]
    public void EscapeAdjacentToToken()
    {
        NewSut().Render("{{ {ProfileName} }}", Ctx()).Should().Be("{ Work }");
    }

    [Fact]
    public void Empty_ReturnsEmpty()
    {
        NewSut().Render("", Ctx()).Should().Be("");
    }

    [Fact]
    public void Renders_Multiline_Header()
    {
        string template = """
            ; {ProfileName} v{AppVersion}
            ; {HotstringCount} hotstrings
            ; {GeneratedAt:yyyy-MM-dd}
            """;
        string expected = """
            ; Work v1.2.3
            ; 12 hotstrings
            ; 2026-05-19
            """;
        NewSut().Render(template, Ctx()).Should().Be(expected);
    }

    [Fact]
    public void Uses_InvariantCulture_For_GeneratedAt()
    {
        CultureInfo original = Thread.CurrentThread.CurrentCulture;
        try
        {
            Thread.CurrentThread.CurrentCulture = new CultureInfo("de-DE");
            string rendered = NewSut().Render("{GeneratedAt:dd MMMM yyyy}", Ctx());
            // German would render "Mai"; invariant must render "May".
            rendered.Should().Be("19 May 2026");
        }
        finally
        {
            Thread.CurrentThread.CurrentCulture = original;
        }
    }

    [Fact]
    public void Uses_InvariantCulture_For_Counts()
    {
        CultureInfo original = Thread.CurrentThread.CurrentCulture;
        try
        {
            Thread.CurrentThread.CurrentCulture = new CultureInfo("de-DE");
            // 12 has no separators; use a larger number to prove the point.
            string rendered = NewSut().Render("{HotstringCount}", Ctx(hotstrings: 1234));
            // German would render "1.234"; invariant must render "1234".
            rendered.Should().Be("1234");
        }
        finally
        {
            Thread.CurrentThread.CurrentCulture = original;
        }
    }

    [Fact]
    public void Renders_When_NoBraces_AtAll()
    {
        NewSut().Render("plain content", Ctx()).Should().Be("plain content");
    }
}
```

- [ ] **Step 2: Run — expect build fail**

```bash
dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~HeaderTokenRendererTests"
```

- [ ] **Step 3: Implement `HeaderTokenRenderer`**

```csharp
// src/Backend/AHKFlowApp.Application/Services/HeaderTokenRenderer.cs
using System.Globalization;
using System.Text;

namespace AHKFlowApp.Application.Services;

/// <summary>
/// Substitutes recognized tokens in a header/footer template, then collapses
/// doubled braces (<c>{{</c> / <c>}}</c>) to literal single braces.
/// All formatting uses <see cref="CultureInfo.InvariantCulture"/> so generated
/// scripts are culture-independent.
/// </summary>
public sealed class HeaderTokenRenderer
{
    public readonly record struct Context(
        string ProfileName,
        string AppVersion,
        int HotstringCount,
        int HotkeyCount,
        DateTimeOffset GeneratedAt);

    public string Render(string template, Context ctx)
    {
        if (string.IsNullOrEmpty(template))
            return template;

        // Pass 1: substitute recognized tokens, leave unknown tokens as-is.
        // We walk character-by-character so escapes {{ / }} are preserved verbatim for pass 2.
        StringBuilder sb = new(template.Length + 64);
        int i = 0;
        while (i < template.Length)
        {
            char c = template[i];
            // Skip past escapes — they're handled in pass 2.
            if (c == '{' && i + 1 < template.Length && template[i + 1] == '{')
            {
                sb.Append('{').Append('{');
                i += 2;
                continue;
            }
            if (c == '}' && i + 1 < template.Length && template[i + 1] == '}')
            {
                sb.Append('}').Append('}');
                i += 2;
                continue;
            }
            if (c == '{')
            {
                int close = template.IndexOf('}', i + 1);
                if (close < 0)
                {
                    // Unterminated — append the rest verbatim.
                    sb.Append(template, i, template.Length - i);
                    break;
                }
                string raw = template.Substring(i + 1, close - i - 1); // between braces
                int colon = raw.IndexOf(':');
                string name = colon < 0 ? raw : raw[..colon];
                string? format = colon < 0 ? null : raw[(colon + 1)..];

                if (TryRender(name, format, ctx, out string replacement))
                {
                    sb.Append(replacement);
                }
                else
                {
                    // Unknown token — preserve verbatim, including braces.
                    sb.Append(template, i, close - i + 1);
                }
                i = close + 1;
                continue;
            }

            sb.Append(c);
            i++;
        }

        // Pass 2: collapse {{ → { and }} → }.
        string afterPass1 = sb.ToString();
        if (!afterPass1.Contains("{{", StringComparison.Ordinal)
            && !afterPass1.Contains("}}", StringComparison.Ordinal))
            return afterPass1;

        return afterPass1.Replace("{{", "{", StringComparison.Ordinal)
                         .Replace("}}", "}", StringComparison.Ordinal);
    }

    private static bool TryRender(string name, string? format, Context ctx, out string replacement)
    {
        switch (name)
        {
            case "ProfileName":
                replacement = ctx.ProfileName;
                return true;
            case "AppVersion":
                replacement = ctx.AppVersion;
                return true;
            case "HotstringCount":
                replacement = ctx.HotstringCount.ToString(CultureInfo.InvariantCulture);
                return true;
            case "HotkeyCount":
                replacement = ctx.HotkeyCount.ToString(CultureInfo.InvariantCulture);
                return true;
            case "GeneratedAt":
                replacement = ctx.GeneratedAt.ToString(format ?? "o", CultureInfo.InvariantCulture);
                return true;
            default:
                replacement = string.Empty;
                return false;
        }
    }
}
```

- [ ] **Step 4: Run tests — all pass**

Expected: 12 tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/Backend/AHKFlowApp.Application/Services/HeaderTokenRenderer.cs \
        tests/AHKFlowApp.Application.Tests/Services/HeaderTokenRendererTests.cs
git commit -m "feat: HeaderTokenRenderer with InvariantCulture + brace escaping"
```

---

## Task 3: Update `AhkScriptGenerator` to Use the Renderer

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/Services/AhkScriptGenerator.cs`
- Modify: `tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorTests.cs` (or sibling if path differs — inspect first).

- [ ] **Step 1: Find existing AhkScriptGenerator tests**

```bash
find tests -name "AhkScriptGeneratorTests.cs"
```

If a test file exists, add new test cases there. If not, create one at `tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorTests.cs`.

- [ ] **Step 2: Token substitution test**

```csharp
[Fact]
public void Generate_SubstitutesHeaderTokens()
{
    // arrange
    HeaderTokenRenderer renderer = new();
    FakeTimeProvider clock = new(DateTimeOffset.Parse("2026-05-19T12:00:00Z"));
    IAppVersionProvider version = Substitute.For<IAppVersionProvider>();
    version.GetVersion().Returns("1.2.3");

    AhkScriptGenerator sut = new(renderer, clock, version);

    Profile p = new ProfileBuilder()
        .WithOwner(Guid.NewGuid())
        .WithName("Work")
        .WithHeader("; {ProfileName} v{AppVersion} — {HotstringCount}h {HotkeyCount}k @ {GeneratedAt:yyyy-MM-dd}\n")
        .WithFooter("")
        .Build();

    var hs = new[]
    {
        new HotstringBuilder().WithOwner(p.OwnerOid).WithTrigger("btw").WithReplacement("by the way").Build(),
    };
    var hk = Array.Empty<Hotkey>();

    // act
    string output = sut.Generate(p, hs, hk);

    // assert
    output.Should().StartWith("; Work v1.2.3 — 1h 0k @ 2026-05-19");
}

[Fact]
public void Generate_PreservesUnknownTokens_InHeader()
{
    HeaderTokenRenderer renderer = new();
    FakeTimeProvider clock = new(DateTimeOffset.Parse("2026-05-19T12:00:00Z"));
    IAppVersionProvider version = Substitute.For<IAppVersionProvider>();
    version.GetVersion().Returns("1.2.3");
    AhkScriptGenerator sut = new(renderer, clock, version);

    Profile p = new ProfileBuilder().WithHeader("{Nope} hello\n").WithFooter("").Build();

    string output = sut.Generate(p, [], []);

    output.Should().Contain("{Nope} hello");
}

[Fact]
public void Generate_FooterIsAlsoRendered()
{
    HeaderTokenRenderer renderer = new();
    FakeTimeProvider clock = new(DateTimeOffset.Parse("2026-05-19T12:00:00Z"));
    IAppVersionProvider version = Substitute.For<IAppVersionProvider>();
    version.GetVersion().Returns("1.2.3");
    AhkScriptGenerator sut = new(renderer, clock, version);

    Profile p = new ProfileBuilder().WithHeader("").WithFooter("; bye v{AppVersion}").Build();

    string output = sut.Generate(p, [], []);

    output.Should().EndWith("; bye v1.2.3");
}
```

- [ ] **Step 3: Update `AhkScriptGenerator`**

Replace its constructor parameters and add the render call:

```csharp
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.Services;

public sealed class AhkScriptGenerator(
    HeaderTokenRenderer renderer,
    TimeProvider clock,
    IAppVersionProvider versions)
{
    private const string HotstringsSection = "; --- Hotstrings ---";
    private const string HotkeysSection = "; --- Hotkeys ---";

    public string Generate(
        Profile profile,
        IEnumerable<Hotstring> hotstrings,
        IEnumerable<Hotkey> hotkeys)
    {
        ArgumentNullException.ThrowIfNull(profile);
        ArgumentNullException.ThrowIfNull(hotstrings);
        ArgumentNullException.ThrowIfNull(hotkeys);

        // Materialize to count once. Lists are typically small.
        List<Hotstring> hsList = hotstrings.OrderBy(h => h.Trigger, StringComparer.Ordinal).ToList();
        List<Hotkey> hkList = hotkeys.OrderBy(h => h.Description, StringComparer.Ordinal).ToList();

        HeaderTokenRenderer.Context ctx = new(
            ProfileName: profile.Name,
            AppVersion: versions.GetVersion(),
            HotstringCount: hsList.Count,
            HotkeyCount: hkList.Count,
            GeneratedAt: clock.GetUtcNow());

        List<string> lines = [renderer.Render(profile.HeaderTemplate, ctx), HotstringsSection];

        foreach (Hotstring hs in hsList)
            lines.Add(FormatHotstring(hs));

        lines.Add(HotkeysSection);

        foreach (Hotkey hk in hkList)
            lines.Add(FormatHotkey(hk));

        lines.Add(renderer.Render(profile.FooterTemplate, ctx));

        return string.Join("\n", lines);
    }

    private static string FormatHotstring(Hotstring hs)
    {
        string options = "";
        if (!hs.IsEndingCharacterRequired) options += "*";
        if (hs.IsTriggerInsideWord) options += "?";
        return $":{options}:{hs.Trigger}::{hs.Replacement}";
    }

    private static string FormatHotkey(Hotkey hk)
    {
        string prefix = "";
        if (hk.Ctrl) prefix += "^";
        if (hk.Alt) prefix += "!";
        if (hk.Shift) prefix += "+";
        if (hk.Win) prefix += "#";

        string fn = hk.Action switch
        {
            HotkeyAction.Send => "Send",
            HotkeyAction.Run => "Run",
            _ => throw new InvalidOperationException($"Unsupported HotkeyAction: {hk.Action}"),
        };

        return $"{prefix}{hk.Key}::{fn}(\"{hk.Parameters}\")";
    }
}
```

- [ ] **Step 4: Run tests — pass**

```bash
dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~AhkScriptGeneratorTests"
```

Pre-existing tests that construct `AhkScriptGenerator` directly (without DI) will break. Fix them by passing the new ctor args: `new AhkScriptGenerator(new HeaderTokenRenderer(), TimeProvider.System, Substitute.For<IAppVersionProvider>())` — and stub the version.

- [ ] **Step 5: Commit**

```bash
git add src/Backend/AHKFlowApp.Application/Services/AhkScriptGenerator.cs \
        tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorTests.cs
git commit -m "feat: AhkScriptGenerator renders header/footer through HeaderTokenRenderer"
```

---

## Task 4: New Default Header Constant

**Files:**
- Modify: `src/Backend/AHKFlowApp.Domain/Constants/DefaultProfileTemplates.cs`

- [ ] **Step 1: Replace the constant**

```csharp
namespace AHKFlowApp.Domain.Constants;

public static class DefaultProfileTemplates
{
    public const string Header = """
        ; {ProfileName} — AHKFlowApp v{AppVersion}
        ; {HotstringCount} hotstrings, {HotkeyCount} hotkeys
        ; Generated {GeneratedAt:yyyy-MM-dd HH:mm}Z

        #Requires AutoHotkey v2.0
        #SingleInstance Force
        #Warn All, Off
        SendMode "Input"
        SetWorkingDir A_ScriptDir
        SetTitleMatchMode 2

        """;

    public const string Footer = "";
}
```

Note: removed `SetCapsLockState "AlwaysOff"` (surprising side-effect, per spec).

- [ ] **Step 2: Commit**

```bash
git add src/Backend/AHKFlowApp.Domain/Constants/DefaultProfileTemplates.cs
git commit -m "feat: richer default header with token placeholders"
```

---

## Task 5: DI Registration

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/DependencyInjection.cs`
- Modify: `src/Backend/AHKFlowApp.API/Program.cs` (or wherever Infrastructure services are registered).

- [ ] **Step 1: Register `HeaderTokenRenderer` in Application DI**

In `AddApplication`, add before `AddSingleton<AhkScriptGenerator>()`:

```csharp
services.AddSingleton<HeaderTokenRenderer>();
```

- [ ] **Step 2: Register `IAppVersionProvider` in Infrastructure DI**

Find the Infrastructure DI extension method (search: `AddInfrastructure` or look in `src/Backend/AHKFlowApp.Infrastructure/`). Add:

```csharp
services.AddSingleton<IAppVersionProvider, AssemblyAppVersionProvider>();
```

If no Infrastructure DI extension exists, add the registration in `Program.cs` next to the existing service registrations.

- [ ] **Step 3: Ensure `TimeProvider.System` is registered**

`Microsoft.Extensions.Hosting` registers `TimeProvider.System` by default in .NET 8+, but if the API project pins an older `Hosting` version this may be missing. Search the Program.cs for `TimeProvider`. If absent, add:

```csharp
services.AddSingleton(TimeProvider.System);
```

- [ ] **Step 4: Verify the app starts**

```bash
dotnet run --project src/Backend/AHKFlowApp.API --launch-profile "Docker SQL (Recommended)"
```

Hit `GET /api/v1/downloads/<some-profile-id>` (after login) and confirm the response.

- [ ] **Step 5: Commit**

```bash
git add src/Backend/AHKFlowApp.Application/DependencyInjection.cs \
        src/Backend/AHKFlowApp.API/Program.cs
git commit -m "chore: register HeaderTokenRenderer and IAppVersionProvider"
```

(Or whichever files were actually modified.)

---

## Task 6: End-to-End Integration Test

**Files:**
- Modify: `tests/AHKFlowApp.API.Tests/Downloads/` — a sibling test file (find one with `find tests/AHKFlowApp.API.Tests -name "Downloads*"`).

- [ ] **Step 1: Add a test that hits the download endpoint and asserts the rendered header**

```csharp
[Fact]
public async Task GetProfileScript_RendersHeaderTokens()
{
    using AuthenticatedClient client = await fx.AuthenticateAsync();

    // Create a profile with a header that uses every token.
    var profile = await client.Profiles.CreateAsync(new CreateProfileDto(
        Name: "Renderer Test",
        IsDefault: false,
        HeaderTemplate: """
            ; {ProfileName} v{AppVersion} — {HotstringCount}h {HotkeyCount}k
            ; Generated {GeneratedAt:yyyy-MM-dd}

            """,
        FooterTemplate: ""));

    HttpResponseMessage resp = await client.GetAsync($"/api/v1/downloads/{profile.Id}");
    resp.EnsureSuccessStatusCode();
    string content = await resp.Content.ReadAsStringAsync();

    content.Should().StartWith("; Renderer Test v");
    content.Should().Contain("0h 0k");
    content.Should().MatchRegex(@"Generated \d{4}-\d{2}-\d{2}");
}
```

Adapt the bootstrap (`AuthenticatedClient`, `client.Profiles`) to whatever helpers the existing Downloads tests use. The point is: round-trip through HTTP → handler → generator → renderer.

- [ ] **Step 2: Run + commit**

```bash
dotnet test tests/AHKFlowApp.API.Tests --filter "FullyQualifiedName~Downloads"
git add tests/AHKFlowApp.API.Tests/Downloads/
git commit -m "test: end-to-end header token substitution"
```

---

## Task 7: Final Verification

- [ ] **Step 1: Full build + test**

```bash
dotnet build --no-restore
dotnet test --no-build --verbosity normal
```

- [ ] **Step 2: Format**

```bash
dotnet format
git add -u
git commit -m "chore: dotnet format" --allow-empty=false 2>&1 || echo "nothing to format"
```

- [ ] **Step 3: Manual smoke**

1. Start the stack.
2. Create a fresh profile (or use the auto-seeded Default after a fresh DB).
3. Download the `.ahk` script.
4. Open it — verify the comment header reads e.g.:
   ```
   ; Default — AHKFlowApp v<your-version>
   ; 0 hotstrings, 0 hotkeys
   ; Generated 2026-05-19 14:35Z
   ```
5. Edit the profile's `HeaderTemplate` to include `{{ literal }}` and verify it renders as `{ literal }` (no token substitution attempted inside the doubled braces).

---

## Self-Review Checklist

- [ ] `HeaderTokenRenderer` always calls `.ToString(..., CultureInfo.InvariantCulture)`.
- [ ] `Render("")` returns `""` (no exception).
- [ ] Unknown tokens like `{NotARealToken}` are preserved verbatim in the output.
- [ ] `{{` → `{` and `}}` → `}` after pass 1.
- [ ] `AhkScriptGenerator` ctor takes `HeaderTokenRenderer`, `TimeProvider`, `IAppVersionProvider`.
- [ ] `HeaderTokenRenderer` and `IAppVersionProvider` are registered as `AddSingleton`.
- [ ] `DefaultProfileTemplates.Header` matches the spec exactly (no leftover `SetCapsLockState`).
- [ ] At least one test sets `Thread.CurrentThread.CurrentCulture = new CultureInfo("de-DE")` and asserts the invariant output (covers the AGENTS.md "explicit InvariantCulture" rule).
- [ ] `dotnet format` clean.

---

## Out of Scope

- Multiple built-in header presets — `Multiple built-in presets` was explicitly rejected during brainstorming in favor of "Richer default + tokens".
- Per-profile date format preferences — `{GeneratedAt:fmt}` already gives users full control via the template.
- Footer-only tokens — same token set is supported in both header and footer; no distinction.
- Backporting tokens to existing user-customized headers — no migration; tokens substitute in whatever template is stored at generation time.
