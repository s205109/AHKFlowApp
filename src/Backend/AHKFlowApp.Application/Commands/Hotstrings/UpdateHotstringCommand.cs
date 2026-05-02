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

        entity.Update(
            input.Trigger,
            input.Replacement,
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
