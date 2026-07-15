using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Enums;
using Swashbuckle.AspNetCore.Filters;

namespace AHKFlowApp.API.OpenApi.Examples;

internal sealed class CreateHotstringDtoExample : IExamplesProvider<CreateHotstringDto>
{
    public CreateHotstringDto GetExamples() => new(
        Trigger: "btw",
        Replacement: "by the way",
        ProfileIds: null,
        AppliesToAllProfiles: true,
        IsEndingCharacterRequired: true,
        IsTriggerInsideWord: true,
        Delivery: HotstringDelivery.Auto);
}

internal sealed class UpdateHotstringDtoExample : IExamplesProvider<UpdateHotstringDto>
{
    public UpdateHotstringDto GetExamples() => new(
        Trigger: "btw",
        Replacement: "by the way",
        ProfileIds: null,
        AppliesToAllProfiles: true,
        IsEndingCharacterRequired: true,
        IsTriggerInsideWord: true,
        Description: "Common chat abbreviation");
}

internal sealed class HotstringDtoExample : IExamplesProvider<HotstringDto>
{
    public HotstringDto GetExamples() => new(
        Id: Guid.Parse("11111111-1111-1111-1111-111111111111"),
        ProfileIds: [],
        AppliesToAllProfiles: true,
        Trigger: "btw",
        Replacement: "by the way",
        Description: "Common chat abbreviation",
        IsEndingCharacterRequired: true,
        IsTriggerInsideWord: true,
        CreatedAt: DateTimeOffset.Parse("2026-04-17T09:00:00Z"),
        UpdatedAt: DateTimeOffset.Parse("2026-04-17T09:00:00Z"),
        CategoryIds: []);
}

internal sealed class PagedHotstringsExample : IExamplesProvider<PagedList<HotstringDto>>
{
    public PagedList<HotstringDto> GetExamples() => new(
        Items: [new HotstringDtoExample().GetExamples()],
        Page: 1,
        PageSize: 50,
        TotalCount: 1);
}

// App-specific (window context) example, targeting the preview endpoint's DTOs rather than
// HotstringDto/CreateHotstringDto/UpdateHotstringDto — Swashbuckle.AspNetCore.Filters resolves
// one IExamplesProvider<T> per T, so a second example on an already-covered type would silently
// replace the "btw" example everywhere it's used. HotstringPreviewRequestDto/HotstringPreviewDto
// had no example yet, making them a clean place to show the context scenario end-to-end.
internal sealed class HotstringPreviewRequestDtoExample : IExamplesProvider<HotstringPreviewRequestDto>
{
    public HotstringPreviewRequestDto GetExamples() => new(
        Kind: HotstringKind.Text,
        Trigger: "sig",
        Replacement: "Best regards,\nJohn Doe\nSales Team",
        IsCaseSensitive: false,
        OmitEndingCharacter: false,
        IsEndingCharacterRequired: true,
        IsTriggerInsideWord: false,
        ContextMatchType: WindowMatchType.Executable,
        ContextValue: "outlook.exe",
        Delivery: HotstringDelivery.Auto);
}

internal sealed class HotstringPreviewDtoExample : IExamplesProvider<HotstringPreviewDto>
{
    // Matches HotstringEmitter.Emit + GetHotstringPreviewQueryHandler's #HotIf wrapping exactly:
    // context groups are wrapped in `#HotIf WinActive(...)` ... bare `#HotIf` (D9).
    public HotstringPreviewDto GetExamples() => new(
        Snippet: "#HotIf WinActive(\"ahk_exe outlook.exe\")\n:T:sig::Best regards,`nJohn Doe`nSales Team\n#HotIf",
        EffectiveDelivery: HotstringDelivery.Type);
}

// Raw kind: `~ver` with a brace body, stored verbatim in Replacement. Targets
// HotstringHistoryVersionDto — the actual response type on HotstringsController's history-version
// endpoint — rather than HotstringSnapshot (nested inside it; Swashbuckle.AspNetCore.Filters only
// annotates examples on operation-level request/response types, not nested property types, so an
// example on the nested type alone never surfaces in swagger.json) or HotstringDto/CreateHotstringDto/
// UpdateHotstringDto/HotstringPreviewRequestDto/HotstringPreviewDto (all already covered above,
// per the same one-provider-per-type trap documented there). HotstringHistoryVersionDto had no
// example yet, making it a clean, unused vehicle for this scenario.
internal sealed class HotstringHistoryVersionDtoExample : IExamplesProvider<HotstringHistoryVersionDto>
{
    public HotstringHistoryVersionDto GetExamples() => new(
        Version: 1,
        ChangeType: HistoryChangeType.Edit,
        CapturedAt: DateTimeOffset.Parse("2026-07-11T09:00:00Z"),
        Snapshot: new HotstringSnapshot(
            Trigger: "~ver",
            Replacement: ":*:~ver::\n{\nMsgBox A_AhkVersion\n}",
            Description: "Show the running AutoHotkey version",
            AppliesToAllProfiles: true,
            IsEndingCharacterRequired: false,
            IsTriggerInsideWord: false,
            ProfileIds: [],
            CategoryIds: [],
            CreatedAt: DateTimeOffset.Parse("2026-07-11T09:00:00Z"),
            UpdatedAt: DateTimeOffset.Parse("2026-07-11T09:00:00Z"),
            Kind: HotstringKind.Raw));
}
