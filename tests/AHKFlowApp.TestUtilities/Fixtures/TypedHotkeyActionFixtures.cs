using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.TestUtilities.Fixtures;

/// <summary>
/// One typed hotkey action case for restore/revert testing: the original create payload
/// and optionally what kind to overwrite it to before reverting (null → defaults to Disable).
/// </summary>
public sealed record TypedHotkeyActionCase(
    CreateHotkeyDto Original,
    HotkeyActionKind? OverwriteKindForRevert);

/// <summary>
/// Shared test data for restore and revert round-trip tests: one create payload per
/// <see cref="HotkeyActionKind"/>, ensuring all action kinds serialize and deserialize correctly.
/// Separate restore payloads from revert cases because revert overwrites before reverting —
/// the Disable case must overwrite to something else to prove state actually changes.
/// </summary>
public static class TypedHotkeyActionFixtures
{
    public static IReadOnlyList<CreateHotkeyDto> RestorePayloads { get; } = BuildRestorePayloads();
    public static IReadOnlyList<TypedHotkeyActionCase> RevertCases { get; } = BuildRevertCases();

    /// <summary>
    /// The payload for one kind. Both lists hold exactly one entry per <see cref="HotkeyActionKind"/>,
    /// so the kind is a stable id — and an enum serializes, which a <c>CreateHotkeyDto</c> does not.
    /// The theories that use these pass the kind and look the payload up here, so each case gets its
    /// own test id instead of all seven sharing one.
    /// <para><c>Single</c>, not <c>First</c>: a kind added to the enum with no entry here, or a
    /// second entry for one kind, must fail loudly rather than silently drop a case.</para>
    /// </summary>
    public static CreateHotkeyDto RestorePayloadFor(HotkeyActionKind kind) =>
        RestorePayloads.Single(p => p.ActionKind == kind);

    /// <inheritdoc cref="RestorePayloadFor"/>
    public static TypedHotkeyActionCase RevertCaseFor(HotkeyActionKind kind) =>
        RevertCases.Single(c => c.Original.ActionKind == kind);

    private static IReadOnlyList<CreateHotkeyDto> BuildRestorePayloads() =>
    [
        new CreateHotkeyDto("run", "f2", HotkeyActionKind.Run,
            RunTarget: "notepad.exe", RunTargetKind: RunTargetKind.Application, AppliesToAllProfiles: true),
        new CreateHotkeyDto("text", "f3", HotkeyActionKind.SendText,
            Text: "hello world", AppliesToAllProfiles: true),
        new CreateHotkeyDto("keys", "f4", HotkeyActionKind.SendKeys,
            SendKeysContent: "^v", AppliesToAllProfiles: true),
        new CreateHotkeyDto("window", "f5", HotkeyActionKind.Window,
            WindowOp: WindowOp.Close, AppliesToAllProfiles: true),
        new CreateHotkeyDto("remap", "a", HotkeyActionKind.Remap,
            RemapDest: "b", AppliesToAllProfiles: true),
        new CreateHotkeyDto("raw", "f6", HotkeyActionKind.Raw,
            Body: "MsgBox \"hi\"", AppliesToAllProfiles: true),
        new CreateHotkeyDto("disable", "f7", HotkeyActionKind.Disable, AppliesToAllProfiles: true),
    ];

    private static IReadOnlyList<TypedHotkeyActionCase> BuildRevertCases() =>
    [
        // Most cases overwrite to Disable, then revert back to the original. For Disable itself,
        // overwrite to Run to ensure the revert genuinely changes state (not vacuous Disable → Disable).
        new(BuildRestorePayloads()[0], null), // Run → Disable → Run
        new(BuildRestorePayloads()[1], null), // SendText → Disable → SendText
        new(BuildRestorePayloads()[2], null), // SendKeys → Disable → SendKeys
        new(BuildRestorePayloads()[3], null), // Window → Disable → Window
        new(BuildRestorePayloads()[4], null), // Remap → Disable → Remap
        new(BuildRestorePayloads()[5], null), // Raw → Disable → Raw
        new(BuildRestorePayloads()[6], HotkeyActionKind.Run), // Disable → Run → Disable
    ];
}
