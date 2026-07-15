namespace AHKFlowApp.CLI.Services;

public interface IHotstringsApiClient
{
    Task<HotstringDto> CreateAsync(CreateHotstringDto input, CancellationToken ct);

    Task<PagedList<HotstringDto>> ListAsync(
        Guid? profileId,
        string? search,
        int page,
        int pageSize,
        CancellationToken ct);
}

public enum HotstringKind
{
    Text = 0,
    DateTime = 1,
    Macro = 2,
    Raw = 4,
}

public enum HotstringDelivery
{
    Auto = 0,
    Type = 1,
    ClipboardPaste = 2,
}

public enum DateOffsetUnit
{
    Seconds = 0,
    Minutes = 1,
    Hours = 2,
    Days = 3,
}

public enum WindowMatchType
{
    Executable = 0,
    WindowClass = 1,
    TitleContains = 2,
}

public sealed record HotstringDto(
    Guid Id,
    Guid[] ProfileIds,
    bool AppliesToAllProfiles,
    string Trigger,
    string Replacement,
    bool IsEndingCharacterRequired,
    bool IsTriggerInsideWord,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt,
    HotstringKind Kind = HotstringKind.Text,
    bool IsCaseSensitive = false,
    bool OmitEndingCharacter = false,
    string? DateTimeFormat = null,
    int? DateOffsetAmount = null,
    DateOffsetUnit? DateOffsetUnit = null,
    WindowMatchType? ContextMatchType = null,
    string? ContextValue = null,
    HotstringDelivery Delivery = HotstringDelivery.Auto,
    // Set by the list endpoint when it shortened a long Text replacement; detail responses
    // (create) always carry the full text. Surfaced so `--json` consumers can tell a preview
    // from a complete replacement rather than silently reading truncated text as the real value.
    bool ReplacementIsTruncated = false);

public sealed record CreateHotstringDto(
    string Trigger,
    string Replacement,
    Guid[]? ProfileIds = null,
    bool AppliesToAllProfiles = true,
    bool IsEndingCharacterRequired = true,
    bool IsTriggerInsideWord = true,
    HotstringKind Kind = HotstringKind.Text,
    HotstringDelivery Delivery = HotstringDelivery.Auto);

public sealed record PagedList<T>(
    IReadOnlyList<T> Items,
    int Page,
    int PageSize,
    int TotalCount)
{
    public int TotalPages => PageSize == 0 ? 0 : (int)Math.Ceiling(TotalCount / (double)PageSize);
    public bool HasNextPage => Page < TotalPages;
    public bool HasPreviousPage => Page > 1;
}
