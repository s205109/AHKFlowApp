using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Common;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
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

        bool duplicate = await db.Hotkeys.AnyAsync(
            h => h.OwnerOid == ownerOid
              && h.Key == input.Key
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
            new HotkeyDefinition(
                input.Description,
                input.Key,
                input.Ctrl,
                input.Alt,
                input.Shift,
                input.Win,
                input.Action,
                input.Parameters,
                input.AppliesToAllProfiles),
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
