using System.Diagnostics.CodeAnalysis;
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Application.Validation;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using FluentValidation;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Hotstrings;

public sealed record UpdateHotstringCommand(Guid Id, UpdateHotstringDto Input) : IRequest<Result<HotstringDto>>;

public sealed class UpdateHotstringCommandValidator : AbstractValidator<UpdateHotstringCommand>
{
    public UpdateHotstringCommandValidator()
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

internal sealed class UpdateHotstringCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock)
    : IRequestHandler<UpdateHotstringCommand, Result<HotstringDto>>
{
    public async Task<Result<HotstringDto>> Handle(UpdateHotstringCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        Hotstring? entity = await db.Hotstrings
            .Include(h => h.Profiles)
            .Include(h => h.Categories)
            .FirstOrDefaultAsync(h => h.Id == request.Id && h.OwnerOid == ownerOid, ct);

        if (entity is null)
            return Result.NotFound();

        UpdateHotstringDto input = request.Input;

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

        entity.Update(
            input.Trigger,
            input.Replacement,
            description,
            input.AppliesToAllProfiles,
            input.IsEndingCharacterRequired,
            input.IsTriggerInsideWord,
            clock);

        // Replace junction rows
        db.HotstringProfiles.RemoveRange(entity.Profiles);
        entity.Profiles.Clear();

        if (!input.AppliesToAllProfiles && distinctProfileIds.Length > 0)
        {
            foreach (Guid pid in distinctProfileIds)
            {
                var junction = HotstringProfile.Create(entity.Id, pid);
                db.HotstringProfiles.Add(junction);
                entity.Profiles.Add(junction);
            }
        }

        db.HotstringCategories.RemoveRange(entity.Categories);
        entity.Categories.Clear();

        foreach (Guid cid in distinctCategoryIds)
            db.HotstringCategories.Add(HotstringCategory.Create(entity.Id, cid));

        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException ex) when (IsDuplicateKeyViolation(ex))
        {
            return Result.Conflict("A hotstring with this trigger already exists.");
        }

        return Result.Success(entity.ToDto());
    }

    [ExcludeFromCodeCoverage]
    private static bool IsDuplicateKeyViolation(DbUpdateException ex) =>
        ex.InnerException?.GetType().GetProperty("Number")?.GetValue(ex.InnerException) is int n &&
        n is 2601 or 2627;
}
