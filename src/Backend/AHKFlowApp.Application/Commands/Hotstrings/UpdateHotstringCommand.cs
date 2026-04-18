using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
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
        RuleFor(x => x.Input.Trigger)
            .NotEmpty()
            .MaximumLength(50);

        RuleFor(x => x.Input.Replacement)
            .NotEmpty()
            .MaximumLength(4000);
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
            .FirstOrDefaultAsync(h => h.Id == request.Id && h.OwnerOid == ownerOid, ct);

        if (entity is null)
            return Result.NotFound();

        UpdateHotstringDto input = request.Input;
        entity.Update(
            input.Trigger,
            input.Replacement,
            input.ProfileId,
            input.IsEndingCharacterRequired,
            input.IsTriggerInsideWord,
            clock);

        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException ex) when (IsDuplicateKeyViolation(ex))
        {
            return Result.Conflict("A hotstring with this trigger already exists for the specified profile.");
        }

        return Result.Success(entity.ToDto());
    }

    private static bool IsDuplicateKeyViolation(DbUpdateException ex) =>
        ex.InnerException?.GetType().GetProperty("Number")?.GetValue(ex.InnerException) is int n &&
        n is 2601 or 2627;
}
