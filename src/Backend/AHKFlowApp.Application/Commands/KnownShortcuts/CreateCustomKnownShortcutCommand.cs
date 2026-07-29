using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Common;
using AHKFlowApp.Application.Constants;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using Ardalis.Result;
using FluentValidation;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.KnownShortcuts;

/// <summary>Records something the owner knows uses a combination.</summary>
public sealed record CreateCustomKnownShortcutCommand(CreateCustomKnownShortcutDto Input);

public sealed class CreateCustomKnownShortcutCommandValidator
    : AbstractValidator<CreateCustomKnownShortcutCommand>
{
    public CreateCustomKnownShortcutCommandValidator()
    {
        RuleFor(x => x.Input.Key)
            .NotEmpty().WithMessage("Pick a key.")
            .Must(HotkeyKeys.IsValidHotkeyKey)
            .WithMessage("That is not a key AHKFlow can use in a hotkey.");

        RuleFor(x => x.Input.UsedBy)
            .NotEmpty().WithMessage("Say what uses these keys.")
            .MaximumLength(60);

        // Does is dropped straight into "<UsedBy> uses <combo> to …", so its shape is part of the
        // sentence, not a free-text field. Two rules keep that sentence readable and honest.
        RuleFor(x => x.Input.Does)
            .NotEmpty().WithMessage("Say what the keys do.")
            .MaximumLength(200)
            .Must(StartsLowercase)
            .WithMessage("Start with a lowercase verb, like \"open the settings window\".")
            .Must(MakesNoAbsoluteClaim)
            .WithMessage("Say what the keys do, not what will or will not happen.");

        // Protected means a Microsoft source says Windows itself handles the keys. An owner has
        // no way to supply that source, so the value is not theirs to set.
        RuleFor(x => x.Input.Protection)
            .Must(p => p is ShortcutProtection.Normal or ShortcutProtection.Unknown)
            .WithMessage("Only built-in records can say Windows handles the keys itself.");

        RuleFor(x => x.Input.Scope).IsInEnum();
    }

    // A leading capital would read as "Windows uses Win+E to Open File Explorer." Only the first
    // character is judged: a product name later in the phrase is fine, and often required.
    // Anything that is not a letter — a digit, a quote — passes, because there is no case to get
    // wrong. The text is trimmed first, because the handler stores the trimmed value: without this
    // a leading space would let a capital through.
    private static bool StartsLowercase(string? does)
    {
        string trimmed = does?.Trim() ?? string.Empty;

        return trimmed.Length == 0 || !char.IsUpper(trimmed[0]);
    }

    // The same ban the built-in manifest lives under, applied to owner text. An owner record ends
    // up in the same warning sentence as a curated one, so it inherits the same promise: describe
    // the use, never predict the outcome. Kept in one place so the manifest test and this rule
    // cannot drift apart.
    private static bool MakesNoAbsoluteClaim(string? does) =>
        does is null || !ShortcutWording.MakesAbsoluteClaim(does);
}

internal sealed class CreateCustomKnownShortcutCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock)
    : IUseCaseHandler<CreateCustomKnownShortcutCommand, Result<ManagedKnownShortcutCatalogDto>>
{
    private const string DuplicateMessage =
        "You have already recorded this key + modifier combination for that name.";

    public async Task<Result<ManagedKnownShortcutCatalogDto>> ExecuteAsync(
        CreateCustomKnownShortcutCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        CreateCustomKnownShortcutDto input = request.Input;
        HotkeyKeys.TryCanonicalize(input.Key, out string canonicalKey);
        string usedBy = input.UsedBy.Trim();
        string does = input.Does.Trim();

        bool duplicate = await db.CustomKnownShortcuts.AnyAsync(
            s => s.OwnerOid == ownerOid
              && s.Key == canonicalKey
              && s.Ctrl == input.Ctrl
              && s.Alt == input.Alt
              && s.Shift == input.Shift
              && s.Win == input.Win
              && s.UsedBy == usedBy,
            ct);

        if (duplicate)
            return Result.Conflict(DuplicateMessage);

        db.CustomKnownShortcuts.Add(CustomKnownShortcut.Create(
            ownerOid, canonicalKey, input.Ctrl, input.Alt, input.Shift, input.Win,
            usedBy, input.Protection, input.Scope, does, clock));

        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException ex) when (ex.IsDuplicateKeyViolation())
        {
            // The AnyAsync check above cannot stop two requests that pass it at the same time. The
            // unique index does stop them, and this turns the second one into the promised 409
            // instead of a 500.
            return Result.Conflict(DuplicateMessage);
        }

        return await ReloadAsync(db, ownerOid, ct);
    }

    // Returns the whole merged list so the page never renders a half-updated view.
    private static async Task<Result<ManagedKnownShortcutCatalogDto>> ReloadAsync(
        IAppDbContext db, Guid ownerOid, CancellationToken ct)
    {
        (CustomKnownShortcut[] owned, IgnoredKnownShortcut[] ignored) =
            await OwnerKnownShortcutLoader.LoadAsync(db, ownerOid, ct);

        return Result<ManagedKnownShortcutCatalogDto>.Success(
            new ManagedKnownShortcutCatalogDto(KnownShortcutMerge.ForManagement(owned, ignored)));
    }
}
