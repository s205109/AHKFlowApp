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

        if (!input.AppliesToAllProfiles && input.ProfileIds is { Length: > 0 })
        {
            int validCount = await db.Profiles
                .CountAsync(p => p.OwnerOid == ownerOid && input.ProfileIds.Contains(p.Id), ct);
            if (validCount != input.ProfileIds.Length)
                return Result.Invalid(new ValidationError
                {
                    Identifier = "Input.ProfileIds",
                    ErrorMessage = "One or more ProfileIds do not exist for this user.",
                });
        }

        Guid[] distinctCategoryIds = input.CategoryIds?.Distinct().ToArray() ?? [];
        if (distinctCategoryIds.Length > 0)
        {
            int validCount = await db.Categories
                .CountAsync(c => c.OwnerOid == ownerOid && distinctCategoryIds.Contains(c.Id), ct);
            if (validCount != distinctCategoryIds.Length)
                return Result.Invalid(new ValidationError
                {
                    Identifier = "Input.CategoryIds",
                    ErrorMessage = "One or more CategoryIds do not exist for this user.",
                });
        }

        var entity = Hotkey.Create(
            ownerOid,
            input.Description,
            input.Key,
            input.Ctrl,
            input.Alt,
            input.Shift,
            input.Win,
            input.Action,
            input.Parameters,
            input.AppliesToAllProfiles,
            clock);

        db.Hotkeys.Add(entity);

        if (!input.AppliesToAllProfiles && input.ProfileIds is { Length: > 0 })
        {
            foreach (Guid pid in input.ProfileIds)
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
