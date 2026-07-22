using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Common;
using AHKFlowApp.Application.Constants;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Application.Validation;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using FluentValidation;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Hotkeys;

public sealed record CreateHotkeyCommand(CreateHotkeyDto Input);

public sealed class CreateHotkeyCommandValidator : AbstractValidator<CreateHotkeyCommand>
{
    public CreateHotkeyCommandValidator()
    {
        RuleFor(x => x.Input.Description).ValidDescription();
        RuleFor(x => x.Input.Key).ValidKey();
        RuleFor(x => x.Input.Parameters).ValidParameters();
        RuleFor(x => x.Input.Action).ValidAction();
        this.AddProfileAssociationRules(
            x => x.Input.AppliesToAllProfiles,
            x => x.Input.ProfileIds);
    }
}

internal sealed class CreateHotkeyCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock)
    : IUseCaseHandler<CreateHotkeyCommand, Result<HotkeyDto>>
{
    public async Task<Result<HotkeyDto>> ExecuteAsync(CreateHotkeyCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        CreateHotkeyDto input = request.Input;

        // Return value ignored: the validator rejects unknown keys before the handler runs,
        // so this always succeeds here.
        HotkeyKeys.TryCanonicalize(input.Key, out string canonicalKey);

        bool duplicate = await db.Hotkeys.AnyAsync(
            h => h.OwnerOid == ownerOid
              && h.Key == canonicalKey
              && h.Ctrl == input.Ctrl
              && h.Alt == input.Alt
              && h.Shift == input.Shift
              && h.Win == input.Win,
            ct);

        if (duplicate)
            return Result.Conflict("A hotkey with this key + modifier combination already exists.");

        Guid[] distinctProfileIds = input.ProfileIds?.Distinct().ToArray() ?? [];
        if (!input.AppliesToAllProfiles)
        {
            ValidationError? profileError = await OwnedIdsValidation.CheckOwnedIdsAsync(
                db.Profiles, p => p.OwnerOid == ownerOid && distinctProfileIds.Contains(p.Id),
                distinctProfileIds, "ProfileIds", ct);
            if (profileError is not null)
                return Result.Invalid(profileError);
        }

        Guid[] distinctCategoryIds = input.CategoryIds?.Distinct().ToArray() ?? [];
        ValidationError? categoryError = await OwnedIdsValidation.CheckOwnedIdsAsync(
            db.Categories, c => c.OwnerOid == ownerOid && distinctCategoryIds.Contains(c.Id),
            distinctCategoryIds, "CategoryIds", ct);
        if (categoryError is not null)
            return Result.Invalid(categoryError);

        var entity = Hotkey.Create(
            ownerOid,
            LegacyHotkeyDefinitionConverter.Apply(new HotkeyDefinition(
                Description: input.Description,
                Key: canonicalKey,
                Ctrl: input.Ctrl,
                Alt: input.Alt,
                Shift: input.Shift,
                Win: input.Win,
                Action: input.Action,
                Parameters: input.Parameters,
                AppliesToAllProfiles: input.AppliesToAllProfiles)),
            clock);

        db.Hotkeys.Add(entity);

        if (!input.AppliesToAllProfiles && distinctProfileIds.Length > 0)
        {
            foreach (Guid pid in distinctProfileIds)
                db.HotkeyProfiles.Add(HotkeyProfile.Create(entity.Id, pid));
        }

        foreach (Guid cid in distinctCategoryIds)
            db.HotkeyCategories.Add(HotkeyCategory.Create(entity.Id, cid));

        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException ex) when (ex.IsDuplicateKeyViolation())
        {
            return Result.Conflict("A hotkey with this key + modifier combination already exists.");
        }

        await db.Entry(entity).Collection(h => h.Profiles).LoadAsync(ct);
        await db.Entry(entity).Collection(h => h.Categories).LoadAsync(ct);
        return Result.Success(entity.ToDto());
    }
}
