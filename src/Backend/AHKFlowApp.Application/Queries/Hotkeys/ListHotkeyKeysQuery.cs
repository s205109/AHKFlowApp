using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Constants;
using AHKFlowApp.Application.DTOs;
using Ardalis.Result;

namespace AHKFlowApp.Application.Queries.Hotkeys;

/// <summary>Returns the canonical key registry for the UI key picker. Static reference data.</summary>
public sealed record ListHotkeyKeysQuery();

internal sealed class ListHotkeyKeysQueryHandler
    : IUseCaseHandler<ListHotkeyKeysQuery, Result<HotkeyKeyCatalogDto>>
{
    // Projected once: the registry is immutable for the process lifetime.
    private static readonly HotkeyKeyCatalogDto s_catalog = Project();

    public Task<Result<HotkeyKeyCatalogDto>> ExecuteAsync(ListHotkeyKeysQuery request, CancellationToken ct) =>
        Task.FromResult(Result<HotkeyKeyCatalogDto>.Success(s_catalog));

    private static HotkeyKeyCatalogDto Project() => new(
        [.. HotkeyKeys.All.Select(e => new HotkeyKeyDto(
            e.Canonical, e.Group, RoleNames(e.Roles), e.RequiresBracesInSend))],
        HotkeyKeys.Aliases);

    // Flags -> names, excluding the None sentinel and the All aggregate so the wire format
    // lists only the five real roles.
    private static string[] RoleNames(HotkeyKeyRoles roles) =>
    [
        .. Enum.GetValues<HotkeyKeyRoles>()
            .Where(r => r is not HotkeyKeyRoles.None and not HotkeyKeyRoles.All && roles.HasFlag(r))
            .Select(r => r.ToString())
    ];
}
