using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Application.Validation;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using FluentValidation;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Hotkeys;

public sealed record UpdateHotkeyCommand(Guid Id, UpdateHotkeyDto Input) : IRequest<Result<HotkeyDto>>;

public sealed class UpdateHotkeyCommandValidator : AbstractValidator<UpdateHotkeyCommand>
{
    public UpdateHotkeyCommandValidator()
    {
        RuleFor(x => x.Input.Trigger).ValidHotkeyTrigger();
        RuleFor(x => x.Input.Action).ValidAction();
        RuleFor(x => x.Input.Description!).ValidOptionalDescription();
        RuleFor(x => x.Input.ProfileId).ValidOptionalProfileId();
    }
}

internal sealed class UpdateHotkeyCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock)
    : IRequestHandler<UpdateHotkeyCommand, Result<HotkeyDto>>
{
    public async Task<Result<HotkeyDto>> Handle(UpdateHotkeyCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        Hotkey? entity = await db.Hotkeys
            .FirstOrDefaultAsync(h => h.Id == request.Id && h.OwnerOid == ownerOid, ct);

        if (entity is null)
            return Result.NotFound();

        UpdateHotkeyDto input = request.Input;
        entity.Update(
            input.Trigger,
            input.Action,
            input.Description,
            input.ProfileId,
            clock);

        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException ex) when (IsDuplicateKeyViolation(ex))
        {
            return Result.Conflict("A hotkey with this trigger already exists for the specified profile.");
        }

        return Result.Success(entity.ToDto());
    }

    private static bool IsDuplicateKeyViolation(DbUpdateException ex) =>
        ex.InnerException?.GetType().GetProperty("Number")?.GetValue(ex.InnerException) is int n &&
        n is 2601 or 2627;
}
