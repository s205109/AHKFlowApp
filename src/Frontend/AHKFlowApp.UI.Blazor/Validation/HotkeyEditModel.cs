using System.ComponentModel.DataAnnotations;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;

namespace AHKFlowApp.UI.Blazor.Validation;

public sealed class HotkeyEditModel
{
    public const int TextMaxLength = 4_000;
    public const int BodyMaxLength = 4_000;
    public const int RunTargetMaxLength = 500;

    public Guid? Id { get; set; }

    [Required(ErrorMessage = "Description is required.")]
    [MaxLength(200, ErrorMessage = "Description must be 200 characters or fewer.")]
    public string Description { get; set; } = "";

    [Required(ErrorMessage = "Key is required.")]
    [MaxLength(20, ErrorMessage = "Key must be 20 characters or fewer.")]
    public string Key { get; set; } = "";

    public bool Ctrl { get; set; }
    public bool Alt { get; set; }
    public bool Shift { get; set; }
    public bool Win { get; set; }

    public HotkeyActionKind ActionKind { get; set; } = HotkeyActionKind.SendText;

    // Legacy members, retired in Task 10. Pages/Hotkeys.razor:155-158 still binds Action until
    // Task 9 replaces that column, and five test files still construct it. Not written to the
    // wire by ToCreateDto/ToUpdateDto — the typed fields are the contract.
    public HotkeyAction Action { get; set; } = HotkeyAction.Send;
    public string Parameters { get; set; } = "";

    // Per-kind fields. All are retained across kind switches so a user who toggles away and
    // back does not lose typed work; gating to the active kind happens once, on the wire, in
    // ToCreateDto / ToUpdateDto / ToPreviewRequest. Server validation is both-or-neither, so
    // sending a field belonging to an inactive kind is a 400.
    public string? Text { get; set; }
    public string? SendKeysContent { get; set; }
    public string? RunTarget { get; set; }
    public RunTargetKind? RunTargetKind { get; set; }
    public WindowOp? WindowOp { get; set; }
    public string? RemapDest { get; set; }
    public string? Body { get; set; }

    public bool AppliesToAllProfiles { get; set; } = true;
    public List<Guid> ProfileIds { get; set; } = [];
    public List<Guid> CategoryIds { get; set; } = [];

    /// <summary>
    /// Grid rows offer inline edit only for the two kinds whose whole payload is a single text
    /// field, and only when the key would survive server-side validation. The key clause is what
    /// surfaces legacy rows the action migration could not rewrite: they route to the dialog,
    /// where the existing field-level error already appears on open. No extra UI, per spec §8.
    /// </summary>
    public bool IsInlineEditable(IHotkeyKeyCatalog catalog) =>
        ActionKind is HotkeyActionKind.SendText or HotkeyActionKind.Run
        && catalog.IsValidKey(Key);

    public static HotkeyEditModel FromDto(HotkeyDto dto) => new()
    {
        Id = dto.Id,
        Description = dto.Description,
        Key = dto.Key,
        Ctrl = dto.Ctrl,
        Alt = dto.Alt,
        Shift = dto.Shift,
        Win = dto.Win,
        ActionKind = dto.ActionKind,
        Text = dto.Text,
        SendKeysContent = dto.SendKeysContent,
        RunTarget = dto.RunTarget,
        RunTargetKind = dto.RunTargetKind,
        WindowOp = dto.WindowOp,
        RemapDest = dto.RemapDest,
        Body = dto.Body,
        Action = dto.Action,
        Parameters = dto.Parameters,
        AppliesToAllProfiles = dto.AppliesToAllProfiles,
        ProfileIds = [.. dto.ProfileIds],
        CategoryIds = [.. dto.CategoryIds ?? []],
    };

    public HotkeyEditModel Clone() => new()
    {
        Id = Id,
        Description = Description,
        Key = Key,
        Ctrl = Ctrl,
        Alt = Alt,
        Shift = Shift,
        Win = Win,
        ActionKind = ActionKind,
        Text = Text,
        SendKeysContent = SendKeysContent,
        RunTarget = RunTarget,
        RunTargetKind = RunTargetKind,
        WindowOp = WindowOp,
        RemapDest = RemapDest,
        Body = Body,
        Action = Action,
        Parameters = Parameters,
        AppliesToAllProfiles = AppliesToAllProfiles,
        ProfileIds = [.. ProfileIds],
        CategoryIds = [.. CategoryIds],
    };

    public CreateHotkeyDto ToCreateDto()
    {
        ActionFields f = ActiveFields();
        return new(Description, Key, ActionKind, Ctrl, Alt, Shift, Win,
            f.Text, f.SendKeysContent, f.RunTarget, f.RunTargetKind, f.WindowOp, f.RemapDest, f.Body,
            AppliesToAllProfiles ? null : [.. ProfileIds], AppliesToAllProfiles, [.. CategoryIds]);
    }

    public UpdateHotkeyDto ToUpdateDto()
    {
        ActionFields f = ActiveFields();
        return new(Description, Key, ActionKind, Ctrl, Alt, Shift, Win,
            f.Text, f.SendKeysContent, f.RunTarget, f.RunTargetKind, f.WindowOp, f.RemapDest, f.Body,
            AppliesToAllProfiles ? null : [.. ProfileIds], AppliesToAllProfiles, [.. CategoryIds]);
    }

    public HotkeyPreviewRequestDto ToPreviewRequest()
    {
        ActionFields f = ActiveFields();
        return new(Description, Key, ActionKind, Ctrl, Alt, Shift, Win,
            f.Text, f.SendKeysContent, f.RunTarget, f.RunTargetKind, f.WindowOp, f.RemapDest, f.Body);
    }

    /// <summary>The single place that knows which fields each kind owns.</summary>
    private ActionFields ActiveFields() => ActionKind switch
    {
        HotkeyActionKind.SendText => new() { Text = Text },
        HotkeyActionKind.SendKeys => new() { SendKeysContent = SendKeysContent },
        HotkeyActionKind.Run => new() { RunTarget = RunTarget, RunTargetKind = RunTargetKind },
        HotkeyActionKind.Window => new() { WindowOp = WindowOp },
        HotkeyActionKind.Remap => new() { RemapDest = RemapDest },
        HotkeyActionKind.Disable => new(),
        HotkeyActionKind.Raw => new() { Body = Body },
        _ => new(),
    };

    private sealed record ActionFields
    {
        public string? Text { get; init; }
        public string? SendKeysContent { get; init; }
        public string? RunTarget { get; init; }
        public RunTargetKind? RunTargetKind { get; init; }
        public WindowOp? WindowOp { get; init; }
        public string? RemapDest { get; init; }
        public string? Body { get; init; }
    }
}
