using AHKFlowApp.Application.DTOs;
using Swashbuckle.AspNetCore.Filters;

namespace AHKFlowApp.API.OpenApi.Examples;

internal sealed class CreateHotstringDtoExample : IExamplesProvider<CreateHotstringDto>
{
    public CreateHotstringDto GetExamples() => new(
        Trigger: "btw",
        Replacement: "by the way",
        ProfileId: null,
        IsEndingCharacterRequired: true,
        IsTriggerInsideWord: true);
}

internal sealed class UpdateHotstringDtoExample : IExamplesProvider<UpdateHotstringDto>
{
    public UpdateHotstringDto GetExamples() => new(
        Trigger: "btw",
        Replacement: "by the way",
        ProfileId: null,
        IsEndingCharacterRequired: true,
        IsTriggerInsideWord: true);
}

internal sealed class HotstringDtoExample : IExamplesProvider<HotstringDto>
{
    public HotstringDto GetExamples() => new(
        Id: Guid.Parse("11111111-1111-1111-1111-111111111111"),
        ProfileId: null,
        Trigger: "btw",
        Replacement: "by the way",
        IsEndingCharacterRequired: true,
        IsTriggerInsideWord: true,
        CreatedAt: DateTimeOffset.Parse("2026-04-17T09:00:00Z"),
        UpdatedAt: DateTimeOffset.Parse("2026-04-17T09:00:00Z"));
}

internal sealed class PagedHotstringsExample : IExamplesProvider<PagedList<HotstringDto>>
{
    public PagedList<HotstringDto> GetExamples() => new(
        Items: [new HotstringDtoExample().GetExamples()],
        Page: 1,
        PageSize: 50,
        TotalCount: 1);
}
