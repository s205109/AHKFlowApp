using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
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
        RuleFor(x => x.Input.Trigger)
            .NotEmpty()
            .MaximumLength(50);

        RuleFor(x => x.Input.Replacement)
            .NotEmpty()
            .MaximumLength(4000);
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
            h => h.OwnerOid == ownerOid
              && h.ProfileId == input.ProfileId
              && h.Trigger == input.Trigger,
            ct);

        if (duplicate)
            return Result.Conflict("A hotstring with this trigger already exists for the specified profile.");

        var entity = Hotstring.Create(
            ownerOid,
            input.Trigger,
            input.Replacement,
            input.ProfileId,
            input.IsEndingCharacterRequired,
            input.IsTriggerInsideWord,
            clock);

        db.Hotstrings.Add(entity);

        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException)
        {
            return Result.Conflict("A hotstring with this trigger already exists for the specified profile.");
        }

        return Result.Success(entity.ToDto());
    }
}
