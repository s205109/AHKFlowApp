using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Common;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Application.Validation;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using Ardalis.Result;
using FluentValidation;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Hotkeys;

public sealed record UpdateHotkeyCommand(Guid Id, UpdateHotkeyDto Input);

public sealed class UpdateHotkeyCommandValidator : AbstractValidator<UpdateHotkeyCommand>
{
    public UpdateHotkeyCommandValidator()
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

internal sealed class UpdateHotkeyCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock,
    IEntityHistoryRecorder recorder)
    : IUseCaseHandler<UpdateHotkeyCommand, Result<HotkeyDto>>
{
    public async Task<Result<HotkeyDto>> ExecuteAsync(UpdateHotkeyCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        Hotkey? entity = await db.Hotkeys
            .Include(h => h.Profiles)
            .Include(h => h.Categories)
            .FirstOrDefaultAsync(h => h.Id == request.Id && h.OwnerOid == ownerOid, ct);

        if (entity is null)
            return Result.NotFound();

        UpdateHotkeyDto input = request.Input;

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

        EntityHistory historyEntry = await recorder.RecordHotkeyAsync(entity, HistoryChangeType.Edit, ct);

        entity.Update(
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

        // Replace junction rows
        db.HotkeyProfiles.RemoveRange(entity.Profiles);
        entity.Profiles.Clear();

        if (!input.AppliesToAllProfiles && input.ProfileIds is { Length: > 0 })
        {
            foreach (Guid pid in input.ProfileIds)
            {
                var junction = HotkeyProfile.Create(entity.Id, pid);
                db.HotkeyProfiles.Add(junction);
                entity.Profiles.Add(junction);
            }
        }

        db.HotkeyCategories.RemoveRange(entity.Categories);
        entity.Categories.Clear();

        foreach (Guid cid in distinctCategoryIds)
            db.HotkeyCategories.Add(HotkeyCategory.Create(entity.Id, cid));

        try
        {
            await db.SaveWithHistoryRetryAsync(historyEntry, ct);
        }
        catch (DbUpdateException ex) when (ex.IsDuplicateKeyViolation())
        {
            return ex.IsHistoryVersionConflict()
                ? Result.Conflict("The item was modified concurrently. Retry the operation.")
                : Result.Conflict("A hotkey with this key + modifier combination already exists.");
        }

        return Result.Success(entity.ToDto());
    }
}
