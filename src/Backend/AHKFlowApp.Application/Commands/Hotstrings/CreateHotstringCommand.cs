using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Common;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Application.Validation;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using FluentValidation;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Hotstrings;

public sealed record CreateHotstringCommand(CreateHotstringDto Input);

public sealed class CreateHotstringCommandValidator : AbstractValidator<CreateHotstringCommand>
{
    public CreateHotstringCommandValidator()
    {
        RuleFor(x => x.Input.Trigger).ValidTrigger();
        RuleFor(x => x.Input.Replacement).ValidReplacement();
        RuleFor(x => x.Input.Description)
            .MaximumLength(HotstringRules.DescriptionMaxLength)
            .WithMessage($"Description must be {HotstringRules.DescriptionMaxLength} characters or fewer.");
        this.AddProfileAssociationRules(
            x => x.Input.AppliesToAllProfiles,
            x => x.Input.ProfileIds);
    }
}

internal sealed class CreateHotstringCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock)
    : IUseCaseHandler<CreateHotstringCommand, Result<HotstringDto>>
{
    public async Task<Result<HotstringDto>> ExecuteAsync(CreateHotstringCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        CreateHotstringDto input = request.Input;

        bool duplicate = await db.Hotstrings.AnyAsync(
            h => h.OwnerOid == ownerOid && h.Trigger == input.Trigger, ct);
        if (duplicate)
            return Result.Conflict("A hotstring with this trigger already exists.");

        Guid[] distinctProfileIds = input.ProfileIds?.Distinct().ToArray() ?? [];
        if (!input.AppliesToAllProfiles && distinctProfileIds.Length > 0)
        {
            int validCount = await db.Profiles
                .CountAsync(p => p.OwnerOid == ownerOid && distinctProfileIds.Contains(p.Id), ct);
            if (validCount != distinctProfileIds.Length)
                return Result.Invalid(new ValidationError
                {
                    Identifier = "Input.ProfileIds",
                    ErrorMessage = "One or more ProfileIds do not exist for this user.",
                });
        }

        string? description = string.IsNullOrWhiteSpace(input.Description) ? null : input.Description.Trim();

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

        var entity = Hotstring.Create(
            ownerOid,
            input.Trigger,
            input.Replacement,
            description,
            input.AppliesToAllProfiles,
            input.IsEndingCharacterRequired,
            input.IsTriggerInsideWord,
            clock);

        db.Hotstrings.Add(entity);

        if (!input.AppliesToAllProfiles && distinctProfileIds.Length > 0)
        {
            foreach (Guid pid in distinctProfileIds)
                db.HotstringProfiles.Add(HotstringProfile.Create(entity.Id, pid));
        }

        foreach (Guid cid in distinctCategoryIds)
            db.HotstringCategories.Add(HotstringCategory.Create(entity.Id, cid));

        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException ex) when (ex.IsDuplicateKeyViolation())
        {
            return Result.Conflict("A hotstring with this trigger already exists.");
        }

        await db.Entry(entity).Collection(h => h.Profiles).LoadAsync(ct);
        await db.Entry(entity).Collection(h => h.Categories).LoadAsync(ct);
        return Result.Success(entity.ToDto());
    }
}
