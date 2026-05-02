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

public sealed record CreateHotstringCommand(CreateHotstringDto Input) : IRequest<Result<HotstringDto>>;

public sealed class CreateHotstringCommandValidator : AbstractValidator<CreateHotstringCommand>
{
    public CreateHotstringCommandValidator()
    {
        RuleFor(x => x.Input.Trigger).ValidTrigger();
        RuleFor(x => x.Input.Replacement).ValidReplacement();
        this.AddProfileAssociationRules(
            x => x.Input.AppliesToAllProfiles,
            x => x.Input.ProfileIds);
    }
}

internal sealed class CreateHotstringCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock)
    : IRequestHandler<CreateHotstringCommand, Result<HotstringDto>>
{
    public async Task<Result<HotstringDto>> Handle(CreateHotstringCommand request, CancellationToken ct)
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

        var entity = Hotstring.Create(
            ownerOid,
            input.Trigger,
            input.Replacement,
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

        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException ex) when (IsDuplicateKeyViolation(ex))
        {
            return Result.Conflict("A hotstring with this trigger already exists.");
        }

        // Reload profiles so ToDto() has the junction rows that were just inserted
        List<HotstringProfile> profiles = await db.HotstringProfiles
            .Where(p => p.HotstringId == entity.Id)
            .ToListAsync(ct);
        foreach (HotstringProfile p in profiles)
            entity.Profiles.Add(p);

        return Result.Success(entity.ToDto());
    }

    // Checks SQL Server unique-constraint error codes (2601/2627) without importing Microsoft.Data.SqlClient,
    // which would couple the Application layer to an infrastructure concern.
    [ExcludeFromCodeCoverage]
    private static bool IsDuplicateKeyViolation(DbUpdateException ex) =>
        ex.InnerException?.GetType().GetProperty("Number")?.GetValue(ex.InnerException) is int n &&
        n is 2601 or 2627;
}
